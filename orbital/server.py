"""API HTTP + interfaz web de Orbital.

Aquí se arma la app: seguridad (solo local, o con token), arranque y las rutas de `orbital.api`,
una pieza por área. La app pública (Alexa por el túnel) solo expone voz y ping.
"""

from __future__ import annotations

import asyncio
import contextlib
import hmac
import ipaddress
import logging
import os
import threading
import time
from contextlib import asynccontextmanager
from pathlib import Path
from urllib.parse import urlsplit

from fastapi import FastAPI, Request
from fastapi.concurrency import run_in_threadpool
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles

from . import __version__
from .api import diagnostics, library, live, media, play, quick, ui, update
from .api.deps import Deps
from .api.live import SseHub, VoiceRequest
from .api.play import humane_error  # noqa: F401 - se importa desde aquí
from .api.ui import SETTINGS  # noqa: F401
from .catalog import Catalog
from .config import Config
from .shell import ConsoleShell
from .voice import VoiceController

log = logging.getLogger(__name__)
WEB_DIR = Path(__file__).parent / "web"
_FORWARD_HEADERS = ("x-forwarded-for", "forwarded", "cf-connecting-ip", "x-real-ip")
EventBus = SseHub  # nombre anterior


_LOCAL_HOSTNAMES = {"127.0.0.1", "localhost", "::1"}


def is_local_request(request: Request) -> bool:
    """Local = viene del propio equipo, NO atravesó un proxy/túnel y va dirigida a localhost.

    Comprobar el Host importa: un túnel como Tailscale Funnel entrega las peticiones desde
    127.0.0.1 y sin garantía de cabeceras de reenvío, pero con Host "tu-equipo.ts.net".
    También evita ataques de DNS rebinding desde páginas web.
    """
    if any(h in request.headers for h in _FORWARD_HEADERS):
        return False
    try:
        hostname = urlsplit("//" + request.headers.get("host", "")).hostname or ""
    except ValueError:
        return False
    if hostname not in _LOCAL_HOSTNAMES:
        return False
    client = request.client.host if request.client else ""
    try:
        return ipaddress.ip_address(client).is_loopback
    except ValueError:
        return False


def token_ok(request: Request, expected: str) -> bool:
    header = request.headers.get("authorization", "").strip()
    # «Bearer», «bearer» o «BEARER» (RFC 6750 no distingue mayúsculas).
    token = header[7:].strip() if header[:7].lower() == "bearer " else header
    if not token or not expected:
        return False
    # En bytes: compare_digest con texto no ASCII lanzaba TypeError (500). Las cabeceras llegan como
    # latin-1: así se recuperan los bytes UTF-8 que mandó el cliente.
    try:
        sent = token.encode("latin-1")
    except UnicodeEncodeError:
        sent = token.encode("utf-8", "surrogatepass")
    return hmac.compare_digest(sent, expected.encode("utf-8", "surrogatepass"))


def paused_path() -> Path:
    """Qué quedó congelado (para descongelarlo si Orbital se cierra de golpe)."""
    return Path(os.environ.get("LOCALAPPDATA") or Path.home() / ".local" / "state") / "orbital" / "paused.json"


