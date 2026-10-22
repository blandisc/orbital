"""Latino o castellano en la TV: el ajuste, el orden de las fuentes, la pista que suena, lo que recuerda cada serie y lo
que dice «Ver» (las mismas cuentas que el iPhone, `Streams.languageScore`)."""

import json
from pathlib import Path

from test_player import make_player

from orbital import player_ui, watch
from orbital.library import streams
from orbital.playback import track_variant

FIXTURES = Path(__file__).parent / "fixtures" / "ios" / "streams.json"


def source(index, title, name="Torrentio\n1080p", cached=True):
    stream = {"name": name.replace("Torrentio", "[RD+] Torrentio") if cached else name, "title": title,
              "url": f"https://cdn/{index}.mkv"}
    return streams.parse(stream, "Torrentio", "https://t/manifest.json", index)


LATINO = "Simpsons.S08E23.1080p.WEB-DL.Latino\n💾 1.2 GB 👤 40"
DUAL_LAT = "Simpsons.S08E23.1080p.Dual-Lat\n💾 1.3 GB 👤 40"
CASTELLANO = "Simpsons.S08E23.1080p.WEB-DL.Castellano\n💾 1.2 GB 👤 40"
SPANISH = "Simpsons.S08E23.1080p.WEB-DL\n🇪🇸 💾 1.2 GB 👤 40"
ENGLISH = "The.Simpsons.S08E23.1080p.WEB-DL\n💾 1.2 GB 👤 40"


def order(prefs, *titles):
    return [s.index for s in streams.rank([source(i, t) for i, t in enumerate(titles)], prefs, "series")]


def test_sin_variante_el_orden_es_el_de_siempre():
    """Con «Español (cualquiera)» o con inglés, nada cambia: las cuentas que ya comparten la TV y el iPhone."""
    data = json.loads(FIXTURES.read_text(encoding="utf-8"))
    samples = [c["stream"] for c in data["parsed"]]
    for case in data["ranked"]:
        prefs = streams.Preferences(audio=case["audio"], quality=case["quality"])
        found = streams.rank([streams.parse(s, "Torrentio", "https://t.example/manifest.json", i) for i, s in enumerate(samples)],
                             prefs, case["kind"])
        assert [s.index for s in found] == case["order"]
        assert {str(s.index): s.score for s in found} == {k: v for k, v in case["scores"].items()}


def test_con_latino_primero_el_doblaje_pedido_luego_el_que_no_dice_y_al_final_el_otro():
    latino = streams.Preferences(audio="es", spanish="es-419")
    assert order(latino, CASTELLANO, SPANISH, LATINO) == [2, 1, 0]
    castellano = streams.Preferences(audio="es", spanish="es-ES")
    assert order(castellano, LATINO, SPANISH, CASTELLANO) == [2, 1, 0]
    # «Dual-Lat» (latino + inglés) va antes que un español que no dice cuál, pero después del latino solo.
    assert order(latino, SPANISH, DUAL_LAT, LATINO) == [2, 1, 0]
    # Sin variante: cualquier español solo vale lo mismo (gana el que tenga más a favor, no el doblaje).
    anyone = streams.Preferences(audio="es")
    assert streams.language_score(source(0, CASTELLANO), anyone) == streams.language_score(source(1, LATINO), anyone) == 300
    assert streams.language_score(source(0, ENGLISH), latino) == -600


def test_la_bandera_de_espana_sola_no_es_castellano():
    spanish = source(0, SPANISH)
    assert spanish.dub == "" and spanish.languages == ["es"]
    assert source(1, CASTELLANO).dub == "castellano" and source(2, LATINO).public()["dub"] == "latino"


def test_cada_variante_se_busca_y_se_recuerda_aparte():
    a = streams.cache_key("series", "tt1:1:1", streams.Preferences(audio="es", spanish="es-419"))
    b = streams.cache_key("series", "tt1:1:1", streams.Preferences(audio="es", spanish="es-ES"))
    assert a != b


