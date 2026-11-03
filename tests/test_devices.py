"""Las llaves por aparato (K1-A; design/addons-contract.json › devices y secrets): el código del QR de una sola vez, la
llave que solo se guarda como huella, el token del túnel que queda solo para Alexa (K1-13), lo que lleva clave solo con
llave, «Pasar a la TV» que prueba la clave antes de guardarla y «Quitar». Nada sale a internet."""

import json
from urllib.parse import parse_qs, urlsplit

import pytest
from fastapi.testclient import TestClient

from orbital import companion, devices, rd_requests
from orbital.credentials import Credentials
from orbital.library import realdebrid
from orbital.server import create_app, create_public_app

CONTRACT = json.loads(open("design/addons-contract.json", encoding="utf-8").read())


class Clock:
    def __init__(self):
        self.now = 1000.0

    def __call__(self):
        return self.now


def test_the_code_is_used_once_and_dies_with_the_screen():
    clock = Clock()
    d = devices.Devices(Credentials(None), clock=clock)
    code = d.code()
    assert len(code) >= 43 and d.code() == code  # el mismo mientras siga a la vista
    got = d.pair(code, "iPhone de Fernando", "iphone")
    assert got["key"].startswith(f"od1.{got['device_id']}.") and len(got["device_id"]) == 32
    with pytest.raises(devices.PairError) as used:
        d.pair(code, "otro", "iphone")
    assert used.value.status == 404
    late = d.code()
    clock.now += devices.CODE_TTL
    with pytest.raises(devices.PairError, match="ya no sirve"):
        d.pair(late, "x", "ipad")
    closed = d.code()
    d.close_code()
    with pytest.raises(devices.PairError, match="ya no sirve"):
        d.pair(closed, "x", "ipad")


def test_only_the_fingerprint_is_kept_and_a_removed_device_is_told():
    creds = Credentials(None)
    d = devices.Devices(creds)
    got = d.pair(d.code(), "iPad", "ipad")
    secret = got["key"].split(".")[2]
    assert secret not in (creds.get("devices") or "")
    assert d.check(got["key"]) == ("ok", {"device_id": got["device_id"], "name": "iPad", "platform": "ipad"})
    assert d.check(got["key"][:-1] + "x")[0] == "bad"
    assert d.check("od1.nope.x")[0] == "bad"
    assert d.remove(got["device_id"]) and d.check(got["key"]) == ("removed", None)
    assert not d.any()


def test_ten_devices_at_most_and_the_limits_per_hour():
    clock = Clock()
    d = devices.Devices(Credentials(None), clock=clock)
    for i in range(devices.MAX_DEVICES):
        d.pair(d.code(), f"iPhone {i}", "iphone")
    with pytest.raises(devices.PairError) as full:
        d.pair(d.code(), "uno más", "iphone")
    assert full.value.status == 409
    assert all(d.allow("a", "rd_put") for _ in range(5)) and not d.allow("a", "rd_put")
    clock.now += devices.HOUR
    assert d.allow("a", "rd_put")


def test_the_contract_says_the_same():
    assert "devices" in CONTRACT and "secrets" in CONTRACT
    assert all(path in CONTRACT["devices"]["access"] for path in devices.ALEXA_PATHS)
    assert devices.LIMITS == {"secret": 20, "rd_put": 5} and "20 lecturas" in CONTRACT["secrets"]["limits"]
    assert devices.PLATFORMS == tuple(p for p in CONTRACT["devices"]["platforms"] if p != "tv")


class User:
    error: Exception | None = None

    def __init__(self, token, opener=None):
        self.token = token

    def user(self):
        if User.error:
            raise User.error
        return {"id": 7, "username": "fer", "type": "premium", "expiration": "2099-11-21T18:00:00.000Z"}


@pytest.fixture
def apps(library, monkeypatch):
    monkeypatch.setattr(rd_requests.RdRequests, "_torrentio_token", lambda self: "TORRENTIOKEY3F2A")
    monkeypatch.setattr(rd_requests.RdRequests, "watch", lambda self: None)
    monkeypatch.setattr(realdebrid, "RealDebrid", User)
    monkeypatch.setattr(companion.alexa_setup, "tailscale_url", lambda: "https://legion.ts.net")
    User.error = None
    main = create_app(library.config, library)
    local = TestClient(main, base_url="http://127.0.0.1:8710", client=("127.0.0.1", 1))
    public = TestClient(create_public_app(library.config, main), base_url="https://legion.ts.net", client=("127.0.0.1", 2))
    with local:
        yield local, public, main


def pair(local, public, main, name="iPhone de Fernando", platform="iphone"):
    assert local.get("/api/companion/pair.svg").status_code == 200
    code = main.state.devices.code()
    got = public.post("/api/devices/pair", json={"code": code, "name": name, "platform": platform})
    assert got.status_code == 200 and got.headers["cache-control"] == "no-store"
    return got.json(), {"Authorization": f"Bearer {got.json()['key']}"}


