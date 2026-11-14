"""V2 en la TV (Fernando, 13 nov 2026: «aplica lo mismo de iPhone»): el canal no desordena tu serie, pero lo que dejaste a
medias siempre se puede retomar. Las mismas historias que `ChannelProgressTests.swift` del iPhone."""

from __future__ import annotations

from orbital.trakt_sync import CHANNEL_MIN_WATCHED, ChannelDetours, merge

SHOW = "tt0096697"


def store() -> tuple[ChannelDetours, dict]:
    box: dict = {}
    return ChannelDetours(lambda: box.get("v"), lambda v: box.__setitem__("v", v)), box


def in_order(last: float = 1_000.0) -> dict[str, dict]:
    """Ibas en tu orden: te toca T1 E2."""
    return {SHOW: {"title": "Los Simpson", "last_watched": last, "next": (1, 2), "watched": {(1, 1)}}}


def row(items, imdb=SHOW):
    found = [i for i in merge([], [], *items) if i.extra.get("meta_id") == imdb and i.category == "continue"]
    return found[0] if found else None


def test_un_episodio_del_canal_a_medias_sale_en_seguir_viendo():
    s, _ = store()
    assert s.progress(SHOW, f"{SHOW}:2:3", 600, 1320, 600, 2_000, f"{SHOW}:1:2", title="Los Simpson")
    item = row((in_order(), {}, None, lambda i: None, s.data()))
    assert item.extra["video_id"] == f"{SHOW}:2:3", "«T2 E3 · quedan 12 min», no el siguiente de tu orden"
    assert abs(item.progress - 600 / 1320) < .001
    assert s.data()["detours"][SHOW]["before"] == f"{SHOW}:1:2", "tu orden queda apartado"
    assert s.position(SHOW, f"{SHOW}:2:3") == (600, 2_000), "«Continuar» lo retoma ahí"


def test_terminado_queda_visto_pero_no_mueve_tu_siguiente():
    s, _ = store()
    s.progress(SHOW, f"{SHOW}:2:3", 600, 1320, 600, 2_000, f"{SHOW}:1:2")
    s.finished(SHOW, f"{SHOW}:2:3", 2_700, f"{SHOW}:1:2")
    # Trakt ya lo tiene visto y diría que te toca T2 E4.
    trakt = {SHOW: {"title": "Los Simpson", "last_watched": 2_700, "next": (2, 4), "watched": {(1, 1), (2, 3)}}}
    item = row((trakt, {}, None, lambda i: None, s.data()))
    assert item.extra["video_id"] == f"{SHOW}:1:2" and item.progress is None, "sigues en tu orden, no en T2 E4"
    assert SHOW not in s.data()["detours"]


def test_de_una_serie_que_no_ves_no_deja_siguiente():
    s, _ = store()
    s.finished(SHOW, f"{SHOW}:2:3", 2_700, None)
    trakt = {SHOW: {"title": "Los Simpson", "last_watched": 2_700, "next": (2, 4), "watched": {(2, 3)}}}
    assert row((trakt, {}, None, lambda i: None, s.data())) is None


def test_zapear_no_cambia_nada():
    s, box = store()
    assert not s.progress(SHOW, f"{SHOW}:2:3", 700, 1320, CHANNEL_MIN_WATCHED - 1, 2_000, f"{SHOW}:1:2")
    assert "v" not in box


def test_si_el_canal_puso_el_que_te_tocaba_es_verlo_en_orden():
    s, _ = store()
    s.finished(SHOW, f"{SHOW}:1:2", 2_700, f"{SHOW}:1:2")
    assert s.data()["kept"] == {}, "tu orden pasa al siguiente, como siempre"


def test_dos_del_canal_guardan_tu_orden_de_antes_del_primero():
    s, _ = store()
    s.progress(SHOW, f"{SHOW}:2:3", 600, 1320, 600, 2_000, f"{SHOW}:1:2")
    s.progress(SHOW, f"{SHOW}:2:9", 300, 1320, 300, 2_100, f"{SHOW}:1:2")
    assert s.data()["detours"][SHOW]["before"] == f"{SHOW}:1:2"
    s.finished(SHOW, f"{SHOW}:2:9", 3_000, f"{SHOW}:1:2")
    assert s.data()["kept"][SHOW]["before"] == f"{SHOW}:1:2"


def test_quitarlo_de_seguir_viendo_lo_olvida():
    s, _ = store()
    s.progress(SHOW, f"{SHOW}:2:3", 600, 1320, 600, 2_000, f"{SHOW}:1:2")
    s.dismiss(SHOW)
    item = row((in_order(), {}, None, lambda i: None, s.data()))
    assert item.extra["video_id"] == f"{SHOW}:1:2"


def test_lo_que_viste_despues_en_otro_aparato_manda():
    s, _ = store()
    s.finished(SHOW, f"{SHOW}:2:3", 2_700, f"{SHOW}:1:2")
    later = {SHOW: {"title": "Los Simpson", "last_watched": 9_000, "next": (1, 3), "watched": {(1, 1), (1, 2), (2, 3)}}}
    assert row((later, {}, None, lambda i: None, s.data())).extra["video_id"] == f"{SHOW}:1:3"
