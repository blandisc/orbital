"""Salud de la consola: memoria libre y memoria de video de DWM, para que los juegos sí abran.

En la Legion Go la memoria de video sale de la RAM. Si se acaba (DWM, el que dibuja las ventanas,
puede ir acumulando), los emuladores fallan al arrancar (Eden: VK_ERROR_OUT_OF_DEVICE_MEMORY).
Cada pocos minutos se anota una línea en %LOCALAPPDATA%\\orbital\\memoria.csv (hora, RAM libre,
memoria de DWM y qué estaba abierto) y, si la memoria está casi llena, Orbital avisa en pantalla.
"""

from __future__ import annotations

import ctypes
import logging
import os
import sys
import threading
import time
from collections.abc import Callable
from pathlib import Path

log = logging.getLogger(__name__)

INTERVAL = 300  # s entre mediciones
LOW_RAM_MB = 1500  # menos que esto libre: los juegos pueden no abrir
DWM_HIGH_MB = 8000  # DWM con más memoria compartida que esto: casi seguro, fuga
WARN_EVERY = 3600  # s: no repetir el aviso más de una vez por hora
MAX_CSV_BYTES = 1_000_000


class _MemoryStatus(ctypes.Structure):
    _fields_ = [("dwLength", ctypes.c_uint), ("dwMemoryLoad", ctypes.c_uint),
                ("ullTotalPhys", ctypes.c_ulonglong), ("ullAvailPhys", ctypes.c_ulonglong),
                ("ullTotalPageFile", ctypes.c_ulonglong), ("ullAvailPageFile", ctypes.c_ulonglong),
                ("ullTotalVirtual", ctypes.c_ulonglong), ("ullAvailVirtual", ctypes.c_ulonglong),
                ("ullAvailExtendedVirtual", ctypes.c_ulonglong)]


def free_ram_mb() -> int | None:
    if sys.platform != "win32":
        return None
    status = _MemoryStatus()
    status.dwLength = ctypes.sizeof(status)
    if not ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(status)):  # type: ignore[attr-defined]
        return None
    return int(status.ullAvailPhys // (1024 * 1024))


def _pdh_sum(counter_paths: list[str]) -> list[float] | None:
    """Suma de cada contador de Windows (con comodines: una instancia por adaptador). Con pdh.dll."""
    from ctypes import wintypes

    pdh = ctypes.windll.pdh  # type: ignore[attr-defined]
    query = wintypes.HANDLE()
    if pdh.PdhOpenQueryW(None, None, ctypes.byref(query)) != 0:
        return None
    try:
        groups: list[list[wintypes.HANDLE]] = []
        for path in counter_paths:
            size = wintypes.DWORD(0)
            pdh.PdhExpandWildCardPathW(None, path, None, ctypes.byref(size), 0)
            if not size.value:
                groups.append([])
                continue
            buf = ctypes.create_unicode_buffer(size.value)
            if pdh.PdhExpandWildCardPathW(None, path, buf, ctypes.byref(size), 0) != 0:
                groups.append([])
                continue
            names = [n for n in ctypes.wstring_at(ctypes.addressof(buf), size.value).split("\x00") if n]
            handles = []
            for name in names:
                counter = wintypes.HANDLE()
                if pdh.PdhAddEnglishCounterW(query, name, None, ctypes.byref(counter)) == 0:
                    handles.append(counter)
            groups.append(handles)
        if pdh.PdhCollectQueryData(query) != 0:
            return None

        class _Value(ctypes.Structure):
            _fields_ = [("CStatus", wintypes.DWORD), ("largeValue", ctypes.c_longlong)]

        totals = []
        for handles in groups:
            total = 0.0
            for counter in handles:
                value = _Value()
                if pdh.PdhGetFormattedCounterValue(counter, 0x400, None, ctypes.byref(value)) == 0:  # PDH_FMT_LARGE
                    total += value.largeValue
            totals.append(total)
        return totals
    finally:
        pdh.PdhCloseQuery(query)


def dwm_gpu_mb() -> tuple[int, int] | None:
    """(compartida, dedicada) en MB que usa DWM según los contadores de Windows (sin PowerShell)."""
    if sys.platform != "win32":
        return None
    from . import windows

    pids = windows.pids_by_exe("dwm.exe")
    if not pids:
        return None
    pid = min(pids)
    try:
        totals = _pdh_sum([rf"\GPU Process Memory(pid_{pid}_*)\Shared Usage",
                           rf"\GPU Process Memory(pid_{pid}_*)\Dedicated Usage"])
    except OSError:
        return None
    if not totals:
        return None
    return int(totals[0] // (1024 * 1024)), int(totals[1] // (1024 * 1024))


def needs_warning(free_mb: int | None, dwm: tuple[int, int] | None) -> bool:
    return (free_mb is not None and free_mb < LOW_RAM_MB) or (dwm is not None and dwm[0] > DWM_HIGH_MB)


def csv_path() -> Path:
    return Path(os.environ.get("LOCALAPPDATA", ".")) / "orbital" / "memoria.csv"


def append_sample(path: Path, when: float, free_mb: int | None, dwm: tuple[int, int] | None, running: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists() and path.stat().st_size > MAX_CSV_BYTES:
        path.replace(path.with_suffix(".old.csv"))
    new = not path.exists()
    with path.open("a", encoding="utf-8") as fh:
        if new:
            fh.write("hora,ram_libre_mb,dwm_compartida_mb,dwm_dedicada_mb,abierto\n")
        shared, dedicated = dwm if dwm else ("", "")
        stamp = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(when))
        fh.write(f"{stamp},{free_mb if free_mb is not None else ''},{shared},{dedicated},{running.replace(',', ' ')}\n")


class HealthMonitor:
    """Hilo que mide cada INTERVAL segundos y avisa (una vez por hora como mucho) si falta memoria."""

    def __init__(self, notify: Callable[[dict], None], running: Callable[[], str], path: Path | None = None,
                 measure=None) -> None:
        self.notify = notify
        self.running = running
        self.path = path or csv_path()
        self.measure = measure or (lambda: (free_ram_mb(), dwm_gpu_mb()))
        self._last_warning = float("-inf")
        self._stop = threading.Event()

    def check(self, now: float | None = None) -> bool:
        """Una medición: la anota y avisa si hace falta. Devuelve si avisó."""
        now = time.time() if now is None else now
        free_mb, dwm = self.measure()
        try:
            append_sample(self.path, now, free_mb, dwm, self.running())
        except OSError as exc:
            log.debug("No pude anotar la memoria: %s", exc)
        if not needs_warning(free_mb, dwm):
            return False
        log.warning("Memoria baja: %s MB libres, DWM %s MB", free_mb, dwm)
        if now - self._last_warning < WARN_EVERY:
            return False
        self._last_warning = now
        self.notify({"type": "toast", "ok": False,
                     "message": "Memoria casi llena: reinicia la consola para que los juegos abran bien"})
        return True

    def start(self) -> None:
        if sys.platform != "win32":
            return
        threading.Thread(target=self._run, daemon=True, name="health").start()

    def _run(self) -> None:
        self._stop.wait(60)  # deja arrancar todo primero
        while not self._stop.is_set():
            try:
                self.check()
            except Exception:  # noqa: BLE001
                log.exception("Error midiendo la memoria")
            self._stop.wait(INTERVAL)
