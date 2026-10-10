"""La ventana de Orbital: Edge/Chromium a pantalla completa con un perfil propio.

Usar un perfil aparte (--user-data-dir) evita dos problemas reales:
  * si Edge ya estaba abierto, sin perfil propio la URL se abría como pestaña normal y no en kiosko;
  * al cerrar la ventana a la fuerza, Edge mostraría "¿Restaurar páginas?" la próxima vez.
"""

from __future__ import annotations

import json
import logging
import os
import shutil
import subprocess
import sys
import threading
import time
from pathlib import Path

from . import system

log = logging.getLogger(__name__)

_BROWSERS = {
    "win32": [
        r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
        r"C:\Program Files\Microsoft\Edge\Application\msedge.exe",
        r"C:\Program Files\Google\Chrome\Application\chrome.exe",
    ],
    "linux": ["chromium", "chromium-browser", "google-chrome", "microsoft-edge"],
}

FLAGS = [
    "--edge-kiosk-type=fullscreen",
    "--no-first-run",
    "--no-default-browser-check",
    "--hide-crash-restore-bubble",
    "--disable-features=Translate",
    "--autoplay-policy=no-user-gesture-required",
    "--overscroll-history-navigation=0",
]


def find_browser(configured: str | None = None) -> str | None:
    if configured:
        return configured
    for candidate in _BROWSERS.get(sys.platform, _BROWSERS["linux"]):
        if Path(candidate).exists() or shutil.which(candidate):
            return candidate
    return None


def default_profile_dir() -> Path:
    if sys.platform == "win32":
        base = Path(os.environ.get("LOCALAPPDATA", Path.home() / "AppData" / "Local"))
    else:
        base = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local" / "share"))
    return base / "orbital" / "browser"


def mark_clean_exit(profile_dir: Path) -> None:
    """Le dice a Chromium que la última sesión terminó bien (no mostrará "Restaurar páginas")."""
    prefs = profile_dir / "Default" / "Preferences"
    if not prefs.exists():
        return
    try:
        data = json.loads(prefs.read_text(encoding="utf-8"))
        profile = data.setdefault("profile", {})
        profile["exit_type"] = "Normal"
        profile["exited_cleanly"] = True
        prefs.write_text(json.dumps(data), encoding="utf-8")
    except (OSError, ValueError) as exc:
        log.debug("No se pudo ajustar %s: %s", prefs, exc)


def build_command(browser: str, url: str, profile_dir: Path) -> list[str]:
    return [browser, f"--user-data-dir={profile_dir}", "--kiosk", url, *FLAGS]


def close_orphans(profile_dir: Path) -> int:
    """Cierra ventanas de Orbital que quedaron de una sesión anterior (mismo perfil). Si no,
    Edge le pasa la página a esa ventana vieja y la nueva se cierra al instante. Nunca toca tu
    Edge normal: solo procesos con el perfil propio de Orbital."""
    if sys.platform != "win32":
        return 0
    script = (
        "Get-CimInstance Win32_Process -Filter \"Name='msedge.exe' or Name='chrome.exe'\" | "
        "Where-Object { $_.CommandLine -and $_.CommandLine.Contains($env:ORBITAL_PROFILE) "
        "-and $_.CommandLine -notmatch '--type=' } | ForEach-Object { $_.ProcessId }"
    )
    try:
        out = subprocess.run(["powershell", "-NoProfile", "-Command", script], capture_output=True, text=True,
                             timeout=15, env={**os.environ, "ORBITAL_PROFILE": f"--user-data-dir={profile_dir}"},
                             creationflags=subprocess.CREATE_NO_WINDOW).stdout  # type: ignore[attr-defined]
    except (OSError, subprocess.TimeoutExpired):
        return 0
    pids = [int(p) for p in out.split() if p.isdigit()]
    for pid in pids:
        subprocess.run(["taskkill", "/PID", str(pid), "/T", "/F"], capture_output=True,
                       creationflags=subprocess.CREATE_NO_WINDOW)  # type: ignore[attr-defined]
    if pids:
        log.info("Cerré %d ventana(s) de Orbital de una sesión anterior", len(pids))
        time.sleep(.5)
    return len(pids)


class KioskWindow:
    """Abre, trae al frente y cierra la ventana de la interfaz."""

    REOPEN_DELAY = 1.5  # s antes de reabrir una ventana que se cerró sola
    MAX_REOPENS = 3  # por minuto: si Edge falla de verdad, no entramos en un ciclo

    def __init__(self, url: str, browser: str | None = None, profile_dir: Path | None = None,
                 keep_open: bool = True) -> None:
        self.url = url
        self.browser = browser
        self.profile_dir = profile_dir or default_profile_dir()
        self._process: subprocess.Popen | None = None
        self.exited_by_user = False  # "Salir al escritorio": no la reabrimos sola al cerrar un juego
        self.keep_open = keep_open  # consola: si la ventana se cierra sin "Salir al escritorio", vuelve
        self._reopens: list[float] = []
        self._lock = threading.Lock()

    @property
    def is_open(self) -> bool:
        return self._process is not None and self._process.poll() is None

    def open(self) -> bool:
        with self._lock:
            self.exited_by_user = False
            if self.is_open:
                return system.bring_to_front()
            exe = find_browser(self.browser)
            if not exe:
                log.warning("No encontré Edge/Chrome/Chromium; abre %s manualmente", self.url)
                return False
            self.profile_dir.mkdir(parents=True, exist_ok=True)
            close_orphans(self.profile_dir)
            mark_clean_exit(self.profile_dir)
            self._process = subprocess.Popen(build_command(exe, self.url, self.profile_dir),
                                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            log.info("Interfaz abierta (pid %s)", self._process.pid)
            if self.keep_open:
                threading.Thread(target=self._watch, args=(self._process,), daemon=True).start()
            return True

    def _watch(self, proc: subprocess.Popen) -> None:
        """Si la ventana se cierra sola (o con Alt+F4), la reabre: en modo consola Orbital siempre está."""
        proc.wait()
        time.sleep(self.REOPEN_DELAY)
        with self._lock:
            if self.exited_by_user or self._process is not proc:
                return
            now = time.monotonic()
            self._reopens = [t for t in self._reopens if now - t < 60]
            if len(self._reopens) >= self.MAX_REOPENS:
                log.warning("La ventana de Orbital se cerró %d veces en un minuto; no la reabro", self.MAX_REOPENS)
                return
            self._reopens.append(now)
        log.info("La ventana de Orbital se cerró sin \"Salir al escritorio\": la reabro")
        self.open()

    def close(self) -> bool:
        """Sale al escritorio. Orbital sigue escuchando (Alexa puede volver a abrirla)."""
        with self._lock:
            proc, self._process = self._process, None
            self.exited_by_user = True
        if proc is None or proc.poll() is not None:
            return False
        if sys.platform == "win32":
            # /T cierra también los procesos hijos de Edge (renderizadores, GPU...).
            subprocess.run(["taskkill", "/PID", str(proc.pid), "/T", "/F"], capture_output=True,
                           creationflags=subprocess.CREATE_NO_WINDOW)  # type: ignore[attr-defined]
        else:
            proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
        mark_clean_exit(self.profile_dir)
        return True
