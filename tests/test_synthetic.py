"""Canales de Orbital: una serie al aire todo el día (Los Simpson en latino), con horario, doblaje y sin dejar rastro."""

from __future__ import annotations

import time
from types import SimpleNamespace

from orbital import player, synthetic
from orbital.library import streams
from orbital.playback import dub_track

CHANNEL = synthetic.SyntheticChannel("orbital:test", "Serie 24/7", (synthetic.Show("tt1", (3, 5)),), slot=1000)


def info(seasons=range(1, 8), per=4, meta_id="tt1", name="La serie") -> dict:
    return {"name": name, "poster": "p.jpg", "videos": [
        {"id": f"{meta_id}:{s}:{e}", "season": s, "episode": e, "name": f"Episodio {s}x{e}", "overview": f"Sinopsis {s}x{e}"}
        for s in range(8) if s in seasons for e in range(1, per + 1)]}


def source(index: int, title: str, url: str | None = None) -> streams.Source:
    src = streams.parse({"name": "Torrentio\n[RD+] 1080p", "title": title, "url": url or f"http://rd/{index}"},
                        "Torrentio", "https://addon", index)
    src.score = 100 - index
    return src


# --- latino o castellano --------------------------------------------------------------------------------------------
def test_las_fuentes_dicen_si_el_espanol_es_latino_o_castellano():
    assert streams.spanish_dub("Simpsons.S08E23.1996.1080p-Dual-Lat") == "latino"
    assert streams.spanish_dub("Los Simpsons (Completa Latino) 24") == "latino"
    assert streams.spanish_dub("Platinum ES-419") == "latino"
    assert streams.spanish_dub("Los Simpsons - Temporada 8 [HDTV][Castellano]") == "castellano"
    assert streams.spanish_dub("Simpsons 🇪🇸 💾 1 GB") == "castellano"
    assert streams.spanish_dub("Dual Latino Castellano") == "latino"  # trae la pista latina
    assert streams.spanish_dub("Los Simpson: Español: Temporadas 1 A 10") == ""  # no lo dice
    assert streams.spanish_dub("Cast.Away 2000 SPANISH") == ""  # «Cast» del título no es castellano
    assert streams.spanish_dub("Translation of a plate") == ""  # «lat» dentro de otra palabra no es latino
    lat = source(0, "Simpsons.S08E23-Dual-Lat")
    assert lat.dub == "latino" and lat.tags[0] == "Latino" and "es" in lat.languages
    assert source(1, "The Simpsons S08E23 1080p").dub == ""  # en inglés: sin doblaje que decir


def test_la_pista_de_audio_del_doblaje():
    lat = [{"id": 1, "type": "audio", "lang": "eng"}, {"id": 2, "type": "audio", "lang": "spa", "title": "Castellano"},
           {"id": 3, "type": "audio", "lang": "spa", "title": "Latino"}]
    assert dub_track(lat) == 3
    assert dub_track([{"id": 1, "type": "audio", "lang": "eng"}, {"id": 2, "type": "audio", "lang": "es-419"}]) == 2
    assert dub_track([{"id": 4, "type": "audio", "lang": "spa"}]) == 4  # español sin decir cuál: se queda
    assert dub_track([{"id": 2, "type": "audio", "lang": "spa", "title": "Castellano"}]) is False  # solo el otro
    assert dub_track([{"id": 1, "type": "audio", "lang": "eng"}]) is False  # idiomas, pero ningún español
    assert dub_track([{"id": 1, "type": "audio"}]) is None  # el archivo no dice: se queda la que trae


