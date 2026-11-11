"""De dónde salen las listas: Trakt, TMDB, RAWG, Top 10, JustWatch, tus complementos, Letterboxd y MDBList.
"""

from __future__ import annotations

import logging
import re
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from datetime import date, datetime, timedelta

from ..library import letterboxd as letterboxd_api
from ..library import mdblist as mdblist_api
from ..library import stremio_api
from ..library import tmdb as tmdb_api
from ..net import NET_FAILURES, read_json, request, urlopen
from .base import (
    CANON,
    CANON_TTL,
    FRESH_BRANDS,
    FRESH_MOVIE_DAYS,
    FRESH_SERIES_DAYS,
    GAME_CATEGORIES,
    GENERIC_CATALOGS,
    JW_LIST_BRANDS,
    MINE_TTL,
    RECS_TTL,
    SERVICE_ERRORS,
    SKIP_ADDONS,
    SLOW_TTL,
    STEAM_ART,
    TRAKT_ADDON,
    load_awards,
)
from .cache import _mark_partial
from .items import fold, library_entry, video_item
from .mine import _Mine

log = logging.getLogger("orbital.foryou")  # el mismo nombre de siempre: la bitácora no cambia


class _Sources(_Mine):
    """De dónde salen las listas: Trakt, TMDB, RAWG, Top 10, JustWatch, tus complementos, Letterboxd y MDBList."""

    def platforms(self) -> dict[str, dict]:
        if not self.tmdb.configured:
            return {}
        try:
            return self.cache.get("tmdb:platforms", SLOW_TTL, lambda: self.tmdb.platforms(self.region), stale=True)
        except SERVICE_ERRORS as exc:
            log.warning("Para ti: no pude leer las plataformas de TMDB: %s", exc)
            return {}

    # --- tus complementos de Stremio -----------------------------------------------------------
    def addon_catalogs(self) -> list[dict]:
        """Los catálogos de tus complementos que agregan algo: uno por nombre, con sus tipos (series y películas) y de qué
        complemento salen. Salen de tu lista de Orbital (Ajustes › Complementos), nunca de tu cuenta de Stremio (4 nov)."""
        registry = getattr(getattr(self.catalog, "watch", None), "addons", None)
        if registry is None:
            return []
        addons = self._listed(registry.known())
        covered = {fold(name) for name, _ in tmdb_api.PLATFORMS.values()} if self.platforms() else set()
        found: dict[str, dict] = {}
        for addon in addons:
            name = addon["name"]
            if any(word in name.lower() for word in SKIP_ADDONS):
                continue
            if name.lower() == TRAKT_ADDON and self.trakt.linked:
                continue  # Trakt conectado: esas listas ya llegan de Trakt
            for cat in addon["catalogs"]:
                title = cat["name"].removeprefix("Trakt ").strip() if name.lower() == TRAKT_ADDON else cat["name"]
                if cat["type"] not in ("movie", "series") or cat["name"].lower() in GENERIC_CATALOGS or fold(title) in covered:
                    continue
                key = f"addon:{fold(name)}:{cat['id']}"
                entry = found.setdefault(key, {"id": key, "title": title, "addon": name, "base": addon["base"],
                                               "catalog": cat["id"], "kinds": []})
                entry["kinds"].append(cat["type"])
        return list(found.values())

    @staticmethod
    def _listed(found) -> list[dict]:
        """Los catálogos que se pueden pedir sin datos extra, de los complementos ya leídos (library/addons.Addon)."""
        addons = []
        for addon in found:
            catalogs = [c for c in addon.catalogs if c.get("id") and c.get("name")
                        and not any(isinstance(e, dict) and e.get("isRequired") for e in c.get("extra") or [])]
            if catalogs and addon.url.startswith("https://"):
                addons.append({"name": addon.name, "base": addon.base,
                               "catalogs": [{"id": str(c["id"]), "name": str(c["name"]), "type": c.get("type")} for c in catalogs]})
        return addons

    def _addon_list(self, entry: dict, kind: str) -> list[dict]:
        kind = kind if kind in entry["kinds"] else entry["kinds"][0]
        url = f"{entry['base']}/catalog/{kind}/{urllib.parse.quote(entry['catalog'], safe='')}.json"
        try:
            with urlopen(request(url, headers={"User-Agent": "Orbital"}), timeout=12) as res:
                data = read_json(res, timeout=12)
        except NET_FAILURES as exc:  # sin red, o algo que no es JSON (BadResponse)
            raise stremio_api.StremioError(f"{entry['addon']} no respondió: {exc}") from exc
        metas = data.get("metas") if isinstance(data, dict) else None
        why = {"Watchlist": "En Mi lista", "Recommendations": "Recomendada"}.get(entry["title"], f"En {entry['title']}")
        named = entry["title"] not in ("Watchlist", "Recommendations")  # «En RT: Certified Fresh»: el nombre de una lista
        items = []
        for m in metas if isinstance(metas, list) else []:
            if not isinstance(m, dict) or not re.fullmatch(r"tt\d+", str(m.get("id") or "")) or not isinstance(m.get("name"), str):
                continue
            year = re.match(r"\d{4}", str(m.get("releaseInfo") or m.get("year") or ""))
            e = {"imdb": m["id"], "kind": kind, "title": m["name"], "year": int(year.group()) if year else None}
            items.append(video_item(e, why, wide=m.get("background") if isinstance(m.get("background"), str) else None,
                                    overview=str(m.get("description") or "")[:600], in_list=named))
        return items[:60]

    def _letterboxd_lists(self) -> list[dict]:
        """Tus listas de Letterboxd (las públicas). Letterboxd a veces cierra esa página a las aplicaciones: entonces, ninguna."""
        if not self.letterboxd.configured:
            return []
        try:
            return self.cache.get("letterboxd:lists", MINE_TTL, self.letterboxd.lists, stale=True)
        except (letterboxd_api.LetterboxdError, *SERVICE_ERRORS) as exc:
            log.info("Para ti: no pude leer tus listas de Letterboxd: %s", exc)
            return []

    def _letterboxd_list(self, slug: str) -> list[dict]:
        """Las películas de una de tus listas de Letterboxd, con su IMDb (cada película se resuelve una vez y se recuerda)."""
        films = self.cache.get(f"letterboxd:list:{slug}", MINE_TTL, lambda: self.letterboxd.list_films(slug))

        def one(f: dict) -> dict | None:
            try:
                found = self.cache.get(f"letterboxd:film:{f['slug']}", 30 * SLOW_TTL, lambda: self.letterboxd.resolve(f["slug"]) or {})
            except (letterboxd_api.LetterboxdError, *SERVICE_ERRORS):
                return None
            return {"imdb": found["imdb"], "kind": found.get("kind") or "movie", "title": f["title"], "year": f.get("year")} if found.get("imdb") else None

        with ThreadPoolExecutor(max_workers=4) as pool:
            return [e for e in pool.map(one, films[:200]) if e]

    def _recent_seeds(self) -> list[dict]:
        """Tus últimos cinco títulos distintos (Trakt), para «Porque viste X»."""
        try:
            return self.cache.get("trakt:recent", MINE_TTL, self.trakt.recent_watched, stale=True)
        except SERVICE_ERRORS as exc:
            log.info("Para ti: no pude leer lo último que viste: %s", exc)
            return []

    ROTATION = 5  # la semilla del día rota entre los primeros cinco (becauseRotation del iPhone)

    def _related(self, seed: dict) -> list[dict]:
        """Lo que Trakt relaciona con esa semilla (15, en su orden; sin ella misma)."""
        try:
            found = self.cache.get(f"trakt:related:{seed['imdb']}", RECS_TTL, lambda: self.trakt.related(seed["kind"], seed["imdb"], 15))
        except SERVICE_ERRORS as exc:
            log.info("Para ti: no pude leer lo relacionado con %s: %s", seed.get("title"), exc)
            return []
        return [e for e in found if e.get("imdb") != seed.get("imdb")]

    def _seed_of_day(self, seeds: list[dict], today: date | None = None) -> dict | None:
        """El de hoy: uno distinto cada día entre los primeros cinco (día % 5, como el iPhone). Si ese no tiene
        relacionados, el siguiente."""
        if not seeds:
            return None
        span = min(self.ROTATION, len(seeds))
        start = (today or date.today()).toordinal() % span
        order = [seeds[(start + i) % span] for i in range(span)] + seeds[span:]
        return next((s for s in order if self._related(s)), order[0])

    def _critics_refs(self) -> dict[str, tuple[str, str]]:
        """Las listas de «Aprobadas por la crítica» por tipo: {"movie": ("mdblist", "usuario/lista"), …}."""
        refs = {}
        for kind, ref in (("movie", self.settings.critics_movies), ("series", self.settings.critics_series)):
            service, _, name = str(ref or "").partition(":")
            if service in ("mdblist", "trakt") and mdblist_api.parse_ref(name):
                refs[kind] = (service, name)
        return refs

    def _critics(self, kind: str) -> list[dict]:
        """Las películas Certified Fresh recientes o las series Fresh (Rotten Tomatoes), un día en caché."""
        refs = self._critics_refs()
        ref = refs.get(kind) or (next(iter(refs.values())) if len(refs) == 1 else None)
        if ref is None:
            return []
        service, name = ref

        def load() -> list[dict]:
            if service == "trakt":
                user, slug = mdblist_api.parse_ref(name) or ("", "")
                return self.trakt.public_list_items(user, slug)
            return self.mdblist.list_items(name)

        entries = self.cache.get(f"critics:{service}:{name}", SLOW_TTL, load, stale=True)
        why = "Certified Fresh" if kind == "movie" else "Fresh en Rotten Tomatoes"
        # La lista de MDBList trae estrenos que aún no salen (The Batman: Part II, Dune: Part Three): esos no son «aprobados».
        # Lo de años que vienen, por su año; lo de este año, por su fecha exacta en Cinemeta (como el iPhone). Sin fecha, se queda.
        this_year = datetime.now().year
        return [video_item(e, why, in_list=True) for e in entries or []
                if (e.get("year") or this_year) <= this_year and not (e.get("year") == this_year and self._not_out_yet(e))]

    def _not_out_yet(self, entry: dict) -> bool:
        """¿Su fecha de estreno (Cinemeta) es después de hoy? Se recuerda un día."""
        imdb = entry.get("imdb") or ""

        def load() -> str:
            try:
                return str(self.catalog.cinemeta.meta("movie", imdb, localized=False).get("released") or "")
            except Exception:  # noqa: BLE001 - sin fecha, se queda
                return ""
        released = self.cache.get(f"released:{imdb}", SLOW_TTL, load) if imdb.startswith("tt") else ""
        return bool(released) and released[:10] > datetime.now().date().isoformat()

    def _stremio(self, which: str, kind: str | None = None) -> list:
        """Lo que Orbital ya trajo de Stremio: «continue» (Seguir viendo), «mylist» (Mi lista) o
        «cinemeta» (lo popular de su catálogo público). Solo títulos con id de IMDb."""
        if which == "cinemeta":
            found = [i for i in self.catalog.items() if i.source == "cinemeta"]
        else:
            mine = sorted((i for i in self.catalog.items() if i.source == "stremio"),
                          key=lambda i: i.last_watched or 0, reverse=True)
            found = [i for i in mine if (i.category == "continue") == (which == "continue")
                     and (which == "continue" or i.extra.get("in_library"))]
        return [(i, e) for i in found if (e := library_entry(i)) and (kind is None or e["kind"] == kind)]

    def _platform(self, brand: str, kind: str) -> list[dict]:
        platform = self.platforms().get(brand)
        if not platform:
            return []
        rows = self.tmdb.discover(kind, platform["id"], self.region)[:20]
        with ThreadPoolExecutor(max_workers=6) as pool:
            details = list(pool.map(lambda r: self._safe(lambda: self.tmdb.details(kind, r["id"])), rows))
        _mark_partial(len(details), sum(1 for d in details if d is None))
        name = tmdb_api.PLATFORMS[brand][0]
        return [video_item(d, f"En {name}", title=d["title"], poster=d["poster"], wide=d["backdrop"],
                           overview=d["overview"], seasons=d.get("seasons"))
                for d in details if d and d.get("imdb") and d.get("title")]

    def _tmdb_items(self, rows: list[dict], kind: str, why: str, limit: int = 20) -> list[dict]:
        """Filas de TMDB (discover) → video_item con su IMDb (la ficha y el reproductor lo necesitan)."""
        with ThreadPoolExecutor(max_workers=6) as pool:
            details = list(pool.map(lambda r: self._safe(lambda: self.tmdb.details(kind, r["id"])), rows[:limit]))
        _mark_partial(len(details), sum(1 for d in details if d is None))
        return [video_item(d, why, title=d["title"], poster=d["poster"], wide=d["backdrop"], overview=d["overview"],
                           seasons=d.get("seasons"))
                for d in details if d and d.get("imdb") and d.get("title")]

    def _fresh(self, kind: str) -> list[dict]:
        """«Nuevo en tus plataformas»: lo nuevo de Netflix, Disney+ y HBO Max, alternados (como el iPhone)."""
        found = self.platforms()
        today = date.today()
        batches = []
        for brand in FRESH_BRANDS:
            platform = found.get(brand)
            if not platform:
                continue
            rows = self._safe(lambda platform=platform: self.tmdb.fresh(
                kind, platform["id"], self.region, today.isoformat(), (today - timedelta(days=FRESH_SERIES_DAYS)).isoformat(),
                (today - timedelta(days=FRESH_MOVIE_DAYS)).isoformat())) or []
            name = tmdb_api.PLATFORMS[brand][0]
            batches.append([{**i, "brand": brand} for i in self._tmdb_items(rows, kind, f"Nuevo en {name}", limit=8)])
        return self._interleave(batches)

    def _studio(self, company_id: int, name: str) -> list[dict]:
        return self._tmdb_items(self.tmdb.studio(company_id), "movie", name)

    def _genre_heading(self, name: str, asked: int, used: int, basis: str) -> tuple[str, str]:
        """El título de la pantalla dice el año de verdad; el renglón de abajo dice si no alcanzó la nota."""
        title = f"Lo mejor de {name} en {used}"
        if basis == "votes":
            return title, "Las mejor calificadas del año"
        if basis == "popular":
            return title, f"Las más populares de {used}"
        if basis == "previous":
            return title, f"Pocas de {asked}: las mejor calificadas de {used}"
        return title, f"Pocas de {asked}: lo más visto en {used}"

    def _genre_bundle(self, slug: str, year: int) -> dict:
        spec = tmdb_api.GENRE_BY_SLUG[slug]
        chart = self.tmdb.genre_top(spec.movie, spec.tv, year)
        title, meta = self._genre_heading(spec.title, year, int(chart["year"]), str(chart["basis"]))
        return {"items": self._from_tmdb_rows(chart["rows"], spec.title, ranked=True), "title": title, "meta": meta}

    def _season_bundle(self, slug: str) -> dict:
        spec = tmdb_api.SEASON_BY_SLUG[slug]
        keyword = self.cache.get(f"tmdb:keyword:{slug}", SLOW_TTL, lambda: self.tmdb.keyword_id(spec.queries))
        rows = self.tmdb.season_titles(int(keyword)) if keyword else []
        return {"items": self._from_tmdb_rows(rows, spec.title, limit=20), "title": spec.title, "meta": spec.blurb}

    def _from_tmdb_rows(self, rows: list[dict], why: str, *, limit: int = 10, ranked: bool = False) -> list[dict]:
        """Filas de discover ({kind, id}) → video_item con IMDb. Un Top pone el puesto 1…n."""
        picked = [r for r in rows if r.get("kind") in ("movie", "series") and isinstance(r.get("id"), int)][:20]

        failed: list[int] = []

        def one(row: dict) -> dict | None:
            detail = self._safe(lambda: self.tmdb.details(row["kind"], int(row["id"])))
            if detail is None:
                failed.append(1)
            if not detail or not detail.get("imdb") or not detail.get("title"):
                return None
            return video_item(detail, why, title=detail["title"], poster=detail.get("poster"), wide=detail.get("backdrop"),
                              overview=detail.get("overview"), seasons=detail.get("seasons"))

        with ThreadPoolExecutor(max_workers=6) as pool:
            items = [item for item in pool.map(one, picked) if item][:limit]
        _mark_partial(len(picked), len(failed))
        if ranked:
            for n, item in enumerate(items, start=1):
                item["rank"] = n
                item["why"] = f"N.º {n} · {why}"
        return items

    def _year(self, year: int, kind: str) -> list[dict]:
        """Lo más popular de un año en Trakt; en películas, primero las premiadas de ese año (como los pósters del iPhone)."""
        items: list[dict] = []
        if kind == "movie":
            for a in load_awards():
                for w in a["winners"]:
                    if a["kind"] == "movie" and w.get("year") == year and all(i["meta_id"] != w["imdb"] for i in items):
                        items.append(video_item({"imdb": w["imdb"], "kind": "movie", "title": w["title"], "year": year},
                                                f"{a['title']} {w['award_year']}"))
        popular = self.trakt.popular(kind, limit=60, years=year)
        return items + [video_item(e, f"Popular en {year}") for e in popular if all(i["meta_id"] != e["imdb"] for i in items)]

    def _chart_item(self, entry: dict, kind: str, platform_name: str) -> dict:
        """Un título de Netflix (Top 10) o JustWatch (tendencia) en forma de video_item: «N.º 3 en Netflix», con `rank`,
        `movement` (+2 subió dos, −1 bajó uno, 0 igual, None sin con qué comparar) y `new` (entró esta semana / hoy)."""
        e = {"imdb": entry["imdb"], "kind": kind, "title": entry["title"], "year": entry.get("year")}
        item = video_item(e, f"N.º {entry['rank']} en {platform_name}", title=entry["title"])
        item["rank"] = entry["rank"]
        item["movement"] = entry.get("movement")
        item["new"] = bool(entry.get("new"))
        if entry.get("weeks"):
            item["weeks"] = entry["weeks"]  # semanas en el Top 10 de Netflix (para la ficha)
        return item

    def _netflix_meta(self) -> str:
        """«México · semana del 28 de sep» si el Top 10 ya se trajo (el archivo es grande: no se pide solo para esto)."""
        for kind in ("series", "movie"):
            cached = self.cache.peek(f"charts:netflix:{kind}") or []
            week = next((e.get("week") for e in cached if e.get("week")), None)
            if week:
                try:
                    start = date.fromisoformat(week) - timedelta(days=6)  # la semana de Netflix termina en domingo
                except ValueError:
                    break
                months = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"]
                return f"{self._country()} · semana del {start.day} de {months[start.month - 1]}"
        return f"Esta semana en {self._country()}"

    @staticmethod
    def _ranked_list(brand: str) -> str | None:
        """La lista con puesto de una plataforma: el Top 10 de Netflix o la de JustWatch (None si no tiene)."""
        return "chart:netflix" if brand == "netflix" else f"jw:{brand}" if brand in JW_LIST_BRANDS else None

    def _rawg(self, which: str) -> list[dict]:
        games = self.rawg.games(which)
        with ThreadPoolExecutor(max_workers=6) as pool:
            appids = list(pool.map(lambda g: self._safe(lambda: self.rawg.steam_appid(g["rawg_id"])), games))
        why = {"new": "Novedad", "popular": "Popular", "best": "Mejor calificado"}[which]
        found = []
        for g, appid in zip(games, appids, strict=True):
            art = (lambda f, a=appid: STEAM_ART.format(appid=a, file=f)) if appid else None
            found.append({
                "key": f"rawg:{g['rawg_id']}", "kind": "game", "rawg_id": g["rawg_id"], "steam_appid": appid,
                "title": g["title"], "year": g["year"], "why": why, "system": "steam" if appid else "pc",
                "detail": f"Metacritic {g['metacritic']}" if g["metacritic"] else (str(g["year"]) if g["year"] else ""),
                "facts": [[k, str(v)] for k, v in (["Salió", g["year"]], ["Metacritic", g["metacritic"]]) if v],
                "image": art("library_600x900.jpg") if art else g["image"], "image_fallback": g["image"],
                "hero": g["image"] or (art("library_hero.jpg") if art else None),
                "logo": art("logo.png") if art else None, "wide": art("capsule_616x353.jpg") if art else None,
                "overview": "", "owned": False, "action": None,
            })
        return found

    def _mark_owned(self, games: list[dict]) -> list[dict]:
        """Lo que ya tienes (por id de Steam o por nombre) se juega desde aquí: palomita y A = Jugar."""
        library = [i for i in self.catalog.items() if i.category in GAME_CATEGORIES]
        by_appid = {i.steam_appid: i for i in library if i.steam_appid}
        by_title = {fold(i.title): i for i in library}
        marked = []
        for g in games:
            mine = by_appid.get(g.get("steam_appid")) or by_title.get(fold(g["title"]))
            if mine:
                g = {**g, "owned": True, "id": mine.id, "item": self.catalog.describe(mine), "action": "Jugar"}
            marked.append(g)
        return marked

    # --- Colecciones (como la repisa del iPhone) --------------------------------------------------------------------
    def _canon(self, canon_id: str) -> list[dict]:
        """Los títulos de una lista famosa, en su orden (una semana guardada). KeyError si no existe."""
        found = next((c for c in CANON if c[0] == canon_id), None)
        if found is None:
            raise KeyError(canon_id)
        _, _, ref, total = found
        if ref:
            return self.cache.get(f"canon:{canon_id}", CANON_TTL, lambda: self.mdblist.list_items(ref, limit=total))

        def mine() -> list[dict]:  # la tuya de Trakt, por su nombre (como el iPhone: «York» o «NYT», y de películas)
            if not self.trakt.linked:
                return []

            def fits(name: str) -> bool:
                low = name.casefold()
                return any(w in low for w in ("york", "nyt")) and not any(w in low for w in ("tv", "serie", "show"))

            row = next((r for r in self.trakt.lists() if fits(r["name"])), None)
            return [e for e in self.trakt.list_items(row["id"]) if e.get("kind") == "movie"] if row else []

        return self.cache.get(f"canon:{canon_id}", CANON_TTL, mine)
