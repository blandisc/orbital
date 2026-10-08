"""API HTTP + interfaz web de Orbital."""

from __future__ import annotations

import asyncio
import hmac
import ipaddress
import json
import logging
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import FileResponse, JSONResponse, StreamingResponse
from fastapi.concurrency import run_in_threadpool
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

from . import __version__
from .catalog import Catalog
from .config import Config
from .library import steam
from .voice import VoiceController

log = logging.getLogger(__name__)
WEB_DIR = Path(__file__).parent / "web"
_FORWARD_HEADERS = ("x-forwarded-for", "forwarded", "cf-connecting-ip", "x-real-ip")


class LaunchRequest(BaseModel):
    id: str


class VoiceRequest(BaseModel):
    intent: str | None = None
    slots: dict[str, str] | None = None
    text: str | None = None


class EventBus:
    """Reparte eventos (toasts, navegación por voz) a las pantallas conectadas vía SSE."""

    def __init__(self) -> None:
        self._subscribers: set[asyncio.Queue] = set()

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


def is_local_request(request: Request) -> bool:
    """Local = viene del propio equipo y NO atravesó un proxy/túnel (cloudflared, ngrok...)."""
    if any(h in request.headers for h in _FORWARD_HEADERS):
        return False
    host = request.client.host if request.client else ""
    try:
        return ipaddress.ip_address(host).is_loopback
    except ValueError:
        return False


def create_app(config: Config, catalog: Catalog | None = None) -> FastAPI:
    catalog = catalog or Catalog(config)
    voice = VoiceController(catalog)
    bus = EventBus()
    @asynccontextmanager
    async def lifespan(_: FastAPI):
        await run_in_threadpool(catalog.refresh)
        yield

    app = FastAPI(title="Orbital", version=__version__, lifespan=lifespan)
    app.state.catalog = catalog
    app.state.bus = bus

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
        return {"rows": catalog.grouped()}

    @app.post("/api/library/refresh")
    def refresh() -> dict:
        return {"count": catalog.refresh(), "rows": catalog.grouped()}

    @app.post("/api/launch")
    def launch(body: LaunchRequest) -> dict:
        try:
            item = catalog.launch(body.id)
        except KeyError:
            raise HTTPException(404, "Elemento no encontrado")
        except (OSError, RuntimeError, ValueError) as exc:
            raise HTTPException(500, f"No se pudo abrir: {exc}")
        return {"ok": True, "title": item.title}

    @app.get("/api/status")
    def status() -> dict:
        return {"running": catalog.launcher.status()}

    @app.post("/api/stop")
    def stop() -> dict:
        return {"stopped": catalog.launcher.stop()}

    @app.post("/api/voice")
    async def voice_command(body: VoiceRequest) -> dict:
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

    @app.get("/api/art/steam/{appid}")
    def steam_art(appid: str) -> FileResponse:
        path = steam.local_art_path(catalog.steam_root, appid) if catalog.steam_root else None
        if path is None:
            raise HTTPException(404)
        return FileResponse(path)

    app.mount("/", StaticFiles(directory=WEB_DIR, html=True), name="web")
    return app
