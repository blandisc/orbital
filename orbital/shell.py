"""Comportamiento de "consola": ir y volver entre Orbital y el juego con el mando.

  * Home (o Legion L): desde el juego -> Orbital; desde Orbital -> de vuelta al juego.
  * Select + Start mantenidos en el juego -> aviso encima del juego (sin salir de él) con una
    barra que se llena; al completarse, el emulador se cierra de golpe y vuelves a Orbital.
    Soltar antes = no pasa nada. Sostenerlo 1,5 s ya es la confirmación: sin "¿Seguro?".

Las ventanas se manejan con `orbital.windows`; se puede inyectar otro objeto en pruebas.
"""

from __future__ import annotations

import logging
import subprocess
import sys
import threading
import time

from . import windows
from .gamepad import HOLD_ARM, HOLD_TOTAL, GamepadWatcher
from .library.detect import KNOWN

log = logging.getLogger(__name__)

BROWSERS = {"msedge.exe", "chrome.exe", "chromium.exe"}
EMULATOR_EXES = {n for k in KNOWN for n in k.exe_names if n.endswith(".exe")} | {
    "retroarch.exe", "citron.exe", "sudachi.exe", "yuzu.exe", "rpcs3.exe", "duckstation-qt-x64-releaseltcg.exe",
}
LEGION_SPACE = "legionspace.exe"
# Nunca se cierran con Select+Start aunque Steam tenga un juego abierto.
NOT_GAMES = BROWSERS | {"steam.exe", "steamwebhelper.exe", "explorer.exe", "es-de.exe", LEGION_SPACE,
                        "claude.exe", "discord.exe", "python.exe", "pythonw.exe"}
APP_NAMES = {"chrome": "Chrome", "msedge": "Edge", "stremio-shell-ng": "Stremio", "steamwebhelper": "Steam",
             "steam": "Steam", "es-de": "ES-DE", "discord": "Discord", "explorer": "Explorador", "eden": "Eden",
             "ryujinx": "Ryujinx", "dolphin": "Dolphin", "mgba": "mGBA", "xemu": "xemu", "ppssppwindows64": "PPSSPP"}
LEGION_DOUBLE_PRESS = 3.0  # s: dos toques de Legion L dejan abierto Legion Space


class ConsoleShell:
    def __init__(self, catalog, kiosk=None, win=windows, overlay=None) -> None:
        self.catalog = catalog
        self.kiosk = kiosk
        self.win = win
        self.overlay = overlay  # GameOverlay (aviso encima del juego); se crea en start()
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
        """Qué se cerraría con Select+Start: el juego que lanzó Orbital, un emulador al frente o
        el juego de Steam en curso (Steam lo reporta y su ventana es la que está al frente)."""
        running = self.catalog.launcher.status()
        if running and running.get("managed"):
            return {"title": running["title"], "runner": running.get("runner"), "pid": None}
        pid = self.win.pid_of(hwnd)
        exe = self.win.exe_name(pid)
        if exe in EMULATOR_EXES:
            name = exe.removesuffix(".exe")
            return {"title": self.win.title(hwnd) or name, "runner": name.capitalize(), "pid": pid}
        if exe and exe not in NOT_GAMES and self.steam_running():
            return {"title": self.win.title(hwnd) or "el juego", "runner": None, "pid": pid}
        return None

    @staticmethod
    def steam_running() -> bool:
        from .launcher import steam_running_appid
        return bool(steam_running_appid())

    def hold_start(self) -> None:
        fg = self.win.foreground()
        if self.is_orbital(fg):
            return  # en Orbital, Select/Start son el menú normal
        target = self.target(fg)
        if target is None:
            return
        self.hold = target
        self.remember(fg)
        if self.overlay:
            runner = target.get("runner") or "el juego"
            self.overlay.show(f"Mantén para cerrar {runner}", target["title"], int((HOLD_TOTAL - HOLD_ARM) * 1000))

    def hold_cancel(self) -> None:
        if self.hold is None:
            return
        self.hold = None
        if self.overlay:
            self.overlay.hide()  # nunca saliste del juego

    def hold_complete(self) -> None:
        target = self.hold
        if target is None:
            return
        if self.overlay:
            self.overlay.closing(f"Cerrando {target.get('runner') or 'el juego'}")
        self.stop_game()
        if self.overlay:
            self.overlay.hide(delay_ms=350)
        if target.get("pid"):
            # Abierto desde ES-DE: nadie vigila su proceso, así que traemos Orbital nosotros.
            # (Si lo lanzó Orbital, vuelve solo al terminar el proceso, con el tiempo jugado.)
            self.show_orbital()

    def stop_game(self) -> bool:
        """Cierra el juego de golpe (ya se confirmó: menú de Orbital o Select+Start sostenidos)."""
        target, self.hold = self.hold, None
        if self.catalog.launcher.stop(force=True):
            return True
        if target and target.get("pid") and sys.platform == "win32":
            subprocess.run(["taskkill", "/PID", str(target["pid"]), "/T", "/F"], capture_output=True,
                           creationflags=subprocess.CREATE_NO_WINDOW)  # type: ignore[attr-defined]
            return True
        return False

    def on_gamepad(self, event: str) -> None:
        {"home": self.home, "hold-start": self.hold_start, "hold-cancel": self.hold_cancel,
         "hold-complete": self.hold_complete}[event]()

    # --------------------------------------------------------------- ventanas abiertas
    def open_windows(self) -> list[dict]:
        """Apps y juegos abiertos (sin Orbital), para saltar entre ellos con el mando."""
        items = []
        for w in self.win.app_windows():
            if self.is_orbital(w["hwnd"]):
                continue
            exe = w["exe"].removesuffix(".exe")
            items.append({"id": w["hwnd"], "app": APP_NAMES.get(exe, exe.replace("-", " ").title()), "title": w["title"]})
        return items

    def focus_window(self, hwnd: int) -> bool:
        # Solo ventanas que están en la lista ahora: nunca un identificador arbitrario.
        if hwnd not in {w["id"] for w in self.open_windows()}:
            return False
        self.remember(hwnd)
        return self.win.focus(hwnd)

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
        if self.overlay is None:
            from .overlay import GameOverlay
            overlay = GameOverlay()
            self.overlay = overlay if overlay.start() else None
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
