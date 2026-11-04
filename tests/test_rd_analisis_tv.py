"""Análisis de fondo de Real-Debrid (Fernando, 3 nov 2026: «para que no encuentre yo más errores»): los 9 errores que el
iPhone encontró con los escenarios comunes (tests/fixtures/rd-scenarios), revisados en la TV. Cada prueba dice cuál."""

import time

from orbital import rd_requests, watch
from orbital.library import cinemeta, streams


def source(index, title, name="[RD+] Torrentio\n1080p", **extra):
    stream = {"name": name, "title": title, "url": f"https://cdn/{index}.mkv", **extra}
    return streams.parse(stream, "Torrentio", "https://t/manifest.json", index)


LATINO = "Cowboy Bebop 01 1440p Latino\n💾 1.2 GB 👤 40"


def test_error_4_1440p_cuenta_como_1080p():
    s = source(0, LATINO, name="[RD+] Torrentio\n1440p")
    assert s.resolution == "1440p" and streams.res_class(s.resolution) == "1080p"
    same = source(1, LATINO.replace("1440p", "1080p"))
    prefs = streams.Preferences(audio="es", spanish="es-419")
    assert streams.score(s, prefs, "series") == streams.score(same, prefs, "series")
    rows = watch.version_grid([s], prefs)
    assert [c["label"] for r in rows for c in r["cells"]] == ["1080p"]  # va con las de 1080p, no con «SD»


def test_error_2_otro_episodio_nunca_es_la_recomendada(library, monkeypatch):
    # Torrentio pone en «Breaking Bad» T1 E1 un paquete latino de la temporada 4 (escenario 11).
    assert streams.other_episode("Breaking Bad T4 720p Dual Latino-Ingles", "04 - CAPITULO 01.mkv", 1)
    assert not streams.other_episode("Breaking.Bad.S01E01.1080p", "", 1)
    assert not streams.other_episode("Breaking.Bad.S01-S05.1080p.Latino", "", 1)  # la serie completa sí trae T1
    assert not streams.other_episode("Breaking Bad S04", "Breaking.Bad.S01E01.mkv", 1)  # el archivo manda
    assert streams.season_of("tt0903747:1:1") == 1 and streams.season_of("kitsu:1:1") is None  # Kitsu va de corrido
    wrong = source(0, "Breaking Bad T4 720p Dual Latino-Ingles\n04 - CAPITULO 01.mkv\n👤 7 💾 322.53 MB")
    wrong.other_episode = True
    right = source(1, "Breaking.Bad.S01E01.720p.Latino\n👤 3 💾 300 MB", name="[RD download] Torrentio\n720p")
    prefs = streams.Preferences(audio="es", spanish="es-419")
    found = streams.rank([wrong, right], prefs, "series")
    assert found[0].score - found[1].score < 1500  # al instante, la de otra temporada todavía puede sumar más…
    w = library.watch
    monkeypatch.setattr(w, "stream_sources", lambda kind, video_id, prefs=None: found)
    assert w.best_source("series", "tt0903747:1:1", prefs=prefs) is right  # …pero nunca es la recomendada
    assert not watch.ready_now(wrong) and wrong.public()["other_episode"]


def test_error_3_kitsu_sabe_que_es_japones(library, monkeypatch):
    w = library.watch
    asked = []
    monkeypatch.setattr(w.localizer, "facts", lambda kind, meta_id: None)
    monkeypatch.setattr(w.cinemeta, "meta", lambda kind, meta_id: asked.append(meta_id) or {"name": "Cowboy Bebop"})
    facts = w._title_facts("series", "kitsu:1:1")
    assert asked == ["kitsu:1"] and facts["original"] == "ja" and facts["titles"] == ["Cowboy Bebop"]


def test_error_6_sin_clave_dice_vuelve_a_conectar(library, monkeypatch):
    w = library.watch
    monkeypatch.setattr(w, "stream_sources", lambda kind, video_id, prefs=None: [])
    monkeypatch.setattr(w.rd, "client", lambda: None)
    monkeypatch.setattr(w.rd, "status", lambda video_id: None)
    monkeypatch.setattr(w, "_release_of", lambda kind, meta_id, video_id: None)
    got = w.availability("movie", "tt1375666", "tt1375666")
    assert (got["why"], got["message"], got["can_request"]) == ("debrid-account", "Vuelve a conectar Real-Debrid", False)


