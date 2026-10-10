"""Cliente de la API de Stremio (api.strem.io) para leer tu biblioteca y "Seguir viendo".

La API no es oficial ni está documentada: el formato sale del código de Stremio
(stremio-core y stremio-api-client). Si Stremio la cambia, Orbital sigue funcionando sin
la fila "Seguir viendo" (solo se registra el error).

  POST https://api.strem.io/api/<método>   body: {"authKey": ..., ...}   -> {"result": ...} | {"error": {...}}
"""

from __future__ import annotations

import json
import logging
import urllib.error
import urllib.request
from dataclasses import dataclass
from datetime import datetime, timezone

log = logging.getLogger(__name__)

API_URL = "https://api.strem.io"
METAHUB_BACKGROUND = "https://images.metahub.space/background/medium/{id}/img"


class StremioError(Exception):
    pass


class StremioAPI:
    def __init__(self, base: str = API_URL, timeout: float = 8) -> None:
        self.base = base.rstrip("/")
        self.timeout = timeout

    def request(self, method: str, params: dict) -> object:
        req = urllib.request.Request(
            f"{self.base}/api/{method}",
            data=json.dumps(params).encode(),
            headers={"Content-Type": "application/json", "User-Agent": "Orbital"},
            method="POST",
        )
        try:
            with urllib.request.urlopen(req, timeout=self.timeout) as res:
                body = json.load(res)
        except urllib.error.HTTPError as exc:
            raise StremioError(f"Stremio respondió HTTP {exc.code}") from exc
        except (urllib.error.URLError, TimeoutError, ValueError) as exc:
            raise StremioError(f"No pude conectar con Stremio: {exc}") from exc
        if isinstance(body, dict) and body.get("error"):
            error = body["error"]
            message = error.get("message") if isinstance(error, dict) else str(error)
            raise StremioError(message or "Error de Stremio")
        if not isinstance(body, dict) or "result" not in body:
            raise StremioError("Respuesta de Stremio sin resultado")
        return body["result"]

    def login(self, email: str, password: str) -> str:
        result = self.request("login", {"type": "Login", "email": email, "password": password, "facebook": False})
        key = result.get("authKey") if isinstance(result, dict) else None
        if not key:
            raise StremioError("Stremio no devolvió la clave de sesión")
        return key

    def library(self, auth_key: str) -> list[dict]:
        result = self.request("datastoreGet", {"authKey": auth_key, "collection": "libraryItem", "ids": [], "all": True})
        return [item for item in result if isinstance(item, dict)] if isinstance(result, list) else []

    def library_item(self, auth_key: str, item_id: str) -> dict | None:
        result = self.request("datastoreGet", {"authKey": auth_key, "collection": "libraryItem", "ids": [item_id], "all": False})
        found = [i for i in result if isinstance(i, dict) and i.get("_id") == item_id] if isinstance(result, list) else []
        return found[0] if found else None

    def save_library_item(self, auth_key: str, item: dict) -> None:
        self.request("datastorePut", {"authKey": auth_key, "collection": "libraryItem", "changes": [item]})


WATCHED_AT = 0.9  # mismo umbral que Stremio para dar algo por visto


