"""«Probar otros» subtítulos en la TV (player_subs.py) y el panel X que ya no se cierra al elegir."""

from test_player import FakeMpv

from orbital import player, player_ui

SUBS = [
    {"id": 1, "type": "video"},
    {"id": 1, "type": "audio", "lang": "eng", "selected": True},
    {"id": 1, "type": "sub", "lang": "eng"},
    {"id": 2, "type": "sub", "lang": "spa", "forced": True},
    {"id": 3, "type": "sub", "lang": "spa", "title": "Latino", "selected": True},
    {"id": 4, "type": "sub", "lang": "spa", "title": "SDH"},
    {"id": 5, "type": "sub", "lang": "spa", "title": "Castellano"},
]
ADDON = ["https://subs.example/es/1.srt", "https://subs.example/es/2.srt", "https://subs.example/es/3.srt"]


def trial_player(urls=ADDON, tracks=SUBS):
    mpv = FakeMpv({"track-list": [dict(t) for t in tracks]})
    p = player.OrbitalPlayer(mpv=mpv)
    p.current = player.Playback("Dune", None, 0, {"meta_id": "tt1160419", "video_id": "tt1160419"})
    p.background = lambda work: work()  # sin hilos: lo de internet pasa en el momento
    p.TRY_PRELOAD_WAIT = 60  # la precarga se prueba a mano (_try_preload)
    p._subs_lang = "es"
    p._fallback_subs = (lambda: list(urls)) if urls is not None else None
    fetched = []

    def fetch(url):
        fetched.append(url)
        return f"C:/cache/subs/{url.rsplit('/', 1)[-1]}"

    p.fetch_subtitle = fetch
    return p, mpv, fetched


def sids(mpv):
    return [c[2] for c in mpv.sent if c[:2] == ("set_property", "sid")]


def test_choosing_a_subtitle_keeps_the_panel_open_and_lifts_the_subtitles():
    p, mpv, _ = trial_player()
    mpv.props["sub-pos"] = 95
    p.press("x")
    p.press("right")  # Subtítulos
    assert p.menu.column.key == "sub" and ("set_property", "sub-pos", 50) in mpv.sent
    labels = [o["label"] for o in p.menu.options]
    assert "Probar otros" in labels and labels[-1].startswith("Buscar en español")
    p.press("down")  # de «Español · Latino» a «Español · Para sordos»
    p.press("a")
    assert sids(mpv) == [4] and p.menu is not None and mpv.overlays[2]  # sigue abierto: pruebas el siguiente
    assert [o["label"] for o in p.menu.options if o.get("current")] == ["Español · Para sordos"]
    p.press("down")
    p.press("a")
    assert sids(mpv) == [4, 5] and p.menu is not None
    p.press("b")
    assert p.menu is None and mpv.sent[-1] == ("set_property", "sub-pos", 95)  # de vuelta a donde estaban


def test_try_others_steps_through_same_language_skipping_sdh_and_forced():
    p, mpv, _ = trial_player()
    p.press("x")
    p.press("right")
    p.menu.column.index = next(i for i, o in enumerate(p.menu.options) if o["label"] == "Probar otros")
    p.press("a")
    assert p.menu is None and p._try is not None
    strip = mpv.overlays[p.TRY]
    # Las del video en español (sin la de sordos ni la forzada) y las 3 de tu complemento.
    assert "Español · Subtítulo 1 de 5" in strip and "Del video" in strip and "Sincronía: A tiempo" in strip
    assert "Otro subtítulo" in strip and "Este va bien" in strip and "Dejar el de antes" in strip
    p.press("right")
    assert sids(mpv) == [5] and mpv.sent[-1] == ("seek", -8, "relative")  # el de Castellano, y la misma frase otra vez
    assert "Subtítulo 2 de 5" in mpv.overlays[p.TRY]
    p.press("right")  # el primero de tu complemento: se baja y se agrega
    assert ("sub-add", "C:/cache/subs/1.srt", "select", "Subtítulo 3", "es") in mpv.sent
    assert mpv.sent[-1] == ("seek", -8, "relative") and "De tu complemento" in mpv.overlays[p.TRY]
    p.press("left")
    assert sids(mpv)[-1] == 5 and mpv.sent[-1] == ("seek", -8, "relative")
    for _ in range(5):
        p.press("right")
    assert "No hay más subtítulos en español" in mpv.overlays[p.TRY]
    assert 4 not in sids(mpv) and 2 not in sids(mpv)  # nunca pasó por la de sordos ni la forzada


def test_sdh_is_offered_when_you_already_had_sdh():
    tracks = [dict(t, selected=t.get("id") == 4) if t["type"] == "sub" else t for t in SUBS]
    p, mpv, _ = trial_player(urls=None, tracks=tracks)
    assert p.try_subtitles() is None
    assert [c["track"] for c in p._try["candidates"]] == [3, 4, 5]  # la de sordos sí (era la tuya); la forzada no


