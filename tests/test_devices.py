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


# --- Conectar con o sin iPhone (CA2-A, TEC-3/4/9-13/30/32; CX1, CX4, CX5, CX8 de Fernando, 3 nov) -------------------
KEY = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789ABCDEFGHIJKLMNOP"


def tunnel(monkeypatch):
    monkeypatch.setattr(companion, "tunnel_info", lambda config, tailscale_url=None, funnel_on=None: {"ready": True, "host": "legion.ts.net", "url": "x"})


def test_the_key_from_any_phone_is_checked_by_the_console_and_confirmed_on_the_tv(apps, monkeypatch):
    local, public, main = apps
    tunnel(monkeypatch)
    published = []
    main.state.catalog.events.subscribe(published.append)
    res = local.post("/api/remote-input", json={"purpose": "realdebrid", "title": "otra cosa", "fields": []}).json()
    code, words = res["code"], res["words"]
    assert len(words.split()) == 2
    page = public.get(f"/escribir/{code}").text
    assert words in page and "Usar esta clave" in page and "Conectar Real-Debrid" in page  # los campos los pone la consola
    User.error = realdebrid.RealDebridError("mala", 401, 8)
    bad = public.post(f"/escribir/{code}", json={"values": {"token": KEY}})
    assert bad.status_code == 400 and "no reconoce" in bad.json()["detail"]
    assert public.get(f"/escribir/{code}").status_code == 200  # un fallo no gasta el código
    User.error = None
    ok = public.post(f"/escribir/{code}", json={"values": {"token": KEY}})
    assert ok.json() == {"ok": True, "account": "fer"}
    arrived = next(e for e in published if e.get("type") == "remote-input")
    assert arrived == {"type": "remote-input", "code": code, "purpose": "realdebrid", "account": "fer"}
    assert KEY not in json.dumps(published)
    assert local.get("/api/remote-input/take", params={"code": code}).status_code == 204  # la interfaz nunca la recoge
    assert main.state.catalog.watch.rd_token() == "TORRENTIOKEY3F2A"  # sin el «Usar» de la TV no se guarda
    saved = local.post("/api/realdebrid/remote/confirm", json={"code": code})
    assert saved.status_code == 200 and saved.json()["user"] == "fer" and KEY not in saved.text
    assert main.state.catalog.watch.rd_token() == KEY and main.state.catalog.watch.debrid_status()["source"] == "celular"
    assert local.post("/api/realdebrid/remote/confirm", json={"code": code}).status_code == 409  # una sola vez


def test_five_wrong_keys_end_the_code(apps, monkeypatch):
    local, public, _ = apps
    tunnel(monkeypatch)
    code = local.post("/api/remote-input", json={"purpose": "realdebrid"}).json()["code"]
    User.error = realdebrid.RealDebridError("mala", 401, 8)
    for _ in range(5):
        last = public.post(f"/escribir/{code}", json={"values": {"token": KEY}})
    assert "muchos intentos" in last.json()["detail"]
    assert public.get(f"/escribir/{code}").status_code == 404


def test_the_key_pasted_on_the_tv_is_checked_first(apps):
    local, _, main = apps
    User.error = realdebrid.RealDebridError("mala", 401, 8)
    assert local.post("/api/realdebrid/key", json={"token": KEY}).status_code == 422
    assert local.post("/api/realdebrid/key", json={"token": "corta"}).status_code == 422
    User.error = None
    assert local.post("/api/realdebrid/key", json={"token": f" {KEY} "}).json()["user"] == "fer"
    assert main.state.catalog.watch.rd_token() == KEY


