"""Real-Debrid propio de la consola («La TV sin Stremio», corte S2): la clave que se toma de tu Torrentio, tu Premium y sus
tres causas, los avisos de Torrentio que nunca son una versión, las claves que no se pierden y la libreta de pedidos por
las rutas que usa el iPhone (design/addons-contract.json, «requests»). Nada sale a internet."""

import json

import pytest
from fastapi.testclient import TestClient

from orbital import rd_requests
from orbital.credentials import Credentials
from orbital.library import realdebrid, streams
from orbital.server import create_app, create_public_app

H = "c" * 40


def test_the_notices_of_torrentio_are_never_a_version():
    assert streams.torrentio_notice({"name": "Torrentio\nRD error", "title": "x"}) == "failed_access"
    assert streams.torrentio_notice({"url": "https://torrentio.strem.fun/videos/failed_access_v3.mp4"}) == "failed_access"
    assert streams.torrentio_notice({"url": "https://torrentio.strem.fun/videos/downloading_v2.mp4?x=1"}) == "downloading"
    assert streams.torrentio_notice({"name": "Torrentio\n1080p", "url": "https://real-debrid.com/d/abc/Movie.mkv"}) is None


def test_real_debrid_errors_say_which_cause():
    assert realdebrid.RealDebridError("x", 401, 8).bad_key
    assert realdebrid.RealDebridError("x", 403, 20).no_premium
    assert realdebrid.RealDebridError("x", 503, 21).too_many
    assert realdebrid.RealDebridError("x", 451, 35).refused
    assert realdebrid.RealDebridError("x", 404).gone


def test_unreadable_keys_are_backed_up_before_writing_over_them(tmp_path):
    path = tmp_path / "secrets.json"
    path.write_text("{esto no es json", encoding="utf-8")
    creds = Credentials(path)
    creds.set("realdebrid_token", "NUEVA")
    backups = list(tmp_path.glob("secrets.ilegible-*.json"))
    assert len(backups) == 1 and backups[0].read_text(encoding="utf-8") == "{esto no es json"
    assert Credentials(path).get("realdebrid_token") == "NUEVA"


class User:
    """El /user de Real-Debrid, de mentira."""

    answer: dict = {}
    error: Exception | None = None

    def __init__(self, token, opener=None):
        self.token = token

    def user(self):
        if User.error:
            raise User.error
        return User.answer


@pytest.fixture
def watch(library, monkeypatch):
    w = library.watch
    monkeypatch.setattr(rd_requests.RdRequests, "_torrentio_token", lambda self: "TORRENTIOKEY3F2A")
    monkeypatch.setattr(realdebrid, "RealDebrid", User)
    User.answer, User.error = {}, None
    return w


def test_the_key_is_taken_from_torrentio_once_and_said(watch):
    events = []
    watch.events.publish = events.append
    assert watch.rd_token() == "TORRENTIOKEY3F2A"
    assert watch.credentials.get("realdebrid_token") == "TORRENTIOKEY3F2A"
    assert [e["message"] for e in events] == ["Tomé tu clave de Real-Debrid de tu Torrentio"]
    assert watch.rd_token() == "TORRENTIOKEY3F2A" and len(events) == 1  # una sola vez


def test_premium_days_and_the_three_causes(watch):
    User.answer = {"id": 7, "username": "fer", "type": "premium", "expiration": "2099-11-21T18:00:00.000Z"}
    ok = watch.debrid_status(fresh=True)
    assert ok["linked"] and ok["premium"] and ok["user"] == "fer" and ok["problem"] is None and ok["days"] > 0
    assert ok["ends_with"] == "3F2A" and "TORRENTIOKEY" not in json.dumps(ok)  # la clave nunca sale entera
    User.answer = {"id": 7, "type": "free", "expiration": "2020-01-01T00:00:00.000Z"}
    assert watch.debrid_status(fresh=True)["problem"] == "expired"
    User.answer = {"id": 7, "type": "free", "expiration": None}
    assert watch.debrid_status(fresh=True)["problem"] == "no_premium"
    User.error = realdebrid.RealDebridError("Vuelve a conectar Real-Debrid", 401, 8)
    assert watch.debrid_status(fresh=True)["problem"] == "bad_key"


@pytest.fixture
def apps(library):
    main = create_app(library.config, library)
    local = TestClient(main, base_url="http://127.0.0.1:8710", client=("127.0.0.1", 1))
    public = TestClient(create_public_app(library.config, main), base_url="https://legion.ts.net", client=("127.0.0.1", 2))
    with local:
        yield local, public, library.watch


