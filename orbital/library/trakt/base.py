"""Lo que usan todas las piezas de Trakt: las medidas, los errores y las funciones que leen y arman lo que Trakt manda."""

from __future__ import annotations

import logging
import re
import time
from dataclasses import dataclass
from datetime import UTC
from typing import TYPE_CHECKING, Any

from ...net import RETRIES

log = logging.getLogger("orbital.library.trakt")  # el nombre de siempre: la bitácora no cambia

def _positive(value) -> int | None:
    """Un entero mayor que cero (lo demás de la API: None)."""
    return value if isinstance(value, int) and value > 0 else None


API = "https://api.trakt.tv"

HOST = "api.trakt.tv"  # para saber cuándo Trakt vuelve a contestar (net.on_recover)

TOKENS_KEY = "trakt_tokens"

# Lo que se escribe en «Redirect URIs» al crear la aplicación. Orbital entra con un código (no usa
# redirección), pero renovar la sesión lo pide y tiene que coincidir: developer.trakt.tv ya solo acepta
# https://, así que va https://localhost; las aplicaciones viejas tienen el valor de antes.
REDIRECTS = ("https://localhost/", "https://localhost", "urn:ietf:wg:oauth:2.0:oob")  # Trakt le agrega la «/»

KINDS = {"movie": "movies", "series": "shows"}

# Donde se esconde una serie («Esconder», la campana apagada) y, para «La dejé» (G1-A, 9 nov 2026), también las «dejadas»
# de trakt.tv (/users/hidden/dropped), como `Trakt.hiddenSections` y `droppedSections` del iPhone.
HIDDEN_SECTIONS = ("calendar", "progress_watched")

DROPPED_SECTIONS = (*HIDDEN_SECTIONS, "dropped")

PRIVACIES = ("private", "link", "friends", "public")  # «Quién la ve» (G4-A), los valores que entiende Trakt

PROGRESS_SHOWS = 40  # el tablero de Guardado pide el avance exacto de tus 40 series más recientes (Trakt dejó de mandarlo junto)

NOTE_LIMIT = 500  # lo más largo que Trakt guarda en una nota

SAME_VIEWING_WINDOW = 600  # s: una vista a ±10 min de la que se iba a mandar es esa misma (llegó y se perdió la respuesta)

REPEAT_WINDOW = 3600  # s: dos vistas del mismo título más cerca que esto son repetidas (la tele y el iPhone a la vez)


SCROBBLE_ACTIONS = ("start", "pause", "stop")


def scrobble_target(kind: str, meta_id: str, video_id: str | None) -> dict | None:
    """Lo que Trakt necesita para saber qué ves: la película (IMDb) o la serie con su temporada y episodio
    (el video_id de Stremio es `tt123:2:5`). None si no hay forma de identificarlo (no se manda nada)."""
    if not isinstance(meta_id, str) or not re.fullmatch(r"tt\d+", meta_id):
        return None
    if kind == "movie":
        return {"movie": {"ids": {"imdb": meta_id}}}
    if kind == "series":
        match = re.fullmatch(r"(tt\d+):(\d+):(\d+)", str(video_id or ""))
        if match and match.group(1) == meta_id:
            return {"show": {"ids": {"imdb": meta_id}},
                    "episode": {"season": int(match.group(2)), "number": int(match.group(3))}}
    return None


PLAYBACK_TTL = 60  # s: el avance de Trakt (/sync/playback) se vuelve a pedir a lo más cada minuto (como el iPhone)

FAVORITES_TTL = 60  # s: tus favoritos se guardan un minuto; pasado ese rato, se pregunta a /sync/last_activities si cambiaron

FAVORITES_FULL = "Llegaste a 100 favoritos en Trakt: quita uno para agregar otro."  # el tope de Trakt (420)


def playback_key(kind: str, meta_id: str, video_id: str | None) -> str | None:
    """La llave con la que se cruza el avance de Trakt: «tt123» (película) o «tt123:2:5» (episodio)."""
    target = scrobble_target(kind, meta_id, video_id)
    if target is None:
        return None
    if "episode" in target:
        return f"{meta_id}:{target['episode']['season']}:{target['episode']['number']}"
    return meta_id


