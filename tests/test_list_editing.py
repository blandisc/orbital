"""Editar tus listas desde la TV (Fernando, 6 nov; como ListEditing del iPhone): quitar y agregar en Mi lista y en tus
listas de Trakt por POST /api/foryou/save, con un Trakt falso (nunca sale a internet). La interfaz cambia al instante y,
si Trakt no acepta, regresa y lo dice: aquí se cuida que el servidor conteste el error en palabras y que, tras el cambio,
la lista se vuelva a pedir a Trakt (no la de la memoria)."""

from __future__ import annotations

from fastapi.testclient import TestClient
from test_foryou import make_foryou, movie, net  # noqa: F401 - las piezas de «Para ti» (fixtures)

from orbital.server import create_app

DUNE = movie("Dune: Parte dos", "tt15239678")
OPPEN = movie("Oppenheimer", "tt15398776")


class FakeTrakt:
    """Tu watchlist y tu lista 7 en Trakt: GET lee lo que hay, POST …/remove y POST agregan."""

    def __init__(self, fake_net) -> None:
        self.watch = [DUNE, OPPEN]
        self.mine = [OPPEN]
        self.fail = False
        fake_net.on("GET", r"/sync/watchlist", lambda url, body: (200, [{"type": "movie", "movie": m} for m in self.watch]))
        fake_net.on("GET", r"/users/me/lists/7/items", lambda url, body: (200, [{"type": "movie", "movie": m} for m in self.mine]))
        fake_net.on("GET", r"/users/me/lists$", (200, [{"name": "Para el finde", "ids": {"trakt": 7}}]))
        fake_net.on("POST", r"/sync/watchlist(/remove)?$", lambda url, body: self.change(self.watch, url, body))
        fake_net.on("POST", r"/users/me/lists/7/items(/remove)?$", lambda url, body: self.change(self.mine, url, body))

    def change(self, rows, url, body):
        if self.fail:
            return 503, None
        imdb = body["movies"][0]["ids"]["imdb"]
        if url.endswith("/remove"):
            rows[:] = [m for m in rows if m["ids"]["imdb"] != imdb]
        else:
            rows.insert(0, next(m for m in (DUNE, OPPEN) if m["ids"]["imdb"] == imdb))
        return 201, {}


def ids(c, list_id):
    return [i["meta_id"] for i in c.get("/api/foryou/list", params={"id": list_id}).json()["items"]]


def test_removing_and_adding_in_mi_lista_and_your_list_reads_trakt_again(library, make_foryou, net):  # noqa: F811
    FakeTrakt(net)
    make_foryou(linked=True)
    with TestClient(create_app(library.config, library), base_url="http://127.0.0.1:8710", client=("127.0.0.1", 5000)) as c:
        assert ids(c, "watchlist") == ["tt15239678", "tt15398776"]
        assert c.post("/api/foryou/save", json={"kind": "movie", "id": "tt15239678", "where": "watchlist", "add": False}).json() == {"ok": True}
        assert ids(c, "watchlist") == ["tt15398776"]  # sin esperar a que caduque la memoria
        # «Deshacer»: de vuelta
        assert c.post("/api/foryou/save", json={"kind": "movie", "id": "tt15239678", "where": "watchlist", "add": True}).status_code == 200
        assert ids(c, "watchlist") == ["tt15239678", "tt15398776"]
        # Tu lista de Trakt («Agregar a esta lista…» y «Quitar de esta lista»)
        assert ids(c, "list:7") == ["tt15398776"]
        assert c.post("/api/foryou/save", json={"kind": "movie", "id": "tt15239678", "where": "list:7", "add": True}).status_code == 200
        assert ids(c, "list:7") == ["tt15239678", "tt15398776"]
        assert c.post("/api/foryou/save", json={"kind": "movie", "id": "tt15398776", "where": "list:7", "add": False}).status_code == 200
        assert ids(c, "list:7") == ["tt15239678"]


def test_when_trakt_does_not_accept_it_says_so_and_nothing_changes(library, make_foryou, net):  # noqa: F811
    fake = FakeTrakt(net)
    make_foryou(linked=True)
    with TestClient(create_app(library.config, library), base_url="http://127.0.0.1:8710", client=("127.0.0.1", 5000)) as c:
        assert ids(c, "watchlist") == ["tt15239678", "tt15398776"]
        fake.fail = True
        res = c.post("/api/foryou/save", json={"kind": "movie", "id": "tt15239678", "where": "watchlist", "add": False})
        assert res.status_code == 502 and res.json()["detail"].startswith("No pude cambiar tu lista de Trakt")
        assert ids(c, "watchlist") == ["tt15239678", "tt15398776"]


def test_only_your_lists_are_edited(library, make_foryou, net):  # noqa: F811
    """Un ranking, un catálogo o Para ti no se editan (como `TitleActions.isEditable`): el servidor no sabe guardar ahí."""
    FakeTrakt(net)
    make_foryou(linked=True)
    with TestClient(create_app(library.config, library), base_url="http://127.0.0.1:8710", client=("127.0.0.1", 5000)) as c:
        for where in ("trend", "chart:netflix", "list:../x", "recs"):
            res = c.post("/api/foryou/save", json={"kind": "movie", "id": "tt15239678", "where": where, "add": False})
            assert res.status_code == 400, where
        assert c.post("/api/foryou/save", json={"kind": "game", "id": "x", "where": "watchlist", "add": False}).status_code == 400