def test_the_iphone_reads_and_writes_the_book_through_the_tunnel(apps, monkeypatch):
    local, public, watch = apps
    monkeypatch.setattr(rd_requests.RdRequests, "watch", lambda self: None)
    monkeypatch.setattr(rd_requests.RdRequests, "account", lambda self: "7")
    entry = {"hash": H, "account": "7", "rd_id": "R1", "title": "Severance · T2 E1", "kind": "series", "meta_id": "tt5",
             "video_ids": ["tt5:2:1"], "files": {"tt5:2:1": 0}, "by": "iPhone de Fernando", "state": "downloading", "percent": 12}
    assert public.post("/api/realdebrid/requests", json=entry).status_code == 401  # sin token, nada
    auth = {"Authorization": "Bearer secreto"}
    saved = public.post("/api/realdebrid/requests", json=entry, headers=auth)
    assert saved.status_code == 200 and saved.json()["hash"] == H
    listed = public.get("/api/realdebrid/requests", headers=auth).json()
    assert listed["version"] == 1 and listed["account"] == "7" and listed["requests"][0]["by"] == "iPhone de Fernando"
    assert "notified" not in listed["requests"][0]
    assert local.get("/api/realdebrid/requests").json()["requests"][0]["hash"] == H  # «Tus pedidos» en la TV
    assert public.post("/api/realdebrid/requests", json={**entry, "hash": "nope"}, headers=auth).status_code == 422
    big = {**entry, "release": "x" * 20000}
    assert public.post("/api/realdebrid/requests", content=json.dumps(big), headers={**auth, "Content-Type": "application/json"}).status_code == 413
    assert public.post("/api/realdebrid/requests/cancel", json={"hash": H}, headers=auth).status_code in (401, 404, 405)  # cancelar: solo en la TV


def test_the_account_is_checked_again_and_the_key_never_leaves(apps, monkeypatch):
    """P6-A: al abrir la cuenta se le pregunta a Real-Debrid otra vez; la clave nunca sale entera."""
    local, _, watch = apps
    monkeypatch.setattr(rd_requests.RdRequests, "_torrentio_token", lambda self: "TORRENTIOKEY3F2A")
    monkeypatch.setattr(realdebrid, "RealDebrid", User)
    User.answer, User.error = {"id": 7, "username": "fer", "type": "premium", "expiration": "2099-11-21T18:00:00.000Z"}, None
    got = local.get("/api/realdebrid").json()
    assert got["linked"] and got["premium"] and got["ends_with"] == "3F2A" and "TORRENTIOKEY" not in json.dumps(got)
    User.error = realdebrid.RealDebridError("Vuelve a conectar Real-Debrid", 401, 8)
    assert local.get("/api/realdebrid").json()["problem"] == "bad_key"  # sin esperar la media hora


def test_the_iphone_reads_and_changes_the_addon_list_through_the_tunnel(apps):
    """Corte S6: GET/PUT /api/addons con el token del túnel; 409 con la lista actual si partió de otra revisión."""
    _, public, _ = apps
    auth = {"Authorization": "Bearer secreto", "X-Orbital-Device": "iPhone%20de%20Fernando"}  # llega codificado
    assert public.get("/api/addons").status_code == 401
    got = public.get("/api/addons", headers=auth).json()
    assert "revision" in got and any(a.get("template") == "torrentio" for a in got["addons"])
    stale = public.put("/api/addons", json={"base_revision": got["revision"] + 5, "addons": got["addons"]}, headers=auth)
    assert stale.status_code == 409 and stale.json()["revision"] == got["revision"]
    ok = public.put("/api/addons", json={"base_revision": got["revision"], "addons": got["addons"], "removed": []}, headers=auth)
    assert ok.status_code == 200 and ok.json()["revision"] == got["revision"] + 1 and ok.json()["changed_by"] == "iPhone de Fernando"
    bad = {**got["addons"][0], "id": "x", "origin": "stremio", "url": "https://y.strem.fun/realdebrid=ZZZ/manifest.json"}
    assert public.put("/api/addons", json={"base_revision": got["revision"] + 1, "addons": [bad]}, headers=auth).status_code == 422


def test_finished_request_is_first_and_instant_and_cam_never_counts_as_instant(watch, monkeypatch):
    """«El viento tiene miedo» (3 nov): la versión que pediste y ya terminó va primero, «Al instante · la pediste», aunque
    Torrentio la siga marcando «[RD download]»; y «al instante» nunca es una grabada en el cine ni un tráiler."""
    from orbital import watch as watch_mod
    from orbital.library import streams as streams_mod

    def src(index, info_hash, cached, tags=()):
        s = streams_mod.Source(index=index, addon="Torrentio", stream={"infoHash": info_hash}, transport_url="")
        s.debrid, s.cached, s.tags = True, cached, list(tags)
        return s

    other, mine = src(1, "b" * 40, True), src(2, "a" * 40, False)
    monkeypatch.setattr(type(watch), "has_addons", property(lambda self: True))
    monkeypatch.setattr(watch.streams, "find", lambda kind, video_id, prefs: [other, mine])
    monkeypatch.setattr(watch.rd, "status", lambda video_id: {"mine": True, "state": "ready", "hash": "a" * 40})
    found = watch.stream_sources("movie", "tt0061752")
    assert found[0] is mine and mine.cached and mine.public()["requested"]
    assert not watch_mod.ready_now(src(3, "c" * 40, True, ("CAM",)))
