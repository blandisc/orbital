"""«Para ti»: qué ver o qué jugar, sin tener que pensarlo.

Junta tres servicios (todos opcionales) con lo que Orbital ya sabe de tus juegos:

  * Trakt  — tus recomendaciones, tu watchlist, tus listas, las series que estás viendo, tendencias
             y lo más popular (library/trakt.py)
  * TMDB   — lo más popular en Netflix, Disney+ y HBO Max en tu país, y sinopsis en español (library/tmdb.py)
  * RAWG   — novedades, lo más popular y lo mejor calificado en juegos de PC (library/rawg.py)
  * Tus juegos — favoritos, los más jugados, los que nunca has abierto y uno al azar (lógica local)
  * Tus complementos de Stremio — sus catálogos que agregan algo (Prime Video, Apple TV+, Rotten
             Tomatoes…) y, sin Trakt conectado, las listas de «Trakt Integration» (library/stremio_api.py)

Dos formas de verlo en la interfaz: el mosaico (lo tuyo, mezclado) y las listas (un riel como el de
Juegos). Cada sugerencia sale con una etiqueta corta («Recomendada», «Sin jugar»…) y un dato.
Un servicio que falla no tumba los demás: su lista queda vacía y se reintenta más tarde.

Es un paquete: una pieza por tema (base, cache, items, mine, sources, titles, agenda, shelves, home) y `ForYou`, aquí,
es la fachada: arma el estado una sola vez y junta las piezas con la misma API de siempre. Las piezas se heredan en
cadena (cada una ve las de antes) solo para que los tipos se revisen.
"""

from __future__ import annotations

import json  # noqa: F401  (foryou.json: las pruebas lo usan)
import logging
import os
import threading
import urllib.request  # noqa: F401  (foryou.urllib: las pruebas lo usan)
from concurrent.futures import ThreadPoolExecutor
from datetime import date as date
from datetime import datetime as datetime
from pathlib import Path

from ..library import charts as charts_api
from ..library import mdblist as mdblist_api  # noqa: F401  (foryou.mdblist_api)
from ..library import tmdb as tmdb_api  # noqa: F401  (foryou.tmdb_api)
from ..library import trakt as trakt_api
from .base import AWARD_ORDER as AWARD_ORDER
from .base import AWARD_TINTS as AWARD_TINTS
from .base import AWARDS_FILE as AWARDS_FILE
from .base import CALENDAR_DAYS as CALENDAR_DAYS
from .base import CANON as CANON
from .base import CANON_TTL as CANON_TTL
from .base import DAWN_HOUR as DAWN_HOUR
from .base import FIRST_YEAR as FIRST_YEAR
from .base import FRESH_BRANDS as FRESH_BRANDS
from .base import FRESH_MOVIE_DAYS as FRESH_MOVIE_DAYS
from .base import FRESH_SERIES_DAYS as FRESH_SERIES_DAYS
from .base import GAME_CATEGORIES as GAME_CATEGORIES
from .base import GENERIC_CATALOGS as GENERIC_CATALOGS
from .base import JW_LIST_BRANDS as JW_LIST_BRANDS
from .base import KEY_PREFIX as KEY_PREFIX
from .base import KEYS as KEYS
from .base import LATEST_PAST_DAYS as LATEST_PAST_DAYS
from .base import LOGO_RETRY as LOGO_RETRY
from .base import LOGO_WARM as LOGO_WARM
from .base import METAHUB as METAHUB
from .base import METAHUB_POSTER as METAHUB_POSTER
from .base import MINE_TTL as MINE_TTL
from .base import MOSAIC_SIZE as MOSAIC_SIZE
from .base import PER_SOURCE as PER_SOURCE
from .base import POPULAR_TTL as POPULAR_TTL
from .base import POSTER_TTL as POSTER_TTL
from .base import PREFETCH_DELAY as PREFETCH_DELAY
from .base import RECS_TTL as RECS_TTL
from .base import SERVICE_ERRORS as SERVICE_ERRORS
from .base import SKIP_ADDONS as SKIP_ADDONS
from .base import SLOW_TTL as SLOW_TTL
from .base import STEAM_ART as STEAM_ART
from .base import TRAKT_ADDON as TRAKT_ADDON
from .base import TRAKT_FAVORITES as TRAKT_FAVORITES
from .base import TV_ONLY_PREFIXES as TV_ONLY_PREFIXES
from .base import WEEKDAYS as WEEKDAYS
from .base import Services as Services
from .base import load_awards as load_awards
from .cache import Cache as Cache
from .cache import _build as _build
from .cache import _has_items as _has_items
from .cache import _mark_partial as _mark_partial
from .home import _Home
from .items import calendar_item as calendar_item
from .items import day_label as day_label
from .items import fold as fold
from .items import game_item as game_item
from .items import hours_text as hours_text
from .items import library_entry as library_entry
from .items import runtime_text as runtime_text
from .items import series_only as series_only
from .items import video_item as video_item
from .items import whiten_if_dark as whiten_if_dark

