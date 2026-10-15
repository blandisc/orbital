"""«Para ti» en el demo: Trakt, TMDB y RAWG de mentiras (títulos reales, sin cuenta ni internet).

Las imágenes sí vienen de internet al verlas en el navegador (metahub y la tienda de Steam), como
en Orbital de verdad. Conectar Trakt funciona: el código se «confirma» solo a los pocos segundos.
"""

from __future__ import annotations

import time

from orbital.library import trakt as trakt_api


def _m(imdb, title, year, runtime):
    return {"kind": "movie", "imdb": imdb, "title": title, "year": year, "runtime": runtime, "episodes": None, "overview": "", "trakt_id": None}


def _s(imdb, title, year, episodes, trakt_id=None):
    return {"kind": "series", "imdb": imdb, "title": title, "year": year, "runtime": None, "episodes": episodes, "overview": "", "trakt_id": trakt_id}


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


class DemoTrakt:
    configured = True

    def __init__(self) -> None:
        self.linked = False
        self._linking_since = 0.0

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

    def watchlist(self):
        return [M["dune2"], M["oppen"], M["past"], S["tlou"], M["batman"], M["parasite"], M["prestige"], S["breaking"]]

    def lists(self):
        # Un nombre largo de verdad (como las listas que la gente copia en Trakt): no debe cortarse feo.
        return [{"id": "1", "name": "The 25 Best Sci-Fi Movies of the 21st Century (So Far)"}]

    def list_items(self, list_id):
        return [_m("tt1136608", "District 9", 2009, 112), M["arrival"], M["inter"], M["inception"], M["dune1"], M["br"], S["dark"]]

    def trending(self, kind, limit=30):
        # Todo el catálogo de mentiras, como Trakt de verdad (decenas): con 14, el mosaico se repetía.
        first = ("tlou", "severance", "stranger", "blackmirror", "bear", "shogun", "penguin", "lotus") if kind == "series" \
            else ("dune2", "oppen", "inside2", "batman", "glass", "poor")
        pool = S if kind == "series" else M
        return [pool[k] for k in first] + [v for k, v in pool.items() if k not in first]

    def popular(self, kind, limit=30):
        return [S[k] for k in ("breaking", "stranger", "tlou", "bear", "succession", "blackmirror", "dark", "saul")] if kind == "series" \
            else [M[k] for k in ("oppen", "dune2", "inter", "inception", "spider", "batman", "parasite", "madmax")]

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

    def discover(self, kind, provider_id, region):
        brand = list(self.PLATFORMS)[provider_id - 1]
        return [{"id": n, "key": k} for n, k in enumerate(self.PLATFORMS[brand]) if (k in S) == (kind == "series")]

    def details(self, kind, tmdb_id):
        raise LookupError  # no se usa: el demo responde en _platform

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
