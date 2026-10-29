"""B en la pantalla de carga: lo que cancelaste no cuenta como jugado."""
from fastapi.testclient import TestClient

from orbital.server import create_app


def test_cancelling_on_the_loading_screen_is_not_played(library):
    hades = library.get("steam:1145360")
    with TestClient(create_app(library.config, library), base_url="http://127.0.0.1:8710", client=("127.0.0.1", 1)) as c:
        assert c.post("/api/launch", json={"id": hades.id}).status_code == 200
        assert library.state.history(hades.id)["launches"] == 1
        assert c.post("/api/stop", json={"cancelled": True}).status_code == 200
    assert library.state.history(hades.id) == {}
    assert hades.id not in library.state.recent()


def test_closing_a_game_normally_still_counts(library):
    hades = library.get("steam:1145360")
    with TestClient(create_app(library.config, library), base_url="http://127.0.0.1:8710", client=("127.0.0.1", 1)) as c:
        c.post("/api/launch", json={"id": hades.id})
        assert c.post("/api/stop").status_code == 200
    assert library.state.history(hades.id)["launches"] == 1
