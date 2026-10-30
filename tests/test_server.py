import pytest
from fastapi.testclient import TestClient

from orbital.server import create_app, create_public_app

LOCAL = ("127.0.0.1", 5000)
REMOTE = ("203.0.113.9", 5000)


@pytest.fixture
def make_client(library):
    def make(client=LOCAL):
        return TestClient(create_app(library.config, library), base_url="http://127.0.0.1:8710", client=client)
    return make


@pytest.fixture
def public_foryou(library):
    """«Para ti» por el puerto público (el que usa el iPhone a través del túnel): siempre con token."""
    main = create_app(library.config, library)
    with TestClient(main, base_url="http://127.0.0.1:8710", client=("127.0.0.1", 1)):
        yield TestClient(create_public_app(library.config, main), base_url="https://legion.ts.net",
                          client=("127.0.0.1", 2))


def test_local_access_without_token(make_client):
    with make_client() as c:
        rows = c.get("/api/library").json()["rows"]
        assert rows[0]["title"] == "Steam"
        assert "argv" not in rows[0]["items"][0]  # no se exponen comandos
        assert c.get("/").status_code == 200
        assert c.get("/styles/main.css").headers["cache-control"] == "no-cache"


def test_remote_requires_token(make_client):
    with make_client(REMOTE) as c:
        assert c.get("/api/library").status_code == 401
        assert c.get("/api/library", headers={"Authorization": "Bearer nope"}).status_code == 401
        assert c.get("/api/library", headers={"Authorization": "Bearer secreto"}).status_code == 200


def test_tunnel_on_localhost_requires_token(make_client):
    # cloudflared conecta desde 127.0.0.1 pero añade cabeceras de reenvío.
    with make_client() as c:
        assert c.get("/api/library", headers={"CF-Connecting-IP": "1.2.3.4"}).status_code == 401


def test_foreign_origin_blocked(make_client):
    with make_client() as c:
        r = c.post("/api/launch", json={"id": "steam:367520"}, headers={"Origin": "https://evil.example"})
        assert r.status_code == 403


def test_launch_and_status(make_client, library):
    with make_client() as c:
        assert c.post("/api/launch", json={"id": "steam:367520"}).json()["title"] == "Hollow Knight"
        assert c.get("/api/status").json()["running"]["title"] == "Hollow Knight"
        assert c.post("/api/launch", json={"id": "nada"}).status_code == 404


def test_launching_search_does_not_close_the_running_game(make_client, library):
    """«Buscar» no se lanza: 422 con su mensaje (antes 500) y lo que estaba abierto sigue abierto."""
    with make_client() as c:
        c.post("/api/launch", json={"id": "steam:367520"})
        r = c.post("/api/launch", json={"id": "media:search"})
        assert r.status_code == 422 and "no tiene forma" in r.json()["detail"]
        assert c.get("/api/status").json()["running"]["title"] == "Hollow Knight"
        assert c.post("/api/art-replace", json={"id": "nada", "kind": "cover"}).status_code == 404


def test_voice_endpoint(make_client, library):
    with make_client(REMOTE) as c:
        r = c.post("/api/voice", json={"intent": "LaunchGameIntent", "slots": {"game": "hollow"}},
                   headers={"Authorization": "Bearer secreto"})
        assert r.json() == {"ok": True, "speech": "Abriendo Hollow Knight."}
        assert c.post("/api/voice", json={}, headers={"Authorization": "Bearer secreto"}).status_code == 422


def test_prefs_endpoint(make_client):
    with make_client() as c:
        r = c.post("/api/prefs", json={"id": "steam:367520", "favorite": True})
        assert r.json()["favorite"] is True
        assert c.get("/api/library").json()["rows"][0]["id"] == "favorites"
        c.post("/api/prefs", json={"id": "steam:367520", "hidden": True})
        assert c.get("/api/library").json()["hidden"] == 1
        assert c.post("/api/prefs/unhide-all").json() == {"restored": 1}
        assert c.post("/api/prefs", json={"id": "nada", "favorite": True}).status_code == 404