def _dict(value) -> dict:
    return value if isinstance(value, dict) else {}


def playback_entry(row) -> tuple[str, dict] | None:
    """Una fila de GET /sync/playback → («tt123» o «tt123:2:5», {percent, paused_at, runtime}). None si no se entiende."""
    if not isinstance(row, dict) or not isinstance(row.get("progress"), (int, float)):
        return None
    when = _when(row.get("paused_at"))
    if when is None:
        return None
    if row.get("type") == "movie":
        movie = _dict(row.get("movie"))
        imdb, runtime = (movie.get("ids") or {}).get("imdb"), movie.get("runtime")
        key = imdb if isinstance(imdb, str) and re.fullmatch(r"tt\d+", imdb) else None
    elif row.get("type") == "episode":
        show = _dict(row.get("show"))
        ep = _dict(row.get("episode"))
        imdb, runtime = (show.get("ids") or {}).get("imdb"), ep.get("runtime")
        season, number = ep.get("season"), ep.get("number")
        ok = isinstance(imdb, str) and re.fullmatch(r"tt\d+", imdb) and isinstance(season, int) and isinstance(number, int)
        key = f"{imdb}:{season}:{number}" if ok else None
    else:
        key = None
    if key is None:
        return None
    return key, {"percent": float(row["progress"]), "paused_at": when,
                 "runtime": float(runtime) * 60 if isinstance(runtime, (int, float)) and runtime > 0 else None}


def latest_resume(stremio_seconds: float, stremio_when: float | None, duration: float | None,
                  trakt: dict | None) -> float:
    """Dónde seguir: lo más reciente entre Stremio (segundos exactos) y Trakt (porcentaje, a segundos con la duración de
    Stremio para ese video o, si no la hay, la que dice Trakt), como ResumePoint.latest del iPhone. El punto exacto, sin
    regresar unos segundos (decisión de Fernando). Pasado el 80 % Trakt no guarda punto (lo marca visto): queda el de
    Stremio. 0 = desde el inicio."""
    if not trakt or (stremio_when is not None and stremio_when >= trakt["paused_at"]):
        return stremio_seconds  # lo de Stremio es más nuevo (también si ahí ya lo terminaste: 0)
    length = duration if duration and duration > 0 else trakt.get("runtime")
    if trakt["percent"] <= 0 or not length:
        return stremio_seconds  # sin duración no se sabe a qué segundo va el porcentaje
    return trakt["percent"] / 100 * length


def history_body(target: dict, watched_at: float | str | None = None) -> dict:
    """Lo que POST /sync/history(/remove) pide para una película o un episodio (`target` de scrobble_target). `watched_at`:
    un momento, «released» (el día que salió) o «unknown» (no sabes cuándo), como «¿Cuándo la viste?» del iPhone."""
    when = {} if watched_at is None else {"watched_at": watched_at if watched_at in ("released", "unknown") else _iso(float(watched_at))}
    if "show" in target and "episode" not in target:  # la serie completa (todos sus episodios)
        return {"shows": [{**target["show"], **when}]}
    if "episode" in target:
        ep = target["episode"]
        return {"shows": [{**target["show"], "seasons": [{"number": ep["season"],
                                                         "episodes": [{"number": ep["number"], **when}]}]}]}
    return {"movies": [{**target["movie"], **when}]}


def _iso(when: float) -> str:
    from datetime import datetime

    return datetime.fromtimestamp(when, tz=UTC).strftime("%Y-%m-%dT%H:%M:%S.000Z")


def playback_row(row) -> dict | None:
    """Una fila de GET /sync/playback con lo que hace falta para ponerla en Seguir viendo: {id (para borrarla), kind,
    meta_id, video_id, title, year, percent, paused_at, runtime (s)}. None si no se entiende."""
    parsed = playback_entry(row)
    if parsed is None:
        return None
    key, info = parsed
    movie = row.get("type") == "movie"
    raw = _dict(row.get("movie") if movie else row.get("show"))
    title = raw.get("title")
    if not isinstance(title, str) or not title.strip():
        return None
    return {"id": row.get("id") if isinstance(row.get("id"), int) else None, "kind": "movie" if movie else "series",
            "meta_id": key.split(":")[0], "video_id": key, "title": title.strip(),
            "year": raw.get("year") if isinstance(raw.get("year"), int) else None, **info}


