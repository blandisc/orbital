"""«Para ti» en el demo: Trakt, TMDB y RAWG de mentiras (títulos reales, sin cuenta ni internet).

Las imágenes sí vienen de internet al verlas en el navegador (metahub y la tienda de Steam), como
en Orbital de verdad. Conectar Trakt funciona: el código se «confirma» solo a los pocos segundos.
"""

from __future__ import annotations

import time

from orbital.library import charts as charts_api
from orbital.library import cinemeta as cinemeta_api
from orbital.library import trakt as trakt_api

# Los géneros de Trakt de algunos títulos (para ver «Misterio y ciencia ficción, como Dark» en la demo).
GENRES = {"tt15239678": ["Science Fiction", "Adventure", "Drama"], "tt2543164": ["Science Fiction", "Drama", "Mystery"],
          "tt0816692": ["Science Fiction", "Adventure", "Drama"], "tt1856101": ["Science Fiction", "Thriller", "Mystery"],
          "tt0482571": ["Mystery", "Thriller", "Drama"], "tt1160419": ["Science Fiction", "Adventure"],
          "tt5753856": ["Mystery", "Science Fiction", "Drama"], "tt2085059": ["Science Fiction", "Thriller", "Drama"],
          "tt14688458": ["Science Fiction", "Mystery", "Drama"], "tt4574334": ["Science Fiction", "Horror", "Drama"],
          "tt9253284": ["Science Fiction", "Action", "Drama"], "tt7660850": ["Drama", "Comedy"],
          "tt11280740": ["Mystery", "Science Fiction", "Drama"], "tt14452776": ["Comedy", "Drama"], "tt2788316": ["Drama", "History", "War"]}

def _m(imdb, title, year, runtime):
    return {"kind": "movie", "imdb": imdb, "title": title, "year": year, "runtime": runtime, "episodes": None, "overview": "", "trakt_id": None,
            "genres": GENRES.get(imdb, [])}


def _s(imdb, title, year, episodes, trakt_id=None):
    return {"kind": "series", "imdb": imdb, "title": title, "year": year, "runtime": None, "episodes": episodes, "overview": "", "trakt_id": trakt_id,
            "genres": GENRES.get(imdb, [])}


MOVIES = {
    "br": _m("tt1856101", "Blade Runner 2049", 2017, 164), "dune2": _m("tt15239678", "Dune: Parte dos", 2024, 166),
    "arrival": _m("tt2543164", "La llegada", 2016, 116), "inter": _m("tt0816692", "Interstellar", 2014, 169),
    "inception": _m("tt1375666", "El origen", 2010, 148), "oppen": _m("tt15398776", "Oppenheimer", 2023, 180),
    "past": _m("tt13238346", "Vidas pasadas", 2023, 106), "batman": _m("tt1877830", "The Batman", 2022, 176),
    "parasite": _m("tt6751668", "Parásitos", 2019, 132), "madmax": _m("tt1392190", "Mad Max: Furia en el camino", 2015, 120),
    "spider": _m("tt9362722", "Spider-Man: A través del Spider-Verso", 2023, 140), "prestige": _m("tt0482571", "El gran truco", 2006, 130),
    "dune1": _m("tt1160419", "Dune", 2021, 155), "glass": _m("tt11564570", "Glass Onion", 2022, 139),
    "inside2": _m("tt22022452", "Intensa-Mente 2", 2024, 96), "poor": _m("tt14230458", "Pobres criaturas", 2023, 141),
}
SHOWS = {
    "andor": _s("tt9253284", "Andor", 2022, 24), "shogun": _s("tt2788316", "Shōgun", 2024, 10),
    "succession": _s("tt7660850", "Succession", 2018, 39), "dark": _s("tt5753856", "Dark", 2017, 26),
    "bear": _s("tt14452776", "The Bear", 2022, 38), "stranger": _s("tt4574334", "Stranger Things", 2016, 42),
    "blackmirror": _s("tt2085059", "Black Mirror", 2011, 33), "saul": _s("tt3032476", "Better Call Saul", 2015, 63),
    "breaking": _s("tt0903747", "Breaking Bad", 2008, 62), "tlou": _s("tt3581920", "The Last of Us", 2023, 16),
    "severance": _s("tt11280740", "Severance", 2022, 19), "silo": _s("tt14688458", "Silo", 2023, 20),
    "futurama": _s("tt0149460", "Futurama", 1999, 180), "wednesday": _s("tt13443470", "Merlina", 2022, 16),
    "squid": _s("tt10919420", "El juego del calamar", 2021, 22), "mando": _s("tt8111088", "The Mandalorian", 2019, 24),
    "loki": _s("tt9140554", "Loki", 2021, 12), "hotd": _s("tt11198330", "La casa del dragón", 2022, 18),
    "penguin": _s("tt15435876", "The Penguin", 2024, 8), "lotus": _s("tt13406094", "The White Lotus", 2021, 21),
}
M, S = MOVIES, SHOWS
OFFLINE = __import__("pathlib").Path(__import__("tempfile").gettempdir()) / "orbital-demo-offline"


