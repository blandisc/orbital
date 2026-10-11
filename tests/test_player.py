from orbital import player
from orbital.gamepad import A_BUTTON, B_BUTTON, DPAD_LEFT, DPAD_UP, GUIDE, X_BUTTON, Y_BUTTON
from orbital.library import cinemeta, stremio_api, streams

RD_URL = "https://real-debrid.example/d/abc/movie.mkv"


def test_stream_url_direct_or_via_stremio_server():
    assert player.stream_url({"url": RD_URL}) == RD_URL
    assert player.stream_url({"infoHash": "abc", "fileIdx": 2}) == "http://127.0.0.1:11470/abc/2"
    assert player.stream_url({"infoHash": "abc"}) == "http://127.0.0.1:11470/abc/-1"
    assert player.stream_url({"ytId": "x"}) is None


def test_command_full_screen_languages_and_resume():
    cmd = player.build_command("mpv.exe", RD_URL, "Interstellar", start=2530.4, audio="en", subtitles="en")
    assert cmd[:2] == ["mpv.exe", RD_URL]
    assert f"--input-ipc-server={player.PIPE}" in cmd and "--fullscreen" in cmd
    assert "--alang=en,eng,English" in cmd and "--slang=en,eng,English" in cmd
    assert "--start=2530" in cmd
    assert not any(a.startswith("--start") for a in player.build_command("mpv.exe", RD_URL, "x", start=3))


class FakeMpv:
    """mpv falso: guarda comandos y responde propiedades."""

    def __init__(self, props=None):
        self.sent = []
        self.overlays = {}
        self.props = {"pause": False, "time-pos": 600.0, "duration": 6000.0, "volume": 80, "track-list": TRACKS,
                      **(props or {})}

    def command(self, *args):
        self.sent.append(args)
        if args[:2] == ("set_property", "pause"):
            self.props["pause"] = args[2]
        if args == ("cycle", "pause"):
            self.props["pause"] = not self.props["pause"]

    def command_named(self, **args):
        self.overlays[args["id"]] = args["data"] if args["format"] != "none" else None

    def get(self, prop):
        return self.props.get(prop)


TRACKS = [
    {"id": 1, "type": "video"},
    {"id": 1, "type": "audio", "lang": "eng", "codec": "eac3", "demux-channel-count": 6, "selected": True},
    {"id": 2, "type": "audio", "lang": "spa", "title": "Latino", "codec": "aac", "demux-channel-count": 2},
    {"id": 1, "type": "sub", "lang": "eng", "selected": True},
    {"id": 2, "type": "sub", "lang": "spa", "forced": True},
]


def make_player(**props):
    mpv = FakeMpv(props)
    p = player.OrbitalPlayer(mpv=mpv)
    p.current = player.Playback("Interstellar", None, 0, {})
    return p, mpv


def test_remote_turns_buttons_into_names_with_repeat():
    pressed = []
    remote = player.PlayerRemote(pressed.append, delay=.35, rate=.15)
    assert remote.actions(A_BUTTON, 0) == ["a"]
    assert remote.actions(A_BUTTON, .5) == []  # mantener A no repite
    assert remote.actions(0, .6) == []
    assert remote.actions(X_BUTTON | Y_BUTTON, .7) == ["x", "y"]
    assert remote.actions(DPAD_LEFT, 1) == ["left"]
    assert remote.actions(DPAD_LEFT, 1.2) == []
    assert remote.actions(DPAD_LEFT, 1.36) == ["left"]  # mantener: continuo
    assert remote.actions(GUIDE | A_BUTTON, 2) == []  # Home es de Orbital
    remote.update(player.RB, 3)
    assert pressed == ["rb"]


def test_a_pauses_and_shows_the_bar_with_the_legend():
    p, mpv = make_player()
    p.press("a")
    assert ("cycle", "pause") in mpv.sent
    hud = mpv.overlays[1]
    assert "Interstellar" in hud and "EN PAUSA" in hud and "Subtítulos" in hud and "Volumen" in hud
    assert "Audio: Inglés" in hud and "Subtítulos: Inglés" in hud and "10:00" in hud


