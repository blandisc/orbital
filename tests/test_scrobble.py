"""Scrobble de Trakt desde el reproductor, con un Trakt falso (nunca sale a internet)."""

from __future__ import annotations

import json
import logging
import re
import time

from orbital import player
from orbital.library import trakt
from orbital.scrobble import TraktScrobbler, label, percent


class Creds:
    def __init__(self, linked=True):
        self.data = {trakt.TOKENS_KEY: json.dumps({"access_token": "tok", "refresh_token": "ref",
                                                   "expires_at": time.time() + 86400})} if linked else {}

    def get(self, key):
        return self.data.get(key)

    def set(self, key, value):
        self.data[key] = value


class FakeNet:
    def __init__(self):
        self.routes = []
        self.calls = []

    def on(self, pattern, reply):
        self.routes.append((pattern, reply))
        return self

    def __call__(self, url, *, method="GET", headers=None, body=None, timeout=10):
        self.calls.append((method, url, body))
        for pattern, reply in self.routes:
            if re.search(pattern, url):
                value = reply(url, body) if callable(reply) else reply
                if isinstance(value, Exception):
                    raise value
                return value
        return 404, None

    def scrobbles(self):
        return [(url.rsplit("/", 1)[1], body) for method, url, body in self.calls if "/scrobble/" in url]


def setup(monkeypatch, linked=True, reply=(201, {})):
    net = FakeNet().on("/scrobble/", reply)
    monkeypatch.setattr(trakt, "http_json", net)
    t = trakt.Trakt("cid", "", Creds(linked))
    return net, t, TraktScrobbler(lambda: t, clock=lambda: 1000.0)


MOVIE = {"kind": "movie", "meta_id": "tt1375666", "video_id": "tt1375666", "title": "Origen"}
EPISODE = {"kind": "series", "meta_id": "tt0386676", "video_id": "tt0386676:2:5", "title": "The Office"}


# ---------------------------------------------------------------- piezas
def test_percent_and_labels():
    assert percent(30, 120) == 25.0 and percent(500, 120) == 100.0 and percent(-5, 120) == 0.0
    assert percent(10, 0) is None and percent(10, None) is None
    assert label(EPISODE) == "The Office T2 · E5" and label(MOVIE) == "Origen"


def test_targets_are_built_from_the_imdb_ids():
    assert trakt.scrobble_target("movie", "tt1375666", "tt1375666") == {"movie": {"ids": {"imdb": "tt1375666"}}}
    assert trakt.scrobble_target("series", "tt0386676", "tt0386676:2:5") == {
        "show": {"ids": {"imdb": "tt0386676"}}, "episode": {"season": 2, "number": 5}}
    assert trakt.scrobble_target("series", "tt0386676", "tt0386676") is None  # sin episodio no se sabe qué ves
    assert trakt.scrobble_target("movie", "kitsu:1", "kitsu:1") is None


def test_each_action_goes_to_its_endpoint_with_a_percentage(monkeypatch):
    net, t, s = setup(monkeypatch)
    s.event("start", EPISODE, 300, 1200)
    s.event("pause", EPISODE, 600, 1200)
    s.event("stop", EPISODE, 1200, 1200)
    s.wait()
    target = {"show": {"ids": {"imdb": "tt0386676"}}, "episode": {"season": 2, "number": 5}}
    assert net.scrobbles() == [("start", {**target, "progress": 25.0}), ("pause", {**target, "progress": 50.0}),
                               ("stop", {**target, "progress": 100.0})]
    assert s.snapshot() == {"last": {"title": "The Office T2 · E5", "action": "stop", "at": 1000.0}, "error": None}


def test_a_409_on_stop_is_not_an_error(monkeypatch):
    net, t, s = setup(monkeypatch, reply=(409, {"watched_at": "x"}))
    s.event("stop", MOVIE, 7000, 7200)
    s.wait()
    assert s.snapshot()["error"] is None and s.snapshot()["last"]["action"] == "stop"


def test_a_401_renews_the_session_once_and_retries(monkeypatch):
    answers = iter([(401, None), (201, {})])
    net, t, s = setup(monkeypatch, reply=lambda url, body: next(answers))
    net.on("/oauth/token", (200, {"access_token": "nuevo", "refresh_token": "r2", "expires_in": 7200}))
    s.event("start", MOVIE, 10, 7200)
    s.wait()
    assert len(net.scrobbles()) == 2 and sum("/oauth/token" in u for _, u, _ in net.calls) == 1
    assert s.snapshot()["error"] is None
    assert json.loads(t.credentials.get(trakt.TOKENS_KEY))["access_token"] == "nuevo"


