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


def test_b_hides_the_controls_and_holding_it_leaves():
    import time
    p, mpv = make_player()
    p.press("a")  # pausa: la barra se queda
    assert mpv.overlays[1]
    p.press("b")  # en pausa el «En pausa» se queda (si no, parecía colgado); empieza el anillo de «Salir»
    assert mpv.overlays[1] and "Salir" in mpv.overlays[6] and ("quit",) not in mpv.sent
    p.press("b-up")  # soltaste antes: no sale
    assert mpv.overlays[6] is None and ("quit",) not in mpv.sent
    p.press("a")  # reproduciendo, B sí oculta los controles
    p.press("b")
    assert mpv.overlays[1] is None
    p.press("b-up")
    p.press("b")
    p.remote._repeats["b"] = 3  # sigue mantenido…
    p.press("b")
    assert ("quit",) not in mpv.sent  # …pero aún no se llena
    p._quit_hold = time.monotonic() - 2
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
    card = mpv.overlays[4]
    assert "Siguiente episodio" in card and "Diversity Day" in card and "}8" in card  # cuenta atrás en el anillo
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
    p.press("b")  # un toque: empieza el anillo, no sale (como en todo el reproductor)
    assert ("quit",) not in mpv.sent and "¿Sigues viendo?" in mpv.overlays[4]
    import time
    p._quit_hold = time.monotonic() - 2  # mantenido hasta llenarse
    p.remote._repeats["b"] = 3
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


def test_skip_intro_by_voice_without_the_card():
    """«Alexa, salta la intro»: también cuando la tarjeta ya se fue; sin capítulos de intro, None."""
    chapters = [{"time": 0, "title": "Opening"}, {"time": 90, "title": "Part A"}]
    p, mpv = series_player(**{"time-pos": 20.0, "chapter-list": chapters, "chapter": 0})
    p.tick(p.segment, 0, False)
    p._hide_card()
    assert p.skip_intro() == "Saltar intro" and ("seek", 90.0, "absolute") in mpv.sent
    mpv.props["chapter"] = 1
    assert p.skip_intro() is None


def test_panels_subtitle_size_and_more():
    p, mpv = make_player()
    p.sources_provider = lambda meta: [{"id": 3, "label": "1080p · Al instante", "current": True},
                                       {"id": 7, "label": "4K · Torrentio", "current": False}]
    switched = []
    p.on_switch_source = lambda meta, sid, pos: switched.append((sid, pos))
    p.press("x")
    p.press("right")
    p.press("right")
    assert p.menu.column.key == "size"
    p.press("down")
    p.press("a")  # Tamaño: Normal -> Grande (se queda en el panel)
    assert p.sub_scale == 1.25 and p.menu is not None and ("set_property", "sub-scale", 1.25) in mpv.sent
    p.press("right")  # ya es la última columna: no se sale
    assert p.menu.column.key == "size"
    p.press("y")  # dentro de un panel, X y Y lo cierran (no saltan al otro)
    assert p.menu is None
    p.press("y")  # Y: Fuentes (y Reproducción)
    assert p.menu.kind == "more" and [c.key for c in p.menu.columns] == ["source", "playback"]
    assert "Fuentes" in mpv.overlays[2] and "Desde el principio" in mpv.overlays[2]
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
    p.press("b")
    p._quit_hold, p.remote._repeats["b"] = 0.0, 9  # B mantenido hasta llenarse
    p.press("b")  # sale en los créditos
    assert ("quit",) in mpv.sent and p.last_end == {"title": "Interstellar", "finished": True, "kind": "series"}


def test_more_lists_the_season_and_restarts():
    p, mpv = series_player(**{"time-pos": 600.0, "duration": 1300.0})
    jumped = []
    p.episodes_provider = lambda meta: [{"id": "s:1:1", "label": "E1 · Pilot", "current": True},
                                        {"id": "s:1:2", "label": "E2 · Diversity Day", "current": False}]
    p.on_play_episode = lambda meta, vid: jumped.append(vid)
    p.press("y")
    assert [c.key for c in p.menu.columns] == ["episodes", "playback"] and p.menu.index == 0
    assert "Viendo" in mpv.overlays[2]
    p.press("down")
    p.press("a")
    import time
    for _ in range(50):
        if jumped:
            break
        time.sleep(.01)
    assert jumped == ["s:1:2"] and p.menu is None
    p.press("y")
    p.press("right")
    p.press("a")  # Desde el principio
    assert ("seek", 0, "absolute") in mpv.sent