def test_a_new_tv_says_so_and_pairing_again_keeps_the_row(apps):
    local, public, main = apps
    tv_id = public.get("/api/companion", headers={"Authorization": "Bearer secreto"}).json()["tv_id"]
    got, key = pair(local, public, main)
    assert got["tv_id"] == tv_id
    stranger = public.get("/api/addons", headers={"Authorization": f"Bearer od1.{'e' * 32}.x"})
    assert stranger.status_code == 401 and stranger.json()["code"] == "device_unknown" and "nueva" in stranger.json()["detail"]
    local.get("/api/companion/pair.svg")
    again = public.post("/api/devices/pair", json={"code": main.state.devices.code(), "name": "Mi iPhone", "platform": "iphone"},
                        headers=key).json()
    assert again["device_id"] == got["device_id"] and again["key"] != got["key"]
    assert [d["name"] for d in local.get("/api/devices").json()["devices"]] == ["Mi iPhone"]  # el mismo renglón
    assert public.get("/api/addons", headers=key).status_code == 401  # la llave vieja ya no sirve


def test_the_mac_never_pairs(apps):
    local, public, main = apps
    local.get("/api/companion/pair.svg")
    mac = public.post("/api/devices/pair", json={"code": main.state.devices.code(), "name": "Mac", "platform": "mac"})
    assert mac.status_code == 422 and "iCloud" in mac.json()["detail"]


def test_the_iphone_invites_one_ipad_and_only_the_iphone_removes_others(apps):
    local, public, main = apps
    phone, phone_key = pair(local, public, main)
    events = []
    main.state.bus.publish_threadsafe = events.append
    invite = public.post("/api/devices/invite", headers=phone_key).json()
    assert invite["platform"] == "ipad"
    as_iphone = public.post("/api/devices/pair", json={"code": invite["code"], "name": "Otro", "platform": "iphone"})
    assert as_iphone.status_code == 404  # la invitación es para un iPad
    pad = public.post("/api/devices/pair", json={"code": invite["code"], "name": "iPad", "platform": "ipad"})
    assert pad.status_code == 200
    assert {"type": "phone-linked", "name": "iPad", "platform": "ipad", "invited_by": "iPhone de Fernando"} in events
    assert public.post("/api/devices/pair", json={"code": invite["code"], "name": "iPad 2", "platform": "ipad"}).status_code == 404
    pad_key = {"Authorization": f"Bearer {pad.json()['key']}"}
    assert public.post("/api/devices/invite", headers=pad_key).status_code == 403  # solo el iPhone invita
    listed = {d["name"]: d for d in local.get("/api/devices").json()["devices"]}
    assert listed["iPad"]["invited_by"] == "iPhone de Fernando"
    assert public.delete(f"/api/devices/{phone['device_id']}", headers=pad_key).status_code == 403  # CX5
    second = public.post("/api/devices/invite", headers=phone_key).json()
    assert public.delete(f"/api/devices/{pad.json()['device_id']}", headers=phone_key).status_code == 200
    local.delete(f"/api/devices/{phone['device_id']}")
    assert public.post("/api/devices/pair", json={"code": second["code"], "name": "iPad", "platform": "ipad"}).status_code == 404


def test_the_old_token_becomes_a_key_only_with_the_tv_saying_yes(apps):
    local, public, main = apps
    tunnel_token = {"Authorization": "Bearer secreto"}
    pair(local, public, main, name="iPad", platform="ipad")  # ya hay un aparato: el token solo abre lo de Alexa…
    events = []
    main.state.bus.publish_threadsafe = events.append
    asked = public.post("/api/devices/upgrade", json={"name": "iPhone de Fernando", "platform": "iphone"}, headers=tunnel_token)
    assert asked.status_code == 202  # …y el paso a la llave (CX8-A)
    ident = asked.json()["id"]
    assert {"type": "device-upgrade", "id": ident, "name": "iPhone de Fernando", "platform": "iphone"} in events
    assert public.get(f"/api/devices/upgrade/{ident}", headers=tunnel_token).status_code == 202
    assert public.post("/api/devices/upgrade", json={}).status_code == 401  # sin token, nada
    assert local.post(f"/api/devices/upgrade/{ident}", json={"yes": True}).status_code == 200
    got = public.get(f"/api/devices/upgrade/{ident}", headers=tunnel_token)
    assert got.status_code == 200 and got.json()["key"].startswith("od1.")
    assert public.get(f"/api/devices/upgrade/{ident}", headers=tunnel_token).status_code == 404  # la llave, una sola vez
    assert public.get("/api/addons", headers={"Authorization": f"Bearer {got.json()['key']}"}).status_code == 200
    no = public.post("/api/devices/upgrade", json={"name": "Otro", "platform": "iphone"}, headers=tunnel_token).json()["id"]
    local.post(f"/api/devices/upgrade/{no}", json={"yes": False})
    assert public.get(f"/api/devices/upgrade/{no}", headers=tunnel_token).status_code == 403
    assert len(local.get("/api/devices").json()["devices"]) == 2