def test_seek_and_volume():
    p, mpv = make_player()
    p.press("rb")
    p.press("left")
    p.press("up")
    assert ("seek", 60, "relative") in mpv.sent and ("seek", -10, "relative") in mpv.sent
    assert ("add", "volume", 5) in mpv.sent and "Volumen 80 %" in mpv.overlays[3]


def test_audio_menu_lists_tracks_and_switches():
    p, mpv = make_player()
    p.press("x")
    assert p.menu.kind == "audio" and [o["label"] for o in p.menu.options] == [
        "Inglés · 5.1 · E-AC3", "Español · Latino · Estéreo · AAC"]
    assert p.menu.index == 0 and "AUDIO" in mpv.overlays[2] and mpv.overlays.get(1) is None
    p.press("down")
    p.press("a")
    assert ("set_property", "aid", 2) in mpv.sent and p.menu is None and mpv.overlays[2] is None
    assert "Audio: Español" in mpv.overlays[3]


def test_subtitle_menu_has_off_and_addon_search():
    p, mpv = make_player()
    p._fallback_subs, p._subs_lang = (lambda: []), "es"
    p.press("y")
    labels = [o["label"] for o in p.menu.options]
    assert labels[0] == "Sin subtítulos" and "Español · Forzados" in labels and labels[-1].startswith("Buscar subtítulos")
    assert p.menu.index == 1  # en la que está puesta
    p.press("up")
    p.press("a")
    assert ("set_property", "sid", "no") in mpv.sent


def test_b_closes_the_menu_before_closing_the_video():
    p, mpv = make_player()
    p.press("y")
    p.press("b")
    assert p.menu is None and ("quit",) not in mpv.sent
    p.press("b")
    assert ("quit",) in mpv.sent


def test_has_language():
    tracks = [{"type": "audio", "lang": "eng"}, {"type": "sub", "lang": "spa"}]
    assert player.has_language(tracks, "audio", {"en", "eng"})
    assert not player.has_language(tracks, "sub", {"en", "eng"})


# --- progreso en Stremio --------------------------------------------------------------------

EXISTING = {
    "_id": "tt0386676", "name": "The Office", "type": "series", "removed": False, "temp": False,
    "_ctime": "2024-01-01T00:00:00.000Z", "_mtime": "2024-01-02T00:00:00.000Z",
    "state": {"video_id": "tt0386676:2:3", "timeOffset": 600_000, "duration": 1_320_000, "timeWatched": 600_000,
              "overallTimeWatched": 9_000_000, "timesWatched": 4, "flaggedWatched": 0, "watched": "x:1:0"},
}


def test_resume_only_same_video_and_not_finished():
    assert stremio_api.resume_seconds(EXISTING, "tt0386676:2:3") == 600
    assert stremio_api.resume_seconds(EXISTING, "tt0386676:2:4") == 0
    done = {"state": {**EXISTING["state"], "timeOffset": 1_300_000}}
    assert stremio_api.resume_seconds(done, "tt0386676:2:3") == 0
    assert stremio_api.resume_seconds(None, "x") == 0


def test_progress_keeps_the_item_and_only_touches_state():
    item = stremio_api.with_progress(EXISTING, meta_id="tt0386676", kind="series", name="The Office", poster=None,
                                     video_id="tt0386676:2:3", position=900, duration=1320, watched=300,
                                     next_video="tt0386676:2:4", now=1_760_000_000)
    assert item["removed"] is False and item["_ctime"] == EXISTING["_ctime"]
    assert item["state"]["timeOffset"] == 900_000 and item["state"]["timeWatched"] == 900_000
    assert item["state"]["overallTimeWatched"] == 9_300_000 and item["state"]["watched"] == "x:1:0"
    assert item["_mtime"].endswith("Z") and item["state"]["lastWatched"] == item["_mtime"]
    assert EXISTING["state"]["timeOffset"] == 600_000  # no modifica el original


