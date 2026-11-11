"""F1 · el contrato TV ↔ iPhone escrito con respuestas de verdad.

Cada caso llama, con datos de demostración, a una ruta del puerto público que usa la app compañera y guarda lo que
contestó en `tests/fixtures/contract/<nombre>.json` (petición, estado y respuesta). El lado Swift decodifica esos mismos
archivos: si la TV cambia la forma de una respuesta, esta prueba falla hasta que se regeneren a propósito con

    ORBITAL_UPDATE_CONTRACT=1 python -m pytest -q tests/test_contract_fixtures.py

y el cambio queda a la vista en el diff (y en el lado Swift, que también los lee). Lo que cambia en cada corrida (fechas,
ids, llaves, la versión de Orbital, rutas de la carpeta temporal) se normaliza para que el archivo sea estable.
"""

from __future__ import annotations

import json
import os
import re
from pathlib import Path

import pytest
from fastapi.testclient import TestClient
from test_companion import _play_episode, _play_movie
from test_foryou import stremio_title

from orbital import companion, rd_requests
from orbital.library import realdebrid
from orbital.server import create_app, create_public_app

CONTRACT_DIR = Path(__file__).parent / "fixtures" / "contract"
UPDATE = os.environ.get("ORBITAL_UPDATE_CONTRACT") == "1"
TUNNEL = {"Authorization": "Bearer secreto"}

# Llaves cuyo valor cambia en cada corrida: se guardan como «<llave>» (si no son None).
VOLATILE = {"tv_id", "device_id", "version", "code", "expires", "expires_at", "started", "seen", "last_seen",
            "added", "at", "created", "updated", "updated_at", "paired", "paired_at", "since_ts", "time", "when",
            "ts", "saved_at", "fetched_at", "id_upgrade", "revision_at", "watched_at", "last_used", "rev_at"}
FIXED = {"days": 30}  # cuenta regresiva que cambia cada día
STAMP = re.compile(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:?\d{2})?")


class User:
    def __init__(self, token, opener=None):
        self.token = token

    def user(self):
        return {"id": 7, "username": "fer", "type": "premium", "expiration": "2099-11-21T18:00:00.000Z"}


def normalize(value, tmp: str, key: str = ""):
    if isinstance(value, dict):
        return {k: normalize(v, tmp, k) for k, v in sorted(value.items())}
    if isinstance(value, list):
        return [normalize(v, tmp) for v in value]
    if key in FIXED and value is not None:
        return FIXED[key]
    stable = (key == "version" and isinstance(value, int)) or (key == "code" and isinstance(value, str)
                                                               and re.fullmatch(r"[a-z_]+", value))
    if key in VOLATILE and value is not None and not isinstance(value, bool) and not stable:
        # «version» entera es de un formato (no la de Orbital); un «code» en minúsculas es un código de error, no uno
        # de emparejar.
        # Mismo tipo que el de verdad (el lado Swift decodifica estos archivos): texto «<llave>», números fijos.
        return f"<{key}>" if isinstance(value, str) else type(value)(1_700_000_000)
    if isinstance(value, str):
        value = value.replace(tmp, "<tmp>").replace(tmp.replace("\\", "/"), "<tmp>")
        value = re.sub(r"([?&])v=\d+", r"\1v=<mtime>", value)  # la fecha del archivo en las direcciones de arte
        return STAMP.sub("<fecha>", value)
    return value


