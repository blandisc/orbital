import importlib.util
import io
import json
import re
from pathlib import Path

import pytest
import yaml
from fastapi.testclient import TestClient

from orbital import alexa_setup
from orbital.server import create_app, create_public_app

ROOT = Path(__file__).parent.parent
SPEC = importlib.util.spec_from_file_location("alexa_lambda", ROOT / "alexa" / "lambda_function.py")
MODEL = json.loads((ROOT / "alexa" / "interaction_model.es-MX.json").read_text(encoding="utf-8"))
SKILL = "amzn1.ask.skill.mia"


# --------------------------------------------------------------------- Lambda
@pytest.fixture
def skill(monkeypatch):
    monkeypatch.setenv("ORBITAL_URL", "https://orbital.example/")
    monkeypatch.setenv("ORBITAL_TOKEN", "secreto")
    monkeypatch.setenv("ALEXA_SKILL_ID", SKILL)
    module = importlib.util.module_from_spec(SPEC)
    SPEC.loader.exec_module(module)
    return module


def event(request, skill_id=SKILL):
    return {"session": {"application": {"applicationId": skill_id}}, "request": request}


def intent_event(name, slots=None, **kw):
    return event({"type": "IntentRequest", "intent": {"name": name, "slots": slots or {}}}, **kw)


@pytest.fixture
def orbital(skill, monkeypatch):
    sent = []

    def fake_urlopen(req, timeout):
        body = json.loads(req.data)
        sent.append({"url": req.full_url, "auth": req.headers["Authorization"], "body": body})
        return io.BytesIO(json.dumps({"ok": True, "speech": f"hecho {body['intent']}"}).encode())

    monkeypatch.setattr(skill.urllib.request, "urlopen", fake_urlopen)
    return sent


def test_forwards_intent(skill, orbital):
    out = skill.lambda_handler(intent_event("LaunchGameIntent", {"game": {"name": "game", "value": "hades con eden"}}))
    assert out["response"]["outputSpeech"]["text"] == "hecho LaunchGameIntent"
    assert orbital == [{"url": "https://orbital.example/api/voice", "auth": "Bearer secreto",
                        "body": {"intent": "LaunchGameIntent", "slots": {"game": "hades con eden"}}}]


def test_launch_request_reopens_ui_and_keeps_session(skill, orbital):
    out = skill.lambda_handler(event({"type": "LaunchRequest"}))
    assert orbital[0]["body"]["intent"] == "OpenOrbitalIntent"
    assert out["response"]["shouldEndSession"] is False


def test_navigate_home(skill, orbital):
    skill.lambda_handler(intent_event("AMAZON.NavigateHomeIntent"))
    assert orbital[0]["body"] == {"intent": "NavigateIntent", "slots": {"direction": "home"}}


def test_rejects_other_skills(skill, orbital):
    with pytest.raises(PermissionError):
        skill.lambda_handler(intent_event("LaunchGameIntent", skill_id="amzn1.ask.skill.ajena"))
    assert orbital == []  # nada llegó a la consola


def test_resolves_synonyms(skill):
    slot = {"name": "direction", "value": "derecha", "resolutions": {"resolutionsPerAuthority": [
        {"status": {"code": "ER_SUCCESS_MATCH"}, "values": [{"value": {"name": "right"}}]}]}}
    assert skill.slot_values({"slots": {"direction": slot}}) == {"direction": "right"}


def test_offline_console(skill, monkeypatch):
    def boom(req, timeout):
        raise skill.urllib.error.URLError("down")

    monkeypatch.setattr(skill.urllib.request, "urlopen", boom)
    for ev in (event({"type": "LaunchRequest"}), intent_event("OpenStremioIntent")):
        out = skill.lambda_handler(ev)
        assert "encendida" in out["response"]["outputSpeech"]["text"] and out["response"]["shouldEndSession"]


def test_bad_token_message(skill, monkeypatch):
    def unauthorized(req, timeout):
        raise skill.urllib.error.HTTPError(req.full_url, 401, "x", {}, io.BytesIO(b""))

    monkeypatch.setattr(skill.urllib.request, "urlopen", unauthorized)
    assert "token" in skill.lambda_handler(intent_event("WhatsPlayingIntent"))["response"]["outputSpeech"]["text"]


# --------------------------------------------------------------------- modelo de voz
def test_interaction_model_is_valid():
    lm = MODEL["interactionModel"]["languageModel"]
    assert lm["invocationName"] == "mi consola"
    types = {t["name"] for t in lm["types"]}
    seen = {}
    for intent in lm["intents"]:
        slots = {s["name"]: s["type"] for s in intent.get("slots", [])}
        assert all(t.startswith("AMAZON.") or t in types for t in slots.values())
        for sample in intent["samples"]:
            assert sample not in seen, f"'{sample}' repetido en {intent['name']} y {seen.get(sample)}"
            seen[sample] = intent["name"]
            used = re.findall(r"{(\w+)}", sample)
            assert set(used) <= set(slots), sample
            # Regla de Alexa: una búsqueda libre necesita frase de apoyo y no admite otros slots.
            if any(slots[u] == "AMAZON.SearchQuery" for u in used):
                assert len(used) == 1 and sample.strip() != "{%s}" % used[0], sample