def _offline():
    """«Sin internet» en la demo (para ver la cola de Trakt): existe el archivo OFFLINE."""
    if OFFLINE.exists():
        raise trakt_api.TraktError("No pude conectar con Trakt: sin internet (demo)")
# Las que tienen ficha en la demo (DEMO_TITLES de demo_server.py) y no salen en las filas: así se pueden guardar y abrir.
WITH_PAGE = [_s("tt0386676", "The Office", 2005, 201)]

if __import__("os").environ.get("ORBITAL_DEMO_LONG") == "1":  # pruebas: nombres larguísimos (¿algo se corta o se encima?)
    for n, entry in enumerate([*MOVIES.values(), *SHOWS.values()]):
        if n % 3 == 0:
            entry["title"] = f"{entry['title']}: La Saga Completa en Versión Extendida del Director"


class DemoTrakt:
    configured = True

    def __init__(self) -> None:
        self.linked = False
        self._linking_since = 0.0
        self._mine: dict[str, dict] = {}  # las listas que se crean aquí («Tu match perfecto», «Tus canales»)
        self._ratings: dict[str, int] = {}
        self._marked: list[tuple[dict, object]] = []
        # Editar tus listas: lo que agregaste o quitaste de Mi lista y de la lista de muestra («1»), como en Trakt.
        self._edits: dict[str, tuple[list[str], set[str]]] = {"watchlist": ([], set()), "1": ([], set())}

    def device_code(self):
        self._linking_since = time.time()
        return trakt_api.DeviceCode("demo", "4F7K2Q", "https://trakt.tv/activate", 2, time.time() + 600)

    def poll_device(self, code):
        if time.time() - self._linking_since > 6:  # como si lo hubieras escrito en el celular
            self.linked = True
            return "linked"
        return "pending"

    def unlink(self):
        self.linked = False

    def username(self):
        return "Demo"

    def recommendations(self, kind, limit=30):
        return [S[k] for k in ("andor", "shogun", "succession", "dark", "bear", "blackmirror", "saul")] if kind == "series" \
            else [M[k] for k in ("br", "spider", "madmax", "inception", "parasite")]

    def _edited(self, which, base):
        added, removed = self._edits[which]
        known = {e["imdb"]: e for e in [*S.values(), *M.values(), *WITH_PAGE]}
        seen = set(removed)
        return [e for e in [*(known.get(i, _m(i, i, 2020, 100)) for i in added), *base] if not (e["imdb"] in seen or seen.add(e["imdb"]))]

    def _edit(self, which, imdb, add):
        added, removed = self._edits[which]
        if add and imdb in removed:  # «Deshacer»: vuelve a su lugar
            removed.discard(imdb)
        elif add:
            if imdb not in added:
                added.insert(0, imdb)
        else:
            removed.add(imdb)
            if imdb in added:
                added.remove(imdb)

    def watchlist(self):
        return self._edited("watchlist", [M["dune2"], M["oppen"], M["past"], S["tlou"], M["batman"], M["parasite"], M["prestige"], S["breaking"]])

    def set_watchlist(self, kind, imdb, add):
        self._edit("watchlist", imdb, add)

    def favorites(self):  # el corazón de Trakt («Series y películas favoritas»)
        return [S["severance"], M["inter"], S["bear"]]

    def lists(self):
        # Un nombre largo de verdad (como las listas que la gente copia en Trakt): no debe cortarse feo.
        meta = getattr(self, "_meta", {})
        rows = [{"id": "1", "name": "The 25 Best Sci-Fi Movies of the 21st Century (So Far)", "privacy": "public", "count": 7}] + \
            [{"id": i, "name": row["name"], "privacy": "private", "count": len(row["items"])} for i, row in self._mine.items()]
        return [{**r, **meta.get(r["id"], {})} for r in rows]

    def named_list(self, name, create=False):
        found = next((row["id"] for row in self.lists() if row["name"].casefold() == name.casefold()), None)
        return found or (self.create_list(name) if create else None)

    def create_list(self, name):
        list_id = str(100 + len(self._mine))
        self._mine[list_id] = {"name": name, "items": []}
        return list_id

    def set_list_item(self, list_id, kind, imdb, add):
        if list_id in self._edits:
            return self._edit(list_id, imdb, add)
        items = self._mine.setdefault(list_id, {"name": list_id, "items": []})["items"]
        if add and imdb not in items:
            items.append(imdb)
        elif not add and imdb in items:
            items.remove(imdb)

    def set_rating(self, kind, imdb, rating):
        if rating is None:
            self._ratings.pop(imdb, None)
        else:
            self._ratings[imdb] = rating

    def my_rating(self, kind, imdb):
        return self._ratings.get(imdb)

    def add_history(self, target, watched_at=None):
        _offline()
        self._marked.append((target, watched_at))
        at = float(watched_at) if isinstance(watched_at, (int, float)) or str(watched_at).replace(".", "").isdigit() else time.time()
        movie, show, ep = target.get("movie"), target.get("show"), target.get("episode") or {}
        imdb = (movie or show or {}).get("ids", {}).get("imdb")
        if imdb and (movie or ep):
            self._views().append(self._view(imdb, "movie" if movie else "series", at, ep.get("season"), ep.get("number")))

    # --- ola 3 (O3-B): tus vistas con su id, tu historial, tu nota y tus temporadas. `ORBITAL_DEMO_VIP=1`: eres VIP.
    #     Sin internet: crea el archivo %TEMP%\orbital-demo-offline (y bórralo para volver).
    def _view(self, imdb, kind, at, season=None, episode=None):
        self._next_id = getattr(self, "_next_id", 9000) + 1
        known = {e["imdb"]: e for e in [*S.values(), *M.values(), *WITH_PAGE]}
        return {"id": self._next_id, "at": at, "kind": kind, "imdb": imdb, "title": known.get(imdb, {}).get("title", imdb),
                "year": known.get(imdb, {}).get("year"), "season": season, "episode": episode,
                "episode_title": f"Episodio {episode}" if episode else None}

    def _views(self):
        if not hasattr(self, "_seen"):
            now, day = time.time(), 86400
            office, inter = WITH_PAGE[0]["imdb"], M["inter"]["imdb"]
            self._seen = [self._view(inter, "movie", now - 2 * day), self._view(inter, "movie", now - 400 * day),
                          self._view(office, "series", now - 3 * day, 1, 1), self._view(office, "series", now - 3 * day + 600, 1, 1),
                          self._view(office, "series", now - 3 * day + 1900, 1, 2)]
        return self._seen

    def last_activities(self):  # cada vez, todo «cambió»: la demo es chica
        return {}

    def watchlist_rows(self):  # la ficha: «En Mi lista» (Seguir viendo y la ficha leen esto)
        return [{**e, "listed_at": time.time() - n * 3600} for n, e in enumerate(self.watchlist())]

    def recent_shows(self, limit=15):  # la ficha de The Office sabe qué capítulos viste (los de tus vistas)
        return [WITH_PAGE[0]]

    def show_progress(self, imdb):
        seen = {(v["season"], v["episode"]) for v in self._views() if v["imdb"] == imdb and v["season"]}
        if not seen:
            return None
        last = max(v["at"] for v in self._views() if v["imdb"] == imdb)
        nxt = max(seen)
        return {"next": (nxt[0], nxt[1] + 1), "last_watched": last, "watched": seen}

    def viewings(self, kind, imdb, season=None, episode=None):
        _offline()
        rows = [v for v in self._views() if v["imdb"] == imdb and (season is None or (v["season"], v["episode"]) == (season, episode))]
        return sorted(({"id": v["id"], "at": v["at"]} for v in rows), key=lambda v: -v["at"])

    def remove_viewings(self, ids):
        _offline()
        self._seen = [v for v in self._views() if v["id"] not in set(ids)]

    def history(self, page=1, limit=100):
        _offline()
        rows = sorted(self._views(), key=lambda v: -v["at"])
        return rows[(page - 1) * limit: page * limit]

    def is_vip(self):
        _offline()
        return __import__("os").environ.get("ORBITAL_DEMO_VIP") == "1"

    def my_notes(self):
        _offline()
        return {imdb: dict(n) for imdb, n in getattr(self, "_notes", {}).items()}

    def set_note(self, kind, imdb, text, existing):
        _offline()
        self._notes = getattr(self, "_notes", {})
        if not text.strip():
            self._notes.pop(imdb, None)
            return None
        self._notes[imdb] = {"id": existing or len(self._notes) + 1, "text": text.strip()}
        return self._notes[imdb]["id"]

    def season_rating(self, imdb, season):
        _offline()
        return getattr(self, "_seasons", {}).get((imdb, season))

    def set_season_rating(self, imdb, season, rating):
        _offline()
        self._seasons = getattr(self, "_seasons", {})
        if rating is None:
            self._seasons.pop((imdb, season), None)
        else:
            self._seasons[(imdb, season)] = rating

    def public_list_items(self, user, slug):
        return []

    # --- el gestor tipo Trakt (olas 1 y 2): lo visto, lo dejado, varios a la vez y tus listas --------------------------
    def watched_state(self):
        now = time.time()
        day = 86400
        movies = {e["imdb"]: {**e, "last": now - n * 9 * day} for n, e in enumerate([M["dune1"], M["inter"], M["arrival"], M["br"], M["inception"]])}
        shows = {S["bear"]["imdb"]: {**S["bear"], "last": now - day, "fraction": .6, "airing": True},
                 S["andor"]["imdb"]: {**S["andor"], "last": now - 3 * day, "fraction": 1, "airing": False},
                 S["silo"]["imdb"]: {**S["silo"], "last": now - 5 * day, "fraction": .4, "airing": True},
                 S["dark"]["imdb"]: {**S["dark"], "last": now - 40 * day, "fraction": 1, "airing": False},
                 S["lotus"]["imdb"]: {**S["lotus"], "last": now - 250 * day, "fraction": .3, "airing": True},
                 S["futurama"]["imdb"]: {**S["futurama"], "last": now - 60 * day, "fraction": .2, "airing": True}}
        for target, _ in self._marked:  # lo que marcaste aquí
            imdb = (target.get("movie") or {}).get("ids", {}).get("imdb")
            if imdb:
                known = next((e for e in M.values() if e["imdb"] == imdb), _m(imdb, imdb, 2020, 100))
                movies[imdb] = {**known, "last": now}
        return {"movies": movies, "shows": shows}

    def watched_movies(self):  # la ficha de una película vista dice «Vista»
        return {imdb: row["last"] for imdb, row in self.watched_state()["movies"].items()}

    def hidden_shows(self):
        return set(getattr(self, "_hidden", {S["futurama"]["imdb"]}))

    def set_hidden(self, imdbs, hidden, sections=trakt_api.HIDDEN_SECTIONS):
        current = self.hidden_shows()
        self._hidden = current | set(imdbs) if hidden else current - set(imdbs)

    def set_items(self, target, items, add):
        for kind, imdb in items:
            (self.set_watchlist(kind, imdb, add) if target == "watchlist" else self.set_list_item(target, kind, imdb, add))

    def remove_history(self, target):
        self._marked = [(t, w) for t, w in self._marked if t != target]

    def update_list(self, list_id, name=None, privacy=None):
        self._meta = getattr(self, "_meta", {})
        self._meta.setdefault(list_id, {}).update({k: v for k, v in (("name", name), ("privacy", privacy)) if v})

    def delete_list(self, list_id):
        self._mine.pop(list_id, None)

    def reorder(self, list_id, imdbs):
        if list_id in self._mine:
            self._mine[list_id]["items"] = [i for i in imdbs if i in self._mine[list_id]["items"]]

    def duplicate_list(self, list_id, name):
        made = self.create_list(name)
        self._mine[made]["items"] = [e["imdb"] for e in self.list_items(list_id)]
        return made

    def __getattr__(self, name):
        """Lo que la demostración no imita (la ficha y las filas lo piden con Trakt conectado): vacío, nunca un error 500."""
        if name.startswith("_"):
            raise AttributeError(name)
        return lambda *args, **kwargs: []

    def list_items(self, list_id):
        if list_id in self._mine:
            known = {e["imdb"]: e for e in [*S.values(), *M.values()]}
            return [known.get(i, _s(i, i, 2020, 10)) for i in self._mine[list_id]["items"]]
        return self._edited("1", [_m("tt1136608", "District 9", 2009, 112), M["arrival"], M["inter"], M["inception"], M["dune1"], M["br"], S["dark"]])

    def trending(self, kind, limit=30):
        # Todo el catálogo de mentiras, como Trakt de verdad (decenas): con 14, el mosaico se repetía.
        first = ("tlou", "severance", "stranger", "blackmirror", "bear", "shogun", "penguin", "lotus") if kind == "series" \
            else ("dune2", "oppen", "inside2", "batman", "glass", "poor")
        pool = S if kind == "series" else M
        return [pool[k] for k in first] + [v for k, v in pool.items() if k not in first]

    def popular(self, kind, limit=30, years=None):
        if years:  # Por año: lo de ese año y, si no hay, lo de siempre (el demo tiene pocos títulos)
            pool = S if kind == "series" else M
            found = [v for v in pool.values() if v["year"] == int(years)]
            if found:
                return found
        return [S[k] for k in ("breaking", "stranger", "tlou", "bear", "succession", "blackmirror", "dark", "saul")] if kind == "series" \
            else [M[k] for k in ("oppen", "dune2", "inter", "inception", "spider", "batman", "parasite", "madmax")]

    def related(self, kind, imdb, limit=15):
        return [S[k] for k in ("dark", "blackmirror", "silo", "stranger", "andor", "succession")] if kind == "series" \
            else [M[k] for k in ("arrival", "inter", "br", "prestige", "dune1")]

    def rating(self, kind, imdb):  # la ficha: la calificación de Trakt (de mentiras, estable por título)
        return round(7 + (sum(map(ord, imdb)) % 25) / 10, 1)

    def last_watched(self):
        return {**S["severance"], "watched_at": time.time() - 2 * 86400}

    def recent_watched(self, limit=5):
        """Tus últimos cinco (para «Porque viste», que cambia cada día entre ellos)."""
        picks = [S["severance"], S["bear"], M["dune2"], S["dark"], S["shogun"]][:limit]
        return [{**e, "watched_at": time.time() - (n + 2) * 86400} for n, e in enumerate(picks)]

    def calendar(self, start, days=15):
        """Estrenos de mentiras alrededor de hoy: uno esta noche, tres juntos de madrugada mañana (como Paramount+)…"""
        import datetime as dt

        base = dt.datetime.now().astimezone().replace(minute=0, second=0, microsecond=0)
        at = lambda days_, hour: (base.replace(hour=hour) + dt.timedelta(days=days_)).timestamp()  # noqa: E731
        rows = [(S["severance"], 2, 7, "Chikhai Bardo", at(0, 20), "Apple TV"), (S["silo"], 2, 4, "", at(1, 1), "Apple TV"),
                (S["andor"], 2, 4, "", at(1, 1), "Disney+"), (S["andor"], 2, 5, "", at(1, 1), "Disney+"), (S["andor"], 2, 6, "", at(1, 1), "Disney+"),
                (S["futurama"], 13, 1, "The One Amigo", at(3, 19), "Hulu"), (S["bear"], 4, 1, "Next", at(3, 21), "FX"),
                (S["severance"], 2, 8, "Sweet Vitriol", at(7, 20), "Apple TV"), (S["tlou"], 2, 3, "", at(5, 20), "HBO"),
                # la semana que pasó (para «Lo nuevo de lo tuyo»)
                (S["bear"], 3, 10, "Forever", at(-1, 21), "FX"), (S["shogun"], 2, 1, "", at(-4, 20), "FX"), (S["dark"], 3, 8, "", at(-6, 20), "Netflix")]
        return [{**show, "season": s, "episode": e, "episode_title": t, "aired": when, "network": net, "runtime": 50}
                for show, s, e, t, when, net in rows]

    def watched_ids(self):  # lo que ya viste: Dune: Parte dos (para probar que ¿Qué vemos? no la propone)
        return [M["dune2"]["imdb"]]

    def plays(self, since, until, max_pages=20):  # «Tu año»: un historial de muestra, de enero a hoy
        import random as _random
        from datetime import datetime as _dt
        rng = _random.Random(7)
        start, end = _dt.fromisoformat(since).timestamp(), _dt.fromisoformat(until).timestamp()
        shows, movies = ["severance", "tlou", "silo", "bear", "futurama"], ["dune2", "oppen", "inter", "br", "poor", "past"]
        found, t = [], start
        while t < end:
            t += rng.choice([0.4, 0.7, 1, 1, 1.5, 3, 6]) * 86400
            if t >= end:
                break
            if rng.random() < .3:
                m = M[rng.choice(movies)]
                found.append({"at": t, "kind": "movie", "imdb": m["imdb"], "title": m["title"], "minutes": 130, "genres": ["science-fiction"]})
            else:
                k = rng.choice(shows)
                found.append({"at": t, "kind": "series", "imdb": S[k]["imdb"], "title": S[k]["title"], "minutes": 50, "genres": ["drama"],
                              "season": 1, "episode": rng.randint(1, 9), "episode_title": None})
        return found

    def watching(self, limit=12):
        return [{**S["severance"], "next": {"season": 2, "episode": 6}}, {**S["silo"], "next": {"season": 2, "episode": 3}},
                {**S["tlou"], "next": {"season": 2, "episode": 1}}, {**S["futurama"], "next": {"season": 8, "episode": 4}}]


