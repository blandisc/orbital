"""El ciclo completo por voz (docs/voz.md): una frase prende la tele, la pone en la entrada de Orbital y arranca la serie;
«otro», «apaga la tele», «siguiente» según lo que ves y la frase más parecida cuando no hay nada con ese nombre."""

from __future__ import annotations

from types import SimpleNamespace

import pytest

from orbital.library import cinemeta
from orbital.voice import VOICE_WAIT, VoiceController, parse_text


class FakeTv:
    enabled = True

    def __init__(self):
        self.calls = []

    def turn_on_soon(self):
        self.calls.append("on")

    def turn_off_soon(self):
        self.calls.append("off")


class FakePlayer:
    def __init__(self, playing=False, title="The Office · T4 E3"):
        self.playing = playing
        self.current = SimpleNamespace(title=title)
        self.stopped = False

    def stop(self):
        self.stopped = True
        self.playing = False


@pytest.fixture
def office(monkeypatch):
    """Cinemeta con The Office (serie) y dos «Dune» (película), sin red."""
    def search(self, kind, query):
        q = query.lower()
        if kind == "series" and "office" in q:
            return [{"id": "tt0386676", "name": "The Office"}]
        if kind == "movie" and "dune" in q:
            return [{"id": "tt1160419", "name": "Dune"}, {"id": "tt0087182", "name": "Dune"}]
        return []

    def meta(self, kind, meta_id):
        return {"name": "The Office", "videos": [
            {"id": "tt0386676:0:1", "season": 0, "episode": 1, "released": "2005-01-01"},  # especial: no cuenta
            {"id": "tt0386676:2:1", "season": 2, "episode": 1, "released": "2005-09-20"},
            {"id": "tt0386676:1:1", "season": 1, "episode": 1, "released": "2005-03-24"},
            {"id": "tt0386676:9:9", "season": 9, "episode": 9, "released": "2999-01-01"}]}

    monkeypatch.setattr(cinemeta.Cinemeta, "search", search)
    monkeypatch.setattr(cinemeta.Cinemeta, "meta", meta)


@pytest.fixture
def played(library, monkeypatch):
    calls = []
    monkeypatch.setattr(library.watch, "play_title", lambda *args, **kw: calls.append((args, kw)))
    return calls


# --- prender antes de poner ------------------------------------------------------------------------------------------
@pytest.mark.parametrize("said", ["pon The Office", "quiero ver Dune", "sigue viendo", "pon el canal ADN 40", "abre Hades",
                                  "pon algo de terror", "otro"])
def test_poner_algo_prende_la_tele(library, office, played, said):
    tv = FakeTv()
    VoiceController(library, tv=tv).handle_text(said)
    assert tv.calls == ["on"], said


@pytest.mark.parametrize("said", ["pausa", "sube el volumen", "qué estoy viendo", "cuánto falta", "silencio"])
def test_lo_que_no_pone_nada_no_toca_la_tele(library, said):
    tv = FakeTv()
    VoiceController(library, tv=tv).handle_text(said)
    assert tv.calls == [], said


def test_sigue_sin_nada_abierto_prende_la_tele_y_con_un_video_no(library):
    tv = FakeTv()
    library.player = FakePlayer(playing=False)
    VoiceController(library, tv=tv).handle_intent("ResumeIntent")
    library.player = FakePlayer(playing=True)
    VoiceController(library, tv=tv).handle_intent("ResumeIntent")
    assert tv.calls == ["on"]


def test_prende_la_tele_prende_la_tele():
    """«Prende la tele» prende la tele (antes abría la TV en vivo); «pon la tele en vivo» y «pon los canales», los canales."""
    assert parse_text("prende la tele") == ("OpenOrbitalIntent", {})
    assert parse_text("enciende la pantalla") == ("OpenOrbitalIntent", {})
    assert parse_text("pídele a mi consola que prenda la tele")[0] == "OpenOrbitalIntent"
    assert parse_text("pon la tele en vivo") == ("LiveTvIntent", {})
    assert parse_text("pon los canales") == ("LiveTvIntent", {})
    assert parse_text("pon la tele") == ("LiveTvIntent", {})  # como antes: los canales


def test_prende_la_tele_lo_dice(library):
    kiosk = SimpleNamespace(open=lambda: None)
    tv = FakeTv()
    assert VoiceController(library, kiosk=kiosk, tv=tv).handle_text("prende la tele").speech == "Prendiendo la tele en Orbital."
    assert tv.calls == ["on"]
    assert VoiceController(library, kiosk=kiosk).handle_text("prende la tele").speech == "Abriendo la consola."


