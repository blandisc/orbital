"""Charts: el Top 10 de Netflix (TSV) y lo más popular de JustWatch (GraphQL), con dobles de red
(nunca sale a internet). Fixtures en tests/fixtures/charts/."""

from __future__ import annotations

import io
import json
from pathlib import Path

import pytest

from orbital.foryou import Cache
from orbital.library import charts
from orbital.library.tmdb import Tmdb

FIXTURES = Path(__file__).parent / "fixtures" / "charts"


def _open_fixture(name):
    """Simula `charts._open`: devuelve el contenido del archivo como si fuera la respuesta HTTP."""
    data = (FIXTURES / name).read_bytes()
    return lambda url: io.BytesIO(data)


def _post_fixture(name, status=200):
    data = json.loads((FIXTURES / name).read_text())
    return lambda url, **kwargs: (status, data)


# ---------------------------------------------------------------- Netflix: el TSV
def test_netflix_top10_takes_the_most_recent_week():
    rows = charts.fetch_netflix_top10("MX", open_url=_open_fixture("netflix-countries-sample.tsv"))
    assert [m["title"] for m in rows["movie"]] == ["UNABOMBER", "What a Father!"]
    assert [m["rank"] for m in rows["movie"]] == [1, 2]
    assert rows["movie"][0]["weeks"] == 2  # de la semana más reciente (2026-10-04), no la de antes
    assert [s["title"] for s in rows["series"]] == ["Not a Stranger", "Physical 100: Mexico"]


def test_netflix_without_the_country_falls_back_to_global():
    open_url = _open_fixture("netflix-countries-sample.tsv")

    def opener(url):
        if "all-weeks-global" in url:
            return io.BytesIO((FIXTURES / "netflix-global-sample.tsv").read_bytes())
        return open_url(url)

    rows = charts.fetch_netflix_top10("CL", open_url=opener)  # Chile no está en la muestra
    # El global prefiere la edición en inglés (la que de verdad se enseña como «Top 10 global»).
    assert [m["title"] for m in rows["movie"]] == ["Global Movie One", "Global Movie Two"]
    assert [s["title"] for s in rows["series"]] == ["Global Show One", "Global Show Two"]


# ---------------------------------------------------------------- Netflix: título → IMDb
def test_resolve_imdb_with_tmdb(monkeypatch):
    tmdb = Tmdb("clave")
    monkeypatch.setattr(tmdb, "search", lambda kind, title, year=None: {"imdb": "tt6933238"} if title == "UNABOMBER" else None)
    assert charts.resolve_imdb("UNABOMBER", "movie", tmdb=tmdb, cinemeta=None) == "tt6933238"
    assert charts.resolve_imdb("Nada que exista", "movie", tmdb=tmdb, cinemeta=None) is None


def test_resolve_imdb_without_tmdb_uses_cinemeta():
    class FakeCinemeta:
        def search(self, kind, query):
            return [{"id": "tt0000111", "name": "Unabomber"}] if "nabom" in query.lower() else []

    assert charts.resolve_imdb("Unabomber", "movie", tmdb=None, cinemeta=FakeCinemeta()) == "tt0000111"
    assert charts.resolve_imdb("Nada que exista", "movie", tmdb=None, cinemeta=FakeCinemeta()) is None
    assert charts.resolve_imdb("Unabomber", "movie", tmdb=None, cinemeta=None) is None  # sin ninguna fuente


def test_netflix_entries_only_keeps_what_resolves_to_imdb():
    class FakeCinemeta:
        def search(self, kind, query):
            return [{"id": "tt6933238", "name": "UNABOMBER"}] if query == "UNABOMBER" else []  # "What a Father!" no se encuentra

    entries = charts.netflix_entries("MX", "movie", open_url=_open_fixture("netflix-countries-sample.tsv"), cinemeta=FakeCinemeta())
    assert [e["title"] for e in entries] == ["UNABOMBER"]
    assert entries[0]["imdb"] == "tt6933238" and entries[0]["rank"] == 1


# ---------------------------------------------------------------- JustWatch
def test_justwatch_popular_brings_rank_and_imdb_and_skips_unresolved():
    items = charts.fetch_justwatch_popular("netflix", "MX", "movie", post=_post_fixture("justwatch-popular-sample.json"))
    assert [i["title"] for i in items] == ["Unabomber", "What a Father!"]  # "Sin IMDb" se omite
    assert [i["rank"] for i in items] == [1, 2]
    assert items[0]["imdb"] == "tt6933238" and items[0]["year"] == 2026


def test_justwatch_unknown_brand_is_empty():
    assert charts.fetch_justwatch_popular("nope", "MX", "movie") == []


def test_justwatch_broken_schema_is_empty_without_raising(caplog):
    broken = lambda url, **kwargs: (200, {"data": {"popularTitles": {"edges": [{"node": {"objectType": "MOVIE"}}]}}})  # noqa: E731 - sin "content"
    assert charts.fetch_justwatch_popular("disney", "MX", "movie", post=broken) == []
    assert charts.fetch_justwatch_popular("disney", "MX", "series", post=broken) == []  # y sigue sin tronar


def test_justwatch_http_error_raises_charts_error():
    with pytest.raises(charts.ChartsError):
        charts.fetch_justwatch_popular("netflix", "MX", "movie", post=lambda url, **kwargs: (500, None))


# ---------------------------------------------------------------- caché: lo de antes se queda si falla la red
def test_cache_keeps_the_previous_value_when_the_network_fails():
    cache = Cache(clock=lambda: 0.0)
    good = _post_fixture("justwatch-popular-sample.json")
    first = cache.get("jw:netflix", 3600, lambda: charts.fetch_justwatch_popular("netflix", "MX", "movie", post=good))
    assert [i["title"] for i in first] == ["Unabomber", "What a Father!"]

    def fails(url, **kwargs):
        raise OSError("sin red")

    second = cache.get("jw:netflix", 3600, lambda: charts.fetch_justwatch_popular("netflix", "MX", "movie", post=fails))
    assert second == first  # la red falló: se queda con lo de la vez pasada, no se tira
