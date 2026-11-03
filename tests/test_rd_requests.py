"""Pedidos a Real-Debrid (propuesta RD, Fernando, 2 nov 2026): pedir lo que no tiene, seguir cuánto lleva y, ya bajado,
tenerlo como una versión que arranca al instante."""

from orbital import rd_requests
from orbital.library import addons, realdebrid, streams

TORRENTIO = "https://torrentio.strem.fun/sort=seeders%7Clanguage=latino%7Crealdebrid=ABC123"


class State:
    def __init__(self):
        self.data = {}

    def prefs(self, item):
        return dict(self.data.get(item, {}))

    def set_pref(self, item, key, value):
        bucket = self.data.setdefault(item, {})
        if value is None:
            bucket.pop(key, None)
        else:
            bucket[key] = value


class FakeRD:
    def __init__(self, token):
        self.token, self.added, self.status, self.progress = token, [], "downloading", 10

    def add(self, info_hash, file_idx=None):
        self.added.append((info_hash, file_idx))
        return "RD1"

    def info(self, rd_id):
        return {"status": self.status, "progress": self.progress, "links": ["https://rd/l1"], "files": [{"id": 1, "selected": 1, "bytes": 5}]}

    def link(self, info):
        return ("https://download.real-debrid.com/x.mkv", "Nocturno.S01E01.1080p.Dual-Lat.mkv")


class Finder:
    timeout = 5

    def __init__(self):
        self.forgot = []

    def addons(self):
        return [addons.Addon(TORRENTIO, {"name": "Torrentio RD", "resources": ["stream"], "types": ["series"]})] \
            if hasattr(addons.Addon, "__init__") else []

    def forget(self, kind, video_id):
        self.forgot.append(video_id)


def test_token_and_the_same_torrentio_without_real_debrid():
    assert realdebrid.token_in(TORRENTIO) == "ABC123"
    assert realdebrid.without_debrid(TORRENTIO) == "https://torrentio.strem.fun/sort=seeders%7Clanguage=latino"


def test_request_follow_and_ready_source(monkeypatch):
    rd = FakeRD("ABC123")
    events, state, finder = [], State(), Finder()
    monkeypatch.setattr(rd_requests.RdRequests, "_debrid_addon", lambda self: type("A", (), {"base": TORRENTIO, "name": "Torrentio RD"})())
    monkeypatch.setattr(addons, "fetch_json", lambda url, timeout: {"streams": [
        {"name": "Torrentio\n1080p", "title": "Nocturno.S01E01.2026.WEB-DL.1080p-Dual-Lat\n👤 3 💾 1.2 GB", "infoHash": "a" * 40}]})
    monkeypatch.setattr(rd_requests.RdRequests, "watch", lambda self: None)  # sin hilo: tick() a mano
    reqs = rd_requests.RdRequests(finder, state, events.append, rd_factory=lambda token: rd)
    got = reqs.request("series", "tt1:1:1", "Nocturne · T1 E1", streams.Preferences(audio="es"))
    assert rd.added == [("a" * 40, None)] and got["state"] == "downloading"
    assert reqs.tick() is True and reqs.status("tt1:1:1")["percent"] == 10
    rd.status = "downloaded"
    assert reqs.tick() is False and reqs.status("tt1:1:1")["state"] == "ready" and finder.forgot == ["tt1:1:1"]
    assert any(e.get("message") == "Ya está Nocturne · T1 E1" for e in events)
    source = reqs.ready_source("series", "tt1:1:1")
    assert source.cached and source.stream["url"].endswith("x.mkv") and "es" in source.languages


def test_nothing_to_request_says_so(monkeypatch):
    monkeypatch.setattr(rd_requests.RdRequests, "_debrid_addon", lambda self: type("A", (), {"base": TORRENTIO, "name": "T"})())
    monkeypatch.setattr(addons, "fetch_json", lambda url, timeout: {"streams": []})
    reqs = rd_requests.RdRequests(Finder(), State(), lambda e: None, rd_factory=FakeRD)
    try:
        reqs.request("series", "tt1:1:1", "x", streams.Preferences())
    except realdebrid.RealDebridError as exc:
        assert "Nadie tiene esto" in str(exc)
    else:
        raise AssertionError("debía decir que nadie lo tiene")
