"""«Guardar en…» (como el iPhone): tu watchlist, tus favoritos y tus listas de Trakt, con un Trakt falso (nunca sale a
internet)."""

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
           .on("/sync/watchlist", (200, [SHOW])).on("/sync/favorites/movies", (200, [MOVIE]))
           .on("/sync/favorites/shows", (200, [])))
    t = client(monkeypatch, net)
    cleared = []
    fy = SimpleNamespace(trakt=t, cache=SimpleNamespace(clear=cleared.append))
    got = foryou.ForYou.saved_in(fy, "series", "tt0386676")
    assert got == {"trakt": True, "watchlist": True, "favorite": False,
                   "lists": [{"id": "7", "name": "Comedias", "contains": True}, {"id": "8", "name": "Pendientes", "contains": False}]}
    net.on("/users/me/lists/8/items", (201, {}))
    foryou.ForYou.save_to(fy, "series", "tt0386676", "list:8", True)
    assert cleared == ["trakt:list:8"]  # esa lista se vuelve a pedir en la TV
    with pytest.raises(ValueError):
        foryou.ForYou.save_to(fy, "series", "tt0386676", "otra:1", True)
    unlinked = SimpleNamespace(trakt=trakt.Trakt("cid", "", Creds(linked=False)))
    assert foryou.ForYou.saved_in(unlinked, "series", "tt0386676") == {"trakt": False, "watchlist": False, "favorite": False, "lists": []}
    assert foryou.ForYou.saved_in(fy, "movie", "tt1160419")["favorite"] is True


# ---------------------------------------------------------------- favoritos de Trakt (el corazón)
def favorite(row: dict, listed_at: str) -> dict:
    return {**row, "listed_at": listed_at, "rank": 1}


def test_favorites_join_movies_and_shows_newest_first(monkeypatch):
    """Películas y series juntas, lo último que marcaste primero; sin IMDb no entra."""
    nameless = {"type": "movie", "movie": {"title": "Sin IMDb", "ids": {"trakt": 5}}}
    net = (FakeNet().on("/sync/last_activities", (200, {"favorites": {"updated_at": "2026-10-20T00:00:00.000Z"}}))
           .on("/sync/favorites/movies", (200, [favorite(MOVIE, "2026-01-01T00:00:00.000Z"), favorite(nameless, "2026-09-01T00:00:00.000Z")]))
           .on("/sync/favorites/shows", (200, [favorite(SHOW, "2026-06-01T00:00:00.000Z")])))
    found = client(monkeypatch, net).favorites()
    assert [(e["title"], e["kind"]) for e in found] == [("The Office", "series"), ("Dune", "movie")]
    assert any("extended=full" in u for _, u, _ in net.calls if "/sync/favorites/" in u)


def test_favorites_are_cached_and_reloaded_only_when_trakt_says_they_changed(monkeypatch):
    stamp = {"value": "2026-10-20T00:00:00.000Z"}
    net = (FakeNet().on("/sync/last_activities", lambda url, body: (200, {"favorites": {"updated_at": stamp["value"]}}))
           .on("/sync/favorites/movies", (200, [favorite(MOVIE, "2026-01-01T00:00:00.000Z")]))
           .on("/sync/favorites/shows", (200, [])))
    t = client(monkeypatch, net)

    def downloads() -> int:
        return sum(1 for _, u, _ in net.calls if "/sync/favorites/movies" in u)
    t.favorites(now=1000)
    t.favorites(now=1030)
    assert downloads() == 1  # dentro del minuto, de lo guardado
    t.favorites(now=1100)
    assert downloads() == 1  # pasado el minuto, la marca no cambió: no se bajan otra vez
    stamp["value"] = "2026-10-28T00:00:00.000Z"
    t.favorites(now=1200)
    assert downloads() == 2  # cambiaron (en el iPhone, en trakt.tv): se bajan


def test_adding_and_removing_a_favorite_and_the_hundred_limit(monkeypatch):
    net = (FakeNet().on(r"/sync/favorites/remove", (200, {})).on(r"/sync/favorites$", (201, {}))
           .on("/sync/last_activities", (200, {})).on("/sync/favorites/(movies|shows)", (200, [])))
    t = client(monkeypatch, net)
    t.favorites(now=1000)
    t.set_favorite("movie", "tt1160419", True)
    t.set_favorite("series", "tt0386676", False)
    sent = [(u.split("/api.trakt.tv")[-1], b) for m, u, b in net.calls if m == "POST"]
    assert sent == [("/sync/favorites", {"movies": [{"ids": {"imdb": "tt1160419"}}]}),
                    ("/sync/favorites/remove", {"shows": [{"ids": {"imdb": "tt0386676"}}]})]
    t.favorites(now=1001)
    assert sum(1 for _, u, _ in net.calls if "/sync/favorites/movies" in u) == 2  # tras cambiarlos, la lectura es nueva
    with pytest.raises(trakt.TraktError):
        t.set_favorite("series", "kitsu:1", True)  # nunca otra ruta
    # Ya hay 100: Trakt responde 420 y se dice qué hacer (no «HTTP 420»).
    full = client(monkeypatch, FakeNet().on("/sync/favorites", (420, {})))
    with pytest.raises(trakt.TraktFavoritesFull, match="Llegaste a 100 favoritos en Trakt: quita uno para agregar otro."):
        full.set_favorite("movie", "tt1160419", True)
    broken = client(monkeypatch, FakeNet().on("/sync/favorites", (500, {})))
    with pytest.raises(trakt.TraktError, match="HTTP 500"):
        broken.set_favorite("movie", "tt1160419", True)


def test_save_to_favorites_goes_to_trakt(monkeypatch):
    net = FakeNet().on(r"/sync/favorites$", (201, {}))
    t = client(monkeypatch, net)
    fy = SimpleNamespace(trakt=t, cache=SimpleNamespace(clear=lambda key: None))
    foryou.ForYou.save_to(fy, "movie", "tt1160419", "favorites", True)
    assert net.calls[-1][0] == "POST" and net.calls[-1][1].endswith("/sync/favorites")
