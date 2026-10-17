"""Charts: el Top 10 de Netflix (su página por país) y lo más popular de JustWatch (GraphQL), con dobles de red
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


# ---------------------------------------------------------------- Netflix: su página por país
def _pages(seen=None):
    """La página de México (series) de esta semana y, con ?week=, la de la anterior (muestras reales en fixtures)."""
    def opener(url):
        if seen is not None:
            seen.append(url)
        name = "netflix_mexico_tv_prev.html" if "?week=" in url else "netflix_mexico_tv.html"
        return io.BytesIO((FIXTURES / name).read_bytes())
    return opener


def test_netflix_page_url_by_country_and_kind():
    assert charts.netflix_page_url("MX", "series") == "https://www.netflix.com/tudum/top10/mexico/tv"
    assert charts.netflix_page_url("mx", "movie") == "https://www.netflix.com/tudum/top10/mexico"
    assert charts.netflix_page_url("ZZ", "movie") == "https://www.netflix.com/tudum/top10"  # sin página propia: la global
    assert charts.netflix_page_url("MX", "series", "2026-10-04").endswith("/mexico/tv?week=2026-10-04")


def test_netflix_page_parses_the_table_and_its_weeks():
    rows, weeks = charts.parse_netflix_page((FIXTURES / "netflix_mexico_tv.html").read_text(encoding="utf-8"))
    assert len(rows) == 10 and rows[0] == {"title": "Below: Limited Series", "rank": 1, "weeks": 1}
    assert weeks[-1] == "2026-10-11"


def test_netflix_titles_lose_the_season_to_find_the_show():
    assert charts.show_title("Below: Limited Series") == "Below"
    assert charts.show_title("Physical 100: Mexico: Season 1") == "Physical 100: Mexico"
    assert charts.show_title("Monster: The Lizzie Borden Story: Season 1") == "Monster: The Lizzie Borden Story"
    assert charts.show_title("UNABOMBER") == "UNABOMBER"


def test_netflix_top10_takes_this_week_and_compares_with_the_last():
    seen = []
    rows = charts.fetch_netflix_top10("MX", "series", open_url=_pages(seen))
    assert seen == ["https://www.netflix.com/tudum/top10/mexico/tv", "https://www.netflix.com/tudum/top10/mexico/tv?week=2026-10-04"]
    first = rows[0]
    assert (first["title"], first["rank"], first["new"], first["movement"], first["week"]) == ("Below", 1, True, None, "2026-10-11")
    stranger = next(r for r in rows if r["title"] == "Not a Stranger")
    assert (stranger["rank"], stranger["movement"], stranger["new"]) == (3, -2, False)  # era la 1 la semana pasada


def test_netflix_without_last_week_has_no_arrows():
    def opener(url):
        if "?week=" in url:
            raise OSError("sin red")
        return io.BytesIO((FIXTURES / "netflix_mexico_tv.html").read_bytes())
    rows = charts.fetch_netflix_top10("MX", "series", open_url=opener)
    assert all(r["movement"] is None for r in rows)


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
            return [{"id": "tt9999001", "name": "Below"}] if query == "Below" else []  # el resto no se encuentra

    entries = charts.netflix_entries("MX", "series", open_url=_pages(), cinemeta=FakeCinemeta())
    assert [e["title"] for e in entries] == ["Below"]  # se busca sin «: Limited Series»
    assert entries[0]["imdb"] == "tt9999001" and entries[0]["rank"] == 1


# ---------------------------------------------------------------- JustWatch
def test_justwatch_chart_ranks_within_the_platform_and_skips_unresolved():
    items = charts.fetch_justwatch_chart("netflix", "MX", "movie", post=_post_fixture("justwatch-chart-sample.json"))
    assert [i["title"] for i in items] == ["Unabomber", "What a Father!"]  # "Sin IMDb" se omite
    assert [i["rank"] for i in items] == [1, 2]  # su lugar en la plataforma, no el 14 y 47 del ranking general
    assert items[0]["imdb"] == "tt6933238" and items[0]["year"] == 2026


def test_justwatch_unknown_brand_is_empty():
    assert charts.fetch_justwatch_chart("nope", "MX", "movie") == []


def test_justwatch_broken_schema_is_empty_without_raising(caplog):
    broken = lambda url, **kwargs: (200, {"data": {"streamingCharts": {"edges": [{"node": {"objectType": "MOVIE"}}]}}})  # noqa: E731 - sin "content"
    assert charts.fetch_justwatch_chart("disney", "MX", "movie", post=broken) == []
    assert charts.fetch_justwatch_chart("disney", "MX", "series", post=broken) == []  # y sigue sin tronar


def test_justwatch_http_error_raises_charts_error():
    with pytest.raises(charts.ChartsError):
        charts.fetch_justwatch_chart("netflix", "MX", "movie", post=lambda url, **kwargs: (500, None))


# ---------------------------------------------------------------- caché: lo de antes se queda si falla la red
def test_cache_keeps_the_previous_value_when_the_network_fails():
    cache = Cache(clock=lambda: 0.0)
    good = _post_fixture("justwatch-chart-sample.json")
    first = cache.get("jw:netflix", 3600, lambda: charts.fetch_justwatch_chart("netflix", "MX", "movie", post=good))
    assert [i["title"] for i in first] == ["Unabomber", "What a Father!"]

    def fails(url, **kwargs):
        raise OSError("sin red")

    second = cache.get("jw:netflix", 3600, lambda: charts.fetch_justwatch_chart("netflix", "MX", "movie", post=fails))
    assert second == first  # la red falló: se queda con lo de la vez pasada, no se tira


def test_justwatch_asks_for_the_daily_chart_of_that_platform():
    sent = {}

    def post(url, **kwargs):
        sent.update(kwargs["body"])
        return 200, {"data": {"streamingCharts": {"edges": []}}}

    charts.fetch_justwatch_chart("disney", "mx", "series", post=post)
    assert sent["operationName"] == "GetStreamingCharts" and "streamingCharts" in sent["query"]
    assert sent["variables"]["country"] == "MX" and sent["variables"]["first"] == charts.JUSTWATCH_FETCH
    assert sent["variables"]["filter"] == {"category": "DAILY_POPULARITY_SAME_CONTENT_TYPE", "objectType": "SHOW", "packages": ["dnp"]}


# ---------------------------------------------------------------- sube y baja
def test_daily_snapshots_give_movement_and_survive_a_restart(tmp_path):
    from datetime import date
    db = tmp_path / "charts.sqlite"

    def entries(*imdbs):
        return [{"imdb": i, "title": i, "rank": n + 1} for n, i in enumerate(imdbs)]

    first = charts.ChartSnapshots(db).annotate("jw:disney", "movie", entries("tt1", "tt2", "tt3"), today=date(2026, 10, 14))
    assert [(e["movement"], e["new"]) for e in first] == [(None, False)] * 3  # sin foto anterior: sin flechas ni «Nuevo»
    again = charts.ChartSnapshots(db).annotate("jw:disney", "movie", entries("tt1", "tt2", "tt3"), today=date(2026, 10, 14))
    assert [e["movement"] for e in again] == [None] * 3  # el mismo día no se compara consigo mismo
    # Otro proceso (Orbital se reinició), al día siguiente: tt3 subió dos, tt1 bajó uno, tt9 es nuevo.
    nxt = charts.ChartSnapshots(db).annotate("jw:disney", "movie", entries("tt3", "tt1", "tt9"), today=date(2026, 10, 15))
    assert {e["imdb"]: (e["movement"], e["new"]) for e in nxt} == {"tt3": (2, False), "tt1": (-1, False), "tt9": (None, True)}
    other = charts.ChartSnapshots(db).annotate("jw:hbo", "movie", entries("tt3"), today=date(2026, 10, 15))
    assert other[0]["movement"] is None  # cada lista con su propia historia


def test_old_snapshots_are_pruned(tmp_path):
    import sqlite3
    from datetime import date
    db = tmp_path / "charts.sqlite"
    snaps = charts.ChartSnapshots(db)
    snaps.annotate("jw:disney", "movie", [{"imdb": "tt1", "rank": 1}], today=date(2026, 1, 1))
    snaps.annotate("jw:disney", "movie", [{"imdb": "tt1", "rank": 1}], today=date(2026, 6, 1))
    days = {d for (d,) in sqlite3.connect(db).execute("SELECT day FROM chart_snapshot")}
    assert days == {"2026-06-01"}
