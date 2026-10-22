"""El idioma de las fuentes, con lo que de verdad manda Torrentio con Real-Debrid (405 fuentes de 6 títulos, 2026-10-20).

Cada regla de streams.audio_languages tiene aquí el caso real que la pidió.
"""

import json
from pathlib import Path

import pytest

from orbital.library import streams
from orbital.library.streams import Preferences, rank

FIXTURE = Path(__file__).parent / "fixtures" / "streams" / "torrentio_rd_2026-10-20.json"
TITLES = {t["label"]: t for t in json.loads(FIXTURE.read_text("utf-8"))["titles"]}


def sources(label: str) -> list[streams.Source]:
    title = TITLES[label]
    out = []
    for i, stream in enumerate(title["streams"]):
        src = streams.parse(stream, "Torrentio RD", "https://torrentio.strem.fun/manifest.json", i, title["original"])
        src.other_title = not streams.mentions_title(title["titles"], f"{src.release} {(stream.get('behaviorHints') or {}).get('filename') or ''}")
        out.append(src)
    return out


def find(label: str, text: str) -> streams.Source:
    return next(s for s in sources(label) if text in s.release)


def test_las_banderas_de_subtitulos_no_son_idiomas_de_audio():
    pahe = find("Dune: Parte dos", "Pahe")  # 23 banderas
    assert pahe.audio_langs == {"en": "original"} and pahe.languages == ["en"]
    sure = [[c for c, how in s.audio_langs.items() if how != "maybe"] for t in TITLES for s in sources(t)]
    assert max(map(len, sure)) <= 6  # las de muchas banderas con doblaje quedan en «tal vez», no como seguras


def test_un_nombre_que_lista_subtitulos_no_habla_del_audio():
    erai = find("Frieren T1E1 (anime)", "[Erai-raws] Sousou no Frieren - 01 [1080p][Multiple Subtitle]")
    assert "es-419" not in erai.audio_langs and erai.audio_langs == {"ja": "original"}  # «[SPA-LA]» son subtítulos


def test_latino_y_castellano_cuando_lo_dicen():
    lat = find("Dune: Parte dos", "Dune.part.two.2024.2160p.x265.hdr.5.1-dual-lat-cinecalidad")
    assert lat.audio_langs == {"es-419": "name", "en": "name"} and lat.dub == "latino"
    cast = find("Dune: Parte dos", "Dune Parte Dos (2024) [Bluray 1080p][Esp]")
    assert cast.audio_langs.get("es-ES") == "site" and cast.dub == "castellano"  # MejorTorrent solo sube castellano
    coco = find("Coco", "Coco [BluRay 1080p][AC3 5.1 Castellano")
    assert coco.audio_langs["es-ES"] == "name" and "en" in coco.audio_langs  # «Castellano DTS 5.1-Ingles»


def test_la_bandera_de_espana_sola_no_dice_cual_espanol():
    yg = find("Dune: Parte dos", "Dual.YG")  # «Dual Audio / 🇪🇸»
    assert "es" in yg.audio_langs and "es-ES" not in yg.audio_langs and yg.dub == ""


def test_el_original_cuando_nada_lo_dice():
    qman = find("La casa de papel T1E1", "Qman")  # serie española, solo 🇪🇸: su castellano original
    assert qman.audio_langs.get("es-ES") in ("original", "maybe") and "en" not in qman.audio_langs
    english = find("La casa de papel T1E1", "Complete Season 1 English HD 720p")
    assert english.audio_langs == {"en": "name"}  # el doblaje en inglés: lo que dice el nombre gana al original


def test_dual_en_anime_es_japones_mas_ingles():
    pmr = find("Frieren T1E1 (anime)", "[PMR]")
    assert pmr.audio_langs == {"ja": "name"} or set(pmr.audio_langs) == {"ja", "en"}
    rapta = find("Frieren T1E1 (anime)", "x265-Rapta")  # Crunchyroll multi-audio: el latino, tal vez
    assert rapta.audio_langs.get("es-419") == "maybe" and rapta.audio_langs.get("ja") == "name"


def test_otro_titulo_baja_sin_esconderse():
    found = sources("La casa de papel T1E1")
    pradera = [s for s in found if "pradera" in s.release.lower()]
    assert len(pradera) == 3 and all(s.other_title for s in pradera)
    assert not any(s.other_title for s in found if "Money Heist" in s.release or "Бумажный" in s.release)
    best = rank(found, Preferences(audio="es", dub="castellano", quality="1080p"), "series")
    assert "pradera" not in best[0].release.lower() and len(best) == len(found)  # abajo, pero sigue en la lista


