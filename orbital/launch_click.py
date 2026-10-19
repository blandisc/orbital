"""Lo que pasa al dar clic en el ícono de Orbital (escritorio, menú Inicio o arranque de Windows).

Antes, si Orbital estaba ocupada o arrancando (tardaba más de 1 s en contestar), el clic creía que no estaba abierta, se
topaba con el candado de «un solo Orbital», esperaba 10 s y se cerraba sin decir nada: «le doy clic y no inicia». Y si un
Orbital anterior se quedó colgado, pasaba lo mismo en cada clic. Ahora:

  1. Si contesta (hasta 3 s): se trae su ventana.
  2. Si el candado está tomado pero no contesta: se espera a que termine de arrancar (hasta 25 s) y se trae su ventana.
  3. Si sigue sin contestar, está colgado: se cierran sus procesos (solo los de Orbital, no tus juegos) y se abre uno nuevo.

Cada clic deja una línea en lanzador.log (el registro normal no lo veía: el segundo intento no escribe en él).
"""

from __future__ import annotations

import os
import re
import subprocess
import time
from collections.abc import Callable
from pathlib import Path

ANSWER_WAIT = 3.0  # s: una Orbital ocupada (escaneando) tarda en contestar /api/health
STARTING_WAIT = 25.0  # s: lo que puede tardar en arrancar (el vigilante, el servidor, la biblioteca)
LOG_MAX = 200_000  # bytes de lanzador.log antes de empezar de nuevo
ORBITAL_CMD = re.compile(r"(?:^|\s)-m\s+orbital(?:\s|$)|orbital\.exe", re.I)


def log_path() -> Path:
    return Path(os.environ.get("LOCALAPPDATA") or Path.home()) / "orbital" / "lanzador.log"


def note(message: str, path: Path | None = None) -> None:
    """Una línea en lanzador.log (nunca rompe el arranque)."""
    path = path or log_path()
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        if path.exists() and path.stat().st_size > LOG_MAX:
            path.unlink()
        with open(path, "a", encoding="utf-8") as out:
            out.write(f"{time.strftime('%Y-%m-%d %H:%M:%S')} [{os.getpid()}] {message}\n")
    except OSError:
        pass


def stuck_orbital(own_pid: int, processes: Callable[[], dict[int, tuple[str, int]]],
                  command_line: Callable[[int], str]) -> list[int]:
    """Los procesos de Orbital que no somos nosotros ni quienes nos abrieron (el lanzador del .venv abre al Python real)."""
    procs = processes()
    mine = set()
    pid = own_pid
    while pid and pid not in mine:  # nosotros y nuestros padres
        mine.add(pid)
        pid = procs.get(pid, ("", 0))[1]
    return sorted(p for p, (exe, _parent) in procs.items()
                  if p not in mine and exe in ("python.exe", "pythonw.exe", "orbital.exe") and ORBITAL_CMD.search(command_line(p) or exe))


def kill(pids: list[int]) -> None:
    """Cierra esos procesos (sin /T: los juegos o videos que abrieron siguen)."""
    for pid in pids:
        subprocess.run(["taskkill", "/PID", str(pid), "/F"], capture_output=True,
                       creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))


def resolve(*, answers: Callable[[float], bool], take_lock: Callable[[float], bool], show: Callable[[], None],
            stuck: Callable[[], list[int]], kill: Callable[[list[int]], None], note: Callable[[str], None] = note) -> str:
    """Qué hace este clic: «shown» (ya estaba: se trajo su ventana), «start» (abrir Orbital; el candado ya es nuestro) o
    «gave-up» (no se pudo; dice por qué en lanzador.log)."""
    if answers(ANSWER_WAIT):
        note("Clic: Orbital ya estaba abierta, traigo su ventana")
        show()
        return "shown"
    if take_lock(0):
        note("Clic: abro Orbital")
        return "start"
    note("Clic: hay una Orbital que no contesta todavía; espero a que termine de arrancar")
    if answers(STARTING_WAIT):
        note("Clic: ya contestó, traigo su ventana")
        show()
        return "shown"
    pids = stuck()
    note(f"Clic: la Orbital abierta no contestó en {STARTING_WAIT:.0f} s (colgada): la cierro ({pids or 'sin procesos'}) y abro otra")
    kill(pids)
    if take_lock(10):
        return "start"
    note("Clic: no pude cerrar la Orbital colgada; no abro una segunda")
    return "gave-up"
