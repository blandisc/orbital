"""Lo que comparten las piezas de «Para ti»: los nombres y los tiempos, las claves de cada servicio y sus clientes.

Dueño del estado: ForYou.__init__ (foryou/__init__.py) lo arma una sola vez; aquí solo se declara. La caché tiene su
propio candado (cache.py); conectar Trakt, `_link_lock` (mine.py).
"""

from __future__ import annotations

import json
import logging
import re
import threading
from concurrent.futures import ThreadPoolExecutor
from datetime import date
from pathlib import Path
from typing import TYPE_CHECKING, Any

from ..library import charts as charts_api
from ..library import letterboxd as letterboxd_api
from ..library import mdblist as mdblist_api
from ..library import rawg as rawg_api
from ..library import stremio_api
from ..library import tmdb as tmdb_api
from ..library import trakt as trakt_api
from ..net import NET_FAILURES
from ..shared import design_file

log = logging.getLogger("orbital.foryou")  # el mismo nombre de siempre: la bitácora no cambia


METAHUB = "https://images.metahub.space/{kind}/medium/{imdb}/img"

PREFETCH_DELAY = 45  # s tras armar el mosaico, antes de bajar sus imágenes (que el arranque termine primero)

LOGO_RETRY = 30 * 60  # un logo que no se pudo bajar (o que no existe) no se vuelve a pedir en media hora

LOGO_WARM = 12  # de cada lista, los logos que se bajan antes de que se pidan

STEAM_ART = "https://cdn.cloudflare.steamstatic.com/steam/apps/{appid}/{file}"

GAME_CATEGORIES = ("steam", "emulators")

SERVICE_ERRORS = (trakt_api.TraktError, tmdb_api.TmdbError, rawg_api.RawgError, stremio_api.StremioError,
                  charts_api.ChartsError, mdblist_api.MdbListError) + NET_FAILURES  # no OSError/ValueError genéricos

# JustWatch, con su propio riel «Lo más visto en…» (Netflix ya tiene el Top 10 oficial: chart:netflix).
JW_LIST_BRANDS = ("disney", "hbo", "prime", "appletv", "paramount")


# Cuánto vale lo que se trajo (s): lo tuyo cambia seguido; lo popular, no tanto.
MINE_TTL = 15 * 60

RECS_TTL = 60 * 60

POPULAR_TTL = 6 * 3600

SLOW_TTL = 24 * 3600

POSTER_TTL = 30 * 24 * 3600  # el póster de TMDB de un título casi no cambia

METAHUB_POSTER = re.compile(r"https://images\.metahub\.space/poster/[a-z]+/(tt[0-9]{1,12})/img")


CALENDAR_DAYS = 14  # lo que enseña «Próximos estrenos»: dos semanas

LATEST_PAST_DAYS = 7  # «Lo nuevo de lo tuyo» también enseña lo que salió la semana pasada (como el iPhone)

DAWN_HOUR = 6  # lo que sale antes de las 6:00 (streaming) se lee «desde la madrugada»

WEEKDAYS = ["lunes", "martes", "miércoles", "jueves", "viernes", "sábado", "domingo"]


MOSAIC_SIZE = 96  # el mosaico tiene ~40 piezas a la vista: con menos, se repetían

PER_SOURCE = 16  # de cada lista, a lo más (así se mezclan)


# Catálogos de tus complementos de Stremio que no se enseñan: los genéricos (ya hay «Lo más popular»),
# los de torrents y los que no son de películas o series.
GENERIC_CATALOGS = {"popular", "year", "language", "search", "new", "featured", "top seeded", "trending",
                    "last videos", "calendar videos", "realdebrid", "anime"}

SKIP_ADDONS = ("cinemeta", "torrent", "opensubtitles", "local files")

TRAKT_ADDON = "trakt integration"

# Tus favoritos de Trakt (películas y series). Otro nombre que «favorites»: esa es la categoría de tus JUEGOS (catalog/base.py).
TRAKT_FAVORITES = "trakt-favorites"


# Las claves de cada servicio. Las que escribes en Ajustes › Cuentas se guardan cifradas con las
# credenciales (como la sesión de Stremio) y mandan sobre las de config.yaml.
# Películas y series (como Para ti › Listas del iPhone): premios fijos, «Nuevo en tus plataformas», estudios, género,
# temporada y por año.
AWARDS_FILE = design_file("awards.json")  # compartido con el iPhone (también empaquetado)

AWARD_TINTS = ("gold", "silver", "bronze")

FRESH_BRANDS = ("netflix", "disney", "hbo")  # «Nuevo en tus plataformas» las alterna, como el iPhone

FRESH_SERIES_DAYS, FRESH_MOVIE_DAYS = 14, 90

FIRST_YEAR = 1980  # «Por año», del actual hacia atrás

# Lo que solo arma la TV (el iPhone calcula los suyos): no viaja por el túnel (server._foryou_public_routes).
TV_ONLY_PREFIXES = ("because", "fresh", "canon:", "letterboxd:", "award:", "studio:", "year:", "genre:", "season:")



