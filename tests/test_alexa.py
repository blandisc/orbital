import importlib.util
import io
import json
import re
import sys
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
    assert lm["invocationName"] == "orbital"  # Alexa: el nombre con que se invoca va en minúsculas
    types = {t["name"] for t in lm["types"]}
    seen = {}
    slot_types = {}  # Regla de Alexa: un nombre de slot = un solo tipo en todo el modelo
    for intent in lm["intents"]:
        slots = {s["name"]: s["type"] for s in intent.get("slots", [])}
        for name, kind in slots.items():
            assert slot_types.setdefault(name, kind) == kind, f"slot '{name}' con dos tipos ({intent['name']})"
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
    cfg.write_text('# mi config\nserver:\n  port: 8710\n  token: "CAMBIA-ESTE-TOKEN"   # cámbialo\nui:\n  mode: browser\n', encoding="utf-8")
    token, created = alexa_setup.ensure_token(cfg)
    text = cfg.read_text(encoding="utf-8")
    assert created and len(token) > 30 and text.startswith("# mi config")
    stored = yaml.safe_load(text)["server"]
    assert stored["port"] == 8710 and token not in text  # en Windows se guarda cifrado (dpapi:…)
    assert alexa_setup.read_token(cfg) == token
    assert alexa_setup.ensure_token(cfg) == (token, False)  # idempotente


def test_ensure_token_other_layouts(tmp_path):
    cfg = tmp_path / "a.yaml"
    cfg.write_text("server:\n  port: 1\n")
    token, _ = alexa_setup.ensure_token(cfg)
    assert yaml.safe_load(cfg.read_text())["server"]["port"] == 1 and alexa_setup.read_token(cfg) == token
    missing = tmp_path / "nuevo" / "config.yaml"
    token, _ = alexa_setup.ensure_token(missing)
    assert list(yaml.safe_load(missing.read_text())) == ["server"] and alexa_setup.read_token(missing) == token
    flow = tmp_path / "flow.yaml"
    flow.write_text("server: {port: 1}\n")
    with pytest.raises(ValueError, match="a mano"):
        alexa_setup.ensure_token(flow)
    assert flow.read_text() == "server: {port: 1}\n"  # no lo rompe


@pytest.mark.skipif(sys.platform != "win32", reason="DPAPI es de Windows")
def test_existing_plain_token_can_be_encrypted(tmp_path):
    from orbital.config import load_config

    cfg = tmp_path / "config.yaml"
    cfg.write_text('server:\n  token: "mi-token-de-alexa"  # fijo\n', encoding="utf-8")
    assert alexa_setup.protect_token(cfg)
    text = cfg.read_text(encoding="utf-8")
    assert "mi-token-de-alexa" not in text and text.startswith("server:")
    assert alexa_setup.read_token(cfg) == "mi-token-de-alexa"
    loaded = load_config(cfg)
    assert loaded.server.token == "mi-token-de-alexa" and not loaded.server.token_is_ephemeral
    assert not alexa_setup.protect_token(cfg)  # ya estaba cifrado


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
    assert main.state.deps.alexa_last is not None
    # Solo existen voz, ping y «Ver en la TV»: ni la interfaz, ni la biblioteca, ni lanzar juegos.
    for path in ("/", "/api/library", "/docs", "/openapi.json"):
        assert client.get(path, headers=auth).status_code == 404
    assert client.post("/api/launch", json={"id": "steam:367520"}, headers=auth).status_code == 404


def test_public_app_plays_a_stremio_title_on_the_tv_only_with_token(public):
    """«Ver en la TV» desde el iPhone: mismo token que Alexa, y lo mismo que pide la tarjeta de la TV."""
    client, main = public
    asked = []
    main.state.play_stremio = lambda body: asked.append(body.model_dump()) or {"ok": True}
    body = {"kind": "series", "id": "tt0386676", "video_id": "tt0386676:2:5", "title": "The Office"}
    assert client.post("/api/stremio/play", json=body).status_code == 401
    assert asked == []
    auth = {"Authorization": "Bearer secreto"}
    assert client.post("/api/stremio/play", json=body, headers=auth).json() == {"ok": True}
    assert asked[0]["video_id"] == "tt0386676:2:5" and asked[0]["source"] is None
    # El resto de la API de Stremio sigue cerrada por el túnel.
    assert client.post("/api/stremio/login", json={}, headers=auth).status_code == 404