def test_up_down_move_the_sync_and_b_goes_back_to_what_you_had():
    p, mpv, _ = trial_player()
    p.try_subtitles()
    p.press("up")
    p.press("up")
    p.press("down")
    delays = [c[2] for c in mpv.sent if c[:2] == ("set_property", "sub-delay")]
    assert delays == [-.5, -1.0, -.5] and "0,5 s antes" in mpv.overlays[p.TRY]
    p.press("right")
    p.press("b")
    assert p._try is None and mpv.overlays[p.TRY] is None
    assert sids(mpv)[-1] == 3 and mpv.sent[-1] == ("set_property", "sub-delay", 0.0)  # el de antes, a tiempo
    assert "Volviste a los subtítulos de antes" in mpv.overlays[3]


def test_a_keeps_it_and_the_title_remembers_it_with_its_sync():
    p, mpv, _ = trial_player()
    remembered, kept = [], []
    p.on_language = lambda meta, kind, lang: remembered.append((kind, lang))
    p.on_sub_kept = lambda meta: kept.append(p.current_subtitle())
    p.segment = player.Segment({"source_key": "rd:abc"}, "Dune", "u")
    p.try_subtitles()
    p.press("right")
    p.press("down")  # medio segundo después
    mpv.props["track-list"] = [dict(t, selected=t.get("id") == 5) if t["type"] == "sub" else t for t in SUBS]
    p.press("a")
    assert p._try is None and mpv.overlays[p.TRY] is None and sids(mpv)[-1] == 5
    assert remembered == [("subtitles", "spa")]
    assert kept == [{"off": False, "lang": "spa", "title": "Castellano", "url": "", "delay": .5, "delay_source": "rd:abc"}]
    assert "Subtítulo 2" in mpv.overlays[3]
    # «Continuar» con esa misma versión: los mismos subtítulos y su sincronía.
    q, qmpv, _ = trial_player()
    q.segment = player.Segment({"source_key": "rd:abc"}, "Dune", "u")
    q._sub_pick = kept[0]
    assert q._apply_sub_pick(SUBS) and ("set_property", "sid", 5) in qmpv.sent and ("set_property", "sub-delay", .5) in qmpv.sent
    other, ompv, _ = trial_player()  # otra versión: la sincronía no le va
    other.segment = player.Segment({"source_key": "rd:otra"}, "Dune", "u")
    other._sub_pick = kept[0]
    other._apply_sub_pick(SUBS)
    assert not any(c[:2] == ("set_property", "sub-delay") for c in ompv.sent)


def test_preloads_only_the_next_internet_subtitle():
    p, mpv, fetched = trial_player()
    p.try_subtitles()
    p.press("right")  # 2 de 5 (Castellano); el siguiente es el 1 de tu complemento
    p._try_preload(p._try["token"], p._try["index"])
    assert fetched == [ADDON[0]] and not any(c[0] == "sub-add" for c in mpv.sent)  # se baja, no se pone
    p._try_preload(p._try["token"], p._try["index"])
    assert fetched == [ADDON[0]]  # ya está: no se baja otra vez
    p.press("right")
    assert fetched == [ADDON[0]] and ("sub-add", "C:/cache/subs/1.srt", "select", "Subtítulo 3", "es") in mpv.sent
    p._try_preload(p._try["token"], p._try["index"] - 1)  # te moviste: la precarga vieja ya no hace nada
    assert fetched == [ADDON[0]]
    p._try_preload(p._try["token"], p._try["index"])
    assert fetched == [ADDON[0], ADDON[1]]  # solo el siguiente, nunca dos


def test_without_internet_or_more_subtitles_the_strip_says_so():
    def offline():
        raise OSError("sin red")

    p, mpv, _ = trial_player()
    p._fallback_subs = offline
    p.try_subtitles()
    assert "Sin internet" in mpv.overlays[p.TRY] and len(p._try["candidates"]) == 2
    p._try_end()

    def fails(url):
        raise OSError("timed out")

    p, mpv, _ = trial_player(tracks=[t for t in SUBS if t.get("id") != 5 or t["type"] != "sub"])
    p.fetch_subtitle = fails
    p.try_subtitles()
    p.press("right")
    assert "No pude bajar este subtítulo" in mpv.overlays[p.TRY] and not any(c[0] == "sub-add" for c in mpv.sent)


def test_phone_legend_and_back_while_trying():
    p, mpv, _ = trial_player()
    p.try_subtitles()
    legend = p.phone_legend()
    assert legend["right"] == "Subtítulo siguiente" and legend["select"] == "Este va bien"
    assert legend["back"] == "Dejar el de antes"
    p.phone_button("right")
    p.phone_button("back")
    assert p._try is None and sids(mpv) == [5, 3] and ("quit",) not in mpv.sent
    assert p.phone_legend()["alt"] == "Audio y subtítulos"


def test_the_strip_with_the_finger_has_buttons():
    p, mpv, _ = trial_player(urls=None)
    player_ui.set_touch(True)
    try:
        p.try_subtitles()
        right = next(t for t in player_ui.targets["try"] if t[4] == "right")
        p.tap(right[0] + 5, right[1] + 5)
        assert sids(mpv) == [5]
        keep = next(t for t in player_ui.targets["try"] if t[4] == "a")
        p.tap(keep[0] + 5, keep[1] + 5)
        assert p._try is None
    finally:
        player_ui.set_touch(False)