def test_player_ui_pieces():
    from orbital import player_ui as ui
    assert ui.seek_label(10) == "+10 s" and ui.seek_label(-60) == "−1 min" and ui.seek_label(30) == "+30 s"
    assert ui.wrap("uno dos tres cuatro", 30, 10_000, 1) == ["uno dos tres cuatro"]
    assert ui.wrap("palabra " * 40, 26, 300, 2)[-1].endswith("…")
    assert ui.fit("Un título larguísimo de verdad", 24, 120).endswith("…")
    hud = ui.Hud("X", position=2000, duration=6000, chapters=[0, 1800, 4000], chapter_titles=["Intro", "Chapter 2", "El final"])
    assert ui.chapter_at(hud) == "Capítulo 2"  # nombre genérico: solo el número
    assert ui.ring(0, 0, 10, 2, 0, ui.TEXT) == "" and "m " in ui.ring(0, 0, 10, 2, .5, ui.TEXT)
    assert "EN PAUSA" not in ui.hud_ass(ui.Hud("X", paused=True)) and "En pausa" in ui.hud_ass(ui.Hud("X", paused=True))



def test_player_sources_show_all_with_language_first():
    """Todas las fuentes (antes 12: con la serie en inglés, las de español no salían), el idioma primero."""
    from types import SimpleNamespace

    from orbital import watch

    def src(i, langs):
        s = streams.Source(index=i, addon="Torrentio", stream={}, transport_url="")
        s.languages, s.resolution, s.cached = langs, "1080p", True
        return s

    found = [src(i, ["en"]) for i in range(15)] + [src(20, ["es"]), src(21, ["es"])]
    fake = SimpleNamespace(language_for=lambda meta_id: (streams.Preferences(audio="en"), "es"),
                           stream_sources=lambda kind, video, prefs: found)
    options = watch.Watch._player_sources(fake, {"kind": "series", "meta_id": "tt1", "video_id": "tt1:1:1", "source": 14})
    ids = [o["id"] for o in options]
    assert ids == [*range(15), 20, 21] and [o["id"] for o in options if o["current"]] == [14]
    assert next(o for o in options if o["id"] == 20)["label"].startswith("Español")


def _wait_for(cond):
    import time
    for _ in range(100):
        if cond():
            return
        time.sleep(.01)


def test_more_panel_offers_the_iphone_only_when_one_is_connected():
    p, _ = series_player()
    p.on_send_iphone = lambda meta, action, position=None: "ok"
    labels = lambda: [o["label"] for c in p.menu.columns for o in c.options]  # noqa: E731
    p.open_more()  # sin iPhone conectado: nada del iPhone
    assert [c.key for c in p.menu.columns] == ["playback"] and labels() == ["Desde el principio"]
    p.iphone_provider = lambda: False
    p.open_more()
    assert not any("iPhone" in label for label in labels())
    p.iphone_provider = lambda: True
    p.open_more()
    # Dentro de Reproducción (como cuarta columna todo se cortaba).
    assert [c.key for c in p.menu.columns] == ["playback"]
    assert labels() == ["Desde el principio", "Seguir en el iPhone", "Enviar al iPhone", "Descargar en el iPhone"]


def test_more_panel_has_no_iphone_for_live_tv():
    p, _ = series_player()
    p.current.meta = {"kind": "tv", "live": True, "title": "Canal"}
    p.iphone_provider, p.on_send_iphone = (lambda: True), (lambda meta, action, position=None: "ok")
    p.open_more()
    assert not any("iPhone" in o["label"] for c in p.menu.columns for o in c.options)


def test_choosing_an_iphone_option_sends_the_episode_in_progress_and_says_so():
    p, mpv = series_player()
    sent = []
    p.iphone_provider = lambda: True
    p.on_send_iphone = lambda meta, action, position=None: sent.append((meta["video_id"], action)) or "Enviado al iPhone: listo"
    p.open_more()
    p.press("down")
    p.press("down")
    p.press("down")
    p.press("a")  # Reproducción › Descargar en el iPhone
    _wait_for(lambda: sent)
    assert sent == [("s:1:1", "download")] and p.menu is None
    _wait_for(lambda: "Enviado al iPhone" in str(mpv.overlays.get(p.TOAST)))
    assert "Enviado al iPhone" in str(mpv.overlays.get(p.TOAST))