def test_public_app_shares_para_ti_keys_with_the_iphone_but_never_the_secret(public):
    client, main = public
    cfg = main.state.deps.config
    cfg.para_ti.tmdb_key, cfg.para_ti.trakt_client_id, cfg.para_ti.trakt_client_secret = "tmdb123", "cid456", "secreto-de-trakt"
    assert client.get("/api/companion").status_code == 401
    got = client.get("/api/companion", headers={"Authorization": "Bearer secreto"}).json()
    assert {k: got[k] for k in ("tmdb_key", "trakt_client_id", "region")} == {"tmdb_key": "tmdb123", "trakt_client_id": "cid456", "region": cfg.para_ti.region}
    assert got["trakt_session"] is None  # Trakt sin conectar en la consola: no hay sesión que prestar
    assert "secreto-de-trakt" not in str(got)


def test_main_app_rejects_tunnel_host_without_token(library):
    # Un túnel que apunte por error al puerto principal llega desde 127.0.0.1 con Host público.
    with TestClient(create_app(library.config, library), base_url="https://legion.ts.net", client=("127.0.0.1", 1)) as c:
        assert c.get("/api/library").status_code == 401
        assert c.post("/api/launch", json={"id": "steam:367520"}).status_code == 401
    with TestClient(create_app(library.config, library), base_url="http://localhost:8710", client=("127.0.0.1", 1)) as c:
        assert c.get("/api/library").status_code == 200


def test_failed_tokens_slow_down_then_block():
    from orbital.server import FailedTokens

    now = [0.0]
    guard = FailedTokens(clock=lambda: now[0])
    delays = [guard.failed("x") for _ in range(8)]
    assert delays[:4] == [0, 0, 0, 0] and delays[-1] > 0  # los primeros (un error de dedo) sin espera
    for _ in range(FailedTokens.BLOCK_AFTER):
        guard.failed("x")
    assert guard.blocked("x") and not guard.blocked("otro")
    now[0] += FailedTokens.BLOCK_FOR + 1
    assert not guard.blocked("x")


def test_public_app_answers_429_when_blocked(library):
    from orbital.server import FailedTokens

    guard = FailedTokens()
    guard._blocked["127.0.0.1"] = guard.clock() + 60
    main = create_app(library.config, library)
    with TestClient(create_public_app(library.config, main, guard), client=("127.0.0.1", 5000)) as c:
        bad = c.get("/api/ping", headers={"Authorization": "Bearer otro"})
        # Con tu token entras aunque alguien haya falsificado tu dirección hasta bloquearla.
        good = c.get("/api/ping", headers={"Authorization": f"Bearer {library.config.server.token}"})
        spoofed = c.get("/api/ping", headers={"Authorization": "Bearer otro", "X-Forwarded-For": "127.0.0.1, 9.9.9.9"})
    assert bad.status_code == 429 and good.status_code == 200
    assert spoofed.status_code == 401  # cuenta el último valor (el que puso el túnel), no el que escribe quien llama


@pytest.mark.skipif(sys.platform != "win32", reason="DPAPI es de Windows")
def test_rotate_gives_a_new_encrypted_token(tmp_path):
    cfg = tmp_path / "config.yaml"
    cfg.write_text('server:\n  token: "viejo"\n', encoding="utf-8")
    new = alexa_setup.rotate_token(cfg)
    assert new != "viejo" and alexa_setup.read_token(cfg) == new and "viejo" not in cfg.read_text(encoding="utf-8")


def test_settings_know_when_the_iphone_last_connected(public):
    """Ajustes › Cuentas enseña «iPhone · Conectado · lo usaste hace 2 h»: cuando la app pide sus claves, se anota."""
    client, main = public
    state = main.state.catalog.state
    assert "companion_seen" not in state.settings()
    assert client.get("/api/companion", headers={"Authorization": "Bearer secreto"}).status_code == 200
    first = state.settings()["companion_seen"]
    client.get("/api/companion", headers={"Authorization": "Bearer secreto"})
    assert state.settings()["companion_seen"] == first  # una escritura cada 10 min, no en cada petición


def test_the_iphone_open_counts_as_a_visit_too(public):
    """El iPhone abierto pide /api/companion/now cada 5 s: eso también es «lo usaste» (antes solo contaba al emparejarse)."""
    client, main = public
    state = main.state.catalog.state
    assert client.get("/api/companion/now", headers={"Authorization": "Bearer secreto"}).status_code == 200
    assert state.settings()["companion_seen"]