def load_awards(path: Path = AWARDS_FILE) -> list[dict]:
    """Los premios (design/awards.json): [] si el archivo no está o viene roto (Películas y series sigue sin ellos)."""
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return []
    awards = []
    for a in data.get("awards") or [] if isinstance(data, dict) else []:
        winners = [w for w in a.get("winners") or [] if isinstance(w, dict) and str(w.get("imdb", "")).startswith("tt")
                   and w.get("title") and isinstance(w.get("award_year"), int)]
        if isinstance(a, dict) and a.get("id") and a.get("kind") in ("movie", "series") and winners:
            awards.append({**a, "tint": a.get("tint") if a.get("tint") in AWARD_TINTS else "gold", "winners": winners})
    return awards



# Colecciones (como la repisa del iPhone, Canon.lists): las listas famosas, además de los premios. «nyt-movies» es una de TUS
# listas de Trakt (la que se llama como la del New York Times de películas), como en el iPhone.
CANON = (
    ("criterion", "Colección Criterion", "pizzadeath/the-criterion-collection", 1000),
    ("top250", "Top 250 de IMDb", "georgenilas/imdb-top-250", 250),
    ("nyt-movies", "NYT · Películas", "", 100),
    ("nyt-series", "NYT · Series", "amything/the-100-best-tv-shows-of-the-21st-century-according-to-the-new-york-times", 100),
)

CANON_TTL = 7 * 86400  # s: las listas famosas cambian poco (el iPhone las guarda una semana)

AWARD_ORDER = ("oscar", "palm", "ariel", "globe", "bafta", "emmy")  # el orden de la repisa del iPhone (Canon.awardOrder)



KEYS = {"trakt": ("trakt_client_id", "trakt_client_secret"), "tmdb": ("tmdb_key",), "rawg": ("rawg_key",),
        "steamgriddb": ("steamgriddb_key",), "mdblist": ("mdblist_key",),
        # Letterboxd no tiene clave: tu usuario (solo se lee lo público de tu perfil, como el iPhone).
        "letterboxd": ("letterboxd_user",)}  # esta no es de Para ti: más portadas para tus juegos (scraper.SteamGridDB)

KEY_PREFIX = "para_ti."


if TYPE_CHECKING:
    from collections.abc import Callable

    from ..catalog import Catalog
    from ..credentials import Credentials
    from ..events import EventBus
    from ..gestor import Gestor
    from ..library.localize import TitleNames
    from ..library.models import LibraryItem
    from ..state import State
    from ..watch import Watch
    from .cache import Cache


class Services:
    """Lo único que «Para ti» usa de Orbital: credenciales, ajustes, avisos, Watch, los nombres de los títulos y tu
    biblioteca (antes recibía el Catalog entero). catalog.py lo arma con `Services.of(catalog)`; si una pieza nueva
    necesita otro servicio, entra aquí (y pyright avisa si una pieza usa algo que no está)."""

    def __init__(self, *, credentials: Credentials, state: State, events: EventBus, watch: Watch, names: TitleNames,
                 items: Callable[..., list[LibraryItem]], get: Callable[[str], LibraryItem | None],
                 describe: Callable[[LibraryItem], dict]) -> None:
        self.credentials = credentials
        self.state = state
        self.events = events
        self.watch = watch
        self.names = names
        self.items = items  # (include_hidden=False) -> tu biblioteca
        self.get = get
        self.describe = describe

    @property
    def cinemeta(self) -> Any:
        """El de Watch, el de ahora (las pruebas lo cambian en Watch)."""
        return self.watch.cinemeta

    @classmethod
    def of(cls, catalog: Catalog) -> Services:
        return cls(credentials=catalog.credentials, state=catalog.state, events=catalog.events, watch=catalog.watch,
                   names=catalog.names, items=catalog.items, get=catalog.get, describe=catalog.describe)


