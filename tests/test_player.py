import pytest

from orbital import player, player_ui
from orbital.gamepad import A_BUTTON, DPAD_LEFT, GUIDE, X_BUTTON, Y_BUTTON
from orbital.library import addons, cinemeta, streams, stremio_api

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
    assert "--d3d11-flip=no" in cmd  # con «flip», cada ventana de mpv dejaba memoria de DWM que Windows nunca devolvía
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
        if args[:2] == ("set_property", "mute"):
            self.props["mute"] = args[2]
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
    assert remote.actions(DPAD_LEFT, 1) == ["x-up", "left"]  # X avisa al soltar (mantener X: probar subtítulos)
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
    assert "Interstellar" in hud and "En pausa" in hud and "Continuar" in hud and "Audio y subtítulos" in hud
    assert "Subtítulos en inglés" in hud and "10:00" in hud and "EN PAUSA" not in hud


def test_seek_and_volume():
    p, mpv = make_player()
    p.press("rb")
    p.press("left")
    p.press("up")
    assert ("seek", 60, "relative") in mpv.sent and ("seek", -10, "relative") in mpv.sent
    assert ("set_property", "volume", 85) in mpv.sent and "}85" in mpv.overlays[5]  # el volumen que se pidió (80 + 5), con su barra
    assert "−10 s" in mpv.overlays[1]  # adelantando: la burbuja dice cuánto


def test_audio_menu_lists_tracks_and_switches():
    p, mpv = make_player()
    p.press("x")
    assert p.menu.kind == "tracks" and p.menu.column.key == "audio" and [o["label"] for o in p.menu.options] == [
        "Inglés · 5.1 · E-AC3", "Español · Latino · Estéreo · AAC"]
    assert [c.key for c in p.menu.columns] == ["audio", "sub", "size", "sync"]
    assert p.menu.index == 0 and "Tamaño de los subtítulos" in mpv.overlays[2] and mpv.overlays.get(1) is None
    assert ("set_property", "sub-pos", 46) in mpv.sent  # con el panel abierto, los subtítulos suben y se ven encima
    p.press("down")
    p.press("a")
    # Elegir no cierra el panel: se prueba otra pista sin volver a abrirlo (B lo cierra).
    assert ("set_property", "aid", 2) in mpv.sent and p.menu is not None and mpv.overlays[2]
    assert [o["current"] for o in p.menu.options] == [False, True]
    assert "Audio: Español" in mpv.overlays[3]
    p.press("b")
    assert p.menu is None and mpv.overlays[2] is None and mpv.sent[-1] == ("set_property", "sub-pos", 100)


def test_subtitle_menu_has_off_and_addon_search():
    p, mpv = make_player()
    p._fallback_subs, p._subs_lang = (list), "es"
    p.press("x")
    p.press("right")  # columna Subtítulos
    labels = [o["label"] for o in p.menu.options]
    assert labels[:2] == ["Probar otros", "Sin subtítulos"] and "Español · Forzados" in labels and labels[-1].startswith("Buscar en español")
    assert p.menu.index == 2  # en la que está puesta («Probar otros» va primero)
    p.press("up")
    p.press("a")
    assert ("set_property", "sid", "no") in mpv.sent


def test_b_closes_the_menu_before_closing_the_video():
    p, mpv = make_player()
    p.press("x")
    p.press("b")
    assert p.menu is None and ("quit",) not in mpv.sent
    p.remote._repeats["b"] = 5  # la misma B, mantenida: no cuenta para salir (empezó cerrando el panel)
    p._quit_hold = None
    p.press("b")
    assert ("quit",) not in mpv.sent


def test_one_press_counts_once_with_empty_controller_ports():
    """El mando llega por cada puerto (los vacíos con 0): antes el vacío "soltaba" la cruceta en
    cada lectura y una pulsación contaba varias veces."""
    from orbital import gamepad, shell
    presses = []
    remote = player.PlayerRemote(presses.append)
    s = shell.ConsoleShell.__new__(shell.ConsoleShell)
    s._pads, s._fg_cache = {}, (1e9, shell.PLAYER_EXE)
    s.catalog = type("C", (), {"player": type("P", (), {"remote": remote})()})()
    for t in (0.0, .016, .032, .048):
        s.on_buttons(0, gamepad.DPAD_DOWN, t)
        s.on_buttons(1, 0, t)
    assert presses == ["down"]


def test_panel_list_scrolls_only_at_the_edge():
    """La cruceta mueve el foco; la lista solo se desplaza al llegar al borde (antes se recentraba y brincaba)."""
    from orbital import player_ui
    column = player_ui.Column("source", [{"label": str(i), "action": ("source", i)} for i in range(20)])
    panel = player_ui.Panel("more", [column])
    tops = []
    for _ in range(8):
        player_ui.panel_ass(panel)
        tops.append(column.top)
        column.index += 1
    assert tops == [0, 0, 0, 0, 0, 0, 1, 2]


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


def test_the_player_knows_the_next_episode_and_every_season(library):
    """«⏭ Siguiente · E3» en la misma temporada, «T2 E1» al cruzar; nada en el último. Y › Episodios: todas las
    temporadas (LB/RB), con el que ves y el que sigue marcados."""
    from orbital.watch import Watch

    meta = {"videos": [
        {"id": "s:1:1", "season": 1, "episode": 1, "name": "Pilot"}, {"id": "s:1:2", "season": 1, "episode": 2, "name": "Diversity Day"},
        {"id": "s:2:1", "season": 2, "episode": 1, "name": "The Dundies"}, {"id": "s:0:1", "season": 0, "episode": 1, "name": "Extra"},
    ]}
    assert Watch._next_label(meta, "s:1:1") == "E2"
    assert Watch._next_label(meta, "s:1:2") == "T2 E1"
    assert Watch._next_label(meta, "s:2:1") == ""
    library.watch.cinemeta = type("Cinemeta", (), {"meta": lambda self, kind, meta_id: meta})()
    episodes = library.watch._season_episodes({"meta_id": "s", "video_id": "s:1:2"})
    assert [(e["season"], e["label"], e["current"], e["next"]) for e in episodes] == [
        (1, "E1 · Pilot", False, False), (1, "E2 · Diversity Day", True, False), (2, "E1 · The Dundies", False, True),
        (0, "E1 · Extra", False, False)]
    column = player_ui.episodes_column(episodes)
    assert [p["label"] for p in column.pages] == ["T1", "T2", "Especiales"] and column.page == 0 and column.index == 1


