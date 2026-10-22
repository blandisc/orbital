"""Latino, castellano y subtítulos por voz (Alexa, Siri, el micrófono del iPhone): «pon Los Simpson en latino» pide el
doblaje (la versión y la pista que suena), «… con subtítulos en inglés» se aplica en todos los caminos (película, serie de
tu biblioteca, episodio, «T5 E3») y lo dicho es solo para esta vez; con «siempre» el título lo recuerda."""

import json
import time
from pathlib import Path
from types import SimpleNamespace

import pytest
from test_player import make_player

from orbital.library import streams
from orbital.library.models import LibraryItem
from orbital.voice import LANGUAGES, VOICE_WAIT, VoiceController, always_said, parse_text

ROOT = Path(__file__).resolve().parent.parent


@pytest.mark.parametrize("text, expected", [
    ("pon Los Simpson en latino", ("LaunchGameIntent", {"game": "los simpson", "language": "latino"})),
    ("pon Los Simpson en castellano", ("LaunchGameIntent", {"game": "los simpson", "language": "castellano"})),
    ("pon Dune en español latino", ("LaunchGameIntent", {"game": "dune", "language": "espanol latino"})),
    ("pon Dune en español", ("LaunchGameIntent", {"game": "dune", "language": "espanol"})),
    ("pon Los Simpson siempre en latino", ("LaunchGameIntent", {"game": "los simpson", "language": "latino", "always": "1"})),
    ("pon Los Simpson en latino siempre", ("LaunchGameIntent", {"game": "los simpson", "language": "latino", "always": "1"})),
    ("pon Dune con subtítulos en inglés", ("LaunchGameIntent", {"game": "dune", "subtitles": "ingles"})),
    ("pon Dune con subtítulos en inglés siempre",
     ("LaunchGameIntent", {"game": "dune", "subtitles": "ingles", "always": "1"})),
    ("pon Los Simpson T5 E3 con subtítulos en inglés",
     ("WatchEpisodeIntent", {"series": "los simpson", "season": "5", "episode": "3", "subtitles": "ingles"})),
    ("quiero ver Los Simpson temporada 5 episodio 3 en latino con subtítulos",
     ("WatchEpisodeIntent", {"series": "los simpson", "season": "5", "episode": "3", "language": "latino", "subtitles": "1"})),
    ("pon el episodio 3 de la temporada 5 de Los Simpson en castellano",
     ("WatchEpisodeIntent", {"episode": "3", "season": "5", "series": "los simpson", "language": "castellano"})),
    ("pon la temporada 2 de The Office con subtítulos",
     ("WatchEpisodeIntent", {"season": "2", "series": "the office", "subtitles": "1", "episode": "1"})),
    ("en latino", ("AudioLanguageIntent", {"language": "latino"})),
    ("pon el audio en latino", ("AudioLanguageIntent", {"language": "latino"})),
    ("ponlo siempre en latino", ("AudioLanguageIntent", {"language": "latino", "always": "1"})),
    ("pon el audio en castellano siempre", ("AudioLanguageIntent", {"language": "castellano", "always": "1"})),
    ("pon subtítulos en inglés siempre", ("SubtitlesIntent", {"language": "ingles", "always": "1"})),
    ("pon siempre subtítulos en inglés", ("SubtitlesIntent", {"language": "ingles", "always": "1"})),
    ("pon lo de siempre", ("LaunchGameIntent", {"game": "lo de siempre"})),  # «lo de siempre» no es «siempre»
])
def test_frases(text, expected):
    assert parse_text(text) == expected


def test_los_idiomas_dichos_y_los_de_alexa():
    assert LANGUAGES["latino"] == LANGUAGES["es 419"] == LANGUAGES["espanol latino"] == "es-419"
    assert LANGUAGES["castellano"] == LANGUAGES["es es"] == LANGUAGES["espanol de espana"] == "es-ES"
    assert LANGUAGES["espanol"] == "es"  # «en español»: cualquiera de los dos
    assert always_said("pon lo de siempre en latino") == ("pon lo de siempre en latino", False)


def test_alexa_trae_latino_y_castellano_como_valores_propios():
    model = json.loads((ROOT / "alexa" / "interaction_model.es-MX.json").read_text(encoding="utf-8"))
    language = next(t for t in model["interactionModel"]["languageModel"]["types"] if t["name"] == "LANGUAGE")
    values = {v["name"]["value"]: v["name"].get("synonyms", []) for v in language["values"]}
    assert "latino" in values["es-419"] and "castellano" in values["es-ES"]
    assert "latino" not in values["es"] and "castellano" not in values["es"]
    for value in values:  # lo que manda Alexa (el valor ya resuelto) lo entiende la consola
        assert LANGUAGES.get(value.lower().replace("-", " ")), value