def test_system_and_alexa_indicator(make_client):
    with make_client(REMOTE) as c:
        auth = {"Authorization": "Bearer secreto"}
        assert c.get("/api/system", headers=auth).json()["alexa_last"] is None
        c.post("/api/voice", json={"text": "abre hades"}, headers=auth)
        assert c.get("/api/system", headers=auth).json()["alexa_last"] > 0


def test_voice_status_says_where_the_last_order_came_from(make_client):
    """Ajustes › Voz › «Qué ha oído la consola»: por dónde llegó la última orden (Alexa, el iPhone y Siri, aquí) y las últimas
    con lo que se dijo y lo que se entendió. Sin eso, «la voz no funciona» no se podía ni ubicar."""
    with make_client(REMOTE) as c:
        auth = {"Authorization": "Bearer secreto"}
        before = c.get("/api/voice/status", headers=auth).json()
        assert before["sources"] == {"alexa": None, "iphone": None, "local": None} and before["recent"] == []
        c.post("/api/voice", json={"text": "abre hades"}, headers=auth)
        c.post("/api/voice", json={"text": "pon pausa", "source": "iphone"}, headers=auth)
        after = c.get("/api/voice/status", headers=auth).json()
        assert after["sources"]["alexa"] > 0 and after["sources"]["iphone"] > 0 and after["sources"]["local"] is None
        assert [e["source"] for e in after["recent"]] == ["iphone", "alexa"]  # la más reciente primero
        assert after["recent"][1]["text"] == "abre hades" and after["recent"][1]["understood"] == "LaunchGameIntent"
        assert "ok" in after["recent"][0] and after["recent"][0]["speech"]


def test_iphone_gets_the_hints_and_its_own_guide(make_client):
    """El iPhone recibe las tres frases del momento con cada respuesta (y por /api/voice/hints antes de hablar); si pregunta
    «¿qué puedo decir?», abre su guía y la tele no se abre sola. Alexa no recibe «hints»."""
    with make_client(REMOTE) as c:
        auth = {"Authorization": "Bearer secreto"}
        queue = c.app.state.bus.subscribe()

        def opened() -> bool:
            seen = []
            while not queue.empty():
                seen.append(queue.get_nowait())
            return any(e.get("type") == "open-guide" for e in seen)
        assert c.get("/api/voice/hints", headers=auth).json() == {"moment": "home", "hints": ["pon The Office", "sigue viendo", "qué sale hoy"]}
        phone = c.post("/api/voice", json={"text": "qué puedo decir", "source": "iphone"}, headers=auth).json()
        assert phone["guide"] is True and phone["hints"] == ["pon The Office", "sigue viendo", "qué sale hoy"]
        assert not opened()
        alexa = c.post("/api/voice", json={"text": "qué puedo decir"}, headers=auth).json()
        assert "hints" not in alexa and opened()


def test_closed_event_reaches_ui(make_client, library):
    with make_client() as c:
        app_bus = c.app.state.bus
        queue = app_bus.subscribe()
        library.sessions.launch("steam:367520")
        library.launcher.finish(60)
        event = c.portal.call(queue.get)
        while event["type"] == "status":  # el estado también llega por aquí
            event = c.portal.call(queue.get)
        assert event["type"] == "closed" and event["title"] == "Hollow Knight"


def test_status_is_pushed_when_something_opens(make_client, library):
    with make_client() as c:
        queue = c.app.state.bus.subscribe()
        library.sessions.launch("steam:367520")
        event = c.portal.call(queue.get)
        while event["type"] != "status" or not event["running"]:
            event = c.portal.call(queue.get)
        assert event["running"]["title"] == "Hollow Knight"
        library.launcher.finish(60)
        while event["type"] != "status" or event["running"]:
            event = c.portal.call(queue.get)
        assert event["running"] is None


def test_diagnostics(make_client, tmp_path):
    with make_client() as c:
        log = tmp_path / "orbital.log"
        log.write_text("INFO todo bien\nWARNING no pude abrir https://torrentio.example/clave-secreta/stream\n",
                       encoding="utf-8")
        c.app.state.deps.log_path = log
        data = c.get("/api/diagnostics").json()
        assert data["library"]["Steam"] >= 2 and "Buscar" not in data["library"] and data["running"] is None
        assert data["problems"] == ["WARNING no pude abrir https://torrentio.example/…"]  # sin la clave


