"""Orbital se vuelve a abrir solo si truena (no si tú lo cierras).

El acceso directo arranca este "vigilante", que abre el Orbital de verdad como proceso hijo:
  * El hijo termina con 0 (cerraste la ventana, "Salir al escritorio"): el vigilante también.
  * Termina con RESTART (actualizar Orbital): se abre de nuevo al instante.
  * Cualquier otra cosa (un error, Windows lo mató): se reabre tras una pausa corta. Si truena
    muchas veces seguidas, se rinde (para no quedar en un ciclo) y lo anota en el registro.
"""

from __future__ import annotations

import logging
import os
import subprocess
import sys
import time

log = logging.getLogger(__name__)

CHILD_ENV = "ORBITAL_CHILD"
RESTART = 3  # código de salida: "vuelve a abrirme" (tras actualizar)
WINDOW = 600.0  # s: cuántos tropiezos recientes cuentan
MAX_CRASHES = 4  # en WINDOW: más que esto y se rinde
BACKOFF = (1.0, 3.0, 8.0, 15.0)


def is_child() -> bool:
    return os.environ.get(CHILD_ENV) == "1"


def decide(code: int, crashes: list[float], now: float) -> tuple[str, float]:
    """("stop" | "restart", espera). `crashes` son los tropiezos recientes (se actualiza)."""
    if code == 0:
        return "stop", 0.0
    if code == RESTART:
        return "restart", 0.0
    crashes[:] = [t for t in crashes if now - t < WINDOW] + [now]
    if len(crashes) > MAX_CRASHES:
        return "stop", 0.0
    return "restart", BACKOFF[min(len(crashes), len(BACKOFF)) - 1]


def run(argv: list[str], spawn=subprocess.call, sleep=time.sleep, clock=time.monotonic) -> int:
    """Abre `python -m orbital argv` como hijo y lo reabre según `decide`. Devuelve el último código."""
    crashes: list[float] = []
    env = {**os.environ, CHILD_ENV: "1"}
    while True:
        command = [sys.executable, *argv] if getattr(sys, "frozen", False) else [sys.executable, "-m", "orbital", *argv]
        code = spawn(command, env=env)  # empaquetado (Orbital.exe) el ejecutable ya es Orbital
        action, wait = decide(code, crashes, clock())
        if action == "stop":
            if code not in (0, RESTART):
                log.error("Orbital tronó %d veces en %d min: no lo vuelvo a abrir. Revisa orbital.log",
                          len(crashes), WINDOW // 60)
            return code
        log.warning("Orbital se cerró solo (código %s): lo vuelvo a abrir", code) if code != RESTART \
            else log.info("Reabriendo Orbital (actualizado)")
        sleep(wait)
