"""Ajustes → Actualizar Orbital."""

from __future__ import annotations

import logging
import os
import threading

from fastapi import APIRouter, HTTPException
from fastapi.concurrency import run_in_threadpool

from .. import supervisor
from ..updater import Updater
from .deps import Deps

log = logging.getLogger(__name__)


def restart_orbital(d: Deps) -> None:
    """Cierra Orbital con el código que le pide al vigilante reabrirlo (con la versión nueva)."""
    try:
        d.shell.unpause()
        d.shell.unpin_orbital()
    except Exception:  # noqa: BLE001
        log.exception("Antes de reiniciar Orbital")
    logging.shutdown()
    os._exit(supervisor.RESTART)


def router(d: Deps, updater: Updater | None = None, restart=restart_orbital) -> APIRouter:
    r = APIRouter()
    up = updater or Updater()
    busy = threading.Lock()

    @r.get("/api/update")
    async def check(force: bool = False) -> dict:
        info = await run_in_threadpool(up.check, force)
        return {**info.public(), "busy": busy.locked()}

    @r.post("/api/update")
    def apply() -> dict:
        if not busy.acquire(blocking=False):
            raise HTTPException(409, "Ya se está actualizando")

        def work() -> None:
            try:
                ok, message = up.apply(lambda text: d.hub.publish_threadsafe({"type": "toast", "message": text}))
                if ok and not supervisor.is_child():
                    message = "Listo. Cierra y abre Orbital para usar la versión nueva."
                d.hub.publish_threadsafe({"type": "update-done", "ok": ok, "message": message})
                if ok and supervisor.is_child():
                    threading.Timer(2.0, restart, args=(d,)).start()
            finally:
                busy.release()

        threading.Thread(target=work, daemon=True, name="update").start()
        return {"ok": True}

    return r
