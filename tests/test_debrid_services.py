"""Tu nube: Real-Debrid, TorBox o AllDebrid (Fernando, 18 nov 2026). Cada cliente habla con su API (aquí, respuestas
falsas con la forma de su documentación) y contesta en la forma de Real-Debrid; la libreta de pedidos, Torrentio y Comet
se arman con la tuya."""

import io
import json
import urllib.error
import urllib.parse

import pytest

from orbital import rd_requests
from orbital.library import addon_list, alldebrid, debrid, streams, torbox, torrentio

TB_KEY = "1b2c3d4e-5f60-7182-93a4-b5c6d7e8f901"
AD_KEY = "abcdefghij0123456789"
H = "a" * 40


class Res(io.BytesIO):
    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False


class Opener:
    """Contesta según (método, ruta) con lo que le digas y anota lo que le pidieron."""

    def __init__(self, answers: dict):
        self.answers = answers
        self.calls: list[tuple[str, str, dict, bytes | None, dict]] = []

    def __call__(self, req, timeout=None):
        url = urllib.parse.urlparse(req.full_url)
        query = dict(urllib.parse.parse_qsl(url.query))
        self.calls.append((req.get_method(), url.path, query, req.data, dict(req.header_items())))
        got = self.answers[(req.get_method(), url.path)]
        got = got(query, req.data) if callable(got) else got
        if isinstance(got, tuple):  # (http, cuerpo): un error HTTP
            raise urllib.error.HTTPError(req.full_url, got[0], "x", {}, io.BytesIO(json.dumps(got[1]).encode()))
        return Res(json.dumps(got).encode())


# --- TorBox ------------------------------------------------------------------------------------------------------
def tb_torrent(**extra):
    return {"id": 77, "hash": H, "name": "The.Simpsons.S37.1080p", "download_state": "downloading", "download_finished": False,
            "download_present": False, "progress": 0.42, "seeds": 9, "active": True,
            "files": [{"id": 0, "name": "The.Simpsons.S37/The.Simpsons.S37E01.mkv", "size": 500},
                      {"id": 1, "name": "The.Simpsons.S37/The.Simpsons.S37E03.mkv", "size": 400},
                      {"id": 2, "name": "The.Simpsons.S37/sample.mkv", "size": 10}], **extra}


def test_torbox_cuenta_pedir_seguir_y_enlace():
    base = "/v1/api"
    op = Opener({
        ("GET", f"{base}/user/me"): {"success": True, "data": {"id": 123, "email": "fer@x.com", "plan": 2,
                                                              "premium_expires_at": "2027-01-01T00:00:00Z"}},
        ("POST", f"{base}/torrents/createtorrent"): {"success": True, "data": {"torrent_id": 77, "hash": H}},
        ("GET", f"{base}/torrents/mylist"): lambda q, _: {"success": True,
                                                         "data": tb_torrent() if q.get("id") else [tb_torrent()]},
        ("GET", f"{base}/torrents/requestdl"): {"success": True, "data": "https://store.torbox.app/dl/e03.mkv"},
        ("POST", f"{base}/torrents/controltorrent"): {"success": True, "data": None},
    })
    tb = torbox.TorBox(TB_KEY, opener=op)
    assert tb.account() == {"id": "123", "username": "fer@x.com", "premium": True, "expires": 1798761600.0}
    assert op.calls[0][4]["Authorization"] == f"Bearer {TB_KEY}"
    assert tb.add(H, 2, pack=True) == "77"
    sent = op.calls[-1][3].decode()
    assert f"magnet:?xt=urn:btih:{H}" in sent and "multipart" in op.calls[-1][4]["Content-type"]
    got = tb.torrents()[0]
    assert got["status"] == "downloading" and got["progress"] == 42 and got["seeders"] == 9 and got["hash"] == H
    assert rd_requests.rd_state(got["status"], got["progress"], got["seeders"]) == rd_requests.DOWNLOADING
    op.answers[("GET", f"{base}/torrents/mylist")] = lambda q, _: {"success": True, "data": tb_torrent(
        download_state="cached", download_finished=True, download_present=True, progress=1)}
    info = tb.info("77")
    assert info["status"] == "downloaded" and rd_requests.rd_state("downloaded", 100, None) == rd_requests.READY
    # El episodio se elige por su nombre (S37E03), no por el lugar del archivo: TorBox no siempre numera como el torrent.
    assert tb.link(info, 0, 37, 3) == ("https://store.torbox.app/dl/e03.mkv", "The.Simpsons.S37E03.mkv")
    assert op.calls[-1][2] == {"token": TB_KEY, "torrent_id": "77", "file_id": "1"}
    tb.delete("77")
    assert json.loads(op.calls[-1][3]) == {"torrent_id": 77, "operation": "delete"}


