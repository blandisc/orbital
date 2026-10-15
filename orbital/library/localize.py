"""Fichas en el idioma de Orbital: Cinemeta solo habla inglés; TMDB pone título, sinopsis, géneros
y episodios en tu idioma (ui.language, o el que elijas en Ajustes). En inglés no se toca nada.

Necesita la clave de TMDB de «Para ti» (para_ti.tmdb_key); sin ella, las fichas siguen en inglés.
Lo que TMDB no tiene traducido (una sinopsis vacía) se queda como venía de Cinemeta.
"""

from __future__ import annotations

import copy
import logging
import re
import threading
import time
from collections.abc import Callable
from concurrent.futures import ThreadPoolExecutor

from . import tmdb as tmdb_api

log = logging.getLogger(__name__)

CACHE_SECONDS = 24 * 3600
RETRY_SECONDS = 600  # TMDB no respondió: no se le vuelve a preguntar por ese título en un rato
CACHE_MAX = 500
REGIONS = {"es": "es-MX", "pt": "pt-BR"}  # el español de México, no el de España
# Sin traducción, TMDB llama al episodio «Episodio 3»: mejor el título original de Cinemeta.
GENERIC_EPISODE = re.compile(r"^(episodio|episode|épisode|episódio|folge|episodio n\.?)\s*\d+$", re.I)


def tmdb_language(language: str | None) -> str | None:
    """«es» -> «es-MX»; None si no hay que traducir (inglés, o nada)."""
    lang = str(language or "").strip()
    if not lang or lang.lower().startswith("en"):
        return None
    return REGIONS.get(lang.lower(), lang)


class Localizer:
    def __init__(self, tmdb: tmdb_api.Tmdb, language: Callable[[], str | None]) -> None:
        self.tmdb = tmdb
        self.language = language
        self._cache: dict[tuple, tuple[float, dict | None]] = {}
        self._lock = threading.Lock()

    @property
    def active(self) -> str | None:
        return tmdb_language(self.language()) if self.tmdb.configured else None

    def _remember(self, key: tuple, fetch: Callable[[], dict | None]) -> dict | None:
        with self._lock:
            hit = self._cache.get(key)
            if hit and time.time() < hit[0]:
                return hit[1]
        try:
            value, ttl = fetch(), CACHE_SECONDS
        except tmdb_api.TmdbError as exc:
            log.info("Ficha sin traducir (%s): %s", key[1], exc)
            value, ttl = None, RETRY_SECONDS
        with self._lock:
            if len(self._cache) >= CACHE_MAX:
                for old in sorted(self._cache, key=lambda k: self._cache[k][0])[:CACHE_MAX // 4]:
                    del self._cache[old]
            self._cache[key] = (time.time() + ttl, value)
        return value

    def _translation(self, kind: str, imdb: str, lang: str, episodes: bool) -> dict | None:
        def fetch() -> dict | None:
            found = self.tmdb.find_id(imdb, kind)
            return self.tmdb.translation(kind, found, lang, episodes=episodes) if found else {}

        return self._remember((lang, imdb, kind, episodes), fetch)

    def meta(self, kind: str, meta: dict) -> dict:
        """La ficha en tu idioma (una copia: la de Cinemeta en caché no se toca)."""
        lang, imdb = self.active, meta.get("imdb_id") or meta.get("id")
        if not lang or kind not in ("movie", "series") or not isinstance(imdb, str) or not imdb.startswith("tt"):
            return meta
        found = self._translation(kind, imdb, lang, episodes=kind == "series")
        return apply(meta, found) if found else meta

    def catalog(self, kind: str, metas: list[dict]) -> list[dict]:
        """Título y sinopsis de una fila (sin episodios: una consulta por título)."""
        lang = self.active
        if not lang:
            return metas

        def one(meta: dict) -> dict:
            imdb = meta.get("id")
            found = self._translation(kind, imdb, lang, episodes=False) \
                if isinstance(imdb, str) and imdb.startswith("tt") else None
            return apply(meta, found) if found else meta

        with ThreadPoolExecutor(max_workers=8) as pool:
            return list(pool.map(one, metas))


def apply(meta: dict, found: dict) -> dict:
    """La ficha de Cinemeta con lo que TMDB tiene traducido; lo vacío se queda como estaba."""
    out = copy.copy(meta)
    for field, value in (("name", found.get("title")), ("description", found.get("overview"))):
        if value:
            out[field] = value
    if found.get("genres"):
        out["genres"] = found["genres"]
    episodes = found.get("episodes") or {}
    if episodes and isinstance(meta.get("videos"), list):
        videos = []
        for video in meta["videos"]:
            ep = episodes.get((video.get("season"), video.get("episode"))) if isinstance(video, dict) else None
            if ep:
                video = dict(video)
                if ep.get("name") and not GENERIC_EPISODE.match(ep["name"]):
                    video["name"] = ep["name"]
                    video.pop("title", None)
                if ep.get("overview"):
                    video["overview"] = ep["overview"]
                    video.pop("description", None)
            videos.append(video)
        out["videos"] = videos
    return out
