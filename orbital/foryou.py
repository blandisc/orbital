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
Juegos). Cada sugerencia sale con una etiqueta corta («Recomendada», «Sin estrenar»…) y un dato.
Un servicio que falla no tumba los demás: su lista queda vacía y se reintenta más tarde.
"""

from __future__ import annotations

import logging
import random
import re
import threading
import time
import urllib.parse
import urllib.request
from collections.abc import Callable
from concurrent.futures import ThreadPoolExecutor
from datetime import date, datetime, timedelta
from typing import Any

from .library import rawg as rawg_api
from .library import stremio_api
from .library import tmdb as tmdb_api
from .library import trakt as trakt_api
from .net import NET_ERRORS, read_json

log = logging.getLogger(__name__)

METAHUB = "https://images.metahub.space/{kind}/medium/{imdb}/img"
STEAM_ART = "https://cdn.cloudflare.steamstatic.com/steam/apps/{appid}/{file}"
GAME_CATEGORIES = ("steam", "emulators")
SERVICE_ERRORS = (trakt_api.TraktError, tmdb_api.TmdbError, rawg_api.RawgError, stremio_api.StremioError) + NET_ERRORS

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

    def __init__(self, clock: Callable[[], float] = time.time) -> None:
        self.clock = clock
        self._data: dict[str, tuple[float, Any]] = {}
        self._locks: dict[str, threading.Lock] = {}
        self._lock = threading.Lock()

    def get(self, key: str, ttl: float, load: Callable[[], Any]) -> Any:
        with self._lock:
            hit = self._data.get(key)
            lock = self._locks.setdefault(key, threading.Lock())
        if hit and self.clock() - hit[0] < ttl:
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
            return value

    def clear(self, prefix: str = "") -> None:
        with self._lock:
            for key in [k for k in self._data if k.startswith(prefix)]:
                del self._data[key]


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
    if kind == "movie" and minutes:
        e["runtime"] = int(minutes.group())
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
    time_text = "Desde la madrugada" if when.hour < DAWN_HOUR else when.strftime("%H:%M")
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


class ForYou:
    def __init__(self, config, catalog) -> None:
        self.settings = config.para_ti
        self.catalog = catalog
        self.region = self.settings.region
        self.cache = Cache()
        self._build()
        self._link: trakt_api.DeviceCode | None = None
        self._link_lock = threading.Lock()
        self._link_gen = 0  # cada pedido o cancelación de código lo sube: solo cuenta el último
        self._dark: dict[str, bool | None] = {}

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
        return {"trakt": {"configured": self.trakt.configured, "linked": self.trakt.linked},
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
            video.append({"id": "continue", "title": "Seguir viendo", "icon": "watching", "source": "Stremio", "meta": "Donde te quedaste"})
        if self._stremio("mylist"):
            video.append({"id": "mylist", "title": "Mi lista", "icon": "bookmark", "source": "Stremio", "meta": "Tu biblioteca"})
        if self.trakt.linked:
            video += [
                {"id": "recs", "title": "Recomendadas", "icon": "spark", "source": "Trakt", "meta": "Por lo que has visto", "split": True},
                {"id": "mine", "title": "Tus series", "icon": "watching", "source": "Trakt", "meta": "Las que estás viendo"},
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
            video.append({"id": entry["id"], "title": entry["title"], "icon": "list", "source": "Stremio",
                          "meta": f"De {entry['addon']}", "split": len(entry["kinds"]) > 1})
        found = self.platforms()
        for brand, (name, _) in tmdb_api.PLATFORMS.items():
            if brand in found:
                video.append({"id": brand, "title": name, "brand": brand, "logo": found[brand]["logo"], "icon": "trailer", "source": "TMDB",
                              "meta": f"Lo más popular en {self._country()}", "split": True})
        games: list[dict] = [{"id": "mygames", "title": "Tus juegos", "icon": "gamepad", "source": "",
                              "meta": "Favoritos, los más jugados y los que no has abierto"}]
        if self.rawg.configured:
            games += [
                {"id": "rawg:new", "title": "Novedades", "icon": "fresh", "source": "RAWG", "meta": "Lo que acaba de salir"},
                {"id": "rawg:popular", "title": "Lo más popular", "icon": "flame", "source": "RAWG", "meta": "Lo que más se juega este año"},
                {"id": "rawg:best", "title": "Mejor calificados", "icon": "trophy", "source": "RAWG", "meta": "Por Metacritic"},
            ]
        return [{**row, "group": "video"} for row in video] + [{**row, "group": "games"} for row in games]

    def _country(self) -> str:
        return {"MX": "México", "US": "Estados Unidos", "ES": "España", "AR": "Argentina", "CO": "Colombia",
                "CL": "Chile", "PE": "Perú"}.get(self.region, self.region)

    # --- el contenido de cada lista ----------------------------------------------------------
    def list_items(self, list_id: str, kind: str | None = None) -> list[dict]:
        kind = kind if kind in ("movie", "series") else "series"
        hidden = self.catalog.state.dismissed()
        items = self._list(list_id, kind)
        return [i for i in items if i["key"] not in hidden]

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
            why = {"continue": "Seguir viendo", "mylist": "En tu lista", "cinemeta": "Popular"}[list_id]
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
            return [video_item(e, "En tu lista") for e in self.cache.get("trakt:watchlist", MINE_TTL, t.watchlist)]
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
        last = today + timedelta(days=CALENDAR_DAYS)
        groups: dict[tuple, dict] = {}
        for row in rows:
            when = datetime.fromtimestamp(row["aired"]).astimezone()
            day = when.date()
            if not today <= day < last:
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
                 + [game_item(d, "Sin estrenar") for d in fresh] + [game_item(d, "Al azar") for d in lucky_picks])
        hidden = self.catalog.state.dismissed()
        return [p for p in picks if p["key"] not in hidden]

    # --- el mosaico ----------------------------------------------------------------------------
    def mosaic(self) -> list[dict]:
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
