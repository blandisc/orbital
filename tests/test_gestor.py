"""El gestor tipo Trakt en la TV (olas 1 y 2, como el iPhone): el estado de un título, el tablero de Guardado, «La dejé»
con las dejadas de trakt.tv, la cola sin internet, elegir varios y tus listas. Con un Trakt falso (nunca sale a internet).
Las mismas reglas que `TitleStatusTests`, `SavedBoardTests`, `DroppedTraktTests`, `SavedBatchTests` y `SavedListsTests`."""

from __future__ import annotations

import time

from fastapi.testclient import TestClient
from test_foryou import make_foryou, movie, net, show  # noqa: F401 - las piezas de «Para ti» (fixtures)

from orbital import gestor
from orbital.library import trakt
from orbital.server import create_app
from orbital.trakt_outbox import TraktOutbox, retryable

DAY = 24 * 3600


def client(library):
    return TestClient(create_app(library.config, library), base_url="http://127.0.0.1:8710", client=("127.0.0.1", 5000))


# --- G1-A: el estado -------------------------------------------------------------------------------------------------
def test_status_follows_the_iphone_rules():
    s = gestor.title_status
    assert s(series=False, in_list=False, watched=0, released=1, upcoming=False, dropped=False) == "none"
    assert s(series=False, in_list=True, watched=1, released=1, upcoming=False, dropped=False) == "in_list"  # otra vez
    assert s(series=False, in_list=False, watched=1, released=1, upcoming=False, dropped=False) == "watched"
    assert s(series=True, in_list=True, watched=0, released=10, upcoming=False, dropped=False) == "in_list"
    assert s(series=True, in_list=True, watched=3, released=10, upcoming=False, dropped=False) == "watching"
    assert s(series=True, in_list=False, watched=10, released=10, upcoming=True, dropped=False) == "watching"  # al día
    assert s(series=True, in_list=False, watched=10, released=10, upcoming=False, dropped=False) == "watched"
    assert s(series=True, in_list=True, watched=3, released=10, upcoming=False, dropped=True) == "dropped"


def test_moves_and_batch_actions_match_the_iphone():
    assert gestor.moves("movie", "in_list") == ["watched", "dropped"]
    assert gestor.moves("series", "watching") == ["in_list", "dropped"]
    assert gestor.moves("series", "dropped") == ["in_list", "watching"]
    assert gestor.moves("movie", "watched") == ["in_list"]
    assert gestor.batch_actions("watchlist") == ["watched", "drop", "move", "remove"]
    assert gestor.batch_actions("list:7") == ["watched", "drop", "move", "to_watchlist", "remove"]
    assert gestor.batch_actions("watched") == ["to_watchlist", "move"]  # sin «Quitar»: borraría cuándo la viste
    assert gestor.batch_actions("dropped") == ["resume", "to_watchlist"]


# --- G2-A: el tablero ------------------------------------------------------------------------------------------------
def test_board_piles_like_saved_board():
    now = 1_800_000_000.0
    wl = [{"kind": "movie", "imdb": "tt1", "title": "Dune"}, {"kind": "series", "imdb": "tt9", "title": "Dejada"}]
    watched = {"movies": {"tt2": {"kind": "movie", "imdb": "tt2", "title": "Flow", "last": now - DAY}},
               "shows": {"tt3": {"kind": "series", "imdb": "tt3", "title": "The Bear", "fraction": .4, "last": now - DAY},
                         "tt4": {"kind": "series", "imdb": "tt4", "title": "Al día", "fraction": 1, "airing": True, "last": now - 2 * DAY},
                         "tt5": {"kind": "series", "imdb": "tt5", "title": "Terminada", "fraction": 1, "last": now - 3 * DAY},
                         "tt6": {"kind": "series", "imdb": "tt6", "title": "Olvidada", "fraction": .2, "last": now - 300 * DAY}}}
    board = gestor.build_board(wl, watched, {"tt9"}, now=now)
    ids = {k: [e["imdb"] for e in v] for k, v in board.items() if k != "last"}
    assert ids == {"in_list": ["tt1"], "watching": ["tt3", "tt4"], "stale": ["tt6"], "watched": ["tt2", "tt5"], "dropped": ["tt9"]}