def test_el_grupo_x264_pl_no_es_polaco():
    pl = find("Los Simpson T5E3", "H 264-pl")
    assert "pl" not in pl.languages


def test_preferir_latino_pone_primero_lo_latino():
    best = rank(sources("Dune: Parte dos"), Preferences(audio="es", dub="latino", quality="4K"), "movie")
    assert best[0].audio_langs.get("es-419") == "name" and best[0].cached
    castellano = rank(sources("Dune: Parte dos"), Preferences(audio="es", dub="castellano", quality="1080p"), "movie")
    assert "es-ES" in castellano[0].audio_langs


def test_ingles_primero_para_quien_lo_prefiere():
    best = rank(sources("Anora"), Preferences(audio="en", quality="1080p"), "movie")
    assert "en" in best[0].languages and best[0].cached and best[0].resolution == "1080p"


@pytest.mark.parametrize("tracks, langs", [
    ([{"type": "audio", "lang": "eng"}, {"type": "audio", "lang": "spa", "title": "Latino"}], ["en", "es-419"]),
    ([{"type": "audio", "lang": "spa", "title": "Castellano"}], ["es-ES"]),
    ([{"type": "audio", "lang": "spa"}], ["es"]),
    ([{"type": "audio", "lang": "es-419"}], ["es-419"]),
    ([{"type": "audio", "lang": "jpn"}, {"type": "sub", "lang": "spa"}], ["ja"]),
    ([{"type": "audio"}, {"type": "audio", "lang": "eng"}], []),  # una pista sin idioma: no se sabe qué trae
])
def test_lo_que_mpv_ve_al_reproducir(tracks, langs):
    assert streams.track_languages(tracks) == langs


def test_lo_comprobado_reemplaza_al_nombre():
    yg = find("Dune: Parte dos", "Dual.YG")
    assert streams.heard(yg, [{"type": "audio", "lang": "eng"}, {"type": "audio", "lang": "spa", "title": "Castellano"}])
    assert yg.audio_langs == {"en": "seen", "es-ES": "seen"} and yg.dub == "castellano"
    assert not streams.heard(yg, [{"type": "audio"}])  # sin idioma no se aprende nada (y no se borra lo de antes)
    assert yg.audio_langs == {"en": "seen", "es-ES": "seen"}


def _fake_watch(found, prefs, tmp_path):
    from types import SimpleNamespace

    from orbital import watch

    finder = SimpleNamespace(cached=lambda kind, video, p: found)
    fake = SimpleNamespace(language_for=lambda meta_id: (prefs, ""), streams=finder,
                           heard=watch.HeardTracks(tmp_path / "pistas.json"))
    fake._other_versions = lambda meta: watch.Watch._other_versions(fake, meta)
    fake._wanted_codes = watch.Watch._wanted_codes
    return fake, watch


def test_x_audio_ofrece_tu_idioma_en_otra_version(tmp_path):
    found = rank(sources("Dune: Parte dos"), Preferences(audio="en", quality="4K"), "movie")
    fake, watch = _fake_watch(found, Preferences(audio="es", dub="latino", quality="4K"), tmp_path)
    english = next(s for s in found if s.audio_langs == {"en": "original"})
    rows = watch.Watch._other_versions(fake, {"source": english.index, "kind": "movie", "video_id": "tt15239678",
                                               "meta_id": "tt15239678"})
    assert rows[0]["label"] == "Latino" and rows[0]["hint"] in ("En otra · 4K", "En otra · 1080p")
    from orbital import player_ui  # cabe en la columna Audio sin cortarse (cuatro columnas: 384 px)
    room = 384 - 70 - (player_ui.text_width(rows[0]["hint"], 20) + 20)
    assert room >= (384 - 70) * .45 and player_ui.text_width("Castellano", 24, "semi") <= room
    assert "en" not in {r["code"] for r in rows} and len(rows) <= 4  # lo que ya trae esta no se repite


