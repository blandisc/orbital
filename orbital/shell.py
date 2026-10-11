"""Comportamiento de "consola": ir y volver entre Orbital y el juego con el mando.

  * Home (o Legion L): desde el juego -> Orbital; desde Orbital -> de vuelta al juego.
  * Select + Start mantenidos en el juego -> aviso encima del juego (sin salir de él) con una
    barra que se llena; al completarse, el emulador se cierra de golpe y vuelves a Orbital.
    Soltar antes = no pasa nada. Sostenerlo 1,5 s ya es la confirmación: sin "¿Seguro?".

Las ventanas se manejan con `orbital.windows`; se puede inyectar otro objeto en pruebas.
"""

from __future__ import annotations

import json
import logging
import subprocess
import sys
import threading
import time

from . import windows
from .gamepad import HOLD_ARM, HOLD_TOTAL, GamepadWatcher, KeyRemote, send_key
from .library.detect import KNOWN

log = logging.getLogger(__name__)

BROWSERS = {"msedge.exe", "chrome.exe", "chromium.exe"}
EMULATOR_EXES = {n for k in KNOWN for n in k.exe_names if n.endswith(".exe")} | {
    "retroarch.exe", "citron.exe", "sudachi.exe", "yuzu.exe", "rpcs3.exe", "duckstation-qt-x64-releaseltcg.exe",
    "stremio-shell-ng.exe", "stremio.exe", "geforcenowstreamer.exe", "mpv.exe",
}
PLAYER_EXE = "mpv.exe"  # el reproductor de Orbital: se maneja por su tubería, no con teclas
LEGION_SPACE = "legionspace.exe"
# Pausa universal al ir a Orbital: solo emuladores (los juegos en línea perderían la conexión y
# congelar Stremio dejaría su ventana trabada).
NO_PAUSE = {"stremio-shell-ng.exe", "stremio.exe", "geforcenowstreamer.exe", PLAYER_EXE}  # congelar la nube = desconectarte

# Apps sin soporte de mando: mientras están al frente, el mando se traduce a teclas.
REMOTE_APPS = {"stremio-shell-ng.exe", "stremio.exe"}
# Nunca se cierran con Select+Start aunque Steam tenga un juego abierto.
# Partes de Windows (escritorio, barra de tareas, menú Inicio, teclado táctil, bloqueo): Home desde
# ahí lleva a Orbital, pero Orbital nunca "regresa" a ellas como si fueran un juego.
SHELL_EXES = {"explorer.exe", "searchhost.exe", "startmenuexperiencehost.exe", "shellexperiencehost.exe",
              "textinputhost.exe", "lockapp.exe", "applicationframehost.exe"}
NOT_GAMES = BROWSERS | {"steam.exe", "steamwebhelper.exe", "explorer.exe", "es-de.exe", LEGION_SPACE,
                        "claude.exe", "discord.exe", "python.exe", "pythonw.exe"}
APP_NAMES = {"chrome": "Chrome", "msedge": "Edge", "stremio-shell-ng": "Stremio", "steamwebhelper": "Steam",
             "steam": "Steam", "es-de": "ES-DE", "discord": "Discord", "explorer": "Explorador", "eden": "Eden",
             "ryujinx": "Ryujinx", "dolphin": "Dolphin", "mgba": "mGBA", "xemu": "xemu", "ppssppwindows64": "PPSSPP", "mpv": "Reproductor"}
LEGION_DOUBLE_PRESS = 3.0  # s: dos toques de Legion L dejan abierto Legion Space