# --- una serie se pone --------------------------------------------------------------------------------------------------
def test_una_serie_nueva_arranca_en_su_primer_episodio(library, office, played):
    result = VoiceController(library).handle_text("pon The Office")
    assert result.ok and result.speech == "Poniendo The Office, temporada 1, episodio 1."
    assert played == [(("series", "tt0386676", "tt0386676:1:1", "The Office · T1 E1"), {"wait": VOICE_WAIT - 2})]
    toast = result.events[0]
    assert toast["type"] == "toast" and toast["message"] == "Poniendo The Office · T1 E1"
    assert toast["detail"] == "Di «pausa» o «siguiente episodio»"  # el segundo renglón: lo que puedes decir ahora


def test_una_serie_en_latino_siempre_lo_recuerda_al_ponerla(library, office, played):
    said = VoiceController(library).handle_text("pon The Office siempre en latino").speech
    assert said == "Poniendo The Office, temporada 1, episodio 1 en latino. The Office quedará en latino."
    assert played[-1][1] == {"wait": VOICE_WAIT - 2, "audio": "es", "spanish": "es-419", "remember": True}


def test_sin_lista_de_episodios_abre_la_ficha(library, office, played, monkeypatch):
    def down(self, kind, meta_id):
        raise cinemeta.CinemetaError("caído")
    monkeypatch.setattr(cinemeta.Cinemeta, "meta", down)
    result = VoiceController(library).handle_text("pon The Office")
    assert result.speech == "Abriendo The Office. Elige el episodio." and played == []
    assert result.events[0]["view"] == {"serie": "tt0386676"}


# --- «otro» ------------------------------------------------------------------------------------------------------------
def test_otro_pone_la_siguiente_que_se_llama_igual(library, office, played):
    voice = VoiceController(library)
    result = voice.handle_text("pon Dune")
    assert result.speech == "Poniendo Dune. Si no es esa, di otro."
    assert [c["meta_id"] for c in result.choices] == ["tt1160419", "tt0087182"]  # el iPhone las enseña para tocar
    assert result.as_dict()["picked"] == "tt1160419"  # la que ya está puesta; la otra es para cambiar
    assert result.events[0]["detail"] == "Si no es esa, di «otro»"
    first = played[-1][0][1]
    assert voice.handle_text("otro").ok
    second = played[-1][0][1]
    assert {first, second} == {"tt1160419", "tt0087182"}
    last = voice.handle_text("esa no")
    assert not last.ok and "busca dune" in last.speech.lower()


def test_busca_con_varias_pregunta_cual(library, office, played):
    """«Busca Dune»: pediste buscar, así que se pregunta (en la tele y en el iPhone) en vez de poner una."""
    result = VoiceController(library).handle_text("busca Dune")
    assert played == [] and result.events[0]["type"] == "choose"
    assert "picked" not in result.as_dict() and len(result.as_dict()["choices"]) == 2  # «busca»: nada puesto, a elegir


def test_otro_sin_nada_antes_pregunta(library):
    result = VoiceController(library).handle_text("otro")
    assert not result.ok and result.speech.startswith("¿Otro qué?")


def test_otro_y_siguiente_en_la_tele_en_vivo_cambian_de_canal(library, monkeypatch):
    library.player = FakePlayer(playing=True)
    monkeypatch.setattr(library.tv, "playing", lambda: "adn")
    voice = VoiceController(library)
    steps = []
    monkeypatch.setattr(voice, "_channel_step_intent", lambda slots: steps.append(slots["step"]) or SimpleNamespace(
        ok=True, speech="Canal X.", events=[{"type": "noop"}]))
    for said in ("otro", "siguiente", "siguiente episodio", "episodio anterior"):
        voice.handle_text(said)
    assert steps == ["next", "next", "next", "previous"]


# --- apagar ------------------------------------------------------------------------------------------------------------
def test_apaga_la_tele_guarda_cierra_y_apaga(library):
    tv = FakeTv()
    library.player = FakePlayer(playing=True)
    result = VoiceController(library, tv=tv).handle_text("apaga la tele")
    assert result.ok and library.player.stopped and tv.calls == ["off"]
    assert result.speech == "Guardé dónde ibas en The Office · T4 E3. Apagando la tele."


def test_apaga_a_secas_solo_cierra_el_video(library):
    tv = FakeTv()
    library.player = FakePlayer(playing=True)
    VoiceController(library, tv=tv).handle_text("apaga")
    assert library.player.stopped and tv.calls == []


def test_apaga_la_tele_sin_tele_conectada_lo_dice(library):
    result = VoiceController(library).handle_text("apaga la tele")
    assert not result.ok and "no tiene una tele" in result.speech


