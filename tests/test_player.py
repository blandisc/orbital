from orbital import player
from orbital.gamepad import A_BUTTON, DPAD_LEFT, GUIDE, X_BUTTON, Y_BUTTON
from orbital.library import cinemeta, streams, stremio_api

RD_URL = "https://real-debrid.example/d/abc/movie.mkv"


def test_stream_url_direct_or_via_stremio_server():
    assert player.stream_url({"url": RD_URL}) == RD_URL
    assert player.stream_url({"infoHash": "abababababababababababababababababababab", "fileIdx": 2}) == "http://127.0.0.1:11470/abababababababababababababababababababab/2"
    assert player.stream_url({"infoHash": "abababababababababababababababababababab"}) == "http://127.0.0.1:11470/abababababababababababababababababababab/-1"
    # Lo que un complemento no debe poder colar: archivos locales, opciones de mpv, hashes raros.
    assert player.stream_url({"url": "C:/Windows/win.ini"}) is None
    assert player.stream_url({"url": "--script=x.lua"}) is None
    assert player.stream_url({"infoHash": "../../x"}) is None
    assert player.stream_url({"infoHash": "abababababababababababababababababababab", "fileIdx": "1/../x"}) == "http://127.0.0.1:11470/abababababababababababababababababababab/-1"
    assert player.stream_url({"ytId": "x"}) is None


def test_command_full_screen_languages_and_resume():
    cmd = player.build_command("mpv.exe", RD_URL, "Interstellar", start=2530.4, audio="en", subtitles="en")
    assert cmd[0] == "mpv.exe" and cmd[-2:] == ["--", RD_URL]
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
    assert ("set_property", "pause", True) in mpv.sent
    hud = mpv.overlays[1]
    assert "Interstellar" in hud and "En pausa" in hud and "Seguir" in hud and "Audio y subtítulos" in hud
    assert "Subtítulos en inglés" in hud and "10:00" in hud and "EN PAUSA" not in hud


def test_seek_and_volume():
    p, mpv = make_player()
    p.press("rb")
    p.press("left")
    p.press("up")
    assert ("seek", 60, "relative") in mpv.sent and ("seek", -10, "relative") in mpv.sent
    assert ("set_property", "volume", 85) in mpv.sent and "}85" in mpv.overlays[3]  # el volumen que se pidió (80 + 5), con su barra
    assert "−10 s" in mpv.overlays[1]  # adelantando: la burbuja dice cuánto


def test_audio_menu_lists_tracks_and_switches():
    p, mpv = make_player()
    p.press("x")
    assert p.menu.kind == "tracks" and p.menu.column.key == "audio" and [o["label"] for o in p.menu.options] == [
        "Inglés · 5.1 · E-AC3", "Español · Latino · Estéreo · AAC"]
    assert [c.key for c in p.menu.columns] == ["audio", "sub", "size"]
    assert p.menu.index == 0 and "Tamaño de los subtítulos" in mpv.overlays[2] and mpv.overlays.get(1) is None
    p.press("down")
    p.press("a")
    assert ("set_property", "aid", 2) in mpv.sent and p.menu is None and mpv.overlays[2] is None
    assert "Audio: Español" in mpv.overlays[3]


def test_subtitle_menu_has_off_and_addon_search():
    p, mpv = make_player()
    p._fallback_subs, p._subs_lang = (list), "es"
    p.press("x")
    p.press("right")  # columna Subtítulos
    labels = [o["label"] for o in p.menu.options]
    assert labels[0] == "Sin subtítulos" and "Español · Forzados" in labels and labels[-1].startswith("Buscar en español")
    assert p.menu.index == 1  # en la que está puesta
    p.press("up")
    p.press("a")
    assert ("set_property", "sid", "no") in mpv.sent


def test_b_closes_the_menu_before_closing_the_video():
    p, mpv = make_player()
    p.press("x")
    p.press("b")
    assert p.menu is None and ("quit",) not in mpv.sent
    p.press("b")  # pregunta antes de salir
    assert ("quit",) not in mpv.sent
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


def test_choosing_audio_or_subtitles_is_remembered_for_that_series():
    p, mpv = make_player()
    p.current = player.Playback("Los Simpson", None, 0, {"meta_id": "tt0096697"})
    seen = []
    p.on_language = lambda meta, kind, lang: seen.append((meta["meta_id"], kind, lang))
    p._choose({"label": "Español", "action": ("aid", 2), "lang": "spa"})
    p._choose({"label": "Sin subtítulos", "action": ("sid", "no")})
    assert seen == [("tt0096697", "audio", "spa"), ("tt0096697", "subtitles", "")]


def test_each_series_keeps_its_own_language(library):
    from orbital.watch import language_code

    assert [language_code(c) for c in ("spa", "es-MX", "eng", "", "jpn")] == ["es", "es", "en", "", None]
    library.watch._remember_language({"meta_id": "tt0096697", "title": "Los Simpson"}, "audio", "spa")
    library.watch._remember_language({"meta_id": "tt0096697"}, "subtitles", "")
    prefs, subs = library.watch.language_for("tt0096697")
    assert prefs.audio == "es" and subs == ""
    other, other_subs = library.watch.language_for("tt0386676")  # otra serie: lo de Ajustes
    assert other.audio == library.watch.stream_prefs.audio and other_subs == library.watch.subtitles_lang


