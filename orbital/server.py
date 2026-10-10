"""API HTTP + interfaz web de Orbital."""

from __future__ import annotations

import asyncio
import hmac
import ipaddress
import json
import logging
import threading
import time
from contextlib import asynccontextmanager
from pathlib import Path
from urllib.parse import urlsplit

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import FileResponse, JSONResponse, StreamingResponse
from fastapi.concurrency import run_in_threadpool
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

from . import __version__, system
from .catalog import Catalog
from .config import Config
from .shell import ConsoleShell
from .voice import VoiceController

log = logging.getLogger(__name__)
WEB_DIR = Path(__file__).parent / "web"
_FORWARD_HEADERS = ("x-forwarded-for", "forwarded", "cf-connecting-ip", "x-real-ip")


class LaunchRequest(BaseModel):
    id: str
    runner: str | None = None


class PrefsRequest(BaseModel):
    id: str
    favorite: bool | None = None
    hidden: bool | None = None
    runner: str | None = None
    clear_runner: bool = False


class VoiceRequest(BaseModel):
    intent: str | None = None
    slots: dict[str, str] | None = None
    text: str | None = None


class EventBus:
    """Reparte eventos (toasts, navegación por voz) a las pantallas conectadas vía SSE."""

    def __init__(self) -> None:
        self._subscribers: set[asyncio.Queue] = set()
        self.loop: asyncio.AbstractEventLoop | None = None

    def subscribe(self) -> asyncio.Queue:
        queue: asyncio.Queue = asyncio.Queue(maxsize=100)
        self._subscribers.add(queue)
        return queue

    def unsubscribe(self, queue: asyncio.Queue) -> None:
        self._subscribers.discard(queue)

    def publish(self, event: dict) -> None:
        for queue in list(self._subscribers):
            if not queue.full():
                queue.put_nowait(event)

    def publish_threadsafe(self, event: dict) -> None:
        """Para hilos que no son el del servidor (p. ej. el vigilante de procesos)."""
        if self.loop and not self.loop.is_closed():
            self.loop.call_soon_threadsafe(self.publish, event)


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