def test_iphone_remote_buttons_go_to_whatever_is_in_front(public, monkeypatch):
    """El control del iPhone: un botón llega a la interfaz como el mando (o al reproductor si está al frente), con token
    y sin pasarse de ~15 por segundo."""
    from orbital import companion

    client, main = public
    auth = {"Authorization": "Bearer secreto"}
    assert client.post("/api/companion/input", json={"action": "down"}).status_code == 401
    events = []
    main.state.catalog.events.subscribe(events.append)
    monkeypatch.setattr(companion, "_front", lambda catalog, shell: "ui")
    r = client.post("/api/companion/input", json={"action": "down"}, headers=auth)
    assert r.status_code == 200 and r.json() == {"ok": True, "target": "ui"}
    assert {"type": "input", "action": "down"} in events
    assert client.post("/api/companion/input", json={"action": "borrar-todo"}, headers=auth).status_code == 400
    pressed = []
    monkeypatch.setattr(companion, "_front", lambda catalog, shell: "player")
    monkeypatch.setattr(main.state.catalog.watch.player, "phone_button", pressed.append)
    assert client.post("/api/companion/input", json={"action": "select"}, headers=auth).json()["target"] == "player"
    assert pressed == ["select"]
    codes = [client.post("/api/companion/input", json={"action": "left"}, headers=auth).status_code for _ in range(40)]
    assert 429 in codes  # mantener el pad no satura la tele


def test_iphone_remote_text_and_what_the_tv_shows(public):
    client, main = public
    auth = {"Authorization": "Bearer secreto"}
    events = []
    main.state.catalog.events.subscribe(events.append)
    assert client.post("/api/companion/text", json={"text": "dune", "submit": True}, headers=auth).status_code == 200
    assert {"type": "text", "text": "dune", "submit": True, "replace": False} in events
    assert client.get("/api/companion/now", headers=auth).json()["ui"] == {"screen": "home", "text_field": False}


def test_the_tv_reports_its_screen_for_the_iphone(public):
    client, main = public
    local = TestClient(main, base_url="http://127.0.0.1:8710", client=("127.0.0.1", 1))
    legend = {"select": "Ver", "back": "Atrás", "alt": "Mi lista", "section": "Sección"}
    assert local.post("/api/ui/state", json={"screen": "search", "text_field": True, "section": "Inicio", "legend": legend}).status_code == 200
    ui = client.get("/api/companion/now", headers={"Authorization": "Bearer secreto"}).json()["ui"]
    assert ui == {"screen": "search", "text_field": True, "section": "Inicio", "legend": legend}


def test_iphone_voice_does_not_count_as_alexa(public):
    """Siri y el micrófono del control mandan source=iphone: Ajustes no dice que se usó Alexa."""
    client, main = public
    auth = {"Authorization": "Bearer secreto"}
    deps = main.state.deps
    deps.alexa_last = None
    assert client.post("/api/voice", json={"text": "pausa", "source": "iphone"}, headers=auth).status_code == 200
    assert deps.alexa_last is None
    client.post("/api/voice", json={"text": "pausa"}, headers=auth)
    assert deps.alexa_last is not None


def test_iphone_choosing_a_series_opens_its_page_on_the_tv(public, monkeypatch):
    """La lista de «choices» del iPhone: una serie (sin episodio) abre su ficha en la tele, como la voz."""
    client, main = public
    catalog = main.state.catalog
    monkeypatch.setattr(type(catalog), "native_player", property(lambda self: True))
    events = []
    catalog.events.subscribe(events.append)
    r = client.post("/api/stremio/play", json={"kind": "series", "id": "tt0386676", "title": "The Office"},
                    headers={"Authorization": "Bearer secreto"})
    assert r.status_code == 200 and r.json()["opened"] == "title"
    assert {"type": "open-view", "view": {"serie": "tt0386676"}, "message": "Abriendo The Office"} in events


def test_every_voice_request_is_written_down_to_find_what_fails(public, tmp_path):
    """voz.log: qué se dijo, qué entendió Orbital y si salió bien (antes no quedaba rastro de lo que fallaba)."""
    from orbital import voice_log

    client, _ = public
    auth = {"Authorization": "Bearer secreto"}
    client.post("/api/voice", json={"text": "abre hades"}, headers=auth)
    client.post("/api/voice", json={"text": "blablá sin sentido"}, headers=auth)
    entries = voice_log.read()
    assert [e["text"] for e in entries] == ["abre hades", "blablá sin sentido"]
    assert entries[0]["ok"] is True and entries[0]["source"] == "alexa" and entries[0]["ms"] >= 0
    assert entries[1]["ok"] is False


