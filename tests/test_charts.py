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
def test_netflix_movement_and_new_come_from_the_previous_week():
    rows = charts.fetch_netflix_top10("MX", open_url=_open_fixture("netflix-countries-sample.tsv"))
    unabomber, father = rows["movie"]
    assert unabomber["week"] == "2026-10-04"
    # La semana anterior (09-27) solo tenía «Vieja película»: ninguna estaba, así que son nuevas y sin flecha.
    assert (unabomber["movement"], unabomber["new"]) == (None, True)
    assert (father["movement"], father["new"]) == (None, True)


def test_netflix_movement_counts_places(tmp_path):
    tsv = ("country_name\tcountry_iso2\tweek\tcategory\tweekly_rank\tshow_title\tseason_title\tcumulative_weeks_in_top_10\n"
           "Mexico\tMX\t2026-09-27\tTV\t1\tA\tA: S1\t3\nMexico\tMX\t2026-09-27\tTV\t2\tB\tB: S1\t2\n"
           "Mexico\tMX\t2026-09-27\tTV\t3\tC\tC: S1\t1\n"
           "Mexico\tMX\t2026-10-04\tTV\t1\tC\tC: S1\t2\nMexico\tMX\t2026-10-04\tTV\t2\tA\tA: S1\t4\n"
           "Mexico\tMX\t2026-10-04\tTV\t3\tB\tB: S1\t3\nMexico\tMX\t2026-10-04\tTV\t4\tD\tD: S1\t1\n")
    rows = charts.fetch_netflix_top10("MX", open_url=lambda url: io.BytesIO(tsv.encode()))
    got = {e["title"]: (e["movement"], e["new"]) for e in rows["series"]}
    assert got == {"C": (2, False), "A": (-1, False), "B": (-1, False), "D": (None, True)}


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
