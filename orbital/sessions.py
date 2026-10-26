"""Abrir cosas y saber cuándo terminan: juegos, emuladores, apps, Stremio y GeForce NOW.

Recibe "abre esto", fija la pantalla de carga, lo lanza y lo vigila; al cerrarse guarda el tiempo
jugado, trae Orbital al frente y publica el evento "closed" (lo escuchan la interfaz, Stremio y Steam).
"""

from __future__ import annotations

import errno
import logging
import sys
import threading
import time
from collections.abc import Callable
from pathlib import Path

from . import companion, display, emulator_clock, emulator_input, focus, health, system, title_switch
from .config import Config
from .events import EventBus
from .launcher import Launcher
from .library import cinemeta, geforcenow, steam, stremio
from .library.models import LibraryItem
from .players import players
from .state import State
from .store import ItemStore

log = logging.getLogger(__name__)

GFN_START_TIMEOUT = 60.0  # s para que la app abra el juego (con la app cerrada: ~6 s; con fila de espera, más)
GFN_READY_TIMEOUT = 30.0  # s de pantalla de carga como mucho en GeForce NOW (luego se ve su fila de espera)


def _cloud_game_ready(exe: str) -> bool:
    """El juego de GeForce NOW ya se ve: su ventana está a pantalla completa (antes: la de conexión, chica)."""
    from . import windows

    hwnd = windows.main_window(windows.pids_by_exe(exe))
    # A pantalla completa y con el nombre del juego: la app en su biblioteca también puede estar a pantalla completa.
    return bool(hwnd) and windows.is_fullscreen(hwnd) and geforcenow.in_game_title(windows.title(hwnd))


TASKBAR_BACK_AFTER = 3.0  # s tras la pantalla de carga: el juego ya está en pantalla completa y tapa la barra
_taskbar_holds = 0  # aperturas en curso (dos a la vez: la barra vuelve cuando acaba la última)
_taskbar_lock = threading.Lock()


def taskbar_hidden(fn, *args, **kwargs):
    """Corre `fn` con la barra de tareas de Windows escondida y la regresa unos segundos después. Al abrir un juego, el
    emulador le roba el foco a Orbital con su ventana aún sin pantalla completa y Windows sacaba su barra encima de la
    pantalla de carga. Antes se escondía todo el tiempo y ya nunca se veía, ni en el escritorio."""
    global _taskbar_holds
    from . import windows

    with _taskbar_lock:
        _taskbar_holds += 1
        if _taskbar_holds == 1:
            windows.set_taskbar_visible(False)
    try:
        return fn(*args, **kwargs)
    finally:
        time.sleep(TASKBAR_BACK_AFTER)
        with _taskbar_lock:
            _taskbar_holds -= 1
            if _taskbar_holds == 0:
                windows.set_taskbar_visible(True)

QUICK_EXIT = 15  # s: un juego que se cierra antes, solo, seguramente no pudo abrir
PARK_AFTER = 8.0  # s con el juego al frente antes de cerrar la ventana de Orbital (modo juego)


def memory_problem() -> str | None:
    """El aviso de memoria si ahora mismo falta (la fuga de DWM o RAM casi llena); None si no."""
    from . import health

    try:
        free_mb, dwm, commit = health.free_ram_mb(), health.dwm_gpu_mb(), health.commit_room_mb()
        if not health.needs_warning(free_mb, dwm, commit):
            return None
        return health.warning_message(free_mb, dwm, [] if health.dwm_leak(dwm) else health.top_memory())
    except OSError:
        return None



class NotLaunchable(ValueError):
    """Algo de la biblioteca que no se abre así (la entrada «Buscar», por ejemplo): es un 422, no un 500."""