def test_the_quick_code_opens_the_same_page_without_scanning(apps, monkeypatch):
    """«…ts.net/clave · KQ7MXR»: la misma página, con las mismas reglas; 5 códigos equivocados en total y se acaba."""
    local, public, _ = apps
    tunnel(monkeypatch)
    res = local.post("/api/remote-input", json={"purpose": "realdebrid"}).json()
    short = res["short"]
    assert len(short) == 6 and set(short) <= set("ACDEFGHJKMNPQRTUVWXY34679")
    assert "Escribe el código de tu TV" in public.get("/clave").text
    page = public.get(f"/clave/{short.lower()}")  # se vale en minúsculas
    assert page.status_code == 200 and res["words"] in page.text
    assert public.post(f"/clave/{short}", json={"values": {"token": KEY}}).json() == {"ok": True, "account": "fer"}
    res = local.post("/api/remote-input", json={"purpose": "realdebrid"}).json()
    for _ in range(4):
        assert public.get("/clave/AAAAAA").status_code == 404
    assert public.get(f"/clave/{res['short']}").status_code == 200  # cuatro fallos: sigue vivo
    assert public.get("/clave/AAAAAA").status_code == 404
    assert public.get(f"/clave/{res['short']}").status_code == 404  # el quinto lo acabó
    assert public.get(f"/escribir/{res['code']}").status_code == 404


def test_a_dead_code_is_replaced_on_the_tv_and_a_lowercase_key_still_works(apps, monkeypatch):
    """Auditoría (3 nov): tras 5 fallos la TV enseña otro código sola; una clave escrita en minúsculas con el teclado de la
    TV se prueba también en mayúsculas (así son las de Real-Debrid)."""
    local, public, main = apps
    tunnel(monkeypatch)
    published = []
    main.state.catalog.events.subscribe(published.append)
    code = local.post("/api/remote-input", json={"purpose": "realdebrid"}).json()["code"]
    for _ in range(5):
        public.get("/clave/AAAAAA")
    assert {"type": "remote-input", "code": code, "expired": True} in published

    class Upper(User):
        def user(self):
            if self.token != self.token.upper():
                raise realdebrid.RealDebridError("mala", 401, 8)
            return super().user()

    monkeypatch.setattr(realdebrid, "RealDebrid", Upper)
    assert local.post("/api/realdebrid/key", json={"token": KEY.lower()}).status_code == 200


def test_audit_a_mistyped_quick_code_lets_you_retry_and_ten_devices_hide_the_qr(apps, monkeypatch):
    """Auditoría de la TV (TV-13, TV-14, TV-1): un código rápido mal escrito se dice y se reintenta; con 10 aparatos no hay
    QR, se dice qué hacer; y la interfaz sabe cuál complemento es OpenSubtitles."""
    local, public, main = apps
    tunnel(monkeypatch)
    local.post("/api/remote-input", json={"purpose": "realdebrid"})
    wrong = public.get("/clave/ZZZZZZ")
    assert wrong.status_code == 404 and "no es el de tu TV" in wrong.text and "Escribe el código de tu TV" in wrong.text
    for i in range(10):
        main.state.devices.pair(main.state.devices.code(), f"iPhone {i}", "iphone")
    assert "10 aparatos" in local.get("/api/companion/pair").json()["reason"]
    assert local.get("/api/companion/pair.svg").status_code == 409
    templates = {e["id"]: e.get("template") for e in local.get("/api/settings").json()["addons"]["entries"]}
    assert templates.get("opensubtitles") == "opensubtitles"
