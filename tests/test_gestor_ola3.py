"""Ola 3 del gestor en la TV (O3-B, como `ViewingsTests` del iPhone): tus vistas con su id, cambiar una fecha (entra la
nueva y sale la vieja), borrar solo una, el historial con las repetidas, tu nota (Trakt con VIP; sin VIP, en esta tele) y las
estrellas de una temporada. Con un Trakt falso (nunca sale a internet)."""

from __future__ import annotations

from fastapi.testclient import TestClient
from test_foryou import make_foryou, net  # noqa: F401 - las piezas de «Para ti» (fixtures)

from orbital.library import trakt
from orbital.server import create_app


def client(library):
    return TestClient(create_app(library.config, library), base_url="http://127.0.0.1:8710", client=("127.0.0.1", 5000))


def posts(fake, path):
    return [b for m, u, b in fake.calls if m == "POST" and u.split("api.trakt.tv")[1] == path]


def test_repeats_are_the_newer_of_two_close_viewings():
    e = [{"id": 1, "at": 1000, "imdb": "tt1", "season": None, "episode": None},
         {"id": 2, "at": 1600, "imdb": "tt1", "season": None, "episode": None},   # 10 min después: repetida
         {"id": 3, "at": 90000, "imdb": "tt1", "season": None, "episode": None},  # otro día: otra vez
         {"id": 4, "at": 1200, "imdb": "tt2", "season": 1, "episode": 1}]
    assert trakt.repeats(e) == {2}


def test_viewings_change_the_date_and_remove_only_one(library, make_foryou, net):  # noqa: F811
    net.on("GET", r"/search/imdb/tt0816692", (200, [{"movie": {"ids": {"trakt": 157336}}}]))
    net.on("GET", r"/sync/history/movies/157336", (200, [{"id": 11, "watched_at": "2025-03-14T21:30:00.000Z"},
                                                         {"id": 12, "watched_at": "2024-01-02T20:00:00.000Z"}]))
    net.on("POST", r"/sync/history(/remove)?$", (201, {}))
    make_foryou(linked=True)
    with client(library) as c:
        got = c.get("/api/foryou/viewings", params={"kind": "movie", "id": "tt0816692"}).json()["viewings"]
        assert [v["id"] for v in got] == [11, 12]
        c.post("/api/foryou/viewings", json={"action": "move", "kind": "movie", "id": "tt0816692", "viewing_id": 12, "at": 1700000000})
        c.post("/api/foryou/viewings", json={"action": "remove", "kind": "movie", "id": "tt0816692", "viewing_id": 11})
    added = posts(net, "/sync/history")
    assert added == [{"movies": [{"ids": {"imdb": "tt0816692"}, "watched_at": "2023-11-14T22:13:20.000Z"}]}]
    assert posts(net, "/sync/history/remove") == [{"ids": [12]}, {"ids": [11]}]  # la nueva entró antes de borrar la vieja


def test_offline_viewing_waits_in_the_queue_and_shows_already(library, make_foryou, net):  # noqa: F811
    down = {"on": True}

    def history(url, body):
        if down["on"]:
            raise OSError("sin red")
        return 201, {}

    net.on("GET", r"/search/imdb/", (200, [{"show": {"ids": {"trakt": 7}}}]))
    net.on("GET", r"/sync/history/shows/7", (200, [{"id": 5, "watched_at": "2025-01-01T00:00:00.000Z", "episode": {"season": 2, "number": 3}},
                                                   {"id": 6, "watched_at": "2025-01-02T00:00:00.000Z", "episode": {"season": 1, "number": 1}}]))
    net.on("POST", r"/sync/history", history)
    fy = make_foryou(linked=True)
    with client(library) as c:
        r = c.post("/api/foryou/viewings", json={"action": "add", "kind": "series", "id": "tt1", "video_id": "tt1:2:3", "at": 1800000000})
        assert r.json() == {"ok": True, "queued": True}
        got = c.get("/api/foryou/viewings", params={"kind": "series", "id": "tt1", "video_id": "tt1:2:3"}).json()["viewings"]
        assert [(v["id"], v["at"]) for v in got] == [(0, 1800000000), (5, got[1]["at"])]  # el capítulo, no el otro
    down["on"] = False
    assert fy.gestor.outbox.flush(fy.trakt) == 1