# --- la voz → play_title ------------------------------------------------------------------------
@pytest.fixture
def played(library, monkeypatch):
    calls = []
    monkeypatch.setattr(library.watch, "play_title", lambda *args, **kw: calls.append((args, kw)))
    library.cinemeta.search = lambda kind, q: [{"id": "tt1160419", "name": "Dune"}] if kind == "movie" else []
    return calls


def test_pon_dune_en_latino_pide_el_doblaje_solo_esta_vez(library, played):
    voice = VoiceController(library)
    assert voice.handle_text("pon Dune en latino").speech == "Poniendo Dune en latino."
    assert played[-1][1] == {"wait": VOICE_WAIT, "from_start": False, "audio": "es", "spanish": "es-419"}
    assert voice.handle_text("pon Dune en español").speech == "Poniendo Dune en español."
    assert played[-1][1] == {"wait": VOICE_WAIT, "from_start": False, "audio": "es"}  # cualquiera


def test_con_siempre_lo_recuerda_y_lo_dice(library, played):
    voice = VoiceController(library)
    said = voice.handle_text("pon Dune siempre en castellano con subtítulos en inglés").speech
    assert said == "Poniendo Dune en castellano con subtítulos en inglés. Dune quedará en castellano con subtítulos en inglés."
    assert played[-1][1] == {"wait": VOICE_WAIT, "from_start": False, "audio": "es", "spanish": "es-ES",
                             "subtitles": "en", "remember": True}


def test_alexa_manda_todo_en_el_slot_del_titulo(library, played):
    """Alexa: «pon {game}» con game «Dune siempre en latino»: se separa en la consola (antes buscaba ese título)."""
    voice = VoiceController(library)
    assert voice.handle_intent("LaunchGameIntent", {"game": "Dune siempre en latino"}).ok
    assert played[-1][1] == {"wait": VOICE_WAIT, "from_start": False, "audio": "es", "spanish": "es-419", "remember": True}
    assert voice.handle_intent("SearchMediaIntent", {"query": "Dune con subtítulos"}).ok
    assert played[-1][1]["subtitles"] == (library.watch.subtitles_lang or "es")
    assert voice.handle_intent("AudioLanguageIntent", {"language": "es-419", "always": "siempre"}).ok is False  # nada puesto


def test_lo_de_tu_biblioteca_tambien_aplica_idioma_y_subtitulos(library, monkeypatch):
    item = LibraryItem(id="stremio:tt0096697", title="Los Simpson", category="media", source="stremio",
                       extra={"kind": "series", "meta_id": "tt0096697", "video_id": "tt0096697:8:23"})
    monkeypatch.setattr(library, "find", lambda name, source=None, exclude_source=None: item if source == "stremio" else None)
    calls = []
    monkeypatch.setattr(library.watch, "play_title", lambda *args, **kw: calls.append((args, kw)))
    voice = VoiceController(library)
    assert voice.handle_text("quiero ver Los Simpson en latino con subtítulos en inglés").speech \
        == "Poniendo Los Simpson en latino con subtítulos en inglés."
    assert calls == [(("series", "tt0096697", "tt0096697:8:23", "Los Simpson"),
                      {"wait": VOICE_WAIT, "audio": "es", "spanish": "es-419", "subtitles": "en"})]


def test_un_episodio_con_subtitulos_y_doblaje(library, monkeypatch):
    from orbital.library import cinemeta

    monkeypatch.setattr(cinemeta.Cinemeta, "search", lambda self, kind, q: [{"id": "tt0096697", "name": "The Simpsons"}])
    monkeypatch.setattr(cinemeta.Cinemeta, "meta", lambda self, kind, mid: {
        "name": "The Simpsons", "videos": [{"id": "tt0096697:5:3", "season": 5, "episode": 3}]})
    calls = []
    monkeypatch.setattr(library.watch, "play_title", lambda *args, **kw: calls.append(kw))
    voice = VoiceController(library)
    assert voice.handle_text("pon los simpson T5 E3 con subtítulos en inglés").speech \
        == "Poniendo The Simpsons, temporada 5, episodio 3 con subtítulos en inglés."
    assert calls[-1] == {"wait": VOICE_WAIT - 2, "subtitles": "en"}
    said = voice.handle_text("pon los simpson temporada 5 episodio 3 siempre en latino").speech
    assert said == "Poniendo The Simpsons, temporada 5, episodio 3 en latino. The Simpsons quedará en latino."
    assert calls[-1] == {"wait": VOICE_WAIT - 2, "audio": "es", "spanish": "es-419", "remember": True}