def test_ui_reload(make_client):
    with make_client() as c:
        assert c.post("/api/ui/reload").json() == {"ok": True}


def test_power_rejects_unknown_actions(make_client):
    with make_client() as c:
        assert c.post("/api/power", json={"action": "format-c"}).status_code == 400


def test_ui_reload_only_allows_known_views(make_client):
    with make_client() as c:
        assert c.post("/api/ui/reload", json={"view": {"buscar": "dune", "evil": "x"}}).json() == {"ok": True}


def test_connect_stremio_from_the_console(make_client, library, monkeypatch):
    from orbital.library.stremio_api import StremioError
    seen = []

    def login(email, password):
        seen.append(email)
        if password != "bien":
            raise StremioError("Wrong password")
        return "clave-sesion"

    monkeypatch.setattr(library.stremio_client, "login", login)
    monkeypatch.setattr(library.watch, "link_stremio", lambda key: seen.append(key) or 42)
    with make_client() as c:
        assert c.post("/api/stremio/login", json={"email": "", "password": ""}).status_code == 422
        bad = c.post("/api/stremio/login", json={"email": "yo@x.com", "password": "mal"})
        assert bad.status_code == 401 and "no son correctos" in bad.json()["detail"]
        assert c.post("/api/stremio/login", json={"email": "yo@x.com", "password": "bien"}).json() == {"ok": True, "count": 42}
    assert seen == ["yo@x.com", "yo@x.com", "clave-sesion"]  # se guarda la clave de sesión, nunca la contraseña


def test_setup_status_for_first_use(make_client):
    with make_client() as c:
        status = c.get("/api/setup").json()
        assert {"games", "steam", "emulators", "esde", "stremio", "player", "alexa"} <= set(status)
        assert c.post("/api/settings", json={"welcomed": True}).json()["welcomed"] is True


def test_errors_are_shown_once_a_minute_without_keys():
    import logging

    from orbital.api.live import ProblemNotifier

    seen = []
    handler = ProblemNotifier(seen.append)
    log = logging.getLogger("orbital.watch")
    log.addHandler(handler)
    try:
        log.error("No pude abrir https://torrentio.example/clave-secreta/stream")
        log.error("Otro error en el mismo minuto")
        logging.getLogger("uvicorn").error("ajeno")
    finally:
        log.removeHandler(handler)
    assert len(seen) == 1 and "clave-secreta" not in seen[0]["message"] and "Diagnóstico" in seen[0]["message"]


def test_auto_close_times_can_be_changed_from_orbital(make_client, library):
    from orbital.shell import ConsoleShell

    with make_client() as c:
        assert c.get("/api/settings").json()["game_idle_minutes"] == 60
        assert c.get("/api/settings").json()["tv"] == {"configured": False, "input": "hdmi1"}  # Ajustes › Tele y voz
        assert c.post("/api/settings", json={"game_idle_minutes": 120, "close_previous": False}).status_code == 200
        assert c.post("/api/settings", json={"game_idle_minutes": 7}).status_code == 422
    sessions = ConsoleShell(library).sessions
    assert sessions.game_idle_minutes == 120 and not sessions.close_previous
    assert sessions.video_idle_minutes == library.config.sessions.video_idle_minutes  # lo demás, de config.yaml


def test_folders_lists_each_emulator(make_client):
    with make_client() as c:
        snes = next(e for e in c.get("/api/folders").json()["emulators"] if e["name"] == "Super Nintendo")
    assert snes["games"] == 2 and len(snes["rom_dirs"]) == 1


# --------------------------------------------------------------------- «Para ti» por el puerto público (CEN-18)
def test_foryou_overview_by_tunnel_needs_a_token_and_has_no_games(public_foryou):
    assert public_foryou.get("/api/foryou").status_code == 401
    auth = {"Authorization": "Bearer secreto"}
    data = public_foryou.get("/api/foryou", headers=auth).json()
    assert "mygames" not in [row["id"] for row in data["lists"]]  # el fixture tiene Steam: sin token, ya se vería
    assert not any(row["id"].startswith("rawg:") for row in data["lists"])
    assert not any(item["kind"] == "game" for item in data["mosaic"])


