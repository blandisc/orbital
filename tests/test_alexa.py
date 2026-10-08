import importlib.util
import io
import json
from pathlib import Path

import pytest

SPEC = importlib.util.spec_from_file_location("alexa_lambda", Path(__file__).parent.parent / "alexa" / "lambda_function.py")


@pytest.fixture
def skill(monkeypatch):
    monkeypatch.setenv("ORBITAL_URL", "https://orbital.example/")
    monkeypatch.setenv("ORBITAL_TOKEN", "secreto")
    module = importlib.util.module_from_spec(SPEC)
    SPEC.loader.exec_module(module)
    return module


def intent_event(name, slots=None):
    return {"request": {"type": "IntentRequest", "intent": {"name": name, "slots": slots or {}}}}


def test_forwards_intent(skill, monkeypatch):
    sent = {}

    def fake_urlopen(req, timeout):
        sent.update(url=req.full_url, auth=req.headers["Authorization"], body=json.loads(req.data))
        return io.BytesIO(json.dumps({"speech": "Abriendo Hades."}).encode())

    monkeypatch.setattr(skill.urllib.request, "urlopen", fake_urlopen)
    out = skill.lambda_handler(intent_event("LaunchGameIntent", {"game": {"name": "game", "value": "hades"}}))
    assert out["response"]["outputSpeech"]["text"] == "Abriendo Hades."
    assert sent == {"url": "https://orbital.example/api/voice", "auth": "Bearer secreto",
                    "body": {"intent": "LaunchGameIntent", "slots": {"game": "hades"}}}


def test_resolves_synonyms(skill):
    slot = {"name": "direction", "value": "derecha", "resolutions": {"resolutionsPerAuthority": [
        {"status": {"code": "ER_SUCCESS_MATCH"}, "values": [{"value": {"name": "right"}}]}]}}
    assert skill.slot_values({"slots": {"direction": slot}}) == {"direction": "right"}


def test_offline_console(skill, monkeypatch):
    def boom(req, timeout):
        raise skill.urllib.error.URLError("down")

    monkeypatch.setattr(skill.urllib.request, "urlopen", boom)
    out = skill.lambda_handler(intent_event("OpenStremioIntent"))
    assert "encendida" in out["response"]["outputSpeech"]["text"]


def test_launch_request_keeps_session(skill):
    out = skill.lambda_handler({"request": {"type": "LaunchRequest"}})
    assert out["response"]["shouldEndSession"] is False