def test_subtitles_from_subtitle_addons_in_your_language(monkeypatch):
    class Client:
        def request(self, method, params):
            return {"addons": [
                {"transportUrl": "https://torrentio/manifest.json", "manifest": {"name": "Torrentio", "resources": ["stream"]}},
                {"transportUrl": "https://opensubs/manifest.json", "manifest": {"name": "OpenSubtitles", "resources": ["subtitles"]}},
            ]}

    asked = []

    def fake_get(self, addon, path):
        asked.append((addon.name, path))
        return {"subtitles": [{"url": "https://subs/en.srt", "lang": "eng"}, {"url": "https://subs/es.srt", "lang": "spa"}]}

    monkeypatch.setattr(streams.StreamFinder, "_get_json", fake_get)
    finder = streams.StreamFinder(addons.AddonRegistry(Client(), auth=lambda: "key"))
    assert finder.subtitles("movie", "tt0816692", "en") == ["https://subs/en.srt"]
    assert asked == [("OpenSubtitles", "subtitles/movie/tt0816692.json")]
    # Un addon solo de subtítulos no se usa para buscar fuentes.
    monkeypatch.setattr(streams.StreamFinder, "_fetch", lambda self, addon, kind, vid: asked.append(addon.name) or [])
    finder.find("movie", "tt0816692", streams.Preferences())
    assert asked[-1] == "Torrentio"


def test_idle_rule():
    assert not player.idle_expired(0, 899, 900)
    assert player.idle_expired(0, 900, 900)
    assert not player.idle_expired(0, 10_000, 0)  # 0 = nunca


def test_touch_tap_tells_orbital_where_and_double_tap_does_not_leave_fullscreen():
    assert "MBTN_LEFT script-message orbital-tap ${mouse-pos/x} ${mouse-pos/y}" in player.TOUCH_BINDINGS
    assert "MBTN_LEFT_DBL ignore" in player.TOUCH_BINDINGS
    cmd = player.build_command("mpv.exe", "u", "t", bindings="C:/x/mpv-input.conf")
    assert "--input-conf=C:/x/mpv-input.conf" in cmd


def test_the_player_works_with_a_finger():
    """Con el dedo: tocar enseña botones (sin glifos del mando), cada uno hace lo suyo, la barra salta y el
    panel se elige tocando. Un botón del mando vuelve a los glifos."""
    from orbital import player_ui

    player_ui.set_touch(False)
    p, mpv = make_player()
    w, h = player_ui.W, player_ui.H
    p._on_mpv_message(["orbital-tap", "960", "300", "1920", "1080"])  # tocar el video: los botones
    hud = mpv.overlays[1]
    assert player_ui.TOUCH and "Pausa" in hud and "Salir" in hud and "Mantén" not in hud
    pause = next(t for t in player_ui.targets["hud"] if t[4] == "a")
    p.tap(pause[0] + 5, pause[1] + 5)
    assert mpv.props["pause"] is True
    rewind = next(t for t in player_ui.targets["hud"] if t[4] == "left")
    p.tap(rewind[0] + 5, rewind[1] + 5)
    assert any(c[0] == "seek" and c[2] == "relative" and c[1] < 0 for c in mpv.sent)
    bar = next(t for t in player_ui.targets["hud"] if isinstance(t[4], tuple) and t[4][0] == "seek")
    p.tap(bar[0] + bar[2] / 2, bar[1] + bar[3] / 2)  # a la mitad de la barra: a la mitad del video
    assert ("seek", 3000.0, "absolute") in mpv.sent
    tracks = next(t for t in player_ui.targets["hud"] if t[4] == "x")
    p.tap(tracks[0] + 5, tracks[1] + 5)
    assert p.menu is not None
    spanish = next(t for t in player_ui.targets["panel"] if t[4] == ("option", 0, 1))
    p.tap(spanish[0] + 5, spanish[1] + 5)  # Audio · Latino
    assert ("set_property", "aid", 2) in mpv.sent
    if p.menu is not None:
        p.tap(w / 2, 200)  # tocar el video, arriba del panel: se cierra
    assert p.menu is None
    p.press("a")  # el mando: otra vez los glifos
    assert not player_ui.TOUCH
    assert h == 1080


def test_a_finger_answers_still_watching():
    from orbital import player_ui

    p, mpv = make_player()
    player_ui.set_touch(True)
    p._card = {"kind": "still", "segment": player.Segment({"id": 1}, "Interstellar", "u")}
    p._draw_card()
    assert "Mantén" not in (mpv.overlays[4] or "")  # con el dedo: «Salir», no «Mantén: salir»
    answered = []
    p._card_accept, p._card_dismiss = (lambda: answered.append("seguir")), (lambda: answered.append("salir"))
    keep = next(t for t in player_ui.targets["card"] if t[4] == "a")
    leave = next(t for t in player_ui.targets["card"] if t[4] == "b")
    p.tap(keep[0] + 5, keep[1] + 5)
    p.tap(leave[0] + 5, leave[1] + 5)
    assert answered == ["seguir", "salir"]  # lo mismo que A y que B en el mando
    player_ui.set_touch(False)


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


def test_paused_video_gets_its_bar_back_after_a_panel():
    p, mpv = make_player()
    p.press("a")  # pausa
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
    p._in_background(lambda: False, failed="No pude cambiar de versión")
    for _ in range(50):
        if mpv.overlays.get(3) and "No pude" in mpv.overlays[3]:
            break
        _t.sleep(.02)
    assert "No pude cambiar de versión" in mpv.overlays[3]


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


def test_canvas_follows_the_screen_shape():
    try:
        assert player_ui.set_canvas(2560, 1600) and player_ui.W == 1728  # Legion Go (16:10): nada se estira
        assert not player_ui.set_canvas(0, 0) and player_ui.W == 1728
        p, mpv = make_player(**{"osd-width": 1920, "osd-height": 1080})
        p.press("a")
        assert player_ui.W == 1920
    finally:
        player_ui.set_canvas(1920, 1080)


def test_next_file_uses_its_own_subtitles():
    p, mpv = make_player()
    p.current.process = type("Proc", (), {"poll": lambda self: None})()
    p.segment = player.Segment({"video_id": "e1"}, "Serie", "u1")
    p._fallback_subs = lambda: ["http://subs/e1.srt"]
    p.load("u2", "Serie", {"video_id": "e2"}, fallback_subs=None, subtitles="")
    assert p._fallback_subs is None and p._subs_lang == ""


def test_y_never_blocks_the_controller_while_sources_load():
    import time as _t

    p, mpv = make_player()
    p.sources_provider = lambda meta: _t.sleep(1.5) or [{"id": 1, "label": "1080p", "current": True}]
    p.current.meta = {"source": 1}
    start = _t.monotonic()
    p.press("y")
    assert _t.monotonic() - start < 1  # antes: el mando esperaba a internet
    p.press("b")  # cambiaste de idea: el panel ya no aparece de golpe
    _t.sleep(1.8)
    assert p.menu is None