def test_torbox_sus_errores_dicen_la_causa():
    base = "/v1/api"
    op = Opener({("POST", f"{base}/torrents/createtorrent"): {"success": False, "error": "ACTIVE_LIMIT", "detail": "x"},
                 ("GET", f"{base}/user/me"): (401, {"success": False, "error": "BAD_TOKEN"}),
                 ("GET", f"{base}/torrents/mylist"): {"success": True, "data": None},
                 ("POST", f"{base}/torrents/controltorrent"): (404, {"success": False, "error": "ITEM_NOT_FOUND"})})
    tb = torbox.TorBox(TB_KEY, opener=op)
    with pytest.raises(debrid.DebridError) as busy:
        tb.add(H)
    assert busy.value.too_many and str(busy.value) == "Muchas descargas activas"
    with pytest.raises(debrid.DebridError) as bad:
        tb.account()
    assert bad.value.bad_key and str(bad.value) == "Vuelve a conectar TorBox"
    with pytest.raises(debrid.DebridError) as gone:
        tb.info("5")
    assert gone.value.gone
    tb.delete("5")  # ya no estaba: cuenta como hecho
    assert tb.counts_active is False and tb.active_count() is None


def test_las_tablas_de_errores_de_torbox_y_alldebrid_dicen_lo_que_prometen():
    for service in ("realdebrid", "torbox", "alldebrid"):
        data = json.loads(debrid.ERRORS_FILES[service].read_text(encoding="utf-8"))
        for case in data["cases"]:
            assert debrid.cause_of(service, case["http"], case["code"]) == case["cause"], (service, case)


# --- AllDebrid ---------------------------------------------------------------------------------------------------
def ad_status(code, **extra):
    return {"id": 55, "filename": "The.Simpsons.S37.1080p", "size": 1000, "downloaded": 250, "status": "x",
            "statusCode": code, "seeders": 4, **extra}


