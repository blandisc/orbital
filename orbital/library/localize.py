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
        self.on_name: Callable[[str, str, str], None] | None = None  # (imdb, nombre, idioma): TitleNames lo recuerda

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
        if found and found.get("title") and self.on_name:
            self.on_name(imdb, found["title"], lang)
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


class TitleNames:
    """El nombre de cada película o serie en el idioma de Orbital, el mismo en todos lados: la ficha y Buscar ya lo
    traducían (TMDB) pero las listas de Trakt, Para ti y tu biblioteca de Stremio llegaban en inglés («Dune: Part Two» en
    una fila y «Dune: Parte dos» en la ficha). Se guarda en disco; lo que falta se pide en segundo plano (nunca hace
    esperar a una lista) y entra en la siguiente vuelta. En inglés, o sin clave de TMDB, todo queda como viene."""

    SAVE_DELAY = 5.0

    def __init__(self, localizer: Localizer, path=None, on_new: Callable[[], None] | None = None) -> None:
        self.localizer = localizer
        self.path = path
        self.on_new = on_new  # llegaron nombres nuevos (la interfaz vuelve a pedir lo que enseña)
        self._names: dict[str, dict[str, str]] = {}
        self._tried: set[tuple[str, str]] = set()
        self._lock = threading.Lock()
        self._pool = ThreadPoolExecutor(max_workers=4, thread_name_prefix="nombres")
        self._save_timer: threading.Timer | None = None
        self._load()

    def _load(self) -> None:
        if not self.path:
            return
        import json
        try:
            raw = json.loads(self.path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return
        if isinstance(raw, dict):
            self._names = {lang: {k: v for k, v in names.items() if isinstance(v, str)}
                           for lang, names in raw.items() if isinstance(names, dict)}

    def _save(self) -> None:
        if not self.path:
            return
        import json
        with self._lock:
            data = json.dumps(self._names, ensure_ascii=False)
        try:
            self.path.parent.mkdir(parents=True, exist_ok=True)
            tmp = self.path.with_suffix(".tmp")
            tmp.write_text(data, encoding="utf-8")
            tmp.replace(self.path)
        except OSError as exc:
            log.info("No pude guardar los nombres traducidos: %s", exc)

    def _schedule_save(self) -> None:
        with self._lock:
            if self._save_timer:
                return
            self._save_timer = threading.Timer(self.SAVE_DELAY, self._flush)
            self._save_timer.daemon = True
            self._save_timer.start()

    def _flush(self) -> None:
        with self._lock:
            self._save_timer = None
        self._save()
        if self.on_new:
            self.on_new()

    def remember(self, imdb: str, name: str, lang: str | None = None) -> None:
        """Un nombre ya traducido (la ficha lo trae): sirve para todo lo demás."""
        lang = lang or self.localizer.active
        if not lang or not isinstance(imdb, str) or not imdb.startswith("tt") or not str(name or "").strip():
            return
        with self._lock:
            if self._names.setdefault(lang, {}).get(imdb) == name.strip():
                return
            self._names[lang][imdb] = name.strip()
        self._schedule_save()

    def _fetch(self, kind: str, imdb: str, lang: str) -> None:
        found = self.localizer._translation(kind, imdb, lang, episodes=False)
        if found and found.get("title"):
            self.remember(imdb, found["title"], lang)

    def name(self, kind: str | None, imdb: str | None) -> str | None:
        """El nombre en tu idioma si ya se sabe (si no, se pide para la próxima)."""
        lang = self.localizer.active
        if not lang or kind not in ("movie", "series") or not isinstance(imdb, str) or not imdb.startswith("tt"):
            return None
        with self._lock:
            hit = self._names.get(lang, {}).get(imdb)
            ask = hit is None and (lang, imdb) not in self._tried
            if ask:
                self._tried.add((lang, imdb))
        if ask:
            self._pool.submit(self._fetch, kind, imdb, lang)
        return hit
