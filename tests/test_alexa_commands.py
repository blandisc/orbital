"""Lo que se le puede decir a Alexa (alexa/commands.json, la lista que enseña la app de iPhone): cada frase de la
lista llega de verdad a un comando de Orbital. Y los comandos nuevos: TV en vivo, Para ti, brillo, secciones."""

from __future__ import annotations

import json
import re
from pathlib import Path
from types import SimpleNamespace

import pytest

from orbital.library.iptv import Channel
from orbital.voice import VoiceController, parse_text, upcoming_speech

ROOT = Path(__file__).resolve().parent.parent
COMMANDS = json.loads((ROOT / "alexa" / "commands.json").read_text(encoding="utf-8"))
MODEL = json.loads((ROOT / "alexa" / "interaction_model.es-MX.json").read_text(encoding="utf-8"))
INTENTS = {i["name"] for i in MODEL["interactionModel"]["languageModel"]["intents"]}
SAID = [c["say"] for g in COMMANDS["groups"] for c in g["commands"]]


@pytest.mark.parametrize("said", SAID)
def test_every_phrase_in_the_guide_reaches_a_command(said):
    found = parse_text(said)
    assert found is not None, f"«{said}» no llega a ningún comando"
    assert found[0] in INTENTS, f"«{said}» → {found[0]}, que no está en el modelo de Alexa"


def test_the_ways_to_ask_alexa_also_work():
    for how in COMMANDS["how"]:
        rest = re.sub(r"^Alexa, (?:pídele|dile|pide) a Orbital que ", "", how["say"])
        if rest != how["say"]:
            assert parse_text(rest) is not None, how["say"]


def test_the_iphone_shows_the_same_list():
    copy = ROOT / "ios" / "App" / "Resources" / "AlexaCommands.json"
    assert copy.read_bytes() == (ROOT / "alexa" / "commands.json").read_bytes(), "copia alexa/commands.json a la app de iPhone"


@pytest.mark.parametrize("said,expected", [
    ("pon el canal ADN 40", ("LiveTvIntent", {"channel": "adn 40"})),
    ("pon el canal adn cuarenta", ("LiveTvIntent", {"channel": "adn 40"})),
    ("pon azteca uno en vivo", ("LiveTvIntent", {"channel": "azteca 1"})),
    ("pon la tele", ("LiveTvIntent", {})),
    ("siguiente canal", ("ChannelStepIntent", {"step": "next"})),
    ("canal anterior", ("ChannelStepIntent", {"step": "previous"})),
    ("cambia de canal", ("ChannelStepIntent", {"step": "next"})),
    ("que sale hoy", ("UpcomingIntent", {})),
    ("qué me recomiendas", ("RecommendIntent", {})),
    ("sube el brillo", ("BrightnessIntent", {"brightness": "sube"})),
    ("pon el brillo al cincuenta", ("BrightnessIntent", {"level": "50"})),
    ("ve a para ti", ("NavigateIntent", {"direction": "para ti"})),
])
def test_new_phrases(said, expected):
    assert parse_text(said) == expected


@pytest.fixture
def channels(library, monkeypatch):
    library.tv.set_channels([
        Channel("adn", "ADN 40 (720p)", "http://x/adn"), Channel("a1", "Azteca Uno (1080p)", "http://x/a1"),
        Channel("c5", "Canal 5 (Mexico) (1080p)", "http://x/c5"), Channel("bm", "Bandamax", "http://x/bm"),
        Channel("ad", "Azteca Deportes Network", "http://x/ad")])
    played = []
    monkeypatch.setattr(library.tv, "play", lambda channel_id, *a, **k: played.append(channel_id) or {"ok": True, "reveal": True})
    return played


def test_a_channel_by_its_spoken_name(library, channels):
    voice = VoiceController(library)
    assert voice.handle_intent("LiveTvIntent", {"channel": "adn cuarenta"}).speech == "Poniendo ADN 40."
    assert voice.handle_intent("LiveTvIntent", {"channel": "azteca uno"}).ok
    assert voice.handle_intent("LiveTvIntent", {"channel": "5"}).ok  # «pon el canal cinco»
    assert voice.handle_intent("LiveTvIntent", {"channel": "azteca deportes"}).ok  # empieza así y es uno solo
    assert channels == ["adn", "a1", "c5", "ad"]


def test_saying_a_channel_as_a_search_puts_it_on(library, channels):
    """«pon ADN 40» llega a Alexa como búsqueda («pon {query}»): antes se buscaba en Stremio y no encontraba nada."""
    voice = VoiceController(library)
    assert voice.handle_intent("SearchMediaIntent", {"query": "ADN 40"}).ok
    assert voice.handle_intent("LaunchGameIntent", {"game": "bandamax"}).ok
    assert channels == ["adn", "bm"]


def test_the_simpsons_channel_by_voice_but_the_series_stays_the_series(library, channels, monkeypatch):
    """«pon el canal de los Simpson» prende el canal de Orbital (Alexa y «Dile a Orbital» del iPhone); «pon los Simpson»
    sin decir canal sigue siendo la serie (no se secuestra)."""
    voice = VoiceController(library)
    assert parse_text("pon el canal de los simpson") == ("LiveTvIntent", {"channel": "de los simpson"})
    assert voice.handle_intent("LiveTvIntent", {"channel": "de los simpson"}).speech == "Poniendo Los Simpson 24/7."
    assert voice.handle_intent("LiveTvIntent", {"channel": "los simpsons"}).ok  # Alexa: «pon el canal de {channel}»
    assert voice.handle_intent("LaunchGameIntent", {"game": "los simpson 24 7"}).ok
    assert voice.handle_intent("LiveTvIntent", {"channel": "de caricaturas"}).ok
    assert channels == ["orbital:simpsons"] * 3 + ["orbital:caricaturas"]
    assert voice._find_channel("los simpson") is None  # «pon los Simpson»: la serie, no el canal