def test_player_and_interface_share_one_palette():
    """La barra del reproductor usa los mismos colores que la interfaz (antes eran copias a mano)."""
    import json
    import re
    from pathlib import Path

    from orbital import player_ui

    web = Path(player_ui.__file__).parent / "web" / "styles"
    palette = json.loads((web / "palette.json").read_text(encoding="utf-8"))
    css = dict(re.findall(r"--palette-([\w-]+):\s*(#[0-9a-fA-F]{6});", (web / "tokens.css").read_text(encoding="utf-8")))
    assert {k: v.lower() for k, v in css.items()} == {k: v for k, v in palette.items() if k != "_"}
    assert player_ui.ass_color("#5cbf6d") == "&H6DBF5C&"
    assert player_ui.GLYPH["A"] == player_ui.ass_color(palette["pad-green"])


def test_background_option_matches_the_installed_mpv(monkeypatch):
    """mpv 0.41 cambió --background (ahora none|color|tiles): con la forma vieja no abría nada."""
    from orbital import playback

    def fake(listing):
        return lambda *a, **k: type("R", (), {"stdout": listing})()

    playback.background_args.cache_clear()
    monkeypatch.setattr(playback.subprocess, "run", fake("--background  Choices: none color tiles\n--background-color  Color\n"))
    assert playback.background_args("mpv-nuevo.exe") == ("--background-color=#08080A",)
    monkeypatch.setattr(playback.subprocess, "run", fake("--background  Color\n"))
    assert playback.background_args("mpv-viejo.exe") == ("--background=#08080A",)
    playback.background_args.cache_clear()


class SlowMpv(FakeMpv):
    """mpv que confirma tarde: lo que se pide no se ve en get() hasta el siguiente vistazo."""

    def command(self, *args):
        self.sent.append(args)


def test_quick_presses_use_what_was_asked_not_the_stale_value():
    p, mpv = make_player()
    p.mpv = mpv = SlowMpv()
    p.press("a")
    p.press("a")
    assert [a for a in mpv.sent if a[:2] == ("set_property", "pause")] == [("set_property", "pause", True),
                                                                          ("set_property", "pause", False)]
    for _ in range(3):
        p.press("up")
    assert [a[2] for a in mpv.sent if a[:2] == ("set_property", "volume")] == [85, 90, 95]
    p.press("right")
    p.press("right")
    assert p._value("time-pos") == 620


def test_paused_video_gets_its_bar_back_after_the_quit_card_or_a_panel():
    p, mpv = make_player(pause=True)
    p.press("b")
    assert mpv.overlays.get(1) is None and mpv.overlays.get(4)
    p.press("a")  # Seguir viendo
    assert mpv.overlays.get(1) and "En pausa" in mpv.overlays[1]
    p.press("x")
    assert mpv.overlays.get(1) is None
    p.press("b")
    assert mpv.overlays.get(1) and "En pausa" in mpv.overlays[1]


def test_old_watcher_does_not_touch_the_new_video():
    p, mpv = make_player()
    failed = []
    p.on_failed = lambda *a: failed.append(a)
    old = p.current
    p.segment = player.Segment({"id": 1}, "Viejo", "u")
    new = player.Playback("Nuevo", None, 0, {"id": 2})
    p.current, p.segment = new, player.Segment({"id": 2}, "Nuevo", "u2")
    p.finish(old)  # el vigilante del viejo despierta tarde
    assert p.current is new and not p.segment.failed and failed == []


def test_background_task_returning_false_shows_the_failure():
    import time as _t
    p, mpv = make_player()
    p._in_background(lambda: False, failed="No pude cambiar de fuente")
    for _ in range(50):
        if mpv.overlays.get(3) and "No pude" in mpv.overlays[3]:
            break
        _t.sleep(.02)
    assert "No pude cambiar de fuente" in mpv.overlays[3]


def test_switching_source_then_quitting_before_it_loads_keeps_the_progress():
    p, mpv = make_player()
    saved = []
    p.on_finished = lambda meta, pos, dur, watched: saved.append((pos, dur, watched))
    p.current.process = type("Proc", (), {"poll": lambda self: None})()
    old = player.Segment({"video_id": "tt1"}, "Peli", "u1")
    old.playing, old.position, old.duration, old.watched, old.saved_watched = True, 3000.0, 6000.0, 400.0, 300.0
    p.segment = old
    assert p.load("u2", "Peli", {"video_id": "tt1"}, start=3000)
    p.finish(p.current)  # sale antes de que la fuente nueva dé imagen
    assert saved == [(3000.0, 6000.0, 100.0)]


def test_load_forgets_what_was_asked_of_the_previous_file():
    p, mpv = make_player()
    p.current.process = type("Proc", (), {"poll": lambda self: None})()
    p.segment = player.Segment({"video_id": "e1"}, "Serie", "u1")
    p.mpv = mpv = SlowMpv()
    p.press("a")  # pausa pedida
    p.load("u2", "Serie", {"video_id": "e2"})
    mpv.props["pause"] = False
    assert p._value("pause") is False


def test_volume_over_100_is_respected():
    p, mpv = make_player(volume=130, **{"volume-max": 130})
    p.press("up")
    p.press("down")
    assert [a[2] for a in mpv.sent if a[:2] == ("set_property", "volume")] == [130, 125]