def test_foryou_list_by_tunnel_needs_a_token_and_hides_game_lists(public_foryou):
    auth = {"Authorization": "Bearer secreto"}
    assert public_foryou.get("/api/foryou/list", params={"id": "mygames"}).status_code == 401
    assert public_foryou.get("/api/foryou/list", params={"id": "mygames"}, headers=auth).status_code == 404
    assert public_foryou.get("/api/foryou/list", params={"id": "rawg:new"}, headers=auth).status_code == 404
    ok = public_foryou.get("/api/foryou/list", params={"id": "cinemeta", "kind": "series"}, headers=auth)
    assert ok.status_code == 200 and "items" in ok.json()


def test_foryou_details_and_dismiss_by_tunnel_need_a_token_and_hide_games(public_foryou):
    auth = {"Authorization": "Bearer secreto"}
    assert public_foryou.get("/api/foryou/details", params={"key": "video:tt0386676"}).status_code == 401
    details = public_foryou.get("/api/foryou/details", params={"key": "video:tt0386676"}, headers=auth)
    assert details.status_code == 200
    assert public_foryou.get("/api/foryou/details", params={"key": "rawg:1"}, headers=auth).status_code == 404
    assert public_foryou.get("/api/foryou/details", params={"key": "game:367520"}, headers=auth).status_code == 404
    assert public_foryou.post("/api/foryou/dismiss", json={"key": "video:tt0386676"}).status_code == 401
    assert public_foryou.post("/api/foryou/dismiss", json={"key": "video:tt0386676"}, headers=auth).json() == {"ok": True}
    assert public_foryou.post("/api/foryou/dismiss", json={"key": "nope"}, headers=auth).status_code == 422


def test_the_interface_input_trace_lands_in_entrada_log(library, tmp_path):
    """Diagnóstico: lo que llega del mando a la interfaz y lo que se disparó, para encontrar toques repetidos."""
    import json as _json

    from fastapi.testclient import TestClient

    from orbital import input_log
    from orbital.server import create_app

    with TestClient(create_app(library.config, library), base_url="http://127.0.0.1:8710", client=("127.0.0.1", 5000)) as c:
        entries = [{"src": "pad", "i": 0, "pressed": [1], "focus": False}, {"src": "action", "from": "pad", "action": "back"}]
        assert c.post("/api/ui/trace", json={"entries": entries}).json() == {"ok": True}
    lines = [_json.loads(x) for x in input_log.default_path().read_text(encoding="utf-8").splitlines()]
    assert [x["src"] for x in lines] == ["pad", "action"] and lines[0]["from"] == "ui" and lines[0]["focus"] is False


def test_ui_says_whether_it_reads_the_controller_and_learns_if_the_server_sees_one(make_client):
    """Quieta, la interfaz suelta el mando del navegador y el primer botón le llega del servidor (shell.forward_to_ui)."""
    with make_client() as c:
        shell = c.app.state.shell
        assert c.post("/api/ui/pad", json={"listening": False}).json() == {"xinput": False, "others": False}  # sin mandos
        assert shell.ui_pad is False
        c.post("/api/ui/pad", json={"listening": True})
        assert shell.ui_pad is True


def test_a_controller_the_server_cannot_read_keeps_the_ui_reading_and_wakes_it(make_client):
    """Un mando de PlayStation no pasa por XInput: la interfaz quieta no debe soltar el suyo y, si ya lo soltó, el servidor
    la despierta (antes ese mando no hacía nada hasta tocar otra cosa)."""
    from orbital.gamepad import GamepadWatcher

    with make_client() as c:
        shell = c.app.state.shell
        watcher = GamepadWatcher(lambda event: None)
        watcher._joysticks = lambda: [(0x17EF, 0x61EB), (0x054C, 0x05C4)]  # Legion (XInput) + DualShock 4
        watcher.devices = {0: (0x17EF, 0x61EB)}
        shell.gamepad = watcher
        assert c.post("/api/ui/pad", json={"listening": False}).json()["others"] is True
        assert watcher.watch_others is True
        c.post("/api/ui/pad", json={"listening": True})
        assert watcher.watch_others is False