def test_from_the_phone_two_quick_episode_presses_go_two_episodes_ahead():
    import time as _t

    p, mpv = make_player()
    p.current.meta = {"kind": "series", "meta_id": "tt1", "video_id": "tt1:1:1"}
    asked = []
    p.on_episode = lambda meta, delta: asked.append(delta) or True
    p.EPISODE_WAIT = .1
    p.phone_button("pageright")  # en el teléfono no se mantiene: cada toque cuenta
    p.phone_button("pageright")
    assert "2 episodios adelante" in mpv.overlays[p.EPISODE_CARD]
    _t.sleep(.4)
    assert asked == [2]


def test_one_trigger_tap_changes_episode_with_a_notice_and_b_cancels():
    """RT con un toque: la tarjeta «Cambio de episodio · Siguiente · E2» con la cuenta atrás en su anillo y «B Cancelar»;
    si no lo cancelas, el siguiente (antes había que mantenerlo). Mantenido cuenta una vez: no salta dos episodios."""
    import time as _t

    p, mpv = make_player()
    p.current.meta = {"kind": "series", "meta_id": "tt1", "video_id": "tt1:1:1", "next": "E2"}
    asked = []
    p.on_episode = lambda meta, delta: asked.append(delta) or True
    p.EPISODE_WAIT = .5
    p.press("rt")
    card = mpv.overlays[p.EPISODE_CARD]
    assert "Cambio de episodio" in card and "Siguiente · E2" in card and "Cancelar" in card
    p.press("b")  # te arrepentiste
    _t.sleep(.6)
    assert asked == [] and "Sigues en este episodio" in mpv.overlays[3] and mpv.overlays[p.EPISODE_CARD] is None
    p.EPISODE_WAIT = .15
    p.press("lt")
    p.remote._repeats["lt"] = 5  # sigues manteniéndolo: las repeticiones no cuentan
    p.press("lt")
    p.press("lt-up")
    _t.sleep(.3)
    assert asked == [-1] and ("quit",) not in mpv.sent


def test_keyboard_brackets_change_episode_with_one_press():
    import time as _t

    p, mpv = make_player()
    p.current.meta = {"kind": "series", "meta_id": "tt1", "video_id": "tt1:1:1"}
    asked = []
    p.on_episode = lambda meta, delta: asked.append(delta) or True
    p.EPISODE_WAIT = .1
    try:
        p.key("rt")  # la tecla ]
        _t.sleep(.3)
        assert asked == [1]
    finally:
        player_ui.set_input("gamepad")


def test_paused_hints_say_rt_next_episode_only_when_there_is_one():
    hud = player_ui.Hud(title="Los Simpson", detail="T5 E2 · Cape Feare", position=500, duration=1300, paused=True,
                        series=True, next="E3")
    assert "Siguiente episodio" in player_ui.hud_ass(hud) and "Mantén: episodio" not in player_ui.hud_ass(hud)
    last = player_ui.Hud(title="Los Simpson", position=500, duration=1300, paused=True, series=True)
    assert "Siguiente episodio" not in player_ui.hud_ass(last)
    playing = player_ui.Hud(title="Los Simpson", position=500, duration=1300, series=True, next="T6 E1")
    assert "Siguiente episodio" in player_ui.hud_ass(playing)
    player_ui.set_input("keyboard")
    try:
        assert "]" in player_ui.hud_ass(hud)  # con teclado, la tecla
    finally:
        player_ui.set_input("gamepad")


def test_paused_next_pill_only_with_a_next_episode_and_a_tap_goes_there():
    import time as _t

    p, mpv = make_player(pause=True, duration=1300.0, **{"time-pos": 500.0})
    p.current.meta = {"kind": "series", "meta_id": "tt1", "video_id": "tt1:5:2", "next": "T6 E1"}
    asked = []
    p.on_episode = lambda meta, delta: asked.append(delta) or True
    p.EPISODE_WAIT = .1
    player_ui.set_touch(True)
    try:
        p.show_hud()
        assert "Siguiente · T6 E1" in mpv.overlays[1]
        labels = [label for label, _ in player_ui._touch_items(p._hud(p.current), paused=True)]
        assert labels.index("⏭ Siguiente · T6 E1") == labels.index("+10 s") + 1  # justo después de «+10 s»
        pill = next(t for t in player_ui.targets["hud"] if t[4] == "next")
        p.tap(pill[0] + 5, pill[1] + 5)
        assert "Cambio de episodio" in mpv.overlays[p.EPISODE_CARD]
        _t.sleep(.3)
        assert asked == [1]
        p.current.meta = {**p.current.meta, "next": ""}  # el último: sin píldora
        p.show_hud()
        assert not any(t[4] == "next" for t in player_ui.targets["hud"]) and "Siguiente ·" not in mpv.overlays[1]
    finally:
        player_ui.set_touch(False)


def test_next_file_resets_the_tracks_to_the_series_language():
    p, mpv = make_player()
    p.current.process = type("Proc", (), {"poll": lambda self: None})()
    p.segment = player.Segment({"video_id": "e1"}, "Serie", "u1")
    p.load("u2", "Serie", {"video_id": "e2"}, subtitles="", audio="es")
    sent = [a[1:] for a in mpv.sent if a[0] == "set_property"]
    assert ("aid", "auto") in sent and ("sid", "no") in sent and ("alang", "es,spa,Spanish,es-419") in sent


def test_sticks_wake_the_controls_and_move_in_panels():
    from orbital import gamepad
    assert gamepad.with_sticks(0, 0, 0, 0) == 0
    assert gamepad.with_sticks(5000, -3000, 0, 0) == 0  # deriva: no cuenta
    assert gamepad.with_sticks(0, 30000, 0, 0) == gamepad.STICK_UP
    assert gamepad.with_sticks(0, 0, -25000, 8000) == gamepad.STICK_LEFT  # la función sabe leer los dos (el ciclo solo usa el izquierdo)
    p, mpv = make_player()
    p.press("stick-right")  # sin panel: solo enciende los controles, no adelanta
    assert mpv.overlays.get(1) and not any(c[0] == "seek" for c in mpv.sent)
    p.press("x")
    p.press("stick-right")  # en un panel: mueve el foco como la cruceta
    assert p.menu.column.key == "sub"