def test_what_alexa_could_not_fit_goes_to_the_console_as_free_text(skill, monkeypatch):
    """«Alexa, pídele a Orbital que por favor ponga Interstellar»: antes caía en «No entendí» sin preguntarle a la consola."""
    sent = []

    def fake_urlopen(req, timeout):
        sent.append(json.loads(req.data))
        return io.BytesIO(json.dumps({"ok": True, "speech": "Poniendo Interstellar."}).encode())

    monkeypatch.setattr(skill.urllib.request, "urlopen", fake_urlopen)
    out = skill.lambda_handler(intent_event("FreeTextIntent", {"query": {"name": "query", "value": "ponga Interstellar"}}))
    assert sent == [{"text": "ponga Interstellar"}]
    assert out["response"]["outputSpeech"]["text"] == "Poniendo Interstellar."
    out = skill.lambda_handler(intent_event("FreeTextIntent", {"query": {"name": "query"}}))
    assert "No entendí" in out["response"]["outputSpeech"]["text"] and len(sent) == 1  # vacío: nada que mandar


def test_a_quick_tunnel_hiccup_is_retried_once(skill, monkeypatch):
    calls = []

    def flaky(req, timeout):
        calls.append(1)
        if len(calls) == 1:
            raise skill.urllib.error.URLError("el túnel despertando")
        return io.BytesIO(json.dumps({"ok": True, "speech": "Abriendo Hades."}).encode())

    monkeypatch.setattr(skill.urllib.request, "urlopen", flaky)
    out = skill.lambda_handler(intent_event("LaunchGameIntent", {"game": {"name": "game", "value": "hades"}}))
    assert out["response"]["outputSpeech"]["text"] == "Abriendo Hades." and len(calls) == 2


def test_the_free_text_intent_is_in_the_model_with_carrier_phrases():
    lm = MODEL["interactionModel"]["languageModel"]
    free = next(i for i in lm["intents"] if i["name"] == "FreeTextIntent")
    assert free["slots"] == [{"name": "query", "type": "AMAZON.SearchQuery"}]
    assert "por favor {query}" in free["samples"] and all("{query}" in s and s != "{query}" for s in free["samples"])


def test_the_catch_all_sends_the_whole_phrase_as_heard(skill, monkeypatch):
    """«Alexa, pausa en Orbital»: lo que no cabe en otro intent cae en el comodín y va entero al intérprete de la consola
    (antes era AMAZON.FallbackIntent y la skill decía «No entendí» sola)."""
    sent = []

    def fake_urlopen(req, timeout):
        sent.append(json.loads(req.data))
        return io.BytesIO(json.dumps({"ok": True, "speech": "En pausa."}).encode())

    monkeypatch.setattr(skill.urllib.request, "urlopen", fake_urlopen)
    snapped = {"resolutionsPerAuthority": [{"status": {"code": "ER_SUCCESS_MATCH"}, "values": [{"value": {"name": "pausa"}}]}]}
    out = skill.lambda_handler(intent_event("CommandIntent", {"command": {"name": "command", "value": "pausa norbital",
                                                                            "resolutions": snapped}}))
    assert sent == [{"text": "pausa norbital"}]  # tal cual se oyó, no el valor de la lista
    assert out["response"]["outputSpeech"]["text"] == "En pausa."


def test_what_alexa_did_not_understand_reaches_the_console_log(skill, orbital):
    out = skill.lambda_handler(intent_event("AMAZON.FallbackIntent"))
    assert orbital[0]["body"] == {"intent": "FallbackIntent", "slots": {}}
    assert out["response"]["shouldEndSession"] is False  # sigue escuchando para que lo vuelvas a decir


def test_the_model_sends_anything_it_does_not_place_to_the_console():
    lm = MODEL["interactionModel"]["languageModel"]
    assert lm["modelConfiguration"]["fallbackIntentSensitivity"]["level"] == "LOW"
    catch_all = next(i for i in lm["intents"] if i["name"] == "CommandIntent")
    assert catch_all["slots"] == [{"name": "command", "type": "ORBITAL_COMMAND"}] and "{command}" in catch_all["samples"]
    values = {v["name"]["value"] for t in lm["types"] if t["name"] == "ORBITAL_COMMAND" for v in t["values"]}
    guide = json.loads((ROOT / "alexa" / "commands.json").read_text(encoding="utf-8"))
    missing = [c["say"] for g in guide["groups"] for c in g["commands"] if c["say"].strip().lower() not in values]
    assert not missing, f"agrega a ORBITAL_COMMAND (le enseña a Alexa cómo suenan las órdenes): {missing}"