def test_a_server_error_is_said_in_words_and_logged_once_per_video(monkeypatch, caplog):
    net, t, s = setup(monkeypatch, reply=(500, None))
    with caplog.at_level(logging.WARNING, logger="orbital.scrobble"):
        for action in ("start", "pause", "start", "stop"):
            s.event(action, MOVIE, 100, 7200)
        s.wait()
        s.event("start", EPISODE, 100, 1200)  # otro video: se vuelve a avisar
        s.wait()
    assert "HTTP 500" in s.snapshot()["error"] and s.snapshot()["last"] is None
    assert len([r for r in caplog.records if "No pude avisarle a Trakt" in r.message]) == 2


def test_nothing_is_sent_without_trakt_or_for_live_tv(monkeypatch):
    net, t, s = setup(monkeypatch, linked=False)
    s.event("start", MOVIE, 10, 7200)
    s.wait()
    assert net.scrobbles() == []
    net, t, s = setup(monkeypatch)
    s.event("start", {"kind": "tv", "meta_id": "tt1", "video_id": "tt1", "title": "Canal"}, 10, 7200)
    s.event("start", MOVIE, 10, 0)  # sin duración no hay porcentaje
    s.wait()
    assert net.scrobbles() == []
    assert TraktScrobbler().event("start", MOVIE, 10, 7200) is None  # ni siquiera hay Trakt


def test_a_dead_network_never_raises_into_the_player(monkeypatch):
    net, t, s = setup(monkeypatch, reply=OSError("sin red"))
    s.event("start", MOVIE, 10, 7200)
    s.wait()
    assert "No pude conectar con Trakt" in s.snapshot()["error"]


# ---------------------------------------------------------------- el reproductor lo avisa
class Mpv:
    def __init__(self):
        self.props = {"pause": False, "volume": 80, "track-list": []}
        self.sent = []

    def command(self, *args):
        self.sent.append(args)

    def command_named(self, **args):
        pass

    def get(self, prop):
        return self.props.get(prop)


class Script:
    """process.poll(): cada vuelta del vigilante aplica un paso de la película y, al acabar, mpv se «cierra»."""

    def __init__(self, mpv, steps):
        self.mpv, self.steps = mpv, list(steps)

    def poll(self):
        if not self.steps:
            return 0
        self.mpv.props.update(self.steps.pop(0))
        return None


def watch(meta, steps, live=False):
    mpv, got = Mpv(), []
    p = player.OrbitalPlayer(mpv=mpv)
    p.POLL = 0
    p.on_scrobble = lambda action, m, pos, dur: got.append((action, round(pos), round(dur)))
    p.current = playback = player.Playback("Peli", Script(mpv, steps), 0, {})
    p.segment = player.Segment(meta, "Peli", "http://x/v", live=live)
    if live:
        p.segment.loaded -= 60
    p._watch(playback)
    return got


def test_the_player_reports_play_pause_resume_seek_and_stop():
    got = watch(MOVIE, [
        {"time-pos": 10.0, "duration": 6000.0},                  # primera imagen
        {"time-pos": 11.0},                                       # ya viendo: start
        {"time-pos": 12.0, "pause": True},                        # pausa
        {"time-pos": 12.0, "pause": False},                       # reanuda: start
        {"time-pos": 3000.0},                                     # salto grande: start con el avance nuevo
        {"time-pos": 3001.0},
    ])
    assert got == [("start", 11, 6000), ("pause", 11, 6000), ("start", 12, 6000), ("start", 3000, 6000),
                   ("stop", 3001, 6000)]


def test_a_seek_while_paused_reports_the_new_position_as_pause():
    got = watch(MOVIE, [
        {"time-pos": 10.0, "duration": 6000.0}, {"time-pos": 11.0}, {"pause": True, "time-pos": 11.0},
        {"time-pos": 4000.0}])
    assert [g[0] for g in got] == ["start", "pause", "pause", "stop"] and got[2][1] == 4000


def test_a_small_skip_does_not_report_again():
    got = watch(MOVIE, [{"time-pos": 10.0, "duration": 6000.0}, {"time-pos": 11.0}, {"time-pos": 41.0}, {"time-pos": 42.0}])
    assert [g[0] for g in got] == ["start", "stop"]


