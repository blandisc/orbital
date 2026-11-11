"""Las tarjetas de la biblioteca (Seguir viendo), el tráiler y las pistas de audio ya vistas."""

from __future__ import annotations

import json
import logging
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import replace
from pathlib import Path

from ..atomic import atomic_write
from ..library import addons, cinemeta, stremio_api
from ..library.models import LibraryItem

log = logging.getLogger("orbital.watch")  # el mismo nombre de siempre: los avisos y la bitácora no cambian


def expired_session(exc: Exception) -> bool:
    """¿Stremio dice que la sesión ya no vale? (tienes que volver a conectar la cuenta)"""
    text = str(exc).lower()
    return any(w in text for w in ("session not found", "not authorized", "unauthorized", "invalid auth", "authkey"))


def time_left(seconds: float) -> str:
    """"quedan 11 min" / "quedan 1 h 40 min" (vacío si falta menos de un minuto)."""
    minutes = int(seconds // 60)
    if minutes < 1:
        return ""
    hours, minutes = divmod(minutes, 60)
    return f"quedan {hours} h {minutes} min" if hours and minutes else f"quedan {hours} h" if hours else f"quedan {minutes} min"


CONTINUE_MIN_PROGRESS = .01  # menos del 1 % (lo abriste un momento): no ensucia Seguir viendo


def addon_gives(addon: addons.Addon | None) -> str:
    """Qué aporta un complemento, en una línea («Fuentes de video · Subtítulos»), de su manifiesto."""
    if addon is None:
        return ""
    names = {"stream": "Fuentes de video", "subtitles": "Subtítulos", "catalog": "Catálogos", "meta": "Fichas"}
    return " · ".join(names[r] for r in ("stream", "subtitles", "catalog", "meta") if r in addon.rules)


def stremio_item(w: stremio_api.Watchable) -> LibraryItem:
    season, episode = w.episode
    if episode is not None:
        detail = f"T{season} E{episode}" if season is not None else f"Episodio {episode}"
    else:
        detail = "Película" if w.type == "movie" else "Serie" if w.type == "series" else ""
    left = (w.duration - w.time_offset) / 1000 if w.duration and w.time_offset > 0 else 0
    # Terminaste un episodio y Stremio ya apunta al siguiente (sin avance): "Sigue: T8 E24".
    next_up = w.type == "series" and w.time_offset <= 1 and not w.duration and episode is not None
    subtitle = f"Sigue: {detail}" if next_up else " · ".join(filter(None, [detail, time_left(left)]))
    barely = w.progress is not None and w.progress < CONTINUE_MIN_PROGRESS and not next_up
    return LibraryItem(
        id=f"stremio:{w.id}",
        title=w.name,
        # Solo "Seguir viendo" tiene fila; el resto de la biblioteca sirve para la voz.
        category="continue" if w.in_continue and not barely else "stremio",
        source="stremio",
        subtitle=subtitle,
        # Con id de IMDb, el póster de metahub (el de Amazon que guarda Stremio a veces ya no existe).
        image=stremio_api.METAHUB_POSTER.format(id=w.id) if w.id.startswith("tt") else w.poster,
        hero=w.background,
        uri=w.deep_link,
        progress=w.progress,
        last_watched=w.last_watched,
        # Para elegir la fuente en Orbital (Seguir viendo -> el mismo episodio).
        extra={"kind": w.type, "meta_id": w.id, "video_id": w.video_id or (w.id if w.type == "movie" else None),
               "in_library": w.in_library, "left": round(left) if left >= 60 else None,  # para «termina a las…»
               "eyebrow": " · ".join(filter(None, ["Película" if w.type == "movie" else "Serie", detail if episode else ""]))},
    )


def returning_item(w: stremio_api.Watchable, video_id: str, released: float) -> LibraryItem:
    """Ibas al día y ya salió el episodio que sigue: la serie vuelve a Seguir viendo («Nuevo: T38 E5»), en su lugar según
    cuándo salió. En tu cuenta de Stremio no se escribe nada: se deduce cada vez."""
    item = stremio_item(replace(w, video_id=video_id, time_offset=1, duration=0, last_watched=released, in_continue=True))
    item.subtitle = item.subtitle.replace("Sigue:", "Nuevo:", 1)
    item.extra["new_episode"] = True
    return item


def trailer_id(info: dict) -> str | None:
    """El video de YouTube del tráiler (Cinemeta: trailerStreams[].ytId o trailers[].source)."""
    for stream in info.get("trailerStreams") or []:
        if isinstance(stream, dict) and stream.get("ytId"):
            return str(stream["ytId"])
    for trailer in info.get("trailers") or []:
        if isinstance(trailer, dict) and trailer.get("source") and trailer.get("type", "Trailer") == "Trailer":
            return str(trailer["source"])
    return None


_YOUTUBE_SEEN: dict[str, bool] = {}


def youtube_available(video: str, *, open_url=urllib.request.urlopen) -> bool:
    """¿Ese video de YouTube existe y es público? Cinemeta a veces trae el id de un tráiler que ya borraron o que es
    privado, y «Tráiler» salía para nada. oEmbed contesta 401/404 en esos casos. Sin red: sí (un tropiezo no lo esconde,
    y no se recuerda)."""
    if video in _YOUTUBE_SEEN:
        return _YOUTUBE_SEEN[video]
    url = "https://www.youtube.com/oembed?format=json&url=" + urllib.parse.quote(f"https://www.youtube.com/watch?v={video}", safe="")
    try:
        with open_url(url, timeout=3) as response:
            ok = 200 <= response.status < 300
    except urllib.error.HTTPError as exc:
        ok = exc.code not in (400, 401, 403, 404)
    except (OSError, ValueError):
        return True
    _YOUTUBE_SEEN[video] = ok
    return ok


def enrich_watch_item(item: LibraryItem, info: dict) -> None:
    """Seguir viendo con lo mismo que el catálogo: sinopsis, calificación, géneros, logo y el
    nombre del episodio ("Serie · T8 E23 · Homer's Enemy")."""
    item.extra.update({k: v for k, v in cinemeta.describe_meta(info).items() if v})
    video_id = item.extra.get("video_id")
    if item.extra.get("kind") == "series" and video_id:
        for season in cinemeta.seasons(info):
            for ep in season["episodes"]:
                if ep["id"] == video_id:
                    item.extra["episode_title"] = ep["title"]
                    item.extra["eyebrow"] = f"Serie · T{season['season']} E{ep['episode']} · {ep['title']}"
    if not item.hero and info.get("background"):
        item.hero = info["background"]


class HeardTracks:
    """Las pistas de audio que el reproductor vio en cada fuente (por su huella), para decir «Comprobado» la próxima
    vez sin volver a abrirla. Un archivo chico en la caché; las más viejas se van."""

    LIMIT = 1000

    def __init__(self, path: Path | None) -> None:
        self.path = path
        self._lock = threading.Lock()
        self._data: dict[str, dict] | None = None

    def _load(self) -> dict[str, dict]:
        if self._data is None:
            try:
                raw = json.loads(self.path.read_text(encoding="utf-8-sig")) if self.path and self.path.exists() else {}
            except (OSError, ValueError):
                raw = {}
            self._data = raw if isinstance(raw, dict) else {}
        return self._data

    def get(self, key: str) -> list[dict] | None:
        with self._lock:
            hit = self._load().get(key)
        return hit.get("audio") if isinstance(hit, dict) and isinstance(hit.get("audio"), list) else None

    def put(self, key: str, audio: list[dict]) -> None:
        with self._lock:
            data = self._load()
            data.pop(key, None)
            data[key] = {"audio": audio, "at": int(time.time())}
            while len(data) > self.LIMIT:
                data.pop(next(iter(data)))
            if not self.path:
                return
            try:
                self.path.parent.mkdir(parents=True, exist_ok=True)
                atomic_write(self.path, json.dumps(data, ensure_ascii=False), encoding="utf-8")
            except OSError:
                log.warning("No pude guardar las pistas que vio el reproductor", exc_info=True)
