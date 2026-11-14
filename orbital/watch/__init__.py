"""Películas y series: tu cuenta de Stremio, elegir la fuente y el reproductor de Orbital.

Seguir viendo y Mi lista (cuenta de Stremio), los populares de Cinemeta, buscar y ordenar fuentes,
reproducir en mpv con el mando (siguiente episodio, otra fuente si una falla) y guardar el avance.

Es un paquete: cada pieza en su módulo (base, versions, items, library, accounts, sources, progress, playback,
details) y `Watch`, aquí, es la fachada: arma el estado una sola vez y junta las piezas, con la misma API de
siempre (`catalog.watch.…`). Las piezas se heredan en cadena (cada una ve las de antes) solo para que los tipos
se revisen; el estado y sus candados están descritos en base.py.
"""

from __future__ import annotations

import logging
import os
import threading
from pathlib import Path

from .. import player, ytdlp
from ..config import Config
from ..credentials import Credentials
from ..events import EventBus
from ..launcher import Launcher
from ..library import addon_list, addons, cinemeta, localize, opensubtitles, streams, stremio_api
from ..library import tmdb as tmdb_api
from ..library.models import LibraryItem
from ..rd_requests import RdRequests
from ..scrobble import TraktScrobbler
from ..sessions import Sessions
from ..state import State
from ..store import ItemStore
from ..trakt_sync import ChannelDetours, TraktLibrary
from .base import ADDONS_KEY as ADDONS_KEY
from .base import DEBRID_CAUSES as DEBRID_CAUSES
from .base import RD_ACCOUNT as RD_ACCOUNT
from .base import RD_KEY as RD_KEY
from .base import RD_STATUS_TTL as RD_STATUS_TTL
from .base import STREMIO_KEY as STREMIO_KEY
from .base import STREMIO_STALE_SECONDS as STREMIO_STALE_SECONDS
from .details import _Details
from .items import _YOUTUBE_SEEN as _YOUTUBE_SEEN
from .items import CONTINUE_MIN_PROGRESS as CONTINUE_MIN_PROGRESS
from .items import HeardTracks as HeardTracks
from .items import addon_gives as addon_gives
from .items import enrich_watch_item as enrich_watch_item
from .items import expired_session as expired_session
from .items import returning_item as returning_item
from .items import stremio_item as stremio_item
from .items import time_left as time_left
from .items import trailer_id as trailer_id
from .items import youtube_available as youtube_available
from .library import _CACHE_LOCK as _CACHE_LOCK
from .library import RETRY_SECONDS as RETRY_SECONDS
from .versions import FALLBACK_TRIES as FALLBACK_TRIES
from .versions import JUNK_TAGS as JUNK_TAGS
from .versions import LATIN_ORDER as LATIN_ORDER
from .versions import QUALITY_ORDER as QUALITY_ORDER
from .versions import SUBTITLE_LINES as SUBTITLE_LINES
from .versions import VERSION_RES as VERSION_RES
from .versions import WANTED_NAMES as WANTED_NAMES
from .versions import _quality as _quality
from .versions import _row_code as _row_code
from .versions import _sure as _sure
from .versions import choice_line as choice_line
from .versions import fallback_source as fallback_source
from .versions import give_up_words as give_up_words
from .versions import handoff_pick as handoff_pick
from .versions import language_code as language_code
from .versions import player_source_label as player_source_label
from .versions import player_ui_day as player_ui_day
from .versions import ready_now as ready_now
from .versions import source_label as source_label
from .versions import spanish_variant as spanish_variant
from .versions import version_grid as version_grid
from .versions import version_lang as version_lang
from .versions import version_layout as version_layout
from .versions import version_line as version_line
from .versions import version_note as version_note
from .versions import version_rows as version_rows

log = logging.getLogger("orbital.watch")  # el mismo nombre de siempre: los avisos y la bitácora no cambian