def test_opening_and_closing_before_any_image_reports_nothing():
    assert watch(MOVIE, [{}, {}]) == []


def test_live_tv_reports_nothing_to_trakt():
    live = {"kind": "tv", "meta_id": "tv:canal", "video_id": "tv:canal", "title": "Canal"}
    assert watch(live, [{"time-pos": 10.0, "path": "http://x/v"}] * 3, live=True) == []


def test_a_filler_clip_does_not_mark_the_movie_as_watched(monkeypatch):
    """El 22 de octubre una fuente de Hope (2 h 36 min) era un clip de 30 s: al «terminar», Trakt la dio por vista y se
    perdió dónde ibas. Un video que dura mucho menos que una película (o que un episodio) no se cuenta."""
    from orbital.scrobble import not_the_video

    assert not_the_video(MOVIE, 30) and not not_the_video(MOVIE, 9406) and not not_the_video(MOVIE, 0)
    assert not_the_video(EPISODE, 30) and not not_the_video(EPISODE, 22 * 60)
    assert not not_the_video({"kind": "channel"}, 30)
    net, t, s = setup(monkeypatch)
    s.event("stop", MOVIE, 30, 30)
    s.event("start", MOVIE, 60, 7200)
    s.wait()
    assert [action for action, _ in net.scrobbles()] == ["start"]


def test_a_401_while_reading_renews_the_session_instead_of_forgetting_it(monkeypatch):
    """Al leer (tus listas, el avance), un 401 renueva la sesión y reintenta; antes la borraba sin intentarlo y había que
    volver a conectar Trakt en Ajustes."""
    net, t, _ = setup(monkeypatch)
    answers = iter([(401, None), (200, [{"id": 1}])])
    net.on("/sync/watchlist", lambda url, body: next(answers))
    net.on("/oauth/token", (200, {"access_token": "nuevo", "refresh_token": "r2", "expires_in": 7200}))
    assert t._get("/sync/watchlist") == [{"id": 1}]
    assert json.loads(t.credentials.get(trakt.TOKENS_KEY))["access_token"] == "nuevo"


def test_trakt_being_down_never_disconnects_you(monkeypatch):
    """Si Trakt está caído al renovar (5xx), la sesión se queda y se reintenta después; solo un rechazo de verdad
    (400/401) obliga a reconectar."""
    import pytest

    net, t, _ = setup(monkeypatch)
    net.on("/sync/watchlist", (401, None)).on("/oauth/token", (503, None))
    with pytest.raises(trakt.TraktError) as caught:
        t._get("/sync/watchlist")
    assert not isinstance(caught.value, trakt.TraktAuthError) and t.credentials.get(trakt.TOKENS_KEY)
    net.routes = [r for r in net.routes if r[0] != "/oauth/token"]
    net.on("/oauth/token", (400, {"error": "invalid_grant"}))
    with pytest.raises(trakt.TraktAuthError):
        t._get("/sync/watchlist")
    assert t.credentials.get(trakt.TOKENS_KEY) is None


# ---------------------------------------------------------------- el avance de Trakt al retomar (como el iPhone)
PLAYBACK = [
    {"progress": 42.5, "paused_at": "2026-10-26T14:00:00.000Z", "type": "movie",
     "movie": {"title": "Origen", "ids": {"imdb": "tt1375666"}, "runtime": 148}},
    {"progress": 30.0, "paused_at": "2026-10-26T13:00:00.000Z", "type": "episode",
     "episode": {"season": 2, "number": 5, "runtime": 22}, "show": {"ids": {"imdb": "tt0386676"}}},
    {"progress": 10.0, "paused_at": "2026-10-20T13:00:00.000Z", "type": "episode",  # uno viejo del mismo episodio
     "episode": {"season": 2, "number": 5, "runtime": 22}, "show": {"ids": {"imdb": "tt0386676"}}},
    {"progress": 50.0, "paused_at": "nunca", "type": "movie", "movie": {"ids": {"imdb": "tt1"}}},
    {"progress": 50.0, "paused_at": "2026-10-26T13:00:00.000Z", "type": "movie", "movie": {"ids": {"tmdb": 5}}},
]


def when(text):
    from datetime import datetime
    return datetime.fromisoformat(text.replace("Z", "+00:00")).timestamp()


