"""Panel rápido (volumen, brillo, energía, batería) y galería de capturas."""

from __future__ import annotations

import re
from pathlib import Path

from fastapi import APIRouter, HTTPException
from fastapi.concurrency import run_in_threadpool
from fastapi.responses import FileResponse

from .. import capture, quick
from .deps import Deps

_LOCAL = re.compile(r"^[A-Za-z]:\\(?!\\)")


def _inside_gallery(path: str) -> Path:
    """Solo imágenes y videos de las carpetas de capturas: nunca rutas arbitrarias. Las rutas de red
    (servidor compartido) se rechazan ANTES de tocarlas: resolverlas colgaba un hilo y abría una conexión SMB."""
    # Solo rutas locales absolutas «C:\…»: «/\servidor», «\\?\UNC», «C:relativa» y similares, fuera.
    path = path.replace("/", "\\") if isinstance(path, str) else ""
    if not path or chr(0) in path or not _LOCAL.match(path) or len(path) > 1024:
        raise HTTPException(404, "Esa captura ya no está")
    try:
        target = Path(path).resolve()
    except (OSError, ValueError) as exc:
        raise HTTPException(404, "Esa captura ya no está") from exc
    inside = any(target.is_relative_to(folder.resolve()) for folder in capture.folders())
    if not inside or target.suffix.lower() not in capture.IMAGE_EXT | capture.VIDEO_EXT or not target.is_file():
        raise HTTPException(404, "Esa captura ya no está")
    return target


def router(d: Deps) -> APIRouter:
    r = APIRouter()

    @r.get("/api/quick")
    async def get_quick() -> dict:
        return await run_in_threadpool(quick.snapshot)

    @r.post("/api/quick")
    def set_quick(body: dict) -> dict:
        # Se valida todo antes de tocar nada (tipos exactos: "false" no es un booleano).
        number = lambda v: isinstance(v, (int, float)) and not isinstance(v, bool) and 0 <= v <= 100  # noqa: E731
        if "volume" in body and not number(body["volume"]):
            raise HTTPException(422, "Volumen: un número de 0 a 100")
        if "brightness" in body and not number(body["brightness"]):
            raise HTTPException(422, "Brillo: un número de 0 a 100")
        if "muted" in body and not isinstance(body["muted"], bool):
            raise HTTPException(422, "Silencio: sí o no")
        if "power_mode" in body and (not isinstance(body["power_mode"], str) or body["power_mode"] not in quick.POWER_MODES):
            raise HTTPException(422, "Modo de energía desconocido")
        if "volume" in body:
            quick.set_volume(level=int(body["volume"]))
        if "muted" in body:
            quick.set_volume(muted=body["muted"])
        if "brightness" in body:
            quick.set_brightness(int(body["brightness"]))
        if "power_mode" in body:
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