class Watch(_Details):
    def __init__(self, config: Config, state: State, credentials: Credentials, stremio_client: stremio_api.StremioAPI,
                 cinemeta_client: cinemeta.Cinemeta, store: ItemStore, events: EventBus, sessions: Sessions,
                 launcher: Launcher) -> None:
        self.config = config
        self.state = state
        self.credentials = credentials
        self.stremio_client = stremio_client
        self.cinemeta = cinemeta_client
        self.onedrive = None  # OneDriveLibrary (catalog.py la pone): «Tu OneDrive» como fuente
        self.downloads = None  # Downloads (catalog.py la pone): lo que bajaste para ver sin internet
        self.trailer_available = youtube_available  # «Tráiler» solo si el video existe (las pruebas lo cambian)
        self.ytdlp = ytdlp.YtDlp()  # lo que le enseña a mpv a abrir YouTube (se baja y se actualiza solo; ver ytdlp.py)
        self.store = store
        self.events = events
        self.sessions = sessions
        self.launcher = launcher
        self.stremio_error: str | None = None
        # La última biblioteca de Stremio, guardada: al arrancar, Seguir viendo y Continuar ya salen en su
        # orden y no se reacomodan unos segundos después cuando llega la descarga nueva.
        self._stremio_cache = (Path(os.environ.get("LOCALAPPDATA") or Path.home()) / "orbital" / "cache"
                               / "stremio-library.json") if config.source else None
        self.stremio_items: list[LibraryItem] = self._load_stremio_cache()
        self.cinemeta_items: list[LibraryItem] = []
        self._stremio_fetched = 0.0
        self._stremio_busy = threading.Lock()
        self._stremio_again = False
        self._stremio_generation = 0
        self._stremio_publish = threading.Lock()
        # Trakt: lo que viste, pausaste o guardaste en el iPhone (o en otra app) también entra a Seguir viendo y Mi lista.
        self.trakt_library = TraktLibrary()  # catalog.py le da el Trakt de «Para ti» cuando ya existe
        self.trakt_library.dismissed = lambda imdb: self.state.prefs(f"stremio:{imdb}").get("dismissed")
        # V2: lo que dejaste a medias en un canal de Orbital (sale en Seguir viendo sin mover tu orden).
        self.trakt_library.channel = ChannelDetours(lambda: self.state.settings().get("channel_detours"),
                                                    lambda value: self.state.set_setting("channel_detours", value))
        self._trakt_busy = threading.Lock()
        self._saving = threading.Lock()
        # Tus complementos: los de tu cuenta de Stremio o, ya traídos, tu lista de Orbital (Ajustes › Complementos).
        self.addon_list = addon_list.AddonList(self.credentials, legacy=self.own_addons,
                                               key=lambda: self.credentials.get(RD_KEY), on_key=self._rd_key_brought,
                                               stremio=lambda: self.stremio_linked or bool(self.own_addons()))
        self.addon_list.adopt_torrentio()  # el Torrentio que ya habías traído de Stremio pasa al de Orbital (corte S3)
        self.addon_list.drop_local()  # 4 nov: sin el servidor de Stremio, «Archivos de la TV» ya no sirve
        if self.addon_list.needs_copy:  # 4 nov: las fuentes salían de tu cuenta de Stremio; se copian una vez a tu lista
            threading.Thread(target=self._copy_stremio_addons, daemon=True, name="addons-copy").start()
        self._removed_addons: dict[str, dict] = {}
        self.addons = addons.AddonRegistry(
            self.stremio_client, auth=lambda: self.credentials.get(STREMIO_KEY), own=self.own_addons,
            listing=self.addon_list,
            manifests=(Path(os.environ.get("LOCALAPPDATA") or Path.home()) / "orbital" / "cache" / "manifiestos.json")
            if config.source else None)
        self.cinemeta.registry = self.addons
        # Las fichas en el idioma de Orbital (TMDB traduce lo que Cinemeta da en inglés).
        self.localizer = localize.Localizer(tmdb_api.Tmdb(config.para_ti.tmdb_key, timeout=5),
                                            lambda: self.setting("language", config.ui.language))
        self.cinemeta.localize = self.localizer.meta
        self.streams = streams.StreamFinder(self.addons)
        # Más subtítulos: la API de OpenSubtitles (clave de la app y tu cuenta en secrets.json; Ajustes › Cuentas).
        self.opensubtitles = opensubtitles.OpenSubtitles(self.credentials, languages=lambda: [self.subtitles_lang, "en"])
        self.streams.opensubtitles = self.opensubtitles
        opensubtitles.install(self.opensubtitles)
        # Lo que Real-Debrid aún no tiene se le pide desde la ficha o el reproductor; ya bajado, es una versión más.
        self._rd_status: tuple[float, str | None, dict] = (0.0, None, {})
        self.rd = RdRequests(self.streams, self.state, lambda event: self.events.publish(event), token=self.rd_token)
        self.rd.start()  # lo que quedó bajando antes de reiniciar se vuelve a seguir
        self.streams.facts = self._title_facts  # el idioma original (TMDB): de qué idioma es una fuente que no lo dice
        self.heard = HeardTracks((Path(os.environ.get("LOCALAPPDATA") or Path.home()) / "orbital" / "cache"
                                  / "pistas-de-audio.json") if config.source else None)
        self.streams.tracks = self.heard.get
        self.streams.internet_subtitles = lambda: bool(self.setting("internet_subtitles", True))
        self.player = player.OrbitalPlayer(
            on_finished=self._player_finished, idle_seconds=config.sessions.video_idle_minutes * 60,
            on_idle=lambda title, minutes, live=False: self.events.publish({
                "type": "toast", "message": f"Cerré {title}",
                "detail": f"Llevaba {minutes} min sin que lo vieras" if live
                else f"Llevaba {minutes} min en pausa · Sigues donde te quedaste"}))
        self.scrobbler = TraktScrobbler()  # catalog.py le da el Trakt de «Para ti» cuando ya existe
        self.scrobbler.on_saved = self._trakt_saved
        self._wire_player()
