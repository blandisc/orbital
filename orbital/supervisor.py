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
  * Nunca le quita la pantalla a un juego o a un video: si hay algo abierto desde Orbital (la marca BUSY_FILE que
    escribe el lanzador, con sus procesos aún vivos) o la ventana al frente no es la de Orbital, no mata ni reabre:
    lo anota y espera a que regreses (los latidos fallidos no cuentan mientras tanto, para que un juego que acapara
    la CPU no se lea como cuelgue). Tras un tropiezo, tampoco reabre encima de un juego que sigue abierto.
"""

from __future__ import annotations

import json
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
HEARTBEAT_MISSES = 6  # latidos fallidos seguidos para darlo por colgado (3 min: un pico de carga no basta)
HEARTBEAT_TIMEOUT = 5.0  # s que espera cada latido
STARTUP_GRACE = 180.0  # s: un arranque lento (escaneo de la biblioteca) no es un cuelgue
UPDATING_STALE = 30 * 60.0  # s: una marca de «actualizando» más vieja ya no cuenta (se quedó de un apagón)
HOLD_EVERY = 10.0  # s entre revisiones mientras espera a que cierres el juego para reabrir Orbital
BUSY_FILE = "busy.json"  # lo que Orbital tiene abierto (juego, emulador, video): {"title", "pids": {pid: exe}, "exe"}
BROWSERS = ("msedge.exe", "chrome.exe", "chromium.exe")


def updating_flag() -> Path:
    """La marca que deja updater.py mientras actualiza: no se reinicia a media actualización."""
    return Path(os.environ.get("LOCALAPPDATA") or tempfile.gettempdir()) / "orbital" / "updating"


def updating(now: float | None = None) -> bool:
    try:
        age = (time.time() if now is None else now) - updating_flag().stat().st_mtime
    except OSError:
        return False
    return age < UPDATING_STALE


def busy_flag() -> Path:
    """La marca de «hay algo abierto»: la escribe el lanzador del servidor (`write_busy`) y la lee el vigilante, que
    no puede preguntarle a un servidor colgado."""
    return updating_flag().with_name(BUSY_FILE)


def write_busy(info: dict | None, path: Path | None = None) -> None:
    """Pone (o quita, con None) la marca. Nunca falla: una marca que no se pudo escribir solo hace al vigilante menos
    paciente, y el fondo de todo sigue siendo la ventana al frente."""
    path = path or busy_flag()
    try:
        if info is None:
            path.unlink(missing_ok=True)
        else:
            from .atomic import atomic_write
            atomic_write(path, json.dumps(info, ensure_ascii=False), durable=False)
    except OSError:
        log.debug("No pude actualizar la marca de «hay algo abierto»", exc_info=True)


def _alive(pid: int, exe: str, table: dict[int, tuple[str, int]] | None) -> bool:
    if table is not None:  # Windows: una foto de los procesos; el nombre descarta un pid que Windows ya reusó
        name = table.get(pid, ("", 0))[0]
        return bool(name) and (not exe or name == exe.lower())
    try:
        os.kill(pid, 0)  # fuera de Windows la señal 0 solo pregunta (en Windows os.kill CIERRA el proceso)
    except ProcessLookupError:
        return False
    except OSError:
        return True  # existe, pero es de otro usuario
    return True


def game_open(path: Path | None = None, table: dict[int, tuple[str, int]] | None = None) -> str:
    """El título de lo que Orbital tiene abierto si alguno de sus procesos sigue vivo, o "". Una marca vieja (Orbital
    se colgó y luego cerraste el juego) no cuenta: sus procesos ya no están."""
    try:
        info = json.loads((path or busy_flag()).read_text(encoding="utf-8"))
        pids = {int(pid): str(exe or "") for pid, exe in (info.get("pids") or {}).items()}
        exe = str(info.get("exe") or "").lower()
    except (OSError, ValueError, AttributeError, TypeError):
        return ""
    if table is None and sys.platform == "win32":
        from . import windows
        table = windows.processes()
    title = str(info.get("title") or "algo")
    if any(_alive(pid, name, table) for pid, name in pids.items()):
        return title
    if exe and table is not None and any(name == exe for name, _ in table.values()):
        return title  # apps de un solo ejecutable (Stremio) o el pid que aún no se conocía
    return ""


def orbital_in_front(child_pid: int, win=None) -> bool | None:
    """¿La ventana al frente es la de Orbital (su Edge, hijo del servidor, o una ventana del navegador que dice
    «Orbital»)? None si no se puede saber (fuera de Windows, o en el instante en que no hay ninguna al frente)."""
    if win is None:
        if sys.platform != "win32":
            return None
        from . import windows as win
    hwnd = win.foreground()
    if not hwnd:
        return None
    pid = win.pid_of(hwnd)
    if pid and pid in win.process_tree(child_pid):
        return True
    return "Orbital" in win.title(hwnd) and win.exe_name(pid) in BROWSERS


def away_reason(child_pid: int, game=game_open, front=orbital_in_front) -> str:
    """Por qué no conviene cerrar y reabrir Orbital ahora («Mario Kart sigue abierto»), o "" si estás en Orbital."""
    title = game()
    if title:
        return f"{title} sigue abierto"
    if front(child_pid) is False:
        return "hay otra ventana al frente"
    return ""


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


def watch(child, probe, clock=time.monotonic, busy=updating, every: float = HEARTBEAT_EVERY, away=None) -> int:
    """Espera a que el hijo termine y devuelve su código; si deja de contestar, lo mata y devuelve HUNG.
    `away()` dice por qué no conviene (un juego o un video abierto, otra ventana al frente): entonces no se cuenta el
    latido y se espera a que regreses."""
    started = last = clock()
    answered, misses, waiting = False, 0, False
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
            answered, misses, waiting = True, 0, False
            continue
        if busy() or (not answered and now - started < STARTUP_GRACE):
            continue
        reason = away() if away is not None else ""
        if reason:
            if not waiting:
                log.warning("Orbital no contesta el latido, pero %s: no lo cierro; espero a que regreses", reason)
                waiting = True
            continue
        if waiting:
            log.info("Regresaste a Orbital: vuelvo a contar sus latidos")
            waiting = False
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


def hold_while_open(game=game_open, sleep=time.sleep, every: float = HOLD_EVERY) -> None:
    """Tras un tropiezo, no reabre Orbital encima de un juego o un video que sigue abierto: espera a que lo cierres."""
    title = game()
    if title:
        log.warning("Orbital se cerró con %s abierto: lo reabro cuando lo cierres", title)
    while title:
        sleep(every)
        title = game()


def run(argv: list[str], spawn=None, sleep=time.sleep, clock=time.monotonic, port: int | None = None, probe=None,
        game=None) -> int:
    """Abre `python -m orbital argv` como hijo y lo reabre según `decide`. Devuelve el último código.
    Con `port`, además le toma el pulso (`watch`). `spawn` (pruebas) devuelve el código directo, sin latido.
    `game` (pruebas) sustituye a `game_open`: con `spawn`, si no se da, no se revisa."""
    crashes: list[float] = []
    env = {**os.environ, CHILD_ENV: "1"}
    while True:
        # Empaquetado (Orbital.exe) el ejecutable ya es Orbital.
        command = [sys.executable, *argv] if getattr(sys, "frozen", False) else [sys.executable, "-m", "orbital", *argv]
        if spawn is not None:
            code = spawn(command, env=env)
        elif port:
            child = subprocess.Popen(command, env=env)
            code = watch(child, probe or health_probe(port), clock, away=lambda pid=child.pid: away_reason(pid))
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
        if code != RESTART:
            checker = game if game is not None else (None if spawn is not None else game_open)
            if checker is not None:
                hold_while_open(checker, sleep)
        write_busy(None)  # lo que anotó el Orbital anterior ya no lo vigila nadie
