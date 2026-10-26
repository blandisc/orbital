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

    # --- emuladores (Ajustes › Mantenimiento › Emuladores) ------------------------------------------------------------
    @r.get("/api/emulators/updates")
    async def emulator_updates(force: bool = False) -> dict:
        return await run_in_threadpool(d.extra["emulator_updates"].summary, force)

    @r.post("/api/emulators/updates/{emulator_id}")
    def install_emulator(emulator_id: str, force: bool = False) -> dict:
        """Instala la versión nueva en segundo plano y avisa al terminar (evento emulator-update-done)."""
        from ..emulator_updates import InstallError

        service = d.extra["emulator_updates"]
        if service.busy():
            raise HTTPException(409, "Cierra el juego primero: no actualizo un emulador abierto.")

        def work() -> None:
            try:
                message, ok = service.install(emulator_id[:40], force=force), True
            except InstallError as exc:
                message, ok = str(exc), False
            except Exception:  # noqa: BLE001
                log.exception("Actualizar emulador %s", emulator_id)
                message, ok = "No pude actualizarlo. Quedó como estaba.", False
            d.hub.publish_threadsafe({"type": "emulator-update-done", "ok": ok, "message": message})

        threading.Thread(target=work, daemon=True, name="emulator-update").start()
        return {"ok": True}

    def _in_background(name: str, action, emulator_id: str) -> dict:
        """Instalar o regresar de versión en segundo plano; avisa al terminar (evento emulator-update-done)."""
        from ..emulator_updates import InstallError

        def work() -> None:
            try:
                message, ok = action(emulator_id[:40]), True
            except InstallError as exc:
                message, ok = str(exc), False
            except Exception:  # noqa: BLE001
                log.exception("%s %s", name, emulator_id)
                message, ok = "No pude hacerlo. Quedó como estaba.", False
            d.hub.publish_threadsafe({"type": "emulator-update-done", "ok": ok, "message": message})

        threading.Thread(target=work, daemon=True, name=name).start()
        return {"ok": True}

    @r.post("/api/emulators/install/{emulator_id}")
    def install_new_emulator(emulator_id: str) -> dict:
        """Instala un emulador que faltaba para juegos que ya tienes."""
        return _in_background("emulator-install", d.extra["emulator_updates"].install_new, emulator_id)

    @r.post("/api/emulators/rollback/{emulator_id}")
    def rollback_emulator(emulator_id: str) -> dict:
        """Regresa a la versión que había antes de la última actualización."""
        if d.extra["emulator_updates"].busy():
            raise HTTPException(409, "Cierra el juego primero: no cambio un emulador abierto.")
        return _in_background("emulator-rollback", d.extra["emulator_updates"].rollback, emulator_id)

    return r