def test_alldebrid_cuenta_pedir_seguir_y_enlace():
    tree = [{"n": "The.Simpsons.S37", "e": [{"n": "The.Simpsons.S37E01.mkv", "s": 500, "l": "https://alldebrid.com/f/1"},
                                            {"n": "The.Simpsons.S37E03.mkv", "s": 400, "l": "https://alldebrid.com/f/3"}]}]
    state = {"code": 1}
    op = Opener({
        ("GET", "/v4/user"): {"status": "success", "data": {"user": {"username": "fer", "isPremium": True,
                                                                     "premiumUntil": 1800000000}}},
        ("POST", "/v4/magnet/upload"): {"status": "success", "data": {"magnets": [{"id": 55, "hash": H, "ready": False}]}},
        ("POST", "/v4.1/magnet/status"): lambda q, data: {"status": "success", "data": {
            "magnets": ad_status(state["code"]) if b"id=" in (data or b"") else [ad_status(state["code"])]}},
        ("POST", "/v4/magnet/files"): {"status": "success", "data": {"magnets": [{"id": "55", "files": tree}]}},
        ("POST", "/v4/link/unlock"): {"status": "success", "data": {"link": "https://x.debrid.it/dl/e03.mkv",
                                                                     "filename": "The.Simpsons.S37E03.mkv"}},
        ("POST", "/v4/magnet/delete"): {"status": "success", "data": {"message": "ok"}},
    })
    ad = alldebrid.AllDebrid(AD_KEY, opener=op)
    assert ad.account() == {"id": "fer", "username": "fer", "premium": True, "expires": 1800000000.0}
    assert ad.add(H) == "55" and b"magnets%5B%5D=" + H.encode() in op.calls[-1][3]
    got = ad.torrents()[0]
    assert (got["status"], got["progress"], got["seeders"]) == ("downloading", 25, 4)
    state["code"] = 4
    info = ad.info("55")
    assert info["status"] == "downloaded" and [f["path"] for f in info["files"]] == [
        "The.Simpsons.S37/The.Simpsons.S37E01.mkv", "The.Simpsons.S37/The.Simpsons.S37E03.mkv"]
    assert ad.link(info, None, 37, 3) == ("https://x.debrid.it/dl/e03.mkv", "The.Simpsons.S37E03.mkv")
    assert b"link=https%3A%2F%2Falldebrid.com%2Ff%2F3" in op.calls[-1][3]
    state["code"] = 15  # nadie lo comparte: AllDebrid lo da por perdido
    assert rd_requests.rd_state(ad.torrents()[0]["status"], 0, 0) == rd_requests.REFUSED
    assert ad.active_count() == (1, 30)


def test_alldebrid_sus_errores_vienen_en_un_200():
    op = Opener({("POST", "/v4/magnet/upload"): {"status": "success", "data": {"magnets": [
                    {"magnet": H, "error": {"code": "MAGNET_TOO_MANY_ACTIVE", "message": "30"}}]}},
                 ("GET", "/v4/user"): {"status": "error", "error": {"code": "AUTH_BAD_APIKEY", "message": "x"}}})
    ad = alldebrid.AllDebrid(AD_KEY, opener=op)
    with pytest.raises(debrid.DebridError) as busy:
        ad.add(H)
    assert busy.value.too_many
    with pytest.raises(debrid.DebridError) as bad:
        ad.account()
    assert bad.value.bad_key and str(bad.value) == "Vuelve a conectar AllDebrid"


# --- Torrentio, Comet y los nombres de las versiones -------------------------------------------------------------
def test_torrentio_con_torbox_o_alldebrid_ya_no_pierde_la_clave():
    """Punto 1 (Fernando, 18 nov): un Torrentio traído de tu Stremio con TorBox o AllDebrid se quedaba sin clave."""
    assert torrentio.parse_service("https://torrentio.strem.fun/sort=seeders|torbox=TBKEY123/manifest.json") == (
        {"language": [], "qualityfilter": [], "sort": "seeders"}, "TBKEY123", "torbox")
    assert torrentio.parse_service("https://torrentio.strem.fun/alldebrid=ADKEY/manifest.json")[1:] == ("ADKEY", "alldebrid")
    options, key, service = torrentio.parse_service("https://torrentio.strem.fun/premiumize=PM|sort=size/manifest.json")
    assert key is None and service is None and "verbatim" not in options  # otra nube: Orbital no la usa (ni la enseña)
    url = torrentio.manifest_url({"sort": "seeders"}, "TBKEY", service="torbox")
    assert url == "https://torrentio.strem.fun/sort=seeders|torbox=TBKEY/manifest.json"
    assert debrid.key_in(url) == ("torbox", "TBKEY")
    assert debrid.without_debrid(url.removesuffix("/manifest.json")) == "https://torrentio.strem.fun/sort=seeders"