class ConsoleShell:
    def __init__(self, catalog, kiosk=None, win=windows, overlay=None, pause_file=None) -> None:
        self.catalog = catalog
        self.kiosk = kiosk
        self.win = win
        self.paused: set[int] = set()  # procesos congelados al ir a Orbital (se descongelan al volver)
        self.paused_since: float | None = None  # desde cuándo (un juego olvidado se cierra solo)
        self.pause_file = pause_file  # si Orbital se cierra de golpe, al arrancar los descongela
        self.overlay = overlay  # GameOverlay (aviso encima del juego); se crea en start()
        self.return_to = 0  # ventana del juego a la que volver
        self.hold: dict | None = None  # juego que se está por cerrar (Select+Start)
        self._remotes = [KeyRemote() for _ in range(4)]
        self._fg_cache = (0.0, "")  # (cuándo, exe al frente): no preguntar a Windows 240 veces/s
        self._legion_last = 0.0
        self._legion_allowed = False
        self._stop = threading.Event()

    @property
    def player(self):
        return getattr(self.catalog, "player", None)

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
        """Recuerda a qué volver con Home: un juego o una app, nunca el escritorio ni Orbital."""
        if hwnd and not self.is_orbital(hwnd) and self.win.exe_name(self.win.pid_of(hwnd)) not in SHELL_EXES:
            self.return_to = hwnd

    # --------------------------------------------------------------- acciones
    def home(self) -> None:
        fg = self.win.foreground()
        if self.is_orbital(fg):
            if not self.resume():
                log.debug("Home en Orbital sin juego al que volver")
            return
        self.remember(fg)
        self.pause(fg)
        self.show_orbital()

    def resume(self) -> bool:
        """Vuelve al juego (descongelándolo). Devuelve False si no hay juego abierto."""
        self.unpause()
        target = self.game_window()
        if not target:
            return False
        focused = self.win.focus(target)
        if focused and self.player and self.win.exe_name(self.win.pid_of(target)) == PLAYER_EXE:
            self.player.show_progress()  # en pausa, con la barra: A para seguir
        return focused

    # --------------------------------------------------------------- pausa universal
    def pause(self, hwnd: int) -> bool:
        """Congela el emulador al frente: imagen, sonido y lógica se detienen al instante, sea cual sea."""
        pid = self.win.pid_of(hwnd)
        exe = self.win.exe_name(pid)
        if exe == PLAYER_EXE and self.player:
            self.player.pause()  # un video se pausa normal (congelarlo cortaría el streaming)
            return False
        if exe not in EMULATOR_EXES or exe in NO_PAUSE:
            return False
        pids = self.win.process_tree(pid)
        if self.win.suspend(pids):
            self.paused |= pids
            self.paused_since = self.paused_since or time.monotonic()
            self._save_paused()
            log.info("En pausa: %s", self.win.title(hwnd))
            return True
        return False

    def unpause(self) -> None:
        if self.paused:
            self.win.resume(self.paused)
            log.info("Fuera de pausa")
            self.paused = set()
            self.paused_since = None
            self._save_paused()

    @property
    def is_paused(self) -> bool:
        return bool(self.paused)

    def _save_paused(self) -> None:
        if self.pause_file is None:
            return
        try:
            self.pause_file.parent.mkdir(parents=True, exist_ok=True)
            self.pause_file.write_text(json.dumps(sorted(self.paused)), encoding="utf-8")
        except OSError as exc:
            log.warning("No pude guardar la pausa: %s", exc)

    def recover_paused(self) -> None:
        """Si Orbital se cerró con un juego congelado, lo descongela (si no, quedaría trabado)."""
        if self.pause_file is None or not self.pause_file.exists():
            return
        try:
            pids = set(json.loads(self.pause_file.read_text(encoding="utf-8")))
        except (OSError, ValueError):
            pids = set()
        if pids:
            log.info("Descongelando lo que quedó en pausa: %s", sorted(pids))
            self.win.resume(pids)
        self.pause_file.unlink(missing_ok=True)

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
        self.unpause()  # un proceso congelado no se cierra limpio
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

    # --------------------------------------------------------------- control remoto (Stremio)
    def foreground_exe(self, now: float) -> str:
        if now - self._fg_cache[0] > .25:
            self._fg_cache = (now, self.win.exe_name(self.win.pid_of(self.win.foreground())))
        return self._fg_cache[1]

    def on_buttons(self, slot: int, buttons: int, now: float, send=send_key) -> None:
        """Stremio no tiene soporte de mando: mientras está al frente, A pausa, la cruceta
        adelanta/regresa y sube/baja volumen, Y pantalla completa, B vuelve."""
        exe = self.foreground_exe(now)
        if exe == PLAYER_EXE and self.player:
            self.player.remote.update(buttons, now)
            return
        remote = self._remotes[slot]
        if exe not in REMOTE_APPS:
            remote.reset()
            return
        for vk in remote.update(buttons, now):
            send(vk)

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
        self.recover_paused()
        self.unpin_orbital()
        if self.overlay is None:
            from .overlay import GameOverlay
            overlay = GameOverlay()
            self.overlay = overlay if overlay.start() else None
        GamepadWatcher(self.on_gamepad, self.on_buttons).start()  # sin XInput, Legion L sigue funcionando
        threading.Thread(target=self._watch_foreground, daemon=True, name="legion-l").start()
        return True

    # --------------------------------------------------------------- que nada quede abierto
    @property
    def sessions(self):
        from .config import SessionsConfig
        return getattr(getattr(self.catalog, "config", None), "sessions", None) or SessionsConfig()

    def close_previous(self, new_id: str) -> None:
        """Abrir algo nuevo cierra lo que estaba abierto (Orbital solo vigila uno: el anterior quedaba
        olvidado, congelado, para siempre). La interfaz pregunta antes si era un juego."""
        running = self.catalog.launcher.status()
        if not self.sessions.close_previous or not running or not running.get("managed") or running.get("id") == new_id:
            return
        log.info("Se abre otra cosa: cierro %s", running["title"])
        self.stop_game()

    def check_idle(self, now: float) -> bool:
        """Un juego congelado (saliste con Home) más de `game_idle_minutes` se cierra solo."""
        limit = self.sessions.game_idle_minutes * 60
        if not self.paused or not limit or self.paused_since is None or now - self.paused_since < limit:
            return False
        running = self.catalog.launcher.status()
        title = running["title"] if running else "el juego"
        pids = set(self.paused)
        log.info("%s llevaba %d min congelado: se cierra", title, limit // 60)
        if not self.stop_game() and sys.platform == "win32":  # abierto desde ES-DE: nadie más lo vigila
            for pid in pids:
                subprocess.run(["taskkill", "/PID", str(pid), "/T", "/F"], capture_output=True,
                               creationflags=subprocess.CREATE_NO_WINDOW)  # type: ignore[attr-defined]
        notify = getattr(self.catalog, "_notify", None)
        if notify:
            notify({"type": "toast", "message": f"Cerré {title}: llevaba {limit // 60} min en pausa."})
        return True

    def unpin_orbital(self) -> None:
        """Si Orbital se cerró con la pantalla de carga encima (topmost), que no se quede así."""
        for w in self.win.app_windows():
            if self.is_orbital(w["hwnd"]):
                self.win.set_topmost(w["hwnd"], False)

    def _watch_foreground(self) -> None:
        last = previous = 0
        while not self._stop.wait(0.12):
            try:
                self.check_idle(time.monotonic())
                fg = self.win.foreground()
                if fg == last:
                    continue
                if self.win.exe_name(self.win.pid_of(last)) != LEGION_SPACE:
                    previous = last  # lo que había antes de Legion Space
                last = fg
                if self.paused and self.win.pid_of(fg) in self.paused:
                    self.unpause()  # volvió al juego por su cuenta (Alt+Tab, clic): que siga
                self.check_legion(fg, previous)
            except Exception:  # noqa: BLE001
                log.exception("Error vigilando la ventana al frente")
