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
"""

from __future__ import annotations

import json
import logging
import os
import random
import re
import threading
import time
import urllib.parse
import urllib.request
from collections.abc import Callable
from concurrent.futures import ThreadPoolExecutor
from datetime import date, datetime, timedelta
from pathlib import Path
from typing import Any

from . import decide as decide_api
from .library import charts as charts_api
from .library import rawg as rawg_api
from .library import stremio_api
from .library import tmdb as tmdb_api
from .library import trakt as trakt_api
from .net import NET_ERRORS, read_json
from .text import clock

log = logging.getLogger(__name__)

METAHUB = "https://images.metahub.space/{kind}/medium/{imdb}/img"
PREFETCH_DELAY = 45  # s tras armar el mosaico, antes de bajar sus imágenes (que el arranque termine primero)
LOGO_RETRY = 30 * 60  # un logo que no se pudo bajar (o que no existe) no se vuelve a pedir en media hora
LOGO_WARM = 12  # de cada lista, los logos que se bajan antes de que se pidan
STEAM_ART = "https://cdn.cloudflare.steamstatic.com/steam/apps/{appid}/{file}"
GAME_CATEGORIES = ("steam", "emulators")
SERVICE_ERRORS = (trakt_api.TraktError, tmdb_api.TmdbError, rawg_api.RawgError, stremio_api.StremioError,
                  charts_api.ChartsError) + NET_ERRORS
# JustWatch, con su propio riel «Lo más visto en…» (Netflix ya tiene el Top 10 oficial: chart:netflix).
JW_LIST_BRANDS = ("disney", "hbo", "prime", "appletv", "paramount")

# Cuánto vale lo que se trajo (s): lo tuyo cambia seguido; lo popular, no tanto.
MINE_TTL = 15 * 60
RECS_TTL = 60 * 60
POPULAR_TTL = 6 * 3600
SLOW_TTL = 24 * 3600

CALENDAR_DAYS = 14  # lo que enseña «Próximos estrenos»: dos semanas
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

# Las claves de cada servicio. Las que escribes en Ajustes › Cuentas se guardan cifradas con las
# credenciales (como la sesión de Stremio) y mandan sobre las de config.yaml.
# Películas y series (como Para ti › Listas del iPhone): premios fijos, «Nuevo en tus plataformas», estudios y por año.
AWARDS_FILE = Path(__file__).resolve().parent.parent / "design" / "awards.json"  # compartido con el iPhone
AWARD_TINTS = ("gold", "silver", "bronze")
FRESH_BRANDS = ("netflix", "disney", "hbo")  # «Nuevo en tus plataformas» las alterna, como el iPhone
FRESH_SERIES_DAYS, FRESH_MOVIE_DAYS = 14, 90
FIRST_YEAR = 1980  # «Por año», del actual hacia atrás
# Lo que solo arma la TV (el iPhone calcula los suyos): no viaja por el túnel (server._foryou_public_routes).
TV_ONLY_PREFIXES = ("because", "fresh", "award:", "studio:", "year:")


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


KEYS = {"trakt": ("trakt_client_id", "trakt_client_secret"), "tmdb": ("tmdb_key",), "rawg": ("rawg_key",)}
KEY_PREFIX = "para_ti."


# ---------------------------------------------------------------- textos
def runtime_text(minutes: int | None) -> str | None:
    if not minutes:
        return None
    hours, rest = divmod(int(minutes), 60)
    return f"{hours} h {rest} min" if hours and rest else f"{hours} h" if hours else f"{rest} min"


def hours_text(seconds: float) -> str:
    """«48 h», «1 h 30 min», «35 min»: lo jugado."""
    minutes = int(seconds // 60)
    if minutes < 60:
        return f"{minutes} min"
    return f"{minutes // 60} h" if minutes >= 600 or minutes % 60 == 0 else f"{minutes // 60} h {minutes % 60} min"


def fold(text: str) -> str:
    """Para comparar títulos: «Baldur's Gate 3» y «Baldurs Gate III» no, pero «HADES» y «Hades» sí."""
    return re.sub(r"[^a-z0-9]+", "", str(text or "").lower())


# ---------------------------------------------------------------- caché
class Cache:
    """Lo que se trajo de internet, con fecha. Si al renovar falla la red se queda lo de antes; dos
    peticiones a la vez por lo mismo esperan a una sola descarga."""

    SAVE_DELAY = 5.0  # s: varias listas que llegan juntas se guardan de una vez

    def __init__(self, clock: Callable[[], float] = time.time, path: Path | None = None) -> None:
        self.clock = clock
        self._data: dict[str, tuple[float, Any]] = {}
        self._locks: dict[str, threading.Lock] = {}
        self._lock = threading.Lock()
        # Modo sin internet: lo último que se trajo queda en disco. Al arrancar sin conexión, Para ti y Películas y series
        # enseñan eso (vencido, pero mejor que nada); con conexión, se renueva como siempre.
        self.path = path
        self._save_timer: threading.Timer | None = None
        if path is not None:
            self._load()

    def _load(self) -> None:
        try:
            raw = json.loads(self.path.read_text(encoding="utf-8")) if self.path and self.path.exists() else {}
        except (OSError, ValueError) as exc:
            log.info("Para ti: no pude leer lo guardado (%s): empiezo de cero", exc)
            return
        for key, entry in raw.items() if isinstance(raw, dict) else []:
            if isinstance(entry, list) and len(entry) == 2 and isinstance(entry[0], (int, float)):
                self._data[key] = (float(entry[0]), entry[1])

    def _schedule_save(self) -> None:
        if self.path is None:
            return
        with self._lock:
            if self._save_timer is not None:
                return
            self._save_timer = threading.Timer(self.SAVE_DELAY, self._save)
            self._save_timer.daemon = True
            self._save_timer.start()

    def _save(self) -> None:
        with self._lock:
            self._save_timer = None
            data = dict(self._data)
        path = self.path
        if path is None:
            return
        out = {}
        for key, (when, value) in data.items():
            try:
                json.dumps(value)  # solo lo que se puede guardar tal cual (listas y fichas)
            except (TypeError, ValueError):
                continue
            out[key] = [when, value]
        try:
            path.parent.mkdir(parents=True, exist_ok=True)
            tmp = path.with_suffix(".tmp")
            tmp.write_text(json.dumps(out, ensure_ascii=False), encoding="utf-8")
            tmp.replace(path)
        except OSError as exc:
            log.info("Para ti: no pude guardar lo traído: %s", exc)

    def get(self, key: str, ttl: float, load: Callable[[], Any], *, stale: bool = False) -> Any:
        """`stale`: si ya venció, devuelve lo de antes al instante y lo renueva en segundo plano (el iPhone y la TV
        no esperan 30 s al Top 10 de Netflix: con caché fría el iPhone se rendía y no enseñaba ni Top 10 ni Disney)."""
        with self._lock:
            hit = self._data.get(key)
            lock = self._locks.setdefault(key, threading.Lock())
        if hit and self.clock() - hit[0] < ttl:
            return hit[1]
        if hit and stale:
            if lock.acquire(blocking=False):  # una sola renovación a la vez
                threading.Thread(target=self._refresh, args=(key, load, lock), daemon=True, name=f"cache:{key}").start()
            return hit[1]
        with lock:
            with self._lock:
                hit = self._data.get(key)
            if hit and self.clock() - hit[0] < ttl:
                return hit[1]
            try:
                value = load()
            except SERVICE_ERRORS:
                if hit:  # sin internet: lo de la última vez
                    return hit[1]
                raise
            with self._lock:
                self._data[key] = (self.clock(), value)
            self._schedule_save()
            return value

    def _refresh(self, key: str, load: Callable[[], Any], lock: threading.Lock) -> None:
        try:
            value = load()
            with self._lock:
                self._data[key] = (self.clock(), value)
            self._schedule_save()
        except SERVICE_ERRORS as exc:  # sin red: se queda lo de antes
            log.warning("Para ti: no pude renovar %s: %s", key, exc)
        finally:
            lock.release()

    def clear(self, prefix: str = "") -> None:
        with self._lock:
            for key in [k for k in self._data if k.startswith(prefix)]:
                del self._data[key]

    def peek(self, key: str) -> Any:
        """Lo último que se trajo para `key` (aunque ya venció), sin salir a internet; None si nunca."""
        with self._lock:
            hit = self._data.get(key)
        return hit[1] if hit else None


# ---------------------------------------------------------------- piezas
def video_item(e: dict, why: str, *, title: str | None = None, poster: str | None = None,
               wide: str | None = None, overview: str | None = None, seasons: int | None = None) -> dict:
    """Una película o serie: lo que necesita el mosaico, las listas, la ficha y el reproductor."""
    imdb, kind = e["imdb"], e["kind"]
    nxt = e.get("next")
    episode = f"T{nxt['season']} E{nxt['episode']}" if nxt else None
    if kind == "movie":
        detail = runtime_text(e.get("runtime")) or (str(e["year"]) if e.get("year") else "")
        facts = [["Duración", runtime_text(e.get("runtime"))], ["Año", e.get("year")]]
        video_id, action = imdb, "Ver"
    else:
        count = f"{seasons} temporada{'s' if seasons != 1 else ''}" if seasons else (
            f"{e['episodes']} episodios" if e.get("episodes") else None)
        detail = f"Sigue {episode}" if episode else count or (str(e["year"]) if e.get("year") else "")
        facts = [["Sigue", episode] if episode else ["Temporadas", seasons] if seasons else ["Episodios", e.get("episodes")],
                 ["Año", e.get("year")]]
        video_id = f"{imdb}:{nxt['season']}:{nxt['episode']}" if nxt else f"{imdb}:1:1"
        # Una serie abre su ficha (temporadas, sinopsis, en qué episodio vas), nunca un episodio directo.
        action = "Ver la serie"
    return {
        "key": f"video:{imdb}", "id": f"cinemeta:{kind}:{imdb}", "source": "cinemeta", "kind": kind, "meta_id": imdb,
        "title": title or e["title"], "year": e.get("year"), "why": why, "detail": detail,
        "facts": [[k, str(v)] for k, v in facts if v],
        "image": poster or METAHUB.format(kind="poster", imdb=imdb),
        "hero": wide or METAHUB.format(kind="background", imdb=imdb),
        "logo": METAHUB.format(kind="logo", imdb=imdb),
        "overview": overview or "", "video_id": video_id, "episode": episode, "action": action,
        # Para «Decide por mí» del iPhone (sin preguntarle a Cinemeta título por título): en inglés, como vienen.
        **({"genres": list(e["genres"])} if e.get("genres") else {}),
        **({"runtime": int(e["runtime"])} if isinstance(e.get("runtime"), int) and e["runtime"] > 0 else {}),
        # La calificación de Trakt (para ordenar «Mejor calificadas en Trakt», en la TV y en el iPhone).
        **({"rating": e["rating"]} if isinstance(e.get("rating"), (int, float)) and e["rating"] > 0 else {}),
    }