@pytest.fixture
def apps(library, monkeypatch, tmp_path):
    from orbital import gamepad, health, memory, quick, system
    monkeypatch.setattr(quick, "battery", lambda: None)  # la CI de Windows podría tener una batería de verdad
    monkeypatch.setattr(rd_requests.RdRequests, "_torrentio_token", lambda self: "TORRENTIOKEY3F2A")
    monkeypatch.setattr(rd_requests.RdRequests, "watch", lambda self: None)
    monkeypatch.setattr(realdebrid, "RealDebrid", User)
    monkeypatch.setattr(companion.alexa_setup, "tailscale_url", lambda: "https://legion.ts.net")
    monkeypatch.setattr(memory, "usage", lambda limit=6, protect_pids=None: [])
    monkeypatch.setattr(health, "free_ram_mb", lambda: 4096)
    monkeypatch.setattr(system, "wifi", lambda: None)
    monkeypatch.setattr(gamepad, "connected_controllers", list)
    main = create_app(library.config, library)
    main.state.play_stremio = lambda body: {"ok": True}  # «Ver en la TV» sin abrir el reproductor de verdad
    local = TestClient(main, base_url="http://127.0.0.1:8710", client=("127.0.0.1", 1))
    public = TestClient(create_public_app(library.config, main), base_url="https://legion.ts.net", client=("127.0.0.1", 2))
    with local:
        yield local, public, main, library, str(tmp_path)


def pair(local, public, main, name="iPhone de Fernando", platform="iphone") -> dict:
    got = public.post("/api/devices/pair", json={"code": main.state.devices.code(), "name": name, "platform": platform})
    assert got.status_code == 200
    return got.json()


def check(name: str, record: dict, tmp: str) -> None:
    path = CONTRACT_DIR / f"{name}.json"
    text = json.dumps(record, ensure_ascii=False, indent=2, sort_keys=True) + "\n"  # la petición la escribe la prueba
    if UPDATE:
        CONTRACT_DIR.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        return
    assert path.exists(), f"Falta {path.name}: corre ORBITAL_UPDATE_CONTRACT=1 python -m pytest {__file__}"
    saved = path.read_text(encoding="utf-8")
    assert json.loads(saved) == json.loads(text), (
        f"La respuesta de {record['request']['method']} {record['request']['path']} cambió de forma: si es a propósito, "
        f"regenera con ORBITAL_UPDATE_CONTRACT=1 y avisa al lado Swift (tests/fixtures/contract/{path.name})")


def call(client, name, method, path, tmp, headers=TUNNEL, params=None, body=None) -> dict:
    response = client.request(method, path, headers=headers, params=params, json=body)
    record = {"request": {"method": method, "path": path, **({"query": params} if params else {}),
                          **({"body": body} if body is not None else {})},
              "status": response.status_code, "response": normalize(response.json(), tmp)}
    check(name, record, tmp)
    return record["response"]


def test_every_capability_points_at_routes_that_exist(apps):
    _, public, *_ = apps
    routes = {(method, route.path) for route in public.app.routes for method in getattr(route, "methods", ()) or ()}
    for name, needed in companion.CAPABILITIES.items():
        assert re.fullmatch(r"[a-z_]+", name)
        for method, path in needed:
            assert (method, path) in routes, f"{name}: {method} {path} no existe en el puerto público"


def test_ping_and_companion_say_the_contract_version_and_what_the_tv_can_do(apps):
    _, public, _, _, tmp = apps
    ping = call(public, "ping", "GET", "/api/ping", tmp)
    keys = call(public, "companion", "GET", "/api/companion", tmp)
    for got in (ping, keys):
        assert got["api"] == companion.API_VERSION == 1
        assert got["capabilities"] == sorted(companion.CAPABILITIES)
    assert ping["ok"] is True and ping["service"] == "orbital"  # lo de antes sigue igual (Alexa lo busca)
    assert keys["pairing"] == 2 and "tv_id" in keys


def test_now_playing_shapes(apps):
    _, public, _, library, tmp = apps
    call(public, "companion_now", "GET", "/api/companion/now", tmp)
    _play_movie(library)
    call(public, "companion_now_movie", "GET", "/api/companion/now", tmp)
    call(public, "companion_player_toggle", "POST", "/api/companion/player", tmp, body={"action": "toggle"})


def test_now_playing_an_episode(apps):
    _, public, _, library, tmp = apps
    _play_episode(library)
    call(public, "companion_now_episode", "GET", "/api/companion/now", tmp)


