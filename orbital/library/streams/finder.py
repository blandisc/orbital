"""StreamFinder: pide las versiones y los subtítulos a tus complementos a la vez, con caché."""

from __future__ import annotations

import threading
import time
from collections.abc import Callable
from concurrent.futures import ThreadPoolExecutor, wait
from dataclasses import replace
from urllib.parse import quote

from ...net import NET_FAILURES
from .. import addons, opensubtitles
from .. import subtitles as subtitle_lib
from .languages import (
    Preferences,
    heard,
    mentions_title,
    names_another_series,
    other_episode,
    other_year,
    other_years,
    season_of,
    series_years,
)
from .ranking import cache_key, is_opensubtitles, rank, score
from .rules import CACHE_SECONDS, LANG_CODES, REQUEST_TIMEOUT, log
from .source import (
    ACCOUNT_NOTICES,
    CACHE_MAX,
    FIND_DEADLINE,
    PARSE_ERRORS,
    RETRY_FAILED,
    Source,
    is_link,
    parse,
    stable_index,
    torrentio_notice,
)


class StreamFinder:
    """Pide fuentes a los complementos que las dan (en paralelo) y las guarda unos minutos."""

    def __init__(self, registry: addons.AddonRegistry, timeout: float = REQUEST_TIMEOUT) -> None:
        self.registry = registry
        self.timeout = timeout
        self._cache: dict[str, tuple[float, list[Source]]] = {}
        # Cómo le va a cada complemento (addons.Health): la del registro, para que Ajustes › Complementos diga lo mismo.
        self.health = getattr(registry, "health", None) or addons.Health()
        self.outcome: dict[str, str] = {}  # kind:video -> "ok" | "offline" | "no-addons" (para decir por qué no hay)  # complemento -> hasta cuándo no se le pregunta (no respondió)
        self._lock = threading.Lock()
        # Lo que se sabe del título y de cada fuente fuera de los complementos (los pone Watch):
        # facts(kind, video_id) -> {"original": "en" | "ja" | "es-ES"…, "titles": [...]} (de TMDB/Cinemeta);
        # tracks(key) -> las pistas de audio que mpv vio al reproducir esa fuente, o None.
        self.facts: Callable[[str, str], dict | None] = lambda kind, video_id: None
        self.tracks: Callable[[str], list[dict] | None] = lambda key: None
        # Ajustes › Ver › «Buscar subtítulos en internet»: OpenSubtitles viene con Orbital, ya no es complemento (3 nov 2026).
        self.internet_subtitles: Callable[[], bool] = lambda: True
        # La API oficial de OpenSubtitles (con la clave de la app): muchos más; el complemento queda de respaldo. La pone Watch.
        self.opensubtitles: opensubtitles.OpenSubtitles | None = None

    def addons(self) -> list[addons.Addon]:
        return self.registry.addons()

    def _get_json(self, addon: addons.Addon, path: str) -> dict:
        return addons.fetch_json(f"{addon.base}/{path}", self.timeout)

    def _fetch(self, addon: addons.Addon, kind: str, video_id: str) -> list[dict] | None:
        """Las fuentes de un complemento; None si la red falló (para no recordar «no hay» 10 minutos)."""
        started = time.monotonic()
        try:
            streams = self._get_json(addon, f"stream/{kind}/{quote(video_id, safe='')}.json").get("streams")
            streams = streams if isinstance(streams, list) else []
        except NET_FAILURES as exc:
            log.info("Sin fuentes de %s: %s", addon.name, exc)
            return None
        self.health.ok(addon.url, time.monotonic() - started)
        return [s for s in streams if isinstance(s, dict) and (s.get("url") or s.get("infoHash"))]

    def subtitles(self, kind: str, video_id: str, lang: str) -> list[str]:
        """URLs de subtítulos en tu idioma de tus complementos y de OpenSubtitles (si está prendido), por si el video no trae."""
        codes = {lang, LANG_CODES.get(lang, lang)}
        urls = []

        def get(addon: addons.Addon | None) -> list:
            path = f"subtitles/{kind}/{quote(video_id, safe='')}.json"
            try:
                data = self._get_json(addon, path) if addon else addons.fetch_json(f"{subtitle_lib.BUILTIN}/{path}", self.timeout)
            except NET_FAILURES as exc:
                log.info("Sin subtítulos de %s: %s", addon.name if addon else "OpenSubtitles", exc)
                return []
            subs = data.get("subtitles")
            return subs if isinstance(subs, list) else []

        # OpenSubtitles viene con Orbital: el de la lista o el traído de Stremio no se pregunta dos veces.
        ask: list[addons.Addon | None] = [a for a in self.addons() if a.handles("subtitles", kind, video_id) and not is_opensubtitles(a.base)]
        if self.internet_subtitles():
            ask.append(None)
        for addon in ask:
            urls += [s["url"] for s in get(addon) if isinstance(s, dict) and isinstance(s.get("url"), str)
                     and s["url"].startswith(("http://", "https://")) and s.get("lang") in codes]
        return urls

    def subtitle_options(self, kind: str, video_id: str, fingerprint: tuple[str, int] | None = None) -> list[dict] | None:
        """Todos los subtítulos de un video, de tus complementos y de OpenSubtitles (si está prendido en Ajustes › Ver, como el iPhone), con la copia
        para la que se hicieron y sus descargas. Con la huella del archivo, los de tu copia exacta salen primero. None si
        nadie contestó (sin internet): así «no hay» y «sin conexión» no se confunden."""
        # OpenSubtitles viene con Orbital: el de la lista o el traído de Stremio no se pregunta dos veces.
        bases = [(a.base, a.name) for a in self.addons() if a.handles("subtitles", kind, video_id) and not is_opensubtitles(a.base)]
        if self.internet_subtitles():
            bases.append((subtitle_lib.BUILTIN, "OpenSubtitles"))
        extra = f"/videoHash={fingerprint[0]}&videoSize={fingerprint[1]}" if fingerprint else ""

        def ask(base: str, name: str) -> list[dict] | None:
            try:
                data = addons.fetch_json(f"{base}/subtitles/{kind}/{quote(video_id, safe='')}{extra}.json", self.timeout)
            except NET_FAILURES as exc:
                log.info("Sin subtítulos de %s: %s", name, exc)
                return None
            return subtitle_lib.parse_options(data.get("subtitles") or [], "OpenSubtitles" if "opensubtitles" in base else name)

        api = self.opensubtitles if self.internet_subtitles() else None
        with ThreadPoolExecutor(max_workers=max(1, len(bases)) + 1) as pool:
            official = pool.submit(api.search, video_id, fingerprint) if api is not None else None
            answers = list(pool.map(lambda b: ask(*b), bases))
            from_api = (official.result() if official else None) or []
        if all(a is None for a in answers) and not from_api:
            return None
        return opensubtitles.merge(from_api, [o for a in answers if a for o in a])

    def find(self, kind: str, video_id: str, prefs: Preferences) -> list[Source]:
        key = cache_key(kind, video_id, prefs)
        with self._lock:
            hit = self._cache.get(key)
            if hit and time.time() - hit[0] < CACHE_SECONDS:
                return hit[1]
        serving = [a for a in self.addons() if a.handles("stream", kind, video_id)]
        # Un complemento que falló dos veces seguidas no se espera: se vuelve a probar con espera creciente, hasta una
        # hora (si todos están así, se prueban).
        alive = [a for a in serving if not self.health.skip(a.url)] or serving
        skipped = len(alive) < len(serving)
        pool = ThreadPoolExecutor(max_workers=max(1, len(alive)))
        futures = {pool.submit(self._fetch, a, kind, video_id): a for a in alive}
        # Plazo total: un complemento lento no deja al usuario mirando la pantalla de carga 45 s.
        done, late = wait(futures, timeout=FIND_DEADLINE)
        pool.shutdown(wait=False, cancel_futures=True)
        results = []
        for future, addon in futures.items():
            streams = future.result() if future in done else None
            if streams is None:
                self.health.fail(addon.url)
                log.info("%s no respondió a tiempo", addon.name)
            results.append((addon, streams))
        sources, seen = [], set()
        failed = skipped or any(streams is None for _, streams in results)
        try:
            facts = self.facts(kind, video_id) or {}
        except Exception as exc:  # noqa: BLE001 - sin TMDB, las fuentes salen igual (sin el idioma original)
            log.info("Sin datos del título para las fuentes: %s", exc)
            facts = {}
        original = facts.get("original") if isinstance(facts.get("original"), str) else None
        titles = [x for x in facts.get("titles") or [] if isinstance(x, str) and x.strip()]
        years = series_years(facts.get("years")) if kind == "series" else None
        notices = set()
        for addon, streams in results:
            for stream in streams or []:
                if isinstance(stream, dict) and (notice := torrentio_notice(stream)):
                    notices.add(notice)
                    continue
                if isinstance(stream, dict) and not is_link(stream):
                    continue  # un torrent suelto (sin Real-Debrid): ya no se reproduce en la tele (4 nov), como el iPhone
                index = stable_index(addon.url, stream)
                while index in seen:  # el mismo enlace dos veces: la segunda, el número siguiente
                    index = (index + 1) % 2**31
                try:
                    src = parse(stream, addon.name, addon.url, index, original)
                    hints = stream.get("behaviorHints") if isinstance(stream.get("behaviorHints"), dict) else {}
                    filename = str(hints.get("filename") or "")
                    src.other_title = not mentions_title(titles, f"{src.release} {filename}")
                    src.other_series = ":" in video_id and any(names_another_series(titles, name) or other_years(name, years)
                                                               for name in (src.release, filename))
                    if kind == "movie" and isinstance(facts.get("year"), int):
                        src.other_year = other_year(src.release, facts["year"])
                    if (season := season_of(video_id)) is not None:
                        src.other_episode = other_episode(src.release, str(hints.get("filename") or ""), season)
                    if (tracks := self.tracks(src.key)):
                        heard(src, tracks)
                    sources.append(src)
                except PARSE_ERRORS as exc:  # una fuente con datos raros se salta, no tumba la lista
                    log.info("Fuente rara de %s: %s", addon.name, exc)
                    continue
                seen.add(index)
        # El plan B de idiomas sabe cuál es el original de este título (latino → original → inglés → castellano).
        ranked = rank(sources, replace(prefs, original=original or ""), kind)
        # «Sin conexión» solo si nadie contestó: un complemento muerto (ThePirateBay+ ya no existe, «Local Files» apagado)
        # hacía decir «No pude conectar con tus complementos» aunque Torrentio sí respondiera que no lo tiene.
        answered = any(streams is not None for _, streams in results)
        self.outcome[f"{kind}:{video_id}"] = "no-addons" if not serving else "offline" if not answered and not ranked else "ok"
        if notices & ACCOUNT_NOTICES:  # tu Real-Debrid no deja: la ficha le pregunta a Real-Debrid cuál de las tres causas
            self.outcome[f"{kind}:{video_id}"] = "debrid-account"
        if failed and not ranked:
            return ranked  # la red falló y no hay nada: no se recuerda, la próxima vez se pregunta otra vez
        with self._lock:
            if len(self._cache) >= CACHE_MAX:  # una entrada por episodio visto: se van las más viejas
                for old in sorted(self._cache, key=lambda k: self._cache[k][0])[:CACHE_MAX // 2]:
                    del self._cache[old]
            # Si algún complemento no respondió (Wi-Fi al despertar), la lista se recuerda solo unos segundos.
            stamp = time.time() - (CACHE_SECONDS - RETRY_FAILED if failed else 0)
            self._cache[key] = (stamp, ranked)
        return ranked

    def cached(self, kind: str, video_id: str, prefs: Preferences) -> list[Source]:
        """Las que ya se buscaron (sin ir a internet): para el reproductor, que no puede esperar. Si se buscaron con
        otras preferencias (acabas de elegir latino), sirven igual: los números de fuente no cambian."""
        hit = self._cache.get(cache_key(kind, video_id, prefs))
        if hit and time.time() - hit[0] < CACHE_SECONDS:
            return hit[1]
        fresh = [v for k, v in list(self._cache.items())
                 if k.startswith(f"{kind}:{video_id}:") and time.time() - v[0] < CACHE_SECONDS]
        other = max(fresh, key=lambda v: v[0], default=None)
        # Ordenadas para estas preferencias sin tocar su `score` (la otra lista las comparte).
        return sorted(other[1], key=lambda s: score(s, prefs, kind), reverse=True) if other else []

    def forget(self, kind: str, video_id: str) -> None:
        """Se aprendió algo de una fuente (sus pistas): la próxima búsqueda la vuelve a clasificar."""
        with self._lock:
            for key in [k for k in self._cache if k.startswith(f"{kind}:{video_id}:")]:
                del self._cache[key]

    def forget_all(self) -> None:
        """Cambiaron tus complementos o sus opciones (Torrentio): la próxima búsqueda pregunta de nuevo."""
        with self._lock:
            self._cache.clear()
        self.outcome.clear()

    def get(self, kind: str, video_id: str, prefs: Preferences, index: int) -> Source | None:
        found = self.cached(kind, video_id, prefs)
        if not found:
            return None  # caducó (los enlaces de Real-Debrid vencen): quien llama busca otra vez
        return next((s for s in found if s.index == index), None)