class DemoTmdb:
    configured = True
    PLATFORMS = {"netflix": ["stranger", "wednesday", "squid", "blackmirror", "dark", "glass"],
                 "disney": ["andor", "shogun", "bear", "mando", "loki", "inside2", "poor"],
                 "hbo": ["tlou", "hotd", "penguin", "lotus", "succession", "dune2", "batman", "dune1"]}

    LOGOS = {"netflix": "pbpMk2JmcoNnQwx5JGpXngfoWtp", "disney": "97yvRBw1GzX7fXprcF80er19ot", "hbo": "jbe4gVSfRlbPTdESXhEKpornsfu"}

    def platforms(self, region):  # los logos sí son los de TMDB (se ven al cargar, como en Orbital de verdad)
        return {brand: {"id": i, "logo": f"https://image.tmdb.org/t/p/w154/{self.LOGOS[brand]}.jpg"}
                for i, brand in enumerate(self.PLATFORMS, start=1)}

    def company_logo(self, company_id):  # sin internet: los estudios van con su nombre
        return None

    def extras(self, kind, tmdb_id, region="MX"):  # la ficha: frase, clasificación y créditos de muestra
        face = lambda i, name, role: {"id": i, "name": name, "role": role, "photo": None}  # noqa: E731 - sin internet: iniciales
        if kind == "series":
            return {"tagline": "Separa tu vida del trabajo. Para siempre.", "certification": "B15", "directors": ["Dan Erickson"],
                    "writers": [], "cast": ["Adam Scott", "Britt Lower", "Zach Cherry"],
                    "people": [face(1, "Dan Erickson", "Creación"), face(2, "Adam Scott", "Mark Scout"), face(3, "Britt Lower", "Helly R."),
                               face(4, "Zach Cherry", "Dylan G."), face(5, "Patricia Arquette", "Harmony Cobel"), face(6, "John Turturro", "Irving B.")],
                    "release": "2022-02-18", "languages": ["en"], "studios": ["Apple TV+"], "collection": None}
        return {"tagline": "Larga vida a la lucha.", "certification": "B", "directors": ["Denis Villeneuve"],
                "writers": ["Jon Spaihts"], "cast": ["Timothée Chalamet", "Zendaya", "Rebecca Ferguson"],
                "people": [face(7, "Denis Villeneuve", "Dirección"), face(8, "Jon Spaihts", "Guion"), face(9, "Timothée Chalamet", "Paul Atreides"),
                           face(10, "Zendaya", "Chani"), face(11, "Rebecca Ferguson", "Jessica")],
                "release": "2024-02-29", "languages": ["en", "es"], "studios": ["Legendary Pictures", "Warner Bros."],
                "collection": {"id": 726871, "name": "Dune: colección"}}

    def collection_parts(self, collection_id):  # la saga del demo: las dos de Dune (los ids del filtro avanzado ya traen su IMDb)
        keys = list(M)
        return [{"kind": "movie", "id": self.FILTER_BASE + keys.index(k)} for k in ("dune1", "dune2") if k in keys]

    def person(self, person_id):  # una persona: su filmografía con los títulos del demo
        picks = ["severance", "dune2", "inter", "br", "arrival", "tlou", "andor", "oppen"]
        return {"id": person_id, "name": "Adam Scott", "photo": None, "born": "3 de abril de 1973", "place": "Santa Cruz, California, EE. UU.",
                "biography": "Actor y productor estadounidense. Empezó en televisión y se hizo conocido por comedias como Parks and Recreation; "
                             "en Severance interpreta a Mark Scout, un empleado de Lumon cuya memoria del trabajo y de su casa está separada.",
                "credits": [{"tmdb_id": n + 1, "kind": "series" if k in S else "movie", "title": {**M, **S}[k]["title"],
                             "poster": f"https://images.metahub.space/poster/medium/{ {**M, **S}[k]['imdb'] }/img",
                             "year": {**M, **S}[k].get("year"), "role": "Mark Scout" if k == "severance" else None} for n, k in enumerate(picks)]}

    def imdb_of(self, kind, tmdb_id):
        picks = ["severance", "dune2", "inter", "br", "arrival", "tlou", "andor", "oppen"]
        return {**M, **S}[picks[(tmdb_id - 1) % len(picks)]]["imdb"]

    def discover(self, kind, provider_id, region):
        brand = list(self.PLATFORMS)[provider_id - 1]
        return [{"id": n, "key": k} for n, k in enumerate(self.PLATFORMS[brand]) if (k in S) == (kind == "series")]

    FILTER_BASE = 100_000  # los ids del filtro avanzado (aparte de los de las plataformas)

    def discover_page(self, kind, **params):
        """El filtro avanzado: el catálogo de mentiras de ese formato, por década si la pides, y un total creíble."""
        pool = [e for e in (S if kind == "series" else M).values()]
        since = params.get("primary_release_date.gte") or params.get("first_air_date.gte")
        until = params.get("primary_release_date.lte") or params.get("first_air_date.lte")
        pool = [e for e in pool if (not since or (e["year"] or 0) >= int(since[:4])) and (not until or (e["year"] or 0) <= int(until[:4]))]
        rows = [{"id": self.FILTER_BASE + i} for i, e in enumerate((S if kind == "series" else M).values()) if e in pool]
        return rows, len(rows) * 37

    def details(self, kind, tmdb_id):  # la calificación (la ficha) y, para el filtro avanzado, el título entero
        if tmdb_id >= self.FILTER_BASE:
            entries = list((S if kind == "series" else M).values())
            e = entries[(tmdb_id - self.FILTER_BASE) % len(entries)]
            return {"kind": kind, "imdb": e["imdb"], "title": e["title"], "year": e["year"], "rating": 7.5, "overview": "", "seasons": None,
                    "poster": f"https://images.metahub.space/poster/medium/{e['imdb']}/img",
                    "backdrop": f"https://images.metahub.space/background/medium/{e['imdb']}/img"}
        return {"rating": round(6.8 + (tmdb_id % 22) / 10, 1)}

    _cinemeta = cinemeta_api.Cinemeta()

    def search(self, kind, title, year=None):
        """El demo no tiene su propio buscador: resuelve título → IMDb con Cinemeta (real), como
        Orbital de verdad sin clave de TMDB. Así el Top 10 de Netflix se ve con arte real."""
        imdb = charts_api.resolve_imdb(title, kind, tmdb=None, cinemeta=self._cinemeta)
        return {"imdb": imdb} if imdb else None

    OVERVIEWS = {  # unas cuantas sinopsis, para ver la ficha completa (las demás quedan sin texto)
        "andor": "Cassian Andor, un ladrón sin causa, descubre en qué puede convertirse cuando la rebelión contra el Imperio empieza a tomar forma.",
        "tlou": "Veinte años después de que una pandemia acabara con la civilización, Joel acepta sacar a Ellie, de 14 años, de una zona de cuarentena.",
        "stranger": "En un pueblo de Indiana, la desaparición de un niño destapa experimentos secretos, fuerzas sobrenaturales y a una niña muy extraña.",
        "severance": "Mark dirige un equipo cuyos recuerdos del trabajo y de la vida personal fueron separados con una cirugía. Hasta que algo no cuadra.",
        "shogun": "Japón, 1600. Un navegante inglés naufraga en las costas de un país al borde de la guerra civil y queda en medio de la lucha por el poder.",
        "dune2": "Paul Atreides se une a Chani y a los Fremen mientras busca venganza contra quienes destruyeron a su familia.",
        "oppen": "La historia del físico J. Robert Oppenheimer y su papel en el desarrollo de la bomba atómica.",
    }
    BY_IMDB = {e["imdb"]: k for k, e in {**M, **S}.items()}

    def find_id(self, imdb, kind):  # la ficha: TMDB de mentiras (cualquier título)
        return sum(map(ord, imdb))

    def find(self, imdb, kind):
        key = self.BY_IMDB.get(imdb)
        if key not in self.OVERVIEWS:
            return None
        e = {**M, **S}[key]
        return {"overview": self.OVERVIEWS[key], "runtime": e["runtime"], "year": e["year"],
                "seasons": None, "episodes": e["episodes"]}