def test_al_empezar_dice_si_no_trae_tu_idioma_y_lo_recuerda(tmp_path):
    found = rank(sources("Dune: Parte dos"), Preferences(audio="es", dub="latino", quality="4K"), "movie")
    fake, watch = _fake_watch(found, Preferences(audio="es", dub="latino", quality="4K"), tmp_path)
    spa = next(s for s in found if "Eng 7.1-Fre 5.1-Spa" in s.release)  # «Spa»: no dice cuál
    meta = {"source": spa.index, "source_key": spa.key, "kind": "movie", "video_id": "tt15239678", "meta_id": "tt15239678"}
    tracks = [{"type": "audio", "lang": "eng"}, {"type": "audio", "lang": "fre"},
              {"type": "audio", "lang": "spa", "title": "Castellano"}]
    note = watch.Watch._tracks_seen(fake, meta, tracks)
    assert note == ("Esta versión no trae latino: sus pistas son inglés, francés y castellano"
                    " · X › Audio: hay latino en otra versión")
    assert spa.audio_langs == {"en": "seen", "fr": "seen", "es-ES": "seen"}  # la lista ya buscada también lo sabe
    assert fake.heard.get(spa.key) and watch.HeardTracks(tmp_path / "pistas.json").get(spa.key)  # y queda guardado
    assert watch.Watch._tracks_seen(fake, meta, [{"type": "audio", "lang": "spa", "title": "Latino"}]) is None
    assert watch.Watch._tracks_seen(fake, meta, [{"type": "audio"}]) is None  # sin idioma: no se sabe, no se avisa


def test_tmdb_dice_el_idioma_original_con_su_pais(monkeypatch):
    from orbital.library import tmdb

    answers = {"/find/tt6468322": {"tv_results": [{"id": 71446, "name": "La casa de papel", "original_name": "La casa de papel",
                                                   "original_language": "es", "origin_country": ["ES"]}]},
               "/find/tt7984734": {"movie_results": [{"id": 426426, "title": "Roma", "original_title": "Roma",
                                                      "original_language": "es"}]},
               "/movie/426426": {"origin_country": ["MX"]},
               "/find/tt22248376": {"tv_results": [{"id": 209867, "name": "Frieren", "original_name": "葬送のフリーレン",
                                                    "original_language": "ja", "origin_country": ["JP"]}]}}
    client = tmdb.Tmdb("clave")
    monkeypatch.setattr(client, "_get", lambda path, **params: answers[path])
    assert client.original("tt6468322", "series") == {"original": "es-ES", "titles": ["La casa de papel"]}
    assert client.original("tt7984734", "movie")["original"] == "es-419"  # Roma: mexicana
    assert client.original("tt22248376", "series") == {"original": "ja", "titles": ["Frieren", "葬送のフリーレン"]}


# --- Lo que encontró el agente que intentó romperlo (2026-10-21) -------------------------------------------------

def langs_of(name: str, marks: str = "", site: str = "", original: str | None = "en") -> dict:
    return streams.audio_languages(name, marks, site, original)


@pytest.mark.parametrize("name, marks, site, original, expected", [
    # «Spanish» + «Latino» en una serie española: es latino, no su castellano original.
    ("Elite.S01E01.SPANISH.LATINO.1080p", "", "", "es-ES", {"es-419": "name"}),
    ("Elite.S01E01.Spanish.1080p", "", "Cinecalidad", "es-ES", {"es-419": "site"}),
    # «Sub» suelto es una palabra del título.
    ("Mortal.Kombat.Sub-Zero.2024.1080p.Latino", "", "", "en", {"es-419": "name"}),
    ("The.Sub.2023.1080p.Castellano", "", "", "en", {"es-ES": "name"}),
    # Subtítulos en español no son audio en español.
    ("Movie.2020.1080p.Subtitulado.Español", "", "", "en", {"en": "original"}),
    ("Movie 2020 1080p [Spa Subs]", "", "", "en", {"en": "original"}),
    # Un sitio polaco con «[Napisy PL]» o «PLSUB»: inglés con subtítulos polacos.
    ("Dune Part Two (2024) [1080p] [Napisy PL]", "", "BestTorrents", "en", {"en": "original"}),
    ("Dune.Part.Two.2024.1080p.PLSUB.WEB-DL", "", "BestTorrents", "en", {"en": "original"}),
    ("Dune Part Two (2024) Lektor PL", "", "BestTorrents", "en", {"pl": "name"}),
    # «FR» suelto; «Lat» con mayúscula inicial no; «MVO» en mayúsculas sí; «Latin American».
    ("Les Simpsons - Toutes les Saisons FR", "", "", "en", {"fr": "name"}),
    ("Lat.Den.2020.1080p", "", "", "en", {"en": "original"}),
    ("Movie.2020.WEB-DL.MVO", "", "", "en", {"ru": "name"}),
    ("Movie 2020 Spanish Latin American 1080p", "", "", "en", {"es-419": "name"}),
])
def test_casos_que_rompio_el_agente(name, marks, site, original, expected):
    found = langs_of(name, marks, site, original)
    assert {c: h for c, h in found.items() if h != "maybe"} == expected


def test_dual_en_anime_suma_el_ingles():
    for text in ("[wham]", "[PMR]", "[Salieri]", "LostYears", "Hulu"):
        src = find("Frieren T1E1 (anime)", text)
        assert {"ja", "en"} <= set(src.audio_langs), text
    assert rank(sources("Frieren T1E1 (anime)"), Preferences(audio="en"), "series")[0].audio_langs.get("en") == "name"


