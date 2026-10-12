"""Cinemeta: el catálogo público de Stremio (películas y series populares, temporadas y episodios).

No necesita cuenta. Orbital lo usa para explorar con el mando dentro de su propia interfaz; Stremio
solo pone la pantalla de reproducción (enlace stremio:// con autoPlay).

  GET https://v3-cinemeta.strem.io/catalog/{movie|series}/top.json -> {"metas": [...]}
  GET https://v3-cinemeta.strem.io/meta/series/{id}.json           -> {"meta": {..., "videos": [...]}}
"""

from __future__ import annotations

import logging
import threading
import time
import urllib.error
import urllib.request
from urllib.parse import quote

from ..net import NET_ERRORS, read_json
from .models import LibraryItem

log = logging.getLogger(__name__)

BASE = "https://v3-cinemeta.strem.io"
MANIFEST = f"{BASE}/manifest.json"  # addon del catálogo, para el enlace al reproductor
CACHE_SECONDS = 6 * 3600
KIND_LABEL = {"movie": "Película", "series": "Serie"}


CACHE_MAX = 400  # respuestas guardadas a lo más (búsquedas y fichas)


class CinemetaError(Exception):
    pass


class Cinemeta:
    def __init__(self, base: str = BASE, timeout: float = 10) -> None:
        self.base = base.rstrip("/")
        self.timeout = timeout
        self._cache: dict[str, tuple[float, dict]] = {}
        self._lock = threading.Lock()

    def _get(self, path: str) -> dict:
        with self._lock:
            hit = self._cache.get(path)
            if hit and time.time() - hit[0] < CACHE_SECONDS:
                return hit[1]
        req = urllib.request.Request(f"{self.base}{path}", headers={"User-Agent": "Orbital"})
        try:
            with urllib.request.urlopen(req, timeout=self.timeout) as res:
                data = read_json(res, timeout=self.timeout)
        except NET_ERRORS as exc:
            raise CinemetaError(f"No pude leer el catálogo de Stremio: {exc}") from exc
        if not isinstance(data, dict):
            raise CinemetaError("Respuesta inesperada de Cinemeta")
        with self._lock:
            if len(self._cache) >= CACHE_MAX:  # una consola siempre encendida: la caché no crece sin tope
                now = time.time()
                for key in [k for k, (at, _) in self._cache.items() if now - at >= CACHE_SECONDS] or \
                        sorted(self._cache, key=lambda k: self._cache[k][0])[:CACHE_MAX // 4]:
                    self._cache.pop(key, None)
            self._cache[path] = (time.time(), data)
        return data

    def catalog(self, kind: str) -> list[dict]:
        metas = self._get(f"/catalog/{kind}/top.json").get("metas") or []
        return [m for m in metas if _usable(m)]

    def search(self, kind: str, query: str) -> list[dict]:
        """Búsqueda tolerante a errores ("ofice" encuentra The Office); 2-3 letras suelen bastar."""
        from urllib.parse import quote

        metas = self._get(f"/catalog/{kind}/top/search={quote(query.strip(), safe='')}.json").get("metas") or []
        return [m for m in metas if _usable(m)]

    def meta(self, kind: str, meta_id: str) -> dict:
        meta = self._get(f"/meta/{quote(kind)}/{quote(str(meta_id), safe=':')}.json").get("meta")
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
        "genres": [g for g in _list(meta.get("genres") or meta.get("genre")) if isinstance(g, str)][:3],
        "description": str(meta.get("description") or "").strip(),
        "logo": meta.get("logo") if isinstance(meta.get("logo"), str) else None,
        "runtime": str(meta.get("runtime") or "").strip(),
    }


def _usable(meta) -> bool:
    """Un título con id y nombre de texto: un nombre numérico (1917) o una lista tumbaban la biblioteca."""
    return (isinstance(meta, dict) and isinstance(meta.get("id"), str) and meta["id"].strip()
            and isinstance(meta.get("name"), str) and bool(meta["name"].strip()))


def _list(value) -> list:
    """Cinemeta a veces manda un número o un texto donde va una lista: lista vacía."""
    return value if isinstance(value, list) else []


def _names(value) -> list[str]:
    if isinstance(value, str):
        return [n.strip() for n in value.split(",") if n.strip()]
    return [str(n).strip() for n in _list(value) if str(n).strip()]


def credits(meta: dict) -> dict:
    """Para la ficha: reparto, dirección, guion, estreno y premios (Cinemeta los trae; antes se tiraban)."""
    by_category: dict[str, list[str]] = {}
    for link in _list(meta.get("links")):
        if isinstance(link, dict) and link.get("name"):
            by_category.setdefault(str(link.get("category") or "").lower(), []).append(str(link["name"]))
    cast = _names(meta.get("cast")) or by_category.get("cast", [])
    directors = _names(meta.get("director")) or by_category.get("directors", [])
    writers = _names(meta.get("writer")) or by_category.get("writers", [])
    return {"cast": cast[:6], "directors": directors[:3], "writers": writers[:3],
            "released": str(meta.get("released") or "")[:10], "awards": str(meta.get("awards") or "").strip(),
            "country": str(meta.get("country") or "").strip()}


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
    for video in _list(meta.get("videos")):
        if not isinstance(video, dict):
            continue
        season, episode = video.get("season"), video.get("episode")
        if not isinstance(season, int) or not isinstance(episode, int) or not video.get("id"):
            continue
        by_season.setdefault(season, []).append({
            "id": video["id"],
            "episode": episode,
            "title": str(video.get("name") or video.get("title") or f"Episodio {episode}"),
            "thumbnail": video.get("thumbnail") or None,
            "overview": str(video.get("overview") or video.get("description") or "").strip(),
            "released": video.get("released") or None,
        })
    order = sorted(by_season, key=lambda s: (s == 0, s))
    return [{"season": s, "label": "Especiales" if s == 0 else f"Temporada {s}",
             "episodes": sorted(by_season[s], key=lambda e: e["episode"])} for s in order]


def next_episode(meta: dict, video_id: str) -> str | None:
    """El episodio que sigue a `video_id` (pasa de temporada; los especiales no cuentan)."""
    episodes = [e["id"] for s in seasons(meta) if s["season"] != 0 for e in s["episodes"]]
    if video_id in episodes:
        i = episodes.index(video_id)
        return episodes[i + 1] if i + 1 < len(episodes) else None
    return None


def search_results(query: str, movies: list[dict], series: list[dict], limit: int = 18) -> list[dict]:
    """Une películas y series alternando tipos (para que uno no tape al otro) y respetando el orden de
    Cinemeta, que ya ordena por relevancia y popularidad y tolera errores de dedo. Solo se sube una
    coincidencia exacta: "subir lo que empieza igual" ponía "Oficer" antes que "The Office" con "ofice"."""
    q = query.strip().lower()
    merged: list[tuple[str, dict]] = []
    for pair in zip(series, movies, strict=False):
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
