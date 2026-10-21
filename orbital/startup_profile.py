"""Qué ocupa a Orbital al arrancar (arranque.log).

Los primeros segundos después de abrir, el servidor llegaba a tener un núcleo al 100 % (medido 2026-10-19: 63 s de CPU en
el primer minuto) y hasta /api/health tardaba más de 1 s: la interfaz cargaba lenta justo al abrirla. Este muestreo dice
en qué función estaba cada hilo, sin instalar nada: cada `interval` se mira la pila de todos los hilos (sys._current_frames)
y se cuenta la función de Orbital más cercana a lo que se ejecutaba. Solo cuentan los hilos que gastaron CPU desde la muestra
anterior (en Windows, GetThreadTimes): uno dormido o esperando la red no le quita nada a nadie.
"""

from __future__ import annotations

import collections
import ctypes
import logging
import os
import sys
import threading
import time
from pathlib import Path

log = logging.getLogger(__name__)

PACKAGE = os.path.dirname(os.path.abspath(__file__))


def default_path() -> Path:
    return Path(os.environ.get("LOCALAPPDATA") or Path.home()) / "orbital" / "arranque.log"


def _cpu_reader():
    """native_id del hilo -> segundos de CPU que lleva. None fuera de Windows (entonces cuenta todo hilo vivo)."""
    if sys.platform != "win32":
        return None
    kernel32 = ctypes.windll.kernel32
    kernel32.OpenThread.restype = ctypes.c_void_p
    kernel32.GetThreadTimes.argtypes = [ctypes.c_void_p] + [ctypes.POINTER(ctypes.c_ulonglong)] * 4
    kernel32.CloseHandle.argtypes = [ctypes.c_void_p]

    def cpu(native_id: int) -> float | None:
        handle = kernel32.OpenThread(0x0800, False, native_id)  # THREAD_QUERY_LIMITED_INFORMATION
        if not handle:
            return None
        try:
            times = [ctypes.c_ulonglong() for _ in range(4)]
            if not kernel32.GetThreadTimes(handle, *(ctypes.byref(t) for t in times)):
                return None
            return (times[2].value + times[3].value) / 1e7  # kernel + usuario, en unidades de 100 ns
        finally:
            kernel32.CloseHandle(handle)

    return cpu


def where(frame) -> str:
    """La función de Orbital más cercana a lo que se ejecuta (y, si es otra cosa, qué)."""
    inner = frame
    while frame is not None:
        name = frame.f_code.co_filename
        if name.startswith(PACKAGE) and not name.endswith("startup_profile.py"):
            rel = os.path.relpath(name, PACKAGE).replace("\\", "/")
            outside = "" if inner is frame else f" → {os.path.basename(inner.f_code.co_filename)}:{inner.f_code.co_name}"
            return f"{rel}:{frame.f_code.co_name}{outside}"
        frame = frame.f_back
    return f"(fuera de Orbital) {os.path.basename(inner.f_code.co_filename)}:{inner.f_code.co_name}"


def summarize(counts: collections.Counter, samples: int, interval: float, top: int = 25) -> list[str]:
    total = sum(counts.values())
    lines = [f"{samples} muestras cada {interval * 1000:.0f} ms · ≈{total * interval:.1f} s de hilos trabajando"]
    lines += [f"{n * interval:6.1f} s  {100 * n / (total or 1):4.0f} %  {name}" for name, n in counts.most_common(top)]
    return lines


def run(seconds: float = 90.0, interval: float = .05, path: Path | None = None) -> list[str]:
    me = threading.get_ident()
    counts: collections.Counter = collections.Counter()
    cpu = _cpu_reader()
    spent: dict[int, float] = {}  # native_id -> su CPU en la muestra anterior
    end = time.monotonic() + seconds
    samples = 0
    while time.monotonic() < end:
        threads = {t.ident: t for t in threading.enumerate()}
        for ident, frame in sys._current_frames().items():
            if ident == me:
                continue
            thread = threads.get(ident)
            native = getattr(thread, "native_id", None)
            if cpu and native:
                now = cpu(native)
                busy = now is not None and native in spent and now > spent[native]
                if now is not None:
                    spent[native] = now
                if not busy:
                    continue
            counts[f"[{thread.name if thread else ident}] {where(frame)}"] += 1
        samples += 1
        time.sleep(interval)
    lines = summarize(counts, samples, interval)
    try:
        target = path or default_path()
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(f"{time.strftime('%Y-%m-%d %H:%M:%S')} · los primeros {seconds:.0f} s\n" + "\n".join(lines) + "\n",
                          encoding="utf-8")
    except OSError as exc:
        log.warning("No pude escribir arranque.log: %s", exc)
    return lines


def start(seconds: float = 90.0) -> None:
    """En segundo plano: no retrasa el arranque."""
    threading.Thread(target=run, args=(seconds,), daemon=True, name="arranque").start()