# --- el horario -----------------------------------------------------------------------------------------------------
def test_el_horario_es_el_mismo_para_todos_y_revuelve_cada_vuelta():
    episodes = synthetic.lineup(info(), CHANNEL.shows[0])
    assert [e["label"] for e in episodes][:2] == ["T3 E1", "T3 E2"] and len(episodes) == 12  # solo de la 3 a la 5
    first, again = synthetic.cycle_order(12, CHANNEL.id, 7), synthetic.cycle_order(12, CHANNEL.id, 7)
    assert first == again and sorted(first) == list(range(12))  # siempre el mismo orden y están todos
    assert synthetic.cycle_order(12, CHANNEL.id, 8) != first  # la siguiente vuelta, otro orden
    at = synthetic.EPOCH + 12 * 1000 * 3 + 5 * 1000 + 250  # tercera vuelta, sexto episodio, 250 s adentro
    assert synthetic.on_air(12, CHANNEL, at) == (3, 5, 250)
    assert synthetic.following(12, 3, 5) == (3, 6) and synthetic.following(12, 3, 11) == (4, 0)


# --- ponerlo -------------------------------------------------------------------------------------------------------
class FakePlayer:
    def __init__(self) -> None:
        self.played, self.loaded = [], []
        self.segment = None

    def play(self, run, mpv_exe, url, title, meta, **options):
        self.played.append((url, title, meta, options))

    def load(self, url, title, meta, **options):
        self.loaded.append((url, title, meta, options))
        return True


def fake_catalog(found: dict[str, list[streams.Source]], infos: dict | None = None):
    pl = FakePlayer()
    watch = SimpleNamespace(
        cinemeta=SimpleNamespace(meta=lambda kind, meta_id: (infos or {}).get(meta_id) or info()),
        stream_sources=lambda kind, video_id, prefs: list(found.get(video_id, [])),
        stream_prefs=streams.Preferences(audio="en", quality="1080p"), player=pl)
    sessions = SimpleNamespace(before_launch=None, pin=lambda: None, unpin=lambda p: None,
                               to_front=lambda *a, **k: False, revealing=False)
    launcher = SimpleNamespace(run=None, track=lambda *a, **k: None)
    return SimpleNamespace(watch=watch, sessions=sessions, launcher=launcher), pl


def on_air_now(now: float):
    episodes = synthetic.lineup(info(), CHANNEL.shows[0])
    cycle, place, offset = synthetic.on_air(len(episodes), CHANNEL, now)
    order = synthetic.cycle_order(len(episodes), CHANNEL.id, cycle)
    return episodes, cycle, place, offset, order


def test_prender_el_canal_entra_a_media_emision_y_solo_en_latino(monkeypatch):
    monkeypatch.setattr(player, "find_mpv", lambda: "mpv.exe")
    now = synthetic.EPOCH + 123_456.0
    episodes, cycle, place, offset, order = on_air_now(now)
    current = episodes[order[place]]["id"]
    found = {current: [source(0, "La serie S03 [Castellano]"), source(1, "La serie S03 en inglés"),
                       source(2, "La serie Español Temporadas"), source(3, "La.serie-Dual-Lat")]}
    catalog, pl = fake_catalog(found)
    tv = synthetic.SyntheticTV(catalog, [CHANNEL], clock=lambda: now)
    # Primero la que dice latino; luego la de español sin decir cuál; nunca castellano ni inglés.
    assert [s.index for s in tv.sources(CHANNEL, current)] == [3, 2]
    assert tv.play(CHANNEL.id)["ok"] is True
    url, title, meta, options = pl.played[0]
    assert url == "http://rd/3" and title == "Serie 24/7" and options["start"] == offset  # a media emisión
    assert options["audio"] == "es" and options["subtitles"] == ""
    assert meta["synthetic"] is True and meta["kind"] == "channel" and meta["dub"] == "latino"
    assert meta["detail"] == f"{episodes[order[place]]['label']} · {episodes[order[place]]['title']}"


def test_un_episodio_sin_latino_se_salta_y_el_siguiente_empieza_desde_el_principio(monkeypatch):
    monkeypatch.setattr(player, "find_mpv", lambda: "mpv.exe")
    now = synthetic.EPOCH + 50_000.0
    episodes, cycle, place, offset, order = on_air_now(now)
    nxt_cycle, nxt_place = synthetic.following(len(episodes), cycle, place)
    nxt = episodes[synthetic.cycle_order(len(episodes), CHANNEL.id, nxt_cycle)[nxt_place]]["id"]
    catalog, pl = fake_catalog({episodes[order[place]]["id"]: [source(0, "Solo [Castellano]")], nxt: [source(1, "Dual-Lat")]})
    tv = synthetic.SyntheticTV(catalog, [CHANNEL], clock=lambda: now)
    tv.play(CHANNEL.id)
    _, _, meta, options = pl.played[0]
    assert meta["video_id"] == nxt and options["start"] == 0.0
    assert (meta["cycle"], meta["place"]) == (nxt_cycle, nxt_place)


