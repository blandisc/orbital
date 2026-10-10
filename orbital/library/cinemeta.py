"""Cinemeta: el catálogo público de Stremio (películas y series populares, temporadas y episodios).

No necesita cuenta. Orbital lo usa para explorar con el mando dentro de su propia interfaz; Stremio
solo pone la pantalla de reproducción (enlace stremio:// con autoPlay).

  GET https://v3-cinemeta.strem.io/catalog/{movie|series}/top.json -> {"metas": [...]}
  GET https://v3-cinemeta.strem.io/meta/series/{id}.json           -> {"meta": {..., "videos": [...]}}
"""

from __future__ import annotations

import json
import logging
import threading
import time
import urllib.error
import urllib.request

from .models import LibraryItem

log = logging.getLogger(__name__)

BASE = "https://v3-cinemeta.strem.io"
MANIFEST = f"{BASE}/manifest.json"  # addon del catálogo, para el enlace al reproductor
CACHE_SECONDS = 6 * 3600
KIND_LABEL = {"movie": "Película", "series": "Serie"}


class CinemetaError(Exception):
    pass


class Cinemeta:
    def __init__(self, base: str = BASE, timeout: float = 10) -> None:
        self.base = base.rstrip("/")
        self.timeout = timeout
        self._cache: dict[str, tuple[float, object]] = {}
        self._lock = threading.Lock()

    def _get(self, path: str) -> dict:
        with self._lock:
            hit = self._cache.get(path)
            if hit and time.time() - hit[0] < CACHE_SECONDS:
                return hit[1]
        req = urllib.request.Request(f"{self.base}{path}", headers={"User-Agent": "Orbital"})
        try:
            with urllib.request.urlopen(req, timeout=self.timeout) as res:
                data = json.load(res)
        except (urllib.error.URLError, TimeoutError, ValueError) as exc:
            raise CinemetaError(f"No pude leer el catálogo de Stremio: {exc}") from exc
        if not isinstance(data, dict):
            raise CinemetaError("Respuesta inesperada de Cinemeta")
        with self._lock:
            self._cache[path] = (time.time(), data)
        return data

    def catalog(self, kind: str) -> list[dict]:
        metas = self._get(f"/catalog/{kind}/top.json").get("metas") or []
        return [m for m in metas if isinstance(m, dict) and m.get("id") and m.get("name")]

    def search(self, kind: str, query: str) -> list[dict]:
        """Búsqueda tolerante a errores ("ofice" encuentra The Office); 2-3 letras suelen bastar."""
        from urllib.parse import quote

        metas = self._get(f"/catalog/{kind}/top/search={quote(query.strip())}.json").get("metas") or []
        return [m for m in metas if isinstance(m, dict) and m.get("id") and m.get("name")]

    def meta(self, kind: str, meta_id: str) -> dict:
        meta = self._get(f"/meta/{kind}/{meta_id}.json").get("meta")
        if not isinstance(meta, dict):
            raise CinemetaError("Título no encontrado")
        return meta


def play_link(kind: str, meta_id: str, video_id: str | None = None, autoplay: bool = True) -> str:
    """Enlace a Stremio. Con autoPlay arranca la mejor fuente sin pasar por sus pantallas.
    En películas el video_id es el mismo id; en series, "{id}:{temporada}:{episodio}"."""
    video = video_id or (meta_id if kind == "movie" else None)
    link = f"stremio:///detail/{kind}/{meta_id}"
    if video:
        link += f"/{video}"
        if autoplay:
            link += "?autoPlay=true"
    return link


def _medium(url: str | None) -> str | None:
    # Los pósters del catálogo vienen en tamaño "small": para una TV hace falta "medium".
    return url.replace("/poster/small/", "/poster/medium/") if url else None


def describe_meta(meta: dict) -> dict:
    """Datos para el héroe: año, calificación, géneros, sinopsis y logotipo."""
    rating = str(meta.get("imdbRating") or "").strip()
    return {
        "year": str(meta.get("releaseInfo") or meta.get("year") or "").strip(),
        "rating": rating if rating and rating != "0" else "",
        "genres": [g for g in (meta.get("genres") or meta.get("genre") or []) if isinstance(g, str)][:3],
        "description": str(meta.get("description") or "").strip(),
        "logo": meta.get("logo") or None,
        "runtime": str(meta.get("runtime") or "").strip(),
    }


def catalog_items(kind: str, metas: list[dict], limit: int = 30) -> list[LibraryItem]:
    category = "movies" if kind == "movie" else "series"
    items = []
    for meta in metas[:limit]:
        info = describe_meta(meta)
        items.append(LibraryItem(
            id=f"cinemeta:{kind}:{meta['id']}",
            title=meta["name"],
            category=category,
            source="cinemeta",
            subtitle=" · ".join(filter(None, [KIND_LABEL.get(kind, ""), info["year"]])),
            image=_medium(meta.get("poster")),
            hero=meta.get("background") or None,
            # Película: directo a reproducir. Serie: la interfaz abre el selector de episodios.
            uri=play_link(kind, meta["id"]) if kind == "movie" else play_link(kind, meta["id"], autoplay=False),
            extra=info,
        ))
    return items


def seasons(meta: dict) -> list[dict]:
    """Temporadas con sus episodios, en orden; los especiales (temporada 0) al final."""
    by_season: dict[int, list[dict]] = {}
    for video in meta.get("videos") or []:
        season, episode = video.get("season"), video.get("episode")
        if not isinstance(season, int) or not isinstance(episode, int) or not video.get("id"):
            continue
        by_season.setdefault(season, []).append({
            "id": video["id"],
            "episode": episode,
            "title": video.get("name") or video.get("title") or f"Episodio {episode}",
            "thumbnail": video.get("thumbnail") or None,
            "overview": (video.get("overview") or video.get("description") or "").strip(),
            "released": video.get("released") or None,
        })
    order = sorted(by_season, key=lambda s: (s == 0, s))
    return [{"season": s, "label": "Especiales" if s == 0 else f"Temporada {s}",
             "episodes": sorted(by_season[s], key=lambda e: e["episode"])} for s in order]


def search_results(query: str, movies: list[dict], series: list[dict], limit: int = 18) -> list[dict]:
    """Une películas y series alternando tipos (para que uno no tape al otro) y respetando el orden de
    Cinemeta, que ya ordena por relevancia y popularidad y tolera errores de dedo. Solo se sube una
    coincidencia exacta: "subir lo que empieza igual" ponía "Oficer" antes que "The Office" con "ofice"."""
    q = query.strip().lower()
    merged: list[tuple[str, dict]] = []
    for pair in zip(series, movies):
        merged += [("series", pair[0]), ("movie", pair[1])]
    longer = series if len(series) > len(movies) else movies
    kind_left = "series" if longer is series else "movie"
    merged += [(kind_left, m) for m in longer[min(len(series), len(movies)):]]
    merged.sort(key=lambda km: km[1]["name"].strip().lower() != q)  # estable: respeta el resto
    seen, results = set(), []
    for kind, meta in merged:
        if meta["id"] in seen:
            continue
        seen.add(meta["id"])
        item = catalog_items(kind, [meta])[0]
        results.append({**item.public(), "kind": kind, "meta_id": meta["id"]})
        if len(results) >= limit:
            break
    return results