class _Base:
    """Lo que ForYou.__init__ arma (aquí solo se declara, con su tipo, para que cada pieza lo vea)."""

    settings: Any  # config.para_ti
    services: Services  # lo que «Para ti» usa de Orbital: credenciales, avisos, biblioteca y Watch (arriba)
    region: Any
    cache: Cache  # dueño: cache.py (tiene su propio candado)
    snapshots: charts_api.ChartSnapshots
    # Los clientes de cada servicio: los arma _build (y se rehacen al cambiar una clave).
    trakt: trakt_api.Trakt
    tmdb: tmdb_api.Tmdb
    _posters_down_until: float
    rawg: rawg_api.Rawg
    mdblist: mdblist_api.MdbList
    letterboxd: letterboxd_api.Letterboxd
    # Conectar Trakt con un código (mine.py): `_link_lock` cuida `_link` y `_link_gen`.
    _link: trakt_api.DeviceCode | None
    _link_lock: threading.Lock
    _link_gen: int
    # Logos de los títulos (titles.py).
    _dark: dict[str, bool | None]
    logo_dir: Path | None
    _logos: dict[str, bytes]
    _logo_pool: ThreadPoolExecutor
    _studio_logos_busy: bool
    _logo_misses: dict[str, float]
    gestor: Gestor

    def _key(self, name: str) -> str:
        return (self.services.credentials.get(KEY_PREFIX + name) or "") or getattr(self.settings, name)

    def key(self, name: str) -> str:
        """La clave vigente (la escrita en la TV o la de config.yaml): también se la lleva la app del iPhone."""
        return self._key(name)

    def _build(self) -> None:
        self.trakt = trakt_api.Trakt(self._key("trakt_client_id"), self._key("trakt_client_secret"), self.services.credentials)
        self.tmdb = tmdb_api.Tmdb(self._key("tmdb_key"))
        self._posters_down_until = 0.0
        self.rawg = rawg_api.Rawg(self._key("rawg_key"))
        self.mdblist = mdblist_api.MdbList(self._key("mdblist_key"))
        self.letterboxd = letterboxd_api.Letterboxd(self._key("letterboxd_user"))

    def set_keys(self, service: str, values: list[str]) -> None:
        """Guarda (o, vacías, quita) las claves de un servicio escritas en Ajustes › Cuentas. TMDB y
        RAWG se prueban antes de guardar: una clave mal copiada se dice aquí, no en una lista vacía."""
        names = KEYS.get(service)
        if not names or len(values) != len(names):
            raise ValueError("Servicio inválido")
        values = [str(v or "").strip() for v in values]
        if service == "letterboxd" and values[0]:
            user = letterboxd_api.clean_user(values[0])
            if not user:
                raise ValueError("Escribe tu usuario de Letterboxd: el de letterboxd.com/tu-usuario (letras, números y «_»).")
            try:
                letterboxd_api.Letterboxd(user).diary()
            except letterboxd_api.LetterboxdNotFound as exc:
                raise ValueError(f"No encontré «{user}» en Letterboxd.") from exc
            values = [user]
        if any(len(v) > 400 or not re.fullmatch(r"[!-~]*", v) for v in values):
            raise ValueError("Esa clave tiene espacios o caracteres raros: cópiala otra vez.")
        if any(values[1:]) and not values[0]:  # Trakt: el Client Secret es opcional (las aplicaciones nuevas no tienen)
            raise ValueError("Falta el Client ID.")
        if service == "tmdb" and values[0]:
            tmdb_api.Tmdb(values[0]).platforms(self.region)
        elif service == "rawg" and values[0]:
            rawg_api.Rawg(values[0]).games("best", size=1)
        elif service == "mdblist" and values[0]:
            try:
                mdblist_api.MdbList(values[0]).check()
            except mdblist_api.MdbListError as exc:
                raise ValueError(str(exc)) from exc
        elif service == "steamgriddb" and values[0]:
            from ..library.scraper import Http, SteamGridDB

            if SteamGridDB(Http(pause=0), lambda: values[0])._get("/search/autocomplete/mario") is None:  # noqa: SLF001
                raise ValueError("SteamGridDB no aceptó esa clave: cópiala otra vez de Preferences › API.")
        changed = any(self.services.credentials.get(KEY_PREFIX + n) != (v or None) for n, v in zip(names, values, strict=True))
        if service == "trakt" and changed and self.trakt.linked:
            self.trakt.unlink()  # la sesión era de la otra aplicación de Trakt: ya no sirve
        for name, value in zip(names, values, strict=True):
            self.services.credentials.set(KEY_PREFIX + name, value or None)
        self._build()
        self.cache.clear()
        self.publish({"type": "foryou-changed"})

    def publish(self, event: dict) -> None:
        self.services.events.publish(event)

    # --- qué hay -----------------------------------------------------------------------------
    def status(self) -> dict:
        return {"trakt": {"configured": self.trakt.configured, "linked": self.trakt.linked,
                          # Lo último que el reproductor le contó a Trakt (o por qué no pudo): Ajustes › Cuentas.
                          "scrobble": self.services.watch.scrobbler.snapshot()},
                "tmdb": self.tmdb.configured, "rawg": self.rawg.configured, "mdblist": bool(self.mdblist.key),
                "steamgriddb": bool(self._key("steamgriddb_key")),
                "letterboxd": self.letterboxd.user,  # tu usuario («Cuentas» lo enseña) o None
                # Cuáles escribiste en Ajustes (esas se pueden quitar desde ahí; las de config.yaml, no).
                "saved": [s for s, names in KEYS.items() if self.services.credentials.get(KEY_PREFIX + names[0])]}

    def _today(self) -> date:
        return date.today()

    def _country(self) -> str:
        return {"MX": "México", "US": "Estados Unidos", "ES": "España", "AR": "Argentina", "CO": "Colombia",
                "CL": "Chile", "PE": "Perú"}.get(self.region, self.region)

    @staticmethod
    def _safe(call):
        try:
            return call()
        except SERVICE_ERRORS:
            return None

    @staticmethod
    def _interleave(batches: list[list[dict]]) -> list[dict]:
        """Una de cada fuente por turno: así el mosaico no es solo recomendaciones."""
        out, i = [], 0
        while any(i < len(b) for b in batches):
            out += [b[i] for b in batches if i < len(b)]
            i += 1
        return out
