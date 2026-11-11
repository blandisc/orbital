"""Los estantes: qué listas hay, su encabezado y lo que trae cada una.
"""

from __future__ import annotations

import logging
from datetime import datetime

from ..library import charts as charts_api
from ..library import tmdb as tmdb_api
from .agenda import _Agenda
from .base import (
    FIRST_YEAR,
    FRESH_BRANDS,
    JW_LIST_BRANDS,
    LOGO_WARM,
    METAHUB,
    MINE_TTL,
    POPULAR_TTL,
    RECS_TTL,
    SERVICE_ERRORS,
    SLOW_TTL,
    TRAKT_FAVORITES,
    load_awards,
)
from .items import video_item

log = logging.getLogger("orbital.foryou")  # el mismo nombre de siempre: la bitácora no cambia


class _Shelves(_Agenda):
    """Los estantes: qué listas hay, su encabezado y lo que trae cada una."""

    def lists(self) -> list[dict]:
        """El riel: una entrada por lista (solo las de los servicios que tienes)."""
        video: list[dict] = []
        # Seguir viendo y Mi lista ya traen lo de Trakt (trakt_sync.py); sin Trakt, lo de tu Stremio, que no pide clave: así
        # «Para ti» no se queda solo con juegos. Con Trakt, Mi lista es tu watchlist de Trakt (abajo, como el iPhone): no se repite.
        mine = "Trakt" if self.trakt.linked else "Stremio"
        if self._stremio("continue"):
            video.append({"id": "continue", "title": "Seguir viendo", "icon": "watching", "source": mine, "meta": "Lo que dejaste a medias"})
        if not self.trakt.linked and self._stremio("mylist"):
            video.append({"id": "mylist", "title": "Mi lista", "icon": "library", "source": "Stremio", "meta": "Tu biblioteca"})
        if self.trakt.linked:
            video += [
                {"id": "recs", "title": "Recomendadas", "icon": "spark", "source": "Trakt", "meta": "Por lo que has visto", "split": True},
                {"id": "mine", "title": "Tus series", "icon": "series", "source": "Trakt", "meta": "Las que estás viendo"},
                # Mi lista = tu watchlist de Trakt (el glosario del iPhone, 31 oct 2026).
                {"id": "watchlist", "title": "Mi lista", "icon": "bookmark", "source": "Trakt", "meta": "Lo que dejaste pendiente"},
                # Tus favoritos de Trakt (el corazón). En pantalla no se llama solo «Favoritos»: así se llaman los de tus juegos.
                {"id": TRAKT_FAVORITES, "title": "Series y películas favoritas", "icon": "heart", "source": "Trakt",
                 "meta": "Las que marcaste con el corazón"},
                # «Lo nuevo de lo tuyo» (el Inicio del iPhone): la semana que pasó y lo que viene, de las series que sigues.
                {"id": "nuevo", "title": "Lo nuevo de lo tuyo", "icon": "calendar", "source": "Trakt", "meta": "De las series que sigues"},
                # Dos formas de verlo (las píldoras de arriba): por día, o la semana como una guía de TV.
                {"id": "estrenos", "title": "Próximos estrenos", "icon": "calendar", "source": "Trakt", "meta": "Las series que sigues",
                 "views": [{"id": "day", "label": "Por día"}, {"id": "week", "label": "Semana"}]},
            ]
            try:
                own = self.cache.get("trakt:lists", MINE_TTL, self.trakt.lists, stale=True)
            except SERVICE_ERRORS as exc:
                log.warning("Para ti: no pude leer tus listas de Trakt: %s", exc)
                own = []
            video += [{"id": f"list:{row['id']}", "title": row["name"], "icon": "list", "source": "Trakt", "meta": "Tu lista"}
                      for row in own[:8]]
        # Tus listas de Letterboxd (como el iPhone, en Tus listas): solo leer.
        video += [{"id": f"letterboxd:{row['slug']}", "title": row["name"], "icon": "list", "source": "Letterboxd",
                   "meta": "Tu lista de Letterboxd", **({"count": row["count"]} if row.get("count") else {})}
                  for row in self._letterboxd_lists()[:8]]
        if self.trakt.configured:
            video += [
                {"id": "trend", "title": "En tendencia", "icon": "trend", "source": "Trakt", "meta": "Lo más visto esta semana en Trakt", "split": True},
                {"id": "popular", "title": "Lo más popular", "icon": "flame", "source": "Trakt", "meta": "De todos los tiempos", "split": True},
            ]
        elif self._stremio("cinemeta"):
            video.append({"id": "cinemeta", "title": "Lo más popular", "icon": "flame", "source": "Cinemeta",
                          "meta": "Lo más visto hoy", "split": True})
        for entry in self.addon_catalogs():
            video.append({"id": entry["id"], "title": entry["title"], "icon": "addon", "source": "Complemento",
                          "meta": f"De {entry['addon']}", "split": len(entry["kinds"]) > 1})
        critics = self._critics_refs()
        if critics:  # Rotten Tomatoes vía MDBList (y una lista pública de Trakt para series): no pide clave
            video.append({"id": "critics", "title": "Aprobadas por la crítica", "icon": "spark", "source": "Rotten Tomatoes",
                          # En español y sin la jerga de Rotten Tomatoes («Certified Fresh») (Fernando, 2 nov 2026, F5).
                          "meta": {2: "Películas y series recientes con buena crítica", 1: ("Películas recientes con buena crítica"
                                   if "movie" in critics else "Series recientes con buena crítica")}[min(2, len(critics))],
                          "split": len(critics) > 1})
        # Netflix (Top 10 oficial) y JustWatch (lo más visto por plataforma): ninguna pide clave.
        video.append({"id": "chart:netflix", "title": "Top 10 en Netflix", "icon": "chart", "source": "Netflix",
                      "meta": self._netflix_meta(), "split": True, "brand": "netflix",
                      "logo": self.platforms().get("netflix", {}).get("logo")})
        for brand in JW_LIST_BRANDS:
            name = charts_api.JUSTWATCH_PACKAGES[brand][1]
            # «Lo más visto» solo en Netflix (cuenta vistas); JustWatch mide interés: «Tendencias».
            video.append({"id": f"jw:{brand}", "title": f"Tendencias en {name}", "icon": "chart", "source": "JustWatch",
                          "meta": f"Tendencia en JustWatch · {self._country()}", "split": True, "brand": brand,
                          "logo": charts_api.justwatch_logo(brand)})
        found = self.platforms()
        for brand, (name, _) in tmdb_api.PLATFORMS.items():
            # Respaldo de cada plataforma: va siempre (si JustWatch trae películas pero no series, con «Series» no quedaba
            # nada de Disney). `fallback_for` dice de qué lista es respaldo y `covered`, qué tipos esa lista ya trae (de lo
            # que hay en caché: el riel no espera a JustWatch). La TV lo esconde si la lista con puesto trae los dos; el
            # iPhone, por tipo (ShelfPlan.isFallback).
            if brand in found:
                ranked = self._ranked_list(brand)
                video.append({"id": brand, "title": name, "brand": brand, "logo": found[brand]["logo"], "icon": "chart", "source": "TMDB",
                              "meta": f"Lo más popular en {self._country()}", "split": True,
                              "fallback_for": ranked, "covered": self._covered(ranked) if ranked else []})
        video += self._collections()
        games: list[dict] = [{"id": "mygames", "title": "Tus juegos", "icon": "gamepad", "source": "",
                              "meta": "Favoritos, los más jugados y los que no has abierto"}]
        if self.rawg.configured:
            games += [
                {"id": "rawg:new", "title": "Novedades", "icon": "fresh", "source": "RAWG", "meta": "Lo que acaba de salir"},
                {"id": "rawg:popular", "title": "Lo más popular", "icon": "flame", "source": "RAWG", "meta": "Lo que más se juega este año"},
                {"id": "rawg:best", "title": "Mejor calificados", "icon": "trophy", "source": "RAWG", "meta": "Por Metacritic"},
            ]
        return [{**row, "group": "video"} for row in video] + [{**row, "group": "games"} for row in games]

    def _collections(self) -> list[dict]:
        """Lo de Películas y series que viene del iPhone (Para ti › Listas): «Porque viste X», «Nuevo en tus plataformas»,
        los premios, los estudios, lo mejor del género, las temporadas y los años. `collection` dice qué tarjeta lleva
        (award, studio, genre, season, year) en la TV."""
        out: list[dict] = []
        if self.trakt.linked:
            seeds = self._recent_seeds()
            seed = self._seed_of_day(seeds) if seeds else None
            if seed:
                # Como el iPhone: cada día otro de los primeros cinco (si uno no tiene relacionados, el siguiente), y se
                # puede elegir entre tus últimos 12 (`seeds`; la lista «because:<imdb>»).
                card = lambda s: {"meta_id": s["imdb"], "kind": s["kind"], "title": s["title"],  # noqa: E731
                                  "image": METAHUB.format(kind="poster", imdb=s["imdb"]), "watched_at": s.get("watched_at")}
                out.append({"id": "because", "title": f"Porque viste {seed['title']}", "icon": "spark", "source": "Trakt",
                            "meta": "Lo que Trakt relaciona con algo que viste hace poco",
                            "seed": card(seed), "seeds": [card(s) for s in seeds]})
        if self.tmdb.configured and any(b in self.platforms() for b in FRESH_BRANDS):
            out.append({"id": "fresh", "title": "Nuevo en tus plataformas", "icon": "fresh", "source": "TMDB",
                        "meta": "Episodios de estas dos semanas y películas recién llegadas", "split": True})
        for a in load_awards():
            out.append({"id": f"award:{a['id']}", "title": a["title"], "meta": a.get("category") or "", "icon": "trophy",
                        "source": "Orbital", "collection": "award", "kinds": [a["kind"]], "tint": a["tint"],
                        "statue": f"/img/awards/{a['id']}.png", "count": len(a["winners"])})
        if self.tmdb.configured:
            logos = self._studio_logos()
            out += [{"id": f"studio:{sid}", "title": name, "meta": "Lo más popular del estudio", "icon": "film", "source": "TMDB",
                     "collection": "studio", "kinds": ["movie"], **({"logo": logos[str(sid)]} if logos.get(str(sid)) else {})}
                    for sid, name in tmdb_api.STUDIOS]
            year = self._today().year
            out += [{"id": f"genre:{g.slug}", "title": g.title, "headline": f"Lo mejor de {g.title} en {year}",
                     "meta": "Las mejor calificadas del año", "icon": "film", "source": "TMDB", "collection": "genre",
                     "kinds": ["movie", "series"]} for g in tmdb_api.GENRES]
            today = self._today()
            out += [{"id": f"season:{s.slug}", "title": s.title, "headline": s.title, "meta": s.blurb, "icon": "calendar",
                     "source": "TMDB", "collection": "season", "kinds": ["movie", "series"],
                     "when": tmdb_api.season_when(tmdb_api.season_days(s, today))}
                    for s in tmdb_api.ordered_seasons(today)]
        if self.trakt.configured:
            this_year = datetime.now().year
            out += [{"id": f"year:{y}", "title": str(y), "meta": f"Lo más popular de {y}", "icon": "calendar", "source": "Trakt",
                     "collection": "year", "split": True} for y in range(this_year, FIRST_YEAR - 1, -1)]
        return out

    # --- el contenido de cada lista ----------------------------------------------------------
    def list_payload(self, list_id: str, kind: str | None = None) -> dict:
        """Lo que pide la tele: los títulos y, en género o temporada, el título de la pantalla (el año de verdad)."""
        return {"items": self.list_items(list_id, kind), **self._list_heading(list_id)}

    def _list_heading(self, list_id: str) -> dict:
        if list_id.startswith("genre:"):
            bundle = self.cache.peek(f"tmdb:genre:{list_id.removeprefix('genre:')}:{self._today().year}")
        elif list_id.startswith("season:"):
            bundle = self.cache.peek(f"tmdb:season:{list_id.removeprefix('season:')}")
        else:
            return {}
        if isinstance(bundle, dict) and bundle.get("title"):
            return {"title": bundle["title"], **({"meta": bundle["meta"]} if bundle.get("meta") else {})}
        return {}

    def list_items(self, list_id: str, kind: str | None = None) -> list[dict]:
        kind = kind if kind in ("movie", "series") else "series"
        hidden = self.services.state.dismissed()
        items = self._list(list_id, kind)
        out = [self._with_art(i) for i in items if i["key"] not in hidden]
        self._warm_logos(out[:LOGO_WARM])
        return out

    def _list(self, list_id: str, kind: str) -> list[dict]:
        t = self.trakt
        if list_id in ("continue", "mylist", "cinemeta"):
            why = {"continue": "Seguir viendo", "mylist": "En Mi lista", "cinemeta": "Popular"}[list_id]
            return [video_item(e, why, overview=i.extra.get("description"))
                    for i, e in self._stremio(list_id, kind if list_id == "cinemeta" else None)]
        if list_id.startswith("addon:"):
            entry = next((a for a in self.addon_catalogs() if a["id"] == list_id), None)
            if not entry:
                raise KeyError(list_id)
            return self.cache.get(f"{list_id}:{kind}", POPULAR_TTL, lambda: self._addon_list(entry, kind))
        if list_id == "estrenos":
            return self.calendar()
        if list_id == "nuevo":
            return self.latest()
        if list_id == "critics":
            return self._critics(kind)
        if list_id == "recs":
            return [video_item(e, "Recomendada") for e in self.cache.get(f"trakt:recs:{kind}", RECS_TTL, lambda: t.recommendations(kind))]
        if list_id == "mine":
            return [video_item(e, "Sigues viéndola") for e in self.cache.get("trakt:watching", MINE_TTL, t.watching)]
        if list_id == "watchlist":
            return [video_item(e, "En Mi lista") for e in self.cache.get("trakt:watchlist", MINE_TTL, t.watchlist)]
        if list_id == TRAKT_FAVORITES:  # ya se guardan un rato en Trakt (y se preguntan con last_activities)
            return [video_item(e, "En tus favoritos") for e in t.favorites()]
        if list_id.startswith("letterboxd:"):
            return [video_item(e, "Tu lista de Letterboxd", in_list=True) for e in self._letterboxd_list(list_id.removeprefix("letterboxd:"))]
        if list_id.startswith("list:"):
            lid = list_id.removeprefix("list:")
            name = next((r["name"] for r in self.cache.get("trakt:lists", MINE_TTL, t.lists) if r["id"] == lid), "tu lista")
            # La etiqueta es de un renglón: un nombre largo se cortaba («En «The 25 Best Sci-Fi…»»).
            why = f"En «{name}»" if len(name) <= 22 else "En una de tus listas"
            return [video_item(e, why, in_list=True) for e in self.cache.get(f"trakt:list:{lid}", MINE_TTL, lambda: t.list_items(lid))]
        if list_id == "trend":
            return [video_item(e, "En tendencia") for e in self.cache.get(f"trakt:trend:{kind}", RECS_TTL, lambda: t.trending(kind))]
        if list_id == "popular":
            return [video_item(e, "Popular") for e in self.cache.get(f"trakt:popular:{kind}", POPULAR_TTL, lambda: t.popular(kind))]
        if list_id in tmdb_api.PLATFORMS:
            return self.cache.get(f"tmdb:{list_id}:{kind}", POPULAR_TTL, lambda: self._platform(list_id, kind), whole=True)
        if list_id == "chart:netflix":
            entries = self.cache.get(f"charts:netflix:{kind}", SLOW_TTL, stale=True, load=lambda: charts_api.netflix_entries(
                self.region, kind, tmdb=self.tmdb if self.tmdb.configured else None, cinemeta=self.services.cinemeta))
            return [self._chart_item(e, kind, "Netflix") for e in entries]
        if list_id.startswith("jw:"):
            brand = list_id.removeprefix("jw:")
            if brand not in charts_api.JUSTWATCH_PACKAGES:
                raise KeyError(list_id)
            entries = self.cache.get(f"charts:jw:{brand}:{kind}", POPULAR_TTL, stale=True, load=lambda: self.snapshots.annotate(
                f"jw:{brand}", kind, charts_api.fetch_justwatch_chart(brand, self.region, kind)))
            name = charts_api.JUSTWATCH_PACKAGES[brand][1]
            return [self._chart_item(e, kind, name) for e in entries]
        if list_id == "because" or list_id.startswith("because:"):
            seeds = self._recent_seeds()
            if not seeds:
                return []
            wanted = list_id.removeprefix("because:") if ":" in list_id else None
            seed = next((s for s in seeds if s["imdb"] == wanted), None) if wanted else self._seed_of_day(seeds)
            if seed is None:
                raise KeyError(list_id)  # solo de tus últimos 12
            # Como el iPhone: el porqué es la semilla (no uno por póster) y van en el orden de Trakt.
            why = f"Porque viste {seed['title']}" if len(seed["title"]) <= 18 else "Porque viste algo parecido"
            return [video_item(e, why) for e in self._related(seed)]
        if list_id == "fresh":
            return self.cache.get(f"tmdb:fresh:{kind}", POPULAR_TTL, lambda: self._fresh(kind), whole=True)
        if list_id.startswith("canon:"):
            return [video_item({"imdb": e["imdb"], "kind": e["kind"], "title": e["title"], "year": e.get("year")}, f"N.º {n} de la lista")
                    for n, e in enumerate(self._canon(list_id.removeprefix("canon:")), start=1)]
        if list_id.startswith("award:"):
            award = next((a for a in load_awards() if a["id"] == list_id.removeprefix("award:")), None)
            if not award:
                raise KeyError(list_id)
            return [{**video_item({"imdb": w["imdb"], "kind": award["kind"], "title": w["title"], "year": w.get("year")},
                                  f"{award['title']} {w['award_year']}"), "award_year": w["award_year"]}
                    for w in award["winners"]]
        if list_id.startswith("studio:"):
            sid = list_id.removeprefix("studio:")
            name = next((n for i, n in tmdb_api.STUDIOS if str(i) == sid), None)
            if not name or not self.tmdb.configured:
                raise KeyError(list_id)
            return self.cache.get(f"tmdb:studio:{sid}", SLOW_TTL, lambda: self._studio(int(sid), name), whole=True)
        if list_id.startswith("genre:"):
            slug = list_id.removeprefix("genre:")
            if slug not in tmdb_api.GENRE_BY_SLUG or not self.tmdb.configured:
                raise KeyError(list_id)
            year = self._today().year
            bundle = self.cache.get(f"tmdb:genre:{slug}:{year}", SLOW_TTL, lambda: self._genre_bundle(slug, year), whole=True)
            return bundle["items"]
        if list_id.startswith("season:"):
            slug = list_id.removeprefix("season:")
            if slug not in tmdb_api.SEASON_BY_SLUG or not self.tmdb.configured:
                raise KeyError(list_id)
            bundle = self.cache.get(f"tmdb:season:{slug}", SLOW_TTL, lambda: self._season_bundle(slug), whole=True)
            return bundle["items"]
        if list_id.startswith("year:"):
            year = list_id.removeprefix("year:")
            if not year.isdigit() or not FIRST_YEAR <= int(year) <= datetime.now().year:
                raise KeyError(list_id)
            return self.cache.get(f"trakt:year:{year}:{kind}", SLOW_TTL, lambda: self._year(int(year), kind))
        if list_id == "mygames":
            return self.local_games()
        if list_id.startswith("rawg:"):
            return self._mark_owned(self.cache.get(list_id, SLOW_TTL, lambda: self._rawg(list_id.removeprefix("rawg:"))))
        raise KeyError(list_id)

    def _covered(self, list_id: str) -> list[str]:
        """Qué tipos ya trae una lista con puesto, según lo que hay en caché (sin salir a internet)."""
        prefix = "charts:netflix" if list_id == "chart:netflix" else f"charts:{list_id}"
        return [kind for kind in ("movie", "series") if self.cache.peek(f"{prefix}:{kind}")]