def test_the_player_stick_has_hysteresis_like_the_interface():
    """Antes un solo umbral: el stick que rondaba el borde se soltaba y se volvía a apretar solo (el foco del panel
    brincaba). Ahora se activa al 55 % y se suelta por debajo del 35 %, y en diagonal no alterna."""
    from orbital import gamepad

    state = gamepad.stick_bits((19000, 0, 0, 0))
    assert state[0] == gamepad.STICK_RIGHT
    state = gamepad.stick_bits((15000, 0, 0, 0), state)  # bajó un poco: sigue empujado
    assert state[0] == gamepad.STICK_RIGHT
    state = gamepad.stick_bits((16000, 14000, 0, 0), state)  # casi diagonal: no cambia de eje
    assert state[0] == gamepad.STICK_RIGHT
    state = gamepad.stick_bits((2000, 26000, 0, 0), state)  # ahora sí, claramente arriba
    assert state[0] == gamepad.STICK_UP
    state = gamepad.stick_bits((0, 9000, 0, 0), state)  # soltado
    assert state[0] == 0
    assert gamepad.stick_bits((15000, 0, 0, 0), state)[0] == 0  # suelto, el 45 % no basta para volver a empujar


def test_sources_panel_explains_instant():
    panel = player_ui.more_panel(sources=[{"id": 1, "label": "Español · 1080p · Al instante", "current": True}])
    assert "Al instante: Real-Debrid" in player_ui.panel_ass(panel)
    assert player_ui.quit_hold_ass(.5) and player_ui.quit_hold_ass(float("nan"))


def test_the_player_with_a_keyboard_shows_keys_and_esc_asks_first():
    """Con teclado: las teclas hacen lo del mando, la barra dice «Espacio»/«Esc» y Esc pregunta antes de salir."""
    from orbital import player_ui
    from orbital.playback import KEY_BINDINGS

    assert "SPACE script-message orbital-key a" in KEY_BINDINGS
    assert "LEFT repeatable script-message orbital-key left" in KEY_BINDINGS
    assert "VOLUME_UP repeatable script-message orbital-key up" in KEY_BINDINGS
    assert "VOLUME_DOWN repeatable script-message orbital-key down" in KEY_BINDINGS
    p, mpv = make_player()
    p._on_mpv_message(["orbital-key", "a"])  # Espacio: pausa, como A
    assert mpv.props["pause"] is True and player_ui.KEYBOARD
    hud = mpv.overlays[1]
    assert "Espacio" in hud and "Esc" in hud and "Mantén" not in hud
    p._on_mpv_message(["orbital-key", "esc"])  # Esc: «¿Salir de …?», todavía no sale
    assert p._card and p._card["kind"] == "quit" and ("quit",) not in mpv.sent
    assert "Esc" in (mpv.overlays[4] or "")
    p._on_mpv_message(["orbital-key", "esc"])  # otro Esc: sale
    assert ("quit",) in mpv.sent
    p.press("a")  # el mando: otra vez sus glifos
    assert not player_ui.KEYBOARD


def test_keyboard_glyphs_never_overlap_their_label():
    """«Espacio» es más ancho que el círculo del mando: el botón crece y el texto empieza después del glifo."""
    import re as _re

    from orbital import player_ui

    player_ui.set_input("keyboard")
    try:
        key_w = player_ui.glyph(0, 0, "A", 30)[1]
        for ass, label in ((player_ui.buttons([("A", "Continuar")], 96, 800), "Continuar"), (player_ui.skip_ass("Saltar intro"), "Saltar intro")):
            def x_of(word, ass=ass):
                line = next(ln for ln in ass.splitlines() if ln.endswith(word))
                return float(_re.search(r"pos\(([\d.]+),", line).group(1))
            # «Espacio» va centrado en su tecla; el texto empieza después del borde derecho de la tecla.
            assert x_of(label) >= x_of("Espacio") + key_w / 2
    finally:
        player_ui.set_input("gamepad")


def test_the_memory_watchdog_reopens_a_channel_and_only_warns_in_a_video():
    """Con una versión de desarrollo de mpv, la tele llegó a 8 GB: un canal se vuelve a abrir en un mpv nuevo (una vez);
    un video solo avisa, no se corta."""
    import types

    p, mpv = make_player()
    p.memory_of = lambda pid: 3500
    reopened = []
    p.on_memory_full = reopened.append
    p.current = player.Playback("ADN 40", types.SimpleNamespace(pid=42), 0, {})
    live = player.Segment({"channel_id": "adn40", "title": "ADN 40", "list": "todos"}, "ADN 40", "u", live=True)
    live.playing = True
    p._check_memory(p.current, live)
    p._check_memory(p.current, live)  # una sola vez por mpv
    import time as _t
    for _ in range(50):
        if reopened:
            break
        _t.sleep(.02)
    assert reopened == [{"channel_id": "adn40", "title": "ADN 40", "list": "todos"}]
    p.current = player.Playback("Interstellar", types.SimpleNamespace(pid=43), 0, {})
    movie = player.Segment({"kind": "movie"}, "Interstellar", "u")
    movie.playing = True
    p._check_memory(p.current, movie)
    assert len(reopened) == 1 and "mucha memoria" in (mpv.overlays.get(3) or "") + "".join(str(v) for v in mpv.overlays.values())
    p.memory_of = lambda pid: 900  # por debajo del tope: nada
    p.current = player.Playback("Otro", types.SimpleNamespace(pid=44), 0, {})
    p._check_memory(p.current, live)
    assert len(reopened) == 1


def test_the_video_buffer_has_a_cap_both_ways():
    cmd = player.build_command("mpv.exe", "u", "t")
    assert "--demuxer-max-bytes=200MiB" in cmd and "--demuxer-max-back-bytes=25MiB" in cmd


def test_mpv_does_not_show_its_own_osd_bar():
    """Orbital dibuja su barra y su volumen: la OSD nativa de mpv (avance abajo, volumen arriba)
    no se enseña, ni con teclas multimedia ni con seek por IPC."""
    cmd = player.build_command("mpv.exe", "u", "t")
    assert "--osd-bar=no" in cmd and "--osd-on-seek=no" in cmd and "--osd-level=0" in cmd
    assert "--osc=no" in cmd and "--input-default-bindings=no" in cmd
    assert "--osd-bar-align-y=0.88" not in cmd


def test_paused_with_the_finger_has_one_play_button_and_the_bar_does_not_cover_the_info():
    """En pausa con el dedo: «Continuar» es el único botón de reproducir (antes también «Seguir» abajo) y la fila de abajo va
    a la derecha, sin tapar «Inglés · Subtítulos en … · 2160p» (antes iba al centro, encima)."""
    player_ui.set_touch(True)
    try:
        hud = player_ui.Hud(title="Futurama", detail="T1 E1", position=60, duration=1200, paused=True, series=True,
                            audio="Inglés 5.1", subtitles="Español (Latinoamérica)", source="2160p · HDR · Torrentio · 18.4 GB")
        ass = player_ui.hud_ass(hud)
        plays = [t for t in player_ui.targets["hud"] if t[4] == "a"]
        assert len(plays) == 1 and "Seguir" not in ass
        bottom = [t for t in player_ui.targets["hud"] if t[1] >= 990]
        assert bottom and max(t[0] + t[2] for t in bottom) == pytest.approx(player_ui.W - player_ui.MARGIN)
        info = player_ui.info_line(hud)
        assert player_ui.MARGIN + player_ui.text_width(info, 22, "semi") < min(t[0] for t in bottom)
    finally:
        player_ui.set_touch(False)


