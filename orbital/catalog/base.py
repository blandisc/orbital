"""El estado del catálogo (se arma una sola vez, aquí), las constantes y lo que comparten las piezas."""

from __future__ import annotations

import logging
import os
import threading
from collections.abc import Callable
from pathlib import Path
from typing import TYPE_CHECKING, cast

from ..config import Config, expand
from ..credentials import Credentials
from ..downloads import Downloads
from ..events import EventBus
from ..foryou import ForYou, Services
from ..launcher import Launcher
from ..library import (
    cinemeta,
    esde,
    geforcenow,
    localize,
    steam_store,
    stremio_api,
    wiki_games,
)
from ..library import onedrive as onedrive_api
from ..library.media import MediaStore
from ..library.models import LibraryItem, Runner
from ..library.scraper import Scraper
from ..onedrive_library import OneDriveLibrary
from ..sessions import Sessions
from ..state import State
from ..store import ItemStore
from ..tv import LiveTV, TvServices
from ..watch import Watch
from .match import title_match as title_match  # noqa: F401

if TYPE_CHECKING:
    from . import Catalog

CONTINUE_LIMIT = 20  # "Seguir viendo": los más recientes
JUMP_LIMIT = 16  # "Continuar" en Inicio
NEW_FOR = 7 * 86400  # un juego es "nuevo" su primera semana
STEAM_STATS_DELAY = 6  # s tras cerrar un juego de Steam, antes de releer sus horas

log = logging.getLogger(__name__)

CATEGORIES = [
    # Inicio: lo último que jugaste o viste, mezclado (como "Jump back in" de Xbox); lo abierto, primero.
    {"id": "jump", "title": "Continuar"},
    {"id": "recent", "title": "Jugado recientemente"},
    {"id": "continue", "title": "Seguir viendo"},
    {"id": "mylist", "title": "Mi lista"},
    {"id": "favorites", "title": "Favoritos"},
    {"id": "steam", "title": "Steam"},
    {"id": "geforcenow", "title": "GeForce NOW"},
    {"id": "emulators", "title": "Emuladores"},
    {"id": "media", "title": "Multimedia"},
    {"id": "movies", "title": "Películas populares"},
    {"id": "series", "title": "Series populares"},
    {"id": "apps", "title": "Apps"},
]

# listener(evento) — el servidor lo usa para avisar a la interfaz.
Listener = Callable[[dict], None]

def default_state(config: Config) -> State:
    if config.source is None:
        return State(None)
    return State(config.source.parent / "state.json")


def default_credentials(config: Config) -> Credentials:
    return Credentials(config.source.parent / "secrets.json" if config.source else None)

def art_version(path: str | Path, sep: str = "&") -> str:
    """«&v=…» con la fecha del archivo: al cambiar la imagen («Cambiar imagen»), cambia la dirección y la
    pantalla deja de enseñar la vieja que tenía guardada (las imágenes se guardan un día)."""
    try:
        return f"{sep}v={int(Path(path).stat().st_mtime)}"
    except OSError:
        return ""


def tone_path(item: LibraryItem) -> str | None:
    """El arte cuyo tono pinta el fondo (backdrop.js): el fondo propio o, si solo hay portada, la portada."""
    return item.hero_path or item.art_path or None


