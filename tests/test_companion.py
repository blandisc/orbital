"""«Conectar iPhone»: el QR con la dirección del túnel y el token, y lo que el iPhone se lleva de la consola."""

from types import SimpleNamespace
from urllib.parse import parse_qs, urlsplit

import pytest
from fastapi.testclient import TestClient
from test_player import FakeMpv

from orbital import companion
from orbital import player as player_mod
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


# --- «Viendo en la TV» (la tarjeta del iPhone) ------------------------------------------------

def _proc():
    return type("Proc", (), {"poll": lambda self: None, "wait": lambda self, timeout=None: None})()


def _play_movie(library):
    mpv = FakeMpv({"pause": False, "time-pos": 100.0, "duration": 6000.0, "mute": False})
    p = library.watch.player
    p.mpv = mpv
    p.current = player_mod.Playback("Interstellar", _proc(), 0, {})
    meta = {"kind": "movie", "meta_id": "tt1", "video_id": "tt1", "title": "Interstellar",
            "poster": "https://img/x.jpg", "detail": ""}
    p.segment = player_mod.Segment(meta, "Interstellar", "http://a", position=100.0, duration=6000.0, playing=True)
    library.launcher.track("media:player", "Interstellar", object(), runner="Reproductor")
    return p, mpv


def _play_episode(library):
    mpv = FakeMpv({"pause": False, "time-pos": 50.0, "duration": 1200.0, "mute": False})
    p = library.watch.player
    p.mpv = mpv
    p.current = player_mod.Playback("The Office", _proc(), 0, {})
    meta = {"kind": "series", "meta_id": "s1", "video_id": "s1:1:1", "title": "The Office",
            "detail": "T1 E1 · Pilot", "poster": None}
    p.segment = player_mod.Segment(meta, "The Office", "http://a", position=50.0, duration=1200.0, playing=True)
    library.launcher.track("media:player", "The Office", object(), runner="Reproductor")
    return p, mpv


def _play_channel(library):
    mpv = FakeMpv({"mute": False})
    p = library.watch.player
    p.mpv = mpv
    p.current = player_mod.Playback("Canal 2", _proc(), 0, {})
    meta = {"kind": "tv", "live": True, "channel_id": "c2", "title": "Canal 2", "number": 2,
            "category": "Noticias", "list": "todos"}
    p.segment = player_mod.Segment(meta, "Canal 2", "http://tv", live=True, playing=True)
    library.launcher.track("media:player", "Canal 2", object(), runner="Reproductor")
    return p, mpv


def test_now_playing_is_none_without_anything_open(library):
    assert companion.now_playing(library) is None


def test_now_playing_describes_a_movie(library):
    _play_movie(library)
    now = companion.now_playing(library)
    assert now["kind"] == "movie" and now["title"] == "Interstellar" and now["position"] == 100.0
    assert now["duration"] == 6000.0 and now["paused"] is False and now["live"] is False
    assert now["poster"] == "https://img/x.jpg"


def test_now_playing_formats_the_episode_label(library):
    _play_episode(library)
    assert companion.now_playing(library)["episode_label"] == "T1 · E1"


def test_now_playing_live_channel_has_no_progress(library):
    _play_channel(library)
    now = companion.now_playing(library)
    assert now == {"kind": "tv", "live": True, "channel": "Canal 2", "title": "Canal 2", "number": 2,
                   "category": "Noticias", "paused": False, "muted": False}


def test_control_player_raises_without_anything_playing(library):
    with pytest.raises(companion.NothingPlaying):
        companion.control_player(library, "pause")


def test_control_player_toggle_pauses_and_resumes(library):
    p, mpv = _play_movie(library)
    now = companion.control_player(library, "toggle")
    assert now["paused"] is True and ("set_property", "pause", True) in mpv.sent
    now = companion.control_player(library, "toggle")
    assert now["paused"] is False