# --- la cola de Trakt ------------------------------------------------------------------------------------------------
class FakeClient:
    linked = True

    def __init__(self) -> None:
        self.calls: list = []
        self.down = False

    def set_items(self, target, items, add):
        if self.down:
            raise trakt.TraktError("No pude conectar con Trakt: sin red")
        self.calls.append(("items", target, items, add))

    def set_hidden(self, imdbs, hidden, sections):
        if self.down:
            raise trakt.TraktError("Trakt respondió HTTP 503", 503)
        self.calls.append(("hidden", imdbs, hidden, sections))


def test_outbox_keeps_the_last_choice_and_sends_one_batch_per_list():
    box: dict = {}
    outbox = TraktOutbox(lambda: box.get("v"), lambda v: box.update(v=v))
    for imdb in ("tt1", "tt2", "tt3"):
        outbox.enqueue({"target": "watchlist", "imdb": imdb, "kind": "movie", "add": False})
    outbox.enqueue({"target": "watchlist", "imdb": "tt1", "kind": "movie", "add": False})  # lo último cuenta, una vez
    outbox.enqueue({"target": "hidden", "imdb": "tt9", "kind": "series", "add": True, "sections": ["calendar"]})
    t = FakeClient()
    t.down = True
    assert outbox.flush(t) == 0 and len(outbox.pending) == 4  # sigue sin red: todo espera
    t.down = False
    assert outbox.flush(t) == 4
    assert t.calls == [("items", "watchlist", [("movie", "tt2"), ("movie", "tt3"), ("movie", "tt1")], False),
                       ("hidden", ["tt9"], True, ("calendar",))]
    assert outbox.pending == []


def test_only_what_can_work_later_waits():
    assert retryable(trakt.TraktError("No pude conectar con Trakt: x"))
    assert retryable(trakt.TraktError("Trakt respondió HTTP 429", 429)) and retryable(trakt.TraktAuthError("x"))
    assert not retryable(trakt.TraktError("Trakt respondió HTTP 404", 404))
    assert not retryable(trakt.TraktError("Título inválido"))


# --- de punta a punta, por la API ------------------------------------------------------------------------------------
def test_dropping_a_series_hides_it_in_trakt_with_dropped_and_waits_offline(library, make_foryou, net):  # noqa: F811
    down = {"on": False}

    def hide(url, body):
        if down["on"]:
            raise OSError("sin red")
        return 201, {}

    net.on("POST", r"/users/hidden/", hide)
    net.on("GET", r"/sync/watchlist", (200, []))
    make_foryou(linked=True)
    with client(library) as c:
        assert c.post("/api/foryou/drop", json={"kind": "series", "id": "tt0386676"}).json() == {"ok": True, "queued": False}
        sent = [u.split("/users/hidden/")[1] for m, u, _ in net.calls if "/users/hidden/" in u and m == "POST"]
        assert sent == ["calendar", "progress_watched", "dropped"]
        assert c.get("/api/foryou/follow", params={"id": "tt0386676"}).json() == {"dropped": True, "following": False}
        # Sin internet: queda hecha y espera
        down["on"] = True
        assert c.post("/api/foryou/drop", json={"kind": "series", "id": "tt0903747"}).json()["queued"] is True
        assert c.get("/api/foryou/follow", params={"id": "tt0903747"}).json()["dropped"] is True
        # Regresar a «Viendo» sin la campana: sale de progress_watched y de las dejadas, no del calendario
        down["on"] = False
        net.calls.clear()
        assert c.post("/api/foryou/drop", json={"kind": "series", "id": "tt0386676", "dropped": False}).status_code == 200
        removed = [u.split("/users/hidden/")[1] for m, u, _ in net.calls if "/users/hidden/" in u]
        assert "calendar/remove" not in removed and "progress_watched/remove" in removed and "dropped/remove" in removed
        assert c.get("/api/foryou/follow", params={"id": "tt0386676"}).json() == {"dropped": False, "following": False}


