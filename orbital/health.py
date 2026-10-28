"""Salud de la consola: memoria libre y memoria de video de DWM, para que los juegos sí abran.

En la Legion Go la memoria de video sale de la RAM. Si se acaba (DWM, el que dibuja las ventanas,
puede ir acumulando), los emuladores fallan al arrancar (Eden: VK_ERROR_OUT_OF_DEVICE_MEMORY).
Cada pocos minutos se anota una línea en %LOCALAPPDATA%\\orbital\\memoria.csv (hora, RAM libre,
memoria de DWM, lo que pesa Orbital y qué estaba abierto) y, si la memoria está casi llena, Orbital avisa en pantalla.
Si DWM crece de golpe, se mide cada minuto y se anota quién estaba al frente (para encontrar al culpable), y con la
consola sin usar se libera solo (ver dwm_release.py).
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
LOW_RAM_MB = 500  # RAM disponible por debajo de esto: Windows ya no puede ni paginar a tiempo
# Lo que de verdad hace tronar a los juegos: el margen de memoria comprometida (RAM + archivo de
# paginación). Con poca RAM libre Windows pagina y sigue; sin margen, quien pide memoria truena.
COMMIT_LOW_MB = 2000
DWM_HIGH_MB = 8000  # DWM con más memoria compartida que esto: casi seguro, fuga
WARN_EVERY = 3600  # s: no repetir el aviso más de una vez por hora
MAX_CSV_BYTES = 1_000_000
CSV_HEADER = "hora,ram_libre_mb,dwm_compartida_mb,dwm_dedicada_mb,orbital_mb,abierto\n"
# Cada juego de Switch le deja ~100 MB a DWM: con más de esto y la consola sin usar, se libera solo (dwm_release.py).
RELEASE_MB = 3000
RELEASE_IDLE = 600  # s sin tocar nada (ni mando ni teclado) antes de liberar: la pantalla parpadea
# Con otra ventana al frente (en esta consola casi siempre hay una: la terminal, el navegador) se espera más. Antes no
# se liberaba nunca así, y DWM llegó a 15 GB: los videos se trababan (ver dwm_release.FRESH_MB).
RELEASE_IDLE_AWAY = 1800
RELEASE_EVERY = 3600  # s: como mucho una vez por hora
# El 2026-10-24 DWM pasó de 0,6 a 52 GB en 25 min sin nada abierto: si crece así, medir cada minuto y anotar quién.
FAST_GROWTH_MB = 1000
FAST_INTERVAL = 60
FAST_FOR = 1800


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


def commit_room_mb() -> int | None:
    """Cuánta memoria más se puede comprometer (hasta el límite RAM + archivo de paginación)."""
    if sys.platform != "win32":
        return None
    status = _MemoryStatus()
    status.dwLength = ctypes.sizeof(status)
    if not ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(status)):  # type: ignore[attr-defined]
        return None
    return int(status.ullAvailPageFile // (1024 * 1024))


NICE_NAMES = {"claude.exe": "la app de Claude", "eden.exe": "Eden", "discord.exe": "Discord",
              "steamwebhelper.exe": "Steam", "steam.exe": "Steam", "msedge.exe": "Edge", "chrome.exe": "Chrome",
              "xenia_canary_netplay.exe": "Xenia", "xemu.exe": "xemu", "dolphin.exe": "Dolphin", "mpv.exe": "el reproductor",
              "msmpeng.exe": "el antivirus", "msedgewebview2.exe": "apps con WebView"}


def top_memory(limit: int = 3) -> list[tuple[str, int]]:
    """Los programas que más memoria tienen comprometida: [("Eden", 6720), …] en MB."""
    if sys.platform != "win32":
        return []
    from ctypes import wintypes

    from . import windows

    class _Counters(ctypes.Structure):
        _fields_ = [("cb", wintypes.DWORD), ("PageFaultCount", wintypes.DWORD),
                    ("PeakWorkingSetSize", ctypes.c_size_t), ("WorkingSetSize", ctypes.c_size_t),
                    ("a", ctypes.c_size_t), ("b", ctypes.c_size_t), ("c", ctypes.c_size_t), ("d", ctypes.c_size_t),
                    ("PagefileUsage", ctypes.c_size_t), ("PeakPagefileUsage", ctypes.c_size_t),
                    ("PrivateUsage", ctypes.c_size_t)]

    kernel32, psapi = ctypes.windll.kernel32, ctypes.windll.psapi  # type: ignore[attr-defined]
    kernel32.OpenProcess.restype = wintypes.HANDLE
    totals: dict[str, int] = {}
    for pid, (exe, _parent) in windows.processes().items():
        handle = kernel32.OpenProcess(0x1000, False, pid)  # PROCESS_QUERY_LIMITED_INFORMATION
        if not handle:
            continue
        counters = _Counters()
        counters.cb = ctypes.sizeof(counters)
        if psapi.GetProcessMemoryInfo(handle, ctypes.byref(counters), counters.cb):
            name = NICE_NAMES.get(exe, exe.removesuffix(".exe"))
            totals[name] = totals.get(name, 0) + counters.PrivateUsage // (1024 * 1024)
        kernel32.CloseHandle(handle)
    return sorted(totals.items(), key=lambda kv: kv[1], reverse=True)[:limit]


def private_mb(pids: set[int]) -> int | None:
    """Memoria comprometida (privada) de esos procesos juntos, en MB: lo que pesa Orbital (servidor + su ventana)."""
    if sys.platform != "win32" or not pids:
        return None
    from . import memory

    return sum(memory._private_mb(pid) for pid in pids)  # noqa: SLF001 - el mismo conteo que «Liberar memoria»


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


_last_dwm: list[int] = []


def note_dwm(moment: str) -> None:
    """Al registro: la memoria con la que Windows dibuja las ventanas en este momento y cuánto cambió desde la anterior
    (al abrir algo y al regresar a Orbital). Así se ve qué la hace crecer. En su propio hilo: los contadores de Windows
    tardan hasta medio minuto en contestar, y al medir antes de abrir el juego se quedaba la pantalla de carga."""
    threading.Thread(target=_note_dwm, args=(moment,), daemon=True, name="dwm-note").start()


def _note_dwm(moment: str) -> None:
    try:
        dwm = dwm_gpu_mb()
    except Exception:  # noqa: BLE001 - medir nunca tumba una apertura
        return
    if dwm is None:
        return
    delta = f" ({dwm[0] - _last_dwm[0]:+d} MB)" if _last_dwm else ""
    _last_dwm[:] = [dwm[0]]
    log.info("Memoria de dibujo de Windows (DWM) %s: %d MB%s", moment, dwm[0], delta)


def dwm_leak(dwm: tuple[int, int] | None) -> bool:
    return dwm is not None and dwm[0] > DWM_HIGH_MB


def needs_warning(free_mb: int | None, dwm: tuple[int, int] | None, commit_room: int | None = None) -> bool:
    return (dwm_leak(dwm) or (free_mb is not None and free_mb < LOW_RAM_MB)
            or (commit_room is not None and commit_room < COMMIT_LOW_MB))


def _gb(mb: int) -> str:
    return f"{mb / 1024:.1f} GB".replace(".", ",")


def warning_message(free_mb: int | None, dwm: tuple[int, int] | None, top: list[tuple[str, int]] | None = None) -> str:
    """El aviso en palabras. La fuga de DWM se arregla reiniciando; la memoria llena por programas
    abiertos, cerrándolos (reiniciar no sirve si se vuelven a abrir)."""
    if dwm is not None and dwm_leak(dwm):
        return (f"Windows está usando {dwm[0] / 1024:.0f} GB solo en dibujar las ventanas (una falla de Windows "
                "que crece con los días). Reinicia la consola: suspender no lo arregla.")
    who = ", ".join(f"{name} {_gb(mb)}" for name, mb in (top or []))
    return ("La memoria está casi llena" + (f" ({who})" if who else "") +
            ". Cierra lo que no estés usando para que los juegos abran bien.")


def csv_path() -> Path:
    return Path(os.environ.get("LOCALAPPDATA", ".")) / "orbital" / "memoria.csv"


def _header(path: Path) -> str:
    try:
        with path.open(encoding="utf-8") as fh:
            return fh.readline()
    except OSError:
        return ""


def append_sample(path: Path, when: float, free_mb: int | None, dwm: tuple[int, int] | None, running: str,
                  orbital_mb: int | None = None) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    # Lleno, o de antes de la columna orbital_mb: se aparta y empieza uno nuevo (nunca columnas revueltas).
    if path.exists() and (path.stat().st_size > MAX_CSV_BYTES or _header(path) != CSV_HEADER):
        path.replace(path.with_suffix(".old.csv"))
    new = not path.exists()
    with path.open("a", encoding="utf-8") as fh:
        if new:
            fh.write(CSV_HEADER)
        shared, dedicated = dwm if dwm else ("", "")
        stamp = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(when))
        own = orbital_mb if orbital_mb is not None else ""
        free = free_mb if free_mb is not None else ""
        fh.write(f"{stamp},{free},{shared},{dedicated},{own},{running.replace(',', ' ')}\n")


class HealthMonitor:
    """Hilo que mide cada INTERVAL segundos y avisa (una vez por hora como mucho) si falta memoria.

    `busy()`: True mientras estás en un juego o un video (Orbital no está al frente). Entonces el
    aviso NO se manda a la interfaz: se guarda y se entrega con `flush()` cuando vuelves a Orbital
    (Home, Legion L, al cerrarse el juego). Un aviso en pleno juego solo estorba y, con la ventana
    de Orbital tapada, cualquier cosa que la haga repintarse es un riesgo de que se asome encima.
    """

    def __init__(self, notify: Callable[[dict], None], running: Callable[[], str], path: Path | None = None,
                 measure=None, busy: Callable[[], bool] | None = None, own_pids: Callable[[], set[int]] | None = None,
                 idle: Callable[[], float] | None = None, release=None,
                 foreground: Callable[[], str] | None = None) -> None:
        self.notify = notify
        self.running = running
        self.busy = busy or (lambda: False)
        self.path = path or csv_path()
        self.measure = measure or (lambda: (free_ram_mb(), dwm_gpu_mb(), commit_room_mb()))
        self.own_pids = own_pids or set  # Orbital: servidor y su ventana, para anotar cuánto pesa
        self.idle = idle or (lambda: 0.0)  # s sin tocar nada (mando, teclado, ratón)
        self.release = release  # dwm_release (o un doble en las pruebas): available() y run()
        self.foreground = foreground or (lambda: "")  # el programa al frente, para anotar quién hace crecer a DWM
        self.pending: dict | None = None  # el aviso que espera a que vuelvas a Orbital
        self._last_warning = float("-inf")
        self._last_release = float("-inf")
        self._last_dwm: int | None = None
        self.fast_until = float("-inf")  # hasta cuándo medir cada minuto (DWM creciendo de golpe)
        self._stop = threading.Event()

    def check(self, now: float | None = None) -> bool:
        """Una medición: la anota y avisa si hace falta. Devuelve si avisó (o dejó el aviso esperando)."""
        now = time.time() if now is None else now
        free_mb, dwm, *rest = self.measure()
        commit = rest[0] if rest else None
        running = self.running()
        try:
            append_sample(self.path, now, free_mb, dwm, running, private_mb(self.own_pids()))
        except OSError as exc:
            log.debug("No pude anotar la memoria: %s", exc)
        if dwm is not None:
            self._watch_growth(now, dwm[0], running)
            if self.maybe_release(now, dwm[0], running):
                return False
        if not needs_warning(free_mb, dwm, commit):
            self.pending = None  # ya hay memoria: el aviso que esperaba ya no aplica
            return False
        top = top_memory() if not dwm_leak(dwm) else []
        log.warning("Memoria baja: %s MB libres, margen %s MB, DWM %s MB, %s", free_mb, commit, dwm, top)
        if now - self._last_warning < WARN_EVERY:
            return False
        # Con la fuga de DWM, pregunta con "Reiniciar ahora"; si son programas abiertos, solo avisa
        # (reiniciar no ayuda).
        event = {"type": "health", "ok": False, "restart": dwm_leak(dwm), "message": warning_message(free_mb, dwm, top)}
        if dwm_leak(dwm) and self.release is not None:
            event["release"] = "ready" if self.release.available() else "setup"  # liberar sin reiniciar
        if self.busy():
            self.pending = event  # el más reciente manda; se entrega al volver a Orbital
            log.info("Aviso de memoria en espera: estás en un juego o un video")
            return True
        self._deliver(event, now)
        return True

    def _watch_growth(self, now: float, shared: int, running: str) -> None:
        """DWM creciendo de golpe: anotar quién estaba al frente y medir cada minuto un rato (ver FAST_GROWTH_MB)."""
        before, self._last_dwm = self._last_dwm, shared
        if before is None or shared - before < FAST_GROWTH_MB:
            return
        self.fast_until = now + FAST_FOR
        log.warning("DWM creció de golpe: %+d MB (ahora %d MB). Al frente: %s · abierto: %s · lo que más ocupa: %s",
                    shared - before, shared, self.foreground() or "?", running or "nada", top_memory(5))

    def maybe_release(self, now: float, shared: int, running: str) -> bool:
        """Con DWM reteniendo mucho y la consola sin usar (nada abierto, nadie tocando), reiniciarlo para que suelte la
        memoria. Nunca en un juego o video ni con alguien usando la consola: la pantalla parpadea. Devuelve si lo hizo."""
        idle = self.idle()
        if (self.release is None or shared < RELEASE_MB or running or idle < RELEASE_IDLE
                or (self.busy() and idle < RELEASE_IDLE_AWAY) or now - self._last_release < RELEASE_EVERY):
            return False
        if not self.release.available():
            return False
        self._last_release = now
        if not self.release.run():
            return False
        log.info("Memoria de video liberada con la consola sin usar (DWM tenía %d MB)", shared)
        self._last_dwm = None  # vuelve a empezar desde poco: no es «crecer de golpe»
        return True

    def flush(self, now: float | None = None) -> bool:
        """Entrega el aviso que esperaba, si lo hay y ya no estorba. Devuelve si lo entregó."""
        event = self.pending
        if event is None or self.busy():
            return False
        self._deliver(event, time.time() if now is None else now)
        return True

    def _deliver(self, event: dict, now: float) -> None:
        self.pending = None
        self._last_warning = now  # la hora sin repetir cuenta desde que lo viste, no desde que se midió
        self.notify(event)

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
            self._stop.wait(FAST_INTERVAL if time.time() < self.fast_until else INTERVAL)