def test_error_7_una_pelicula_por_estrenarse(library, monkeypatch):
    w = library.watch
    soon = time.strftime("%Y-%m-%dT00:00:00.000Z", time.gmtime(time.time() + 40 * 86400))
    monkeypatch.setattr(w.cinemeta, "meta", lambda kind, meta_id: {"name": "Avengers: Doomsday", "released": soon})
    monkeypatch.setattr(w.rd, "status", lambda video_id: None)
    assert w._release_of("movie", "tt21357150", "tt21357150") == cinemeta.released_at(soon)
    got = w.availability("movie", "tt21357150", "tt21357150")
    assert got["why"] == "unreleased" and got["message"].startswith("Aún no se estrena · sale ")


def test_error_9_lo_pedido_le_gana_a_continuar(library, monkeypatch):
    w = library.watch
    old, mine, cam = source(0, "Inception.2010.1080p.Latino"), source(1, "Inception.2010.1080p.Dual-Lat"), \
        source(2, "Inception.2010.HDCAM.Latino")
    mine.requested = True
    found = [mine, old, cam]
    monkeypatch.setattr(w, "stream_sources", lambda kind, video_id, prefs=None: found)
    monkeypatch.setattr(w, "best_source", lambda kind, video_id, binge=None, skip=None, prefs=None: found[0])
    prefs = streams.Preferences(audio="es", spanish="es-419")
    assert w.choose_source("movie", "tt1375666", prefs, {"source": old.key}) is mine
    mine.requested = False
    assert w.choose_source("movie", "tt1375666", prefs, {"source": old.key}) is old  # sin pedido, «Continuar» como antes
    assert w.choose_source("movie", "tt1375666", prefs, {"source": cam.key}) is found[0]  # nunca la de cine


def test_error_1_el_siguiente_episodio_de_un_paquete_pedido(library, monkeypatch):
    w = library.watch
    pack = "c" * 40
    e2 = source(0, "Breaking.Bad.S01.1080p.Latino\nBreaking.Bad.S01E02.mkv", name="[RD download] Torrentio\n1080p",
                infoHash=pack)
    other = source(1, "Breaking.Bad.S01E02.720p.Latino", name="[RD download] Torrentio\n720p", infoHash="d" * 40)
    monkeypatch.setattr(type(w), "has_addons", property(lambda self: True))
    monkeypatch.setattr(w.streams, "find", lambda kind, video_id, prefs: [other, e2])
    monkeypatch.setattr(w.rd, "status", lambda video_id: None)
    monkeypatch.setattr(w.rd, "ready_packs", lambda meta_id: {pack} if meta_id == "tt0903747" else set())
    got = w.stream_sources("series", "tt0903747:1:2", streams.Preferences(audio="es"))
    assert got[0] is e2 and e2.cached and e2.requested and watch.ready_now(e2) and not other.requested


def test_ready_packs_solo_lo_tuyo_listo_y_con_todos_sus_videos():
    class State:
        data = {}

        def prefs(self, item):
            return dict(self.data.get(item, {}))

        def set_pref(self, item, key, value):
            self.data.setdefault(item, {})[key] = value

    class Finder:
        timeout = 5

        def addons(self):
            return []

    reqs = rd_requests.RdRequests(Finder(), State(), lambda e: None, rd_factory=lambda token: None)
    reqs.account = lambda: "7"
    base = {"account": "7", "kind": "series", "meta_id": "tt0903747", "video_ids": ["tt0903747:1:1"], "state": "ready",
            "all_files": True}
    entries = {"a" * 40: base, "b" * 40: {**base, "account": "8"}, "c" * 40: {**base, "state": "downloading"},
               "d" * 40: {**base, "all_files": False}, "e" * 40: {**base, "meta_id": "tt1"}}
    reqs._entries = lambda: [{**v, "hash": k} for k, v in entries.items()]
    assert reqs.ready_packs("tt0903747") == {"a" * 40}


def test_fq2_la_que_real_debrid_no_dejo_bajar_nunca_es_la_recomendada(library, monkeypatch):
    w = library.watch
    no = source(0, "Inception.2010.1080p.Latino", name="[RD download] Torrentio\n1080p", infoHash="e" * 40)
    yes = source(1, "Inception.2010.720p.Latino", name="[RD download] Torrentio\n720p", infoHash="f" * 40)
    monkeypatch.setattr(w, "stream_sources", lambda kind, video_id, prefs=None: [no, yes])
    monkeypatch.setattr(w.rd, "refused", lambda: {"e" * 40})
    assert w.best_source("movie", "tt1375666") is yes
    monkeypatch.setattr(w.rd, "refused", lambda: {"e" * 40, "f" * 40})
    assert w.best_source("movie", "tt1375666") is no  # si todas, la primera (algo hay que ofrecer)