def test_an_unknown_channel_shows_the_list(library, channels):
    result = VoiceController(library).handle_intent("LiveTvIntent", {"channel": "canal que no existe"})
    assert not result.ok and "No encontré el canal" in result.speech
    assert result.events[0]["view"] == {"seccion": "tv"} and channels == []


def test_next_channel_tunes_the_one_after_in_its_list(library, channels, monkeypatch):
    tuned = []
    monkeypatch.setattr(library.tv, "playing", lambda: "adn")
    monkeypatch.setattr(library.watch.player, "segment", SimpleNamespace(meta={"channel_id": "adn", "list": "todos"}), raising=False)
    monkeypatch.setattr(library.tv, "tune", lambda meta, channel_id, category=None, **k: tuned.append(channel_id) or True)
    voice = VoiceController(library)
    order = [c.id for c in library.tv.zap_list("todos")[1]]
    assert voice.handle_intent("ChannelStepIntent", {"step": "next"}).ok
    assert voice.handle_intent("ChannelStepIntent", {"step": "anterior"}).ok
    here = order.index("adn")
    assert tuned == [order[(here + 1) % len(order)], order[(here - 1) % len(order)]]


def test_next_channel_without_tv_on_says_how(library):
    result = VoiceController(library).handle_intent("ChannelStepIntent", {"step": "next"})
    assert not result.ok and "pon el canal" in result.speech


@pytest.mark.parametrize("said,section", [("para ti", "foryou"), ("la tele", "tv"), ("tv en vivo", "tv"), ("juegos", "games")])
def test_sections_by_voice(library, said, section):
    result = VoiceController(library).handle_intent("NavigateIntent", {"direction": said})
    assert result.ok and result.events[0]["view"] == {"seccion": section}


def test_open_para_ti_is_a_section_not_a_game(library):
    result = VoiceController(library).handle_intent("LaunchGameIntent", {"game": "Para ti"})
    assert result.ok and result.events[0]["view"] == {"seccion": "foryou"}


def test_upcoming_without_trakt_says_what_to_do(library):
    result = VoiceController(library).handle_intent("UpcomingIntent", {})
    assert not result.ok and "Trakt" in result.speech


def test_upcoming_is_said_by_day(library, monkeypatch):
    monkeypatch.setattr(library.foryou.trakt, "tokens", {"access_token": "x"}, raising=False)
    monkeypatch.setattr(type(library.foryou.trakt), "linked", property(lambda self: True))
    monkeypatch.setattr(library.foryou, "calendar", lambda: [
        {"title": "Severance", "day_label": "Hoy", "time": "20:00"},
        {"title": "Andor", "day_label": "Mañana", "time": "Desde la madrugada"},
        {"title": "Silo", "day_label": "Mañana", "time": "Desde la madrugada"}])
    result = VoiceController(library).handle_intent("UpcomingIntent", {})
    assert result.ok and result.speech == "Hoy sale Severance a las 20:00. Mañana: Andor y Silo, desde la madrugada."
    assert result.events[0]["view"] == {"seccion": "foryou"}


def test_upcoming_speech_without_a_common_time():
    assert upcoming_speech([{"title": "A", "day_label": "Hoy", "time": "19:00"}, {"title": "B", "day_label": "Hoy", "time": "21:00"}]) \
        == "Hoy salen A y B."


def test_brightness_by_voice(library, monkeypatch):
    from orbital import quick
    state = {"level": 50}
    monkeypatch.setattr(quick, "brightness", lambda: state["level"])
    monkeypatch.setattr(quick, "set_brightness", lambda level: state.update(level=level) or level)
    voice = VoiceController(library)
    assert voice.handle_intent("BrightnessIntent", {"brightness": "up"}).speech == "Brillo en 65 por ciento."
    assert voice.handle_intent("BrightnessIntent", {"level": "30"}).speech == "Brillo en 30 por ciento."
    monkeypatch.setattr(quick, "brightness", lambda: None)
    assert not voice.handle_intent("BrightnessIntent", {"brightness": "down"}).ok


def test_the_tv_shows_the_same_guide(make_client):
    data = make_client().get("/api/voice/commands").json()
    assert data == COMMANDS


def test_genre_art_is_the_same_on_the_tv_and_the_iphone():
    """Películas y series › Por género usa el arte de Explora del iPhone (más ligero, misma proporción)."""
    from PIL import Image

    ios = sorted((ROOT / "ios/App/Resources/Assets.xcassets/Genres").glob("genre-*.imageset/*.jpg"))
    assert ios
    for path in ios:
        tv = ROOT / "orbital/web/img/genres" / path.name
        assert tv.is_file(), f"falta {tv.name} en la tele (scripts/genre_art.py)"
        a, b = Image.open(path).size, Image.open(tv).size
        assert abs(a[0] / a[1] - b[0] / b[1]) < .01
