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
import re
import threading
import time
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Any
from urllib.parse import urlsplit

from fastapi import FastAPI, HTTPException, Request
from fastapi.concurrency import run_in_threadpool
from fastapi.exceptions import RequestValidationError
from fastapi.responses import FileResponse, HTMLResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field

from . import __version__, companion
from . import quick as system_audio
from .api import diagnostics, downloads, foryou, library, live, media, onedrive, play, quick, tv, ui, update
from .api.deps import Deps
from .api.live import SseHub, VoiceRequest
from .api.play import humane_error  # noqa: F401 - se importa desde aquí
from .api.ui import SETTINGS  # noqa: F401
from .catalog import Catalog
from .config import Config
from .foryou import SERVICE_ERRORS, TV_ONLY_PREFIXES
from .library import trakt
from .library_watch import LibraryWatcher
from .remote_input import RemoteInput
from .roku import RokuTv
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


STORE_DELAY = 90  # s tras el primer escaneo antes de pedir fichas a la tienda de Steam (que el arranque termine primero)


def paused_path() -> Path:
    """Qué quedó congelado (para descongelarlo si Orbital se cierra de golpe)."""
    return Path(os.environ.get("LOCALAPPDATA") or Path.home() / ".local" / "state") / "orbital" / "paused.json"




def emulator_updates_for(d: Deps):
    """Las actualizaciones de los emuladores que tienes (ver emulator_updates.py)."""
    from . import emulator_updates
    from .library import emulators as emulator_lib

    def exes() -> list[Path]:
        found = (emulator_lib.resolve_executable(e) for e in d.catalog.emulators)
        return [emulator_updates.real_exe(p) for p in found if p is not None]

    return emulator_updates.EmulatorUpdates(
        exes, mode=lambda: d.catalog.state.settings().get("emulator_updates", "avisar"),
        busy=lambda: d.catalog.launcher.status() is not None,
        notify=lambda text: d.hub.publish_threadsafe({"type": "toast", "message": text}))


def create_app(config: Config, catalog: Catalog | None = None, kiosk=None, shortcuts: bool = False,
               log_path: Path | None = None, updater=None) -> FastAPI:
    """`shortcuts`: activa los atajos globales del mando (Home, Select+Start, Legion L)."""
    catalog = catalog or Catalog(config)
    if kiosk is not None:
        catalog.kiosk = kiosk
    shell = ConsoleShell(catalog, kiosk, pause_file=paused_path() if shortcuts else None)
    catalog.before_launch = shell.close_previous  # abrir algo nuevo cierra lo anterior (no queda olvidado)
    d = Deps(config=config, catalog=catalog, shell=shell, voice=VoiceController(catalog, kiosk, RokuTv(config.tv)), hub=SseHub(),
             kiosk=kiosk, log_path=log_path, started=time.time())

    d.extra["emulator_updates"] = emulator_updates_for(d)

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
                # Juegos nuevos con Orbital abierto: vigila las carpetas de juegos (antes solo se buscaba al arrancar).
                catalog.library_watch = LibraryWatcher(catalog.watched_folders, catalog.rescan_for_new)
                catalog.library_watch.start()
                try:  # de qué trata cada juego de Steam y GeForce NOW: con calma, después de todo lo demás
                    time.sleep(STORE_DELAY)
                    catalog.warm_store()
                except Exception:  # noqa: BLE001 - la tienda nunca tumba a Orbital
                    logging.getLogger(__name__).exception("Fichas de la tienda de Steam")

            # Con la biblioteca del último arranque, la interfaz entra ya; si no, espera el escaneo.
            catalog.scanning = not catalog.load_snapshot()  # antes de que la interfaz pregunte
            catalog.tv.start()  # revisa los canales de TV con calma (y cada ~6 h)
            catalog.foryou.warm()  # Para ti listo antes de que la TV o el iPhone lo pidan
            d.extra["emulator_updates"].start()  # versiones nuevas de los emuladores: avisa o instala (según Ajustes)
            # Un solo volumen: el reproductor mueve el de Windows (el de Ajustes rápidos y Alexa). Solo aquí, en la Orbital de
            # verdad: en pruebas movería el volumen real de la computadora.
            catalog.watch.player.system_volume = (system_audio.volume, system_audio.set_volume)
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
        catalog.tv.stop()
        if catalog.library_watch is not None:
            catalog.library_watch.stop()
        d.extra["emulator_updates"].stop()
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
    app.state.remote_input = RemoteInput(publish=catalog.events.publish)
    app.state.ui_state = d.extra.setdefault("ui_state", {"screen": "home", "text_field": False})  # lo cuenta la interfaz (POST /api/ui/state)

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
                 update.router(d, updater), foryou.router(d), tv.router(d), onedrive.router(d), downloads.router(d)):
        app.include_router(part)
    _companion_routes(app, config)
    _remote_input_routes(app, config)
    app.state.run_voice = d.extra["run_voice"]
    app.state.play_stremio = d.extra["play_stremio"]
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


