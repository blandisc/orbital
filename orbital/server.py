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

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import FileResponse, JSONResponse, StreamingResponse
from fastapi.concurrency import run_in_threadpool
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

from . import __version__, system
from .catalog import Catalog
from .config import Config
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


def is_local_request(request: Request) -> bool:
    """Local = viene del propio equipo y NO atravesó un proxy/túnel (cloudflared, ngrok...)."""
    if any(h in request.headers for h in _FORWARD_HEADERS):
        return False
    host = request.client.host if request.client else ""
    try:
        return ipaddress.ip_address(host).is_loopback
    except ValueError:
        return False


def create_app(config: Config, catalog: Catalog | None = None, kiosk=None) -> FastAPI:
    catalog = catalog or Catalog(config)
    voice = VoiceController(catalog, kiosk)
    bus = EventBus()
    @asynccontextmanager
    async def lifespan(_: FastAPI):
        bus.loop = asyncio.get_running_loop()
        catalog.listeners.append(bus.publish_threadsafe)
        await run_in_threadpool(catalog.refresh)
        yield
        catalog.listeners.remove(bus.publish_threadsafe)

    app = FastAPI(title="Orbital", version=__version__, lifespan=lifespan)
    app.state.catalog = catalog
    app.state.bus = bus
    app.state.alexa_last = None  # última vez que llegó un comando de voz remoto

    @app.middleware("http")
    async def security(request: Request, call_next):
        # Bloquea páginas web ajenas que intenten lanzar cosas contra localhost.
        origin = request.headers.get("origin")
        if origin and origin.rstrip("/") != f"{request.url.scheme}://{request.url.netloc}":
            return JSONResponse({"detail": "Origen no permitido"}, status_code=403)
        if not is_local_request(request):
            auth = request.headers.get("authorization", "")
            token = auth.removeprefix("Bearer ").strip()
            if not token or not hmac.compare_digest(token, config.server.token):
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
        return {"stopped": catalog.launcher.stop()}

    @app.post("/api/voice")
    async def voice_command(body: VoiceRequest, request: Request) -> dict:
        if not is_local_request(request):
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

    app.mount("/", StaticFiles(directory=WEB_DIR, html=True), name="web")
    return app