def test_fq1_ver_en_castellano_y_al_lado_pedir_la_latina(library, monkeypatch):
    w = library.watch
    cast = source(0, "Dune.Part.Two.2024.1080p.Castellano")
    lat = source(1, "Dune.Part.Two.2024.1080p.Latino", name="[RD download] Torrentio\n1080p", infoHash="a" * 40)
    monkeypatch.setattr(type(w), "asked_language", lambda self, meta: (streams.Preferences(audio="es", spanish="es-419"), ""))
    monkeypatch.setattr(w, "stream_sources", lambda kind, video_id, prefs=None: [cast, lat])
    monkeypatch.setattr(w.rd, "client", lambda: object())
    monkeypatch.setattr(w.rd, "status", lambda video_id: None)
    monkeypatch.setattr(w.rd, "refused", lambda: set())
    monkeypatch.setattr(w, "_release_of", lambda kind, meta_id, video_id: None)
    got = w.availability("movie", "tt15239678", "tt15239678")
    assert got["why"] == "ok" and got["offer"] == {"label": "Pedir a la nube en latino", "hash": "a" * 40}
    monkeypatch.setattr(w.rd, "refused", lambda: {"a" * 40})  # la que no dejó bajar no se ofrece (FQ2-A)
    assert "offer" not in w.availability("movie", "tt15239678", "tt15239678")
    monkeypatch.setattr(w, "stream_sources", lambda kind, video_id, prefs=None: [source(2, "Dune.Part.Two.2024.1080p.Latino"), lat])
    assert "offer" not in w.availability("movie", "tt15239678", "tt15239678")  # ya arranca en latino: nada que pedir


def test_orden_de_idiomas_latino_original_ingles_castellano():
    """Fernando, 4 nov 2026: «El orden sería latino, idioma original, luego inglés y luego castellano»."""
    prefs = streams.Preferences(audio="es", spanish="es-419", original="ja")
    lat = source(0, "Frieren.S01E01.1080p.Latino", name="[RD download] Torrentio\n1080p")
    ja = source(1, "Frieren.S01E01.1080p.Japanese")
    en = source(2, "Frieren.S01E01.1080p.English")
    cast = source(3, "Frieren.S01E01.1080p.Castellano")
    score = lambda s: streams.language_score(s, prefs)  # noqa: E731
    assert score(lat) > score(ja) > score(en) > score(cast) > streams.WRONG_LANGUAGE
    # Al instante: sin latino al instante, «Ver» pone el japonés antes que el castellano (y el latino se pide al lado, FQ1).
    assert [s.index for s in streams.rank([cast, en, ja, lat], prefs, "series")][:3] == [1, 2, 3]


def test_error_3_nuevo_el_dia_de_estreno_se_dice_en_utc(monkeypatch):
    """Cinemeta: «2026-12-18T00:00:00.000Z» es el viernes 18, también en México (antes decía «el jueves 17»)."""
    from datetime import datetime
    monkeypatch.setattr(time, "time", lambda: datetime(2026, 11, 3, 18).timestamp())
    assert watch.player_ui_day(cinemeta.released_at("2026-12-18T00:00:00.000Z")) == "el viernes 18"


def test_n4_tus_idiomas_es_la_unica_fuente(library):
    """N4-A (Fernando, 4 nov): una lista en orden con «Idioma original»; de ahí leen la búsqueda y Torrentio."""
    w = library.watch
    w.state.set_setting("audio", "es-419")
    assert w.languages == ["es-419", "original", "en", "es-ES"]  # sin tocarla: la de siempre con latino
    w.set_languages(["en", "original", "es-419"])
    prefs = w.stream_prefs
    assert (prefs.audio, prefs.spanish, prefs.plan) == ("en", "", ("original", "es-419"))
    assert w.addon_list.torrentio().options["language"] == ["latino"]  # Torrentio sigue a tus idiomas
    ja = source(0, "Frieren.S01E01.1080p.Japanese")
    lat = source(1, "Frieren.S01E01.1080p.Latino")
    en = source(2, "Frieren.S01E01.1080p.English")
    with_original = streams.Preferences(audio="en", plan=("original", "es-419"), original="ja")
    s = lambda x: streams.language_score(x, with_original)  # noqa: E731
    assert s(en) > s(ja) > s(lat) > streams.WRONG_LANGUAGE
    for bad in (["original", "en"], [], ["en", "en"], ["xx"]):
        assert not streams.valid_languages(bad)