def library_entry(item) -> dict | None:
    """Un título que Orbital ya tiene (tu Stremio o lo popular de Cinemeta), en la forma de video_item."""
    extra = item.extra or {}
    imdb, kind = str(extra.get("meta_id") or ""), extra.get("kind")
    if not re.fullmatch(r"tt\d+", imdb) or kind not in ("movie", "series"):
        return None
    year = re.match(r"\d{4}", str(extra.get("year") or ""))
    minutes = re.match(r"\d+", str(extra.get("runtime") or ""))
    e: dict[str, Any] = {"imdb": imdb, "kind": kind, "title": item.title, "year": int(year.group()) if year else None}
    if minutes:  # en una serie, lo que dura un episodio
        e["runtime"] = int(minutes.group())
    if isinstance(extra.get("genres"), list) and extra["genres"]:
        e["genres"] = [str(g) for g in extra["genres"]][:4]
    parts = str(extra.get("video_id") or "").split(":")
    if kind == "series" and len(parts) == 3 and parts[1].isdigit() and parts[2].isdigit():
        e["next"] = {"season": int(parts[1]), "episode": int(parts[2])}  # el episodio en que vas
    return e


def day_label(day: date, today: date) -> tuple[str, str]:
    """(«Hoy», «jueves 15») · («Mañana», «viernes 16») · («Domingo 18», «octubre»)."""
    name = f"{WEEKDAYS[day.weekday()]} {day.day}"
    delta = (day - today).days
    if delta == 0:
        return "Hoy", name
    if delta == 1:
        return "Mañana", name
    months = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre"]
    return name[:1].upper() + name[1:], months[day.month - 1]


def calendar_item(g: dict, today: date) -> dict:
    """Un estreno («Próximos estrenos»): la serie (A abre su ficha) con su día, hora, episodio y dónde sale."""
    when: datetime = g["when"]
    time_text = "Desde la madrugada" if when.hour < DAWN_HOUR else clock(when)
    if g["count"] > 1:
        episode = f"T{g['season']} E{g['first']}–E{g['last']}"
        episode_long = f"{episode} · {g['count']} episodios"
    else:
        episode = f"T{g['season']} E{g['episode']}"
        episode_long = f"{episode} · {g['episode_title']}" if g.get("episode_title") else episode
    day, sub = day_label(when.date(), today)
    when_text = f"{day} · madrugada" if when.hour < DAWN_HOUR else f"{day} · {time_text}"
    item = video_item({**g, "kind": "series", "next": None}, "Sale hoy" if day == "Hoy" else day)
    return {**item, "key": f"video:{g['imdb']}", "day": when.date().isoformat(), "day_label": day, "day_sub": sub,
            "time": time_text, "today": day == "Hoy", "episode": None, "episode_label": episode, "network": g.get("network") or "",
            "detail": " · ".join(p for p in (time_text, g.get("network")) if p),
            # Datos cortos (la ficha los pinta en una fila); el nombre del episodio va en la descripción.
            "facts": [[k, v] for k, v in (("Cuándo", when_text), ("Episodio", episode), ("Dónde", g.get("network") or "")) if v],
            "overview": " · ".join(p for p in (episode_long if (g["count"] > 1 or g.get("episode_title")) else "", item.get("overview")) if p)}


def game_item(described: dict, why: str) -> dict:
    """Un juego tuyo (de la biblioteca): A lo abre como en Juegos."""
    played = float(described.get("playtime") or 0)
    detail = f"{hours_text(played)} jugadas" if played >= 60 else "Nunca lo has abierto"
    extra = described.get("extra") or {}
    steam_id = str(described["id"]).removeprefix("steam:")
    appid = extra.get("steam_appid") or described.get("steam_appid") or (
        int(steam_id) if str(described["id"]).startswith("steam:") and steam_id.isdigit() else None)
    return {
        "key": f"game:{described['id']}", "id": described["id"], "kind": "game", "item": described, "owned": True,
        "title": described["title"], "why": why, "detail": detail,
        "facts": [["Jugadas", hours_text(played) if played >= 60 else "0 h"]],
        "image": described.get("image"), "hero": described.get("hero") or described.get("image"),
        "logo": extra.get("logo"), "overview": "", "action": "Jugar",
        "steam_appid": appid or None,
        # El «hero» de Steam es un fondo hecho para llevar el logo encima (el de Cult of the Lamb es un
        # patrón de corderitos): sin foco, la pieza ancha usa la cápsula de la tienda, que sí lleva el juego.
        "wide": STEAM_ART.format(appid=appid, file="capsule_616x353.jpg") if appid else None,
        # Sin un fondo ancho de verdad (el respaldo de Orbital o una captura chiquita): siempre en vertical.
        "hero_weak": bool(extra.get("placeholder_hero") or extra.get("hero_lowres")),
        "placeholder": bool(extra.get("placeholder_cover")),  # sin portada propia: la genérica de Orbital
    }


def whiten_if_dark(png: bytes) -> bytes:
    """Un logo oscuro (negro sobre transparente, como el de Severance) en blanco: sobre los fondos de Orbital no se veía en
    la ficha ni en el héroe. Los de color se dejan como vienen."""
    try:
        import io

        from PIL import Image

        image = Image.open(io.BytesIO(png)).convert("RGBA")
        small = image.copy()
        small.thumbnail((96, 96))
        visible = [px[:3] for px in small.getdata() if isinstance(px, tuple) and len(px) == 4 and px[3] > 128]
        if not visible or sum(.2126 * r + .7152 * g + .0722 * b for r, g, b in visible) / len(visible) >= 64:
            return png
        alpha = image.getchannel("A")
        white = Image.new("RGBA", image.size, (255, 255, 255, 255))
        white.putalpha(alpha)
        out = io.BytesIO()
        white.save(out, "PNG")
        return out.getvalue()
    except Exception:  # noqa: BLE001 - sin Pillow o un PNG raro: el logo como venía
        return png


