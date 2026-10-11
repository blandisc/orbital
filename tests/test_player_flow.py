"""El reproductor como servicio de streaming: B, adelantar, fuentes que fallan, siguiente episodio, intro."""

from test_player import make_player

from orbital import player
from orbital.library import cinemeta, streams
from orbital.server import humane_error


def series_player(**props):
    p, mpv = make_player(**props)
    meta = {"kind": "series", "meta_id": "s", "video_id": "s:1:1", "title": "The Office · T1 E1"}
    p.current.meta = meta
    p.segment = player.Segment(meta, "The Office · T1 E1", "http://a")
    p.current.process = type("Proc", (), {"poll": lambda self: None})()
    return p, mpv


def test_b_hides_the_bar_first_and_then_leaves():
    p, mpv = make_player()
    p.press("a")  # pausa: la barra se queda
    assert mpv.overlays[1]
    p.press("b")
    assert mpv.overlays[1] is None and ("quit",) not in mpv.sent
    p.press("b")
    assert ("quit",) in mpv.sent


def test_holding_right_seeks_faster_and_faster():
    assert [player.seek_step(n) for n in (0, 3, 4, 9, 10, 40)] == [10, 10, 30, 30, 60, 60]
    p, mpv = make_player()
    remote = p.remote
    remote.update(player.DPAD_RIGHT, 0)
    t = .35
    for _ in range(12):
        remote.update(player.DPAD_RIGHT, t)
        t += .16
    seeks = [c[1] for c in mpv.sent if c[0] == "seek"]
    assert seeks[0] == 10 and 30 in seeks and seeks[-1] == 60


def test_lb_rb_jump_chapters_when_the_file_has_them():
    p, mpv = make_player()
    p.press("rb")
    assert ("seek", 60, "relative") in mpv.sent  # sin capítulos: 1 min
    p.segment = player.Segment({}, "x", "u", chapters=[{"time": 0, "title": "a"}, {"time": 300, "title": "b"}])
    p.press("rb")
    assert ("add", "chapter", 1) in mpv.sent


def test_a_source_that_never_starts_tries_the_next_one():
    p, mpv = series_player(**{"time-pos": None, "duration": None, "idle-active": True})
    tried = []
    p.on_failed = lambda meta, pos, alive: tried.append((meta["video_id"], pos, alive)) or True
    segment = p.segment
    p.tick(segment, segment.loaded + 1, False)
    assert not tried  # recién cargado: se le da un momento
    p.tick(segment, segment.loaded + 3, False)
    assert tried == [("s:1:1", 0.0, True)] and "probando otra" in mpv.overlays[3]
    p.tick(segment, segment.loaded + 4, False)
    assert len(tried) == 1  # no se reintenta dos veces la misma


def test_when_no_source_works_it_says_so_and_closes():
    p, mpv = series_player(**{"time-pos": None, "duration": None})
    p.on_failed = lambda *a: False
    p.tick(p.segment, p.segment.loaded + player.STARTUP_TIMEOUT + 1, False)
    assert "ninguna fuente" in mpv.overlays[3]


def test_progress_is_saved_every_minute_not_only_at_the_end():
    p, mpv = series_player()
    saved = []
    p.on_progress = lambda meta, pos, dur, watched: saved.append((pos, watched))
    segment = p.segment
    p.tick(segment, 100, False)  # primera imagen
    mpv.props["time-pos"] = 660.0
    p.tick(segment, 100 + player.SAVE_EVERY + 1, False)
    for _ in range(50):
        if saved:
            break
        import time
        time.sleep(.01)
    assert saved and saved[0][0] == 660.0 and saved[0][1] > 0


def test_next_episode_card_counts_down_and_plays_in_the_same_window():
    p, mpv = series_player(**{"time-pos": 5980.0, "duration": 6000.0})
    started = []
    p.next_provider = lambda meta: {"label": "T1 E2", "title": "Diversity Day", "play": lambda: started.append("T1 E2")}
    segment = p.segment
    p.tick(segment, 0, False)  # primera imagen
    segment.upnext = p.next_provider(segment.meta)  # (lo busca en segundo plano)
    segment.upnext_requested = True
    p.tick(segment, 1, False)
    assert "Siguiente episodio en 8" in mpv.overlays[4] and "Diversity Day" in mpv.overlays[4]
    p.tick(segment, 1 + player.UPNEXT_COUNTDOWN + .1, False)
    import time
    for _ in range(50):
        if started:
            break
        time.sleep(.01)
    assert started == ["T1 E2"] and mpv.overlays[4] is None


