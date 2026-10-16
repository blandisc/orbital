"""Escribir desde el celular (remote_input.py): un código de un solo uso, la página por el túnel y la TV que lo recoge."""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from orbital import companion, server
from orbital.remote_input import TTL, RemoteInput
from orbital.server import create_app, create_public_app

FIELDS = [{"name": "email", "label": "Correo de Stremio"}, {"name": "password", "label": "Contraseña", "secret": True}]


class Clock:
    def __init__(self):
        self.now = 1000.0

    def __call__(self):
        return self.now


def test_a_code_is_single_use_validated_and_expires():
    events, clock = [], Clock()
    remote = RemoteInput(publish=events.append, clock=clock)
    code = remote.start("Conectar Stremio", FIELDS + [{"name": "mal nombre", "label": "x"}, "basura"])
    assert len(code) >= 20
    assert remote.form(code) == {"title": "Conectar Stremio", "fields": [
        {"name": "email", "label": "Correo de Stremio", "secret": False, "optional": False},
        {"name": "password", "label": "Contraseña", "secret": True, "optional": False}]}
    assert remote.form("otro") is None and remote.submit("otro", {}) is not None
    assert "Contraseña" in remote.submit(code, {"email": "yo@x.mx", "password": "  "})  # falta
    assert remote.submit(code, {"email": "x" * 600, "password": "p"}) is not None  # demasiado largo
    assert remote.submit(code, {"email": "yo@x.mx", "password": "secreta", "otro": "se ignora"}) is None
    assert events == [{"type": "remote-input", "code": code}], "el aviso no lleva lo escrito"
    assert remote.form(code) is None and remote.submit(code, {"email": "a", "password": "b"}) is not None, "un solo envío"
    assert remote.take(code) == {"email": "yo@x.mx", "password": "secreta"}
    assert remote.take(code) is None, "se recoge una sola vez"
    # Caduca; y abrir otro formulario anula el anterior.
    old = remote.start("A", FIELDS)
    clock.now += TTL + 1
    assert remote.form(old) is None
    first, second = remote.start("A", FIELDS), remote.start("B", FIELDS)
    assert remote.form(first) is None and remote.form(second)["title"] == "B"
    remote.cancel(second)
    assert remote.form(second) is None


@pytest.fixture
def apps(library, monkeypatch):
    monkeypatch.setattr(companion, "pair_info", lambda config, tailscale_url=None: {"ready": True, "host": "legion.ts.net", "link": "x"})
    main = create_app(library.config, library)
    with TestClient(main, base_url="http://127.0.0.1:8710", client=("127.0.0.1", 1)) as local:
        yield local, TestClient(create_public_app(library.config, main), base_url="https://legion.ts.net", client=("127.0.0.1", 2)), library


def test_from_the_phone_to_the_tv(apps):
    local, phone, library = apps
    published = []
    library.events.subscribe(published.append)
    res = local.post("/api/remote-input", json={"title": "Conectar Stremio", "fields": FIELDS}).json()
    assert res["ready"] and res["host"] == "legion.ts.net"
    code = res["code"]
    assert local.get("/api/remote-input/qr.svg", params={"code": code}).text.startswith("<svg")
    # La página del celular entra sin el token de Orbital (el código es la llave) y no carga nada de fuera.
    page = phone.get(f"/escribir/{code}")
    assert page.status_code == 200 and "Correo de Stremio" in page.text and "Bearer" not in page.text
    assert "default-src 'none'" in page.headers["content-security-policy"] and page.headers["referrer-policy"] == "no-referrer"
    assert phone.post(f"/escribir/{code}", json={"values": {"email": "yo@x.mx"}}).status_code == 400  # falta la contraseña
    assert phone.post(f"/escribir/{code}", json={"values": {"email": "yo@x.mx", "password": "secreta"}}).json() == {"ok": True}
    assert {"type": "remote-input", "code": code} in published
    assert not any("secreta" in str(e) for e in published), "la contraseña no viaja por los avisos"
    assert local.get("/api/remote-input/take", params={"code": code}).json() == {"values": {"email": "yo@x.mx", "password": "secreta"}}
    assert local.get("/api/remote-input/take", params={"code": code}).status_code == 204
    # Ya usado: la página dice que no sirve; y el resto del túnel sigue pidiendo token.
    gone = phone.get(f"/escribir/{code}")
    assert gone.status_code == 404 and "ya no sirve" in gone.text
    assert phone.get("/api/ping").status_code == 401


def test_bad_codes_count_like_bad_tokens(apps, monkeypatch):
    _, phone, _ = apps
    tries = []

    class Guard(server.FailedTokens):
        def failed(self, key):
            tries.append(key)
            return 0

    monkeypatch.setattr(server, "FailedTokens", Guard)
    local, _, library = apps
    public = TestClient(create_public_app(library.config, local.app, guard=Guard()), base_url="https://legion.ts.net")
    for _ in range(3):
        assert public.get("/escribir/adivinando").status_code == 404
    assert public.post("/escribir/adivinando", json={"values": {}}).status_code == 404
    assert len(tries) == 4


def test_without_a_tunnel_there_is_no_qr(library, monkeypatch):
    monkeypatch.setattr(companion, "pair_info", lambda config, tailscale_url=None: {"ready": False, "reason": "No encontré Tailscale."})
    with TestClient(create_app(library.config, library), base_url="http://127.0.0.1:8710", client=("127.0.0.1", 1)) as local:
        assert local.post("/api/remote-input", json={"title": "X", "fields": FIELDS}).json()["ready"] is False


def test_the_page_never_lets_a_label_close_the_script():
    html = server.remote_page({"title": "</script><script>alert(1)</script>", "fields": []})
    assert "</script><script>alert(1)" not in html
