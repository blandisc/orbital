"""Abrir cosas y saber cuándo terminan: juegos, emuladores, apps, Stremio y GeForce NOW.

Recibe "abre esto", fija la pantalla de carga, lo lanza y lo vigila; al cerrarse guarda el tiempo
jugado, trae Orbital al frente y publica el evento "closed" (lo escuchan la interfaz, Stremio y Steam).
"""

from __future__ import annotations

import logging
import sys
import threading
from collections.abc import Callable
from pathlib import Path

from . import focus, system
from .config import Config
from .events import EventBus
from .launcher import Launcher
from .library import cinemeta, geforcenow, stremio
from .library.models import LibraryItem
from .state import State
from .store import ItemStore

log = logging.getLogger(__name__)

QUICK_EXIT = 15  # s: un juego que se cierra antes, solo, seguramente no pudo abrir


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
        # Por hilo: cada petición sabe si SU lanzamiento tiene pantalla de carga (antes era un solo
        # valor compartido y un lanzamiento por voz en segundo plano podía pisar el de la interfaz).
        self._local = threading.local()
        launcher.on_exit = self.session_ended
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

    def launch(self, item_id: str, runner_id: str | None = None, keep: bool = False) -> LibraryItem:
        """`keep`: abrir sin cerrar lo que estaba abierto (lo pediste en "¿Cerrar…?")."""
        self.revealing = False
        item = self.store.get(item_id)
        if item is None:
            raise KeyError(item_id)
        if self.before_launch and not keep:
            self.before_launch(item.id)
        if item.source in ("stremio", "cinemeta") or item.id == "media:stremio":
            self.open_stremio(item.uri if item.id != "media:stremio" else None, item.title)
            self.state.record_launch(item.id)
            return item
        if item.source == "geforcenow":
            # La app (y su reproductor en la nube) es de instancia única: se vigila por ejecutable.
            exe = geforcenow.APP_EXE if item.id == "app:geforcenow" else geforcenow.STREAMER_EXE
            self.launcher.run(item.argv, cwd=item.cwd)
            self.launcher.track_exe(item.id, item.title, exe, runner="GeForce NOW")
            threading.Thread(target=focus.bring_app_to_front, args=(exe,), daemon=True).start()
            self.state.record_launch(item.id)
            return item
        runner = self.runner_for(item, runner_id)
        if runner or item.argv:
            # Orbital encima ANTES de lanzar: la ventana del emulador nunca se asoma.
            pinned = self.pin()
            try:
                proc = self.launcher.run(runner.argv if runner else item.argv, cwd=runner.cwd if runner else item.cwd)
            except BaseException:
                self.unpin(pinned)
                raise
            self.launcher.track(item.id, item.title, proc, runner=runner.name if runner else None)
            self.revealing = self.to_front(item.id, item.title, runner.name if runner else None, pinned=pinned)
        elif item.uri:
            self.launcher.open_uri(item.uri)
            self.launcher.track(item.id, item.title, None, steam_appid=item.steam_appid)
        else:
            raise ValueError(f"{item.title} no tiene forma de lanzarse")
        self.state.record_launch(item.id)
        return item

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
        threading.Thread(target=focus.bring_game_to_front, args=(self.launcher, item_id, title, runner),
                         kwargs={"notify": self.events.publish, "skip": self._reveal_skip, "pinned": pinned,
                                 "ready_check": ready, "timeout": timeout}, daemon=True,
                         name="to-front").start()
        return True

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

    def session_ended(self, item_id: str, title: str, seconds: float) -> None:
        """El juego o emulador se cerró: guarda el tiempo, vuelve a Orbital y publica "closed"
        (Stremio refresca Seguir viendo y Steam relee sus horas al escucharlo)."""
        self.state.record_session(item_id, seconds)
        if self.kiosk is not None and not self.kiosk.exited_by_user:
            self.kiosk.open()  # al frente o, si alguien cerró la ventana, otra vez abierta
        else:
            system.bring_to_front()
        # Se cerró solo a los pocos segundos: casi siempre es que no pudo abrir (falta la ROM, el
        # firmware, una clave…). No es "de vuelta de": se avisa como problema.
        crashed = seconds < QUICK_EXIT and not self.launcher.last_stopped_by_user and not item_id.startswith(("media:", "app:"))
        event = {"type": "closed", "id": item_id, "title": title, "seconds": int(seconds), "crashed": crashed}
        end = self.last_end() if item_id == "media:player" else None
        if end:  # el reproductor anotó cómo terminó: "Terminaste Interstellar"
            event.update(title=end["title"], finished=end["finished"])
        self.events.publish(event)

