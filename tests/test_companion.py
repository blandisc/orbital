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
        assert r.status_code == 200 and r.json() == {"playing": None, "inbox": []}


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



# --- la bandeja: lo que la TV le manda al iPhone ---------------------------------------------

class FakeWatch:
    """Lo mínimo que `send_to_phone` le pide al catálogo: la ficha y dónde guardar."""

    def __init__(self, state, details=None):
        self.state = state
        self.details = details or {}

    def title_details(self, kind, meta_id):
        return {"kind": kind, "title": "The Office", "poster": "http://p", **self.details}


OFFICE = {"seasons": [{"season": 1, "episodes": [{"id": "tt:1:1", "episode": 1}]},
                      {"season": 2, "episodes": [{"id": "tt:2:5", "episode": 5}, {"id": "tt:2:6", "episode": 6}]}],
          "resume": {"video_id": "tt:2:5"}}


@pytest.fixture(autouse=True)
def _forget_phone():
    companion.forget_phone()
    yield
    companion.forget_phone()


def _send(watch, action="download", kind="series", meta_id="tt", video_id=None, connected=lambda c: True):
    return companion.send_to_phone(watch, config(), action, kind, meta_id, video_id, connected=connected)


def test_send_queues_the_episode_that_follows_with_its_label():
    from orbital.state import State
    watch = FakeWatch(State(), OFFICE)
    item = _send(watch)
    assert (item["title"], item["episode_label"], item["video_id"], item["action"]) == ("The Office", "T2 · E5", "tt:2:5", "download")
    assert item["poster"] == "http://p" and item["id"] and item["at"]
    assert _send(watch, "open", video_id="tt:1:1")["episode_label"] == "T1 · E1"
    assert [i["action"] for i in watch.state.inbox()] == ["download", "open"]


def test_a_movie_uses_its_own_id_and_has_no_episode():
    from orbital.state import State
    item = _send(FakeWatch(State()), "open", kind="movie", meta_id="tt9")
    assert (item["video_id"], item["episode_label"]) == ("tt9", "")


def test_the_same_title_and_action_pending_is_not_repeated_but_another_action_is():
    from orbital.state import State
    watch = FakeWatch(State(), OFFICE)
    first, again = _send(watch), _send(watch)
    assert first["id"] == again["id"] and len(watch.state.inbox()) == 1
    _send(watch, "open")
    assert len(watch.state.inbox()) == 2


def test_ack_removes_only_what_was_acted_on():
    from orbital.state import State
    watch = FakeWatch(State(), OFFICE)
    a, b = _send(watch), _send(watch, "open")
    assert companion.inbox_ack(watch.state, [a["id"], "no-existe"]) == 1
    assert [i["id"] for i in companion.inbox_pending(watch.state)] == [b["id"]]


def test_the_inbox_keeps_the_20_newest():
    from orbital.state import State
    watch = FakeWatch(State())
    for n in range(25):
        _send(watch, "open", kind="movie", meta_id=f"tt{n}")
    pending = watch.state.inbox()
    assert len(pending) == companion.INBOX_LIMIT == 20
    assert pending[0]["meta_id"] == "tt5" and pending[-1]["meta_id"] == "tt24"


def test_without_an_iphone_it_is_a_409_in_words_and_nothing_is_queued(library):
    library.config.server.token = ""
    main = create_app(library.config, library)
    with TestClient(main, base_url="http://127.0.0.1:8710", client=("127.0.0.1", 1)) as c:
        r = c.post("/api/companion/send", json={"action": "open", "kind": "movie", "meta_id": "tt1"})
        assert r.status_code == 409 and "Ajustes › Cuentas" in r.json()["detail"]
    assert library.state.inbox() == []


def test_the_phone_check_is_remembered_so_the_menus_do_not_wait_on_tailscale():
    calls = []

    def tailscale():
        calls.append(1)
        return "https://legion.tail1.ts.net"

    clock = [100.0]
    assert companion.phone_ready(config(), tailscale, now=lambda: clock[0]) is True
    clock[0] += 30
    assert companion.phone_ready(config(), tailscale, now=lambda: clock[0]) is True and len(calls) == 1
    clock[0] += 40  # pasó el minuto: se vuelve a preguntar
    companion.phone_ready(config(), tailscale, now=lambda: clock[0])
    assert len(calls) == 2


def test_the_route_queues_and_the_iphone_gets_it_with_now_and_acks_it(library, monkeypatch):
    library.config.server.token, library.config.server.token_is_ephemeral = "secreto", False
    monkeypatch.setattr(companion.alexa_setup, "tailscale_url", lambda: "https://legion.tail1.ts.net")
    monkeypatch.setattr(type(library.watch), "title_details", lambda self, kind, meta_id: {
        "kind": kind, "title": "Dune", "poster": None, **({} if kind == "movie" else OFFICE)})
    main = create_app(library.config, library)
    auth = {"Authorization": "Bearer secreto"}
    with TestClient(main, base_url="http://127.0.0.1:8710", client=("127.0.0.1", 1)) as c:
        assert c.get("/api/companion/phone").json() == {"ready": True}
        r = c.post("/api/companion/send", json={"action": "download", "kind": "movie", "meta_id": "tt1"})
        assert r.status_code == 200 and r.json()["item"]["title"] == "Dune"
        assert c.post("/api/companion/send", json={"action": "bailar", "kind": "movie", "meta_id": "tt1"}).status_code == 409
    with TestClient(create_public_app(library.config, main), client=("127.0.0.1", 2)) as c:
        pending = c.get("/api/companion/now", headers=auth).json()["inbox"]
        assert [i["title"] for i in pending] == ["Dune"]
        assert c.post("/api/companion/inbox/ack", json={"ids": [pending[0]["id"]]}).status_code == 401
        assert c.post("/api/companion/inbox/ack", json={"ids": [pending[0]["id"]]}, headers=auth).json() == {"removed": 1}
        assert c.get("/api/companion/now", headers=auth).json()["inbox"] == []


def test_the_inbox_survives_a_restart(tmp_path):
    from orbital.state import State
    path = tmp_path / "state.json"
    watch = FakeWatch(State(path), OFFICE)
    kept = _send(watch)
    again = State(path)
    assert [i["id"] for i in again.inbox()] == [kept["id"]]
    again.inbox_ack([kept["id"]])
    assert State(path).inbox() == []
