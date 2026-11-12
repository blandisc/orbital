"""Una sola escala de clasificación por idioma (Fernando, 12 nov 2026): en español latino, la mexicana; en cualquier otro,
la de EE. UU.; nunca el dato crudo de otro país. Los casos de design/clasificaciones.json son los mismos que corre el
iPhone (CertificationTests)."""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from orbital.library import certification

TABLE = json.loads((Path(__file__).parents[1] / "design" / "clasificaciones.json").read_text(encoding="utf-8"))


@pytest.mark.parametrize("case", TABLE["cases"], ids=lambda c: c["why"])
def test_the_shared_cases(case):
    assert certification.resolve(case["mx"], case["us"], case["kind"], case["language"]) == case["expect"], case["why"]


def test_the_tv_reads_the_shared_table():
    assert certification.TABLE == TABLE
    assert TABLE["version"] == 1


def test_every_conversion_lands_on_the_other_scale():
    scales = TABLE["scales"]
    for kind in ("movie", "series"):
        assert set(TABLE["to_mexico"][kind]) == set(scales["us"][kind]), f"to_mexico.{kind}: toda la escala de EE. UU."
        assert set(TABLE["to_mexico"][kind].values()) <= set(scales["mexico"])
        assert set(TABLE["to_us"][kind]) == set(scales["mexico"]), f"to_us.{kind}: toda la escala mexicana"
        assert set(TABLE["to_us"][kind].values()) <= set(scales["us"][kind])


def test_without_the_table_there_is_no_rating_never_another_countrys(tmp_path):
    assert certification.load_table(tmp_path / "no-esta.json") == {}
    assert certification.resolve("B15", "R", "movie", "es", table={}) is None


def test_the_title_page_resolves_after_the_cache_so_a_language_change_takes(monkeypatch):
    """La caché guarda la clasificación cruda (México y EE. UU.); la escala sale del idioma de las fichas de ahora."""
    from orbital.foryou.titles import _Titles

    class Cache:
        def get(self, key, ttl, load):
            assert key.startswith("extras3:"), "las de extras2 traían la clasificación ya elegida"
            return load()

    class Tmdb:
        configured = True

        def find_id(self, imdb, kind):
            return 1

        def extras(self, kind, tmdb_id, region):
            return {"ratings": {"MX": None, "US": "R"}, "collection": None}

    language = ["es"]

    class Localizer:
        def language(self):
            return language[0]

    class Watch:
        localizer = Localizer()

    class Services:
        watch = Watch()

    class Trakt:
        configured = False

    page = _Titles.__new__(_Titles)
    page.cache, page.tmdb, page.trakt, page.region, page.services = Cache(), Tmdb(), Trakt(), "MX", Services()  # type: ignore[assignment]
    out = page.title_extras("movie", "tt0000001")
    assert out["certification"] == "B15" and "ratings" not in out
    language[0] = "en"
    assert page.title_extras("movie", "tt0000001")["certification"] == "R"