class CompanionPlayerAction(BaseModel):
    action: str
    delta: float | None = None  # "skip": segundos (±10, ±30); "volume": cuánto sube o baja (±5)
    level: int | None = None  # "volume": el nivel exacto (0-100)
    track: int | str | None = None  # "subtitles" / "audio": el id de playing.tracks ("no": sin subtítulos)


class CompanionGame(BaseModel):
    action: str  # "resume" | "home" | "close"


class CompanionConsole(BaseModel):
    power_mode: str | None = None  # "efficiency" | "balanced" | "performance"
    close_app: str | None = Field(None, max_length=80)  # el nombre de la lista de memoria («Chrome»)


class CompanionInput(BaseModel):
    action: str  # up, down, left, right, select, back, home, menu, search, options, pageleft, pageright


class CompanionText(BaseModel):
    text: str
    submit: bool = False
    replace: bool = False  # el texto reemplaza todo el campo (si no, se agrega)


class CompanionSend(BaseModel):
    action: str  # "open" (abrirlo en el iPhone) | "download" (descargarlo en el iPhone)
    kind: str  # "movie" | "series"
    meta_id: str
    video_id: str | None = None  # el episodio (si falta, el que sigue)


MEDIA_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9:_.\-]{0,79}$")  # tt0096697, kitsu:12, tmdb:…


class CompanionAck(BaseModel):
    ids: list[str] = []


class ChoiceChange(BaseModel):
    """Lo que el iPhone eligió para un título: solo los campos que cambió (None = olvidar) y la última revisión que vio."""
    audio: str | None = Field(None, max_length=3)
    spanish: str | None = Field(None, max_length=6)
    subtitles: str | None = Field(None, max_length=6)
    forget: list[str] = Field(default_factory=list, max_length=3)
    base_rev: int = Field(0, ge=0)


class ChoicesSync(BaseModel):
    since: int = Field(0, ge=0)
    changes: dict[str, ChoiceChange] = Field(default_factory=dict, max_length=100)


def _companion_routes(app: FastAPI, config: Config) -> None:
    """«Conectar iPhone» en la TV: el QR y «Enviar/Descargar en el iPhone» (solo en el puerto local, el de la consola)."""
    from fastapi.responses import Response

    @app.get("/api/companion/phone")
    def phone() -> dict:
        """¿Hay iPhone conectado? (la TV solo ofrece «Enviar al iPhone» si sí)."""
        return {"ready": companion.phone_ready(config)}

    @app.post("/api/companion/send")
    def send_to_phone(body: CompanionSend) -> dict:
        try:
            item = companion.send_to_phone(app.state.catalog.watch, config, body.action[:20], body.kind[:20], body.meta_id[:80],
                                           body.video_id[:120] if body.video_id else None)
        except companion.PhoneNotConnected as exc:
            raise HTTPException(409, str(exc))
        except ValueError as exc:
            raise HTTPException(409, str(exc))
        return {"item": item, "message": companion.SENT_TOAST[item["action"]]}

    @app.get("/api/companion/pair")
    def pair() -> dict:
        info = companion.pair_info(config)
        info.pop("link", None)  # el token no viaja en el JSON: solo dentro del QR
        return info

    @app.get("/api/companion/pair.svg")
    def pair_svg() -> Response:
        info = companion.pair_info(config)
        if not info["ready"]:
            return Response(status_code=409)
        return Response(companion.qr_svg(info["link"]), media_type="image/svg+xml", headers={"Cache-Control": "no-store"})


