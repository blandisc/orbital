"""Comportamiento de "consola": ir y volver entre Orbital y el juego con el mando.

  * Home (o Legion L): desde el juego -> Orbital; desde Orbital -> de vuelta al juego.
  * Select + Start mantenidos en el juego -> Orbital muestra un anillo y luego
    "¿Cerrar el juego?" ("Seguir jugando" es la opción por defecto).

Las ventanas se manejan con `orbital.windows`; se puede inyectar otro objeto en pruebas.
"""

from __future__ import annotations

import logging
import subprocess
import sys
import threading
import time
from collections.abc import Callable

from . import windows
from .gamepad import HOLD_ARM, HOLD_TOTAL, GamepadWatcher
from .library.detect import KNOWN

log = logging.getLogger(__name__)

BROWSERS = {"msedge.exe", "chrome.exe", "chromium.exe"}
EMULATOR_EXES = {n for k in KNOWN for n in k.exe_names if n.endswith(".exe")} | {
    "retroarch.exe", "citron.exe", "sudachi.exe", "yuzu.exe", "rpcs3.exe", "duckstation-qt-x64-releaseltcg.exe",
}
LEGION_SPACE = "legionspace.exe"
LEGION_DOUBLE_PRESS = 3.0  # s: dos toques de Legion L dejan abierto Legion Space


class ConsoleShell:
    def __init__(self, catalog, kiosk=None, publish: Callable[[dict], None] = lambda event: None, win=windows) -> None:
        self.catalog = catalog
        self.kiosk = kiosk
        self.publish = publish
        self.win = win
        self.return_to = 0  # ventana del juego a la que volver
        self.hold: dict | None = None  # juego que se está por cerrar (Select+Start)
        self._legion_last = 0.0
        self._legion_allowed = False
        self._stop = threading.Event()

    # --------------------------------------------------------------- ventanas
    def is_orbital(self, hwnd: int) -> bool:
        return "Orbital" in self.win.title(hwnd) and self.win.exe_name(self.win.pid_of(hwnd)) in BROWSERS

    def show_orbital(self) -> None:
        if self.kiosk is not None:
            self.kiosk.open()  # al frente, o la reabre si alguien la cerró
        else:
            from . import system
            system.bring_to_front()

    def game_window(self) -> int:
        """Ventana del juego: la que estaba al frente al venir a Orbital, o la del proceso lanzado."""
        if self.win.is_window(self.return_to) and not self.is_orbital(self.return_to):
            return self.return_to
        running = self.catalog.launcher.status()
        if running and running.get("pid"):
            return self.win.main_window(self.win.process_tree(running["pid"]))
        return 0

    def remember(self, hwnd: int) -> None:
        if hwnd and not self.is_orbital(hwnd):
            self.return_to = hwnd

    # --------------------------------------------------------------- acciones
    def home(self) -> None:
        fg = self.win.foreground()
        if self.is_orbital(fg):
            if not self.resume():
                log.debug("Home en Orbital sin juego al que volver")
            return
        self.remember(fg)
        self.show_orbital()

    def resume(self) -> bool:
        """Vuelve al juego. Devuelve False si no hay juego abierto."""
        target = self.game_window()
        if not target:
            return False
        return self.win.focus(target)

    def target(self, hwnd: int) -> dict | None:
        """Qué se cerraría con Select+Start: el juego que lanzó Orbital o un emulador al frente."""
        running = self.catalog.launcher.status()
        if running and running.get("managed"):
            return {"title": running["title"], "runner": running.get("runner"), "pid": None}
        pid = self.win.pid_of(hwnd)
        exe = self.win.exe_name(pid)
        if exe in EMULATOR_EXES:
            name = exe.removesuffix(".exe")
            return {"title": self.win.title(hwnd) or name, "runner": name.capitalize(), "pid": pid}
        return None

    def hold_start(self) -> None:
        fg = self.win.foreground()
        if self.is_orbital(fg):
            return  # en Orbital, Select/Start son el menú normal
        target = self.target(fg)
        if target is None:
            return
        self.hold = target
        self.remember(fg)
        self.show_orbital()
        self.publish({"type": "hold", "phase": "start", "title": target["title"],
                      "ms": int((HOLD_TOTAL - HOLD_ARM) * 1000)})

    def hold_cancel(self) -> None:
        if self.hold is None:
            return
        self.hold = None
        self.publish({"type": "hold", "phase": "cancel"})
        self.resume()

    def hold_complete(self) -> None:
        if self.hold is None:
            return
        self.publish({"type": "confirm-stop", "title": self.hold["title"], "runner": self.hold.get("runner")})

    def stop_game(self) -> bool:
        target, self.hold = self.hold, None
        if self.catalog.launcher.stop():
            return True
        if target and target.get("pid") and sys.platform == "win32":
            subprocess.run(["taskkill", "/PID", str(target["pid"]), "/T"], capture_output=True,
                           creationflags=subprocess.CREATE_NO_WINDOW)  # type: ignore[attr-defined]
            return True
        return False

    def on_gamepad(self, event: str) -> None:
        {"home": self.home, "hold-start": self.hold_start, "hold-cancel": self.hold_cancel,
         "hold-complete": self.hold_complete}[event]()

    # --------------------------------------------------------------- Legion L
    def check_legion(self, fg: int, previous: int, now: float | None = None) -> None:
        """Legion L abre Legion Space: lo minimizamos y hacemos lo mismo que Home, tomando
        como punto de partida la ventana que estaba al frente antes (`previous`).
        Dos toques seguidos (menos de 3 s) dejan Legion Space abierto."""
        now = time.monotonic() if now is None else now
        if self.win.exe_name(self.win.pid_of(fg)) != LEGION_SPACE:
            self._legion_allowed = False
            return
        if self._legion_allowed:
            return
        if now - self._legion_last < LEGION_DOUBLE_PRESS:
            self._legion_allowed = True
            log.info("Doble Legion L: se queda Legion Space")
            return
        self._legion_last = now
        self.win.minimize(fg)
        if self.is_orbital(previous):
            self.resume()
        else:
            self.remember(previous)
            self.show_orbital()

    # --------------------------------------------------------------- arranque
    def start(self) -> bool:
        if sys.platform != "win32":
            return False
        GamepadWatcher(self.on_gamepad).start()  # sin XInput, Legion L sigue funcionando
        threading.Thread(target=self._watch_foreground, daemon=True, name="legion-l").start()
        return True

    def _watch_foreground(self) -> None:
        last = previous = 0
        while not self._stop.wait(0.12):
            try:
                fg = self.win.foreground()
                if fg == last:
                    continue
                if self.win.exe_name(self.win.pid_of(last)) != LEGION_SPACE:
                    previous = last  # lo que había antes de Legion Space
                last = fg
                self.check_legion(fg, previous)
            except Exception:  # noqa: BLE001
                log.exception("Error vigilando la ventana al frente")
