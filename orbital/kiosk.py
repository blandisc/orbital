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
from urllib.parse import urlsplit

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
    "--autoplay-policy=no-user-gesture-required",
    "--overscroll-history-navigation=0",
    # Sin DirectComposition: con el driver AMD de la Legion Go, cada vez que el kiosko a pantalla
    # completa pasa al frente DWM se queda con 34-68 MB que nunca suelta (medido 2026-10-11: +1.3 GB
    # en 30 cambios de foco; con este flag, 0 MB).
    "--disable-direct-composition",
    # Más liviana: la ventana de Orbital no necesita extensiones, sincronizar, barra lateral ni
    # compras. Medido en esta Legion Go: ~120 MB menos y 2 procesos menos (de ~910 MB / 17).
    "--renderer-process-limit=1",
    # El micrófono (dictar en Buscar) sin preguntar cada vez: el quiosco de Edge corre como InPrivate y no hereda el
    # «Permitir» guardado (allow_microphone), así que el aviso salía en cada sesión y con el mando no hay cómo
    # contestarlo. Esta ventana solo abre la página de Orbital; tu Edge normal no cambia.
    "--use-fake-ui-for-media-stream",
    # Menos memoria de video para pintar la interfaz (en la Legion Go sale de la RAM): el presupuesto de mosaicos de la GPU
    # y la caché de imágenes ya decodificadas. Medido en esta Legion Go (ver docs y el commit): sin cambio visible.
    "--force-gpu-mem-available-mb=512",
    "--force-gpu-mem-discardable-limit-mb=128",
    "--disable-extensions",
    "--disable-background-networking",
    "--disable-sync",
    "--disable-default-apps",
    "--no-pings",
    # Sin los botones que Edge pone sobre las imágenes (búsqueda visual y su engrane) ni el mini
    # menú al seleccionar texto: en una consola solo confunden. La página además los evita (base.css).
    "--disable-features=Translate,msEdgeSidebarV2,msShoppingTrigger,EdgeCollections,"
    "msVisualSearch,msEdgeVisualSearch,msImageHoverMenu,msQuickSearchMiniMenu,msEdgeMiniMenu",
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


def allow_microphone(profile_dir: Path, url: str) -> bool:
    """Deja el micrófono permitido para la página de Orbital (y solo para ella) en su perfil: dictar
    en Buscar ya no muestra el aviso «¿Permitir el micrófono?» (con el mando no hay cómo contestarlo).
    Es la misma preferencia que guarda Edge al elegir «Permitir»; si el perfil aún no existe, se crea."""
    parts = urlsplit(url)
    if not parts.scheme or not parts.netloc:
        return False
    origin = f"{parts.scheme}://{parts.netloc}"
    prefs = profile_dir / "Default" / "Preferences"
    try:
        data = json.loads(prefs.read_text(encoding="utf-8")) if prefs.exists() else {}
        exceptions = data.setdefault("profile", {}).setdefault("content_settings", {}).setdefault("exceptions", {})
        mic = exceptions.setdefault("media_stream_mic", {})
        key = f"{origin},*"
        if mic.get(key, {}).get("setting") == 1:
            return True
        mic[key] = {"last_modified": str(int(time.time() * 1_000_000)), "setting": 1}  # 1 = Permitir
        prefs.parent.mkdir(parents=True, exist_ok=True)
        prefs.write_text(json.dumps(data), encoding="utf-8")
        return True
    except (OSError, ValueError) as exc:
        log.debug("No se pudo permitir el micrófono en %s: %s", prefs, exc)
        return False


def build_command(browser: str, url: str, profile_dir: Path) -> list[str]:
    return [browser, f"--user-data-dir={profile_dir}", "--kiosk", url, *FLAGS]