def test_sin_latino_en_ningun_lado_lo_dice_en_palabras(monkeypatch):
    monkeypatch.setattr(player, "find_mpv", lambda: "mpv.exe")
    catalog, _ = fake_catalog({})
    tv = synthetic.SyntheticTV(catalog, [CHANNEL], clock=lambda: synthetic.EPOCH + 10.0)
    try:
        tv.play(CHANNEL.id)
    except LookupError as exc:
        assert "español latino" in str(exc)
    else:
        raise AssertionError("debía decir que no hay latino")


def test_al_terminar_sigue_el_siguiente_de_la_vuelta_y_si_falla_otra_fuente():
    now = synthetic.EPOCH + 7_000.0
    episodes, cycle, place, offset, order = on_air_now(now)
    here = episodes[order[place]]["id"]
    nxt_cycle, nxt_place = synthetic.following(len(episodes), cycle, place)
    nxt = episodes[synthetic.cycle_order(len(episodes), CHANNEL.id, nxt_cycle)[nxt_place]]["id"]
    catalog, pl = fake_catalog({here: [source(0, "A-Dual-Lat"), source(1, "B Latino")], nxt: [source(5, "C-Dual-Lat")]})
    tv = synthetic.SyntheticTV(catalog, [CHANNEL], clock=lambda: now)
    meta = {"channel_id": CHANNEL.id, "cycle": cycle, "place": place, "tried": [0]}
    assert tv.failed(meta) is True  # la fuente falló: la otra del mismo episodio
    assert pl.loaded[-1][0] == "http://rd/1" and pl.loaded[-1][2]["tried"] == [0, 1]
    assert tv.failed({**meta, "tried": [0, 1]}) is True  # ya no hay otra: el siguiente episodio
    assert pl.loaded[-1][2]["video_id"] == nxt and pl.loaded[-1][2]["skips"] == 1
    assert tv.ended(meta) is True  # terminó: el siguiente, desde el principio
    assert pl.loaded[-1][2]["video_id"] == nxt and pl.loaded[-1][3]["start"] == 0
    assert tv.failed({**meta, "tried": [0, 1], "skips": synthetic.MAX_SKIPS - 1}) is False  # demasiados seguidos: se rinde


# --- en el reproductor: la tele de fondo no deja rastro --------------------------------------------------------------
def test_el_reproductor_no_guarda_nada_de_un_canal_y_al_terminar_pide_el_siguiente():
    from tests.test_player import make_player

    p, mpv = make_player()
    saved, scrobbled, ended = [], [], []
    p.on_progress = lambda *a: saved.append(a)
    p.on_finished = lambda *a: saved.append(a)
    p.on_scrobble = lambda *a: scrobbled.append(a)
    p.on_synthetic_end = lambda meta: ended.append(meta) or True
    segment = player.Segment({"synthetic": True, "kind": "channel", "detail": "T3 E1 · Uno"}, "Serie 24/7", "u")
    segment.duration, segment.position, segment.watched = 1300.0, 1299.0, 900.0
    p.segment = segment
    p._save_progress(segment)
    p._scrobble("start", segment)
    p._close_segment(player.Segment({**segment.meta}, "Serie 24/7", "u", duration=1300.0, watched=900.0))
    p._at_end(segment)
    p._at_end(segment)  # el final se ve cada segundo: se pide una sola vez
    for _ in range(50):
        if ended:
            break
        time.sleep(.02)
    assert saved == [] and scrobbled == [] and len(ended) == 1


