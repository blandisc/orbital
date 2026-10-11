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
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles

from . import __version__
from .api import diagnostics, library, live, media, play, ui
from .api.deps import Deps
from .api.live import SseHub, VoiceRequest
from .api.play import humane_error  # noqa: F401 - se importa desde aquí
from .api.ui import SETTINGS  # noqa: F401
from .catalog import Catalog
from .config import Config
from .shell import ConsoleShell
from .voice import VoiceController

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
    token = request.headers.get("authorization", "").removeprefix("Bearer ").strip()
    return bool(token) and bool(expected) and hmac.compare_digest(token, expected)


def paused_path() -> Path:
    """Qué quedó congelado (para descongelarlo si Orbital se cierra de golpe)."""
    return Path(os.environ.get("LOCALAPPDATA") or Path.home() / ".local" / "state") / "orbital" / "paused.json"


def create_app(config: Config, catalog: Catalog | None = None, kiosk=None, shortcuts: bool = False,
               log_path: Path | None = None) -> FastAPI:
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

            catalog.scanning = True  # antes de que la interfaz pregunte
            threading.Thread(target=scan, daemon=True, name="first-scan").start()
        else:
            await run_in_threadpool(catalog.refresh)
        status = asyncio.create_task(live.watch_status(d))
        problems = live.ProblemNotifier(d.hub.publish_threadsafe) if shortcuts else None
        if problems:
            logging.getLogger("orbital").addHandler(problems)
        yield
        if problems:
            logging.getLogger("orbital").removeHandler(problems)
        status.cancel()
        with contextlib.suppress(asyncio.CancelledError):
            await status
        unsubscribe()

    app = FastAPI(title="Orbital", version=__version__, lifespan=lifespan)
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
                 live.router(d, is_local_request), diagnostics.router(d)):
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


def create_public_app(config: Config, main_app: FastAPI) -> FastAPI:
    """App mínima para internet (Alexa a través del túnel): solo voz y ping, siempre con token.

    Corre en otro puerto (server.public_port). Aunque el túnel entregue las peticiones desde
    127.0.0.1, aquí no hay excepciones para "local": sin token no se hace nada.
    """
    public = FastAPI(title="Orbital · Alexa", docs_url=None, redoc_url=None, openapi_url=None)

    @public.middleware("http")
    async def require_token(request: Request, call_next):
        if not token_ok(request, config.server.token):
            return JSONResponse({"detail": "Token inválido"}, status_code=401)
        return await call_next(request)

    @public.get("/api/ping")
    def ping() -> dict:
        return {"ok": True, "service": "orbital", "version": __version__}

    @public.post("/api/voice")
    async def voice_command(body: VoiceRequest) -> dict:
        return await main_app.state.run_voice(body, remote=True)

    return public