def _remote_input_routes(app: FastAPI, config: Config) -> None:
    """Escribir desde el celular (remote_input.py): la TV pide un código, enseña su QR y recoge lo escrito. Solo local."""
    from fastapi import Body, HTTPException
    from fastapi.responses import Response

    remote: RemoteInput = app.state.remote_input
    urls: dict[str, str] = {}

    @app.post("/api/remote-input")
    def remote_start(title: str = Body(""), fields: list = Body(default_factory=list)) -> dict:
        info = companion.pair_info(config)  # el celular entra por el mismo túnel que Alexa y el iPhone
        if not info["ready"]:
            return {"ready": False, "reason": info.get("reason", "")}
        code = remote.start(title, fields)
        if code is None:
            raise HTTPException(422, "Formulario sin campos")
        urls.clear()
        urls[code] = f"https://{info['host']}/escribir/{code}"
        return {"ready": True, "code": code, "host": info["host"]}

    @app.get("/api/remote-input/qr.svg")
    def remote_qr(code: str = "") -> Response:
        if remote.form(code) is None or code not in urls:
            return Response(status_code=404)
        return Response(companion.qr_svg(urls[code]), media_type="image/svg+xml", headers={"Cache-Control": "no-store"})

    @app.get("/api/remote-input/take")
    def remote_take(code: str = "") -> Response:
        values = remote.take(code)
        if values is None:
            return Response(status_code=204)
        urls.pop(code, None)
        return JSONResponse({"values": values}, headers={"Cache-Control": "no-store"})

    @app.post("/api/remote-input/cancel")
    def remote_cancel(code: str = Body("", embed=True)) -> dict:
        remote.cancel(code or None)
        urls.pop(code, None)
        return {"ok": True}


REMOTE_PAGE = Path(__file__).with_name("remote_input_page.html")
# La página del celular no carga nada de fuera ni se deja incrustar; sin «Referer» (la dirección lleva el código).
REMOTE_HEADERS = {"Cache-Control": "no-store", "Referrer-Policy": "no-referrer", "X-Frame-Options": "DENY",
                  "Content-Security-Policy": "default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; "
                                             "connect-src 'self'; form-action 'self'; frame-ancestors 'none'; base-uri 'none'"}


def remote_page(form: dict | None) -> str:
    import json
    data = json.dumps(form, ensure_ascii=False).replace("<", "\\u003c")  # que un nombre no cierre el <script>
    return REMOTE_PAGE.read_text(encoding="utf-8").replace("/*FORM*/null", data, 1)


MAX_PUBLIC_BODY = 16 * 1024


