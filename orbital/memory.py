"""Liberar memoria: qué programas ocupan más y cerrar los que no estés usando.

Lo que hace tronar a los juegos es quedarse sin margen de memoria comprometida (ver health.py).
Aquí se agrupa por programa (la app de Claude son ~18 procesos) y solo se ofrece cerrar lo que es
seguro cerrar: apps con ventana o conocidas (Claude, Discord, Steam, navegadores…). Nunca piezas de
Windows, el antivirus, Orbital ni su ventana.
"""

from __future__ import annotations

import ctypes
import logging
import subprocess
import sys
from dataclasses import dataclass, field

from . import health, windows

log = logging.getLogger(__name__)

# Nunca se ofrecen para cerrar (Windows, drivers, Orbital y lo que mantiene la consola funcionando).
PROTECTED = {
    "system", "registry", "smss.exe", "csrss.exe", "wininit.exe", "winlogon.exe", "services.exe", "lsass.exe",
    "svchost.exe", "dwm.exe", "explorer.exe", "fontdrvhost.exe", "sihost.exe", "ctfmon.exe", "dllhost.exe",
    "conhost.exe", "runtimebroker.exe", "searchhost.exe", "startmenuexperiencehost.exe", "shellexperiencehost.exe",
    "textinputhost.exe", "audiodg.exe", "spoolsv.exe", "msmpeng.exe", "nissrv.exe", "securityhealthservice.exe",
    "memory compression", "wudfhost.exe", "taskhostw.exe", "lockapp.exe", "applicationframehost.exe",
    "python.exe", "pythonw.exe", "legionspace.exe", "msedge.exe", "msedgewebview2.exe", "gamebar.exe",
    "gamebarftserver.exe", "widgets.exe", "phoneexperiencehost.exe", "systemsettings.exe",
}
# Apps que viven en la bandeja (sin ventana visible) y es seguro cerrar.
KNOWN_APPS = {"claude.exe", "discord.exe", "steam.exe", "steamwebhelper.exe", "chrome.exe", "spotify.exe",
              "slack.exe", "ms-teams.exe", "teams.exe", "whatsapp.exe", "telegram.exe", "epicgameslauncher.exe",
              "battle.net.exe", "eadesktop.exe", "obs64.exe", "onedrive.exe", "zoom.exe"}
# Al cerrar, el grupo entero (Steam son steam.exe + sus steamwebhelper).
GROUPS = {"steamwebhelper.exe": "steam.exe"}
# Cómo cerrar bien algunos (sin perder descargas): si no, se terminan sus procesos.
GRACEFUL = {"steam.exe": ["-shutdown"]}
WARNINGS = {"claude.exe": "Detiene lo que Claude esté haciendo en esta consola",
            "steam.exe": "Las descargas siguen cuando lo vuelvas a abrir"}


@dataclass
class AppUsage:
    exe: str  # el ejecutable principal del grupo ("steam.exe")
    name: str  # cómo se llama para ti ("Steam")
    mb: int
    pids: list[int] = field(default_factory=list)
    closable: bool = False
    warning: str = ""

    def public(self) -> dict:
        return {"exe": self.exe, "name": self.name, "mb": self.mb, "closable": self.closable, "warning": self.warning}


class _Counters(ctypes.Structure):
    _fields_ = [("cb", ctypes.c_ulong), ("PageFaultCount", ctypes.c_ulong),
                ("PeakWorkingSetSize", ctypes.c_size_t), ("WorkingSetSize", ctypes.c_size_t),
                ("a", ctypes.c_size_t), ("b", ctypes.c_size_t), ("c", ctypes.c_size_t), ("d", ctypes.c_size_t),
                ("PagefileUsage", ctypes.c_size_t), ("PeakPagefileUsage", ctypes.c_size_t),
                ("PrivateUsage", ctypes.c_size_t)]