def test_una_serie_que_no_tienes_con_siempre_ya_lo_recuerda(library, monkeypatch):
    library.cinemeta.search = lambda kind, q: [{"id": "tt0096697", "name": "Los Simpson"}] if kind == "series" else []
    voice = VoiceController(library)
    said = voice.handle_text("pon Los Simpson siempre en latino").speech
    assert said == "Abriendo Los Simpson. Elige el episodio. Los Simpson quedará en latino."
    prefs, _ = library.watch.language_for("tt0096697")
    assert (prefs.audio, prefs.spanish) == ("es", "es-419")


# --- play_title: solo esta vez o siempre --------------------------------------------------------
def _play(library, monkeypatch, **kw):
    w = library.watch
    monkeypatch.setattr(type(w), "native_player", property(lambda self: True))
    latino = streams.parse({"name": "[RD+] Torrentio\n1080p", "title": "Los.Simpson.S08E23.1080p.Latino",
                            "url": "https://cdn/0.mkv"}, "Torrentio", "https://t/manifest.json", 0)
    asked_prefs, sent = [], []
    monkeypatch.setattr(w, "best_source", lambda kind, video_id, binge=None, skip=None, prefs=None: asked_prefs.append(prefs) or latino)
    monkeypatch.setattr(w, "play_source", lambda *args, **kwargs: sent.append(kwargs))
    assert w.play_title("series", "tt0096697", "tt0096697:8:23", "Los Simpson", wait=2, **kw) is None
    for _ in range(100):
        if sent:
            break
        time.sleep(.02)
    time.sleep(.05)  # lo que se recuerda va después de poner
    return asked_prefs[0], sent[0]


def test_lo_dicho_es_solo_para_esta_vez(library, monkeypatch):
    library.watch.state.set_setting("audio", "en")
    prefs, sent = _play(library, monkeypatch, audio="es", spanish="es-419", subtitles="en")
    assert (prefs.audio, prefs.spanish) == ("es", "es-419")  # la versión se elige latina
    assert sent["asked"] == {"audio": "es", "spanish": "es-419", "subtitles": "en"} and sent["subtitles"] == "en"
    assert library.watch.state.prefs("stremio:tt0096697") == {}  # el título no lo recuerda
    assert library.watch.language_for("tt0096697")[0].audio == "en"


def test_el_codigo_es_419_tambien_sirve(library, monkeypatch):
    prefs, sent = _play(library, monkeypatch, audio="es-419")
    assert (prefs.audio, prefs.spanish) == ("es", "es-419") and sent["asked"]["spanish"] == "es-419"


def test_siempre_lo_recuerda_el_titulo(library, monkeypatch):
    library.watch.state.set_setting("audio", "en")
    _play(library, monkeypatch, audio="es", spanish="es-ES", subtitles="en", remember=True)
    prefs, subtitles = library.watch.language_for("tt0096697")
    assert (prefs.audio, prefs.spanish, subtitles) == ("es", "es-ES", "en")


def test_lo_de_esta_vez_lo_siguen_el_respaldo_y_la_pista(library):
    w = library.watch
    w.state.set_setting("audio", "en")
    meta = {"meta_id": "tt0096697", "asked": {"audio": "es", "spanish": "es-419", "subtitles": ""}}
    prefs, subtitles = w.asked_language(meta)
    assert (prefs.audio, prefs.spanish, subtitles) == ("es", "es-419", "")
    assert w._spanish_for(meta) == "es-419"
    assert w._spanish_for({"meta_id": "tt0096697"}) == ""  # otro video: lo de siempre
    assert w.asked_language({"meta_id": "tt0096697"})[0].audio == "en"


# --- en el reproductor: «pon el audio en latino», «… siempre» ----------------------------------
TWO_SPANISH = [{"id": 1, "type": "audio", "lang": "spa", "title": "Castellano", "selected": True},
               {"id": 2, "type": "audio", "lang": "spa", "title": "Latino"},
               {"id": 3, "type": "audio", "lang": "eng"}]