def test_overlays_that_can_be_together_do_not_overlap():
    """El volumen (barra vertical a la derecha) ya no cae sobre los avisos ni sobre «Cargando…»; con la guía abierta y la
    tele en silencio, el panel lo dice en su etiqueta (la píldora «Sin sonido» se encimaba)."""
    import re
    ass = player_ui.volume_ass(50)
    # Lo dibujado va en coordenadas de la figura («m x y l x y…»); el texto, en \pos(x,y).
    ys = [float(y) for y in re.findall(r"(?:^|[ }])[ml] [\d.]+ ([\d.]+)", ass)]
    ys += [float(y) for x, y in re.findall(r"\\pos\(([\d.]+),([\d.]+)\)", ass) if float(x) or float(y)]
    assert min(ys) > player_ui.BUFFER_Y + 54  # debajo del aviso (NOTICE_Y) y de «Cargando…» (BUFFER_Y)
    panel = player_ui.channels_panel([{"id": "todos", "label": "Todos"}], [{"id": "a", "name": "ADN 40", "number": 1}])
    assert "Sigue reproduciendo · sin sonido" in player_ui.panel_ass(panel, muted=True)
    assert "sin sonido" not in player_ui.panel_ass(panel)


def test_info_line_keeps_the_region_capitalized():
    hud = player_ui.Hud(title="X", audio="Inglés", subtitles="Español (Latinoamérica)")
    assert "Subtítulos en español (Latinoamérica)" in player_ui.info_line(hud)


def test_source_counter_sits_in_the_header_not_on_the_note():
    """«7 de 12» va en el encabezado de la columna: abajo se encimaba con «Al instante: Real-Debrid…»."""
    import re

    sources = [{"label": f"{i}p", "hint": "Torrentio", "id": f"s{i}", "current": i == 0} for i in range(12)]
    panel = player_ui.more_panel(sources=sources)
    panel.col = next(i for i, c in enumerate(panel.columns) if c.key == "source")
    panel.columns[panel.col].index = 6
    ass = player_ui.panel_ass(panel)
    assert re.search(r"\\an9\\pos\(\d+,562\)[^}]*}7 de 12", ass)
    assert "Al instante: Real-Debrid" in ass


def test_one_volume_the_players_buttons_move_the_computers():
    """Con el volumen de Windows conectado (de mentiras aquí), ▲ ▼ lo mueven y «Sin sonido» es el suyo: mpv no se toca."""
    system = {"level": 30, "muted": True}

    def write(level=None, muted=None):
        if level is not None:
            system["level"] = level
        if muted is not None:
            system["muted"] = muted
        return dict(system)

    p, mpv = make_player()
    p.system_volume = (lambda: dict(system), write)
    p.press("up")
    assert system == {"level": 35, "muted": False}  # subir también quita el silencio
    p.press("down")
    assert system["level"] == 30
    assert not any(c[:2] == ("set_property", "volume") or c[:2] == ("add", "volume") for c in mpv.sent)
    assert p.toggle_mute() is True and system["muted"] is True
    assert "--volume=100" in player.build_command("mpv.exe", "u", "t")


def test_volume_shows_its_level_with_waves_and_a_cross_when_muted():
    from orbital import player_ui

    def waves(ass):  # cada onda es un tramo de anillo: una figura más después del cuerpo de la bocina
        return ass.count("\p1}") - 4  # cápsula, riel, relleno y cuerpo de la bocina
    assert waves(player_ui.volume_ass(15)) == 1 and waves(player_ui.volume_ass(50)) == 2 and waves(player_ui.volume_ass(90)) == 3
    muted = player_ui.volume_ass(50, muted=True)
    assert "—" in muted and muted.count("\p1}") == 4  # cápsula, riel (sin relleno), cuerpo y la ✕
    assert player_ui.volume_ass(float("nan")) and player_ui.volume_ass("x")  # nunca truena


def test_the_video_fades_in_from_black_without_a_transparent_window(monkeypatch):
    """El video arranca tapado de negro (capa del reproductor) y se destapa ya con imagen: el fundido de entrada sin
    volver transparente la ventana de Orbital. Otro episodio en la misma ventana también entra fundiéndose."""
    import time as _t

    monkeypatch.setattr(player, "CURTAIN_STEP", 0)
    p, mpv = make_player()
    segment = player.Segment({"kind": "series"}, "Serie", "u")
    p.segment = segment
    p._reveal_wait = 0
    p._curtain(1)
    assert mpv.overlays[player.CURTAIN_ID].startswith(r"{\an7")
    p._started(segment)
    for _ in range(100):
        if mpv.overlays.get(player.CURTAIN_ID) is None:
            break
        _t.sleep(.01)
    assert mpv.overlays.get(player.CURTAIN_ID) is None  # destapado
    live = player.Segment({"kind": "tv"}, "Canal", "u", live=True)
    p.segment = live
    p._curtain(0)
    p._started(live)
    assert mpv.overlays.get(player.CURTAIN_ID) is None  # la TV en vivo no lleva fundido


def test_the_small_video_glides_to_the_corner_and_back_with_only_three_buttons(monkeypatch):
    """Home durante un video: la ventana sale de pantalla completa YA con el tamaño de la pantalla (antes saltaba al centro)
    y se desliza, frenando, a la esquina de abajo a la derecha; en chiquito solo tres botones, como el PiP del iPhone."""
    p, mpv = make_player()
    p.current.process = type("Proc", (), {"poll": lambda self: None, "pid": 1})()
    placed = []

    class Win:
        screen_size = staticmethod(lambda: (1920, 1080))
        place_window = staticmethod(lambda hwnd, x, y, w, h, topmost=True: placed.append((x, y, w, h)))
        glide_window = staticmethod(lambda hwnd, x, y, w, h: placed.append((x, y, w, h)))
        window_rect = staticmethod(lambda hwnd: (placed[-1][0], placed[-1][1], placed[-1][0] + placed[-1][2], placed[-1][1] + placed[-1][3]))
        focus = staticmethod(lambda hwnd: True)

    monkeypatch.setattr(p, "_window", lambda current: (Win, 7))
    monkeypatch.setattr(player.time, "sleep", lambda s: None)
    class Timer:  # los botones se irían solos a los 3 s: aquí no corre el reloj
        def __init__(self, *a, **kw):
            self.daemon = True

        def start(self):
            pass

        def cancel(self):
            pass

    monkeypatch.setattr(player.threading, "Timer", Timer)
    monkeypatch.setattr(player.threading, "Thread", lambda target, args=(), **kw: type("T", (), {"start": lambda self: target(*args)})())
    assert p.enter_pip() and p.pip
    geometry = mpv.sent.index(("set_property", "geometry", "1920x1080+0+0"))
    assert geometry < mpv.sent.index(("set_property", "fullscreen", False))  # primero el tamaño, luego salir
    assert ("set_property", "ontop", True) in mpv.sent
    assert mpv.props["pause"] is False  # se detuvo mientras se movía y siguió al llegar
    assert placed[0] == (0, 0, 1920, 1080) and placed[-1] == (1287, 699, 576, 324)  # de toda la pantalla a la esquina
    widths = [w for _, _, w, _ in placed]
    assert widths == sorted(widths, reverse=True) and len(placed) > 10  # se encoge poco a poco, nunca de golpe
    # En chiquito: los tres botones (y no la barra completa del reproductor, ni aunque se pida).
    p.show_hud()
    assert [t[4] for t in player.player_ui.targets["hud"]] == ["pip:expand", "pip:close", "pip:play"]
    p._pip_tap(960, 540)  # pausa
    assert mpv.props["pause"] is True
    placed.clear()
    placed.append((1287, 699, 576, 324))
    p._pip_tap(156, 156)  # volver a pantalla completa
    assert not p.pip and placed[-1] == (0, 0, 1920, 1080) and ("set_property", "fullscreen", True) in mpv.sent[-3:]