class Sessions:
    def __init__(self, config: Config, state: State, launcher: Launcher, store: ItemStore, events: EventBus,
                 runner_for: Callable, last_end: Callable[[], dict | None] = lambda: None) -> None:
        self.config = config
        self.state = state
        self.launcher = launcher
        self.store = store
        self.events = events
        self.runner_for = runner_for  # (item, runner_id) -> el emulador a usar (preferencias)
        self.last_end = last_end  # cómo terminó el reproductor ("Terminaste Interstellar")
        self.kiosk = None  # KioskWindow si Orbital abrió la interfaz (la reabre al cerrar un juego)
        # Antes de abrir algo, cerrar lo que estaba abierto (lo pone el servidor: shell.close_previous).
        self.before_launch: Callable[[str], None] | None = None
        self._reveal_skip = threading.Event()
        # El arte de la pantalla de carga (lo avisa la interfaz): cuándo empezó a esperarlo y cuándo ya se vio.
        self._art_pending_at: float | None = None
        self._art_shown_at: float | None = None
        # Por hilo: cada petición sabe si SU lanzamiento tiene pantalla de carga (antes era un solo
        # valor compartido y un lanzamiento por voz en segundo plano podía pisar el de la interfaz).
        self._local = threading.local()
        # El último emulador abierto: si truena al arrancar se reintenta UNA vez (Eden a veces se
        # cierra en el primer intento, sobre todo al volver de suspender, y al segundo abre bien).
        self._last_launch: dict | None = None
        # Un lanzamiento a la vez: A dos veces seguidas (o mando + Alexa) abría dos emuladores.
        self._launch_lock = threading.RLock()
        # Cuándo pediste ir a Orbital (Home, Legion L): el vigilante del foco deja de regresar el juego.
        self.returned_at = 0.0
        launcher.on_exit = self.session_ended
        launcher.on_playtime = self.state.record_session
        launcher.on_timeout = lambda item_id, title: self.events.publish({
            "type": "toast", "ok": False,
            "message": f"{title} no arrancó. Revisa Steam (puede estar actualizando o pidiendo algo en su ventana)."})

    @property
    def revealing(self) -> bool:
        """El último lanzamiento de ESTE hilo tiene pantalla de carga hasta launch-ready."""
        return getattr(self._local, "revealing", False)

    @revealing.setter
    def revealing(self, value: bool) -> None:
        self._local.revealing = value

    def launch(self, item_id: str, runner_id: str | None = None, keep: bool = False,
               retry: bool = False) -> LibraryItem:
        """`keep`: abrir sin cerrar lo que estaba abierto (lo pediste en "¿Cerrar…?"). `retry`: es
        el reintento automático tras tronar al arrancar (no se vuelve a reintentar)."""
        with self._launch_lock:
            return self._launch(item_id, runner_id, keep, retry)

    def _launch(self, item_id: str, runner_id: str | None, keep: bool, retry: bool) -> LibraryItem:
        self.revealing = False
        item = self.store.get(item_id)
        if item is None:
            raise KeyError(item_id)
        # Antes de cerrar lo que estaba abierto: si esto no se puede abrir, no se pierde el juego en curso.
        if runner_id and item.runners and not any(r.id == runner_id for r in item.runners):
            raise NotLaunchable(f"{item.title} no se abre con ese emulador")
        if not self._launchable(item, runner_id):
            raise NotLaunchable(f"{item.title} no tiene forma de lanzarse")
        runner = self.runner_for(item, runner_id)
        running = self.launcher.status()
        if (running and running["id"] == item.id and running.get("pid") and not retry and (runner or item.argv)
                and item.source not in ("stremio", "cinemeta", "geforcenow")
                and (runner is None or running.get("runner") in (None, runner.name))):
            # Ya se está abriendo (aún sin ventana a la cual volver): otra copia quedaría huérfana.
            log.info("%s ya está abierto: no abro otra copia", item.title)
            return item
        argv = runner.argv if runner else item.argv
        if argv and Path(argv[0]).is_absolute() and not Path(argv[0]).exists():
            # El emulador ya no está: se avisa SIN cerrar antes lo que estaba abierto.
            raise FileNotFoundError(errno.ENOENT, "No existe", argv[0])
        if self.before_launch and not keep:
            self.before_launch(item.id)
        if item.source in ("stremio", "cinemeta") or item.id == "media:stremio":
            self.open_stremio(item.uri if item.id != "media:stremio" else None, item.title)
            self.state.record_launch(item.id)
            return item
        if item.source == "geforcenow":
            # La app es de instancia única: se vigila por ejecutable. Los juegos también los abre la app (con su ruta); un
            # juego sigue mientras la ventana de la app lleva su nombre (al salir, la app vuelve a su biblioteca y sigue).
            exe = geforcenow.APP_EXE
            if item.id == "app:geforcenow":
                self.launcher.run(item.argv, cwd=item.cwd)
                self.launcher.track_exe(item.id, item.title, exe, runner="GeForce NOW")
                threading.Thread(target=focus.bring_app_to_front, args=(exe,), daemon=True).start()
            else:
                # Un juego en la nube, como los demás: la pantalla de carga (con su arte) tapa las ventanas de GeForce NOW
                # hasta que el juego está a pantalla completa; si tarda (fila de espera), se ve a los 30 s.
                pinned = self.pin()
                try:
                    self.launcher.run(item.argv, cwd=item.cwd)
                    self.launcher.track_exe(item.id, item.title, exe, runner="GeForce NOW", alive=geforcenow.in_session,
                                            start_timeout=GFN_START_TIMEOUT, on_end=geforcenow.close_app)
                except BaseException:
                    self.unpin(pinned)
                    raise
                self.revealing = self.to_front(item.id, item.title, "GeForce NOW", pinned=pinned,
                                               ready=lambda: _cloud_game_ready(exe), timeout=GFN_READY_TIMEOUT)
            self.state.record_launch(item.id)
            return item
        if runner or item.argv:
            self.lower_resolution()  # los juegos a ~1080p (la tele a 4K le cuesta 4 veces más a la gráfica)
            emulator_clock.sync_for(argv or [])  # su hora, la de la computadora (los de Switch traen la suya)
            # El control con el que lo abriste es el Jugador 1, los demás en el orden en que llegaron (Switch y Dolphin).
            order = players.for_launch()
            emulator_input.arrange_for(argv or [], players.devices(order), slots=order, versions=players.versions())
            # Orbital encima ANTES de lanzar: la ventana del emulador nunca se asoma.
            pinned = self.pin()
            try:
                proc = self.launcher.run(runner.argv if runner else item.argv, cwd=runner.cwd if runner else item.cwd)
            except BaseException:
                self.unpin(pinned)
                raise
            self.launcher.track(item.id, item.title, proc, runner=runner.name if runner else None)
            self._last_launch = {"id": item.id, "runner": runner_id, "retried": retry}
            self.revealing = self.to_front(item.id, item.title, runner.name if runner else None, pinned=pinned)
            self.watch_program_switch(item, runner.argv if runner else item.argv, runner.cwd if runner else item.cwd,
                                      runner.name if runner else None)
        elif item.uri:
            if item.source == "steam" and item.steam_appid:
                self.lower_resolution()
            if item.source == "steam" and item.steam_appid and self.config.steam.silent_start:
                steam.ready_silent(steam.find_steam(self.config.steam.path))
            self.launcher.open_uri(item.uri)
            self.launcher.track(item.id, item.title, None, steam_appid=item.steam_appid)
        else:
            raise NotLaunchable(f"{item.title} no tiene forma de lanzarse")
        self.state.record_launch(item.id)
        return item

    def watch_program_switch(self, item: LibraryItem, argv: list[str], cwd: str | None, runner: str | None) -> None:
        """Xenia: cuando el juego pide abrir su otro programa (Black Ops II, de la campaña a Zombies), Orbital relanza Xenia
        y lo vuelve a traer al frente; antes había que pulsar OK, salir y abrirlo otra vez (ver title_switch)."""
        folder = title_switch.xenia_dir(argv)
        if folder is None:
            return

        def still_playing() -> bool:
            status = self.launcher.status()
            return bool(status and status.get("id") == item.id)

        def relaunch(module: str) -> None:
            # La pantalla de carga del juego por si Windows pone a Orbital al frente al cerrarse el Xenia viejo.
            self.events.publish({"type": "switching", "id": item.id, "title": item.title, "detail": title_switch.program_name(module)})
            if self.launcher.relaunch(item.id, argv, cwd=cwd):
                self.to_front(item.id, item.title, runner)

        title_switch.start(folder, still_playing, relaunch)

    def _launchable(self, item: LibraryItem, runner_id: str | None) -> bool:
        if item.source in ("stremio", "cinemeta", "geforcenow") or item.id == "media:stremio":
            return True
        return bool(item.argv or item.uri or self.runner_for(item, runner_id))

    @staticmethod
    def pin() -> int | None:
        """Fija Orbital encima (si está al frente) antes de lanzar algo. None fuera de Windows."""
        return focus.pin_orbital() if sys.platform == "win32" else None

    @staticmethod
    def unpin(pinned: int | None) -> None:
        if pinned and sys.platform == "win32":
            from . import windows
            windows.set_topmost(pinned, False)

    def to_front(self, item_id: str, title: str = "", runner: str | None = None, pinned: int | None = None,
                 ready=None, timeout: float = focus.READY_TIMEOUT) -> bool:
        """Pantalla de carga hasta que el juego esté listo (ver bring_game_to_front). Devuelve si la
        interfaz debe esperar el evento launch-ready en lugar de esconder "Abriendo" sola."""
        if sys.platform != "win32":
            return False
        self._reveal_skip = threading.Event()
        launched = time.monotonic()
        health.note_dwm(f"antes de abrir {title}")

        def reveal(*args, **kwargs):
            shown = taskbar_hidden(focus.bring_game_to_front, *args, **kwargs)
            health.note_dwm(f"con {title} al frente")
            if shown:
                self.park_soon(item_id)
            return shown

        threading.Thread(target=reveal, args=(self.launcher, item_id, title, runner),
                         kwargs={"notify": self.events.publish, "skip": self._reveal_skip, "pinned": pinned,
                                 "ready_check": ready, "timeout": timeout, "art_wait": self.art_wait,
                                 "user_returned": lambda: self.returned_at > launched},
                         daemon=True, name="to-front").start()
        return True

    def lower_resolution(self) -> bool:
        """Al abrir un juego: ~1080p si no lo apagaste (Ajustes › Juegos y videos › Resolución al jugar)."""
        if sys.platform != "win32" or self.state.settings().get("game_resolution", "lower") != "lower":
            return False
        try:
            return display.resolution.for_game()
        except Exception:  # noqa: BLE001 - la resolución nunca impide abrir un juego
            log.exception("No pude bajar la resolución para jugar")
            return False

    def restart_with_players(self) -> bool:
        """Jugadores › «Reiniciar con estos jugadores»: cierra el juego y lo abre otra vez con el orden de ahora (los de
        Switch solo leen los controles al arrancar). Lo no guardado se pierde: la interfaz lo dice antes."""
        running = self.launcher.status()
        last = self._last_launch
        if not running or not running.get("managed") or not last or last.get("id") != running.get("id"):
            return False
        item = self.store.get(running["id"])
        if item is None:
            return False
        runner = self.runner_for(item, last.get("runner"))
        argv = runner.argv if runner else item.argv
        if not argv:
            return False
        cwd = runner.cwd if runner else item.cwd
        order = players.sync()  # el orden que elegiste (no el del último control que apretó A, que fue en el menú)
        emulator_input.arrange_for(argv, players.devices(order), slots=order, versions=players.versions())
        log.info("Reinicio %s con %d jugador(es)", item.title, len(order))
        if not self.launcher.relaunch(item.id, argv, cwd=cwd):
            return False
        self.to_front(item.id, item.title, runner.name if runner else None)
        return True

    def game_mode(self, item_id: str) -> bool:
        """¿Cerrar la ventana de Orbital mientras se juega esto? Solo consolas pesadas (sus emuladores necesitan la
        memoria que ocupa Edge) y si no lo apagaste en Ajustes › Juegos y videos."""
        from .memory import HEAVY_SYSTEMS

        item = self.store.get(item_id)
        if self.kiosk is None or item is None or item.system not in HEAVY_SYSTEMS:
            return False
        return self.state.settings().get("game_mode", "heavy") == "heavy"

    def park_soon(self, item_id: str) -> None:
        """Modo juego: en unos segundos, si sigues en ese juego (no apretaste Home), cerrar la ventana de Orbital."""
        if not self.game_mode(item_id):
            return
        asked = time.monotonic()

        def park() -> None:
            status = self.launcher.status()
            if not status or status.get("id") != item_id or self.returned_at > asked:
                return  # ya se cerró, o volviste a Orbital mientras tanto
            if self.kiosk is not None:
                self.kiosk.park()

        timer = threading.Timer(PARK_AFTER, park)
        timer.daemon = True
        timer.start()

    def art(self, shown: bool) -> None:
        """La pantalla de carga avisa de su arte: `False` viene en camino, `True` ya se ve (o ya no hace falta)."""
        if shown:
            self._art_shown_at = time.monotonic() if self._art_pending_at is not None else None
            self._art_pending_at = None
        else:
            self._art_pending_at, self._art_shown_at = time.monotonic(), None

    def art_wait(self, now: float | None = None) -> float:
        """Cuánto más espera la salida para que el arte se vea un momento. 0 sin aviso de la interfaz (desde el iPhone o
        por voz no hay pantalla de carga que esperar) o si el aviso es viejo."""
        now = time.monotonic() if now is None else now
        if self._art_pending_at is not None:
            return .2 if now - self._art_pending_at < 90 else 0.0
        if self._art_shown_at is not None:
            return max(0.0, self._art_shown_at + focus.ART_DWELL - now)
        return 0.0

    def reveal_now(self) -> None:
        """B en la pantalla de carga: deja de esperar y muestra lo que haya."""
        self._reveal_skip.set()

    def open_stremio(self, uri: str | None, title: str) -> None:
        """Abre Stremio (opcionalmente en un enlace) y lo vigila por su ejecutable: si ya estaba
        abierto, el proceso que lanzamos le pasa el enlace y termina al instante."""
        argv = stremio.find_stremio(self.config.stremio)
        if argv:
            self.launcher.run([*argv, uri] if uri else argv)
            self.launcher.track_exe("media:stremio", title, Path(argv[0]).name, runner="Stremio")
            # Si Stremio ya estaba abierto, recibe el enlace en su ventana de siempre... detrás de
            # Orbital: sin esto, "no pasa nada". La traemos al frente cuando exista.
            in_player = bool(uri and uri.startswith("stremio:///player/"))
            threading.Thread(target=focus.bring_app_to_front, args=(Path(argv[0]).name,),
                             kwargs={"fullscreen": in_player}, daemon=True).start()
        else:
            self.launcher.open_uri(uri or "stremio://")
            self.launcher.track("media:stremio", title, None)

    def play_stremio(self, kind: str, meta_id: str, video_id: str | None, title: str) -> str:
        """Reproduce directo (autoPlay) una película o un episodio elegido en Orbital."""
        uri = cinemeta.play_link(kind, meta_id, video_id)
        self.open_stremio(uri, title)
        return uri

    def search_media(self, query: str) -> str:
        uri = stremio.search_uri(query)
        self.open_stremio(uri, f"Stremio: {query}")
        return uri

    def _retry_quick_crash(self, item_id: str, title: str, seconds: float) -> bool:
        """Un emulador que se cerró solo en los primeros segundos se abre otra vez (una sola). La
        pantalla de carga sigue; si vuelve a tronar, se avisa como siempre."""
        last = self._last_launch
        if (not last or last["id"] != item_id or last["retried"] or seconds >= QUICK_EXIT
                or self.launcher.last_stopped_by_user or getattr(self.launcher, "last_was_already_open", False)):
            return False
        last["retried"] = True
        log.warning("%s se cerró a los %d s al arrancar: lo intento otra vez", title, seconds)

        def again() -> None:
            # En ese segundo y medio abriste otra cosa (mando, Alexa): el reintento ya no toca.
            if self._last_launch is not last or self.launcher.status() is not None:
                log.info("No reintento %s: ya se abrió otra cosa", title)
                return
            try:
                self.launch(item_id, last["runner"], keep=True, retry=True)
            except Exception:  # noqa: BLE001 - si no se puede reintentar, se avisa como cierre normal
                log.exception("No pude reintentar %s", title)
                self.events.publish({"type": "closed", "id": item_id, "title": title, "seconds": int(seconds),
                                     "crashed": True, "kind": "emulator"})

        threading.Timer(1.5, again).start()
        return True

    def session_ended(self, item_id: str, title: str, seconds: float) -> None:
        """El juego o emulador se cerró: guarda el tiempo, vuelve a Orbital y publica "closed"
        (Stremio refresca Seguir viendo y Steam relee sus horas al escucharlo)."""
        self.state.record_session(item_id, seconds)
        if self._retry_quick_crash(item_id, title, seconds):
            return
        display.resolution.restore()  # de vuelta a la resolución de la pantalla (Orbital y las películas, a 4K)
        if self.kiosk is not None and not self.kiosk.exited_by_user:
            self.kiosk.open()  # al frente o, si alguien cerró la ventana, otra vez abierta
        else:
            system.bring_to_front()
        health.note_dwm(f"de vuelta de {title}")
        # Se cerró solo a los pocos segundos: casi siempre es que no pudo abrir (falta la ROM, el
        # firmware, una clave…). No es "de vuelta de": se avisa como problema.
        crashed = (seconds < QUICK_EXIT and not self.launcher.last_stopped_by_user
                   and not getattr(self.launcher, "last_was_already_open", False)
                   and not item_id.startswith(("media:", "app:")))
        item = self.store.get(item_id)
        # De dónde es, para decir qué revisar si no abrió: Steam, GeForce NOW o un emulador.
        kind = "steam" if item_id.startswith("steam:") else item.source if item and item.source == "geforcenow" else "emulator"
        event = {"type": "closed", "id": item_id, "title": title, "seconds": int(seconds), "crashed": crashed, "kind": kind}
        if crashed:
            # Con la memoria casi llena los emuladores truenan al arrancar aunque el juego esté bien:
            # decirlo (antes: "revisa ROM, firmware, claves", que mandaba a buscar donde no era).
            low = memory_problem()
            if low:
                event["low_memory"] = low
                event["low_memory_restart"] = low.startswith("Windows está usando")  # la fuga de DWM
        end = self.last_end() if item_id == "media:player" else None
        if end:  # el reproductor anotó cómo terminó: "Terminaste Interstellar"
            event.update(title=end["title"], finished=end["finished"], **({"live": True} if end.get("live") else {}))
        self.events.publish(event)
        if not item_id.startswith(("media:", "app:")):  # un juego: su resumen en la bandeja del iPhone (modo acompañante)
            try:
                companion.note_played(self.state, item_id, event["title"], seconds,
                                      total_seconds=float(self.state.history(item_id).get("playtime") or 0),
                                      crashed=bool(event.get("crashed")), low_memory=bool(event.get("low_memory")),
                                      captures=companion.captures_since(time.time() - seconds))
            except Exception:  # noqa: BLE001 - el resumen del iPhone nunca estorba al cierre
                log.debug("No pude anotar el resumen para el iPhone", exc_info=True)