class DemoRawg:
    configured = True
    GAMES = {
        "new": [(1030300, "Hollow Knight: Silksong", 2025, 91), (1903340, "Clair Obscur: Expedition 33", 2025, 92),
                (1145350, "Hades II", 2025, 95), (2001120, "Split Fiction", 2025, 91), (1771300, "Kingdom Come: Deliverance II", 2025, 88)],
        "popular": [(271590, "Grand Theft Auto V", 2015, 96), (292030, "The Witcher 3: Wild Hunt", 2015, 93),
                    (1174180, "Red Dead Redemption 2", 2019, 93), (1086940, "Baldur's Gate 3", 2023, 96), (489830, "The Elder Scrolls V: Skyrim", 2016, 94)],
        "best": [(1086940, "Baldur's Gate 3", 2023, 96), (271590, "Grand Theft Auto V", 2015, 96), (620, "Portal 2", 2011, 95),
                 (1145360, "Hades", 2020, 93), (367520, "Hollow Knight", 2017, 87), (504230, "Celeste", 2018, 92)],
    }

    def games(self, which):
        return [{"rawg_id": appid, "title": t, "year": y, "released": f"{y}-01-01", "image": None, "metacritic": mc}
                for appid, t, y, mc in self.GAMES[which]]

    def steam_appid(self, rawg_id):
        return rawg_id  # en el demo, el id de RAWG es el de Steam

    def description(self, rawg_id):
        return ""