def test_titulos_cortos_no_marcan_todo_como_otro_titulo():
    assert streams.mentions_title(["Up"], "Up.2009.1080p.BluRay")
    assert streams.mentions_title(["It", "Eso"], "It 2017 2160p")
    assert not streams.mentions_title(["La casa de papel", "Money Heist"], "La Casa De La Pradera (2026)")


@pytest.mark.parametrize("tracks, langs", [
    ([{"type": "audio", "lang": "es-MX"}], ["es-419"]),
    ([{"type": "audio", "lang": "es-ES"}], ["es-ES"]),
    ([{"type": "audio", "lang": "spa", "title": "Platino"}], ["es"]),  # «Platino» no es latino
    ([{"type": "audio", "lang": "cat"}, {"type": "audio", "lang": "eng"}], ["ca", "en"]),  # un código raro no borra todo
    ([{"type": "audio", "lang": "esl"}], ["es"]),
])
def test_pistas_raras(tracks, langs):
    assert streams.track_languages(tracks) == langs


def test_una_en_otro_idioma_al_instante_no_le_gana_a_la_tuya_que_tarda():
    ru = streams.parse({"name": "[RD+] Torrentio\n1080p", "title": "Дюна 2024 1080p\n👤 9 💾 3 GB ⚙️ Rutor"}, "T", "t", 0, "en")
    en = streams.parse({"name": "[RD download] Torrentio\n1080p", "title": "Dune 2024 1080p\n👤 9 💾 3 GB"}, "T", "t", 1, "en")
    assert rank([ru, en], Preferences(audio="en"), "movie")[0] is en


def test_cualquiera_en_espanol_no_avisa_ni_esconde(tmp_path):
    found = rank(sources("Dune: Parte dos"), Preferences(audio="es", quality="4K"), "movie")
    fake, watch = _fake_watch(found, Preferences(audio="es", dub="", quality="4K"), tmp_path)
    english = next(s for s in found if s.audio_langs == {"en": "original"})
    meta = {"source": english.index, "source_key": english.key, "kind": "movie", "video_id": "tt15239678",
            "meta_id": "tt15239678"}
    rows = watch.Watch._other_versions(fake, meta)
    assert {rows[0]["code"], rows[1]["code"]} == {"es-419", "es-ES"}  # los dos españoles primero
    note = watch.Watch._tracks_seen(fake, meta, [{"type": "audio", "lang": "eng"}])
    assert note == "Esta versión no trae español: sus pistas son inglés · X › Audio: hay español en otra versión"
    assert watch.Watch._tracks_seen(fake, meta, [{"type": "audio", "lang": "spa", "title": "Castellano"}]) is None


def test_el_aviso_dice_cuantas_pistas_mas(tmp_path):
    found = rank(sources("Dune: Parte dos"), Preferences(audio="es", dub="latino"), "movie")
    fake, watch = _fake_watch(found, Preferences(audio="es", dub="latino"), tmp_path)
    src = found[-1]
    meta = {"source": src.index, "source_key": src.key, "kind": "movie", "video_id": "tt15239678", "meta_id": "tt15239678"}
    tracks = [{"type": "audio", "lang": code} for code in ("eng", "fre", "ger", "ita", "jpn")]
    assert "inglés, francés, alemán y 2 más" in watch.Watch._tracks_seen(fake, meta, tracks)
    assert watch.Watch._other_versions(fake, {"source": 1, "kind": "movie", "video_id": "x"}) == []  # sin meta_id


def test_la_lista_sirve_aunque_cambie_la_preferencia(monkeypatch):
    finder = streams.StreamFinder.__new__(streams.StreamFinder)
    finder._cache, finder._lock = {}, __import__("threading").Lock()
    found = sources("Dune: Parte dos")
    import time as _time
    finder._cache["movie:tt1:es:4K:castellano"] = (_time.time(), found)
    assert finder.get("movie", "tt1", Preferences(audio="es", quality="4K", dub="latino"), found[3].index) is found[3]
    assert finder.cached("movie", "tt1", Preferences(audio="es", dub="latino"))[0].audio_langs.get("es-419")


def test_heard_tracks_con_bom(tmp_path):
    from orbital import watch

    path = tmp_path / "pistas.json"
    path.write_text('﻿{"k": {"audio": [{"type": "audio", "lang": "eng"}]}}', encoding="utf-8")
    assert watch.HeardTracks(path).get("k") == [{"type": "audio", "lang": "eng"}]
