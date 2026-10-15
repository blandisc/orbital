"""«Conectar iPhone»: el QR con la dirección del túnel y el token, y lo que el iPhone se lleva de la consola."""

from types import SimpleNamespace
from urllib.parse import parse_qs, urlsplit

from fastapi.testclient import TestClient

from orbital import companion
from orbital.server import create_app, create_public_app


def config(token="secreto", ephemeral=False):
    return SimpleNamespace(server=SimpleNamespace(token=token, token_is_ephemeral=ephemeral))


def test_pair_link_carries_the_tunnel_and_the_token():
    info = companion.pair_info(config(), tailscale_url=lambda: "https://legion.tail1.ts.net")
    assert info["ready"] and info["host"] == "legion.tail1.ts.net"
    link = urlsplit(info["link"])
    assert (link.scheme, link.netloc) == ("orbital-ios", "pair")
    assert parse_qs(link.query) == {"u": ["https://legion.tail1.ts.net"], "t": ["secreto"]}


def test_pair_explains_what_is_missing():
    assert "Alexa" in companion.pair_info(config(ephemeral=True), tailscale_url=lambda: "https://x")["reason"]
    assert "Tailscale" in companion.pair_info(config(), tailscale_url=lambda: None)["reason"]


def test_qr_is_an_svg_with_modules():
    svg = companion.qr_svg("orbital-ios://pair?u=https%3A%2F%2Fa&t=b")
    assert svg.startswith("<svg") and "<path" in svg and svg.count("h1v1h-1z") > 100


class FakeTrakt:
    linked = True

    def access_token(self):
        return "AT"

    def session_expiry(self):
        return 123.0


def test_trakt_session_is_lent_without_the_refresh_token():
    assert companion.trakt_session(FakeTrakt()) == {"access_token": "AT", "expires_at": 123.0}
    assert companion.trakt_session(None) is None
    broken = FakeTrakt()
    broken.access_token = lambda: (_ for _ in ()).throw(OSError("sin red"))
    assert companion.trakt_session(broken) is None


def test_qr_route_is_local_and_the_json_never_has_the_token(library, monkeypatch):
    library.config.server.token, library.config.server.token_is_ephemeral = "secreto", False
    monkeypatch.setattr(companion.alexa_setup, "tailscale_url", lambda: "https://legion.tail1.ts.net")
    main = create_app(library.config, library)
    with TestClient(main, base_url="http://127.0.0.1:8710", client=("127.0.0.1", 1)) as c:
        info = c.get("/api/companion/pair").json()
        assert info["ready"] and "secreto" not in str(info)
        svg = c.get("/api/companion/pair.svg")
        assert svg.headers["content-type"].startswith("image/svg+xml")
    # El QR no existe por el túnel: solo en la consola.
    with TestClient(create_public_app(library.config, main), client=("127.0.0.1", 2)) as c:
        assert c.get("/api/companion/pair.svg", headers={"Authorization": "Bearer secreto"}).status_code == 404

