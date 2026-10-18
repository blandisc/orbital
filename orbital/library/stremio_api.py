"""Cliente de la API de Stremio (api.strem.io) para leer tu biblioteca y "Seguir viendo".

La API no es oficial ni está documentada: el formato sale del código de Stremio
(stremio-core y stremio-api-client). Si Stremio la cambia, Orbital sigue funcionando sin
la fila "Seguir viendo" (solo se registra el error).

  POST https://api.strem.io/api/<método>   body: {"authKey": ..., ...}   -> {"result": ...} | {"error": {...}}
"""

from __future__ import annotations

import base64
import binascii
import json
import logging
import urllib.error
import urllib.request
import zlib
from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Any

from ..net import NET_ERRORS, read_json

log = logging.getLogger(__name__)

API_URL = "https://api.strem.io"
METAHUB_BACKGROUND = "https://images.metahub.space/background/medium/{id}/img"
METAHUB_POSTER = "https://images.metahub.space/poster/medium/{id}/img"


# Sin cuenta: qué hacer, en una frase (se muestra tal cual; antes «Stremio no respondió bien (…). Inténtalo de nuevo»).
NOT_LINKED = "Para eso, conecta tu cuenta de Stremio en Ajustes › Cuentas."

class StremioError(Exception):
    pass


class StremioUnreachable(StremioError):
    """No se llegó a Stremio (sin internet, caído): no es que tus datos estén mal."""


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
                body = read_json(res, timeout=self.timeout)
        except urllib.error.HTTPError as exc:
            raise StremioUnreachable(f"Stremio respondió HTTP {exc.code}") from exc
        except NET_ERRORS as exc:
            raise StremioUnreachable(f"No pude conectar con Stremio: {exc}") from exc
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
    return datetime.fromtimestamp(when, UTC).strftime("%Y-%m-%dT%H:%M:%S.") + f"{int(when * 1000) % 1000:03d}Z"


def as_int(value) -> int:
    """Un número de Stremio; 0 si viene raro ("abc", 1e999, una lista)."""
    try:
        return int(value or 0)
    except (TypeError, ValueError, OverflowError):
        return 0


def state_of(raw) -> dict:
    """El `state` de un elemento de la biblioteca de Stremio, siempre un diccionario."""
    state = raw.get("state") if isinstance(raw, dict) else None
    return state if isinstance(state, dict) else {}


def resume_seconds(raw: dict | None, video_id: str) -> float:
    """Dónde ibas en ese episodio o película según Stremio (0 = desde el principio)."""
    state = state_of(raw)
    if state.get("video_id") != video_id:
        return 0.0
    offset, duration = as_int(state.get("timeOffset")), as_int(state.get("duration"))
    if offset <= 0 or (duration and offset >= duration * WATCHED_AT):
        return 0.0
    return offset / 1000


def with_progress(raw: dict | None, *, meta_id: str, kind: str, name: str, poster: str | None, video_id: str,
                  position: float, duration: float, watched: float, next_video: str | None, now: float,
                  video_ids: list[str] | None = None) -> dict:
    """El libraryItem de Stremio con lo que viste en Orbital (para "Seguir viendo" en todos lados).

    Se parte del que ya existe y solo se toca `state`; si no existía, se crea como `temp` (así
    lo hace Stremio con lo que ves sin añadirlo a tu biblioteca). Tiempos en milisegundos.
    """
    item: dict[str, Any] = dict(raw or {
        "_id": meta_id, "name": name, "type": kind, "poster": poster, "posterShape": "poster",
        "removed": True, "temp": True, "_ctime": _iso(now),
        "behaviorHints": {"defaultVideoId": None, "featuredVideoId": None, "hasScheduledVideos": False},
    })
    state: dict[str, Any] = dict(state_of(item))
    if state.get("video_id") != video_id:
        state["timeWatched"] = 0
    pos_ms, dur_ms, watched_ms = int(position * 1000), int(duration * 1000), int(watched * 1000)
    state.update({
        "lastWatched": _iso(now), "video_id": video_id, "duration": dur_ms, "timeOffset": pos_ms,
        "timeWatched": as_int(state.get("timeWatched")) + watched_ms,
        "overallTimeWatched": as_int(state.get("overallTimeWatched")) + watched_ms,
    })
    state.setdefault("timesWatched", 0)
    state.setdefault("flaggedWatched", 0)
    state.setdefault("noNotif", False)
    if dur_ms and pos_ms >= dur_ms * WATCHED_AT:
        state["timesWatched"] = as_int(state["timesWatched"]) + 1
        state["flaggedWatched"] = 1
        if video_ids and video_id in video_ids:  # ✓ en ese episodio, en Orbital y en Stremio
            seen = parse_watched(state.get("watched"), video_ids) | {video_id}
            state["watched"] = encode_watched(seen, video_ids) or state.get("watched")
        if next_video:  # sigue en "Seguir viendo", ya en el siguiente episodio
            state.update({"video_id": next_video, "timeOffset": 1, "timeWatched": 0, "duration": 0})
        else:
            state["timeOffset"] = 0  # terminada: sale de "Seguir viendo"
    item["state"] = state
    item["_mtime"] = _iso(now)
    return item