def create_app(config: Config, catalog: Catalog | None = None, kiosk=None, shortcuts: bool = False,
               log_path: Path | None = None, updater=None) -> FastAPI:
    """`shortcuts`: activa los atajos globales del mando (Home, Select+Start, Legion L)."""
    catalog = catalog or Catalog(config)
    if kiosk is not None:
        catalog.kiosk = kiosk
    shell = ConsoleShell(catalog, kiosk, pause_file=paused_path() if shortcuts else None)
    catalog.before_launch = shell.close_previous  # abrir algo nuevo cierra lo anterior (no queda olvidado)
    d = Deps(config=config, catalog=catalog, shell=shell, voice=VoiceController(catalog, kiosk), hub=SseHub(),
             kiosk=kiosk, log_path=log_path, started=time.time())

    @asynccontextmanager
    async def lifespan(_: FastAPI):
        d.hub.loop = asyncio.get_running_loop()
        unsubscribe = catalog.events.subscribe(d.hub.publish_threadsafe)
        if shortcuts:
            # De verdad (no en pruebas): la interfaz abre ya, con su animación de arranque, mientras
            # se escanea la biblioteca; al terminar avisa (library-changed). Antes no se veía nada
            # hasta que acababa el escaneo de Steam, emuladores y Stremio.
            def scan() -> None:
                try:
                    catalog.refresh()
                finally:
                    catalog.scanning = False
                    d.hub.publish_threadsafe({"type": "library-changed"})
                shell.start()

            # Con la biblioteca del último arranque, la interfaz entra ya; si no, espera el escaneo.
            catalog.scanning = not catalog.load_snapshot()  # antes de que la interfaz pregunte
            threading.Thread(target=scan, daemon=True, name="first-scan").start()
        else:
            await run_in_threadpool(catalog.refresh)
        status = asyncio.create_task(live.watch_status(d))
        problems = live.ProblemNotifier(d.hub.publish_threadsafe) if shortcuts else None
        if problems:
            logging.getLogger("orbital").addHandler(problems)
        yield
        # Orbital se cierra con un video abierto: se cierra bien (lo visto se guarda) y no queda un mpv
        # huérfano con la tubería ocupada para el siguiente.
        player = getattr(catalog, "player", None)
        if player is not None and getattr(player, "playing", False):
            with contextlib.suppress(Exception):
                await run_in_threadpool(player.stop)
        if problems:
            logging.getLogger("orbital").removeHandler(problems)
        status.cancel()
        with contextlib.suppress(asyncio.CancelledError):
            await status
        unsubscribe()

    app = FastAPI(title="Orbital", version=__version__, lifespan=lifespan, docs_url=None, redoc_url=None, openapi_url=None)
    app.add_exception_handler(RequestValidationError, invalid_request)  # type: ignore[arg-type]
    app.state.deps = d
    app.state.catalog = catalog
    app.state.bus = d.hub
    app.state.shell = shell

    @app.middleware("http")
    async def security(request: Request, call_next):
        # Bloquea páginas web ajenas que intenten lanzar cosas contra localhost.
        origin = request.headers.get("origin")
        if origin and origin.rstrip("/") != f"{request.url.scheme}://{request.url.netloc}":
            return JSONResponse({"detail": "Origen no permitido"}, status_code=403)
        if not is_local_request(request) and not token_ok(request, config.server.token):
            return JSONResponse({"detail": "Token inválido"}, status_code=401)
        return await call_next(request)

    for part in (library.router(d), play.router(d), media.router(d), ui.router(d),
                 live.router(d, is_local_request), diagnostics.router(d), quick.router(d),
                 update.router(d, updater)):
        app.include_router(part)
    app.state.run_voice = d.extra["run_voice"]
    app.mount("/", WebFiles(directory=WEB_DIR, html=True), name="web")
    return app


class WebFiles(StaticFiles):
    """La interfaz siempre se revalida (ETag): tras actualizar Orbital, Edge no mezcla CSS o JS viejos."""

    def file_response(self, *args, **kwargs):
        response = super().file_response(*args, **kwargs)
        response.headers["Cache-Control"] = "no-cache"
        return response