def show_progress(data) -> dict | None:
    """GET /shows/{id}/progress/watched → {next ((temporada, episodio) o None), last_watched (s o None), watched (set de
    (temporada, episodio))}. None si no se entiende."""
    if not isinstance(data, dict):
        return None
    watched: set[tuple[int, int]] = set()
    for season in data.get("seasons") or []:
        number = _dict(season).get("number")
        for ep in _dict(season).get("episodes") or []:
            ep = _dict(ep)
            if isinstance(number, int) and isinstance(ep.get("number"), int) and ep.get("completed"):
                watched.add((number, ep["number"]))
    nxt = _dict(data.get("next_episode"))
    ok = isinstance(nxt.get("season"), int) and isinstance(nxt.get("number"), int)
    return {"next": (nxt["season"], nxt["number"]) if ok else None, "last_watched": _when(data.get("last_watched_at")),
            "watched": watched}


def activity_stamps(data) -> dict[str, str]:
    """GET /sync/last_activities → la marca de cada cosa que la consola lee: {«paused», «watched», «watchlist»}. Si una
    cambia (desde cualquier app: el iPhone, la TV…), hay que volver a pedir eso; si no, nada."""
    data = _dict(data)

    def stamp(*paths: tuple[str, str]) -> str:
        return "|".join(str(_dict(data.get(a)).get(b) or "") for a, b in paths)

    return {"paused": stamp(("movies", "paused_at"), ("episodes", "paused_at")),
            "watched": stamp(("movies", "watched_at"), ("episodes", "watched_at")),
            "watchlist": stamp(("watchlist", "updated_at"), ("movies", "watchlisted_at"), ("shows", "watchlisted_at")),
            # SS1-A: «Esconder» en el iPhone (o «Dejar de seguir» aquí) cambia esta marca.
            "hidden": stamp(("shows", "hidden_at"), ("shows", "dropped_at"))}


class TraktError(Exception):
    def __init__(self, message: str = "", status: int | None = None) -> None:
        super().__init__(message)
        self.status = status  # el código de Trakt cuando respondió con un error (para saber si vale la pena reintentar)


class TraktAuthError(TraktError):
    """Trakt ya no acepta la sesión: hay que volver a conectar la cuenta."""


class TraktFavoritesFull(TraktError):
    """Ya tienes 100 favoritos en Trakt (respondió 420): hay que quitar uno para agregar otro."""


@dataclass
class DeviceCode:
    device_code: str
    user_code: str
    verification_url: str
    interval: float
    expires_at: float

    def public(self) -> dict:
        return {"code": self.user_code, "url": self.verification_url.removeprefix("https://"),
                "expires_in": max(0, int(self.expires_at - time.time()))}


def entry(raw: dict | None, kind: str) -> dict | None:
    """Una película o serie de Trakt en la forma de Orbital; None si no trae IMDb (no se podría ver)."""
    if not isinstance(raw, dict):
        return None
    ids = raw.get("ids") if isinstance(raw.get("ids"), dict) else {}
    imdb = ids.get("imdb")
    title = raw.get("title")
    if not isinstance(imdb, str) or not imdb.startswith("tt") or not isinstance(title, str) or not title.strip():
        return None
    year = raw.get("year") if isinstance(raw.get("year"), int) else None
    runtime = _positive(raw.get("runtime"))
    episodes = _positive(raw.get("aired_episodes"))
    genres = [str(g).replace("-", " ").title() for g in raw.get("genres") or [] if isinstance(g, str)][:4]  # «Science Fiction»
    rating = raw.get("rating")
    return {"kind": kind, "imdb": imdb, "title": title.strip(), "year": year, "runtime": runtime, "genres": genres,
            "episodes": episodes, "overview": str(raw.get("overview") or "").strip(),
            "trakt_id": ids.get("trakt") if isinstance(ids.get("trakt"), int) else None,
            # La calificación de Trakt (0–10): para ordenar una lista «Mejor calificadas en Trakt», como en el iPhone.
            "rating": round(float(rating), 1) if isinstance(rating, (int, float)) and rating > 0 else None}