class _Base:
    def __init__(self, config: Config, launcher: Launcher | None = None, state: State | None = None,
                 credentials: Credentials | None = None, stremio_client: stremio_api.StremioAPI | None = None,
                 cinemeta_client: cinemeta.Cinemeta | None = None) -> None:
        self.config = config
        self.launcher = launcher or Launcher()
        self.state = state or default_state(config)
        self.credentials = credentials or default_credentials(config)
        self.events = EventBus()
        self.store = ItemStore()
        self.steam_root: Path | None = None
        self.tones = None  # ArtTones (art_tone.py): el tono de cada arte, medido una vez; solo de verdad (create_app)
        self.esde: esde.EsdeLibrary | None = None
        # Emuladores en uso: los de config.yaml + los detectados automáticamente.
        self.emulators = list(config.emulators)
        self.detected: dict[str, Path] = {}
        # Cachés en disco (no en pruebas: sin config.yaml no se guarda nada).
        cache = Path(os.environ.get("LOCALAPPDATA") or Path.home()) / "orbital" / "cache" if config.source else None
        self._steam_art = geforcenow.SteamArt(cache / "steam-appids.json" if cache else None)
        # De qué trata cada juego de Steam y GeForce NOW (la tienda de Steam, en español; ver steam_store.py).
        self.steam_store = steam_store.SteamStore(cache / "steam-store.json" if cache else None)
        # Los juegos de GeForce NOW que no están en Steam (Blizzard…): su ficha de Wikidata/Wikipedia (wiki_games.py).
        self.wiki_games = wiki_games.WikiGames(cache / "wiki-games.json" if cache else None)
        self._steam_owned: list[str] = []  # los juegos de tu cuenta de Steam que no están instalados (números)
        self._cache = cache
        # La biblioteca del último escaneo: la interfaz la muestra al instante mientras se escanea.
        self._snapshot = cache / "library.json" if cache else None
        self.media = MediaStore(Path(expand(config.art.dir)) if config.art.dir else None)
        self._scraper: Scraper | None = None
        self._scraped: set[tuple[str, str, str]] = set()  # lo que ya se buscó en esta sesión (no insistir)
        self._scraping = threading.Lock()
        self.scanning = False  # primer escaneo en curso (la interfaz sigue en su pantalla de arranque)
        self._refreshing = threading.Lock()  # un escaneo a la vez (arranque + botón "Actualizar")
        self.sessions = Sessions(config, self.state, self.launcher, self.store, self.events,
                                 runner_for=self.runner_for, last_end=lambda: self.watch.player.last_end)
        self.watch = Watch(config, self.state, self.credentials, stremio_client or stremio_api.StremioAPI(),
                           cinemeta_client or cinemeta.Cinemeta(), self.store, self.events, self.sessions,
                           self.launcher)
        if cache and isinstance(self.watch.cinemeta, cinemeta.Cinemeta):
            self.watch.cinemeta.keep_on_disk(cache / "cinemeta-fichas.json")  # sin internet, las fichas que ya abriste
        # Tus videos de OneDrive (la carpeta que eliges en Ajustes): fila propia y fuente recomendada (onedrive_library.py).
        self.onedrive = OneDriveLibrary(onedrive_api.OneDrive(self.credentials), self.watch.cinemeta, self.state,
                                        cache / "onedrive-library.json" if cache else None, publish=self.notify)
        self.watch.onedrive = self.onedrive
        # Descargas para ver sin internet (Videos\Orbital): la película o el episodio, del disco.
        self.downloads = Downloads(Path(expand(config.downloads.dir)) if config.downloads.dir else None,
                                   resolve=self.watch.download_url, publish=self.notify, autostart=bool(cache))
        self.watch.downloads = self.downloads
        # El nombre de cada título en tu idioma, igual en las filas, Para ti, tu biblioteca y la ficha.
        # v2: las de antes guardaron en inglés las películas en el idioma de la app («Even the Wind Is Afraid»).
        self.names = localize.TitleNames(self.watch.localizer, cache / "title-names-v2.json" if cache else None,
                                         on_new=lambda: self.notify({"type": "library-changed"}))
        self.watch.localizer.on_name = self.names.remember
        self.foryou = ForYou(config, Services.of(cast("Catalog", self)))  # «Para ti»: recomendaciones (no sale a internet hasta que se pide)
        self.watch.scrobbler.trakt = lambda: self.foryou.trakt  # lo que ves, a Trakt (se pide en cada aviso)
        self.watch.trakt_library.trakt = lambda: self.foryou.trakt  # y lo de Trakt (el iPhone) a Seguir viendo y Mi lista
        # En pausa, el título estilizado: el mismo logo recortado de la ficha (en blanco si es oscuro).
        self.watch.player.logo_provider = lambda meta: self.foryou.trimmed_logo(str(meta.get("meta_id") or ""))
        self.tv = LiveTV(config, TvServices.of(cast("Catalog", self)))  # «TV en vivo»: canales y su salud (no sale a internet hasta que arranca)
        self.events.subscribe(self._on_event)

    if TYPE_CHECKING:
        # Los define las piezas de después (query.py, facts.py, scan.py); aquí solo para que los tipos las vean.
        def refresh(self) -> int: ...
        def refresh_steam_stats(self) -> None: ...
        def runner_for(self, item: LibraryItem, runner_id: str | None = None) -> Runner | None: ...

    # --- piezas y compatibilidad ----------------------------------------------------------------
    @property
    def listeners(self) -> list[Listener]:
        return self.events.listeners

    def notify(self, event: dict) -> None:
        self.events.publish(event)

    @property
    def player(self):
        return self.watch.player

    @player.setter
    def player(self, value) -> None:
        self.watch.player = value

    kiosk = property(lambda self: self.sessions.kiosk, lambda self, v: setattr(self.sessions, "kiosk", v))
    before_launch = property(lambda self: self.sessions.before_launch,
                             lambda self, v: setattr(self.sessions, "before_launch", v))
    revealing = property(lambda self: self.sessions.revealing,
                         lambda self, v: setattr(self.sessions, "revealing", v))
    streams = property(lambda self: self.watch.streams)
    cinemeta = property(lambda self: self.watch.cinemeta)
    stremio_client = property(lambda self: self.watch.stremio_client)
    stremio_error = property(lambda self: self.watch.stremio_error)
    stremio_linked = property(lambda self: self.watch.stremio_linked)
    stream_prefs = property(lambda self: self.watch.stream_prefs)
    subtitles_lang = property(lambda self: self.watch.subtitles_lang)
    native_player = property(lambda self: self.watch.native_player)

    def _on_event(self, event: dict) -> None:
        """Al cerrarse algo: Stremio refresca Seguir viendo; Steam relee sus horas (las guarda unos
        segundos después de cerrar el juego)."""
        if event.get("type") != "closed":
            return
        if event.get("id") == "media:stremio":
            self.watch.refresh_stremio(background=True)
        elif str(event.get("id", "")).startswith("steam:"):
            threading.Timer(STEAM_STATS_DELAY, self.refresh_steam_stats).start()
