"""«Aprobadas por la crítica» en Para ti: Rotten Tomatoes vía MDBList (películas) y una lista pública de Trakt (series).
Con la red falsa: nunca sale a internet."""

from __future__ import annotations

from test_foryou import FakeNet, make_foryou, net, show  # noqa: F401 - fixtures de Para ti

from orbital.library import mdblist


def test_both_shapes_mdblist_answers_become_titles():
    flat = [{"imdb_id": "tt1", "title": "Uno", "mediatype": "movie", "release_year": 2026},
            {"imdb_id": None, "title": "Sin IMDb", "mediatype": "movie"},
            {"imdb_id": "tt1", "title": "Repetida", "mediatype": "movie"}]
    assert [(e["imdb"], e["kind"], e["year"]) for e in mdblist.entries(flat)] == [("tt1", "movie", 2026)]
    split = {"movies": [{"imdb_id": "tt2", "title": "Dos", "mediatype": "movie"}],
             "shows": [{"imdb_id": "tt3", "title": "Tres", "mediatype": "show"}]}
    assert [(e["imdb"], e["kind"]) for e in mdblist.entries(split)] == [("tt2", "movie"), ("tt3", "series")]
    assert mdblist.parse_ref("https://mdblist.com/lists/tbotcotw/recent-certified-fresh/") == ("tbotcotw", "recent-certified-fresh")
    assert mdblist.parse_ref("nada") is None


def test_with_a_key_it_uses_the_api_and_without_it_the_public_json(monkeypatch):
    fake = FakeNet().on("GET", r"api\.mdblist\.com/lists/u/l/items", (200, [{"imdb_id": "tt1", "title": "Uno", "mediatype": "movie"}]))
    fake.on("GET", r"mdblist\.com/lists/u/l/json", (200, [{"imdb_id": "tt2", "title": "Dos", "mediatype": "movie"}]))
    monkeypatch.setattr(mdblist, "http_json", fake)
    assert [e["imdb"] for e in mdblist.MdbList("k").list_items("u/l")] == ["tt1"]
    assert "apikey=k" in fake.calls[0][1]
    assert [e["imdb"] for e in mdblist.MdbList("").list_items("u/l")] == ["tt2"]


def test_critics_shelf_in_para_ti(net, make_foryou, monkeypatch):  # noqa: F811
    monkeypatch.setattr(mdblist, "http_json", net)
    net.on("GET", r"mdblist\.com/lists/tbotcotw/recent-certified-fresh/json",
           (200, [{"imdb_id": "tt5", "title": "Fresca", "mediatype": "movie", "release_year": 2026}]))
    net.on("GET", r"/users/truckclancy/lists/rotten-tomatoes-certified-fresh-tv-shows-ranked-by-tomatometer-score/items",
           (200, [{"type": "show", "show": show("Severance", "tt11280740")}]))
    fy = make_foryou()
    entry = next(e for e in fy.lists() if e["id"] == "critics")
    assert entry["source"] == "Rotten Tomatoes" and entry["split"] is True
    assert [i["title"] for i in fy.list_items("critics", "movie")] == ["Fresca"]
    assert [i["title"] for i in fy.list_items("critics", "series")] == ["Severance"]