def _iso(when: float) -> str:
    return datetime.fromtimestamp(when, timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.") + f"{int(when * 1000) % 1000:03d}Z"


def resume_seconds(raw: dict | None, video_id: str) -> float:
    """Dónde ibas en ese episodio o película según Stremio (0 = desde el principio)."""
    state = (raw or {}).get("state") or {}
    if state.get("video_id") != video_id:
        return 0.0
    offset, duration = int(state.get("timeOffset") or 0), int(state.get("duration") or 0)
    if offset <= 0 or (duration and offset >= duration * WATCHED_AT):
        return 0.0
    return offset / 1000


def with_progress(raw: dict | None, *, meta_id: str, kind: str, name: str, poster: str | None, video_id: str,
                  position: float, duration: float, watched: float, next_video: str | None, now: float) -> dict:
    """El libraryItem de Stremio con lo que viste en Orbital (para "Seguir viendo" en todos lados).

    Se parte del que ya existe y solo se toca `state`; si no existía, se crea como `temp` (así
    lo hace Stremio con lo que ves sin añadirlo a tu biblioteca). Tiempos en milisegundos.
    """
    item = dict(raw or {
        "_id": meta_id, "name": name, "type": kind, "poster": poster, "posterShape": "poster",
        "removed": True, "temp": True, "_ctime": _iso(now),
        "behaviorHints": {"defaultVideoId": None, "featuredVideoId": None, "hasScheduledVideos": False},
    })
    state = dict(item.get("state") or {})
    if state.get("video_id") != video_id:
        state["timeWatched"] = 0
    pos_ms, dur_ms, watched_ms = int(position * 1000), int(duration * 1000), int(watched * 1000)
    state.update({
        "lastWatched": _iso(now), "video_id": video_id, "duration": dur_ms, "timeOffset": pos_ms,
        "timeWatched": int(state.get("timeWatched") or 0) + watched_ms,
        "overallTimeWatched": int(state.get("overallTimeWatched") or 0) + watched_ms,
    })
    state.setdefault("timesWatched", 0)
    state.setdefault("flaggedWatched", 0)
    state.setdefault("noNotif", False)
    if dur_ms and pos_ms >= dur_ms * WATCHED_AT:
        state["timesWatched"] = int(state["timesWatched"]) + 1
        state["flaggedWatched"] = 1
        if next_video:  # sigue en "Seguir viendo", ya en el siguiente episodio
            state.update({"video_id": next_video, "timeOffset": 1, "timeWatched": 0, "duration": 0})
        else:
            state["timeOffset"] = 0  # terminada: sale de "Seguir viendo"
    item["state"] = state
    item["_mtime"] = _iso(now)
    return item


@dataclass
class Watchable:
    id: str
    type: str
    name: str
    poster: str | None
    video_id: str | None
    time_offset: int
    duration: int
    last_watched: float | None  # epoch
    in_continue: bool

    @property
    def progress(self) -> float | None:
        if self.duration <= 0 or self.time_offset <= 0:
            return None
        return min(1.0, self.time_offset / self.duration)

    @property
    def episode(self) -> tuple[int | None, int | None]:
        """("tt0944947:1:5") -> (1, 5); ("kitsu:123:7") -> (None, 7)."""
        if not self.video_id or self.type == "movie":
            return None, None
        # El video_id empieza por el id del título (que puede tener ":" propios, p. ej. kitsu:1).
        rest = self.video_id.removeprefix(self.id + ":") if self.video_id.startswith(self.id + ":") \
            else ":".join(self.video_id.split(":")[1:])
        numbers = [p for p in rest.split(":") if p.isdigit()]
        if len(numbers) >= 2:
            return int(numbers[-2]), int(numbers[-1])
        if len(numbers) == 1:
            return None, int(numbers[0])
        return None, None

    @property
    def deep_link(self) -> str:
        """Con el episodio (o la película), directo a reproducir (autoPlay); si no, la ficha."""
        link = f"stremio:///detail/{self.type}/{self.id}"
        video = self.video_id or (self.id if self.type == "movie" else None)
        if video:
            link += f"/{video}?autoPlay=true"
        return link

    @property
    def background(self) -> str | None:
        return METAHUB_BACKGROUND.format(id=self.id) if self.id.startswith("tt") else None


def _epoch(value) -> float | None:
    if not value:
        return None
    try:
        return datetime.fromisoformat(str(value).replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None


def parse_item(raw: dict) -> Watchable | None:
    item_id, name = raw.get("_id"), raw.get("name")
    if not item_id or not name:
        return None
    state = raw.get("state") or {}
    kind = raw.get("type") or "other"
    removed, temp = bool(raw.get("removed")), bool(raw.get("temp"))
    offset = int(state.get("timeOffset") or 0)
    if removed and not temp:
        return None
    return Watchable(
        id=item_id,
        type=kind,
        name=name,
        poster=raw.get("poster") or None,
        video_id=state.get("video_id") or None,
        time_offset=offset,
        duration=int(state.get("duration") or 0),
        last_watched=_epoch(state.get("lastWatched")),
        # Misma regla que stremio-core (LibraryItem::is_in_continue_watching).
        in_continue=kind != "other" and offset > 0,
    )


def parse_library(raw_items: list[dict]) -> list[Watchable]:
    items = [w for w in (parse_item(r) for r in raw_items) if w]
    return sorted(items, key=lambda w: w.last_watched or 0, reverse=True)