class FailedTokens:
    """Frena a quien prueba tokens por el túnel: tras varios intentos fallidos desde el mismo lugar,
    cada respuesta tarda más y, si sigue, se le bloquea un rato. Lo que entra por el túnel suele
    venir de 127.0.0.1, así que también cuenta la cabecera X-Forwarded-For si existe."""

    WINDOW = 300.0  # s que se recuerda un intento fallido
    SLOW_AFTER = 5  # fallos: a partir de aquí cada respuesta tarda más (hasta MAX_DELAY)
    BLOCK_AFTER = 30  # fallos en WINDOW: bloqueo
    BLOCK_FOR = 900.0
    MAX_DELAY = 5.0

    def __init__(self, clock=time.monotonic) -> None:
        self.clock = clock
        self._fails: dict[str, list[float]] = {}
        self._blocked: dict[str, float] = {}
        self._all: list[float] = []  # todos los fallos: quien inventa una X-Forwarded-For por intento igual se frena

    @staticmethod
    def key(request: Request) -> str:
        # El último valor es el que puso el túnel (el de confianza); los anteriores los escribe quien llama.
        forwarded = request.headers.get("x-forwarded-for", "").split(",")[-1].strip()
        return forwarded or (request.client.host if request.client else "?")

    def blocked(self, key: str) -> bool:
        until = self._blocked.get(key)
        if until and self.clock() < until:
            return True
        self._blocked.pop(key, None)
        return False

    def failed(self, key: str) -> float:
        """Anota un fallo; devuelve cuántos segundos esperar antes de responder."""
        now = self.clock()
        if len(self._fails) > 500:  # quien rota cabeceras no hace crecer esto sin tope
            self._fails = {k: v for k, v in self._fails.items() if v and now - v[-1] < self.WINDOW}
            if len(self._fails) > 500:  # aún muchos recientes: se quedan los 250 más nuevos
                self._fails = dict(sorted(self._fails.items(), key=lambda kv: kv[1][-1])[-250:])
        self._all = [t for t in self._all[-999:] if now - t < self.WINDOW] + [now]
        recent = [t for t in self._fails.get(key, []) if now - t < self.WINDOW] + [now]
        self._fails[key] = recent
        if len(recent) >= self.BLOCK_AFTER:
            self._blocked[key] = now + self.BLOCK_FOR
            log.warning("Demasiados tokens inválidos desde %s: bloqueado %d min", key, self.BLOCK_FOR // 60)
        # La espera crece por origen y también por el total (sin bloquear a todos: Alexa sigue respondiendo).
        mine = max(0, len(recent) - self.SLOW_AFTER) * 0.5
        overall = max(0, len(self._all) - self.SLOW_AFTER * 4) * 0.1
        return min(self.MAX_DELAY, max(mine, overall))

    def succeeded(self, key: str) -> None:
        self._fails.pop(key, None)


async def invalid_request(request: Request, exc: RequestValidationError) -> JSONResponse:
    """422 sin repetir lo que llegó: un NaN o un sustituto Unicode suelto en el cuerpo no se puede volver a escribir
    como JSON y el 422 de FastAPI terminaba en 500."""
    errors = [{"loc": [str(p) for p in e.get("loc", ())], "msg": str(e.get("msg", "")), "type": str(e.get("type", ""))}
              for e in exc.errors()]
    return JSONResponse({"detail": errors}, status_code=422)


MAX_PUBLIC_BODY = 16 * 1024


def create_public_app(config: Config, main_app: FastAPI, guard: FailedTokens | None = None) -> FastAPI:
    """App mínima para internet (Alexa a través del túnel): solo voz y ping, siempre con token.

    Corre en otro puerto (server.public_port). Aunque el túnel entregue las peticiones desde
    127.0.0.1, aquí no hay excepciones para "local": sin token no se hace nada.
    """
    public = FastAPI(title="Orbital · Alexa", docs_url=None, redoc_url=None, openapi_url=None)
    public.add_exception_handler(RequestValidationError, invalid_request)  # type: ignore[arg-type]

    guard = guard or FailedTokens()
    one_at_a_time: list[asyncio.Lock] = []  # los intentos fallidos esperan en fila, no en paralelo
    waiting = [0]
    MAX_WAITING = 20  # más que esto en fila: 429 al instante (no se acumulan conexiones abiertas)

    @public.middleware("http")
    async def require_token(request: Request, call_next):
        # Un comando de voz cabe en unos cientos de bytes: 5 MB de texto ocupaban el servidor segundos.
        try:
            size = int(request.headers.get("content-length") or 0)
        except ValueError:
            size = MAX_PUBLIC_BODY + 1
        if size > MAX_PUBLIC_BODY:
            return JSONResponse({"detail": "Petición demasiado grande"}, status_code=413)
        key = FailedTokens.key(request)
        # El token correcto pasa siempre: quien falsifica tu dirección no te deja fuera.
        if token_ok(request, config.server.token):
            guard.succeeded(key)
            return await call_next(request)
        if guard.blocked(key):
            return JSONResponse({"detail": "Demasiados intentos"}, status_code=429)
        if waiting[0] >= MAX_WAITING:
            guard.failed(key)
            return JSONResponse({"detail": "Demasiados intentos"}, status_code=429)
        if not one_at_a_time:
            one_at_a_time.append(asyncio.Lock())
        waiting[0] += 1
        try:
            async with one_at_a_time[0]:  # 600 intentos a la vez ya no esperan 5 s en total, sino uno tras otro
                if guard.blocked(key):  # se bloqueó mientras esperaba en la fila
                    return JSONResponse({"detail": "Demasiados intentos"}, status_code=429)
                await asyncio.sleep(guard.failed(key))
        finally:
            waiting[0] -= 1
        return JSONResponse({"detail": "Token inválido"}, status_code=401)

    @public.api_route("/api/ping", methods=["GET", "HEAD"])  # HEAD: los monitores de disponibilidad
    def ping() -> dict:
        return {"ok": True, "service": "orbital", "version": __version__}

    @public.post("/api/voice")
    async def voice_command(body: VoiceRequest) -> dict:
        return await main_app.state.run_voice(body, remote=True)

    return public