def test_an_iphone_without_connection_says_it_in_words_not_with_an_error():
    p, mpv = series_player()
    p.iphone_provider = lambda: True

    def refuse(meta, action, position=None):
        raise ValueError("Conecta tu iPhone en Ajustes › Cuentas")

    p.on_send_iphone = refuse
    p.open_more()
    p.press("down")
    p.press("down")
    p.press("a")  # Reproducción › Enviar al iPhone
    _wait_for(lambda: "Conecta tu iPhone" in str(mpv.overlays.get(p.TOAST)))
    assert "Conecta tu iPhone" in str(mpv.overlays.get(p.TOAST))



def test_the_quit_ring_fills_smoothly_on_its_own_clock():
    """El anillo de «Salir» se redibuja solo (a 30 cuadros por segundo), no solo con cada repetición de B; al soltar
    se va y no sale."""
    import time
    p, mpv = make_player()
    drawn = []
    original = p._overlay
    p._overlay = lambda layer, ass: (drawn.append((layer, ass)) if layer == p.HOLD else None, original(layer, ass))[1]
    p.press("b")
    time.sleep(.3)
    rings = [a for layer, a in drawn if a]
    assert len(rings) >= 5  # varios cuadros sin que llegue otra repetición de B
    p.press("b-up")
    time.sleep(.1)
    assert mpv.overlays[6] is None and ("quit",) not in mpv.sent


def test_iphone_remote_in_the_player():
    """El control del iPhone con el video al frente: A pausa, ← → buscan y B sale sin mantener (primero quita lo que haya)."""
    p, mpv = make_player()
    p.phone_button("select")
    assert ("set_property", "pause", True) in mpv.sent
    p.phone_button("back")  # en pausa, con la barra: sale (en el teléfono no hay «mantener B»)
    assert ("quit",) in mpv.sent


def test_the_time_is_said_in_12_hours():
    from datetime import datetime

    from orbital.text import clock
    assert clock(datetime(2026, 10, 16, 23, 40)) == "11:40 p. m."
    assert clock(datetime(2026, 10, 16, 0, 5)) == "12:05 a. m."
    assert clock(datetime(2026, 10, 16, 9, 0)) == "9:00 a. m."


def test_the_stick_walks_the_buttons_and_a_presses_the_focused_one():
    """El stick recorre los botones de siempre (empieza en Pausa) y A elige el enfocado; Adelantar, Volumen y Episodio
    abren sus opciones (A elige); la cruceta sigue siendo atajo y B quita el foco."""
    from orbital import player_ui

    p, mpv = series_player()
    p.on_episode = lambda meta, step: None  # una serie con LT/RT: sale «Episodio»
    p.press("stick-right")
    assert p._hud_focus == 0 and "Pausa" in mpv.overlays[1]  # Pausa enfocado
    p.press("stick-right")
    items = player_ui.nav_items(p._hud(p.current), paused=False)
    assert items[p._hud_focus][2] == "x"  # Audio y subtítulos
    p.press("a")
    assert p.menu is not None and p.menu.kind == "tracks"  # A abrió lo enfocado (no pausó)
    p.press("b")  # cierra el panel
    p._hud_focus = [i for i, it in enumerate(items) if it[2] == "seek"][0]
    p.show_hud()
    p.press("a")
    assert p.menu.kind == "seek" and p.menu.column.options[p.menu.column.index]["label"] == "+10 s"
    p.press("down")
    p.press("a")  # +30 s
    assert ("seek", 30, "relative") in mpv.sent and p.menu is None
    p._hud_focus = [i for i, it in enumerate(items) if it[2] == "episode"][0]
    p.show_hud()
    p.press("a")
    assert p.menu.kind == "episode" and p.menu.column.options[0]["label"] == "Siguiente episodio"
    p.press("b")
    p.press("b")
    assert p._hud_focus is None  # B quita el foco
    p.press("right")  # la cruceta sigue adelantando como siempre
    assert any(c[0] == "seek" and c[1] != 30 for c in mpv.sent[-3:])