def test_player_without_anything_open_is_409_in_words(apps):
    _, public, _, _, tmp = apps
    got = call(public, "companion_player_409", "POST", "/api/companion/player", tmp, body={"action": "toggle"})
    assert "detail" in got


def test_remote_and_console_shapes(apps):
    _, public, _, _, tmp = apps
    call(public, "companion_input", "POST", "/api/companion/input", tmp, body={"action": "select"})
    call(public, "companion_text", "POST", "/api/companion/text", tmp, body={"text": "hola", "submit": False})
    call(public, "companion_console", "GET", "/api/companion/console", tmp)
    call(public, "companion_game_409", "POST", "/api/companion/game", tmp, body={"action": "resume"})
    call(public, "companion_inbox_ack", "POST", "/api/companion/inbox/ack", tmp, body={"ids": ["nada"]})


def test_sync_shapes(apps):
    _, public, _, _, tmp = apps
    call(public, "companion_choices", "POST", "/api/companion/choices", tmp,
         body={"since": 0, "changes": {"tt0386676": {"audio": "es", "base_rev": 0}}})
    call(public, "companion_resume", "POST", "/api/companion/resume", tmp,
         body={"changes": {}, "want": ["tt0386676"]})


def test_foryou_shapes(apps):
    _, public, _, library, tmp = apps
    # Títulos de demostración (lo que Orbital ya trajo de Stremio y lo popular de Cinemeta) para que las listas y el
    # mosaico lleven ítems con su forma de verdad, no listas vacías.
    library.store.replace_source("stremio", [
        stremio_title("tt0903747", "Breaking Bad", continue_=True, video_id="tt0903747:2:6", last=5),
        stremio_title("tt1375666", "Inception", kind="movie", last=9)])
    library.store.replace_source("cinemeta", [stremio_title(f"tt{900 + i}", f"Popular {i}", kind=("movie", "series")[i % 2],
                                                            source="cinemeta") for i in range(4)])
    call(public, "foryou", "GET", "/api/foryou", tmp)
    call(public, "foryou_list", "GET", "/api/foryou/list", tmp, params={"id": "cinemeta", "kind": "series"})
    call(public, "foryou_list_continue", "GET", "/api/foryou/list", tmp, params={"id": "continue"})
    call(public, "foryou_details", "GET", "/api/foryou/details", tmp, params={"key": "video:tt0386676"})
    call(public, "foryou_dismiss", "POST", "/api/foryou/dismiss", tmp, body={"key": "video:tt0386676"})


def test_voice_and_play_shapes(apps):
    _, public, _, _, tmp = apps
    call(public, "voice", "POST", "/api/voice", tmp, body={"text": "abre hades", "source": "iphone"})
    call(public, "voice_hints", "GET", "/api/voice/hints", tmp)
    call(public, "stremio_play", "POST", "/api/stremio/play", tmp,
         body={"kind": "series", "id": "tt0386676", "video_id": "tt0386676:2:5", "title": "The Office"})


def test_device_shapes(apps):
    local, public, main, _, tmp = apps
    paired = pair(local, public, main)
    record = {"request": {"method": "POST", "path": "/api/devices/pair",
                          "body": {"code": "<code>", "name": "iPhone de Fernando", "platform": "iphone"}},
              "status": 200, "response": normalize({**paired, "key": "<key>"}, tmp)}  # la llave nueva, al azar
    check("devices_pair", record, tmp)
    key = {"Authorization": f"Bearer {paired['key']}"}
    call(public, "devices", "GET", "/api/devices", tmp, headers=key)
    call(public, "devices_invite", "POST", "/api/devices/invite", tmp, headers=key, body={"platform": "ipad"})
    call(public, "realdebrid", "GET", "/api/realdebrid", tmp, headers=key)
    call(public, "realdebrid_requests", "GET", "/api/realdebrid/requests", tmp, headers=key)
    call(public, "addons", "GET", "/api/addons", tmp, headers=key)
    call(public, "devices_key_required", "GET", "/api/addons", tmp)  # el token del túnel ya no basta
