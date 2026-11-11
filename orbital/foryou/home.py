"""El mosaico, «¿Qué vemos hoy?», el mazo de match y el filtro avanzado.
"""

from __future__ import annotations

import json
import logging
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import date, datetime

from .. import decide as decide_api
from ..library import tmdb as tmdb_api
from .base import (
    JW_LIST_BRANDS,
    MINE_TTL,
    MOSAIC_SIZE,
    PER_SOURCE,
    PREFETCH_DELAY,
    RECS_TTL,
    SERVICE_ERRORS,
    SLOW_TTL,
    TRAKT_ADDON,
)
from .items import series_only
from .shelves import _Shelves

log = logging.getLogger("orbital.foryou")  # el mismo nombre de siempre: la bitácora no cambia


class _Home(_Shelves):
    """El mosaico, «¿Qué vemos hoy?», el mazo de match y el filtro avanzado."""

    # --- el mosaico ----------------------------------------------------------------------------
    def mosaic(self) -> list[dict]:
        """El mosaico de la caché (vencido o no, se renueva solo); solo la primera vez se espera a armarlo."""
        hidden = self.catalog.state.dismissed()
        # series_only también aquí: lo guardado antes de la regla no espera a que se vuelva a armar.
        return [self._with_art(series_only(i)) for i in self.cache.get("mosaic", MINE_TTL, self._build_mosaic, stale=True)
                if i["key"] not in hidden]

    def warm(self) -> None:
        """Al arrancar Orbital, arma el mosaico y las listas con puesto en segundo plano: la primera vez que la TV o el
        iPhone abren Para ti ya está (antes esperaban el Top 10 de Netflix, unos 30 s). Y sus primeros pósters y logos,
        ya bajados y reducidos: la primera vez que se veía el mosaico, cada imagen se bajaba en ese momento."""
        def run() -> None:
            items = self._safe(self.mosaic) or []
            # Las imágenes, con calma: al arrancar Orbital ya escanea la biblioteca y el arte, y todo junto hacía que la
            # interfaz tardara segundos en contestar.
            time.sleep(PREFETCH_DELAY)
            self._safe(lambda: self.prefetch_art(items))

        threading.Thread(target=run, daemon=True, name="foryou-warm").start()

    def prefetch_art(self, items: list[dict], limit: int = 60) -> int:
        """Baja y reduce los pósters (al ancho del mosaico) y los logos de las primeras piezas. Devuelve cuántas."""
        from .. import remote_art

        def one(item: dict) -> bool:
            ok = False
            url = item.get("image")
            if isinstance(url, str) and remote_art.allowed(url):
                ok = remote_art.sized(self.poster_source(url), 360) is not None  # POSTER_PX del mosaico (foryou-mosaic.js)
            imdb = item.get("meta_id")
            if isinstance(imdb, str) and str(item.get("logo") or "").startswith("https://images.metahub.space/logo/"):
                self.trimmed_logo(imdb)
            return ok

        with ThreadPoolExecutor(max_workers=2) as pool:
            return sum(pool.map(one, items[:limit]))

    def _build_mosaic(self) -> list[dict]:
        """Lo tuyo, mezclado: tus recomendaciones, tu watchlist, tus listas, tus series y tus juegos.
        Sin Trakt conectado: lo que dejaste a medias y tu lista de Stremio, más lo que está en
        tendencia (o lo popular en tus plataformas, o en el catálogo de Stremio si no hay claves)."""
        sources: list[tuple[str, str | None]] = []
        if self.trakt.linked:
            sources = [("recs", "series"), ("recs", "movie"), ("watchlist", None), ("mine", None)]
            try:
                sources += [(f"list:{r['id']}", None) for r in self.cache.get("trakt:lists", MINE_TTL, self.trakt.lists, stale=True)[:3]]
            except SERVICE_ERRORS:
                pass
        else:
            sources = [("continue", None), ("mylist", None)]
            sources += [(a["id"], kind) for a in self.addon_catalogs() if a["addon"].lower() == TRAKT_ADDON
                        and a["title"] in ("Watchlist", "Recommendations") for kind in a["kinds"]]
            if self.trakt.configured:
                sources += [("trend", "series"), ("trend", "movie")]
            elif self.platforms():
                sources += [(brand, kind) for brand in self.platforms() for kind in ("series", "movie")]
            else:
                sources += [("cinemeta", "series"), ("cinemeta", "movie")]
        # El Top 10 de Netflix y lo más visto por plataforma: no dependen de Trakt ni de ninguna clave.
        sources += [("chart:netflix", "movie"), ("chart:netflix", "series")]
        sources += [(f"jw:{brand}", kind) for brand in JW_LIST_BRANDS for kind in ("movie", "series")]

        def fetch(source):
            try:
                return self.list_items(*source)[:PER_SOURCE]
            except (KeyError, *SERVICE_ERRORS) as exc:
                log.warning("Para ti: %s no respondió: %s", source[0], exc)
                return []

        with ThreadPoolExecutor(max_workers=4) as pool:
            batches = list(pool.map(fetch, sources))
        videos = self._interleave(batches)
        # El mosaico es de imágenes: sin arte, no entra. Y lleva más «Al azar» que la lista (hay lugar).
        games = [g for g in self.local_games(lucky=24) if not g["placeholder"]]
        mixed, seen = [], set()
        # Tres videos por cada dos juegos, más o menos (lo que haya de cada uno).
        vi = gi = 0
        while len(mixed) < MOSAIC_SIZE and (vi < len(videos) or gi < len(games)):
            for _ in range(3):
                if vi < len(videos):
                    mixed.append(videos[vi])
                    vi += 1
            for _ in range(2):
                if gi < len(games):
                    mixed.append(games[gi])
                    gi += 1
        out = []
        for item in mixed:
            if item["key"] not in seen:
                seen.add(item["key"])
                out.append(series_only(item))
        return out[:MOSAIC_SIZE]

    def overview(self) -> dict:
        return {"status": self.status(), "lists": self.lists(), "mosaic": self.mosaic()}

    # --- ¿Qué vemos? (como el iPhone) -------------------------------------------------------------
    def _decide_pool(self) -> list[dict]:
        """De dónde salen las propuestas: el mosaico, tus recomendaciones, tu watchlist y lo que es tendencia."""
        pool = [i for i in self.mosaic() if i.get("meta_id")]
        for list_id in ("recs", "watchlist", "trend"):
            try:
                pool += self.list_items(list_id)
            except (KeyError, *SERVICE_ERRORS):
                continue
        hidden = self.catalog.state.dismissed()
        return [i for i in pool if i.get("key") not in hidden]

    def _decide_details(self, items: list[dict]) -> dict[str, dict]:
        """Género, duración y calificación de lo que no los trae (Cinemeta, varios a la vez; se recuerda un día)."""
        def one(item: dict) -> tuple[str, dict]:
            imdb, kind = item["meta_id"], item["kind"]

            def load() -> dict:
                try:
                    meta = self.catalog.cinemeta.meta(kind, imdb, localized=False)
                except Exception:  # noqa: BLE001 - sin datos, se decide con lo que hay
                    return {}
                rating = meta.get("imdbRating")
                try:
                    score = float(rating) if rating not in (None, "") else None
                except (TypeError, ValueError):
                    score = None
                return {"genres": list(meta.get("genres") or meta.get("genre") or []),
                        "minutes": decide_api.runtime_minutes(meta.get("runtime")), "rating": score}
            return imdb, self.cache.get(f"decide:{imdb}", SLOW_TTL, load) or {}

        with ThreadPoolExecutor(max_workers=12) as pool:
            return dict(pool.map(one, items[:60]))

    def decide(self, time_choice: str | None = None, mood: str | None = None, kind: str | None = None,
               genres: list[str] | None = None, include_watched: bool = False, now: datetime | None = None) -> dict:
        """Tres propuestas (la primera es la elegida) con su porqué: duración y calificación de IMDb."""
        now = now or datetime.now().astimezone()
        time_choice = time_choice if time_choice in decide_api.TIMES else decide_api.context_time(now)
        mood = mood if mood in decide_api.MOODS else None
        kind = kind if kind in ("movie", "series") else None
        stamp = now.timestamp()
        exclude = self.catalog.state.skipped(decide_api.SKIP_HOURS * 3600, now=stamp)
        if not include_watched:
            exclude |= set(self.watched_ids())
        pool = self._decide_pool()
        details: dict[str, dict] = {}
        if mood or genres or time_choice != "long":
            missing = [i for i in pool if i.get("meta_id") not in exclude and (not i.get("genres") or not i.get("runtime"))]
            details = self._decide_details(missing)
        picks = decide_api.choose(pool, time=time_choice, mood=mood, kind=kind, genres=set(genres or ()), exclude=exclude,
                                  details=details)
        details.update(self._decide_details([p for p in picks if p["meta_id"] not in details]))
        out = []
        for p in picks:
            d = details.get(p["meta_id"], {})
            minutes = p.get("runtime") or d.get("minutes")
            out.append({**p, "minutes": minutes, "imdb_rating": d.get("rating"), "genres": p.get("genres") or d.get("genres") or [],
                        "fits": decide_api.fits(minutes, time_choice)})  # ¿cabe en el tiempo? (si no, es de las más cortas)
        return {"time": time_choice, "mood": mood, "kind": kind, "picks": out}

    def match_deck(self, mood: str | None = None, now: float | None = None) -> list[dict]:
        """«¿Qué vemos hoy?» (como el iPhone): tus propuestas sin repetir y sin lo que ya viste, del ánimo elegido, en un orden
        revuelto que cambia cada día (el mismo que el iPhone). Lo que descartas lo recuerda la interfaz (un mes)."""
        mood = mood if mood in decide_api.MOODS else None
        watched = set(self.watched_ids())
        seen: set[str] = set()
        pool = [i for i in self._decide_pool() if i.get("meta_id") and i["meta_id"] not in watched
                and not (i["meta_id"] in seen or seen.add(i["meta_id"]))]
        if mood:
            details = self._decide_details([i for i in pool if not i.get("genres")])
            pool = [{**i, "genres": i.get("genres") or details.get(i["meta_id"], {}).get("genres") or []} for i in pool]
            pool = [i for i in pool if decide_api.matches(i["genres"], mood, set())]
        day = int((now if now is not None else time.time()) // 86400)
        return sorted(pool, key=lambda i: decide_api.fnv_order(day, i["meta_id"]))

    # --- Filtro avanzado (como el del iPhone, ola 3) ------------------------------------------------------------------
    FILTER_COUNTRIES = ("MX", "US", "GB", "KR", "JP", "ES", "FR")

    FILTER_DECADES = ("2020", "2010", "2000", "1990", "1980", "old")

    def filter_params(self, kind: str, f: dict) -> dict | None:
        """Lo que pide TMDB para un filtro: {género, década, calificación, fama, plataforma, país}. None si no puede haber
        nada (un género que no existe en series, una plataforma que no está en tu país)."""
        params: dict = {"sort_by": "popularity.desc"}
        genre = tmdb_api.GENRE_BY_SLUG.get(f.get("genre") or "")
        if genre:
            gid = genre.tv if kind == "series" else genre.movie
            if not gid:
                return None
            params["with_genres"] = gid
        date_field = "first_air_date" if kind == "series" else "primary_release_date"
        decade = f.get("decade")
        if decade == "old":
            params[f"{date_field}.lte"] = "1979-12-31"
        elif decade in self.FILTER_DECADES:
            params[f"{date_field}.gte"], params[f"{date_field}.lte"] = f"{decade}-01-01", f"{int(decade) + 9}-12-31"
        rating = f.get("rating")
        if rating in ("6", "7", "8"):
            params["vote_average.gte"], params["vote_count.gte"] = int(rating), 50
        fame = f.get("fame")
        if fame == "known":
            params["vote_count.gte"] = max(params.get("vote_count.gte", 0), 1000)
        elif fame == "hidden":
            params["vote_count.gte"], params["vote_count.lte"] = max(params.get("vote_count.gte", 0), 100), 1000
        platform = f.get("platform")
        if platform:
            found = self.platforms().get(platform)
            if not found:
                return None
            params.update(with_watch_providers=found["id"], watch_region=self.region,
                          with_watch_monetization_types="flatrate|free|ads")  # también lo gratis (ViX, Pluto TV), como el iPhone
        country = f.get("country")
        if country in self.FILTER_COUNTRIES:
            params["with_origin_country"] = country
        # Como el iPhone: nunca lo que aún no se estrena, sin relleno de TV (noticieros, realities, telenovelas, entrevistas;
        # lo infantil salvo Familia o Animación) y con un piso de votos para que no salgan rarezas de moda en otro país
        # (más bajo de un país donde se vota poco).
        params.setdefault(f"{date_field}.lte", date.today().isoformat())
        if params[f"{date_field}.lte"] > date.today().isoformat():
            params[f"{date_field}.lte"] = date.today().isoformat()
        if kind == "series":
            filler = [10763, 10764, 10766, 10767] + ([] if f.get("genre") in ("familia", "animacion") else [10762])
            params["without_genres"] = ",".join(str(g) for g in sorted(filler))
        floor = (50 if kind == "series" else 100) // (5 if country and country not in ("US", "GB") else 1)
        params["vote_count.gte"] = max(params.get("vote_count.gte", 0), floor) if fame != "hidden" else params["vote_count.gte"]
        return params

    def filtered(self, kind: str, f: dict, count_only: bool = False) -> dict:
        """El filtro avanzado: {total, items} (sin items si solo cuenta). Sin clave de TMDB: TmdbError en palabras."""
        if not self.tmdb.configured:
            raise tmdb_api.TmdbError("El filtro avanzado usa TMDB: agrega su clave en Ajustes › Cuentas.")
        kind = "series" if kind == "series" else "movie"
        params = self.filter_params(kind, f)
        if params is None:
            return {"total": 0, "items": []}
        key = "filter:" + kind + ":" + json.dumps(params, sort_keys=True)
        rows, total = self.cache.get(key, RECS_TTL, lambda: self.tmdb.discover_page(kind, **params))
        if count_only:
            return {"total": total}
        return {"total": total, "items": self._tmdb_items(rows, kind, "Con tu filtro", limit=20)}
