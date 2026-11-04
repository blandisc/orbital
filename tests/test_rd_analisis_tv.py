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