def create_app(config: Config, catalog: Catalog | None = None, kiosk=None, shortcuts: bool = False) -> FastAPI:
    """`shortcuts`: activa los atajos globales del mando (Home, Select+Start, Legion L)."""
    catalog = catalog or Catalog(config)
    if kiosk is not None:
        catalog.kiosk = kiosk
    voice = VoiceController(catalog, kiosk)
    bus = EventBus()
    shell = ConsoleShell(catalog, kiosk, publish=bus.publish_threadsafe)

    @asynccontextmanager
    async def lifespan(_: FastAPI):
        bus.loop = asyncio.get_running_loop()
        catalog.listeners.append(bus.publish_threadsafe)
        await run_in_threadpool(catalog.refresh)
        if shortcuts:
            shell.start()
        yield
        catalog.listeners.remove(bus.publish_threadsafe)

    app = FastAPI(title="Orbital", version=__version__, lifespan=lifespan)
    app.state.catalog = catalog
    app.state.bus = bus
    app.state.shell = shell
    app.state.alexa_last = None  # última vez que llegó un comando de voz remoto

    @app.middleware("http")
    async def security(request: Request, call_next):
        # Bloquea páginas web ajenas que intenten lanzar cosas contra localhost.
        origin = request.headers.get("origin")
        if origin and origin.rstrip("/") != f"{request.url.scheme}://{request.url.netloc}":
            return JSONResponse({"detail": "Origen no permitido"}, status_code=403)
        if not is_local_request(request) and not token_ok(request, config.server.token):
            return JSONResponse({"detail": "Token inválido"}, status_code=401)
        return await call_next(request)

    @app.get("/api/health")
    def health() -> dict:
        return {"ok": True, "version": __version__}

    @app.get("/api/library")
    def library() -> dict:
        catalog.refresh_stremio_if_stale()  # en segundo plano; avisa con "library-changed"
        return {"rows": catalog.grouped(), "hidden": catalog.hidden_count()}

    @app.post("/api/library/refresh")
    def refresh() -> dict:
        return {"count": catalog.refresh(), "rows": catalog.grouped(), "hidden": catalog.hidden_count()}

    @app.post("/api/prefs")
    def prefs(body: PrefsRequest) -> dict:
        try:
            return catalog.set_prefs(body.id, favorite=body.favorite, hidden=body.hidden,
                                     runner=body.runner, clear_runner=body.clear_runner)
        except KeyError:
            raise HTTPException(404, "Elemento no encontrado")
        except ValueError as exc:
            raise HTTPException(422, str(exc))

    @app.post("/api/prefs/unhide-all")
    def unhide_all() -> dict:
        return {"restored": catalog.state.unhide_all()}

    @app.get("/api/system")
    async def system_info() -> dict:
        return {"wifi": await run_in_threadpool(system.wifi), "alexa_last": app.state.alexa_last}

    @app.post("/api/launch")
    def launch(body: LaunchRequest) -> dict:
        try:
            item = catalog.launch(body.id, body.runner)
        except KeyError:
            raise HTTPException(404, "Elemento no encontrado")
        except (OSError, RuntimeError, ValueError) as exc:
            raise HTTPException(500, f"No se pudo abrir: {exc}")
        return {"ok": True, "title": item.title}

    @app.get("/api/status")
    def status() -> dict:
        return {"running": catalog.launcher.status()}

    @app.get("/api/ui")
    def ui_info() -> dict:
        return {"can_exit": kiosk is not None}

    @app.post("/api/ui/exit")
    async def ui_exit() -> dict:
        if kiosk is None:
            raise HTTPException(409, "Esta ventana no la abrió Orbital: ciérrala tú (Alt+F4)")
        # Se cierra un instante después para que la respuesta llegue a la página.
        asyncio.get_running_loop().call_later(0.4, lambda: threading.Thread(target=kiosk.close, daemon=True).start())
        return {"ok": True}

    @app.post("/api/stop")
    def stop() -> dict:
        # También cierra un emulador abierto desde ES-DE si se pidió con Select+Start.
        return {"stopped": shell.stop_game()}

    @app.post("/api/ui/resume")
    def ui_resume() -> dict:
        """Vuelve al juego ("Seguir jugando")."""
        shell.hold = None
        return {"ok": shell.resume()}

    async def run_voice(body: VoiceRequest, remote: bool) -> dict:
        if remote:
            app.state.alexa_last = time.time()
        if body.intent:
            result = await run_in_threadpool(voice.handle_intent, body.intent, body.slots)
        elif body.text:
            result = await run_in_threadpool(voice.handle_text, body.text)
        else:
            raise HTTPException(422, "Envía 'intent' o 'text'")
        for event in result.events:
            bus.publish(event)
        return result.as_dict()

    app.state.run_voice = run_voice

    @app.post("/api/voice")
    async def voice_command(body: VoiceRequest, request: Request) -> dict:
        return await run_voice(body, remote=not is_local_request(request))

    @app.get("/api/events")
    async def events(request: Request) -> StreamingResponse:
        queue = bus.subscribe()

        async def stream():
            try:
                yield ": conectado\n\n"
                while not await request.is_disconnected():
                    try:
                        event = await asyncio.wait_for(queue.get(), timeout=15)
                        yield f"data: {json.dumps(event, ensure_ascii=False)}\n\n"
                    except asyncio.TimeoutError:
                        yield ": ping\n\n"
            finally:
                bus.unsubscribe(queue)

        return StreamingResponse(stream(), media_type="text/event-stream")

    @app.get("/api/art/{item_id:path}")
    def art(item_id: str, kind: str = "cover") -> FileResponse:
        # Solo se sirven imágenes que el escaneo asoció a un elemento: nunca rutas arbitrarias.
        item = catalog.get(item_id)
        path = None if item is None else (item.hero_path if kind == "hero" else item.art_path)
        if not path or not Path(path).is_file():
            raise HTTPException(404)
        return FileResponse(path, headers={"Cache-Control": "max-age=86400"})

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