def test_finished_episode_moves_continue_watching_to_the_next():
    item = stremio_api.with_progress(EXISTING, meta_id="tt0386676", kind="series", name="The Office", poster=None,
                                     video_id="tt0386676:2:3", position=1300, duration=1320, watched=700,
                                     next_video="tt0386676:2:4", now=1_760_000_000)
    state = item["state"]
    assert state["video_id"] == "tt0386676:2:4" and state["timeOffset"] == 1 and state["timesWatched"] == 5
    assert stremio_api.parse_item(item).in_continue


def test_finished_movie_leaves_continue_watching():
    item = stremio_api.with_progress(None, meta_id="tt0816692", kind="movie", name="Interstellar", poster="p.jpg",
                                     video_id="tt0816692", position=9900, duration=10140, watched=9000,
                                     next_video=None, now=1_760_000_000)
    assert item["temp"] is True and item["type"] == "movie" and item["poster"] == "p.jpg"
    assert item["state"]["timeOffset"] == 0 and item["state"]["flaggedWatched"] == 1
    assert not stremio_api.parse_item(item).in_continue


def test_new_item_half_watched_appears_in_continue():
    item = stremio_api.with_progress(None, meta_id="tt0816692", kind="movie", name="Interstellar", poster=None,
                                     video_id="tt0816692", position=3000, duration=10140, watched=3000,
                                     next_video=None, now=1_760_000_000)
    watchable = stremio_api.parse_item(item)
    assert watchable.in_continue and round(watchable.progress, 2) == 0.30


def test_next_episode_crosses_seasons_and_skips_specials():
    meta = {"videos": [
        {"id": "s:1:1", "season": 1, "episode": 1}, {"id": "s:1:2", "season": 1, "episode": 2},
        {"id": "s:2:1", "season": 2, "episode": 1}, {"id": "s:0:1", "season": 0, "episode": 1},
    ]}
    assert cinemeta.next_episode(meta, "s:1:1") == "s:1:2"
    assert cinemeta.next_episode(meta, "s:1:2") == "s:2:1"
    assert cinemeta.next_episode(meta, "s:2:1") is None
    assert cinemeta.next_episode(meta, "nope") is None


def test_subtitles_from_subtitle_addons_in_your_language(monkeypatch):
    class Client:
        def request(self, method, params):
            return {"addons": [
                {"transportUrl": "https://torrentio/manifest.json", "manifest": {"name": "Torrentio", "resources": ["stream"]}},
                {"transportUrl": "https://opensubs/manifest.json", "manifest": {"name": "OpenSubtitles", "resources": ["subtitles"]}},
            ]}

    asked = []

    def fake_get(self, addon, path):
        asked.append((addon["name"], path))
        return {"subtitles": [{"url": "https://subs/en.srt", "lang": "eng"}, {"url": "https://subs/es.srt", "lang": "spa"}]}

    monkeypatch.setattr(streams.StreamFinder, "_get_json", fake_get)
    finder = streams.StreamFinder(Client())
    assert finder.subtitles("key", "movie", "tt0816692", "en") == ["https://subs/en.srt"]
    assert asked == [("OpenSubtitles", "subtitles/movie/tt0816692.json")]
    # Un addon solo de subtítulos no se usa para buscar fuentes.
    monkeypatch.setattr(streams.StreamFinder, "_fetch", lambda self, addon, kind, vid: asked.append(addon["name"]) or [])
    finder.find("key", "movie", "tt0816692", streams.Preferences())
    assert asked[-1] == "Torrentio"


def test_idle_rule():
    assert not player.idle_expired(0, 899, 900)
    assert player.idle_expired(0, 900, 900)
    assert not player.idle_expired(0, 10_000, 0)  # 0 = nunca


def test_touch_tap_pauses_and_double_tap_does_not_leave_fullscreen():
    assert "MBTN_LEFT cycle pause" in player.TOUCH_BINDINGS and "MBTN_LEFT_DBL ignore" in player.TOUCH_BINDINGS
    cmd = player.build_command("mpv.exe", "u", "t", bindings="C:/x/mpv-input.conf")
    assert "--input-conf=C:/x/mpv-input.conf" in cmd
