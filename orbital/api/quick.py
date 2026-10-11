"""Panel rápido (volumen, brillo, energía, batería) y galería de capturas."""

from __future__ import annotations

from pathlib import Path

from fastapi import APIRouter, HTTPException
from fastapi.concurrency import run_in_threadpool
from fastapi.responses import FileResponse

from .. import capture, quick
from .deps import Deps


def _inside_gallery(path: str) -> Path:
    """Solo archivos de las carpetas de capturas: nunca rutas arbitrarias."""
    target = Path(path).resolve()
    if not any(target.is_relative_to(folder.resolve()) for folder in capture.folders()) or not target.is_file():
        raise HTTPException(404, "Esa captura ya no está")
    return target


def router(d: Deps) -> APIRouter:
    r = APIRouter()

    @r.get("/api/quick")
    async def get_quick() -> dict:
        return await run_in_threadpool(quick.snapshot)

    @r.post("/api/quick")
    def set_quick(body: dict) -> dict:
        if "volume" in body:
            quick.set_volume(level=int(body["volume"]))
        if "muted" in body:
            quick.set_volume(muted=bool(body["muted"]))
        if "brightness" in body:
            quick.set_brightness(int(body["brightness"]))
        if "power_mode" in body:
            if body["power_mode"] not in quick.POWER_MODES:
                raise HTTPException(422, "Modo de energía desconocido")
            quick.set_power_mode(body["power_mode"])
        return quick.snapshot()

    @r.post("/api/capture")
    def take_capture() -> dict:
        running = d.catalog.launcher.status()
        event = capture.take_and_describe(running["title"] if running else "")
        return {"ok": event.get("ok", True), "message": event["message"]}

    @r.get("/api/captures")
    async def captures() -> dict:
        items = await run_in_threadpool(capture.gallery)
        return {"items": items, "folders": [str(f) for f in capture.folders()]}

    @r.get("/api/captures/file")
    def capture_file(path: str) -> FileResponse:
        return FileResponse(_inside_gallery(path), headers={"Cache-Control": "max-age=3600"})

    @r.post("/api/captures/open")
    def open_capture(body: dict) -> dict:
        """Un clip: se abre con su reproductor (fuera de Orbital)."""
        target = _inside_gallery(str(body.get("path") or ""))
        d.catalog.launcher.open_uri(str(target))
        return {"ok": True}

    return r