def test_un_archivo_sin_la_pista_latina_pide_otra_fuente():
    from tests.test_player import make_player

    p, mpv = make_player(**{"track-list": [{"id": 1, "type": "audio", "lang": "spa", "title": "Castellano"}]})
    asked = []
    p.on_synthetic_failed = lambda meta: asked.append(meta) or True
    segment = player.Segment({"synthetic": True, "kind": "channel", "dub": "latino", "detail": "T3 E1"}, "Serie 24/7", "u")
    p.segment = segment
    p._started(segment)
    for _ in range(50):
        if asked:
            break
        time.sleep(.02)
    assert segment.failed and asked and asked[0]["detail"] == "T3 E1"

    p, mpv = make_player(**{"track-list": [{"id": 1, "type": "audio", "lang": "eng"},
                                           {"id": 2, "type": "audio", "lang": "spa", "title": "Latino"}]})
    segment = player.Segment({"synthetic": True, "kind": "channel", "dub": "latino", "detail": "T3 E1"}, "Serie 24/7", "u")
    p.segment = segment
    p._started(segment)
    assert ("set_property", "aid", 2) in mpv.sent and not segment.failed


# --- varias series y la memoria del doblaje --------------------------------------------------------------------------
def test_un_canal_de_varias_series_dice_cual_va_y_usa_el_logo_de_la_interfaz(monkeypatch):
    monkeypatch.setattr(player, "find_mpv", lambda: "mpv.exe")
    toons = synthetic.SyntheticChannel("orbital:toons", "Caricaturas", (synthetic.Show("tt7"), synthetic.Show("tt8")),
                                       slot=1000, logo="/img/channels/caricaturas.png", aliases=("caricaturas",))
    infos = {"tt7": info(range(1, 3), 2, "tt7", "Pinky y Cerebro"), "tt8": info(range(1, 2), 2, "tt8", "Batman")}
    found = {f"{m}:{s}:{e}": [source(0, f"{m} {s}x{e} Dual-Lat")] for m, ss in (("tt7", (1, 2)), ("tt8", (1,))) for s in ss for e in (1, 2)}
    catalog, pl = fake_catalog(found, infos)
    tv = synthetic.SyntheticTV(catalog, [toons], clock=lambda: synthetic.EPOCH + 3_500.0)
    assert len(tv.all_episodes(toons)) == 6  # las dos series juntas, sin especiales
    described = tv.describe(toons)
    assert described["logo"] == "/img/channels/caricaturas.png" and described["now"]["series"] in ("Pinky y Cerebro", "Batman")
    assert tv.remote_logo(toons.id) is None
    tv.play(toons.id)
    meta = pl.played[0][2]
    assert meta["detail"].startswith(meta["series"] + " · T") and meta["meta_id"] == meta["video_id"].split(":")[0]


def test_los_episodios_sin_latino_se_quedan_fuera_del_horario(tmp_path):
    catalog, _ = fake_catalog({"tt1:3:1": [source(0, "Dual-Lat")]})
    tv = synthetic.SyntheticTV(catalog, [CHANNEL], clock=lambda: synthetic.EPOCH + 10.0, directory=tmp_path)
    tv._stop = SimpleNamespace(wait=lambda seconds: False, is_set=lambda: False)  # sin esperar entre episodios
    assert tv.scan(limit=100) == 12  # revisó los doce
    assert tv.coverage.has("tt1:3:1") is True and tv.coverage.has("tt1:3:2") is False
    # Todos sin latino menos uno: el horario solo lo tiene a él (si fueran todos, todos: algo raro pasó).
    assert [e["id"] for e in tv._episodes(CHANNEL)] == ["tt1:3:1"]
    again = synthetic.SyntheticTV(catalog, [CHANNEL], directory=tmp_path)  # se guardó en disco
    assert again.coverage.has("tt1:3:2") is False and not again.coverage.stale("tt1:3:1", synthetic.EPOCH + 20)
    assert again.coverage.stale("tt1:3:2", synthetic.EPOCH + 10 + synthetic.RECHECK_MISSING + 1)  # a la semana, otra vez