def _private_mb(pid: int) -> int:
    from ctypes import wintypes

    kernel32, psapi = ctypes.windll.kernel32, ctypes.windll.psapi  # type: ignore[attr-defined]
    kernel32.OpenProcess.restype = wintypes.HANDLE
    handle = kernel32.OpenProcess(0x1000, False, pid)  # PROCESS_QUERY_LIMITED_INFORMATION
    if not handle:
        return 0
    try:
        counters = _Counters()
        counters.cb = ctypes.sizeof(counters)
        if psapi.GetProcessMemoryInfo(handle, ctypes.byref(counters), counters.cb):
            return int(counters.PrivateUsage // (1024 * 1024))
        return 0
    finally:
        kernel32.CloseHandle(handle)


def usage(limit: int = 6, protect_pids: set[int] | None = None) -> list[AppUsage]:
    """Los programas que más memoria comprometida tienen, agrupados, lo más grande primero."""
    if sys.platform != "win32":
        return []
    protect_pids = protect_pids or set()
    procs = windows.processes()
    with_window = {windows.pid_of(w["hwnd"]) for w in windows.app_windows()}
    groups: dict[str, AppUsage] = {}
    for pid, (exe, _parent) in procs.items():
        exe = exe.lower()
        key = GROUPS.get(exe, exe)
        mb = _private_mb(pid)
        if not mb:
            continue
        app = groups.get(key)
        if app is None:
            app = groups[key] = AppUsage(key, health.NICE_NAMES.get(key, key.removesuffix(".exe")), 0)
        app.mb += mb
        app.pids.append(pid)
        if pid in with_window:
            app.closable = True
    for app in groups.values():
        protected = app.exe in PROTECTED or any(p in protect_pids for p in app.pids)
        app.closable = not protected and (app.closable or app.exe in KNOWN_APPS)
        app.warning = WARNINGS.get(app.exe, "")
    return sorted(groups.values(), key=lambda a: a.mb, reverse=True)[:limit]


# Consolas cuyos emuladores ocupan mucho (Eden llega a 10 GB, Ryujinx 3–4 GB): antes de abrirlas se revisa la memoria.
HEAVY_SYSTEMS = {"switch", "wiiu", "ps3", "ps4", "xbox360"}
PLAY_FREE_MB = 4000  # RAM disponible por debajo de esto: el juego va a pelear por memoria (tirones, la consola trabada)
PLAY_MIN_APP_MB = 300  # solo vale la pena ofrecer cerrar lo que pesa


def before_play(system: str | None, protect_pids: set[int] | None = None, free_mb: int | None = None) -> dict | None:
    """Antes de abrir un juego pesado: si falta memoria y hay programas que se pueden cerrar, cuáles (para ofrecerlo).
    None si no hace falta (la consola ligera, una consola que no pesa, o nada que cerrar). Midiendo solo lo barato
    primero: la lista de programas (lo lento) solo cuando de verdad falta."""
    if system not in HEAVY_SYSTEMS:
        return None
    free_mb = health.free_ram_mb() if free_mb is None else free_mb
    if free_mb is None or free_mb >= PLAY_FREE_MB:
        return None
    apps = [a for a in usage(limit=12, protect_pids=protect_pids) if a.closable and a.mb >= PLAY_MIN_APP_MB][:4]
    if not apps:
        return None
    return {"free_mb": free_mb, "apps": [a.public() for a in apps]}


def close(exe: str, protect_pids: set[int] | None = None) -> int:
    """Cierra un programa (todos sus procesos). Devuelve cuántos MB tenía."""
    apps = {a.exe: a for a in usage(limit=200, protect_pids=protect_pids)}
    app = apps.get(exe.lower())
    if app is None:
        raise LookupError("Ese programa ya no está abierto")
    if not app.closable:
        raise PermissionError(f"{app.name} no se puede cerrar desde Orbital")
    flags = getattr(subprocess, "CREATE_NO_WINDOW", 0)
    if app.exe in GRACEFUL:
        main = [p for p in app.pids if windows.exe_name(p) == app.exe]
        exe_path = windows.exe_path(min(main)) if main else ""
        if exe_path:
            subprocess.Popen([exe_path, *GRACEFUL[app.exe]], creationflags=flags)
            log.info("Cerrando %s (a su manera): %d MB", app.name, app.mb)
            return app.mb
    for pid in app.pids:
        subprocess.run(["taskkill", "/PID", str(pid), "/T", "/F"], capture_output=True, creationflags=flags)
    log.info("Cerré %s para liberar memoria: %d MB", app.name, app.mb)
    return app.mb
