import pytest
from fastapi.testclient import TestClient

from orbital.server import create_app

LOCAL = ("127.0.0.1", 5000)
REMOTE = ("203.0.113.9", 5000)


@pytest.fixture
def make_client(library):
    def make(client=LOCAL):
        return TestClient(create_app(library.config, library), client=client)
    return make


def test_local_access_without_token(make_client):
    with make_client() as c:
        rows = c.get("/api/library").json()["rows"]
        assert rows[0]["title"] == "Steam"
        assert "argv" not in rows[0]["items"][0]  # no se exponen comandos
        assert c.get("/").status_code == 200


def test_remote_requires_token(make_client):
    with make_client(REMOTE) as c:
        assert c.get("/api/library").status_code == 401
        assert c.get("/api/library", headers={"Authorization": "Bearer nope"}).status_code == 401
        assert c.get("/api/library", headers={"Authorization": "Bearer secreto"}).status_code == 200


def test_tunnel_on_localhost_requires_token(make_client):
    # cloudflared conecta desde 127.0.0.1 pero añade cabeceras de reenvío.
    with make_client() as c:
        assert c.get("/api/library", headers={"CF-Connecting-IP": "1.2.3.4"}).status_code == 401


def test_foreign_origin_blocked(make_client):
    with make_client() as c:
        r = c.post("/api/launch", json={"id": "steam:367520"}, headers={"Origin": "https://evil.example"})
        assert r.status_code == 403


def test_launch_and_status(make_client, library):
    with make_client() as c:
        assert c.post("/api/launch", json={"id": "steam:367520"}).json()["title"] == "Hollow Knight"
        assert c.get("/api/status").json()["running"]["title"] == "Hollow Knight"
        assert c.post("/api/launch", json={"id": "nada"}).status_code == 404


def test_voice_endpoint(make_client, library):
    with make_client(REMOTE) as c:
        r = c.post("/api/voice", json={"intent": "LaunchGameIntent", "slots": {"game": "hollow"}},
                   headers={"Authorization": "Bearer secreto"})
        assert r.json() == {"ok": True, "speech": "Abriendo Hollow Knight."}
        assert c.post("/api/voice", json={}, headers={"Authorization": "Bearer secreto"}).status_code == 422