def test_model_intents_exist_in_orbital(library):
    from orbital.voice import VoiceController
    voice = VoiceController(library)
    for intent in MODEL["interactionModel"]["languageModel"]["intents"]:
        name = intent["name"]
        if not name.startswith("AMAZON."):
            handler = "_" + re.sub(r"(?<!^)(?=[A-Z])", "_", name).lower()
            assert hasattr(voice, handler), f"Orbital no maneja {name}"


def test_spanish_conjugations_reach_same_intent():
    from orbital.voice import parse_text
    for phrase in ("abre hades", "abra hades", "abrir hades", "juegue hades"):
        assert parse_text(phrase) == ("LaunchGameIntent", {"game": "hades"})
    for phrase in ("sal al escritorio", "salga al escritorio", "salir al escritorio"):
        assert parse_text(phrase) == ("ExitToDesktopIntent", {})
    assert parse_text("siga viendo") == ("ContinueWatchingIntent", {})


# --------------------------------------------------------------------- asistente
def test_ensure_token_keeps_comments(tmp_path):
    cfg = tmp_path / "config.yaml"
    cfg.write_text('# mi config\nserver:\n  port: 8710\n  token: "CAMBIA-ESTE-TOKEN"   # cámbialo\nui:\n  mode: browser\n')
    token, created = alexa_setup.ensure_token(cfg)
    text = cfg.read_text()
    assert created and len(token) > 30 and text.startswith("# mi config")
    assert yaml.safe_load(text)["server"] == {"port": 8710, "token": token}
    assert alexa_setup.ensure_token(cfg) == (token, False)  # idempotente


def test_ensure_token_other_layouts(tmp_path):
    cfg = tmp_path / "a.yaml"
    cfg.write_text("server:\n  port: 1\n")
    token, _ = alexa_setup.ensure_token(cfg)
    assert yaml.safe_load(cfg.read_text())["server"] == {"token": token, "port": 1}
    missing = tmp_path / "nuevo" / "config.yaml"
    token, _ = alexa_setup.ensure_token(missing)
    assert yaml.safe_load(missing.read_text()) == {"server": {"token": token}}
    flow = tmp_path / "flow.yaml"
    flow.write_text("server: {port: 1}\n")
    with pytest.raises(ValueError, match="a mano"):
        alexa_setup.ensure_token(flow)
    assert flow.read_text() == "server: {port: 1}\n"  # no lo rompe


def test_parse_tailscale_status():
    raw = json.dumps({"Self": {"DNSName": "legion-go.tail1234.ts.net.", "HostName": "legion-go"}})
    assert alexa_setup.parse_tailscale_status(raw) == "https://legion-go.tail1234.ts.net"
    assert alexa_setup.parse_tailscale_status("{}") is None
    assert alexa_setup.parse_tailscale_status("no json") is None


def fake_fetch(responses):
    def fetch(url, token=None, data=None, timeout=10):
        return responses[(url.rsplit("/api/", 1)[1], bool(token))]
    return fetch


def test_check_tunnel_ok_and_wrong_port():
    good = {("ping", True): (200, '{"ok":true,"service":"orbital"}'), ("ping", False): (401, ""),
            ("library", True): (401, "")}
    assert all(c.ok for c in alexa_setup.check_tunnel("https://x.ts.net", "t", fake_fetch(good)))
    wrong = {("ping", True): (404, '{"detail":"Not Found"}')}  # túnel apuntando al 8710
    [check] = alexa_setup.check_tunnel("https://x.ts.net", "t", fake_fetch(wrong))
    assert not check.ok and "8711" in check.detail
    bad_token = {("ping", True): (401, "")}
    assert "token" in alexa_setup.check_tunnel("https://x.ts.net", "t", fake_fetch(bad_token))[0].detail


# --------------------------------------------------------------------- puerto público
@pytest.fixture
def public(library):
    main = create_app(library.config, library)
    with TestClient(main, base_url="http://127.0.0.1:8710", client=("127.0.0.1", 1)):
        yield TestClient(create_public_app(library.config, main), base_url="https://legion.ts.net",
                         client=("127.0.0.1", 2)), main


def test_public_app_always_requires_token(public):
    client, main = public
    # Aunque el túnel entregue desde 127.0.0.1, sin token no hay nada.
    assert client.get("/api/ping").status_code == 401
    assert client.post("/api/voice", json={"text": "abre hades"}).status_code == 401
    auth = {"Authorization": "Bearer secreto"}
    assert client.get("/api/ping", headers=auth).json()["service"] == "orbital"
    assert client.post("/api/voice", json={"text": "abre hades"}, headers=auth).json()["speech"] == "Abriendo Hades."
    assert main.state.alexa_last is not None
    # Solo existen voz y ping: ni la interfaz, ni la biblioteca, ni lanzar cosas.
    for path in ("/", "/api/library", "/docs", "/openapi.json"):
        assert client.get(path, headers=auth).status_code == 404
    assert client.post("/api/launch", json={"id": "steam:367520"}, headers=auth).status_code == 404


def test_main_app_rejects_tunnel_host_without_token(library):
    # Un túnel que apunte por error al puerto principal llega desde 127.0.0.1 con Host público.
    with TestClient(create_app(library.config, library), base_url="https://legion.ts.net", client=("127.0.0.1", 1)) as c:
        assert c.get("/api/library").status_code == 401
        assert c.post("/api/launch", json={"id": "steam:367520"}).status_code == 401
    with TestClient(create_app(library.config, library), base_url="http://localhost:8710", client=("127.0.0.1", 1)) as c:
        assert c.get("/api/library").status_code == 200
