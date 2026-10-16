"""Fichas en el idioma de Orbital (TMDB traduce lo que Cinemeta da en inglés)."""

from orbital.library import cinemeta, tmdb
from orbital.library.localize import Localizer, apply, tmdb_language

SERIES = {"id": "tt0386676", "name": "The Office", "description": "A mockumentary.", "genres": ["Comedy"],
          "videos": [{"id": "tt0386676:1:1", "season": 1, "episode": 1, "name": "Pilot", "overview": "Meet the staff."},
                     {"id": "tt0386676:1:2", "season": 1, "episode": 2, "name": "Diversity Day", "overview": "A seminar."}]}


class FakeTmdb:
    configured = True

    def __init__(self):
        self.calls = []

    def find_id(self, imdb, kind):
        self.calls.append(("find", imdb))
        return 2316

    def translation(self, kind, tmdb_id, language, episodes=False):
        self.calls.append(("translation", language, episodes))
        return {"title": "La oficina", "overview": "Un falso documental.", "genres": ["Comedia"],
                "episodes": {(1, 1): {"name": "Piloto", "overview": ""}, (1, 2): {"name": "Episodio 2", "overview": "Un taller."}}}


def test_language_codes():
    assert tmdb_language("es") == "es-MX" and tmdb_language("en") is None and tmdb_language("en-US") is None
    assert tmdb_language("fr") == "fr" and tmdb_language("") is None


def test_spanish_meta_keeps_what_tmdb_lacks():
    got = apply(SERIES, FakeTmdb().translation("series", 1, "es-MX", True))
    assert (got["name"], got["description"], got["genres"]) == ("La oficina", "Un falso documental.", ["Comedia"])
    first, second = got["videos"]
    assert (first["name"], first["overview"]) == ("Piloto", "Meet the staff.")  # sin sinopsis traducida: la original
    assert (second["name"], second["overview"]) == ("Diversity Day", "Un taller.")  # «Episodio 2» no tapa el título
    assert first["id"] == "tt0386676:1:1" and SERIES["videos"][0]["name"] == "Pilot"  # ids intactos; Cinemeta no se toca


def test_follows_orbital_language_and_caches():
    fake, lang = FakeTmdb(), ["es"]
    localizer = Localizer(fake, lambda: lang[0])
    assert localizer.meta("series", SERIES)["name"] == "La oficina"
    localizer.meta("series", SERIES)
    assert len(fake.calls) == 2  # la segunda vez, de memoria
    lang[0] = "en"  # Orbital en inglés: la ficha de Cinemeta tal cual
    assert localizer.meta("series", SERIES) is SERIES
    assert localizer.catalog("series", [SERIES]) == [SERIES]


def test_without_tmdb_key_nothing_changes():
    localizer = Localizer(tmdb.Tmdb(""), lambda: "es")
    assert localizer.meta("series", SERIES) is SERIES and localizer.catalog("movie", [SERIES]) == [SERIES]


def test_tmdb_down_leaves_english_and_does_not_insist():
    class Down(FakeTmdb):
        def find_id(self, imdb, kind):
            self.calls.append("find")
            raise tmdb.TmdbError("sin internet")

    down = Down()
    localizer = Localizer(down, lambda: "es")
    assert localizer.meta("movie", {"id": "tt1", "name": "Interstellar"})["name"] == "Interstellar"
    localizer.meta("movie", {"id": "tt1", "name": "Interstellar"})
    assert down.calls == ["find"]


def test_tmdb_translation_reads_seasons_in_batches(monkeypatch):
    asked = []

    def get(self, path, **params):
        asked.append((path, params.get("append_to_response")))
        if params.get("append_to_response"):
            return {"season/1": {"episodes": [{"episode_number": 1, "name": "Piloto", "overview": "Hola."}, "raro"]}}
        return {"name": "La oficina", "overview": "", "genres": [{"name": "Comedia"}, 5],
                "seasons": [{"season_number": 0}, {"season_number": 1}, {"season_number": "x"}]}

    monkeypatch.setattr(tmdb.Tmdb, "_get", get)
    found = tmdb.Tmdb("k").translation("series", 2316, "es-MX", episodes=True)
    assert found["title"] == "La oficina" and found["genres"] == ["Comedia"]
    assert found["episodes"] == {(1, 1): {"name": "Piloto", "overview": "Hola."}}
    assert asked[1] == ("/tv/2316", "season/0,season/1")


def test_cinemeta_meta_goes_through_the_localizer(monkeypatch):
    monkeypatch.setattr(cinemeta.Cinemeta, "_get", lambda self, path, base=None: {"meta": dict(SERIES)})
    client = cinemeta.Cinemeta()
    client.localize = Localizer(FakeTmdb(), lambda: "es").meta
    assert client.meta("series", "tt0386676")["name"] == "La oficina"
    assert cinemeta.seasons(client.meta("series", "tt0386676"))[0]["episodes"][0]["title"] == "Piloto"


def test_your_stremio_account_keeps_the_original_title(library, monkeypatch):
    """Lo que Orbital crea en tu cuenta de Stremio (avance, Mi lista) va con el título de Cinemeta:
    Stremio y la app del celular no deben ver «La oficina» por haber visto la ficha en español."""
    from orbital.library import stremio_api

    monkeypatch.setattr(cinemeta.Cinemeta, "_get", lambda self, path, base=None: {"meta": dict(SERIES)})
    library.watch.cinemeta.localize = Localizer(FakeTmdb(), lambda: "es").meta
    library.credentials.set("stremio_auth_key", "k")
    saved = []
    monkeypatch.setattr(stremio_api.StremioAPI, "library_item", lambda self, auth, mid: None)
    monkeypatch.setattr(stremio_api.StremioAPI, "save_library_item", lambda self, auth, item: saved.append(item["name"]))
    monkeypatch.setattr(library.watch, "refresh_stremio", lambda background=False: None)
    library.watch.set_in_library("series", "tt0386676", True)
    library.watch._save_progress({"kind": "series", "meta_id": "tt0386676", "video_id": "tt0386676:1:1"},
                                 position=600, duration=1300, watched=600, refresh=False)
    assert saved == ["The Office", "The Office"]
    assert library.watch.cinemeta.meta("series", "tt0386676")["name"] == "La oficina"  # la ficha, en español