def test_a_new_file_is_not_mistaken_for_the_end_of_the_previous_one():
    """Recién cargado otro episodio en la misma ventana, mpv tarda un instante en soltar lo del anterior (posición al
    final y «llegó al final»): el nuevo no se da por terminado (antes se cargaba otro encima)."""
    import time as _t

    p, mpv = make_player(**{"time-pos": 1335.0, "duration": 1340.0, "eof-reached": True})
    ended = []
    p.on_synthetic_end = lambda meta: ended.append(meta) or True
    segment = player.Segment({"synthetic": True, "kind": "channel"}, "Serie 24/7", "u2", grace_until=_t.monotonic() + 1.5)
    p.segment = segment
    p.tick(segment, _t.monotonic(), False)  # recién cargado: no se lee nada todavía
    assert not segment.playing and ended == []


def test_each_mpv_command_takes_only_its_own_answer():
    """Una respuesta que llegó tarde (de otro comando) se salta: antes la siguiente pregunta la tomaba como suya y el
    vigilante recibió un número en vez de la lista de pistas."""
    import io
    import json

    from orbital.mpv import Mpv

    class Pipe(io.BytesIO):
        def __init__(self, lines):
            super().__init__(b"".join((json.dumps(line) + "\n").encode() for line in lines))
            self.sent = []

        def write(self, data):
            self.sent.append(data)
            return len(data)

    m = Mpv(pipe="no-existe")
    m._fh = Pipe([{"data": 1080, "error": "success", "request_id": 6},  # la de un comando anterior, atrasada
                  {"event": "property-change"},
                  {"data": [{"id": 1, "type": "audio"}], "error": "success", "request_id": 7}])
    reply = m._exchange(b'{"command": ["get_property", "track-list"], "request_id": 7}\n', "track-list", 7)
    assert reply["data"] == [{"id": 1, "type": "audio"}]


def test_the_same_video_still_loading_is_not_started_again():
    """Un stream lento (20–40 s sin imagen): otro A, o un «pon…» del iPhone, no cierra mpv para empezar de cero."""
    class Alive:
        def poll(self):
            return None

    p, _ = make_player()
    p.current = player.Playback("Calle Oak", Alive(), 0, {})
    p.segment = player.Segment({"video_id": "tt27165187", "source_key": "a"}, "Calle Oak", "http://x")
    assert p.starting("tt27165187")
    assert p.starting("tt27165187", "a")
    assert not p.starting("tt27165187", "b")  # otra fuente elegida a propósito sí se abre
    assert not p.starting("tt0076162")  # otro video, también
    p.segment.loaded -= player.STARTUP_TIMEOUT + 1
    assert not p.starting("tt27165187")  # ya pasó el tiempo de arranque: esa fuente no sirve, se puede volver a pedir
    p.segment.loaded += player.STARTUP_TIMEOUT + 1
    p.segment.playing = True
    assert not p.starting("tt27165187")  # ya se ve: lo de siempre (reanudar, etc.)


def test_subtitles_from_the_internet_are_downloaded_apart_and_mpv_gets_the_file():
    """Con la URL mpv bajaba el subtítulo él mismo y mientras tanto no contestaba (pausa, volumen, la interfaz)."""
    p, mpv = make_player()
    p.fetch_subtitle = lambda url: "C:/cache/subs/abc.srt"
    p.add_subtitles("https://subs5.strem.io/en/download/file/1962602374", "es")
    assert mpv.sent[-1] == ("sub-add", "C:/cache/subs/abc.srt", "select", "Subtítulos", "es")
    # «Continuar» recuerda de dónde vino, no el archivo del caché.
    mpv.props["track-list"] = [{"type": "sub", "id": 3, "lang": "es", "title": "Subtítulos", "selected": True,
                                "external": True, "external-filename": "C:/cache/subs/abc.srt"}]
    assert p.current_subtitle()["url"] == "https://subs5.strem.io/en/download/file/1962602374"

    def fails(url):
        raise OSError("timed out")

    p.fetch_subtitle = fails
    sent = len(mpv.sent)
    p.add_subtitles("https://subs/otro.srt", "es")
    assert len(mpv.sent) == sent  # no se bajó: mpv ni se entera (antes se quedaba esperando)

    pending = []
    p.fetch_subtitle = lambda url: "C:/cache/subs/tarde.srt"
    p.background = pending.append
    p.add_subtitles("https://subs/tarde.srt", "es")
    p.current = player.Playback("Otro video", None, 0, {})
    pending[0]()
    assert len(mpv.sent) == sent  # llegó cuando ya era otro video: no se le pone