def test_tu_lista_arma_torrentio_y_comet_con_tu_nube():
    class Store(dict):
        def set(self, key, value):
            self[key] = value

    brought = {}
    lst = addon_list.AddonList(Store(), key=lambda: "TBKEY", service=lambda: "torbox",
                               on_key=lambda key, service="realdebrid": brought.update(key=key, service=service))
    entries = {e.template: e for e in lst.entries()}
    assert entries["torrentio"].address.endswith("|torbox=TBKEY/manifest.json")
    import base64
    comet = entries["comet"].address.split("/")[3]
    assert json.loads(base64.b64decode(comet))["debridServices"] == [{"apiKey": "TBKEY", "service": "torbox"}]
    empty = addon_list.AddonList(Store(), on_key=lambda key, service="realdebrid": brought.update(key=key, service=service))
    empty._adopt(empty.entries(), "https://torrentio.strem.fun/alldebrid=ADKEY/manifest.json")
    assert brought == {"key": "ADKEY", "service": "alldebrid"}


def test_las_marcas_de_torbox_y_alldebrid_cuentan_como_las_de_real_debrid():
    def parse(name, url="https://torrentio.strem.fun/resolve/torbox/KEY/" + H + "/0/x.mkv"):
        return streams.parse({"name": name, "title": "The.Simpsons.S37E03.1080p", "url": url}, "Torrentio",
                             "https://torrentio.strem.fun/torbox=KEY/manifest.json", 0)

    ready, later = parse("[TB+] Torrentio\n1080p"), parse("[TB download] Torrentio\n1080p")
    assert ready.cached and ready.debrid and not later.cached and later.debrid and ready.info_hash == H
    assert parse("[AD+] Torrentio\n1080p", url=f"https://torrentio.strem.fun/resolve/alldebrid/K/{H}/0/x").cached
    assert streams.source.torrentio_notice({"name": "[TB error] Torrentio", "title": "x"}) == "failed_access"
    assert streams.source.torrentio_notice({"name": "[AD error] Torrentio", "title": "x"}) == "failed_access"


# --- La libreta con otra nube --------------------------------------------------------------------------------------
class State:
    def __init__(self):
        self.data = {}

    def prefs(self, key):
        return dict(self.data.get(key, {}))

    def set_pref(self, key, field, value):
        self.data.setdefault(key, {})
        if value is None:
            self.data[key].pop(field, None)
        else:
            self.data[key][field] = value


class Finder:
    timeout = 5

    def addons(self):
        return []

    def forget(self, kind, video_id):
        pass


def test_cada_pedido_dice_su_nube_y_lo_de_otra_no_se_toca(monkeypatch):
    monkeypatch.setattr(rd_requests.RdRequests, "watch", lambda self: None)
    service = {"now": "torbox"}
    state = State()
    reqs = rd_requests.RdRequests(Finder(), state, lambda e: None, rd_factory=lambda token: None,
                                  token=lambda: "K", service=lambda: service["now"])
    reqs.account = lambda: "1"
    entry = {"hash": H, "service": "realdebrid", "account": "1", "kind": "movie", "video_ids": ["tt1"], "state": "refused"}
    state.set_pref(rd_requests.STATE_ID, H, entry)
    assert reqs.refused() == set()  # lo que rechazó Real-Debrid puede que TorBox sí lo deje
    assert reqs.status("tt1")["mine"] is False and reqs.status("tt1")["message"] == "Real-Debrid no lo dejó bajar"
    service["now"] = "realdebrid"
    assert reqs.refused() == {H} and reqs.status("tt1")["mine"] is True
    assert reqs.listing()["service"] == "realdebrid"
    assert rd_requests.clean({**entry, "service": "premiumize"}) is None
    assert rd_requests.clean({k: v for k, v in entry.items() if k != "service"}) is not None  # los de antes: Real-Debrid
    assert rd_requests.cloud("torbox").startswith("La nube es tu TorBox:")