def test_playback_is_read_by_imdb_and_episode_and_cached_for_a_minute(monkeypatch):
    net, t, s = setup(monkeypatch)
    net.on("/sync/playback", (200, PLAYBACK))
    got = t.playback(now=1000)
    assert set(got) == {"tt1375666", "tt0386676:2:5"}
    assert got["tt0386676:2:5"] == {"percent": 30.0, "paused_at": when("2026-10-26T13:00:00Z"), "runtime": 22 * 60}
    assert got["tt1375666"]["runtime"] == 148 * 60
    assert "extended=full" in net.calls[-1][1]
    t.playback(now=1050)
    assert sum("/sync/playback" in c[1] for c in net.calls) == 1  # un minuto de caché
    t.playback(now=1061)
    assert sum("/sync/playback" in c[1] for c in net.calls) == 2


def test_pausing_or_closing_forgets_the_cached_playback(monkeypatch):
    net, t, s = setup(monkeypatch)
    net.on("/sync/playback", (200, PLAYBACK))
    t.playback()
    s.event("start", MOVIE, 10, 7200)
    s.wait()
    assert t._playback is not None  # empezar no cambia el punto guardado
    s.event("pause", MOVIE, 600, 7200)
    s.wait()
    assert t._playback is None
    t.playback()
    s.event("stop", MOVIE, 900, 7200)
    s.wait()
    assert t._playback is None


def test_the_most_recent_resume_point_wins_like_the_iphone():
    tr = {"percent": 50.0, "paused_at": 2000.0, "runtime": 6000.0}
    assert trakt.latest_resume(300.0, 1000.0, 7200.0, tr) == 3600  # Trakt más nuevo: el punto exacto, con la duración de Stremio
    assert trakt.latest_resume(300.0, 3000.0, 7200.0, tr) == 300.0  # Stremio más nuevo
    assert trakt.latest_resume(0.0, 3000.0, 7200.0, tr) == 0.0  # en Stremio lo terminaste después: desde el inicio
    assert trakt.latest_resume(0.0, None, None, tr) == 3000  # solo Trakt: su propia duración
    assert trakt.latest_resume(120.0, None, None, None) == 120.0  # sin Trakt: lo de siempre
    assert trakt.latest_resume(120.0, 1000.0, None, {**tr, "percent": 85.0}) == 5100.0  # también arriba de 80 %: el punto exacto
    assert trakt.latest_resume(0.0, None, None, {**tr, "runtime": None}) == 0.0  # sin duración no se adivina
    assert trakt.playback_key("series", "tt0386676", "tt0386676:2:5") == "tt0386676:2:5"
    assert trakt.playback_key("movie", "tt1375666", "tt1375666") == "tt1375666"
    assert trakt.playback_key("series", "kitsu:1", "kitsu:1:2") is None


def test_watch_resumes_from_trakt_when_the_iphone_paused_later(monkeypatch):
    from types import SimpleNamespace

    from orbital.watch import Watch

    net, t, s = setup(monkeypatch)
    net.on("/sync/playback", (200, PLAYBACK))
    stremio_item = {"state": {"video_id": "tt0386676:2:5", "timeOffset": 120_000, "duration": 1_320_000,
                              "lastWatched": "2026-10-25T20:00:00.000Z"}}
    w = SimpleNamespace(scrobbler=s, credentials=Creds(), stremio_client=SimpleNamespace(library_item=lambda key, meta: stremio_item))
    w._trakt_playback = lambda m, v: Watch._trakt_playback(w, m, v)
    # El iPhone pausó al 30 % hoy (más nuevo que Stremio, ayer): 30 % de 22 min (la duración de Stremio), exacto.
    assert Watch.resume_position(w, "tt0386676", "tt0386676:2:5") == .3 * 1320
    stremio_item["state"]["lastWatched"] = "2026-10-26T15:00:00.000Z"  # luego viste más aquí: gana Stremio
    assert Watch.resume_position(w, "tt0386676", "tt0386676:2:5") == 120.0
    t.credentials.set(trakt.TOKENS_KEY, None)  # sin Trakt conectado: solo Stremio, sin pedirle nada
    stremio_item["state"]["lastWatched"] = "2026-10-25T20:00:00.000Z"
    t.forget_playback()
    assert Watch.resume_position(w, "tt0386676", "tt0386676:2:5") == 120.0