def test_history_marks_repeats(library, make_foryou, net):  # noqa: F811
    show = {"title": "The Bear", "year": 2022, "ids": {"imdb": "tt14452776"}}
    net.on("GET", r"/sync/history\?", (200, [
        {"id": 3, "watched_at": "2026-11-09T21:10:00.000Z", "show": show, "episode": {"season": 3, "number": 1, "title": "Tomorrow"}},
        {"id": 2, "watched_at": "2026-11-09T21:00:00.000Z", "show": show, "episode": {"season": 3, "number": 1, "title": "Tomorrow"}},
        {"id": 1, "watched_at": "2026-11-01T20:00:00.000Z", "movie": {"title": "Dune", "year": 2021, "ids": {"imdb": "tt1160419"}}}]))
    make_foryou(linked=True)
    with client(library) as c:
        got = c.get("/api/foryou/history").json()
    assert [e["id"] for e in got["entries"]] == [3, 2, 1] and got["repeats"] == [3]
    assert got["entries"][0]["episode_title"] == "Tomorrow"


def test_note_lives_on_the_tv_without_vip_and_in_trakt_with_it(library, make_foryou, net):  # noqa: F811
    vip = {"on": False}
    net.on("GET", r"/users/settings", lambda url, body: (200, {"user": {"vip": vip["on"]}}))
    net.on("GET", r"/users/me/notes/", (200, []))
    net.on("POST", r"/notes$", (201, {"id": 99}))
    make_foryou(linked=True)
    with client(library) as c:
        assert c.post("/api/foryou/note", json={"kind": "movie", "id": "tt1", "text": "  La vi con Ana  "}).json() == {"vip": False, "queued": False}
        assert c.get("/api/foryou/note", params={"kind": "movie", "id": "tt1"}).json() == {"text": "La vi con Ana", "vip": False}
        vip["on"] = True  # ya eres VIP: la de la tele pasa sola a Trakt
        c.get("/api/foryou/note", params={"kind": "movie", "id": "tt1"})
    assert posts(net, "/notes") == [{"movie": {"ids": {"imdb": "tt1"}}, "notes": "La vi con Ana", "privacy": "private", "spoiler": False}]


def test_season_stars_count_double_in_trakt(library, make_foryou, net):  # noqa: F811
    net.on("GET", r"/sync/ratings/seasons", (200, [{"rating": 8, "show": {"ids": {"imdb": "tt14452776"}}, "season": {"number": 3}}]))
    net.on("POST", r"/sync/ratings", (201, {}))
    make_foryou(linked=True)
    with client(library) as c:
        assert c.get("/api/foryou/season-rating", params={"id": "tt14452776", "season": 3}).json() == {"stars": 4}
        c.post("/api/foryou/season-rating", json={"id": "tt14452776", "season": 2, "stars": 5})
    assert posts(net, "/sync/ratings") == [{"shows": [{"ids": {"imdb": "tt14452776"}, "seasons": [{"number": 2, "rating": 10}]}]}]


def test_without_internet_your_viewings_still_open_with_what_waits(library, make_foryou, net):  # noqa: F811
    """Sin internet, «Tus vistas» abre con lo que espera en la cola y lo dice: «La vi otra vez» sigue a la mano."""
    def down(url, body):
        raise OSError("sin red")

    net.on("GET", r"/search/imdb/", down)
    net.on("POST", r"/sync/history", down)
    make_foryou(linked=True)
    with client(library) as c:
        c.post("/api/foryou/viewings", json={"action": "add", "kind": "movie", "id": "tt0816692", "at": 1800000000})
        got = c.get("/api/foryou/viewings", params={"kind": "movie", "id": "tt0816692"}).json()
    assert got == {"viewings": [{"id": 0, "at": 1800000000}], "offline": True}