# --- no encontré: la más parecida ----------------------------------------------------------------------------------------
def test_no_encontre_sugiere_el_mas_parecido(library, monkeypatch):
    voice = VoiceController(library)
    monkeypatch.setattr(library, "find", lambda *a, **k: None)  # lo que find() ya adivina no llega aquí
    monkeypatch.setattr(voice, "_watch_exact", lambda *a, **k: None)
    result = voice.handle_text("abre holow nait")
    assert not result.ok and result.speech == "No encontré holow nait. ¿Quisiste decir Hollow Knight? Di: abre Hollow Knight."
    assert voice._closest_title("zzzz qqqq") is None


# --- lo que encontró la sesión de las maquetas de la tele ---------------------------------------------------------------
def test_abrir_algo_parecido_dice_que_oyo(library):
    """«abre jades» abre Hades (se parece): el aviso dice qué oyó y cómo deshacerlo, no solo «Abriendo Hades»."""
    result = VoiceController(library).handle_text("abre jades")
    assert result.speech == "Abriendo Hades."
    assert result.events[0]["detail"] == "Entendí «jades»"
    assert result.events[0]["action"] == {"type": "voice-undo", "query": "jades"}  # B «No era eso»
    exact = VoiceController(library).handle_text("abre hades")
    assert exact.events[0].get("detail") is None  # igual a lo dicho: el aviso de siempre


def test_lo_que_no_se_entiende_se_ve_en_la_tele(library):
    result = VoiceController(library).handle_text("bla bla bla")
    assert not result.ok and result.events[0]["type"] == "toast" and result.events[0]["ok"] is False
    assert result.events[0]["message"] == "No entendí «bla bla bla»"
    assert result.events[0]["action"] == {"type": "voice-guide"}  # ☰ «Lo que puedes decir»
    fallback = VoiceController(library).handle_intent("FallbackIntent")
    assert fallback.events[0]["action"] == {"type": "voice-guide"}


def test_el_segundo_renglon_sale_de_lo_esencial_y_solo_con_frases_en_pantalla(library, office, played):
    """Decisión de Fernando: «Di …» solo con «Frases en pantalla» en Sí, y con frases de «Lo esencial» según el momento."""
    import json
    from pathlib import Path

    from orbital.voice import MOMENT_SAY
    core = {c["say"] for c in json.loads((Path(__file__).parent.parent / "alexa" / "commands.json").read_text(encoding="utf-8"))["core"]}
    assert {said for three in MOMENT_SAY.values() for said in three} <= core
    voice = VoiceController(library)
    assert voice.handle_text("pon The Office").events[0]["detail"] == "Di «pausa» o «siguiente episodio»"
    library.state.set_setting("voice_tips", False)
    off = voice.handle_text("pon The Office").events[0]
    assert "detail" not in off and off["message"] == "Poniendo The Office · T1 E1"
    kiosk = SimpleNamespace(open=lambda: None)
    library.state.set_setting("voice_tips", True)
    assert VoiceController(library, kiosk=kiosk).handle_text("prende la tele").events[0]["detail"] == "Di «pon The Office» o «sigue viendo»"


# --- lo que pidió el iPhone: «¿qué puedo decir?» y las frases del momento ------------------------------------------------
@pytest.mark.parametrize("said", ["qué puedo decir", "¿Qué le puedo decir?", "qué te puedo pedir", "ayuda", "enséñame la guía",
                                  "pídele a mi consola que me muestre la guía"])
def test_que_puedo_decir_abre_la_guia(said):
    assert parse_text(said) == ("GuideIntent", {}), said


def test_la_guia_se_abre_en_la_tele_y_avisa_al_iphone(library):
    result = VoiceController(library).handle_text("qué puedo decir")
    assert result.ok and result.as_dict()["guide"] is True
    assert result.events == [{"type": "open-guide"}]
    assert result.speech == "Te enseño lo que puedes decir. Por ejemplo: pon The Office, sigue viendo o qué sale hoy."


def test_las_frases_del_momento(library, monkeypatch):
    voice = VoiceController(library)
    assert voice.hints() == {"moment": "home", "hints": ["pon The Office", "sigue viendo", "qué sale hoy"]}
    library.player = FakePlayer(playing=True)
    library.player.current = SimpleNamespace(title="The Office", meta={"kind": "series"})
    assert voice.hints()["hints"] == ["pausa", "siguiente episodio", "pon subtítulos"]
    library.player.current = SimpleNamespace(title="Dune", meta={"kind": "movie"})
    assert voice.hints()["moment"] == "movie"
    monkeypatch.setattr(library.tv, "playing", lambda: "adn")
    assert voice.hints()["moment"] == "live"
