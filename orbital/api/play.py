"""Abrir y cerrar juegos y apps, qué está abierto, saltar entre ventanas y apagar/suspender."""

from __future__ import annotations

import logging
import threading
from pathlib import Path

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from .. import system
from .deps import Deps

log = logging.getLogger(__name__)


class LaunchRequest(BaseModel):
    id: str
    runner: str | None = None
    keep: bool = False  # abrir sin cerrar lo que estaba abierto


def humane_error(exc: Exception, what: str = "") -> str:
    """Errores de Windows/Python en palabras de persona (lo técnico se queda en el log)."""
    if isinstance(exc, FileNotFoundError):
        name = Path(exc.filename).stem if getattr(exc, "filename", None) else (what or "el programa")
        return f"No encuentro {name}. ¿Lo moviste o lo desinstalaste? Actualiza la biblioteca desde el menú (☰)."
    if isinstance(exc, PermissionError):
        return f"Windows no me deja abrir {what or 'esto'}. Prueba abrirlo una vez desde el escritorio."
    text = str(exc)
    if "WinError" in text or "Errno" in text:
        return f"No pude abrir {what or 'esto'}."
    return text


def router(d: Deps) -> APIRouter:
    r = APIRouter()
    catalog, shell = d.catalog, d.shell

    @r.post("/api/launch")
    def launch(body: LaunchRequest) -> dict:
        running = catalog.launcher.status()
        if running and running["id"] == body.id and not body.runner and shell.resume():
            return {"ok": True, "resumed": True}
        try:
            item = catalog.launch(body.id, body.runner, keep=body.keep)
        except KeyError:
            raise HTTPException(404, "Ese juego ya no está en tu biblioteca")
        except (OSError, RuntimeError, ValueError) as exc:
            log.warning("No se pudo abrir %s: %s", body.id, exc)
            found = catalog.get(body.id)
            raise HTTPException(500, humane_error(exc, found.title if found else ""))
        # `reveal`: la pantalla de carga espera el evento launch-ready (el juego ya está listo).
        return {"ok": True, "title": item.title, "reveal": catalog.revealing}

    @r.post("/api/launch/reveal")
    def launch_reveal() -> dict:
        """B en la pantalla de carga: mostrar ya el juego (o lo que haya)."""
        catalog.reveal_now()
        return {"ok": True}

    @r.get("/api/status")
    def status() -> dict:
        return d.status()

    @r.post("/api/stop")
    def stop() -> dict:
        # También cierra un emulador abierto desde ES-DE si se pidió con Select+Start.
        return {"stopped": shell.stop_game()}

    @r.get("/api/windows")
    def open_windows() -> dict:
        """Ventanas abiertas (como Alt+Tab), para saltar entre ellas con el mando."""
        return {"windows": shell.open_windows()}

    @r.post("/api/windows/focus")
    def focus_window(body: dict) -> dict:
        if not shell.focus_window(int(body.get("id", 0))):
            raise HTTPException(404, "Esa ventana ya no está abierta")
        return {"ok": True}

    @r.post("/api/power")
    def power(body: dict) -> dict:
        action = body.get("action")
        if action not in system.POWER_ACTIONS:
            raise HTTPException(400, "Acción desconocida")
        # Un instante después, para que la respuesta llegue a la interfaz.
        threading.Timer(0.6, system.power, args=(action,)).start()
        return {"ok": True}

    return r