def parse_watched(watched: str | None, video_ids: list[str]) -> set[str]:
    """Los episodios vistos según Stremio (state.watched).

    Formato de stremio-core (WatchedBitField): "{video ancla}:{largo}:{bits}", con los bits en
    base64 de zlib, uno por video en el orden del catálogo (el bit 0 es el menos significativo del
    primer byte). El ancla es el último visto y alinea la lista si el catálogo cambió de largo."""
    if not isinstance(watched, str) or not watched or not video_ids:
        return set()
    try:
        anchor, length, data = watched.rsplit(":", 2)
        bits = zlib.decompress(base64.b64decode(data))
        length = int(length)
    except (ValueError, zlib.error, binascii.Error):
        return set()
    offset = (length - 1) - video_ids.index(anchor) if anchor in video_ids else 0
    seen = set()
    for i, video in enumerate(video_ids):
        bit = i + offset
        if 0 <= bit < len(bits) * 8 and (bits[bit >> 3] >> (bit & 7)) & 1:
            seen.add(video)
    return seen


def encode_watched(seen: set[str], video_ids: list[str]) -> str | None:
    """Lo contrario de parse_watched (para marcar como visto lo que terminaste en Orbital)."""
    marks = [i for i, video in enumerate(video_ids) if video in seen]
    if not marks:
        return None
    length = marks[-1] + 1
    bits = bytearray((length + 7) // 8)
    for i in marks:
        bits[i >> 3] |= 1 << (i & 7)
    return f"{video_ids[marks[-1]]}:{length}:{base64.b64encode(zlib.compress(bytes(bits))).decode()}"


def library_toggled(raw: dict | None, *, meta_id: str, kind: str, name: str, poster: str | None,
                    add: bool, now: float) -> dict:
    """El libraryItem dentro o fuera de tu biblioteca de Stremio ("Mi lista"): `removed` y `temp`
    son lo que Stremio usa para eso; el avance (state) no se toca."""
    item: dict[str, Any] = dict(raw or {
        "_id": meta_id, "name": name, "type": kind, "poster": poster, "posterShape": "poster",
        "_ctime": _iso(now), "state": {},
        "behaviorHints": {"defaultVideoId": None, "featuredVideoId": None, "hasScheduledVideos": False},
    })
    item["removed"] = not add
    item["temp"] = False if add else bool(item.get("temp"))
    item["_mtime"] = _iso(now)
    return item


def dismissed(raw: dict, now: float) -> dict:
    """El libraryItem fuera de "Seguir viendo" (como el "Quitar" de Stremio: sin avance pendiente)."""
    item = dict(raw)
    state = dict(state_of(item))
    state["timeOffset"] = 0
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
    in_library: bool = False  # en tu biblioteca de Stremio (Mi lista), no solo algo que viste

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
    except (ValueError, OSError, OverflowError):  # fechas imposibles (año 1 o 9999)
        return None


def parse_item(raw: dict) -> Watchable | None:
    item_id, name = raw.get("_id"), raw.get("name")
    if isinstance(name, (int, float)) and not isinstance(name, bool):
        name = str(name)  # «1917»: el título es un número
    if not isinstance(item_id, str) or not item_id or not isinstance(name, str) or not name.strip():
        return None
    state = state_of(raw)
    raw_type = raw.get("type")
    kind = raw_type if isinstance(raw_type, str) and raw_type else "other"
    removed, temp = bool(raw.get("removed")), bool(raw.get("temp"))
    offset = as_int(state.get("timeOffset"))
    if removed and not temp:
        return None
    return Watchable(
        id=item_id,
        type=kind,
        name=name,
        poster=raw.get("poster") if isinstance(raw.get("poster"), str) and raw.get("poster") else None,
        video_id=state.get("video_id") if isinstance(state.get("video_id"), str) and state.get("video_id") else None,
        time_offset=offset,
        duration=as_int(state.get("duration")),
        last_watched=_epoch(state.get("lastWatched")),
        # Misma regla que stremio-core (LibraryItem::is_in_continue_watching).
        in_continue=kind != "other" and offset > 0,
        in_library=not removed and not temp,
    )


def parse_library(raw_items: list[dict]) -> list[Watchable]:
    items = []
    for raw in raw_items if isinstance(raw_items, list) else []:
        try:
            item = parse_item(raw) if isinstance(raw, dict) else None
        except (TypeError, ValueError, AttributeError, OverflowError, OSError) as exc:
            log.warning("Stremio: se salta un elemento raro de tu biblioteca (%s)", exc)
            continue
        if item:
            items.append(item)
    return sorted(items, key=lambda w: w.last_watched or 0, reverse=True)