def test_dragging_the_knob_with_the_mouse_moves_through_the_video():
    """Click en la barra y, sin soltar, arrastrar: el video busca mientras arrastras (a cuadros clave) y exacto al soltar."""
    from orbital import player_ui

    player_ui.set_touch(False)
    p, mpv = make_player()
    p.SCRUB_EVERY = 0
    p._on_mpv_message(["orbital-tap", "960", "300", "1920", "1080"])  # los botones (y la barra que se toca)
    bar = next(t for t in player_ui.targets["hud"] if isinstance(t[4], tuple) and t[4][0] == "seek")
    _, x0, width = bar[4]
    y = bar[1] + bar[3] / 2
    sx = lambda frac: str((x0 + width * frac) / player_ui.W * 1920)  # noqa: E731
    sy = str(y / player_ui.H * 1080)
    p._on_mpv_message(["orbital-tap", sx(.5), sy, "1920", "1080"])
    p._on_mpv_message(["orbital-drag", sx(.25), sy, "1920", "1080"])
    assert any(c[0] == "seek" and c[2] == "absolute+keyframes" and abs(c[1] - 1500) < 2 for c in mpv.sent)
    p._on_mpv_message(["orbital-drop", sx(.75), sy, "1920", "1080"])
    assert mpv.sent[-1][0] == "seek" and mpv.sent[-1][2] == "absolute" and abs(mpv.sent[-1][1] - 4500) < 2
    sent = len(mpv.sent)
    p._on_mpv_message(["orbital-drag", sx(.1), sy, "1920", "1080"])  # ya soltaste: moverlo no busca
    assert not any(c[0] == "seek" for c in mpv.sent[sent:])


def test_mpv_loads_the_mouse_script_next_to_the_bindings(tmp_path):
    conf = tmp_path / "mpv-input.conf"
    conf.write_text("", encoding="utf-8")
    (tmp_path / player.MOUSE_SCRIPT_NAME).write_text(player.MOUSE_SCRIPT, encoding="utf-8")
    cmd = player.build_command("mpv.exe", "http://a", "T", bindings=str(conf))
    assert f"--script={tmp_path / player.MOUSE_SCRIPT_NAME}" in cmd
    assert 'mp.add_forced_key_binding("MBTN_LEFT"' in player.MOUSE_SCRIPT and "orbital-drop" in player.MOUSE_SCRIPT


def test_watching_the_same_video_again_does_not_reload_it():
    """La ficha de atrás recibía «Ver» de la misma película (la A de pausar): se recargaba desde lo último guardado."""
    p, _ = make_player()
    alive = type("Proc", (), {"poll": lambda self: None})()
    p.current = player.Playback("Qué pasó ayer", alive, 0, {})
    p.segment = player.Segment({"video_id": "tt1119646", "source_key": "rd:1"}, "Qué pasó ayer", "u")
    assert not p.showing("tt1119646")  # todavía sin imagen: eso es starting()
    p.segment.playing = True
    assert p.showing("tt1119646") and p.showing("tt1119646", "rd:1")
    assert not p.showing("tt1119646", "rd:2")  # otra versión elegida a propósito sí se abre
    assert not p.showing("tt0000001")


def test_paused_shows_the_title_logo_instead_of_plain_text():
    """En pausa, el título estilizado (su logo, como en la ficha) en vez de su nombre en texto: mpv lo pone encima con
    overlay-add donde el bloque le dejó lugar, y se quita al seguir viendo. Sin logo, el nombre como siempre."""
    import io
    import time

    from PIL import Image

    png = io.BytesIO()
    Image.new("RGBA", (400, 100), (255, 255, 255, 255)).save(png, "PNG")
    p, mpv = make_player(**{"osd-height": 2160, "osd-width": 3840})
    p.current.meta = {"meta_id": "tt0816692", "kind": "movie"}
    p.logo_provider = lambda meta: png.getvalue()
    p.press("a")  # pausa: el logo se prepara por detrás y la pausa se vuelve a dibujar con él
    deadline = time.monotonic() + 3
    while not any(c[0] == "overlay-add" for c in mpv.sent) and time.monotonic() < deadline:
        time.sleep(.02)
    add = next(c for c in mpv.sent if c[0] == "overlay-add")
    _, oid, x, y, path, offset, fmt, w, h, stride = add
    # Cabe en 860 × 190 del lienzo (1080 de alto): en una pantalla 4K, al doble en píxeles.
    assert (fmt, w, h, stride, x) == ("bgra", 1520, 380, 1520 * 4, player_ui.MARGIN * 2)
    assert len(open(path, "rb").read()) == w * h * 4
    assert "Interstellar" not in mpv.overlays[1].split("En pausa", 1)[1].split("Continuar", 1)[0]  # sin el nombre en texto
    p.press("a")  # sigue: el logo se va con la barra de pausa
    assert ("overlay-remove", 0) in mpv.sent
    q, mpv2 = make_player()
    q.press("a")
    assert "Interstellar" in mpv2.overlays[1] and not any(c[0] == "overlay-add" for c in mpv2.sent)  # sin logo: el nombre


def test_the_next_file_starts_playing_even_if_the_last_one_ended_paused():
    """Al terminar, keep-open deja el archivo en pausa en su último cuadro y mpv lo vuelve a pausar mientras siga ahí: la
    pausa se quita también DESPUÉS de cargar el siguiente (antes el siguiente episodio de un canal 24/7 arrancaba en pausa
    en el segundo 0, y parecía que «no ponía el siguiente»; probado con mpv de verdad en la Lenovo)."""
    alive = type("Proc", (), {"poll": lambda self: None})()
    p, mpv = make_player(pause=True)
    p.current = player.Playback("Los Simpson 24/7", alive, 0, {})
    assert p.load("http://ep2", "Los Simpson 24/7", {"synthetic": True, "video_id": "tt0096697:5:8"})
    at = next(i for i, c in enumerate(mpv.sent) if c[0] == "loadfile")
    assert ("set_property", "pause", False) in mpv.sent[at + 1:]


def _shaded_screens(ass: str) -> float:
    """Cuántas pantallas cubren, sumadas, las figuras de una capa (lo que pesa en libass)."""
    import re

    total = 0.0
    for line in ass.split("\n"):
        m = re.search(r"\\p1\}(.*?)\{\\p0\}", line)
        if m:
            nums = [float(x) for x in re.findall(r"-?\d+(?:\.\d+)?", m.group(1))]
            total += (max(nums[0::2]) - min(nums[0::2])) * (max(nums[1::2]) - min(nums[1::2]))
    return total / (player_ui.W * player_ui.H)


def test_every_layer_fits_what_mpv_can_paint_at_4k():
    """A 4K, libass deja de pintar una capa cuyas figuras suman más de ~12 pantallas: la pausa (con su sombra de 28 pasos)
    sumaba 21 y en la TV no salía nada de ella, solo la imagen del logo. Medido en la Lenovo con mpv de verdad."""
    hud = player_ui.Hud(title="Los Expedientes Secretos X", detail="T1 E1", position=3, duration=2894, paused=True, audio="",
                        subtitles="", source="", series=True, now="9:50", chapters=[], chapter_titles=[], facts="1993",
                        description="Fox Mulder y Dana Scully investigan casos sin explicación.", seeking="", pip=False)
    layers = {"pausa": player_ui.hud_ass(hud)}
    hud.paused = False
    layers["barra"] = player_ui.hud_ass(hud)
    tracks = [{"type": "audio", "id": 1, "lang": "spa", "selected": True}, {"type": "sub", "id": 2, "lang": "eng"}]
    layers["panel"] = player_ui.panel_ass(player_ui.tracks_panel(tracks, 1.0))
    layers["canal"] = player_ui.live_hud_ass(player_ui.LiveHud(name="Canal 5", number=5))
    for name, ass in layers.items():
        assert _shaded_screens(ass) <= player_ui.SHADE_BUDGET, f"{name}: {_shaded_screens(ass):.1f} pantallas"


