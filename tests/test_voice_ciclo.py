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
    assert result.events[0]["detail"] == "Di «otro» si no es esa"
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
    assert result.events[0]["detail"] == "Entendí «jades». Si no era, di «cierra el juego»"
    exact = VoiceController(library).handle_text("abre hades")
    assert exact.events[0].get("detail") is None  # igual a lo dicho: el aviso de siempre


def test_lo_que_no_se_entiende_se_ve_en_la_tele(library):
    result = VoiceController(library).handle_text("bla bla bla")
    assert not result.ok and result.events[0]["type"] == "toast" and result.events[0]["ok"] is False
    assert result.events[0]["message"] == "No entendí «bla bla bla»"
