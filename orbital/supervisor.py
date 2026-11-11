"""Orbital se vuelve a abrir solo si truena (no si tú lo cierras).

El acceso directo arranca este "vigilante", que abre el Orbital de verdad como proceso hijo:
  * El hijo termina con 0 (cerraste la ventana, "Salir al escritorio"): el vigilante también.
  * Termina con RESTART (actualizar Orbital): se abre de nuevo al instante.
  * Cualquier otra cosa (un error, Windows lo mató): se reabre tras una pausa corta. Si truena
    muchas veces seguidas, se rinde (para no quedar en un ciclo) y lo anota en el registro.
  * Latido (A7): cada HEARTBEAT_EVERY s le pregunta a /api/health si sigue vivo. Tras HEARTBEAT_MISSES
    respuestas fallidas seguidas lo da por colgado, lo mata y lo reabre (como un tropiezo más). No cuenta
    mientras arranca (hasta su primera respuesta, o STARTUP_GRACE), mientras se actualiza (UPDATING_FLAG)
    ni justo después de que la consola se durmió.
"""

from __future__ import annotations

import logging
import os
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path

log = logging.getLogger(__name__)

CHILD_ENV = "ORBITAL_CHILD"
RESTART = 3  # código de salida: "vuelve a abrirme" (tras actualizar)
WINDOW = 600.0  # s: cuántos tropiezos recientes cuentan
MAX_CRASHES = 4  # en WINDOW: más que esto y se rinde
BACKOFF = (1.0, 3.0, 8.0, 15.0)
HUNG = 4  # código con que se anota un Orbital colgado (el vigilante lo mató)
HEARTBEAT_EVERY = 30.0  # s entre latidos
HEARTBEAT_MISSES = 3  # latidos fallidos seguidos para darlo por colgado
HEARTBEAT_TIMEOUT = 5.0  # s que espera cada latido
STARTUP_GRACE = 180.0  # s: un arranque lento (escaneo de la biblioteca) no es un cuelgue
UPDATING_STALE = 30 * 60.0  # s: una marca de «actualizando» más vieja ya no cuenta (se quedó de un apagón)


def updating_flag() -> Path:
    """La marca que deja updater.py mientras actualiza: no se reinicia a media actualización."""
    return Path(os.environ.get("LOCALAPPDATA") or tempfile.gettempdir()) / "orbital" / "updating"


def updating(now: float | None = None) -> bool:
    try:
        age = (time.time() if now is None else now) - updating_flag().stat().st_mtime
    except OSError:
        return False
    return age < UPDATING_STALE


def health_probe(port: int, timeout: float = HEARTBEAT_TIMEOUT):
    """¿Contesta /api/health con un 200? Con un socket simple: sin proxy y sin cargar más módulos en el vigilante."""
    def probe() -> bool:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=timeout) as sock:
                sock.sendall(b"GET /api/health HTTP/1.0\r\nHost: 127.0.0.1\r\n\r\n")
                head = sock.recv(64)
        except OSError:
            return False
        return head.startswith((b"HTTP/1.1 200", b"HTTP/1.0 200"))
    return probe


def watch(child, probe, clock=time.monotonic, busy=updating, every: float = HEARTBEAT_EVERY) -> int:
    """Espera a que el hijo termine y devuelve su código; si deja de contestar, lo mata y devuelve HUNG."""
    started = last = clock()
    answered, misses = False, 0
    while True:
        try:
            return child.wait(timeout=every)
        except subprocess.TimeoutExpired:
            pass
        now = clock()
        if now - last > every * 3:  # la consola se durmió (o el vigilante no tuvo CPU): se empieza a contar de nuevo
            misses = 0
        last = now
        if probe():
            answered, misses = True, 0
            continue
        if busy() or (not answered and now - started < STARTUP_GRACE):
            continue
        misses += 1
        log.warning("Orbital no contestó el latido (%d de %d)", misses, HEARTBEAT_MISSES)
        if misses >= HEARTBEAT_MISSES:
            log.error("Orbital se colgó (no contesta desde hace %.0f s): lo cierro y lo vuelvo a abrir", misses * every)
            child.kill()
            try:
                child.wait(timeout=15)
            except subprocess.TimeoutExpired:
                log.error("Orbital no se dejó cerrar")
            return HUNG


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


def _taskbar_back() -> None:
    if sys.platform != "win32" or os.environ.get("ORBITAL_TEST"):
        return
    try:
        from . import windows
        windows.set_taskbar_visible(True)
    except Exception:  # noqa: BLE001 - nunca impide reabrir Orbital
        log.debug("No pude regresar la barra de tareas", exc_info=True)


def run(argv: list[str], spawn=None, sleep=time.sleep, clock=time.monotonic, port: int | None = None, probe=None) -> int:
    """Abre `python -m orbital argv` como hijo y lo reabre según `decide`. Devuelve el último código.
    Con `port`, además le toma el pulso (`watch`). `spawn` (pruebas) devuelve el código directo, sin latido."""
    crashes: list[float] = []
    env = {**os.environ, CHILD_ENV: "1"}
    while True:
        # Empaquetado (Orbital.exe) el ejecutable ya es Orbital.
        command = [sys.executable, *argv] if getattr(sys, "frozen", False) else [sys.executable, "-m", "orbital", *argv]
        if spawn is not None:
            code = spawn(command, env=env)
        elif port:
            code = watch(subprocess.Popen(command, env=env), probe or health_probe(port), clock)
        else:
            code = subprocess.call(command, env=env)
        _taskbar_back()  # si Orbital tronó con la barra de Windows escondida (modo consola), de regreso
        action, wait = decide(code, crashes, clock())
        if action == "stop":
            if code not in (0, RESTART):
                log.error("Orbital tronó %d veces en %d min: no lo vuelvo a abrir. Revisa orbital.log",
                          len(crashes), WINDOW // 60)
            return code
        log.warning("Orbital se cerró solo (código %s): lo vuelvo a abrir", code) if code != RESTART \
            else log.info("Reabriendo Orbital (actualizado)")
        sleep(wait)
