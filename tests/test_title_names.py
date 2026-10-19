"""El nombre de cada título en tu idioma, el mismo en todos lados (TitleNames)."""

from __future__ import annotations

import time

from orbital.library import localize


class FakeLocalizer:
    def __init__(self, lang="es-MX"):
        self.lang = lang
        self.asked = []

    @property
    def active(self):
        return self.lang

    def _translation(self, kind, imdb, lang, episodes):
        self.asked.append((kind, imdb, lang))
        return {"title": "Dune: Parte dos"} if imdb == "tt15239678" else {}


def wait_for(check, seconds=3.0):
    end = time.time() + seconds
    while time.time() < end and not check():
        time.sleep(.02)
    return check()


def test_a_missing_name_is_fetched_in_the_background_and_saved(tmp_path):
    loc = FakeLocalizer()
    path = tmp_path / "title-names.json"
    names = localize.TitleNames(loc, path)
    names.SAVE_DELAY = 0.01
    assert names.name("movie", "tt15239678") is None  # la primera vez no hace esperar
    assert wait_for(lambda: names.name("movie", "tt15239678") == "Dune: Parte dos")
    assert wait_for(path.exists)
    assert localize.TitleNames(loc, path).name("movie", "tt15239678") == "Dune: Parte dos"  # se guarda en disco
    names.name("movie", "tt0000001")
    names.name("movie", "tt0000001")
    assert wait_for(lambda: loc.asked.count(("movie", "tt0000001", "es-MX")) == 1)  # lo que no tiene, no se pide dos veces


def test_english_or_no_tmdb_leaves_names_as_they_come(tmp_path):
    names = localize.TitleNames(FakeLocalizer(lang=None), tmp_path / "n.json")
    assert names.name("movie", "tt15239678") is None
    names.remember("tt15239678", "Dune: Parte dos")
    assert names.name("movie", "tt15239678") is None


def test_the_title_page_teaches_the_name_to_everything_else(tmp_path):
    loc = FakeLocalizer()
    names = localize.TitleNames(loc, None)
    names.remember("tt11280740", "Separación")
    assert names.name("series", "tt11280740") == "Separación"
    assert names.name("game", "tt11280740") is None