def test_dropped_in_trakt_tv_counts_and_a_dropped_section_refusal_does_not_fail(library, make_foryou, net):  # noqa: F811
    net.on("GET", r"/users/hidden/progress_watched", (200, []))
    net.on("GET", r"/users/hidden/dropped", (200, [{"show": show("Lost", "tt0411008")}]))
    net.on("POST", r"/users/hidden/dropped", (404, None))
    net.on("POST", r"/users/hidden/", (201, {}))
    fy = make_foryou(linked=True)
    assert fy.trakt.hidden_shows() == {"tt0411008"}
    fy.trakt.set_hidden(["tt1"], True, trakt.DROPPED_SECTIONS)  # «dejadas» es extra: lo demás ya quedó


def test_the_board_reads_trakt_and_tells_what_changed_by_itself(library, make_foryou, net):  # noqa: F811
    now = time.time()
    iso = time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime(now - DAY))
    watched = []
    net.on("GET", r"/sync/watchlist", (200, [{"type": "movie", "movie": movie("Dune", "tt15239678")}]))
    net.on("GET", r"/sync/watched/movies", lambda url, body: (200, watched))
    net.on("GET", r"/sync/watched/shows", (200, [{"last_watched_at": iso, "show": {**show("The Bear", "tt14452776", episodes=10),
                                                   "status": "returning series"}, "seasons": [{"number": 1, "episodes": [{}] * 4}]}]))
    net.on("GET", r"/users/me/lists$", (200, [{"name": "Para el finde", "privacy": "link", "item_count": 3, "ids": {"trakt": 7}}]))
    fy = make_foryou(linked=True)
    with client(library) as c:
        board = c.get("/api/foryou/board").json()
        assert [i["meta_id"] for i in board["in_list"]] == ["tt15239678"]
        assert [i["meta_id"] for i in board["watching"]] == ["tt14452776"]
        assert board["lists"] == [{"id": "7", "name": "Para el finde", "privacy": "link", "count": 3}]
        assert board["changes"] == []
        # La terminaste en otro aparato: sale de Mi lista y pasa a Vistas, y el tablero lo dice
        watched.append({"last_watched_at": iso, "movie": movie("Dune", "tt15239678")})
        net.routes.insert(0, ("GET", r"/sync/watchlist", (200, [])))
        fy.cache.clear("trakt:")
        board = c.get("/api/foryou/board").json()
        assert board["changes"] == [{"id": "tt15239678", "title": "Dune", "to": "watched"}]


def test_many_titles_go_in_one_request_per_list(library, make_foryou, net):  # noqa: F811
    net.on("POST", r"/sync/watchlist/remove", (200, {}))
    net.on("POST", r"/users/me/lists/7/items$", (201, {}))
    make_foryou(linked=True)
    items = [{"kind": "movie", "id": "tt1"}, {"kind": "series", "id": "tt2"}]
    with client(library) as c:
        assert c.post("/api/foryou/many", json={"where": "watchlist", "items": items, "add": False}).status_code == 200
        assert c.post("/api/foryou/many", json={"where": "list:7", "items": items, "add": True}).status_code == 200
    posts = [(u.split("api.trakt.tv")[1], b) for m, u, b in net.calls if m == "POST"]
    assert posts == [("/sync/watchlist/remove", {"movies": [{"ids": {"imdb": "tt1"}}], "shows": [{"ids": {"imdb": "tt2"}}]}),
                     ("/users/me/lists/7/items", {"movies": [{"ids": {"imdb": "tt1"}}], "shows": [{"ids": {"imdb": "tt2"}}]})]