def test_b_on_the_card_stays_in_the_credits():
    p, mpv = series_player(**{"time-pos": 5980.0, "duration": 6000.0})
    p.next_provider = lambda meta: {"label": "T1 E2", "title": "", "play": lambda: None}
    segment = p.segment
    p.tick(segment, 0, False)
    segment.upnext, segment.upnext_requested = p.next_provider(segment.meta), True
    p.tick(segment, 1, False)
    p.press("b")
    assert mpv.overlays[4] is None and ("quit",) not in mpv.sent and segment.upnext_dismissed


def test_after_three_episodes_without_touching_anything_it_asks():
    p, mpv = series_player(**{"time-pos": 5980.0, "duration": 6000.0})
    p._quiet_episodes = 2
    p.next_provider = lambda meta: {"label": "T1 E4", "title": "", "play": lambda: None}
    segment = p.segment
    p.tick(segment, 0, False)
    segment.upnext, segment.upnext_requested = p.next_provider(segment.meta), True
    p.tick(segment, 1, False)
    assert "¿Sigues viendo?" in mpv.overlays[4]
    p.press("b")
    assert ("quit",) in mpv.sent


def test_skip_intro_from_chapters():
    chapters = [{"time": 0, "title": "Prologue"}, {"time": 60, "title": "Opening"}, {"time": 150, "title": "Part A"}]
    p, mpv = series_player(**{"time-pos": 65.0, "chapter-list": chapters, "chapter": 1})
    segment = p.segment
    p.tick(segment, 0, False)
    p.tick(segment, 1, False)
    assert "Saltar intro" in mpv.overlays[4]
    p.press("a")
    assert ("seek", 150.0, "absolute") in mpv.sent and mpv.overlays[4] is None
    assert player.chapter_kind("End Credits") == "credits" and player.chapter_kind("Part B") is None


def test_menu_tabs_and_subtitle_size():
    p, mpv = make_player()
    p.sources_provider = lambda meta: [{"id": 3, "label": "1080p · Al instante", "current": True},
                                       {"id": 7, "label": "4K · Torrentio", "current": False}]
    switched = []
    p.on_switch_source = lambda meta, sid, pos: switched.append((sid, pos))
    p.press("x")
    assert p.menu.tabs == ["audio", "sub", "source"] and "FUENTE" in mpv.overlays[2]
    p.press("rb")
    assert p.menu.kind == "sub"
    p.menu.index = len(p.menu.options) - 1
    p.press("a")  # Tamaño: Normal -> Grande (se queda en el menú)
    assert p.sub_scale == 1.25 and p.menu is not None and ("set_property", "sub-scale", 1.25) in mpv.sent
    p.press("rb")
    assert p.menu.kind == "source"
    p.press("down")
    p.press("a")
    import time
    for _ in range(50):
        if switched:
            break
        time.sleep(.01)
    assert switched == [(7, 600.0)]


def test_source_label_and_binge_group():
    from orbital.catalog import source_label
    src = streams.parse({"name": "Torrentio\n4k DV | HDR", "title": "Movie.2160p\n💾 20 GB 👤 50",
                         "behaviorHints": {"bingeGroup": "torrentio|4k"}}, "Torrentio", "u", 0)
    assert src.binge == "torrentio|4k"
    assert source_label(src) == "4K DV · Torrentio"


def test_credits_from_cinemeta():
    info = {"cast": ["A", "B"], "director": ["D"], "links": [{"name": "W", "category": "Writers"}], "released": "2014-11-05T00:00"}
    got = cinemeta.credits(info)
    assert got["cast"] == ["A", "B"] and got["directors"] == ["D"] and got["writers"] == ["W"]
    assert got["released"] == "2014-11-05"


def test_errors_in_plain_words():
    err = FileNotFoundError(2, "No such file", r"C:\Emus\Eden\eden.exe")
    assert humane_error(err) .startswith("No encuentro eden")
    assert "WinError" not in humane_error(OSError("[WinError 5] Acceso denegado"), "Hades")


def test_hud_says_when_it_ends_and_forced_subtitles_option():
    from orbital import player_ui
    assert player_ui.ends_at(600, 6000, now=0) != "" and player_ui.ends_at(5990, 6000, now=0) == ""
    hud = player_ui.hud_ass(player_ui.Hud("X", position=600, duration=6000, ends="23:40"))
    assert "termina a las 23:40" in hud
    cmd = player.build_command("mpv.exe", "u", "t", audio="es", subtitles="forced")
    assert "--subs-with-matching-audio=forced" in cmd and "--slang=es,spa,Spanish,es-419" in cmd
    assert "--sid=no" in player.build_command("mpv.exe", "u", "t", subtitles="")


def test_knows_how_it_ended_before_closing():
    p, mpv = series_player(**{"time-pos": 5990.0, "duration": 6000.0})
    p.tick(p.segment, 0, False)
    p.hide_hud()
    p.press("b")  # sale con la barra oculta, en los créditos
    assert ("quit",) in mpv.sent and p.last_end == {"title": "Interstellar", "finished": True, "kind": "series"}
