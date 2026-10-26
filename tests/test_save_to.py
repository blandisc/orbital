"""«Guardar en…» (como el iPhone): tu watchlist y tus listas de Trakt, con un Trakt falso (nunca sale a internet)."""

from __future__ import annotations

from types import SimpleNamespace

import pytest
from test_scrobble import Creds, FakeNet

from orbital import foryou
from orbital.library import trakt

SHOW = {"type": "show", "show": {"title": "The Office", "year": 2005, "ids": {"imdb": "tt0386676", "trakt": 1}}}
MOVIE = {"type": "movie", "movie": {"title": "Dune", "year": 2021, "ids": {"imdb": "tt1160419", "trakt": 2}}}


def client(monkeypatch, net):
    monkeypatch.setattr(trakt, "http_json", net)
    return trakt.Trakt("cid", "", Creds())


def test_adding_and_removing_from_the_watchlist_and_a_list(monkeypatch):
    net = FakeNet().on("/sync/watchlist", (201, {})).on("/users/me/lists/7/items", (201, {}))
    t = client(monkeypatch, net)
    t.set_watchlist("series", "tt0386676", True)
    t.set_watchlist("movie", "tt1160419", False)
    t.set_list_item("7", "series", "tt0386676", True)
    t.set_list_item("7", "series", "tt0386676", False)
    assert [(m, u.split("/api.trakt.tv")[-1].split("?")[0], b) for m, u, b in net.calls] == [
        ("POST", "/sync/watchlist", {"shows": [{"ids": {"imdb": "tt0386676"}}]}),
        ("POST", "/sync/watchlist/remove", {"movies": [{"ids": {"imdb": "tt1160419"}}]}),
        ("POST", "/users/me/lists/7/items", {"shows": [{"ids": {"imdb": "tt0386676"}}]}),
        ("POST", "/users/me/lists/7/items/remove", {"shows": [{"ids": {"imdb": "tt0386676"}}]}),
    ]
    with pytest.raises(trakt.TraktError):
        t.set_list_item("../x", "series", "tt0386676", True)  # nunca otra ruta
    with pytest.raises(trakt.TraktError):
        t.set_watchlist("series", "kitsu:1", True)


def test_a_trakt_error_is_reported(monkeypatch):
    t = client(monkeypatch, FakeNet().on("/sync/watchlist", (500, {})))
    with pytest.raises(trakt.TraktError):
        t.set_watchlist("series", "tt0386676", True)


def test_saved_in_says_where_the_title_is(monkeypatch):
    """En tu watchlist sí, en «Comedias» sí, en «Pendientes» no; una lista que falla no tumba a las demás."""
    lists = [{"name": "Comedias", "ids": {"trakt": 7}}, {"name": "Pendientes", "ids": {"trakt": 8}},
             {"name": "Rota", "ids": {"trakt": 9}}]
    net = (FakeNet().on(r"/users/me/lists$", (200, lists)).on("/users/me/lists/7/items", (200, [SHOW, MOVIE]))
           .on("/users/me/lists/8/items", (200, [MOVIE])).on("/users/me/lists/9/items", (500, None))
           .on("/sync/watchlist", (200, [SHOW])))
    t = client(monkeypatch, net)
    cleared = []
    fy = SimpleNamespace(trakt=t, cache=SimpleNamespace(clear=cleared.append))
    got = foryou.ForYou.saved_in(fy, "series", "tt0386676")
    assert got == {"trakt": True, "watchlist": True,
                   "lists": [{"id": "7", "name": "Comedias", "contains": True}, {"id": "8", "name": "Pendientes", "contains": False}]}
    net.on("/users/me/lists/8/items", (201, {}))
    foryou.ForYou.save_to(fy, "series", "tt0386676", "list:8", True)
    assert cleared == ["trakt:list:8"]  # esa lista se vuelve a pedir en la TV
    with pytest.raises(ValueError):
        foryou.ForYou.save_to(fy, "series", "tt0386676", "otra:1", True)
    unlinked = SimpleNamespace(trakt=trakt.Trakt("cid", "", Creds(linked=False)))
    assert foryou.ForYou.saved_in(unlinked, "series", "tt0386676") == {"trakt": False, "watchlist": False, "lists": []}