def install(catalog) -> None:
    """Pone los servicios de mentiras en «Para ti» (la lógica de foryou.py es la de verdad)."""
    from orbital import foryou

    fy = catalog.foryou
    fy.trakt, fy.tmdb, fy.rawg = DemoTrakt(), DemoTmdb(), DemoRawg()
    fy.logo_dark = lambda url: "tt11280740" in url  # el logo de Severance es negro
    original = fy._platform

    def platform(brand, kind):
        if brand not in DemoTmdb.PLATFORMS:
            return original(brand, kind)
        name = foryou.tmdb_api.PLATFORMS[brand][0]
        picks = [k for k in DemoTmdb.PLATFORMS[brand] if (k in S) == (kind == "series")]
        return [foryou.video_item((S if kind == "series" else M)[k], f"En {name}") for k in picks]

    fy._platform = platform

    # «Nuevo en tus plataformas» y los estudios, sin TMDB: títulos del demo.
    def fresh(kind):
        picks = {"series": ["wednesday", "andor", "penguin", "squid", "shogun", "lotus"], "movie": ["glass", "inside2", "dune2", "poor"]}[kind]
        names = ["Netflix", "Disney+", "HBO Max"]
        return [foryou.video_item((S if kind == "series" else M)[k], f"Nuevo en {names[n % 3]}") for n, k in enumerate(picks)]

    studios = {41077: ["past", "poor", "arrival"], 3: ["inside2", "spider"], 10342: ["spider", "inside2"], 420: ["spider", "dune1"],
               1: ["br", "dune2"], 3172: ["glass", "prestige"], 521: ["inside2", "spider"], 90733: ["parasite", "past"]}
    fy._fresh = fresh
    fy._studio = lambda company_id, name: [foryou.video_item(M[k], name) for k in studios.get(company_id, ["inter"])]

    # «Lo mejor del género» y «Temporadas», sin TMDB: títulos del demo (ids de IMDb de verdad).
    # Película y serie intercaladas: cada Top 10 del demo mezcla los dos, como TMDB.
    cycle = ["madmax", "andor", "batman", "stranger", "spider", "dark", "dune2", "breaking", "inception", "tlou",
             "oppen", "severance", "parasite", "wednesday", "br", "squid", "inter", "mando", "arrival", "shogun",
             "bear", "succession", "blackmirror", "saul", "silo", "loki", "hotd", "penguin", "lotus", "inside2",
             "prestige", "dune1", "glass", "poor", "past", "futurama"]
    pool = {**M, **S}

    def genre_bundle(slug, year):
        spec = foryou.tmdb_api.GENRE_BY_SLUG[slug]
        start = list(foryou.tmdb_api.GENRE_BY_SLUG).index(slug)
        items = []
        for n, key in enumerate([cycle[(start + i) % len(cycle)] for i in range(10)]):
            item = foryou.video_item(pool[key], f"N.º {n + 1} · {spec.title}")
            item["rank"] = n + 1
            items.append(item)
        return {"items": items, "title": f"Lo mejor de {spec.title} en {year}", "meta": "Las mejor calificadas del año"}

    seasons = {
        "halloween": ["stranger", "wednesday", "dark", "blackmirror", "batman", "prestige", "parasite", "silo", "squid", "glass"],
        "muertos": ["parasite", "dark", "stranger", "wednesday", "prestige", "silo", "breaking", "saul", "blackmirror", "glass"],
        "navidad": ["inside2", "bear", "succession", "lotus", "shogun", "futurama", "poor", "past", "loki", "mando"],
        "sanvalentin": ["past", "poor", "arrival", "succession", "bear", "lotus", "shogun", "severance", "inside2", "prestige"],
        "verano": ["dune2", "dune1", "spider", "madmax", "inter", "br", "mando", "loki", "andor", "tlou"],
    }

    def season_bundle(slug):
        spec = foryou.tmdb_api.SEASON_BY_SLUG[slug]
        items = [foryou.video_item(pool[key], spec.title) for key in seasons[slug]]
        return {"items": items, "title": spec.title, "meta": spec.blurb}

    fy._genre_bundle = genre_bundle
    fy._season_bundle = season_bundle

    # El Top 10 de Netflix y lo más visto por plataforma (JustWatch), sin internet: puestos, sube y baja y «Nuevo».
    def chart(keys, kind):
        pool = S if kind == "series" else M
        moves = [None, 2, -1, 0, 3, -2, None, 1, 0, -4]
        return [{**pool[k], "rank": n + 1, "movement": moves[n] if moves[n] is not None else None, "new": moves[n] is None}
                for n, k in enumerate(keys) if k in pool][:10]

    top = {"series": ["stranger", "wednesday", "squid", "blackmirror", "dark", "andor", "shogun", "bear", "silo", "tlou"],
           "movie": ["glass", "dune2", "oppen", "inside2", "batman", "past", "spider", "poor", "br", "inter"]}
    charts_api.netflix_entries = lambda region, kind, **_: chart(top[kind], kind)
    charts_api.fetch_justwatch_chart = lambda brand, region, kind, **_: chart(list(reversed(top[kind])), kind)