def create_public_app(config: Config, main_app: FastAPI, guard: FailedTokens | None = None) -> FastAPI:
    """App mínima para internet (Alexa y el iPhone a través del túnel): voz, ping, «Ver en la TV» y las claves de «Para ti» para la app del iPhone, siempre con token.

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
        if not request.headers.get("content-length") and "chunked" in request.headers.get("transfer-encoding", "").lower():
            size = MAX_PUBLIC_BODY + 1  # sin tamaño declarado no se puede medir antes de leerlo todo
        if size > MAX_PUBLIC_BODY:
            return JSONResponse({"detail": "Petición demasiado grande"}, status_code=413)
        key = FailedTokens.key(request)
        if request.url.path.startswith("/escribir/"):
            code = request.url.path.split("/", 2)[2].strip("/")
            if guard.blocked(key):
                return JSONResponse({"detail": "Demasiados intentos"}, status_code=429)
            if main_app.state.remote_input.form(code) is not None:
                return await call_next(request)
            await asyncio.sleep(guard.failed(key))
            if request.method == "GET":
                return HTMLResponse(remote_page(None), status_code=404, headers=REMOTE_HEADERS)
            return JSONResponse({"detail": "Este código ya no sirve. Vuelve a abrir el formulario en la tele."}, status_code=404)
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

    def saw_phone() -> None:
        """Para Ajustes › Cuentas («Conectado · Lo usaste hace 2 h»): una escritura cada 10 min como mucho."""
        state = getattr(main_app.state.catalog, "state", None)
        if state is not None and time.time() - float(state.settings().get("companion_seen") or 0) > 600:
            state.set_setting("companion_seen", time.time())

    @public.get("/api/companion")
    def companion_keys() -> dict:
        """La app del iPhone toma de aquí lo de «Para ti» para no escribirlo dos veces: la clave de TMDB, la aplicación
        de Trakt (su Client ID, que no es secreto; el secreto no sale de aquí) y el país."""
        p = config.para_ti
        saw_phone()  # Ajustes › Cuentas: el iPhone está conectado (antes decía siempre «Conectar»)
        foryou = getattr(main_app.state.catalog, "foryou", None)
        key = foryou.key if foryou else (lambda name: getattr(p, name))  # las escritas en la TV, o las de config.yaml
        return {"tmdb_key": key("tmdb_key"), "trakt_client_id": key("trakt_client_id"), "region": p.region,
                "trakt_session": companion.trakt_session(getattr(foryou, "trakt", None))}

    @public.get("/escribir/{code}")
    def remote_form(code: str) -> HTMLResponse:
        """La página del celular para escribir en la tele (correo, contraseña, una clave)."""
        return HTMLResponse(remote_page(main_app.state.remote_input.form(code)), headers=REMOTE_HEADERS)

    @public.post("/escribir/{code}")
    async def remote_send(code: str, request: Request) -> JSONResponse:
        try:
            body = await request.json()
        except ValueError:
            body = {}
        problem = main_app.state.remote_input.submit(code, body.get("values") if isinstance(body, dict) else None)
        if problem:
            return JSONResponse({"detail": problem}, status_code=400)
        return JSONResponse({"ok": True})

    @public.post("/api/stremio/play")
    def play_on_tv(body: media.PlayRequest) -> dict:
        """«Ver en la TV» desde el iPhone: lo mismo que la tarjeta de la TV (la fuente recomendada, donde ibas).
        No da más de lo que ya da la voz («pon The Office»): solo poner un título de Stremio."""
        return main_app.state.play_stremio(body)

    _foryou_public_routes(public, main_app)

    @public.get("/api/companion/now")
    def companion_now() -> dict:
        """«Viendo en la TV» del iPhone: qué se ve ahora (o `null` si no hay nada abierto)."""
        # Lo que la TV le dejó al iPhone («Enviar» / «Descargar en el iPhone») viaja aquí: ni una petición de más.
        catalog = main_app.state.catalog
        saw_phone()  # lo que el iPhone pide cada 5 s abierto (antes solo contaba /api/companion, que pide al emparejarse)
        return {"playing": companion.now_playing(catalog), "inbox": companion.inbox_pending(catalog.state),
                "game": companion.game_now(catalog, main_app.state.shell),  # el modo acompañante (None sin juego)
                # qué pantalla y si hay un campo de texto (el iPhone enseña «Escribir»); con el reproductor al frente,
                # "player"/"live" y su leyenda
                "ui": companion.ui_state(catalog, main_app.state.shell, main_app.state.ui_state),
                "volume": _volume()}  # {"level", "muted"}: la barra de volumen del control del iPhone

    @public.get("/api/tv/logo")
    def companion_channel_logo(id: str) -> FileResponse:
        """El logo del canal que se ve (el iPhone lo pinta en «Viendo en la TV»)."""
        path = main_app.state.catalog.tv.logo_path(id[:200])
        if path is None:
            raise HTTPException(404, "Ese canal no tiene logo.")
        return FileResponse(path, headers={"Cache-Control": "public, max-age=86400"})

    @public.post("/api/companion/choices")
    def companion_choices(body: ChoicesSync) -> dict:
        """El audio, la variante y los subtítulos que eligió cada título, en la TV y en el iPhone: el iPhone manda lo que
        cambió y recibe lo que cambió aquí desde `since`. Si la TV lo cambió después de lo que el iPhone vio, gana la TV
        (`rejected`; su valor va en `changed`). No da más que eso: ni historial ni lo que se ve."""
        state = main_app.state.catalog.state
        rejected = []
        for meta_id, change in body.changes.items():
            if not MEDIA_ID.match(meta_id):
                continue
            fields = {k: getattr(change, k) for k in ("audio", "spanish", "subtitles") if getattr(change, k) is not None}
            fields.update({k: None for k in change.forget if k in ("audio", "spanish", "subtitles")})
            if not state.apply_choice(meta_id, fields, change.base_rev):
                rejected.append(meta_id)
        rev, changed = state.choices_since(body.since)
        for meta_id in rejected:  # lo que ganó la TV vuelve aunque sea viejo
            prefs = state.prefs(f"stremio:{meta_id}")
            changed[meta_id] = {**{k: prefs[k] for k in ("audio", "spanish", "subtitles") if isinstance(prefs.get(k), str)},
                                "rev": prefs.get("rev") or 0}
        return {"rev": rev, "changed": changed, "rejected": rejected}

    @public.post("/api/companion/inbox/ack")
    def companion_inbox_ack(body: CompanionAck) -> dict:
        """El iPhone ya actuó sobre estos pendientes: se quitan de la bandeja."""
        return {"removed": companion.inbox_ack(main_app.state.catalog.state, body.ids)}

    remote_bucket = {"tokens": 20.0, "at": time.monotonic()}  # el pad manda ~10 por segundo al mantener

    def remote_allowed() -> bool:
        now = time.monotonic()
        remote_bucket["tokens"] = min(20.0, remote_bucket["tokens"] + (now - remote_bucket["at"]) * 15)
        remote_bucket["at"] = now
        if remote_bucket["tokens"] < 1:
            return False
        remote_bucket["tokens"] -= 1
        return True

    @public.post("/api/companion/input")
    def companion_input(body: CompanionInput) -> dict:
        """El control remoto del iPhone: un botón, como si fuera del mando (a la interfaz o al reproductor)."""
        if not remote_allowed():
            raise HTTPException(429, "Más despacio")
        try:
            target = companion.remote_input(main_app.state.catalog, main_app.state.shell, body.action)
        except ValueError as exc:
            raise HTTPException(400, str(exc))
        return {"ok": True, "target": target}

    @public.post("/api/companion/text")
    def companion_text(body: CompanionText) -> dict:
        """«Escribir» del control del iPhone: el texto al campo con foco de la tele (sin QR)."""
        if not remote_allowed():
            raise HTTPException(429, "Más despacio")
        companion.remote_text(main_app.state.catalog, body.text, body.submit, body.replace)
        return {"ok": True}

    @public.get("/api/art/{item_id:path}")
    def companion_art(item_id: str, kind: str = "cover", w: int | None = None):
        """El arte de un juego para el iPhone (portada, fondo, logo): lo mismo que la tele, con el token del puerto público."""
        return library.art_response(main_app.state.catalog, item_id, kind, w)

    @public.get("/api/companion/console")
    def companion_console() -> dict:
        """Cómo está la consola mientras juegas (el iPhone lo pide cada ~30 s): batería, energía, wifi, mandos, memoria."""
        return companion.console_state(main_app.state.catalog)

    @public.post("/api/companion/console")
    def companion_console_set(body: CompanionConsole) -> dict:
        """Del iPhone: modo de energía o cerrar un programa (nunca el juego ni Orbital)."""
        try:
            return companion.console_action(main_app.state.catalog, body.power_mode, body.close_app)
        except LookupError as exc:
            raise HTTPException(404, str(exc))
        except (ValueError, PermissionError) as exc:
            raise HTTPException(409, str(exc))

    @public.post("/api/companion/game")
    def companion_game(body: CompanionGame) -> dict:
        """Volver al juego, ir al Inicio o cerrarlo desde el iPhone."""
        try:
            return {"game": companion.game_action(main_app.state.catalog, main_app.state.shell, body.action)}
        except companion.NothingPlaying as exc:
            raise HTTPException(409, str(exc))
        except ValueError as exc:
            raise HTTPException(400, str(exc))

    @public.post("/api/companion/player")
    def companion_player(body: CompanionPlayerAction) -> dict:
        """Un botón de la tarjeta «Viendo en la TV»: pausa, adelantar, siguiente episodio o canal…"""
        try:
            now = companion.control_player(main_app.state.catalog, body.action, body.delta, body.level, body.track)
        except companion.NothingPlaying as exc:
            raise HTTPException(409, str(exc))
        except ValueError as exc:
            raise HTTPException(409, str(exc))
        return {"playing": now}

    return public


def _volume() -> dict | None:
    from . import quick

    try:
        return quick.volume()
    except OSError:
        return None


def _is_game_list(list_id: str) -> bool:
    return list_id == "mygames" or list_id.startswith("rawg:")


def _foryou_public_routes(public: FastAPI, main_app: FastAPI) -> None:
    """«Para ti» para el iPhone por el túnel: la misma curaduría de la consola (misma caché), sin juegos
    (el iPhone solo enseña películas y series)."""

    def foryou_of() -> Any:
        return main_app.state.catalog.foryou

    @public.get("/api/foryou")
    def overview() -> dict:
        data = foryou_of().overview()
        # Ni juegos ni lo que solo arma la TV (premios, estudios, años…): el iPhone calcula los suyos.
        data["lists"] = [row for row in data["lists"] if not _is_game_list(row["id"]) and not row["id"].startswith(TV_ONLY_PREFIXES)]
        data["mosaic"] = [item for item in data["mosaic"] if item.get("kind") != "game"]
        return data

    @public.get("/api/foryou/list")
    def items(id: str, kind: str | None = None) -> dict:
        list_id = id[:120]
        if _is_game_list(list_id) or list_id.startswith(TV_ONLY_PREFIXES):
            raise HTTPException(404, "Esa lista ya no existe.")
        try:
            return foryou_of().list_payload(list_id, kind)
        except KeyError:
            raise HTTPException(404, "Esa lista ya no existe.")
        except trakt.TraktAuthError as exc:
            raise HTTPException(409, str(exc))
        except SERVICE_ERRORS:
            raise HTTPException(502, "No pude cargar esta lista. Revisa tu conexión e inténtalo de nuevo.")

    @public.get("/api/foryou/details")
    def details(key: str, kind: str | None = None) -> dict:
        value = key[:320]
        if value.startswith(("rawg:", "game:")):
            raise HTTPException(404, "No encontré esa sugerencia.")
        try:
            return foryou_of().details(value, kind)
        except KeyError:
            raise HTTPException(404, "No encontré esa sugerencia.")
        except SERVICE_ERRORS:
            return {"overview": ""}  # sin sinopsis no pasa nada

    @public.post("/api/foryou/dismiss")
    def dismiss(body: foryou.DismissRequest) -> dict:
        try:
            foryou_of().dismiss(body.key)
        except ValueError as exc:
            raise HTTPException(422, str(exc))
        return {"ok": True}