def test_too_many_en_torbox_se_vuelve_a_pedir_sin_preguntar_cuantas_deja(monkeypatch):
    monkeypatch.setattr(rd_requests.RdRequests, "watch", lambda self: None)
    added = []

    class FakeTB:
        counts_active = False

        def torrents(self, limit=100):
            return []

        def add(self, info_hash, file_idx=None, pack=False):
            added.append(info_hash)
            return "9"

        def active_count(self):
            raise AssertionError("TorBox no dice cuántas deja: no se pregunta")

        def info(self, rd_id):
            return {"id": rd_id, "hash": H, "status": "queued", "progress": 0, "seeders": None, "files": []}

    state = State()
    reqs = rd_requests.RdRequests(Finder(), state, lambda e: None, rd_factory=lambda token: FakeTB(),
                                  token=lambda: "K", service=lambda: "torbox")
    reqs.account = lambda: "1"
    state.set_pref(rd_requests.STATE_ID, H, {"hash": H, "service": "torbox", "account": "1", "kind": "movie",
                                            "video_ids": ["tt1"], "state": "too_many", "by": "TV", "files": {}})
    reqs.tick()
    assert added == [H] and state.prefs(rd_requests.STATE_ID)[H]["state"] == "queued"


def test_la_ficha_dice_el_nombre_de_tu_nube(library, monkeypatch):
    w = library.watch
    assert w.debrid_service == "realdebrid" and w.debrid_status()["name"] == "Real-Debrid"
    with pytest.raises(ValueError):
        w.set_debrid_service("premiumize")
    monkeypatch.setattr(torbox.TorBox, "account", lambda self: {"id": "1", "username": "fer", "premium": True,
                                                                "expires": 4102444800.0})
    w.set_debrid_service("torbox")
    assert w.debrid_status() == {"linked": False, "service": "torbox", "name": "TorBox"}
    status = w.set_rd_token(TB_KEY, "TV", source="tv", service="torbox")
    assert status["service"] == "torbox" and status["user"] == "fer" and status["premium"] and status["problem"] is None
    assert w.addon_list.torrentio().address.endswith(f"|torbox={TB_KEY}/manifest.json")
    summary = w.debrid_summary()
    assert [s["service"] for s in summary["services"]] == ["realdebrid", "torbox", "alldebrid"]
    assert [s["linked"] for s in summary["services"]] == [False, True, False]


def test_el_contrato_de_las_tres_nubes_es_el_que_usa_la_tv():
    """design/debrid-services.json es lo que lee el iPhone: tiene que decir lo mismo que la TV."""
    from orbital.shared import design_file
    data = json.loads(design_file("debrid-services.json").read_text(encoding="utf-8"))
    assert tuple(data["services"]) == debrid.SERVICES and data["default"] == debrid.DEFAULT
    for service, s in data["services"].items():
        assert s["name"] == debrid.NAMES[service] and s["tag"] == debrid.TAGS[service] and s["site"] == debrid.SITES[service]
        assert s["key_url"] == debrid.KEY_URLS[service] and s["key_store"] == debrid.KEYS[service]
        assert s["torrentio_param"] in torrentio.DEBRID_PARAMS and debrid.ERRORS_FILES[service].name == s["errors"]
        assert debrid.ERRORS_FILES[service].is_file()
    assert data["client"]["torbox"]["counts_active"] is torbox.TorBox.counts_active
    assert data["client"]["alldebrid"]["counts_active"] is alldebrid.AllDebrid.counts_active


def test_el_qr_de_la_pagina_de_cada_nube(library):
    """«Todavía no tengo» una nube: el QR de su página de planes, solo de las tres."""
    from fastapi.testclient import TestClient

    from orbital.server import create_app
    client = TestClient(create_app(library.config, library), base_url="http://127.0.0.1:8710", client=("127.0.0.1", 1))
    assert client.get("/api/debrid/qr.svg?service=torbox").headers["content-type"].startswith("image/svg+xml")
    assert client.get("/api/debrid/qr.svg?service=premiumize").status_code == 404


def test_la_pagina_de_planes_de_cada_nube_es_la_del_contrato():
    from orbital.shared import design_file
    data = json.loads(design_file("debrid-services.json").read_text(encoding="utf-8"))
    assert data["words"]["signup_urls"] == debrid.SIGNUP_URLS