def test_el_ajuste_de_idioma_trae_la_variante(library):
    w = library.watch
    w.state.set_setting("audio", "es-419")
    assert (w.stream_prefs.audio, w.stream_prefs.spanish) == ("es", "es-419")
    w.state.set_setting("audio", "es")
    assert (w.stream_prefs.audio, w.stream_prefs.spanish) == ("es", "")
    w.state.set_setting("audio", "en")
    assert (w.stream_prefs.audio, w.stream_prefs.spanish) == ("en", "")
    assert watch.spanish_variant("es-MX") == "es-419" and watch.spanish_variant("es-ES") == "es-ES"
    assert watch.spanish_variant("spa") == "" and watch.spanish_variant("en") == ""


def test_elegir_la_pista_latina_lo_recuerda_la_serie(library):
    w = library.watch
    w.state.set_setting("audio", "es")
    meta = {"meta_id": "tt0096697", "title": "Los Simpson"}
    w._remember_language(meta, "audio", "es-419")
    prefs, _ = w.language_for("tt0096697")
    assert (prefs.audio, prefs.spanish) == ("es", "es-419")
    w._remember_language(meta, "audio", "spa")  # una pista que no dice cuál: lo que ya sabía se queda
    assert w.language_for("tt0096697")[0].spanish == "es-419"
    w._remember_language(meta, "audio", "eng")  # en inglés: la variante no estorba (solo cuenta con español)
    assert w.language_for("tt0096697")[0].audio == "en"
    assert w.language_for("otro")[0].spanish == ""


def test_la_pista_del_panel_dice_su_doblaje():
    assert track_variant("spa", "Español · Latino · 5.1") == "es-419"
    assert track_variant("spa", "Español · Castellano") == "es-ES"
    assert track_variant("es-419", "Español latino") == "es-419"
    assert track_variant("spa", "Español · 5.1") == ""
    assert track_variant("eng", "Inglés · Latin Jazz") == ""  # no es español
    assert player_ui.language("es-ES") == "Castellano"


TWO_SPANISH = [{"id": 1, "type": "audio", "lang": "spa", "title": "Castellano", "selected": True},
               {"id": 2, "type": "audio", "lang": "spa", "title": "Latino"},
               {"id": 3, "type": "audio", "lang": "eng"}]


def test_el_reproductor_pone_la_pista_del_doblaje_que_quieres():
    p, mpv = make_player(**{"track-list": TWO_SPANISH})
    segment = type("S", (), {"meta": {"meta_id": "tt1"}})()
    p._audio_lang, p.spanish_provider = "es", lambda meta: "es-419"
    p._pick_dub(segment, TWO_SPANISH)
    assert ("set_property", "aid", 2) in mpv.sent
    mpv.sent.clear()
    p.spanish_provider = lambda meta: "es-ES"  # ya suena la castellana: no se toca
    p._pick_dub(segment, TWO_SPANISH)
    assert not mpv.sent
    p._audio_lang, p.spanish_provider = "en", lambda meta: "es-419"  # en inglés: nada que elegir
    p._pick_dub(segment, TWO_SPANISH)
    assert not mpv.sent


def test_ver_dice_lo_que_va_a_sonar():
    latino = streams.Preferences(audio="es", spanish="es-419")
    assert watch.version_line(source(0, LATINO), latino, "") == "Latino · 1080p · Sin subtítulos"
    assert watch.version_line(source(0, SPANISH), latino, "") == "Español · 1080p · Sin subtítulos"  # no dice cuál
    assert watch.version_line(source(0, ENGLISH), latino, "es") == "Inglés · 1080p · Subtítulos en español"
    assert watch.version_line(source(0, DUAL_LAT), streams.Preferences(audio="en"), "forced") \
        == "Inglés · 1080p · Solo traducciones en pantalla"


def test_ver_y_la_ficha_eligen_la_misma(library, monkeypatch):
    w = library.watch
    found = [source(0, LATINO), source(1, CASTELLANO)]
    monkeypatch.setattr(w, "stream_sources", lambda kind, video_id, prefs=None: found)
    monkeypatch.setattr(w, "best_source", lambda kind, video_id, binge=None, skip=None, prefs=None: found[0])
    prefs = streams.Preferences(audio="es", spanish="es-419")
    assert w.choose_source("movie", "tt1", prefs) is found[0]
    assert w.choose_source("movie", "tt1", prefs, {"video_id": "tt1", "source": found[1].key}) is found[1]  # «Continuar»
    assert w.choose_source("movie", "tt1", prefs, {"video_id": "tt1", "source": "ya-no-está"}) is found[0]
