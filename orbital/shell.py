"""Comportamiento de "consola": ir y volver entre Orbital y el juego con el mando.

  * Home (o un toque de Legion L): desde el juego -> Orbital; desde Orbital -> de vuelta al juego.
  * Legion L dos veces seguidas desde un juego -> se cierra (el primer toque ya te trajo a Orbital).
  * El atajo de cerrar mantenido en el juego (Start + Select + Home; GameSir: LB + RB + Select) -> aviso encima del juego (sin salir de él) con una
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
LEGION_DOUBLE_PRESS = 2.0  # s: dos toques de Legion L desde un juego lo cierran
IDLE_WARNING = 600  # s antes de cerrar un juego olvidado: se avisa
SLEEP_CHECK = 5.0  # s entre comprobaciones de si la consola estuvo suspendida
SLEEP_GAP = 30.0  # s de más: más que esto entre dos comprobaciones = estuvo dormida


def was_asleep(last: float, now: float, every: float = SLEEP_CHECK, gap: float = SLEEP_GAP) -> bool:
    return now - last > every + gap


class ConsoleShell:
    def __init__(self, catalog, kiosk=None, win=windows, overlay=None, pause_file=None) -> None:
        self._idle_warned = False
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
        self._pads: dict[int, int] = {}  # botones de cada puerto, para el reproductor (los junta)
        self._fg_cache = (0.0, "")  # (cuándo, exe al frente): no preguntar a Windows 240 veces/s
        self._refocus_at = 0.0  # la última vez que se le devolvió el foco al video (ver _video_lost_focus)
        self._legion_last = 0.0
        self._legion_left: dict | None = None  # el juego que dejaste con Legion L (para el 2.º toque)
        self._last_buttons: dict[int, int] = {}  # por puerto, para ver cuándo se presiona algo (wake_on_button)
        self._woke_at = -999.0
        self.health = None  # HealthMonitor (memoria); se crea en start()
        self._stop = threading.Event()

    def notify(self, event: dict) -> None:
        """Aviso para la interfaz (por el catálogo, que lo reparte a quien escuche)."""
        notify = getattr(self.catalog, "notify", None)
        if callable(notify):
            notify(event)

    @property
    def player(self):
        return getattr(self.catalog, "player", None)

    # --------------------------------------------------------------- ventanas
    def is_orbital(self, hwnd: int) -> bool:
        return "Orbital" in self.win.title(hwnd) and self.win.exe_name(self.win.pid_of(hwnd)) in BROWSERS

    def show_orbital(self) -> None:
        self.mark_returned()  # siempre es porque tú lo pediste (Home, Legion L, cerrar el juego)
        if self.kiosk is not None:
            self.kiosk.open()  # al frente, o la reabre si alguien la cerró
        else:
            from . import system
            system.bring_to_front()

    def game_window(self) -> int:
        """Ventana del juego: la del juego que lanzó Orbital (si sigue abierto) o, si no, la que estaba
        al frente al venir a Orbital. Antes mandaba la recordada: si llegabas a Orbital sin pasar por
        el juego (te tapó al abrir), "Volver al juego" iba a una ventana vieja (GeForce NOW…)."""
        remembered = self.return_to if self.win.is_window(self.return_to) and not self.is_orbital(self.return_to) else 0
        running = self.catalog.launcher.status()
        if running and running.get("pid"):
            pids = self.win.process_tree(running["pid"])
            if remembered and self.win.pid_of(remembered) in pids:
                return remembered
            game = self.win.main_window(pids)
            if game:
                return game
        return remembered

    def remember(self, hwnd: int) -> None:
        """Recuerda a qué volver con Home: un juego o una app, nunca el escritorio ni Orbital."""
        if hwnd and not self.is_orbital(hwnd) and self.win.exe_name(self.win.pid_of(hwnd)) not in SHELL_EXES:
            self.return_to = hwnd

    # --------------------------------------------------------------- acciones
    def mark_returned(self) -> None:
        """Pediste ir a Orbital: que nadie te regrese al juego por su cuenta."""
        sessions = getattr(self.catalog, "sessions", None)
        if sessions is not None:
            sessions.returned_at = time.monotonic()

    def home(self) -> None:
        self.mark_returned()  # también Home estando en Orbital (vuelve al juego, no hay que regresarte)
        fg = self.win.foreground()
        if self.is_orbital(fg):
            if not self.resume():
                log.debug("Home en Orbital sin juego al que volver")
            return
        self.remember(fg)
        log.info("Home: de %s a Orbital", self.win.title(fg) or self.win.exe_name(self.win.pid_of(fg)))
        if self._video_to_corner(fg):
            self.show_orbital()
            return
        self.pause(fg)
        self.show_orbital()

    def _video_to_corner(self, hwnd: int) -> bool:
        """Home con un video al frente y Ajustes › «Home durante un video: En pequeño»: el video se va a una esquina y
        sigue (en vez de pausarse)."""
        if not self.player or self.win.exe_name(self.win.pid_of(hwnd)) != PLAYER_EXE:
            return False
        state = getattr(self.catalog, "state", None)
        if (state.settings().get("video_home", "pip") if state is not None else "pip") != "pip":
            return False
        enter = getattr(self.player, "enter_pip", None)
        if not (enter and enter()):
            return False
        # Orbital dice cómo regresar (antes, ya en chiquito, no se sabía): Home lo vuelve a pantalla completa.
        events = getattr(self.catalog, "events", None)
        current = getattr(self.player, "current", None)
        if events is not None:
            events.publish({"type": "pip", "title": getattr(current, "title", "") or "El video"})
        return True

    def resume(self) -> bool:
        """Vuelve al juego (descongelándolo). Devuelve False si no hay juego abierto."""
        self.unpause()
        if self.player and getattr(self.player, "pip", False):
            self.player.exit_pip()  # el video en pequeño vuelve a pantalla completa
        target = self.game_window()
        if not target:
            return False
        focused = self.win.focus(target)
        log.info("Volver al juego: %s%s", self.win.title(target), "" if focused else " (Windows no lo dejó al frente)")
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
            loaded = json.loads(self.pause_file.read_text(encoding="utf-8"))
            # Solo una lista de números de proceso; cualquier otra cosa se ignora (y el archivo se borra).
            pids = {p for p in loaded if isinstance(p, int) and not isinstance(p, bool) and p > 0} if isinstance(loaded, list) else set()
        except (OSError, ValueError, TypeError):
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
            # El juego en grande y qué mantener (el atajo del mando que lo está haciendo: el GameSir no usa Home).
            label = getattr(getattr(self, "gamepad", None), "hold_label", "")
            self.overlay.show(target["title"], f"Mantén {label} para cerrar" if label else "Sigue manteniendo para cerrar",
                              int((HOLD_TOTAL - HOLD_ARM) * 1000))

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
            self.overlay.closing(f"Cerrando {target['title']}", target.get("runner") or "")
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
        running = self.catalog.launcher.status()
        player = getattr(getattr(self.catalog, "watch", None), "player", None)
        if running and running.get("id") == "media:player" and player is not None:
            player._user_quit = True  # lo cerraste tú: no es «No pude reproducir»
        if self.catalog.launcher.stop(force=True):
            return True
        if target and target.get("pid") and sys.platform == "win32":
            subprocess.run(["taskkill", "/PID", str(target["pid"]), "/T", "/F"], capture_output=True,
                           creationflags=subprocess.CREATE_NO_WINDOW)  # type: ignore[attr-defined]
            return True
        return False

    def on_gamepad(self, event: str) -> None:
        {"home": self.home, "hold-start": self.hold_start, "hold-cancel": self.hold_cancel,
         "hold-complete": self.hold_complete, "quick": self.quick_panel, "capture": self.capture}[event]()

    def quick_panel(self) -> None:
        """Home + LB: el panel rápido (brillo, volumen, energía…). Desde un juego, primero a Orbital."""
        if not self.is_orbital(self.win.foreground()):
            self.home()
        self.notify({"type": "open-quick"})

    def capture(self) -> None:
        """Home + RB: captura de lo que está en pantalla (el juego), sin salir de él."""
        from . import capture

        threading.Thread(target=lambda: self.notify(capture.take_and_describe()), daemon=True,
                         name="capture").start()

    # --------------------------------------------------------------- control remoto (Stremio)
    def foreground_exe(self, now: float) -> str:
        if now - self._fg_cache[0] > .25:
            self._fg_cache = (now, self.win.exe_name(self.win.pid_of(self.win.foreground())))
        return self._fg_cache[1]

    def _video_lost_focus(self, now: float) -> bool:
        """El video se ve al frente, pero Windows dejó el foco en Orbital (detrás): el mando y el teclado
        le hablaban a Orbital y el video «solo funcionaba con teclado» tras hacer clic. Si no volviste a
        Orbital desde que empezó el video, el foco regresa al video. True si lo intentó."""
        player = self.player
        current = getattr(player, "current", None) if getattr(player, "playing", False) else None
        if current is None or now < self._refocus_at:
            return False
        fg = self.win.foreground()
        if not self.is_orbital(fg):
            return False
        sessions = getattr(self.catalog, "sessions", None)
        returned = getattr(sessions, "returned_at", 0.0) or 0.0
        if returned and time.time() - (time.monotonic() - returned) > current.started:
            return False  # tú volviste a Orbital (Home): ahí se queda
        video = self.win.main_window(self.win.process_tree(current.process.pid))
        if not video:
            return False
        self._refocus_at = now + 1.0
        log.info("El video estaba al frente sin el foco: se lo devuelvo")
        self.win.focus(video)
        return True

    WAKE_EVERY = 2.0  # s: un botón trae a Orbital al frente a lo más una vez en ese rato

    def wake_on_button(self, slot: int, buttons: int, now: float) -> bool:
        """Los controles de la Legion Go no tienen Home: si otra ventana le quitó el foco a Orbital (el escritorio, una app)
        y no hay nada abierto por Orbital, cualquier botón la trae al frente. Nunca encima de algo a pantalla completa
        (un juego abierto por fuera de Orbital), de Stremio, de Legion Space o si saliste al escritorio a propósito."""
        if not hasattr(self, "_last_buttons"):  # pruebas que arman el shell sin __init__
            self._last_buttons, self._woke_at = {}, -999.0
        pressed = buttons and not self._last_buttons.get(slot)
        self._last_buttons[slot] = buttons
        kiosk = getattr(self, "kiosk", None)
        if not pressed or kiosk is None or getattr(kiosk, "exited_by_user", False) or now - self._woke_at < self.WAKE_EVERY:
            return False
        if self.catalog.launcher.status():
            return False  # un juego, un video o una app de Orbital: Home y Legion L ya saben volver
        fg = self.win.foreground()
        exe = self.win.exe_name(self.win.pid_of(fg)) if fg else ""
        if not fg or self.is_orbital(fg) or exe in (LEGION_SPACE, PLAYER_EXE) or exe in REMOTE_APPS or self.win.is_fullscreen(fg):
            return False  # Stremio y el reproductor usan el mando a través de Orbital (A pausa)
        self._woke_at = now
        log.info("Botón del mando con otra ventana al frente y nada abierto: Orbital al frente")
        kiosk.open()
        return True

    def on_buttons(self, slot: int, buttons: int, now: float, send=send_key) -> None:
        """Stremio no tiene soporte de mando: mientras está al frente, A pausa, la cruceta
        adelanta/regresa y sube/baja volumen, Y pantalla completa, B vuelve."""
        if self.wake_on_button(slot, buttons, now):
            return
        exe = self.foreground_exe(now)
        if buttons and exe != PLAYER_EXE and self._video_lost_focus(now):
            return  # el foco vuelve al video; la siguiente lectura del mando ya le llega a él
        if exe == PLAYER_EXE and self.player:
            # El reproductor tiene UN control remoto y esto llega por cada puerto (los 4, aun vacíos):
            # el puerto vacío "soltaba" la cruceta en cada lectura y una pulsación contaba varias
            # veces (el foco saltaba). Se juntan los botones de todos los puertos.
            self._pads[slot] = buttons
            combined = 0
            for pressed in self._pads.values():
                combined |= pressed
            self.player.remote.update(combined, now)
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
        """Legion L abre Legion Space (no se puede reasignar): Orbital lo esconde al instante y lo usa
        como botón propio, tomando como punto de partida la ventana de antes (`previous`).

          * Un toque: igual que Home (del juego a Orbital, con pausa; de Orbital al juego).
          * Dos toques seguidos desde un juego: se cierra ese juego, sin preguntar (el segundo toque
            es la confirmación; tras el primero, Orbital avisa "Toca otra vez para cerrar…").
        """
        now = time.monotonic() if now is None else now
        if self.win.exe_name(self.win.pid_of(fg)) != LEGION_SPACE:
            return
        self.win.minimize(fg)
        left = self._legion_left
        if left and now - self._legion_last < LEGION_DOUBLE_PRESS:
            self._legion_left = None
            self.hold = self.target(left["hwnd"]) or left["target"]
            log.info("Legion L dos veces: cierro %s", self.hold.get("title"))
            if self.overlay:
                self.overlay.closing(f"Cerrando {self.hold.get('title') or 'el juego'}", self.hold.get("runner") or "")
            self.stop_game()
            if self.overlay:
                self.overlay.hide(delay_ms=350)
            self.show_orbital()
            return
        self._legion_last = now
        self._legion_left = None
        if self.is_orbital(previous):
            self.resume()
            return
        game = self.target(previous)
        self.remember(previous)
        self.pause(previous)
        self.show_orbital()
        if game:
            self._legion_left = {"hwnd": previous, "target": game}
            self.notify({"type": "toast", "message": f"Toca Legion L otra vez para cerrar {game['title']}",
                         "countdown": int(LEGION_DOUBLE_PRESS * 1000)})

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
        self.gamepad = GamepadWatcher(self.on_gamepad, self.on_buttons)
        self.gamepad.start()  # sin XInput, Legion L sigue funcionando
        # El Home del teclado (Ctrl + Inicio): como Home en el mando o un toque de Legion L, aunque el juego tenga el foco.
        from .hotkey import KeyboardHome
        self.keyboard_home = KeyboardHome(self.home)
        self.keyboard_home.start()
        # Memoria (RAM y la de video que usa DWM): se anota cada 5 min y avisa si los juegos no van a poder
        # abrir. Nunca en pleno juego o video: el aviso espera a que Orbital vuelva al frente.
        from .health import HealthMonitor
        running = lambda: (self.catalog.launcher.status() or {}).get("title", "")  # noqa: E731
        self.health = HealthMonitor(self.notify, running, busy=self.away_from_orbital)
        threading.Thread(target=self._watch_foreground, daemon=True, name="legion-l").start()
        threading.Thread(target=self._watch_sleep, daemon=True, name="sleep").start()
        self.health.start()
        return True

    def away_from_orbital(self) -> bool:
        """¿Estás en otra cosa (un juego, un video, otra app)? Orbital no debe asomarse ni avisar."""
        return not self.is_orbital(self.win.foreground())

    # --------------------------------------------------------------- que nada quede abierto
    @property
    def sessions(self):
        """Lo de config.yaml, con lo que cambiaste en Ajustes encima."""
        from dataclasses import replace

        from .config import SessionsConfig
        base = getattr(getattr(self.catalog, "config", None), "sessions", None) or SessionsConfig()
        state = getattr(self.catalog, "state", None)
        saved = state.settings() if state is not None else {}
        return replace(base, **{k: saved[k] for k in ("game_idle_minutes", "video_idle_minutes", "close_previous")
                                if k in saved})

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
        if not self.paused or not limit or self.paused_since is None:
            self._idle_warned = False
            return False
        if now - self.paused_since < limit:
            if limit > IDLE_WARNING and now - self.paused_since >= limit - IDLE_WARNING and not self._idle_warned:
                self._idle_warned = True
                running = self.catalog.launcher.status()
                if running:
                    self.notify({"type": "toast", "tone": "warn", "message": f"{running['title']} se cerrará en {IDLE_WARNING // 60} min",
                                 "detail": "Si no vuelves (Home). Lo no guardado se pierde"})
            return False
        self._idle_warned = False
        running = self.catalog.launcher.status()
        title = running["title"] if running else "el juego"
        pids = set(self.paused)
        log.info("%s llevaba %d min congelado: se cierra", title, limit // 60)
        if not self.stop_game() and sys.platform == "win32":  # abierto desde ES-DE: nadie más lo vigila
            for pid in pids:
                subprocess.run(["taskkill", "/PID", str(pid), "/T", "/F"], capture_output=True,
                               creationflags=subprocess.CREATE_NO_WINDOW)  # type: ignore[attr-defined]
        self.notify({"type": "toast", "message": f"Cerré {title}", "detail": f"Llevaba {limit // 60} min en pausa"})
        return True

    def unpin_orbital(self) -> None:
        """Si Orbital se cerró con la pantalla de carga encima (topmost), que no se quede así."""
        for w in self.win.app_windows():
            if self.is_orbital(w["hwnd"]):
                self.win.set_topmost(w["hwnd"], False)

    # --------------------------------------------------------------- volver de suspender
    def _watch_sleep(self) -> None:
        """Mientras la consola duerme, este hilo no corre: si "despierta" mucho después de lo
        esperado, la consola estuvo suspendida."""
        last = time.time()
        while not self._stop.wait(SLEEP_CHECK):
            now = time.time()
            if was_asleep(last, now):
                try:
                    self.on_resumed(now - last)
                except Exception:  # noqa: BLE001
                    log.exception("Al volver de suspender")
            last = now

    def on_resumed(self, slept: float) -> None:
        """Al despertar: los mandos se vuelven a reconocer, un video queda en pausa (no sigue
        sonando sin que lo veas) y la interfaz se pone al día."""
        log.info("La consola volvió de suspender (%d min dormida)", slept // 60)
        gamepad = getattr(self, "gamepad", None)
        if gamepad is not None:
            gamepad.redetect()
        player = self.player
        if player is not None and getattr(player, "playing", False):
            player.pause()
        self.notify({"type": "resumed", "minutes": int(slept // 60)})
        if self.kiosk is not None and hasattr(self.kiosk, "ensure_shown"):
            # La pantalla pudo cambiar dormida (de la tele a la de la Legion): que la ventana se vea, y al frente si no
            # había nada abierto. Unos segundos después: Windows acomoda las pantallas al despertar.
            front = not self.catalog.launcher.status()
            threading.Timer(4.0, lambda: self.kiosk.ensure_shown(front=front)).start()

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
                if self.health is not None and self.is_orbital(self.win.foreground()):
                    self.health.flush()  # ya estás en Orbital: el aviso de memoria que esperaba
            except Exception:  # noqa: BLE001
                log.exception("Error vigilando la ventana al frente")