class ForYou:
    def __init__(self, config, catalog) -> None:
        self.settings = config.para_ti
        self.catalog = catalog
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
        self._skipped: dict[str, float] = {}  # «Hoy no» de ¿Qué vemos?: IMDb → cuándo

    def _key(self, name: str) -> str:
        return (self.catalog.credentials.get(KEY_PREFIX + name) or "") or getattr(self.settings, name)

    def key(self, name: str) -> str:
        """La clave vigente (la escrita en la TV o la de config.yaml): también se la lleva la app del iPhone."""
        return self._key(name)

    def _build(self) -> None:
        self.trakt = trakt_api.Trakt(self._key("trakt_client_id"), self._key("trakt_client_secret"), self.catalog.credentials)
        self.tmdb = tmdb_api.Tmdb(self._key("tmdb_key"))
        self.rawg = rawg_api.Rawg(self._key("rawg_key"))

    def set_keys(self, service: str, values: list[str]) -> None:
        """Guarda (o, vacías, quita) las claves de un servicio escritas en Ajustes › Cuentas. TMDB y
        RAWG se prueban antes de guardar: una clave mal copiada se dice aquí, no en una lista vacía."""
        names = KEYS.get(service)
        if not names or len(values) != len(names):
            raise ValueError("Servicio inválido")
        values = [str(v or "").strip() for v in values]
        if any(len(v) > 400 or not re.fullmatch(r"[!-~]*", v) for v in values):
            raise ValueError("Esa clave tiene espacios o caracteres raros: cópiala otra vez.")
        if any(values[1:]) and not values[0]:  # Trakt: el Client Secret es opcional (las aplicaciones nuevas no tienen)
            raise ValueError("Falta el Client ID.")
        if service == "tmdb" and values[0]:
            tmdb_api.Tmdb(values[0]).platforms(self.region)
        elif service == "rawg" and values[0]:
            rawg_api.Rawg(values[0]).games("best", size=1)
        changed = any(self.catalog.credentials.get(KEY_PREFIX + n) != (v or None) for n, v in zip(names, values, strict=True))
        if service == "trakt" and changed and self.trakt.linked:
            self.trakt.unlink()  # la sesión era de la otra aplicación de Trakt: ya no sirve
        for name, value in zip(names, values, strict=True):
            self.catalog.credentials.set(KEY_PREFIX + name, value or None)
        self._build()
        self.cache.clear()
        self.publish({"type": "foryou-changed"})

    def publish(self, event: dict) -> None:
        self.catalog.events.publish(event)

    # --- qué hay -----------------------------------------------------------------------------
    def status(self) -> dict:
        return {"trakt": {"configured": self.trakt.configured, "linked": self.trakt.linked,
                          # Lo último que el reproductor le contó a Trakt (o por qué no pudo): Ajustes › Cuentas.
                          "scrobble": self.catalog.watch.scrobbler.snapshot()},
                "tmdb": self.tmdb.configured, "rawg": self.rawg.configured,
                # Cuáles escribiste en Ajustes (esas se pueden quitar desde ahí; las de config.yaml, no).
                "saved": [s for s, names in KEYS.items() if self.catalog.credentials.get(KEY_PREFIX + names[0])]}

    def platforms(self) -> dict[str, dict]:
        if not self.tmdb.configured:
            return {}
        try:
            return self.cache.get("tmdb:platforms", SLOW_TTL, lambda: self.tmdb.platforms(self.region))
        except SERVICE_ERRORS as exc:
            log.warning("Para ti: no pude leer las plataformas de TMDB: %s", exc)
            return {}

    # --- tus complementos de Stremio -----------------------------------------------------------
    def addon_catalogs(self) -> list[dict]:
        """Los catálogos de tus complementos de Stremio que agregan algo: uno por nombre, con sus tipos
        (series y películas) y de qué complemento salen. Sin Stremio conectado o sin red: ninguno."""
        auth = self.catalog.credentials.get("stremio_auth_key")
        if not auth:
            return []
        try:
            addons = self.cache.get("stremio:addons", SLOW_TTL, lambda: self._addons(auth))
        except SERVICE_ERRORS as exc:
            log.warning("Para ti: no pude leer tus complementos de Stremio: %s", exc)
            return []
        covered = {fold(name) for name, _ in tmdb_api.PLATFORMS.values()} if self.platforms() else set()
        found: dict[str, dict] = {}
        for addon in addons:
            name = addon["name"]
            if any(word in name.lower() for word in SKIP_ADDONS):
                continue
            if name.lower() == TRAKT_ADDON and self.trakt.linked:
                continue  # Trakt conectado: esas listas ya llegan de Trakt
            for cat in addon["catalogs"]:
                title = cat["name"].removeprefix("Trakt ").strip() if name.lower() == TRAKT_ADDON else cat["name"]
                if cat["type"] not in ("movie", "series") or cat["name"].lower() in GENERIC_CATALOGS or fold(title) in covered:
                    continue
                key = f"addon:{fold(name)}:{cat['id']}"
                entry = found.setdefault(key, {"id": key, "title": title, "addon": name, "base": addon["base"],
                                               "catalog": cat["id"], "kinds": []})
                entry["kinds"].append(cat["type"])
        return list(found.values())

    def _addons(self, auth: str) -> list[dict]:
        raw = self.catalog.stremio_client.request("addonCollectionGet", {"authKey": auth, "update": True})
        rows = raw.get("addons") if isinstance(raw, dict) else raw
        addons = []
        for row in rows if isinstance(rows, list) else []:
            manifest = row.get("manifest") if isinstance(row, dict) else None
            url = str(row.get("transportUrl") or "") if isinstance(row, dict) else ""
            if not isinstance(manifest, dict) or not url.startswith("https://") or not url.endswith("/manifest.json"):
                continue
            catalogs = [c for c in manifest.get("catalogs") or [] if isinstance(c, dict) and c.get("id") and c.get("name")
                        and not any(isinstance(e, dict) and e.get("isRequired") for e in c.get("extra") or [])]
            if catalogs:
                addons.append({"name": str(manifest.get("name") or ""), "base": url.removesuffix("/manifest.json"),
                               "catalogs": [{"id": str(c["id"]), "name": str(c["name"]), "type": c.get("type")} for c in catalogs]})
        return addons

    def _addon_list(self, entry: dict, kind: str) -> list[dict]:
        kind = kind if kind in entry["kinds"] else entry["kinds"][0]
        url = f"{entry['base']}/catalog/{kind}/{urllib.parse.quote(entry['catalog'], safe='')}.json"
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "Orbital"}), timeout=12) as res:
                data = read_json(res, timeout=12)
        except (*NET_ERRORS, ValueError) as exc:  # sin red, o algo que no es JSON
            raise stremio_api.StremioError(f"{entry['addon']} no respondió: {exc}") from exc
        metas = data.get("metas") if isinstance(data, dict) else None
        why = {"Watchlist": "En tu watchlist", "Recommendations": "Recomendada"}.get(entry["title"], f"En {entry['title']}")
        items = []
        for m in metas if isinstance(metas, list) else []:
            if not isinstance(m, dict) or not re.fullmatch(r"tt\d+", str(m.get("id") or "")) or not isinstance(m.get("name"), str):
                continue
            year = re.match(r"\d{4}", str(m.get("releaseInfo") or m.get("year") or ""))
            e = {"imdb": m["id"], "kind": kind, "title": m["name"], "year": int(year.group()) if year else None}
            items.append(video_item(e, why, wide=m.get("background") if isinstance(m.get("background"), str) else None,
                                    overview=str(m.get("description") or "")[:600]))
        return items[:60]

    def lists(self) -> list[dict]:
        """El riel: una entrada por lista (solo las de los servicios que tienes)."""
        video: list[dict] = []
        # Lo de tu Stremio no necesita ninguna clave: sin Trakt, «Para ti» no se queda solo con juegos.
        if self._stremio("continue"):
            video.append({"id": "continue", "title": "Seguir viendo", "icon": "watching", "source": "Stremio", "meta": "Lo que dejaste a medias"})
        if self._stremio("mylist"):
            video.append({"id": "mylist", "title": "Mi lista", "icon": "library", "source": "Stremio", "meta": "Tu biblioteca"})
        if self.trakt.linked:
            video += [
                {"id": "recs", "title": "Recomendadas", "icon": "spark", "source": "Trakt", "meta": "Por lo que has visto", "split": True},
                {"id": "mine", "title": "Tus series", "icon": "series", "source": "Trakt", "meta": "Las que estás viendo"},
                {"id": "watchlist", "title": "Tu watchlist", "icon": "bookmark", "source": "Trakt", "meta": "Lo que dejaste pendiente"},
                # Dos formas de verlo (las píldoras de arriba): por día, o la semana como una guía de TV.
                {"id": "estrenos", "title": "Próximos estrenos", "icon": "calendar", "source": "Trakt", "meta": "Las series que sigues",
                 "views": [{"id": "day", "label": "Por día"}, {"id": "week", "label": "Semana"}]},
            ]
            try:
                own = self.cache.get("trakt:lists", MINE_TTL, self.trakt.lists)
            except SERVICE_ERRORS as exc:
                log.warning("Para ti: no pude leer tus listas de Trakt: %s", exc)
                own = []
            video += [{"id": f"list:{row['id']}", "title": row["name"], "icon": "list", "source": "Trakt", "meta": "Tu lista"}
                      for row in own[:8]]
        if self.trakt.configured:
            video += [
                {"id": "trend", "title": "En tendencia", "icon": "trend", "source": "Trakt", "meta": "Lo más visto esta semana", "split": True},
                {"id": "popular", "title": "Lo más popular", "icon": "flame", "source": "Trakt", "meta": "De todos los tiempos", "split": True},
            ]
        elif self._stremio("cinemeta"):
            video.append({"id": "cinemeta", "title": "Lo más popular", "icon": "flame", "source": "Stremio",
                          "meta": "En el catálogo de Stremio", "split": True})
        for entry in self.addon_catalogs():
            video.append({"id": entry["id"], "title": entry["title"], "icon": "addon", "source": "Stremio",
                          "meta": f"De {entry['addon']}", "split": len(entry["kinds"]) > 1})
        # Netflix (Top 10 oficial) y JustWatch (lo más visto por plataforma): ninguna pide clave.
        video.append({"id": "chart:netflix", "title": "Top 10 en Netflix", "icon": "chart", "source": "Netflix",
                      "meta": self._netflix_meta(), "split": True, "brand": "netflix",
                      "logo": self.platforms().get("netflix", {}).get("logo")})
        for brand in JW_LIST_BRANDS:
            name = charts_api.JUSTWATCH_PACKAGES[brand][1]
            # «Lo más visto» solo en Netflix (cuenta vistas); JustWatch mide interés: «Tendencias».
            video.append({"id": f"jw:{brand}", "title": f"Tendencias en {name}", "icon": "chart", "source": "JustWatch",
                          "meta": f"Tendencia en JustWatch · {self._country()}", "split": True, "brand": brand,
                          "logo": charts_api.justwatch_logo(brand)})
        found = self.platforms()
        for brand, (name, _) in tmdb_api.PLATFORMS.items():
            # Respaldo de cada plataforma: va siempre (si JustWatch trae películas pero no series, con «Series» no quedaba
            # nada de Disney). `fallback_for` dice de qué lista es respaldo y `covered`, qué tipos esa lista ya trae (de lo
            # que hay en caché: el riel no espera a JustWatch). La TV lo esconde si la lista con puesto trae los dos; el
            # iPhone, por tipo (ShelfPlan.isFallback).
            if brand in found:
                ranked = self._ranked_list(brand)
                video.append({"id": brand, "title": name, "brand": brand, "logo": found[brand]["logo"], "icon": "chart", "source": "TMDB",
                              "meta": f"Lo más popular en {self._country()}", "split": True,
                              "fallback_for": ranked, "covered": self._covered(ranked) if ranked else []})
        video += self._collections()
        games: list[dict] = [{"id": "mygames", "title": "Tus juegos", "icon": "gamepad", "source": "",
                              "meta": "Favoritos, los más jugados y los que no has abierto"}]
        if self.rawg.configured:
            games += [
                {"id": "rawg:new", "title": "Novedades", "icon": "fresh", "source": "RAWG", "meta": "Lo que acaba de salir"},
                {"id": "rawg:popular", "title": "Lo más popular", "icon": "flame", "source": "RAWG", "meta": "Lo que más se juega este año"},
                {"id": "rawg:best", "title": "Mejor calificados", "icon": "trophy", "source": "RAWG", "meta": "Por Metacritic"},
            ]
        return [{**row, "group": "video"} for row in video] + [{**row, "group": "games"} for row in games]

    def _collections(self) -> list[dict]:
        """Lo de Películas y series que viene del iPhone (Para ti › Listas): «Porque viste X», «Nuevo en tus plataformas»,
        los premios, los estudios y los años. `collection` dice qué tarjeta lleva (award, studio, year) en la TV."""
        out: list[dict] = []
        if self.trakt.linked:
            seeds = self._recent_seeds()
            seed = self._seed_of_day(seeds) if seeds else None
            if seed:
                # Como el iPhone: cada día otro de los primeros cinco (si uno no tiene relacionados, el siguiente), y se
                # puede elegir entre tus últimos 12 (`seeds`; la lista «because:<imdb>»).
                card = lambda s: {"meta_id": s["imdb"], "kind": s["kind"], "title": s["title"],  # noqa: E731
                                  "image": METAHUB.format(kind="poster", imdb=s["imdb"]), "watched_at": s.get("watched_at")}
                out.append({"id": "because", "title": f"Porque viste {seed['title']}", "icon": "spark", "source": "Trakt",
                            "meta": "Lo que Trakt relaciona con algo que viste hace poco",
                            "seed": card(seed), "seeds": [card(s) for s in seeds]})
        if self.tmdb.configured and any(b in self.platforms() for b in FRESH_BRANDS):
            out.append({"id": "fresh", "title": "Nuevo en tus plataformas", "icon": "fresh", "source": "TMDB",
                        "meta": "Episodios de estas dos semanas y películas recién llegadas", "split": True})
        for a in load_awards():
            out.append({"id": f"award:{a['id']}", "title": a["title"], "meta": a.get("category") or "", "icon": "trophy",
                        "source": "Orbital", "collection": "award", "kinds": [a["kind"]], "tint": a["tint"],
                        "statue": f"/img/awards/{a['id']}.png", "count": len(a["winners"])})
        if self.tmdb.configured:
            logos = self._studio_logos()
            out += [{"id": f"studio:{sid}", "title": name, "meta": "Lo más popular del estudio", "icon": "film", "source": "TMDB",
                     "collection": "studio", "kinds": ["movie"], **({"logo": logos[str(sid)]} if logos.get(str(sid)) else {})}
                    for sid, name in tmdb_api.STUDIOS]
        if self.trakt.configured:
            this_year = datetime.now().year
            out += [{"id": f"year:{y}", "title": str(y), "meta": f"Lo más popular de {y}", "icon": "calendar", "source": "Trakt",
                     "collection": "year", "split": True} for y in range(this_year, FIRST_YEAR - 1, -1)]
        return out

    def imdb_ratings(self, wanted: list[tuple[str, str]]) -> dict[str, float]:
        """La calificación de IMDb de cada título (de Cinemeta, varios a la vez; se recuerda un día), para ordenar una lista
        «Mejor calificadas en IMDb», como el iPhone. Los que Cinemeta no tiene no salen."""
        def one(pair: tuple[str, str]) -> tuple[str, float | None]:
            kind, imdb = pair

            def load() -> float | None:
                try:
                    raw = self.catalog.cinemeta.meta(kind, imdb, localized=False).get("imdbRating")
                    return float(raw) if raw not in (None, "") else None
                except Exception:  # noqa: BLE001 - sin calificación no pasa nada
                    return None
            return imdb, self.cache.get(f"imdb:rating:{imdb}", SLOW_TTL, load)

        pairs = [(k if k in ("movie", "series") else "movie", i) for k, i in wanted if isinstance(i, str) and i.startswith("tt")][:120]
        with ThreadPoolExecutor(max_workers=12) as pool:
            return {imdb: rating for imdb, rating in pool.map(one, pairs) if rating}

    def saved_in(self, kind: str, imdb: str) -> dict:
        """«Guardar en…» (como el iPhone): si el título está en tu watchlist y en cuáles de tus listas de Trakt. Se
        pregunta a Trakt al momento (no a lo guardado en caché): lo que cambiaste en el iPhone ya cuenta."""
        t = self.trakt
        if not t.linked or not imdb.startswith("tt"):
            return {"trakt": False, "watchlist": False, "lists": []}
        lists = t.lists()

        def members(list_id: str) -> list[dict] | None:
            try:
                return t.list_items(list_id)
            except SERVICE_ERRORS:  # una lista que no responde no tumba las demás
                return None

        with ThreadPoolExecutor(max_workers=6) as pool:
            watch = pool.submit(t.watchlist)
            found = [pool.submit(members, row["id"]) for row in lists]
            in_watch = any(e["imdb"] == imdb for e in watch.result())
            out = [{**row, "contains": any(e["imdb"] == imdb for e in f.result() or [])}
                   for row, f in zip(lists, found, strict=True) if f.result() is not None]
        return {"trakt": True, "watchlist": in_watch, "lists": out}

    def save_to(self, kind: str, imdb: str, where: str, add: bool) -> None:
        """Añadir o quitar de tu watchlist («watchlist») o de una de tus listas de Trakt («list:123»). Las filas de esa
        lista se vuelven a pedir (en la TV y en Para ti)."""
        if where == "watchlist":
            self.trakt.set_watchlist(kind, imdb, add)
            self.cache.clear("trakt:watchlist")
        elif where.startswith("list:") and where[5:].isdigit():
            self.trakt.set_list_item(where[5:], kind, imdb, add)
            self.cache.clear(f"trakt:list:{where[5:]}")
        else:
            raise ValueError("¿Guardar dónde?")

    def title_extras(self, kind: str, imdb: str) -> dict:
        """La ficha como el iPhone: frase, clasificación, quién la hizo (TMDB) y «Más como esto» (lo que Trakt relaciona, ya
        con IMDb para abrirlo). Lo que no se pueda (sin clave, sin red) queda vacío; se recuerda (también sin internet)."""
        kind = kind if kind in ("movie", "series") else "movie"
        empty = {"tagline": None, "certification": None, "directors": [], "writers": [], "cast": [], "people": [], "more": []}
        if not isinstance(imdb, str) or not re.fullmatch(r"tt[0-9]{1,12}", imdb):
            return empty
        out = dict(empty)
        if self.tmdb.configured:
            def load_tmdb() -> dict:
                tmdb_id = self.tmdb.find_id(imdb, kind)
                return self.tmdb.extras(kind, tmdb_id, self.region) if tmdb_id else {}
            try:
                out.update(self.cache.get(f"extras:{kind}:{imdb}", SLOW_TTL, load_tmdb) or {})
            except Exception:  # noqa: BLE001 - lo de TMDB es un extra: la ficha se ve sin él
                log.info("Ficha: no pude leer los extras de %s", imdb)
        if self.trakt.configured:
            related = self._related({"imdb": imdb, "kind": kind})
            out["more"] = [video_item(e, "Más como esto") for e in related[:15]]
        return out

    def title_ratings(self, kind: str, imdb: str) -> dict:
        """Las calificaciones de la ficha, como el iPhone (RatingsRow): IMDb (de Cinemeta), TMDB y Trakt, en 0–10. Las que no
        se pueden saber (sin clave, sin red, sin votos) quedan en None; se recuerdan un día."""
        kind = kind if kind in ("movie", "series") else "movie"
        if not isinstance(imdb, str) or not re.fullmatch(r"tt[0-9]{1,12}", imdb):
            return {"imdb": None, "tmdb": None, "trakt": None}

        def imdb_rating() -> float | None:
            return self.imdb_ratings([(kind, imdb)]).get(imdb)

        def tmdb_rating() -> float | None:
            if not self.tmdb.configured:
                return None
            tmdb_id = self.tmdb.find_id(imdb, kind)
            return self.tmdb.details(kind, tmdb_id).get("rating") if tmdb_id else None

        def trakt_rating() -> float | None:
            return self.trakt.rating(kind, imdb) if self.trakt.configured else None

        def safe(name: str, load: Callable[[], float | None]) -> float | None:
            try:
                return self.cache.get(f"rating:{name}:{imdb}", SLOW_TTL, load)
            except Exception:  # noqa: BLE001 - una calificación que falla no tumba la ficha
                return None

        with ThreadPoolExecutor(max_workers=3) as pool:
            jobs = {name: pool.submit(safe, name, load) for name, load in
                    (("imdb", imdb_rating), ("tmdb", tmdb_rating), ("trakt", trakt_rating))}
            return {name: job.result() for name, job in jobs.items()}

    def watched_ids(self) -> list[str]:
        """Lo que ya viste en Trakt (sin Trakt, nada): «Ocultar lo que ya vi»."""
        if not self.trakt.linked:
            return []
        try:
            return self.cache.get("trakt:watched", MINE_TTL, self.trakt.watched_ids)
        except SERVICE_ERRORS as exc:
            log.info("Para ti: no pude leer lo que ya viste: %s", exc)
            return []

    def _studio_logos(self) -> dict[str, str]:
        """Los logos de los estudios (TMDB), sin hacer esperar al riel: si aún no están, se piden en segundo plano y mientras
        tanto la tarjeta dice el nombre. Se recuerdan un día."""
        found = self.cache.peek("tmdb:studio-logos")
        if found is None and not self._studio_logos_busy:
            self._studio_logos_busy = True

            def load() -> None:
                try:
                    with ThreadPoolExecutor(max_workers=4) as pool:
                        pairs = list(pool.map(lambda s: (str(s[0]), self._safe(lambda: self.tmdb.company_logo(s[0]))), tmdb_api.STUDIOS))
                    self.cache.get("tmdb:studio-logos", SLOW_TTL, lambda: {k: v for k, v in pairs if v})
                finally:
                    self._studio_logos_busy = False
                    self.publish({"type": "studio-logos"})  # Películas y series se pone al día con los logos

            threading.Thread(target=load, daemon=True, name="studio-logos").start()
        return found or {}

    def _recent_seeds(self) -> list[dict]:
        """Tus últimos cinco títulos distintos (Trakt), para «Porque viste X»."""
        try:
            return self.cache.get("trakt:recent", MINE_TTL, self.trakt.recent_watched)
        except SERVICE_ERRORS as exc:
            log.info("Para ti: no pude leer lo último que viste: %s", exc)
            return []

    ROTATION = 5  # la semilla del día rota entre los primeros cinco (becauseRotation del iPhone)

    def _related(self, seed: dict) -> list[dict]:
        """Lo que Trakt relaciona con esa semilla (15, en su orden; sin ella misma)."""
        try:
            found = self.cache.get(f"trakt:related:{seed['imdb']}", RECS_TTL, lambda: self.trakt.related(seed["kind"], seed["imdb"], 15))
        except SERVICE_ERRORS as exc:
            log.info("Para ti: no pude leer lo relacionado con %s: %s", seed.get("title"), exc)
            return []
        return [e for e in found if e.get("imdb") != seed.get("imdb")]

    def _seed_of_day(self, seeds: list[dict], today: date | None = None) -> dict | None:
        """El de hoy: uno distinto cada día entre los primeros cinco (día % 5, como el iPhone). Si ese no tiene
        relacionados, el siguiente."""
        if not seeds:
            return None
        span = min(self.ROTATION, len(seeds))
        start = (today or date.today()).toordinal() % span
        order = [seeds[(start + i) % span] for i in range(span)] + seeds[span:]
        return next((s for s in order if self._related(s)), order[0])

    def _country(self) -> str:
        return {"MX": "México", "US": "Estados Unidos", "ES": "España", "AR": "Argentina", "CO": "Colombia",
                "CL": "Chile", "PE": "Perú"}.get(self.region, self.region)

    # --- el contenido de cada lista ----------------------------------------------------------
    def list_items(self, list_id: str, kind: str | None = None) -> list[dict]:
        kind = kind if kind in ("movie", "series") else "series"
        hidden = self.catalog.state.dismissed()
        items = self._list(list_id, kind)
        out = [self._with_art(i) for i in items if i["key"] not in hidden]
        self._warm_logos(out[:LOGO_WARM])
        return out

    def _warm_logos(self, items: list[dict]) -> None:
        """Baja en segundo plano (uno a la vez) los logos recortados de los primeros títulos de una lista: cuando el héroe
        de la tele los pide ya están en disco (antes una serie nueva tardaba en enseñar su título estilizado)."""
        wanted = [i["meta_id"] for i in items if isinstance(i.get("meta_id"), str) and i["meta_id"].startswith("tt")]
        if wanted:
            self._logo_pool.submit(lambda: [self.trimmed_logo(imdb) for imdb in wanted])

    def _with_art(self, item: dict) -> dict:
        """El póster o fondo que elegiste para ese título («Cambiar el arte»), en lugar del de siempre."""
        name = self.catalog.names.name(item.get("kind"), item.get("meta_id")) if getattr(self.catalog, "names", None) else None
        if name and name != item.get("title"):  # el mismo nombre que en la ficha y en Buscar (tu idioma)
            item = {**item, "title": name}
        art = self.catalog.watch.art_for(item.get("meta_id")) if item.get("meta_id") else {}
        if not art:
            return item
        return {**item, **({"image": art["poster"]} if art.get("poster") else {}),
                **({"hero": art["background"]} if art.get("background") else {})}

    def _stremio(self, which: str, kind: str | None = None) -> list:
        """Lo que Orbital ya trajo de Stremio: «continue» (Seguir viendo), «mylist» (Mi lista) o
        «cinemeta» (lo popular de su catálogo público). Solo títulos con id de IMDb."""
        if which == "cinemeta":
            found = [i for i in self.catalog.items() if i.source == "cinemeta"]
        else:
            mine = sorted((i for i in self.catalog.items() if i.source == "stremio"),
                          key=lambda i: i.last_watched or 0, reverse=True)
            found = [i for i in mine if (i.category == "continue") == (which == "continue")
                     and (which == "continue" or i.extra.get("in_library"))]
        return [(i, e) for i in found if (e := library_entry(i)) and (kind is None or e["kind"] == kind)]

    def _list(self, list_id: str, kind: str) -> list[dict]:
        t = self.trakt
        if list_id in ("continue", "mylist", "cinemeta"):
            why = {"continue": "Seguir viendo", "mylist": "En Mi lista", "cinemeta": "Popular"}[list_id]
            return [video_item(e, why, overview=i.extra.get("description"))
                    for i, e in self._stremio(list_id, kind if list_id == "cinemeta" else None)]
        if list_id.startswith("addon:"):
            entry = next((a for a in self.addon_catalogs() if a["id"] == list_id), None)
            if not entry:
                raise KeyError(list_id)
            return self.cache.get(f"{list_id}:{kind}", POPULAR_TTL, lambda: self._addon_list(entry, kind))
        if list_id == "estrenos":
            return self.calendar()
        if list_id == "recs":
            return [video_item(e, "Recomendada") for e in self.cache.get(f"trakt:recs:{kind}", RECS_TTL, lambda: t.recommendations(kind))]
        if list_id == "mine":
            return [video_item(e, "Sigues viéndola") for e in self.cache.get("trakt:watching", MINE_TTL, t.watching)]
        if list_id == "watchlist":
            return [video_item(e, "En tu watchlist") for e in self.cache.get("trakt:watchlist", MINE_TTL, t.watchlist)]
        if list_id.startswith("list:"):
            lid = list_id.removeprefix("list:")
            name = next((r["name"] for r in self.cache.get("trakt:lists", MINE_TTL, t.lists) if r["id"] == lid), "tu lista")
            # La etiqueta es de un renglón: un nombre largo se cortaba («En «The 25 Best Sci-Fi…»»).
            why = f"En «{name}»" if len(name) <= 22 else "En una de tus listas"
            return [video_item(e, why) for e in self.cache.get(f"trakt:list:{lid}", MINE_TTL, lambda: t.list_items(lid))]
        if list_id == "trend":
            return [video_item(e, "En tendencia") for e in self.cache.get(f"trakt:trend:{kind}", RECS_TTL, lambda: t.trending(kind))]
        if list_id == "popular":
            return [video_item(e, "Popular") for e in self.cache.get(f"trakt:popular:{kind}", POPULAR_TTL, lambda: t.popular(kind))]
        if list_id in tmdb_api.PLATFORMS:
            return self.cache.get(f"tmdb:{list_id}:{kind}", POPULAR_TTL, lambda: self._platform(list_id, kind))
        if list_id == "chart:netflix":
            entries = self.cache.get(f"charts:netflix:{kind}", SLOW_TTL, stale=True, load=lambda: charts_api.netflix_entries(
                self.region, kind, tmdb=self.tmdb if self.tmdb.configured else None, cinemeta=self.catalog.cinemeta))
            return [self._chart_item(e, kind, "Netflix") for e in entries]
        if list_id.startswith("jw:"):
            brand = list_id.removeprefix("jw:")
            if brand not in charts_api.JUSTWATCH_PACKAGES:
                raise KeyError(list_id)
            entries = self.cache.get(f"charts:jw:{brand}:{kind}", POPULAR_TTL, stale=True, load=lambda: self.snapshots.annotate(
                f"jw:{brand}", kind, charts_api.fetch_justwatch_chart(brand, self.region, kind)))
            name = charts_api.JUSTWATCH_PACKAGES[brand][1]
            return [self._chart_item(e, kind, name) for e in entries]
        if list_id == "because" or list_id.startswith("because:"):
            seeds = self._recent_seeds()
            if not seeds:
                return []
            wanted = list_id.removeprefix("because:") if ":" in list_id else None
            seed = next((s for s in seeds if s["imdb"] == wanted), None) if wanted else self._seed_of_day(seeds)
            if seed is None:
                raise KeyError(list_id)  # solo de tus últimos 12
            # Como el iPhone: el porqué es la semilla (no uno por póster) y van en el orden de Trakt.
            why = f"Porque viste {seed['title']}" if len(seed["title"]) <= 18 else "Porque viste algo parecido"
            return [video_item(e, why) for e in self._related(seed)]
        if list_id == "fresh":
            return self.cache.get(f"tmdb:fresh:{kind}", POPULAR_TTL, lambda: self._fresh(kind))
        if list_id.startswith("award:"):
            award = next((a for a in load_awards() if a["id"] == list_id.removeprefix("award:")), None)
            if not award:
                raise KeyError(list_id)
            return [{**video_item({"imdb": w["imdb"], "kind": award["kind"], "title": w["title"], "year": w.get("year")},
                                  f"{award['title']} {w['award_year']}"), "award_year": w["award_year"]}
                    for w in award["winners"]]
        if list_id.startswith("studio:"):
            sid = list_id.removeprefix("studio:")
            name = next((n for i, n in tmdb_api.STUDIOS if str(i) == sid), None)
            if not name or not self.tmdb.configured:
                raise KeyError(list_id)
            return self.cache.get(f"tmdb:studio:{sid}", SLOW_TTL, lambda: self._studio(int(sid), name))
        if list_id.startswith("year:"):
            year = list_id.removeprefix("year:")
            if not year.isdigit() or not FIRST_YEAR <= int(year) <= datetime.now().year:
                raise KeyError(list_id)
            return self.cache.get(f"trakt:year:{year}:{kind}", SLOW_TTL, lambda: self._year(int(year), kind))
        if list_id == "mygames":
            return self.local_games()
        if list_id.startswith("rawg:"):
            return self._mark_owned(self.cache.get(list_id, SLOW_TTL, lambda: self._rawg(list_id.removeprefix("rawg:"))))
        raise KeyError(list_id)

    def _platform(self, brand: str, kind: str) -> list[dict]:
        platform = self.platforms().get(brand)
        if not platform:
            return []
        rows = self.tmdb.discover(kind, platform["id"], self.region)[:20]
        with ThreadPoolExecutor(max_workers=6) as pool:
            details = list(pool.map(lambda r: self._safe(lambda: self.tmdb.details(kind, r["id"])), rows))
        name = tmdb_api.PLATFORMS[brand][0]
        return [video_item(d, f"En {name}", title=d["title"], poster=d["poster"], wide=d["backdrop"],
                           overview=d["overview"], seasons=d.get("seasons"))
                for d in details if d and d.get("imdb") and d.get("title")]

    def _tmdb_items(self, rows: list[dict], kind: str, why: str, limit: int = 20) -> list[dict]:
        """Filas de TMDB (discover) → video_item con su IMDb (la ficha y el reproductor lo necesitan)."""
        with ThreadPoolExecutor(max_workers=6) as pool:
            details = list(pool.map(lambda r: self._safe(lambda: self.tmdb.details(kind, r["id"])), rows[:limit]))
        return [video_item(d, why, title=d["title"], poster=d["poster"], wide=d["backdrop"], overview=d["overview"],
                           seasons=d.get("seasons"))
                for d in details if d and d.get("imdb") and d.get("title")]

    def _fresh(self, kind: str) -> list[dict]:
        """«Nuevo en tus plataformas»: lo nuevo de Netflix, Disney+ y HBO Max, alternados (como el iPhone)."""
        found = self.platforms()
        today = date.today()
        batches = []
        for brand in FRESH_BRANDS:
            platform = found.get(brand)
            if not platform:
                continue
            rows = self._safe(lambda platform=platform: self.tmdb.fresh(
                kind, platform["id"], self.region, today.isoformat(), (today - timedelta(days=FRESH_SERIES_DAYS)).isoformat(),
                (today - timedelta(days=FRESH_MOVIE_DAYS)).isoformat())) or []
            name = tmdb_api.PLATFORMS[brand][0]
            batches.append([{**i, "brand": brand} for i in self._tmdb_items(rows, kind, f"Nuevo en {name}", limit=8)])
        return self._interleave(batches)

    def _studio(self, company_id: int, name: str) -> list[dict]:
        return self._tmdb_items(self.tmdb.studio(company_id), "movie", name)

    def _year(self, year: int, kind: str) -> list[dict]:
        """Lo más popular de un año en Trakt; en películas, primero las premiadas de ese año (como los pósters del iPhone)."""
        items: list[dict] = []
        if kind == "movie":
            for a in load_awards():
                for w in a["winners"]:
                    if a["kind"] == "movie" and w.get("year") == year and all(i["meta_id"] != w["imdb"] for i in items):
                        items.append(video_item({"imdb": w["imdb"], "kind": "movie", "title": w["title"], "year": year},
                                                f"{a['title']} {w['award_year']}"))
        popular = self.trakt.popular(kind, limit=60, years=year)
        return items + [video_item(e, f"Popular en {year}") for e in popular if all(i["meta_id"] != e["imdb"] for i in items)]

    def _chart_item(self, entry: dict, kind: str, platform_name: str) -> dict:
        """Un título de Netflix (Top 10) o JustWatch (tendencia) en forma de video_item: «N.º 3 en Netflix», con `rank`,
        `movement` (+2 subió dos, −1 bajó uno, 0 igual, None sin con qué comparar) y `new` (entró esta semana / hoy)."""
        e = {"imdb": entry["imdb"], "kind": kind, "title": entry["title"], "year": entry.get("year")}
        item = video_item(e, f"N.º {entry['rank']} en {platform_name}", title=entry["title"])
        item["rank"] = entry["rank"]
        item["movement"] = entry.get("movement")
        item["new"] = bool(entry.get("new"))
        if entry.get("weeks"):
            item["weeks"] = entry["weeks"]  # semanas en el Top 10 de Netflix (para la ficha)
        return item

    def _netflix_meta(self) -> str:
        """«México · semana del 28 de sep» si el Top 10 ya se trajo (el archivo es grande: no se pide solo para esto)."""
        for kind in ("series", "movie"):
            cached = self.cache.peek(f"charts:netflix:{kind}") or []
            week = next((e.get("week") for e in cached if e.get("week")), None)
            if week:
                try:
                    start = date.fromisoformat(week) - timedelta(days=6)  # la semana de Netflix termina en domingo
                except ValueError:
                    break
                months = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"]
                return f"{self._country()} · semana del {start.day} de {months[start.month - 1]}"
        return f"Esta semana en {self._country()}"

    @staticmethod
    def _ranked_list(brand: str) -> str | None:
        """La lista con puesto de una plataforma: el Top 10 de Netflix o la de JustWatch (None si no tiene)."""
        return "chart:netflix" if brand == "netflix" else f"jw:{brand}" if brand in JW_LIST_BRANDS else None

    def _covered(self, list_id: str) -> list[str]:
        """Qué tipos ya trae una lista con puesto, según lo que hay en caché (sin salir a internet)."""
        prefix = "charts:netflix" if list_id == "chart:netflix" else f"charts:{list_id}"
        return [kind for kind in ("movie", "series") if self.cache.peek(f"{prefix}:{kind}")]

    @staticmethod
    def _safe(call):
        try:
            return call()
        except SERVICE_ERRORS:
            return None

    def _rawg(self, which: str) -> list[dict]:
        games = self.rawg.games(which)
        with ThreadPoolExecutor(max_workers=6) as pool:
            appids = list(pool.map(lambda g: self._safe(lambda: self.rawg.steam_appid(g["rawg_id"])), games))
        why = {"new": "Novedad", "popular": "Popular", "best": "Mejor calificado"}[which]
        found = []
        for g, appid in zip(games, appids, strict=True):
            art = (lambda f, a=appid: STEAM_ART.format(appid=a, file=f)) if appid else None
            found.append({
                "key": f"rawg:{g['rawg_id']}", "kind": "game", "rawg_id": g["rawg_id"], "steam_appid": appid,
                "title": g["title"], "year": g["year"], "why": why, "system": "steam" if appid else "pc",
                "detail": f"Metacritic {g['metacritic']}" if g["metacritic"] else (str(g["year"]) if g["year"] else ""),
                "facts": [[k, str(v)] for k, v in (["Salió", g["year"]], ["Metacritic", g["metacritic"]]) if v],
                "image": art("library_600x900.jpg") if art else g["image"], "image_fallback": g["image"],
                "hero": g["image"] or (art("library_hero.jpg") if art else None),
                "logo": art("logo.png") if art else None, "wide": art("capsule_616x353.jpg") if art else None,
                "overview": "", "owned": False, "action": None,
            })
        return found

    def _mark_owned(self, games: list[dict]) -> list[dict]:
        """Lo que ya tienes (por id de Steam o por nombre) se juega desde aquí: palomita y A = Jugar."""
        library = [i for i in self.catalog.items() if i.category in GAME_CATEGORIES]
        by_appid = {i.steam_appid: i for i in library if i.steam_appid}
        by_title = {fold(i.title): i for i in library}
        marked = []
        for g in games:
            mine = by_appid.get(g.get("steam_appid")) or by_title.get(fold(g["title"]))
            if mine:
                g = {**g, "owned": True, "id": mine.id, "item": self.catalog.describe(mine), "action": "Jugar"}
            marked.append(g)
        return marked

    # --- próximos estrenos -----------------------------------------------------------------------
    def calendar(self, now: datetime | None = None) -> list[dict]:
        """Los episodios que salen (hoy y los próximos días) de las series que sigues en Trakt, con la hora de aquí. Varios
        de la misma serie el mismo día (las plataformas sueltan tres juntos) van en una sola sugerencia: «E4–E6»."""
        now = now or datetime.now().astimezone()
        start = (now - timedelta(days=1)).date().isoformat()  # Trakt va en hora universal: un día antes, para no perder lo de hoy
        rows = self.cache.get(f"trakt:calendar:{start}", RECS_TTL, lambda: self.trakt.calendar(start, CALENDAR_DAYS + 2))
        today = now.date()
        return self._airings(rows, today, today + timedelta(days=CALENDAR_DAYS), today)

    def calendar_month(self, year: int, month: int, now: datetime | None = None) -> dict:
        """El mes completo (como «Sale hoy › el mes» del iPhone): lo que sale cada día de las series que sigues, también
        los días que ya pasaron. Trakt da hasta 31 días por pedido: el mes va en dos mitades (con un día de más a cada lado
        por la hora universal)."""
        now = now or datetime.now().astimezone()
        first = date(year, month, 1)
        following = date(year + (month == 12), month % 12 + 1, 1)
        start = first - timedelta(days=1)
        span = (following - first).days + 2
        rows: list[dict] = []
        for offset, days in ((0, 16), (16, span - 16)):
            begin = (start + timedelta(days=offset)).isoformat()
            ttl = RECS_TTL if following > now.date() else SLOW_TTL  # un mes que ya pasó no cambia
            rows += self.cache.get(f"trakt:calendar:{begin}:{days}", ttl, lambda b=begin, d=days: self.trakt.calendar(b, d))
        return {"month": f"{year:04d}-{month:02d}", "today": now.date().isoformat(),
                "items": self._airings(rows, first, following, now.date())}

    def _airings(self, rows: list[dict], first: date, end: date, today: date) -> list[dict]:
        """Los estrenos entre dos fechas (con la hora de aquí); varios de la misma serie el mismo día, en uno («E4–E6»)."""
        groups: dict[tuple, dict] = {}
        seen: set[tuple] = set()
        for row in rows:
            if (row["imdb"], row["season"], row["episode"]) in seen:  # las dos mitades se tocan en un día
                continue
            seen.add((row["imdb"], row["season"], row["episode"]))
            when = datetime.fromtimestamp(row["aired"]).astimezone()
            day = when.date()
            if not first <= day < end:
                continue
            key = (day, row["imdb"])
            group = groups.get(key)
            if group:
                group["last"] = max(group["last"], row["episode"])
                group["first"] = min(group["first"], row["episode"])
                group["count"] += 1
                continue
            groups[key] = {**row, "when": when, "first": row["episode"], "last": row["episode"], "count": 1}
        return [calendar_item(g, today) for g in sorted(groups.values(), key=lambda g: (g["when"], g["title"]))]

    def airing_today(self) -> dict[str, str]:
        """{IMDb: «19:00»} de lo que sale hoy, para marcarlo en el Inicio («Sale hoy»). Sin Trakt o sin red: nada."""
        if not self.trakt.linked:
            return {}
        try:
            items = self.calendar()
        except SERVICE_ERRORS:
            return {}
        return {i["meta_id"]: i["time"] for i in items if i["today"]}

    # --- tus juegos ----------------------------------------------------------------------------
    def local_games(self, seed: int | None = None, lucky: int = 3) -> list[dict]:
        """Favoritos, los más jugados, los que nunca has abierto y uno al azar (cambia cada día)."""
        rng = random.Random(seed if seed is not None else date.today().toordinal())
        described = [self.catalog.describe(i) for i in self.catalog.items() if i.category in GAME_CATEGORIES]
        last = lambda d: d.get("last_played") or 0  # noqa: E731
        played = lambda d: float(d.get("playtime") or 0)  # noqa: E731
        favorites = sorted((d for d in described if d.get("favorite")), key=last, reverse=True)[:8]
        taken = {d["id"] for d in favorites}
        most = sorted((d for d in described if d["id"] not in taken and played(d) >= 3600), key=played, reverse=True)[:6]
        taken |= {d["id"] for d in most}
        fresh = [d for d in described if d["id"] not in taken and not played(d) and not last(d)]
        rng.shuffle(fresh)
        fresh = fresh[:8]
        taken |= {d["id"] for d in fresh}
        rest = [d for d in described if d["id"] not in taken]
        lucky_picks = rng.sample(rest, min(lucky, len(rest)))
        picks = ([game_item(d, "Tu favorito") for d in favorites] + [game_item(d, "Tu más jugado") for d in most]
                 + [game_item(d, "Sin jugar") for d in fresh] + [game_item(d, "Al azar") for d in lucky_picks])
        hidden = self.catalog.state.dismissed()
        return [p for p in picks if p["key"] not in hidden]

    # --- el mosaico ----------------------------------------------------------------------------
    def mosaic(self) -> list[dict]:
        """El mosaico de la caché (vencido o no, se renueva solo); solo la primera vez se espera a armarlo."""
        hidden = self.catalog.state.dismissed()
        return [self._with_art(i) for i in self.cache.get("mosaic", MINE_TTL, self._build_mosaic, stale=True) if i["key"] not in hidden]

    def warm(self) -> None:
        """Al arrancar Orbital, arma el mosaico y las listas con puesto en segundo plano: la primera vez que la TV o el
        iPhone abren Para ti ya está (antes esperaban el Top 10 de Netflix, unos 30 s). Y sus primeros pósters y logos,
        ya bajados y reducidos: la primera vez que se veía el mosaico, cada imagen se bajaba en ese momento."""
        def run() -> None:
            items = self._safe(self.mosaic) or []
            # Las imágenes, con calma: al arrancar Orbital ya escanea la biblioteca y el arte, y todo junto hacía que la
            # interfaz tardara segundos en contestar.
            time.sleep(PREFETCH_DELAY)
            self._safe(lambda: self.prefetch_art(items))

        threading.Thread(target=run, daemon=True, name="foryou-warm").start()

    def prefetch_art(self, items: list[dict], limit: int = 60) -> int:
        """Baja y reduce los pósters (al ancho del mosaico) y los logos de las primeras piezas. Devuelve cuántas."""
        from . import remote_art

        def one(item: dict) -> bool:
            ok = False
            url = item.get("image")
            if isinstance(url, str) and remote_art.allowed(url):
                ok = remote_art.sized(url, 360) is not None  # POSTER_PX del mosaico (foryou-mosaic.js)
            imdb = item.get("meta_id")
            if isinstance(imdb, str) and str(item.get("logo") or "").startswith("https://images.metahub.space/logo/"):
                self.trimmed_logo(imdb)
            return ok

        with ThreadPoolExecutor(max_workers=2) as pool:
            return sum(pool.map(one, items[:limit]))

    def _build_mosaic(self) -> list[dict]:
        """Lo tuyo, mezclado: tus recomendaciones, tu watchlist, tus listas, tus series y tus juegos.
        Sin Trakt conectado: lo que dejaste a medias y tu lista de Stremio, más lo que está en
        tendencia (o lo popular en tus plataformas, o en el catálogo de Stremio si no hay claves)."""
        sources: list[tuple[str, str | None]] = []
        if self.trakt.linked:
            sources = [("recs", "series"), ("recs", "movie"), ("watchlist", None), ("mine", None)]
            try:
                sources += [(f"list:{r['id']}", None) for r in self.cache.get("trakt:lists", MINE_TTL, self.trakt.lists)[:3]]
            except SERVICE_ERRORS:
                pass
        else:
            sources = [("continue", None), ("mylist", None)]
            sources += [(a["id"], kind) for a in self.addon_catalogs() if a["addon"].lower() == TRAKT_ADDON
                        and a["title"] in ("Watchlist", "Recommendations") for kind in a["kinds"]]
            if self.trakt.configured:
                sources += [("trend", "series"), ("trend", "movie")]
            elif self.platforms():
                sources += [(brand, kind) for brand in self.platforms() for kind in ("series", "movie")]
            else:
                sources += [("cinemeta", "series"), ("cinemeta", "movie")]
        # El Top 10 de Netflix y lo más visto por plataforma: no dependen de Trakt ni de ninguna clave.
        sources += [("chart:netflix", "movie"), ("chart:netflix", "series")]
        sources += [(f"jw:{brand}", kind) for brand in JW_LIST_BRANDS for kind in ("movie", "series")]

        def fetch(source):
            try:
                return self.list_items(*source)[:PER_SOURCE]
            except (KeyError, *SERVICE_ERRORS) as exc:
                log.warning("Para ti: %s no respondió: %s", source[0], exc)
                return []

        with ThreadPoolExecutor(max_workers=4) as pool:
            batches = list(pool.map(fetch, sources))
        videos = self._interleave(batches)
        # El mosaico es de imágenes: sin arte, no entra. Y lleva más «Al azar» que la lista (hay lugar).
        games = [g for g in self.local_games(lucky=24) if not g["placeholder"]]
        mixed, seen = [], set()
        # Tres videos por cada dos juegos, más o menos (lo que haya de cada uno).
        vi = gi = 0
        while len(mixed) < MOSAIC_SIZE and (vi < len(videos) or gi < len(games)):
            for _ in range(3):
                if vi < len(videos):
                    mixed.append(videos[vi])
                    vi += 1
            for _ in range(2):
                if gi < len(games):
                    mixed.append(games[gi])
                    gi += 1
        out = []
        for item in mixed:
            if item["key"] not in seen:
                seen.add(item["key"])
                out.append(item)
        return out[:MOSAIC_SIZE]

    @staticmethod
    def _interleave(batches: list[list[dict]]) -> list[dict]:
        """Una de cada fuente por turno: así el mosaico no es solo recomendaciones."""
        out, i = [], 0
        while any(i < len(b) for b in batches):
            out += [b[i] for b in batches if i < len(b)]
            i += 1
        return out

    def overview(self) -> dict:
        return {"status": self.status(), "lists": self.lists(), "mosaic": self.mosaic()}

    # --- la ficha de una sugerencia ------------------------------------------------------------
    def details(self, key: str, kind: str | None = None) -> dict:
        """Sinopsis en español (si se puede) y si su logo es oscuro (se pinta blanco)."""
        if key.startswith("video:"):
            imdb = key.removeprefix("video:")
            kind = kind if kind in ("movie", "series") else "movie"
            return self.cache.get(f"details:{key}", SLOW_TTL, lambda: self._video_details(imdb, kind))
        if key.startswith("rawg:"):
            rawg_id = int(key.removeprefix("rawg:")) if key.removeprefix("rawg:").isdigit() else 0
            return self.cache.get(f"details:{key}", SLOW_TTL, lambda: self._rawg_details(rawg_id))
        if key.startswith("game:"):
            item = self.catalog.get(key.removeprefix("game:"))
            appid = item.steam_appid if item else None
            text = self.cache.get(f"steam:{appid}", SLOW_TTL, lambda: rawg_api.steam_description(appid)) if appid else ""
            return {"overview": text}
        raise KeyError(key)

    def _video_details(self, imdb: str, kind: str) -> dict:
        overview, facts = "", None
        if self.tmdb.configured:
            found = self._safe(lambda: self.tmdb.find(imdb, kind))
            if found:
                overview = found["overview"]
                if kind == "movie" and found.get("runtime"):
                    facts = [["Duración", runtime_text(found["runtime"])], ["Año", str(found["year"] or "")]]
                elif kind == "series" and found.get("seasons"):
                    facts = [["Temporadas", str(found["seasons"])], ["Episodios", str(found.get("episodes") or "")]]
        if not overview:
            try:  # Cinemeta (en inglés): mejor eso que nada
                overview = str(self.catalog.cinemeta.meta(kind, imdb).get("description") or "").strip()
            except Exception:  # noqa: BLE001 - sin sinopsis no pasa nada
                overview = ""
        return {"overview": overview, "facts": [f for f in facts or [] if f[1]] or None,
                "logo_dark": self.logo_dark(METAHUB.format(kind="logo", imdb=imdb))}

    def _rawg_details(self, rawg_id: int) -> dict:
        appid = self._safe(lambda: self.rawg.steam_appid(rawg_id)) if rawg_id else None
        text = rawg_api.steam_description(appid) if appid else ""
        if not text and rawg_id:
            text = self._safe(lambda: self.rawg.description(rawg_id)) or ""
            text = text[:600].rsplit(" ", 1)[0] + "…" if len(text) > 600 else text
        return {"overview": text}

    def logo_dark(self, url: str) -> bool | None:
        """¿El logo es oscuro (negro sobre transparente)? Sobre el fondo oscuro no se vería: se pinta blanco."""
        if url in self._dark:
            return self._dark[url]
        verdict = None
        try:
            import io
            import urllib.request

            from PIL import Image

            from .net import read_body

            with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "Orbital"}), timeout=6) as res:
                raw = read_body(res, timeout=6, limit=4 * 1024 * 1024)
            image = Image.open(io.BytesIO(raw)).convert("RGBA")
            image.thumbnail((96, 96))
            visible = [px[:3] for px in image.getdata() if isinstance(px, tuple) and len(px) == 4 and px[3] > 128]
            if visible:
                lum = sum(.2126 * r + .7152 * g + .0722 * b for r, g, b in visible) / len(visible)
                verdict = lum < 64
        except Exception:  # noqa: BLE001 - sin Pillow, sin logo o sin internet: se deja como venga
            verdict = None
        if len(self._dark) > 2000:
            self._dark.clear()
        self._dark[url] = verdict
        return verdict

    def trimmed_logo(self, imdb: str) -> bytes | None:
        """El logo del título (metahub) ya sin su aire transparente, guardado en disco: la tele lo pide aquí, así el hueco
        entre la etiqueta y el logo es el mismo en todos. None si no hay (o no se pudo bajar: se reintenta en un rato)."""
        from .library import iptv_logos

        if not re.fullmatch(r"tt[0-9]{1,12}", imdb or ""):
            return None
        path = self.logo_dir / f"{imdb}.v2.png" if self.logo_dir else None  # v2: los oscuros ya vienen en blanco
        try:
            if path is not None and path.is_file():
                return path.read_bytes()
        except OSError:
            pass
        if imdb in self._logos:
            return self._logos[imdb]
        if time.monotonic() - self._logo_misses.get(imdb, -1e9) < LOGO_RETRY:
            return None
        try:
            png = whiten_if_dark(iptv_logos.trim(iptv_logos.download_logo(METAHUB.format(kind="logo", imdb=imdb))))
        except (iptv_logos.LogoError, *NET_ERRORS) as exc:
            log.debug("Sin logo de %s: %s", imdb, exc)
            if len(self._logo_misses) > 2000:
                self._logo_misses.clear()
            self._logo_misses[imdb] = time.monotonic()
            return None
        if path is not None:
            try:
                path.parent.mkdir(parents=True, exist_ok=True)
                tmp = path.with_suffix(".tmp")
                tmp.write_bytes(png)
                tmp.replace(path)
                return png
            except OSError as exc:
                log.info("No pude guardar un logo: %s", exc)
        if len(self._logos) > 300:
            self._logos.clear()
        self._logos[imdb] = png
        return png

    # --- una persona (como el iPhone) -------------------------------------------------------------
    def person(self, person_id: int) -> dict:
        """Foto, biografía y filmografía de alguien del reparto (TMDB). Se recuerda un día."""
        if not self.tmdb.configured:
            raise ValueError("Para ver a esta persona falta la clave de TMDB (Ajustes › Cuentas).")
        return self.cache.get(f"person:{int(person_id)}", SLOW_TTL, lambda: self.tmdb.person(int(person_id)))

    def tmdb_imdb(self, kind: str, tmdb_id: int) -> str | None:
        """El IMDb de un título de TMDB (abrir su ficha desde la filmografía)."""
        kind = kind if kind in ("movie", "series") else "movie"
        return self.cache.get(f"tmdb-imdb:{kind}:{int(tmdb_id)}", SLOW_TTL, lambda: self.tmdb.imdb_of(kind, int(tmdb_id)))

    def sagas(self, imdbs: list[str]) -> list[dict]:
        """Las sagas de tus películas (TMDB), solo las que tienen dos o más tuyas: [{id, name, imdbs}]. Cada película se
        pregunta una vez y se recuerda mucho tiempo (no cambia de saga)."""
        if not self.tmdb.configured:
            return []

        def one(imdb: str):
            try:
                return imdb, self.cache.get(f"saga:{imdb}", 30 * SLOW_TTL, lambda: self.tmdb.collection_of(imdb) or {})
            except SERVICE_ERRORS:
                return imdb, None
        groups: dict[int, dict] = {}
        with ThreadPoolExecutor(max_workers=6) as pool:
            for imdb, saga in pool.map(one, imdbs[:200]):
                if saga and saga.get("id"):
                    groups.setdefault(saga["id"], {"id": saga["id"], "name": saga["name"], "imdbs": []})["imdbs"].append(imdb)
        return sorted((g for g in groups.values() if len(g["imdbs"]) >= 2), key=lambda g: g["name"])

    # --- ¿Qué vemos? (como el iPhone) -------------------------------------------------------------
    def _decide_pool(self) -> list[dict]:
        """De dónde salen las propuestas: el mosaico, tus recomendaciones, tu watchlist y lo que es tendencia."""
        pool = [i for i in self.mosaic() if i.get("meta_id")]
        for list_id in ("recs", "watchlist", "trend"):
            try:
                pool += self.list_items(list_id)
            except (KeyError, *SERVICE_ERRORS):
                continue
        hidden = self.catalog.state.dismissed()
        return [i for i in pool if i.get("key") not in hidden]

    def _decide_details(self, items: list[dict]) -> dict[str, dict]:
        """Género, duración y calificación de lo que no los trae (Cinemeta, varios a la vez; se recuerda un día)."""
        def one(item: dict) -> tuple[str, dict]:
            imdb, kind = item["meta_id"], item["kind"]

            def load() -> dict:
                try:
                    meta = self.catalog.cinemeta.meta(kind, imdb, localized=False)
                except Exception:  # noqa: BLE001 - sin datos, se decide con lo que hay
                    return {}
                rating = meta.get("imdbRating")
                try:
                    score = float(rating) if rating not in (None, "") else None
                except (TypeError, ValueError):
                    score = None
                return {"genres": list(meta.get("genres") or meta.get("genre") or []),
                        "minutes": decide_api.runtime_minutes(meta.get("runtime")), "rating": score}
            return imdb, self.cache.get(f"decide:{imdb}", SLOW_TTL, load) or {}

        with ThreadPoolExecutor(max_workers=12) as pool:
            return dict(pool.map(one, items[:60]))

    def decide(self, time_choice: str | None = None, mood: str | None = None, kind: str | None = None,
               genres: list[str] | None = None, include_watched: bool = False, now: datetime | None = None) -> dict:
        """Tres propuestas (la primera es la elegida) con su porqué: duración y calificación de IMDb."""
        now = now or datetime.now().astimezone()
        time_choice = time_choice if time_choice in decide_api.TIMES else decide_api.context_time(now)
        mood = mood if mood in decide_api.MOODS else None
        kind = kind if kind in ("movie", "series") else None
        stamp = now.timestamp()
        self._skipped = {k: v for k, v in self._skipped.items() if stamp - v < decide_api.SKIP_HOURS * 3600}
        exclude = set(self._skipped)
        if not include_watched:
            exclude |= set(self.watched_ids())
        pool = self._decide_pool()
        details: dict[str, dict] = {}
        if mood or genres or time_choice != "long":
            missing = [i for i in pool if i.get("meta_id") not in exclude and (not i.get("genres") or not i.get("runtime"))]
            details = self._decide_details(missing)
        picks = decide_api.choose(pool, time=time_choice, mood=mood, kind=kind, genres=set(genres or ()), exclude=exclude,
                                  details=details)
        details.update(self._decide_details([p for p in picks if p["meta_id"] not in details]))
        out = []
        for p in picks:
            d = details.get(p["meta_id"], {})
            out.append({**p, "minutes": p.get("runtime") or d.get("minutes"), "imdb_rating": d.get("rating"),
                        "genres": p.get("genres") or d.get("genres") or []})
        return {"time": time_choice, "mood": mood, "kind": kind, "picks": out}

    def skip_today(self, imdb: str) -> None:
        """«Hoy no»: esa no vuelve a proponerse en 24 horas."""
        if re.fullmatch(r"tt[0-9]{1,12}", imdb or ""):
            self._skipped[imdb] = time.time()

    # --- Tu año (como el iPhone) ------------------------------------------------------------------
    def year_review(self, now: datetime | None = None) -> dict | None:
        """Lo que viste desde el 1 de enero (historial de Trakt; se recuerda una hora: son varias páginas). Sin Trakt: None."""
        if not self.trakt.linked:
            return None
        now = now or datetime.now().astimezone()
        start = now.replace(month=1, day=1, hour=0, minute=0, second=0, microsecond=0)
        plays = self.cache.get(f"trakt:year:{now.year}", RECS_TTL, lambda: self.trakt.plays(start.isoformat(), now.isoformat()))
        return decide_api.year_review(plays, now.year, now.tzinfo)

    # --- «No me interesa» ----------------------------------------------------------------------
    def dismiss(self, key: str) -> None:
        if not re.fullmatch(r"(video:tt[0-9]+|rawg:[0-9]+|game:.{1,300})", key or ""):
            raise ValueError("Sugerencia inválida")
        self.catalog.state.dismiss(key)

    # --- conectar Trakt ------------------------------------------------------------------------
    def start_link(self) -> dict:
        """Pide un código a Trakt y espera (en segundo plano) a que lo confirmes en trakt.tv/activate."""
        if not self.trakt.configured:
            raise ValueError("Falta la aplicación de Trakt: agrega su Client ID en Ajustes › Cuentas.")
        # Dos pedidos seguidos (Y dos veces) o cancelar mientras llega: solo cuenta el último. Antes se
        # quedaba el que terminara al final, y la pantalla podía mostrar un código que nadie esperaba.
        with self._link_lock:
            self._link_gen = gen = self._link_gen + 1
        code = self.trakt.device_code()
        with self._link_lock:
            if self._link_gen != gen:
                return code.public()
            self._link = code
        threading.Thread(target=self._wait_link, args=(code,), daemon=True, name="trakt-link").start()
        return code.public()

    def cancel_link(self) -> None:
        with self._link_lock:
            self._link_gen = self._link_gen + 1
            self._link = None

    def _wait_link(self, code: trakt_api.DeviceCode, sleep: Callable[[float], None] = time.sleep) -> str:
        interval = max(1.0, code.interval)
        while time.time() < code.expires_at:
            sleep(interval)
            with self._link_lock:
                if self._link is not code:  # cancelaste (B) o pediste otro código
                    return "cancelled"
            try:
                result = self.trakt.poll_device(code)
            except (trakt_api.TraktError, ValueError, TypeError, KeyError):
                continue  # la red parpadeó (o Trakt respondió algo raro): se sigue esperando
            if result == "slow":
                interval += 5
            elif result == "linked":
                with self._link_lock:
                    self._link = None
                self.cache.clear()
                name = self._safe(self.trakt.username) or ""
                self.publish({"type": "trakt-linked", "name": name})
                self.publish({"type": "foryou-changed"})
                return result
            elif result != "pending":
                break
        with self._link_lock:
            if self._link is code:
                self._link = None
        self.publish({"type": "trakt-link-failed", "message": "El código caducó. Pide otro para conectar Trakt."})
        return "expired"

    def unlink(self) -> None:
        self.trakt.unlink()
        self.cache.clear("trakt:")
        self.publish({"type": "foryou-changed"})
