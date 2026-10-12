"""Lo que encontró el agente que intentó romper Alexa y la voz: que no vuelva a pasar."""

import importlib.util
import io
import json
from pathlib import Path

import pytest

from orbital.voice import VoiceController, parse_text

SPEC = importlib.util.spec_from_file_location("alexa_lambda_robusta", Path(__file__).parent.parent / "alexa" / "lambda_function.py")


@pytest.fixture
def skill(monkeypatch):
    monkeypatch.setenv("ORBITAL_URL", "https://orbital.example")
    monkeypatch.setenv("ORBITAL_TOKEN", "secreto")
    monkeypatch.setenv("ALEXA_SKILL_ID", "")
    module = importlib.util.module_from_spec(SPEC)
    SPEC.loader.exec_module(module)
    return module


def answer(skill, monkeypatch, body: bytes, event):
    monkeypatch.setattr(skill.urllib.request, "urlopen", lambda req, timeout: io.BytesIO(body))
    out = skill.lambda_handler(event)
    text = out["response"]["outputSpeech"]["text"]
    assert isinstance(text, str) and text.strip() and len(text) <= 601
    return text


@pytest.mark.parametrize("event", [
    {"request": None}, {"request": {"type": "IntentRequest"}}, {"request": {"type": "IntentRequest", "intent": None}},
    {"request": {"type": "IntentRequest", "intent": {}}},
    {"request": {"type": "IntentRequest", "intent": {"name": "LaunchGameIntent", "slots": {"game": None}}}},
    {"request": {"type": "IntentRequest", "intent": {"name": "LaunchGameIntent", "slots": {"game": "hades"}}}},
    {"request": {"type": "IntentRequest", "intent": {"name": "NavigateIntent", "slots": {"direction": {"value": "x", "resolutions": {
        "resolutionsPerAuthority": [{"status": {"code": "ER_SUCCESS_MATCH"}, "values": []}]}}}}}},
])
def test_odd_alexa_requests_always_get_a_spoken_answer(skill, monkeypatch, event):
    answer(skill, monkeypatch, json.dumps({"ok": True, "speech": "hecho"}).encode(), event)


@pytest.mark.parametrize("body", [b"<html>502</html>", b"", b"[1]", b"null", b"\xff\xfe{", json.dumps({"speech": ""}).encode(),
                                  json.dumps({"speech": None}).encode(), json.dumps({"speech": 5}).encode(),
                                  json.dumps({"ok": True, "speech": "x " * 6000}).encode()])
def test_odd_orbital_answers_are_still_speakable(skill, monkeypatch, body):
    answer(skill, monkeypatch, body, {"request": {"type": "IntentRequest", "intent": {"name": "PauseIntent"}}})


def test_slow_tunnel_answers_before_alexa_gives_up(skill, monkeypatch):
    import time

    skill.TIMEOUT = .3
    monkeypatch.setattr(skill, "_post", lambda req: time.sleep(3) or b"{}")
    start = time.monotonic()
    out = skill.lambda_handler({"request": {"type": "IntentRequest", "intent": {"name": "PauseIntent"}}})
    assert time.monotonic() - start < 1.5 and "tardó" in out["response"]["outputSpeech"]["text"]


@pytest.mark.parametrize("said", ["h", "de", "o", "super man", "chrono cross", "hadestown", "hollow knight silksong", "hands"])
def test_voice_does_not_open_the_wrong_game(library, said):
    result = VoiceController(library).handle_intent("LaunchGameIntent", {"game": said})
    assert library.launcher.opened == [] and library.launcher.ran == [], (said, result.speech)


@pytest.mark.parametrize("said, title", [("hades", "Hades"), ("el juego hades", "Hades"), ("jades", "Hades"),
                                         ("hollow", "Hollow Knight"), ("chrono trigger", "Chrono Trigger")])
def test_voice_still_finds_what_you_meant(library, said, title):
    assert VoiceController(library).handle_intent("LaunchGameIntent", {"game": said}).speech.startswith(f"Abriendo {title}")


def test_volume_to_a_level_sets_it_and_points_add():
    from orbital import quick

    quick.set_volume(level=90)
    voice = VoiceController(None)
    assert voice.handle_intent("VolumeIntent", {"volume": "sube", "level": "30"}).speech == "Volumen en 30 por ciento."
    assert voice.handle_intent("VolumeIntent", {"volume": "sube", "amount": "20"}).speech == "Volumen en 50 por ciento."
    assert parse_text("pon el volumen a cincuenta") == ("VolumeIntent", {"level": "50"})
    assert parse_text("pon el volumen al maximo") == ("VolumeIntent", {"level": "100"})
    assert parse_text("silencia") == ("MuteIntent", {})


def test_text_phrases_that_were_missing():
    assert parse_text("episodio anterior") == ("PreviousEpisodeIntent", {})
    assert parse_text("cierra el video") == ("CloseGameIntent", {})
    assert parse_text("que estoy viendo") == ("WhatsPlayingIntent", {})
    assert parse_text("adelanta media hora") == ("SeekIntent", {"seek": "adelanta", "amount": "media", "unit": "hora"})


def test_public_port_limits_body_and_accepts_any_bearer_case(library):
    from fastapi.testclient import TestClient

    from orbital.server import create_app, create_public_app

    main = create_app(library.config, library)
    token = library.config.server.token
    with TestClient(main, base_url="http://127.0.0.1:8710", client=("127.0.0.1", 1)):
        with TestClient(create_public_app(library.config, main), client=("127.0.0.1", 2)) as c:
            assert c.get("/api/ping", headers={"Authorization": f"bearer {token}"}).status_code == 200
            assert c.head("/api/ping", headers={"Authorization": f"Bearer {token}"}).status_code == 200
            big = c.post("/api/voice", headers={"Authorization": f"Bearer {token}"}, json={"text": "abre " + "a" * 100_000})
            assert big.status_code == 413