def test_el_reproductor_elige_la_pista_latina_y_no_la_primera_spa():
    p, mpv = make_player(**{"track-list": TWO_SPANISH})
    p.segment = SimpleNamespace(meta={"meta_id": "tt1"})
    assert p.select_language("audio", "es", "es-419")
    assert ("set_property", "aid", 2) in mpv.sent
    assert p.segment.meta["asked"] == {"audio": "es", "spanish": "es-419"}  # si cambia de versión, sigue en latino
    only_castellano = [t for t in TWO_SPANISH if t["id"] != 2]
    p2, _ = make_player(**{"track-list": only_castellano})
    assert not p2.select_language("audio", "es", "es-419")  # solo trae la castellana: se dice que no
    assert p2.select_language("audio", "es")  # «en español»: cualquiera


class PlayingPlayer:
    playing = True

    def __init__(self):
        self.calls = []
        self.current = SimpleNamespace(title="Los Simpson · T8 E23", meta={"meta_id": "tt0096697", "title": "Los Simpson · T8 E23"})

    def select_language(self, kind, lang, variant=""):
        self.calls.append((kind, lang, variant))
        return True

    def toast(self, text, seconds=1.6):
        self.calls.append(("toast", text))


def test_pon_el_audio_en_latino_es_solo_esta_vez(library):
    library.player = PlayingPlayer()
    voice = VoiceController(library)
    assert voice.handle_text("pon el audio en latino").speech == "Audio en latino."
    assert library.player.calls == [("audio", "es", "es-419")]
    assert library.watch.state.prefs("stremio:tt0096697") == {}


def test_ponlo_siempre_en_latino_lo_guarda_y_lo_avisa(library):
    library.player = PlayingPlayer()
    voice = VoiceController(library)
    assert voice.handle_text("ponlo siempre en latino").speech == "Audio en latino. Los Simpson quedará en latino."
    assert ("toast", "Los Simpson quedará en latino") in library.player.calls
    prefs, _ = library.watch.language_for("tt0096697")
    assert (prefs.audio, prefs.spanish) == ("es", "es-419")


def test_subtitulos_en_ingles_siempre(library, monkeypatch):
    library.player = PlayingPlayer()
    monkeypatch.setattr(library.watch, "player_subtitles", lambda lang: True)
    voice = VoiceController(library)
    assert voice.handle_text("pon subtítulos en inglés siempre").speech \
        == "Subtítulos en inglés. Los Simpson quedará con subtítulos en inglés."
    assert library.watch.language_for("tt0096697")[1] == "en"
    assert voice.handle_text("pon subtítulos en latino").speech == "Subtítulos en español."  # los subtítulos no tienen doblaje


def test_la_skill_de_alexa_manda_el_doblaje_resuelto(monkeypatch):
    """lambda_function solo pasa el intent: «latino» llega como su valor («es-419») y «siempre» como su slot."""
    import importlib.util
    import io

    monkeypatch.setenv("ORBITAL_URL", "https://x")
    monkeypatch.setenv("ORBITAL_TOKEN", "t")
    monkeypatch.delenv("ALEXA_SKILL_ID", raising=False)
    spec = importlib.util.spec_from_file_location("hosted_skill_latino", ROOT / "alexa" / "lambda_function.py")
    skill = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(skill)
    sent = []
    monkeypatch.setattr(skill.urllib.request, "urlopen",
                        lambda req, timeout: sent.append(json.loads(req.data)) or io.BytesIO(b'{"ok": true, "speech": "Listo."}'))

    def resolved(said, value):
        return {"value": said, "resolutions": {"resolutionsPerAuthority": [
            {"status": {"code": "ER_SUCCESS_MATCH"}, "values": [{"value": {"name": value}}]}]}}

    slots = {"language": resolved("latino", "es-419"), "always": resolved("siempre", "siempre")}
    skill.lambda_handler({"request": {"type": "IntentRequest", "intent": {"name": "AudioLanguageIntent", "slots": slots}}})
    assert sent == [{"intent": "AudioLanguageIntent", "slots": {"language": "es-419", "always": "siempre"}}]


def test_alexa_con_el_valor_resuelto_y_siempre(library):
    library.player = PlayingPlayer()
    voice = VoiceController(library)
    said = voice.handle_intent("AudioLanguageIntent", {"language": "es-419", "always": "siempre"}).speech
    assert said == "Audio en latino. Los Simpson quedará en latino."
    assert library.player.calls[0] == ("audio", "es", "es-419")