def test_each_buffer_wait_goes_to_the_log(caplog):
    """Un «Cargando…» a media película queda en el registro (cuánto duró, cuánto había por delante y la velocidad), y al
    cerrar el video, cuántas esperas hubo: antes solo se veía en pantalla y una traba no se podía investigar (#12)."""
    import logging

    p, mpv = make_player(**{"paused-for-cache": True, "cache-buffering-state": 40, "demuxer-cache-duration": 0.4,
                            "cache-speed": 500_000, "frame-drop-count": 3})
    segment = player.Segment({"kind": "movie"}, "¿Qué Pasó Ayer?", "u")
    segment.playing, segment.position, segment.watched = True, 1800.0, 1800.0
    p.segment = segment
    with caplog.at_level(logging.INFO, logger="orbital.player"):
        p._buffering_state(False)
        mpv.props["paused-for-cache"] = False
        p._buffering_state(False)
        p._close_segment(segment)
    text = caplog.text
    assert "Esperó al búfer" in text and "(min 30)" in text and "por delante 0.4 s" in text and "bajando a 4.0 Mbps" in text
    assert "1 esperas de búfer" in text and "3 cuadros perdidos" in text


def test_playing_bar_has_no_title_and_the_info_goes_to_the_bottom():
    """Reproduciendo, el título y «Película» sobran (son de la pausa): solo la barra, y abajo a la izquierda el idioma, los
    subtítulos y la versión, en el mismo renglón que en pausa (antes subían encima de la barra)."""
    hud = player_ui.Hud(title="Interstellar", detail="Película", position=600, duration=6000, audio="Inglés 5.1",
                        subtitles="Español", source="2160p · Al instante")
    ass = player_ui.hud_ass(hud)
    assert "Interstellar" not in ass and "Película" not in ass
    info = player_ui.esc(player_ui.fit(player_ui.info_line(hud), 22, 1200, "semi"))
    line = next(row for row in ass.splitlines() if info in row)
    assert r"\pos(96,1022)" in line
    player_ui.set_touch(True)
    try:
        assert "Interstellar" not in player_ui.hud_ass(hud)
        bottom = [t for t in player_ui.targets["hud"] if t[1] >= 990]
        assert max(t[0] + t[2] for t in bottom) == pytest.approx(player_ui.W - player_ui.MARGIN)  # a la derecha
    finally:
        player_ui.set_touch(False)


def test_a_clip_opens_paused_and_starts_when_released_without_the_pause_bar():
    """Un tráiler abre en pausa con su primer cuadro listo y empieza cuando se va la pantalla de carga; esa pausa no
    es tuya: ni barra «En pausa» ni barra al seguir."""
    from orbital.playback import build_command

    assert "--pause=yes" in build_command("mpv.exe", "u", "Tráiler", paused=True)
    assert "--pause=yes" not in build_command("mpv.exe", "u", "Película")
    p, mpv = make_player(pause=True)
    p._held = True
    p.release_start()
    assert ("set_property", "pause", False) in mpv.sent and not p._held
    sent = len(mpv.sent)
    p.release_start()  # una sola vez
    assert len(mpv.sent) == sent


def test_video_memory_is_checked_before_opening_mpv():
    """Antes de abrir mpv (con la pantalla de carga a la vista) se libera la memoria de video si hace falta: con DWM
    lleno, el video se trababa cada pocos minutos."""
    p, mpv = make_player()
    p.current = None  # nada abierto todavía
    order = []
    p.before_open = lambda: order.append("liberar")
    p.play(lambda argv: order.append("mpv") or type("P", (), {"poll": lambda self: None, "pid": 1})(), "mpv.exe", "u",
           "Sleepy Hollow", {"kind": "movie"})
    assert order[:2] == ["liberar", "mpv"]


def test_each_stutter_goes_to_the_log_with_its_minute(caplog):
    """El video se congela, el audio sigue y el video corre para alcanzarlo: cada tirón (varios cuadros perdidos de golpe)
    queda en el registro con su minuto y si fue al mostrar o al decodificar; uno suelto no. Al cerrar, el total
    (antes «? cuadros perdidos»: se leía cuando mpv ya no contestaba)."""
    import logging

    p, mpv = make_player(**{"frame-drop-count": 0, "decoder-frame-drop-count": 0, "hwdec-current": "d3d11va",
                            "video-codec": "HEVC", "demuxer-cache-duration": 600.0})
    segment = player.Segment({"kind": "movie"}, "Sleepy Hollow", "u")
    segment.playing, segment.position = True, 1265.0
    with caplog.at_level(logging.INFO, logger="orbital.player"):
        p._drops_tick(segment, False)
        mpv.props["frame-drop-count"] = 1  # uno suelto: no se nota
        p._drops_tick(segment, False)
        mpv.props["frame-drop-count"] = 25  # un tirón
        p._drops_tick(segment, False)
        mpv.props["frame-drop-count"] = 40  # en pausa (adelantando) no cuenta
        p._drops_tick(segment, True)
        mpv.props.pop("frame-drop-count")  # al cerrar mpv ya no contesta: se queda lo último que se vio
        p._close_segment(segment)
    tirones = [r.getMessage() for r in caplog.records if r.getMessage().startswith("Tirón")]
    assert len(tirones) == 1 and "minuto 21:05" in tirones[0] and "24 cuadros perdidos al mostrar" in tirones[0]
    assert "d3d11va" in tirones[0] and "búfer 600 s" in tirones[0]
    assert "40 cuadros perdidos (0 al decodificar), 1 tirones" in caplog.text


def test_watch_now_in_the_credits_saves_the_episode_as_seen():
    p, mpv = make_player()
    saved = []
    p.on_finished = lambda meta, pos, dur, watched: saved.append((pos, dur))
    p.current.process = type("Proc", (), {"poll": lambda self: None})()
    ep = player.Segment({"kind": "series", "video_id": "tt1:1:1"}, "Serie", "u1")
    ep.playing, ep.position, ep.duration, ep.watched = True, 2400.0, 2640.0, 2300.0  # créditos largos: faltan 4 min
    ep.upnext = {"label": "T1 E2", "title": "", "play": lambda: True}
    p.segment = ep
    p._play_next(ep, auto=False)  # «Ver ahora»
    p._close_segment(ep)
    assert saved == [(2640.0, 2640.0)]  # visto: se guarda al final, no a 4 min
