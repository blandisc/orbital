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
    def __init__(self):
        self.sent = []

    def command(self, *args):
        self.sent.append(args)


def test_remote_maps_buttons_to_mpv_commands():
    remote = player.PlayerRemote(FakeMpv())
    assert remote.actions(A_BUTTON, 0) == [("cycle", "pause")]
    assert remote.actions(A_BUTTON, .1) == []  # mantener A no repite
    assert remote.actions(0, .2) == []
    assert remote.actions(B_BUTTON, .3) == [("quit",)]
    assert remote.actions(X_BUTTON | Y_BUTTON, .4) == [("cycle", "audio"), ("cycle", "sub")]
    assert remote.actions(player.RB, .5) == [("seek", 60, "relative")]


def test_remote_repeats_seek_and_volume_while_held():
    remote = player.PlayerRemote(FakeMpv(), delay=.35, rate=.15)
    assert remote.actions(DPAD_LEFT, 0) == [("seek", -10, "relative")]
    assert remote.actions(DPAD_LEFT, .2) == []
    assert remote.actions(DPAD_LEFT, .36) == [("seek", -10, "relative")]
    assert remote.actions(DPAD_LEFT, .52) == [("seek", -10, "relative")]
    assert remote.actions(DPAD_UP, .6) == [("add", "volume", 5)]


def test_remote_leaves_home_and_select_start_to_orbital():
    remote = player.PlayerRemote(FakeMpv())
    assert remote.actions(GUIDE | A_BUTTON, 0) == []
    assert remote.actions(A_BUTTON, .1) == [("cycle", "pause")]  # al soltar Home, A vuelve a contar


def test_remote_shows_feedback_after_each_action():
    mpv = FakeMpv()
    remote = player.PlayerRemote(mpv)
    remote.update(DPAD_LEFT, 0)
    remote.update(0, .1)
    remote.update(Y_BUTTON, .2)
    assert mpv.sent[0] == ("seek", -10, "relative") and mpv.sent[1] == ("show-progress",)
    assert mpv.sent[2] == ("cycle", "sub") and mpv.sent[3][0] == "show-text"


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
