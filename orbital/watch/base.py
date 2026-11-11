"""El estado que comparten las piezas de Watch y lo poco que todas usan (las claves guardadas, qué hay prendido).

Dueño del estado: Watch.__init__ (watch/__init__.py) lo arma una sola vez; aquí solo se declara, para que cada
pieza sepa qué hay. Los candados son de quien los usa: `_stremio_busy`, `_stremio_publish` y `_saving` de la
biblioteca (library.py), `_trakt_busy` de Trakt (library.py), `_CACHE_LOCK` del caché de Stremio (library.py).
"""

from __future__ import annotations

import logging
import threading
from pathlib import Path
from typing import TYPE_CHECKING, Any

from .. import player
from ..config import Config
from ..credentials import Credentials
from ..events import EventBus
from ..launcher import Launcher
from ..library import cinemeta, localize, stremio_api
from ..library.models import LibraryItem
from ..rd_requests import RdRequests
from ..scrobble import TraktScrobbler
from ..sessions import Sessions
from ..state import State
from ..store import ItemStore
from ..trakt_sync import TraktLibrary
from .items import HeardTracks

log = logging.getLogger("orbital.watch")  # el mismo nombre de siempre: los avisos y la bitácora no cambian

STREMIO_KEY = "stremio_auth_key"
ADDONS_KEY = "stremio_addons"  # tus complementos: cifrados como la clave de sesión (sus URLs llevan claves)
RD_KEY = "realdebrid_token"  # la clave fija de tu Real-Debrid, propia de la consola (corte S2), cifrada como las demás
RD_ACCOUNT = "rd:account"
RD_STATUS_TTL = 1800
# Las tres causas de tu cuenta (AD-5), con las palabras de design/vocabulario.json: (texto, detalle).
DEBRID_CAUSES = {"expired": ("Tu Real-Debrid venció", "Renovar en real-debrid.com, desde tu celular"),
                 "no_premium": ("Tu cuenta no tiene Premium", "Sin Premium no arranca nada al instante"),
                 "bad_key": ("Vuelve a conectar Real-Debrid", "Tu clave ya no sirve · Ajustes › Cuentas › Real-Debrid")}
STREMIO_STALE_SECONDS = 180


if TYPE_CHECKING:
    from collections.abc import Callable

    from ..library import addon_list as addon_list_lib
    from ..library import addons as addons_lib
    from ..library import cinemeta as cinemeta_lib
    from ..library import opensubtitles as opensubtitles_lib
    from ..library import streams as streams_lib
    from ..player import OrbitalPlayer
    from ..ytdlp import YtDlp


class _Base:
    """Lo que Watch.__init__ arma (aquí solo se declara, con su tipo, para que cada pieza lo vea)."""

    config: Config
    state: State
    credentials: Credentials
    stremio_client: stremio_api.StremioAPI
    cinemeta: cinemeta_lib.Cinemeta
    onedrive: Any  # OneDriveLibrary (catalog.py la pone): «Tu OneDrive» como fuente
    downloads: Any  # Downloads (catalog.py la pone): lo que bajaste para ver sin internet
    trailer_available: Callable[..., bool]
    ytdlp: YtDlp
    store: ItemStore
    events: EventBus
    sessions: Sessions
    launcher: Launcher
    stremio_error: str | None
    # La biblioteca (library.py): sus candados son `_stremio_busy` (una descarga a la vez), `_stremio_publish` (avisar en
    # orden), `_trakt_busy` (Trakt, una a la vez) y `_saving` (guardar el avance, progress.py).
    _stremio_cache: Path | None
    stremio_items: list[LibraryItem]
    cinemeta_items: list[LibraryItem]
    _stremio_fetched: float
    _stremio_busy: threading.Lock
    _stremio_again: bool
    _stremio_generation: int
    _stremio_publish: threading.Lock
    trakt_library: TraktLibrary
    _trakt_busy: threading.Lock
    _saving: threading.Lock
    # Complementos y Real-Debrid (accounts.py).
    addon_list: addon_list_lib.AddonList
    _removed_addons: dict[str, dict]
    addons: addons_lib.AddonRegistry
    localizer: localize.Localizer
    streams: streams_lib.StreamFinder
    opensubtitles: opensubtitles_lib.OpenSubtitles
    _rd_status: tuple[float, str | None, dict]
    rd: RdRequests
    heard: HeardTracks
    player: OrbitalPlayer
    scrobbler: TraktScrobbler

    # --- Stremio -------------------------------------------------------------
    @property
    def stremio_linked(self) -> bool:
        return bool(self.credentials.get(STREMIO_KEY))

    @property
    def has_addons(self) -> bool:
        """Hay a quién pedirle fuentes: tu lista de Orbital (con algo prendido), o tu cuenta de Stremio o complementos tuyos."""
        if self.addons.own_list:  # solo subtítulos (OpenSubtitles) no da versiones de nada
            return any(e.on() and e.address and e.template != "opensubtitles" for e in self.addon_list.entries())
        return self.stremio_linked or bool(self.addons.local)

    # --- películas y series en el reproductor de Orbital -----------------------------------------
    def setting(self, key: str, default=None):
        """Lo que elegiste en Ajustes manda; si no, config.yaml."""
        return self.state.settings().get(key, default)

    @staticmethod
    def _episode_label(info: dict, video_id: str) -> tuple[str, str]:
        """("T3 E6", "Nombre del episodio") de un video de una serie ("", "") si no se encuentra."""
        for season in cinemeta.seasons(info):
            for episode in season["episodes"]:
                if episode["id"] == video_id:
                    prefix = "Especial" if season["season"] == 0 else f"T{season['season']}"
                    return f"{prefix} E{episode['episode']}", episode["title"]
        return "", ""

    @staticmethod
    def _next_label(info: dict, video_id: str) -> str:
        """«E3» (misma temporada) o «T6 E1» (cruza de temporada): el que sigue, para «⏭ Siguiente» y la pista RT del
        reproductor. "" en el último (o si el que sigue aún no sale)."""
        found = cinemeta.next_episode(info, video_id)
        where = {e["id"]: (s["season"], e["episode"]) for s in cinemeta.seasons(info) for e in s["episodes"]}
        if found is None or found not in where:
            return ""
        season, episode = where[found]
        return f"E{episode}" if where.get(video_id, (None,))[0] == season else f"T{season} E{episode}"

    def _episode_title(self, info: dict, meta_id: str, video_id: str) -> tuple[str, str]:
        label, name = self._episode_label(info, video_id)
        series = info.get("name") or meta_id
        return f"{series} · {label}".strip(" ·"), " · ".join(p for p in (label, name) if p)

    @property
    def native_player(self) -> bool:
        """¿Se puede reproducir en el reproductor de Orbital (elegido, instalado y con cuenta)?"""
        return self.config.stremio.player == "orbital" and self.has_addons and player.find_mpv() is not None