log = logging.getLogger("orbital.foryou")  # el mismo nombre de siempre: la bitácora no cambia


class ForYou(_Home):
    def __init__(self, config, services: Services) -> None:
        self.settings = config.para_ti
        self.services = services
        self.region = self.settings.region
        folder = Path(os.environ.get("LOCALAPPDATA") or Path.home()) / "orbital" / "cache" if getattr(config, "source", None) else None
        self.cache = Cache(path=folder / "foryou-cache.json" if folder else None)
        self.snapshots = charts_api.ChartSnapshots(folder / "charts.sqlite" if folder else None)
        self._build()
        self._link: trakt_api.DeviceCode | None = None
        self._link_lock = threading.Lock()
        self._link_gen = 0  # cada pedido o cancelación de código lo sube: solo cuenta el último
        self._dark: dict[str, bool | None] = {}
        self.logo_dir = folder / "title-logos" if folder else None
        self._logos: dict[str, bytes] = {}  # sin carpeta (pruebas): en memoria
        self._logo_pool = ThreadPoolExecutor(max_workers=1, thread_name_prefix="logos")  # calentar logos, de uno en uno
        self._studio_logos_busy = False
        self._logo_misses: dict[str, float] = {}
        from ..gestor import Gestor

        self.gestor = Gestor(self)  # el gestor tipo Trakt (G1–G4), como el iPhone
        scrobbler = getattr(getattr(services, "watch", None), "scrobbler", None)
        if scrobbler is not None:  # lo que el reproductor no pudo avisarle a Trakt espera en la misma cola (F4)
            scrobbler.outbox = self.gestor.outbox

    # Aquí y no en su pieza: lee `load_awards` de este módulo (las pruebas lo cambian por aquí).
    def collections(self) -> list[dict]:
        """La vitrina de Colecciones: cada premio y cada lista famosa con cuántas ya viste (lo que no se pudo leer no sale)."""
        watched = set(self.watched_ids()) if self.trakt.linked else set()
        awards = {a["id"]: a for a in load_awards()}
        out = []
        for award_id in [*AWARD_ORDER, *(a for a in awards if a not in AWARD_ORDER)]:
            a = awards.get(award_id)
            if a:
                ids = {w["imdb"] for w in a["winners"]}
                out.append({"id": f"award:{award_id}", "title": a["title"], "meta": a.get("category") or "", "family": "award",
                            "tint": a["tint"], "kind": a["kind"], "total": len(ids), "seen": len(ids & watched)})
        for canon_id, title, _, _total in CANON:
            try:
                items = self._canon(canon_id)
            except SERVICE_ERRORS:
                continue
            if items:
                ids = {e["imdb"] for e in items}
                out.append({"id": f"canon:{canon_id}", "title": title, "meta": "", "family": "list", "total": len(ids),
                            "seen": len(ids & watched)})
        return out