def close_orphans(profile_dir: Path) -> int:
    """Cierra ventanas de Orbital que quedaron de una sesión anterior (mismo perfil). Si no,
    Edge le pasa la página a esa ventana vieja y la nueva se cierra al instante. Nunca toca tu
    Edge normal: solo procesos con el perfil propio de Orbital."""
    if sys.platform != "win32":
        return 0
    from . import windows

    profile = f"--user-data-dir={profile_dir}".lower()
    pids = []
    for pid, (exe, _parent) in windows.processes().items():
        if exe not in ("msedge.exe", "chrome.exe"):
            continue
        line = windows.command_line(pid).lower()
        if profile in line and "--type=" not in line:  # la ventana principal, no sus procesos hijos
            pids.append(pid)
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
                 keep_open: bool = True, on_closed=None, hide_taskbar: bool = True) -> None:
        self.url = url
        self.browser = browser
        self.profile_dir = profile_dir or default_profile_dir()
        self._process: subprocess.Popen | None = None
        self.exited_by_user = False  # "Salir al escritorio": no la reabrimos sola al cerrar un juego
        self.keep_open = keep_open  # consola: si la ventana se cierra sin "Salir al escritorio", vuelve
        self.on_closed = on_closed  # sin keep_open: cerraste la ventana (Orbital se cierra)
        self._reopens: list[float] = []
        self.hide_taskbar = hide_taskbar  # modo consola: la barra de Windows no se asoma al abrir un juego
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
            allow_microphone(self.profile_dir, self.url)
            self._process = subprocess.Popen(build_command(exe, self.url, self.profile_dir),
                                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            log.info("Interfaz abierta (pid %s)", self._process.pid)
            self._console_taskbar(hidden=True)
            if sys.platform == "win32":
                threading.Thread(target=self._brand, args=(self._process,), daemon=True, name="kiosk-icon").start()
            if self.keep_open or self.on_closed:
                threading.Thread(target=self._watch, args=(self._process,), daemon=True).start()
            return True

    APP_ID = "Orbital.Consola"
    ICON = Path(__file__).parent / "web" / "icons" / "orbital.ico"

    def _brand(self, proc: subprocess.Popen) -> None:
        """Abajo, en la barra de tareas, «Orbital» con su ícono (no el de Edge, agrupada con tu Edge normal). La ventana
        tarda en aparecer y Edge puede volver a ponerle su ícono al cargar: se aplica unas veces en los primeros segundos."""
        from . import windows

        profile = f"--user-data-dir={self.profile_dir}".lower()
        startup = Path(os.environ.get("APPDATA", "")) / "Microsoft" / "Windows" / "Start Menu" / "Programs" / "Startup" / "Orbital.lnk"
        command = f'explorer.exe "{startup}"' if startup.exists() else f'"{sys.executable}" -m orbital'
        done = False
        for wait in (1, 2, 3, 4, 10, 20):
            time.sleep(wait)
            if proc.poll() is not None and self._process is not proc:
                return
            pids = {pid for pid, (exe, _parent) in windows.processes().items()
                    if exe in ("msedge.exe", "chrome.exe") and profile in windows.command_line(pid).lower()}
            hwnd = windows.main_window(pids)
            if hwnd and windows.set_app_identity(hwnd, self.APP_ID, str(self.ICON), "Orbital", command) and not done:
                log.info("Ventana de Orbital con su propio ícono en la barra de tareas")
                done = True

    def _watch(self, proc: subprocess.Popen) -> None:
        """Si la ventana se cierra sola (o con Alt+F4), la reabre: en modo consola Orbital siempre está."""
        proc.wait()
        time.sleep(self.REOPEN_DELAY)
        with self._lock:
            if self.exited_by_user or self._process is not proc:
                return  # "Salir al escritorio" u otra ventana nueva: no es que la cerraste
        if not self.keep_open:
            log.info("Cerraste la ventana de Orbital: Orbital se cierra (no se reabre sola)")
            self._console_taskbar(hidden=False)
            if self.on_closed:
                self.on_closed()
            return
        with self._lock:
            now = time.monotonic()
            self._reopens = [t for t in self._reopens if now - t < 60]
            if len(self._reopens) >= self.MAX_REOPENS:
                log.warning("La ventana de Orbital se cerró %d veces en un minuto; no la reabro", self.MAX_REOPENS)
                return
            self._reopens.append(now)
        log.info("La ventana de Orbital se cerró sin \"Salir al escritorio\": la reabro")
        self.open()

    def _console_taskbar(self, hidden: bool) -> None:
        """Modo consola: sin la barra de tareas de Windows (ver windows.set_taskbar_visible); al salir, de regreso."""
        if sys.platform != "win32" or not self.hide_taskbar:
            return
        from . import windows

        try:
            if windows.set_taskbar_visible(not hidden) and hidden:
                log.info("Modo consola: barra de tareas escondida")
        except OSError as exc:
            log.debug("No pude %s la barra de tareas: %s", "esconder" if hidden else "mostrar", exc)

    def close(self) -> bool:
        """Sale al escritorio. Orbital sigue escuchando (Alexa puede volver a abrirla)."""
        self._console_taskbar(hidden=False)  # en el escritorio, la barra de siempre
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
