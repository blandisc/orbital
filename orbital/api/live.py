"""En vivo: eventos para las pantallas conectadas (SSE) y comandos de voz.

Además de los avisos (toasts, "se cerró", navegación por voz), el servidor manda `status` cuando
cambia lo que está abierto o su pausa: la interfaz ya no tiene que preguntar cada 5 s.
"""

from __future__ import annotations

import asyncio
import json
import logging
import time

from fastapi import APIRouter, HTTPException, Request
from fastapi.concurrency import run_in_threadpool
from fastapi.responses import StreamingResponse
from pydantic import BaseModel

from .deps import Deps

log = logging.getLogger(__name__)
STATUS_EVERY = 1.0  # s entre comprobaciones de lo que está abierto (barato: en memoria + lista de procesos)
KEEPALIVE = 15.0


class VoiceRequest(BaseModel):
    intent: str | None = None
    slots: dict[str, str] | None = None
    text: str | None = None


class SseHub:
    """Reparte eventos a las pantallas conectadas vía SSE (una cola por pantalla)."""

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


def _comparable(status: dict) -> dict:
    running = status.get("running")
    return {"running": None if running is None else {k: v for k, v in running.items() if k != "pid"}}


async def watch_status(d: Deps) -> None:
    """Manda `status` a las pantallas cuando cambia lo abierto (lo corre el arranque del servidor)."""
    last = None
    while True:
        try:
            status = await run_in_threadpool(d.status)
            if _comparable(status) != last:
                last = _comparable(status)
                d.hub.publish({"type": "status", **status})
        except Exception:  # noqa: BLE001 - que un fallo no apague los avisos
            log.exception("No pude leer el estado")
        await asyncio.sleep(STATUS_EVERY)


def router(d: Deps, is_local) -> APIRouter:
    r = APIRouter()

    async def run_voice(body: VoiceRequest, remote: bool) -> dict:
        if remote:
            d.alexa_last = time.time()
        if body.intent:
            result = await run_in_threadpool(d.voice.handle_intent, body.intent, body.slots)
        elif body.text:
            result = await run_in_threadpool(d.voice.handle_text, body.text)
        else:
            raise HTTPException(422, "Envía 'intent' o 'text'")
        for event in result.events:
            d.hub.publish(event)
        return result.as_dict()

    d.extra["run_voice"] = run_voice

    @r.post("/api/voice")
    async def voice_command(body: VoiceRequest, request: Request) -> dict:
        return await run_voice(body, remote=not is_local(request))

    @r.get("/api/events")
    async def events(request: Request) -> StreamingResponse:
        queue = d.hub.subscribe()
        # Quien se conecta (o reconecta) recibe ya el estado, sin esperar a que cambie.
        queue.put_nowait({"type": "status", **await run_in_threadpool(d.status)})

        async def stream():
            try:
                yield ": conectado\n\n"
                while not await request.is_disconnected():
                    try:
                        event = await asyncio.wait_for(queue.get(), timeout=KEEPALIVE)
                        yield f"data: {json.dumps(event, ensure_ascii=False)}\n\n"
                    except asyncio.TimeoutError:
                        yield ": ping\n\n"
            finally:
                d.hub.unsubscribe(queue)

        return StreamingResponse(stream(), media_type="text/event-stream")

    return r