def test_managing_your_lists(library, make_foryou, net):  # noqa: F811
    net.on("PUT", r"/users/me/lists/7$", (200, {}))
    net.on("DELETE", r"/users/me/lists/7$", (204, None))
    net.on("POST", r"/users/me/lists$", (201, {"ids": {"trakt": 8}}))
    net.on("GET", r"/users/me/lists/7/items", (200, [{"id": 70, "type": "movie", "movie": movie("A", "tt1")},
                                                     {"id": 71, "type": "movie", "movie": movie("B", "tt2")}]))
    net.on("GET", r"/users/me/lists/8/items", (200, [{"id": 80, "type": "movie", "movie": movie("A", "tt1")},
                                                     {"id": 81, "type": "movie", "movie": movie("B", "tt2")}]))
    net.on("POST", r"/items(/reorder)?$", (201, {}))
    make_foryou(linked=True)
    with client(library) as c:
        manage = lambda **body: c.post("/api/foryou/list-manage", json=body)  # noqa: E731
        assert manage(action="rename", where="list:7", name="  Con Ana ").status_code == 200
        assert manage(action="rename", where="list:7", name=" ").status_code == 400
        assert manage(action="privacy", where="list:7", privacy="link").status_code == 200
        assert manage(action="privacy", where="list:7", privacy="todos").status_code == 400
        assert manage(action="reorder", where="list:7", ids=["tt2"]).status_code == 200
        assert manage(action="duplicate", where="list:7", name="Copia de Con Ana").json() == {"ok": True, "id": "list:8", "name": "Copia de Con Ana"}
        assert manage(action="delete", where="list:7").status_code == 200
    sent = [(m, u.split("api.trakt.tv")[1], b) for m, u, b in net.calls if m != "GET"]
    assert sent[0] == ("PUT", "/users/me/lists/7", {"name": "Con Ana"})
    assert sent[1] == ("PUT", "/users/me/lists/7", {"privacy": "link"})
    assert sent[2] == ("POST", "/users/me/lists/7/items/reorder", {"rank": [71, 70]})
    assert ("POST", "/users/me/lists", {"name": "Copia de Con Ana", "privacy": "private"}) in sent
    assert ("POST", "/users/me/lists/8/items/reorder", {"rank": [80, 81]}) in sent
    assert sent[-1] == ("DELETE", "/users/me/lists/7", None)


def test_watched_state_without_seasons_asks_progress_of_recent_shows(library, make_foryou, net):  # noqa: F811
    """Trakt dejó de mandar «seasons» en /sync/watched/shows (10 nov 2026): el avance exacto sale de su progreso; si no
    contesta, se estima con las veces que viste episodios."""
    net.on("GET", r"/sync/watched/movies", (200, []))
    net.on("GET", r"/sync/watched/shows", (200, [
        {"plays": 3, "last_watched_at": "2026-11-09T10:00:00.000Z", "show": show("The Bear", "tt14452776", episodes=10)},
        {"plays": 8, "last_watched_at": "2026-11-01T10:00:00.000Z", "show": show("Silo", "tt14688458", trakt_id=2, episodes=10)}]))
    net.on("GET", r"/shows/tt14452776/progress/watched", (200, {"aired": 10, "completed": 5}))
    fy = make_foryou(linked=True)
    shows = fy.trakt.watched_state()["shows"]
    assert shows["tt14452776"]["fraction"] == .5  # el exacto
    assert shows["tt14688458"]["fraction"] == .8  # sin respuesta: 8 de 10


def test_lists_saved_before_g4_are_read_again(library, make_foryou, net):  # noqa: F811
    """La caché del disco tenía tus listas sin «quién la ve» ni cuántos: todas decían «solo tú» (10 nov, en la tele)."""
    net.on("GET", r"/users/me/lists$", (200, [{"name": "animadas", "privacy": "public", "item_count": 17, "ids": {"trakt": 3}}]))
    fy = make_foryou(linked=True)
    fy.cache.get("trakt:lists", 900, lambda: [{"id": "3", "name": "animadas"}])
    assert fy.gestor.lists() == [{"id": "3", "name": "animadas", "privacy": "public", "count": 17}]


def test_mi_lista_y_tus_listas_dicen_cuando_las_agregaste():
    """GD2 (13 nov 2026): «Agregadas: más recientes / más viejas» en la TV necesita la fecha de Trakt en cada título."""
    from orbital.foryou.items import video_item
    from orbital.library.trakt.base import _typed

    rows = [{"type": "movie", "listed_at": "2026-11-01T10:00:00.000Z", "movie": {"title": "Dune", "ids": {"imdb": "tt1160419"}}},
            {"type": "show", "show": {"title": "Dark", "ids": {"imdb": "tt5753856"}}}]
    dune, dark = _typed(rows, listed=True)
    assert dune["listed_at"] > 0 and "listed_at" not in dark
    assert video_item(dune, "En Mi lista")["added_at"] == dune["listed_at"]
    assert "added_at" not in video_item(dark, "En Mi lista")
    assert "listed_at" not in _typed(rows)[0]  # donde no se pide (tendencias, catálogos), no viaja