def _when(value) -> float | None:
    """«2026-10-16T01:00:00.000Z» → segundos desde 1970 (None si no se entiende)."""
    from datetime import datetime

    if not isinstance(value, str) or not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None


def history_play(row) -> dict | None:
    """Una fila del historial de Trakt → lo que cuenta «Tu año». None si no trae fecha o IMDb."""
    if not isinstance(row, dict):
        return None
    at = _when(row.get("watched_at"))
    movie = row.get("type") == "movie"
    item = row.get("movie") if movie else row.get("show")
    ids = item.get("ids") if isinstance(item, dict) and isinstance(item.get("ids"), dict) else {}
    imdb = ids.get("imdb")
    if at is None or not isinstance(imdb, str) or not imdb.startswith("tt") or not isinstance(item.get("title"), str):
        return None
    ep = {} if movie or not isinstance(row.get("episode"), dict) else row["episode"]
    minutes = _positive(item.get("runtime")) if movie else (_positive(ep.get("runtime")) or _positive(item.get("runtime")))
    assert isinstance(item, dict)
    return {"at": at, "kind": "movie" if movie else "series", "imdb": imdb, "title": item["title"].strip(), "minutes": minutes or 0,
            "genres": [g for g in item.get("genres") or [] if isinstance(g, str)],
            "season": ep.get("season") if isinstance(ep.get("season"), int) else None,
            "episode": ep.get("number") if isinstance(ep.get("number"), int) else None,
            "episode_title": str(ep.get("title") or "").strip() or None}


def _typed(rows) -> list[dict]:
    """Filas mezcladas («type»: movie/show) → solo películas y series con IMDb, sin repetir."""
    found, seen = [], set()
    for row in rows if isinstance(rows, list) else []:
        if not isinstance(row, dict):
            continue
        kind_name = row.get("type")
        kind = {"movie": "movie", "show": "series"}.get(kind_name) if isinstance(kind_name, str) else None
        item = entry(row.get(kind_name), kind) if kind and isinstance(kind_name, str) else None
        if item and item["imdb"] not in seen:
            seen.add(item["imdb"])
            found.append(item)
    return found


def repeats(entries: list[dict], window: float = REPEAT_WINDOW) -> set[int]:
    """Las vistas repetidas de tu historial: el mismo título o capítulo a menos de `window` de otra más vieja (esa se queda)."""
    groups: dict[str, list[dict]] = {}
    for e in entries:
        groups.setdefault(f"{e['imdb']}:{e.get('season')}:{e.get('episode')}", []).append(e)
    out: set[int] = set()
    for group in groups.values():
        ordered = sorted(group, key=lambda e: e["at"])
        for a, b in zip(ordered, ordered[1:], strict=False):
            if b["at"] - a["at"] < window:
                out.add(b["id"])
    return out


def show_completed(row: object) -> bool:
    """¿Viste todos los capítulos que han salido de una serie (sin los especiales)? Sin el dato, cuenta como vista."""
    if not isinstance(row, dict):
        return True
    show = row.get("show")
    aired = show.get("aired_episodes") if isinstance(show, dict) else None
    if not isinstance(aired, int) or aired <= 0:
        return True
    seasons = row.get("seasons")
    seasons = seasons if isinstance(seasons, list) else []
    seen = sum(len(s.get("episodes") or []) for s in seasons if isinstance(s, dict) and (s.get("number") or 0) > 0)
    return seen >= aired


class _State:
    """El estado que Trakt.__init__ arma y los métodos que las piezas se piden entre sí: aquí solo se declaran,
    con su tipo, para que cada pieza los vea (nada de esto existe en ejecución)."""

    _favorites: tuple[float, str | None, list[dict]] | None
    _lock: Any
    _playback: tuple[float, dict[str, dict]] | None
    client_id: Any
    client_secret: Any
    credentials: Any
    timeout: Any

    if TYPE_CHECKING:  # viven en una pieza de más adelante o en la fachada: aquí solo para los tipos
        def _call(self, method: str, path: str, *, body: dict | None=None, auth: bool=True, params: dict | None=None, retries: int=RETRIES, idempotent: bool=False) -> Any: ...
        def list_items(self, list_id: str) -> list[dict]: ...