def test_the_qr_carries_a_code_and_never_the_token(apps):
    local, _, main = apps
    info = companion.pair_info(main.state.deps.config, code="CODIGO")
    link = urlsplit(info["link"])
    assert parse_qs(link.query) == {"v": ["2"], "u": ["https://legion.ts.net"], "c": ["CODIGO"]}
    assert "link" not in local.get("/api/companion/pair").json()


def test_pairing_closes_the_tunnel_token_to_everything_but_alexa(apps):
    local, public, main = apps
    tunnel = {"Authorization": "Bearer secreto"}
    assert public.get("/api/companion", headers=tunnel).json()["pairing"] == 2
    assert public.post("/api/devices/pair", json={"code": "inventado"}).status_code == 404
    got, key = pair(local, public, main)
    assert public.get("/api/addons", headers=tunnel).json() == {"code": "device_key_required",
                                                                "detail": "Vuelve a escanear el código de tu TV"}
    assert public.get("/api/ping", headers=tunnel).status_code == 200  # Alexa sigue
    assert public.get("/api/addons", headers=key).status_code == 200
    listed = public.get("/api/devices", headers=key).json()["devices"]
    assert listed == [{**listed[0], "device_id": got["device_id"], "name": "iPhone de Fernando", "platform": "iphone", "this": True}]
    assert "hash" not in json.dumps(local.get("/api/devices").json())
    assert local.delete(f"/api/devices/{got['device_id']}").json() == {"devices": []}
    gone = public.get("/api/addons", headers=key)
    assert gone.status_code == 401 and gone.json()["code"] == "device_removed"
    assert public.get("/api/addons", headers=tunnel).status_code == 200  # sin aparatos, el token abre lo de siempre


def test_what_carries_a_key_needs_the_device_key(apps):
    local, public, main = apps
    tunnel = {"Authorization": "Bearer secreto"}
    assert public.get("/api/addons?full=1", headers=tunnel).status_code == 401
    assert public.put("/api/realdebrid", json={"token": "X" * 40}, headers=tunnel).status_code == 401
    _, key = pair(local, public, main)
    events = []
    main.state.catalog.watch.events.publish = events.append
    full = public.get("/api/realdebrid?full=1", headers=key)
    assert full.json()["token"] == "TORRENTIOKEY3F2A" and full.headers["cache-control"] == "no-store"
    assert "token" not in public.get("/api/realdebrid", headers=key).json()
    assert any("tomó la clave" in e.get("message", "") for e in events)
    User.error = realdebrid.RealDebridError("mala", 401, 8)
    bad = public.put("/api/realdebrid", json={"token": "MALA" * 10}, headers=key)
    assert bad.status_code == 422 and main.state.catalog.watch.rd_token() == "TORRENTIOKEY3F2A"  # la de antes se queda
    User.error = None
    ok = public.put("/api/realdebrid", json={"token": "NUEVA" * 8}, headers=key)
    assert ok.status_code == 200 and "NUEVA" not in json.dumps(ok.json()) and ok.json()["user"] == "fer"
    assert main.state.catalog.watch.rd_token() == "NUEVA" * 8
    assert any("cambió la clave" in e.get("message", "") for e in events)
    away = TestClient(public.app, base_url="https://legion.ts.net", client=("100.64.0.9", 3))
    assert away.get("/api/realdebrid?full=1", headers=key).status_code == 403  # solo por Tailscale (loopback)


def test_each_device_switches_only_its_own_and_takes_it_when_removed(apps):
    local, public, main = apps
    got, key = pair(local, public, main)
    me = got["device_id"]
    listed = public.get("/api/addons", headers=key).json()
    addons = [{**a, "enabled": {**a["enabled"], me: False, "tv": False, "iphone": False}} for a in listed["addons"]]
    saved = public.put("/api/addons", json={"base_revision": listed["revision"], "addons": addons}, headers=key).json()
    assert saved["changed_by"] == me
    torrentio = next(a for a in saved["addons"] if a["id"] == "torrentio")
    assert torrentio["enabled"].get(me) is False and torrentio["enabled"].get("tv", True) is not False
    assert "iphone" not in torrentio["enabled"]
    assert local.get("/api/settings").json()["addons"]["changed_by"] == "iPhone de Fernando"
    with_key = {"id": "x", "origin": "stremio", "name": "Comet", "order": 9, "enabled": {me: True},
                "url": "https://y.strem.fun/realdebrid=ZZZZ/manifest.json"}
    kept = public.put("/api/addons", json={"base_revision": saved["revision"], "addons": [*saved["addons"], with_key]}, headers=key)
    assert kept.status_code == 200  # con llave sí entra una dirección con clave
    assert "ZZZZ" not in json.dumps(kept.json()) and "ZZZZ" in json.dumps(public.get("/api/addons?full=1", headers=key).json())
    local.delete(f"/api/devices/{me}")
    assert all(me not in a["enabled"] for a in main.state.catalog.watch.addon_list.shared()["addons"])