def test_control_player_skip_seeks(library):
    _play_movie(library)
    companion.control_player(library, "skip", 30)
    assert ("seek", 30.0, "relative") in library.watch.player.mpv.sent


def test_control_player_skip_live_is_rejected(library):
    _play_channel(library)
    with pytest.raises(ValueError):
        companion.control_player(library, "skip", 10)


def test_control_player_live_does_not_pause(library):
    _play_channel(library)
    with pytest.raises(ValueError):
        companion.control_player(library, "toggle")


def test_control_player_mute_toggles(library):
    p, mpv = _play_channel(library)
    now = companion.control_player(library, "mute")
    assert now["muted"] is True and ("set_property", "mute", True) in mpv.sent


def test_control_player_stop_closes_the_player(library):
    p, _ = _play_movie(library)
    assert companion.control_player(library, "stop") is None
    assert p._user_quit is True


def test_control_player_next_changes_the_episode(library):
    p, _ = _play_episode(library)
    calls = []
    p.on_episode = lambda meta, step: calls.append((meta["video_id"], step))
    companion.control_player(library, "next")
    assert calls == [("s1:1:1", 1)]


def test_control_player_previous_without_episodes_fails(library):
    _play_movie(library)
    with pytest.raises(ValueError):
        companion.control_player(library, "previous")


def test_control_player_next_channel_zaps(library, monkeypatch):
    _play_channel(library)
    calls = []
    monkeypatch.setattr(library.tv, "guide", lambda meta, category=None: {
        "category": "todos",
        "channels": [{"id": "c1", "current": False}, {"id": "c2", "current": True}, {"id": "c3", "current": False}]})
    monkeypatch.setattr(library.tv, "tune", lambda meta, cid, category=None: calls.append((cid, category)) or True)
    companion.control_player(library, "next")
    assert calls == [("c3", "todos")]
    companion.control_player(library, "previous")
    assert calls[-1] == ("c1", "todos")


def test_control_player_unknown_action_is_rejected(library):
    _play_movie(library)
    with pytest.raises(ValueError):
        companion.control_player(library, "dance")


# --- las rutas del puerto público (el iPhone, siempre con token) -----------------------------

def test_companion_now_requires_a_token(library):
    main = create_app(library.config, library)
    with TestClient(create_public_app(library.config, main)) as c:
        assert c.get("/api/companion/now").status_code == 401


def test_companion_now_is_null_without_anything_open(library):
    main = create_app(library.config, library)
    with TestClient(create_public_app(library.config, main)) as c:
        r = c.get("/api/companion/now", headers={"Authorization": "Bearer secreto"})
        assert r.status_code == 200 and r.json() == {"playing": None}


def test_companion_now_reports_whats_playing(library):
    _play_movie(library)
    main = create_app(library.config, library)
    with TestClient(create_public_app(library.config, main)) as c:
        r = c.get("/api/companion/now", headers={"Authorization": "Bearer secreto"})
        assert r.json()["playing"]["title"] == "Interstellar"


def test_companion_player_without_anything_playing_is_409_in_words(library):
    main = create_app(library.config, library)
    with TestClient(create_public_app(library.config, main)) as c:
        r = c.post("/api/companion/player", json={"action": "toggle"}, headers={"Authorization": "Bearer secreto"})
        assert r.status_code == 409 and "TV" in r.json()["detail"]


def test_companion_player_toggle_pauses_through_the_route(library):
    _play_movie(library)
    main = create_app(library.config, library)
    with TestClient(create_public_app(library.config, main)) as c:
        r = c.post("/api/companion/player", json={"action": "toggle"}, headers={"Authorization": "Bearer secreto"})
        assert r.status_code == 200 and r.json()["playing"]["paused"] is True


def test_companion_player_requires_a_token(library):
    _play_movie(library)
    main = create_app(library.config, library)
    with TestClient(create_public_app(library.config, main)) as c:
        assert c.post("/api/companion/player", json={"action": "toggle"}).status_code == 401

