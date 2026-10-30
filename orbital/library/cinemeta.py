"""Cinemeta: el catálogo público de Stremio (películas y series populares, temporadas y episodios).

No necesita cuenta. Orbital lo usa para explorar con el mando dentro de su propia interfaz; Stremio
solo pone la pantalla de reproducción (enlace stremio:// con autoPlay).

Las fichas de IMDb (tt…) salen de Cinemeta, en el idioma de Orbital (localize.py): así no cambian
según el orden de los complementos de tu cuenta. Lo que Cinemeta no conoce (anime de Kitsu, etc.)
se pide al primer complemento de tu lista que sabe de ese título.

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
from collections.abc import Callable
from datetime import UTC, datetime
from pathlib import Path
from urllib.parse import quote

from ..net import NET_ERRORS, read_json
from . import addons as addons_mod
from .models import LibraryItem

log = logging.getLogger(__name__)

BASE = "https://v3-cinemeta.strem.io"
MANIFEST = f"{BASE}/manifest.json"  # addon del catálogo, para el enlace al reproductor
CACHE_SECONDS = 6 * 3600
KIND_LABEL = {"movie": "Película", "series": "Serie"}


CACHE_MAX = 400  # respuestas guardadas a lo más (búsquedas y fichas)
# Una ficha que no existe en ningún lado (404 en todas las fuentes): se recuerda un rato. Cada vez que se pedía la
# biblioteca, los títulos de un complemento ajeno a Cinemeta se volvían a buscar varias veces por segundo (orbital.log).
MISSING_SECONDS = 6 * 3600


class CinemetaError(Exception):
    pass


class TitleNotFound(CinemetaError):
    """El catálogo respondió, pero ese título no existe (404, no un problema de red)."""


class Cinemeta:
    def __init__(self, base: str = BASE, timeout: float = 10, registry: addons_mod.AddonRegistry | None = None) -> None:
        self.base = base.rstrip("/")
        self.timeout = timeout
        self.registry = registry  # tus complementos: quién más sabe dar fichas
        self.localize: Callable[[str, dict], dict] | None = None  # la ficha en el idioma de Orbital
        self._cache: dict[str, tuple[float, dict]] = {}
        self._missing: dict[str, float] = {}  # ficha -> cuándo se vio que no existe en ninguna fuente
        self._lock = threading.Lock()
        # Modo sin internet: las fichas que ya abriste quedan en disco (`saved`); sin conexión se enseña lo guardado.
        self.saved: Path | None = None
        self._save_timer: threading.Timer | None = None

    def keep_on_disk(self, path: Path) -> None:
        """Guarda las fichas en `path` y carga las de la vez pasada (sin internet, se ven igual)."""
        self.saved = path
        try:
            raw = json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}
        except (OSError, ValueError):
            raw = {}
        with self._lock:
            for url, entry in raw.items() if isinstance(raw, dict) else []:
                if isinstance(entry, list) and len(entry) == 2 and isinstance(entry[1], dict):
                    self._cache.setdefault(url, (float(entry[0]), entry[1]))

    def _save_later(self) -> None:
        if self.saved is None or self._save_timer is not None:
            return
        self._save_timer = threading.Timer(5.0, self._save)
        self._save_timer.daemon = True
        self._save_timer.start()

    def _save(self) -> None:
        self._save_timer = None
        if self.saved is None:
            return
        with self._lock:  # solo fichas (/meta/): las listas cambian a diario y ocupan más
            data = {url: [at, d] for url, (at, d) in self._cache.items() if "/meta/" in url}
        try:
            self.saved.parent.mkdir(parents=True, exist_ok=True)
            tmp = self.saved.with_suffix(".tmp")
            tmp.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
            tmp.replace(self.saved)
        except OSError as exc:
            log.info("No pude guardar las fichas: %s", exc)

    def _get(self, path: str, base: str | None = None) -> dict:
        url = f"{base or self.base}{path}"
        with self._lock:
            hit = self._cache.get(url)
            if hit and time.time() - hit[0] < CACHE_SECONDS:
                return hit[1]
        req = urllib.request.Request(url, headers={"User-Agent": "Orbital"})
        try:
            with urllib.request.urlopen(req, timeout=self.timeout) as res:
                data = read_json(res, timeout=self.timeout)
        except NET_ERRORS as exc:
            if hit and not (isinstance(exc, urllib.error.HTTPError) and exc.code == 404):
                return hit[1]  # sin internet: la de la última vez (vencida, pero es la misma ficha)
            raise CinemetaError(f"No pude leer el catálogo de Stremio: {exc}") from exc
        if not isinstance(data, dict):
            raise CinemetaError("Respuesta inesperada de Cinemeta")
        with self._lock:
            if len(self._cache) >= CACHE_MAX:  # una consola siempre encendida: la caché no crece sin tope
                now = time.time()
                for key in [k for k, (at, _) in self._cache.items() if now - at >= CACHE_SECONDS] or \
                        sorted(self._cache, key=lambda k: self._cache[k][0])[:CACHE_MAX // 4]:
                    self._cache.pop(key, None)
            self._cache[url] = (time.time(), data)
        if "/meta/" in url:
            self._save_later()
        return data

    def catalog(self, kind: str) -> list[dict]:
        metas = self._get(f"/catalog/{kind}/top.json").get("metas")
        return [m for m in metas if _usable(m)] if isinstance(metas, list) else []

    def genre(self, kind: str, genre: str) -> list[dict]:
        """Lo más popular de un género («Horror», «Comedy»…): «pon algo de terror»."""
        from urllib.parse import quote

        metas = self._get(f"/catalog/{kind}/top/genre={quote(genre, safe='')}.json").get("metas")
        return [m for m in metas if _usable(m)] if isinstance(metas, list) else []

    def search(self, kind: str, query: str) -> list[dict]:
        """Búsqueda tolerante a errores ("ofice" encuentra The Office); 2-3 letras suelen bastar."""
        from urllib.parse import quote

        metas = self._get(f"/catalog/{kind}/top/search={quote(query.strip(), safe='')}.json").get("metas")
        return [m for m in metas if _usable(m)] if isinstance(metas, list) else []

    def meta_sources(self, kind: str, meta_id: str) -> list[str | None]:
        """De dónde pedir la ficha, en orden (None = Cinemeta). Un id de IMDb, primero Cinemeta; otro
        (kitsu:…), primero los complementos que saben de él, sin esperar a la cuenta."""
        known = self.registry.known() if self.registry else []
        others = [a.base for a in known if a.handles("meta", kind, meta_id) and a.base != self.base]
        return [None, *others] if str(meta_id).startswith("tt") else [*others, None]

    def meta(self, kind: str, meta_id: str, localized: bool = True) -> dict:
        """La ficha; `localized=False`, tal cual la da Cinemeta (lo que se guarda en tu cuenta de
        Stremio va con el título original, no con el traducido)."""
        path = f"/meta/{quote(kind)}/{quote(str(meta_id), safe=':')}.json"
        error = CinemetaError("Título no encontrado")
        if time.time() - self._missing.get(path, -MISSING_SECONDS) < MISSING_SECONDS:
            raise error
        only_missing = True  # todas las fuentes dijeron 404 (no un error de red, que puede ser pasajero)
        for base in self.meta_sources(kind, meta_id):
            try:
                meta = (self._get(path, base) if base else self._get(path)).get("meta")
            except CinemetaError as exc:
                log.info("Sin ficha de %s en %s: %s", meta_id, addons_mod.redact(base) if base else "Cinemeta", exc)
                error = exc
                only_missing = only_missing and "404" in str(exc)
                continue
            if isinstance(meta, dict):
                return self.localize(kind, meta) if self.localize and localized and base is None else meta
        if only_missing:
            with self._lock:
                if len(self._missing) >= CACHE_MAX:
                    self._missing.clear()
                self._missing[path] = time.time()
        raise error


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
    return url.replace("/poster/small/", "/poster/medium/") if isinstance(url, str) and url else None


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


def released_at(released) -> float | None:
    """La fecha de estreno de un episodio en segundos desde 1970 (None sin fecha o con una rara)."""
    if not isinstance(released, str) or not released:
        return None
    try:
        when = datetime.fromisoformat(released.replace("Z", "+00:00"))
    except ValueError:
        return None
    if when.tzinfo is None:
        when = when.replace(tzinfo=UTC)
    return when.timestamp()


def aired(released, now: float | None = None) -> bool:
    """¿Ya salió? Sin fecha (o con una rara) se da por emitido."""
    when = released_at(released)
    return when is None or when <= (time.time() if now is None else now) + 12 * 3600


def next_episode(meta: dict, video_id: str, now: float | None = None) -> str | None:
    """El episodio que sigue a `video_id` (pasa de temporada; los especiales no cuentan). Uno que aún no
    se emite no cuenta: en una serie al día, la tarjeta «Siguiente episodio» ofrecía uno que no existe."""
    episodes = [e for s in seasons(meta) if s["season"] != 0 for e in s["episodes"]]
    ids = [e["id"] for e in episodes]
    if video_id in ids:
        i = ids.index(video_id)
        if i + 1 < len(episodes) and aired(episodes[i + 1]["released"], now):
            return ids[i + 1]
    return None


def new_episode(meta: dict, video_id: str, since: float, now: float | None = None) -> tuple[str, float] | None:
    """Ibas al día: terminaste `video_id` y el siguiente aún no salía. Si ya salió (después de `since`, cuando lo
    terminaste), (su id, su fecha); si no, None. Así la serie vuelve sola a Seguir viendo con su episodio nuevo."""
    following = next_episode(meta, video_id, now)
    if following is None:
        return None
    episode = next(e for s in seasons(meta) for e in s["episodes"] if e["id"] == following)
    when = released_at(episode["released"])
    return (following, when) if when is not None and when > since else None


_ARTICLES = ("the ", "el ", "la ", "los ", "las ")


def _without_article(name: str) -> str:
    """«the office» → «office»: el artículo no le quita lo exacto (con «office», The Office empataba en orden de
    Cinemeta con una serie nueva llamada «Office», y la nueva ganaba por ser exacta)."""
    for article in _ARTICLES:
        if name.startswith(article):
            return name[len(article):]
    return name


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
    q = _without_article(q)
    merged.sort(key=lambda km: _without_article(km[1]["name"].strip().lower()) != q)  # estable: respeta el resto
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
