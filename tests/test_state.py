import sys
import time

from orbital.launcher import Launcher
from orbital.state import State
from orbital.system import parse_netsh


def test_state_persists(tmp_path):
    path = tmp_path / "state.json"
    s = State(path)
    s.record_launch("a", now=100)
    s.record_launch("b", now=200)
    s.record_session("a", 3600)
    s.record_session("a", 5)  # demasiado corta: no cuenta
    s.set_pref("a", "favorite", True)
    s.set_pref("b", "hidden", True)
    again = State(path)
    assert again.recent() == ["b", "a"]
    assert again.history("a") == {"playtime": 3600, "launches": 1, "last_played": 100}
    assert again.prefs("a") == {"favorite": True}
    assert again.unhide_all() == 1 and State(path).prefs("b") == {}


def test_opened_rows_are_capped_keeping_the_latest(tmp_path, monkeypatch):
    """«opened» crecía sin tope en state.json (cada fila nueva sumaba para siempre)."""
    from orbital import state as state_module

    monkeypatch.setattr(state_module, "MAX_OPENED", 3)
    path = tmp_path / "state.json"
    s = State(path)
    for i, row in enumerate(["a", "b", "c", "d"]):
        s.mark_opened(row, now=100 + i)
    s.mark_opened("b", now=200)  # volver a entrar la hace reciente
    s.mark_opened("e", now=201)
    again = State(path)
    assert [again.opened(r) for r in "abcde"] == [0, 200, 0, 103, 201]


def test_corrupt_state_starts_fresh(tmp_path):
    path = tmp_path / "state.json"
    path.write_text("{no es json")
    assert State(path).recent() == []


def test_recent_favorite_hidden_rows(library):
    library.sessions.launch("steam:1145360")
    library.sessions.launch("steam:367520")
    rows = {r["id"]: r for r in library.grouped()}
    assert [i["title"] for i in rows["recent"]["items"]] == ["Hollow Knight", "Hades"]
    library.set_prefs("steam:367520", favorite=True, hidden=False)
    assert [i["title"] for i in {r["id"]: r for r in library.grouped()}["favorites"]["items"]] == ["Hollow Knight"]
    jump = {r["id"]: r for r in library.grouped()}["jump"]["items"]  # Inicio: lo último, lo abierto primero
    assert [i["title"] for i in jump] == ["Hollow Knight", "Hades"] and jump[0].get("live")
    library.set_prefs("steam:1145360", hidden=True)
    assert library.find("hades") is None and library.hidden_count() == 1
    assert "Hades" not in [i["title"] for r in library.grouped() for i in r["items"]]


def test_session_end_records_time_and_notifies(library):
    events = []
    library.listeners.append(events.append)
    library.sessions.launch("steam:367520")
    library.launcher.finish(1800)
    assert library.describe(library.get("steam:367520"))["playtime"] == 1800
    assert events == [{"type": "closed", "id": "steam:367520", "title": "Hollow Knight", "seconds": 1800,
                      "crashed": False, "kind": "steam"}]


def test_quick_close_is_a_failure_unless_the_game_was_already_open(library):
    """Un juego de Steam que ya estaba abierto (Steam solo lo trajo al frente) y se cierra pronto no
    es «no pudo abrir»; uno recién abierto que se cierra solo a los segundos, sí (y dice que es de Steam)."""
    events = []
    library.listeners.append(events.append)
    library.sessions.launch("steam:367520")
    library.launcher.finish(5)
    assert events[-1]["crashed"] and events[-1]["kind"] == "steam"
    library.launcher.last_was_already_open = True
    library.sessions.launch("steam:367520")
    library.launcher.finish(5)
    assert not events[-1]["crashed"]


def test_launcher_watches_real_process():
    done = []
    launcher = Launcher(on_exit=lambda *args: done.append(args))
    proc = launcher.run([sys.executable, "-c", "pass"])
    launcher.track("x", "Prueba", proc)
    for _ in range(50):
        if done:
            break
        time.sleep(0.05)
    assert done and done[0][:2] == ("x", "Prueba")
    assert launcher.status() is None


def test_parse_netsh_any_language():
    es = "    Nombre                 : Wi-Fi\n    SSID                   : MiCasa\n    BSSID                  : aa:bb\n    Señal                 : 82%\n"
    assert parse_netsh(es) == {"signal": 82, "ssid": "MiCasa"}
    assert parse_netsh("No hay interfaces") is None


def test_steam_game_that_never_starts_is_not_running_forever(monkeypatch):
    from orbital import launcher as launcher_mod

    monkeypatch.setattr(launcher_mod, "steam_running_appid", lambda: 0)  # Steam abierto, juego no
    lau = launcher_mod.Launcher()
    lau.STEAM_START_TIMEOUT, lau.POLL = 0.05, 0.01
    running = launcher_mod.Running("steam:1", "Be My Horde", None)
    lau.current = running
    lau._watch_steam(running, 1)
    assert lau.status() is None


def test_new_games_are_only_the_ones_that_arrive_later():
    from orbital.state import State

    state = State()
    state.mark_seen(["a", "b"], now=100)
    assert state.first_seen("a") == 0  # lo que ya tenías al estrenar la función no es "nuevo"
    state.mark_seen(["a", "b", "c"], now=200)
    assert state.first_seen("c") == 200 and state.first_seen("a") == 0


def test_opening_a_console_is_remembered(tmp_path):
    from orbital.state import State

    state = State(tmp_path / "s.json")
    assert state.opened("steam") == 0
    state.mark_opened("steam", now=300)
    assert State(tmp_path / "s.json").opened("steam") == 300


def test_cancelling_a_launch_does_not_count_as_played(tmp_path):
    """B en la pantalla de carga: el juego no pasa a «Jugaste hace 2 min» ni sube al Inicio."""
    path = tmp_path / "state.json"
    s = State(path)
    s.record_launch("viejo", now=100)
    before = s.record_launch("viejo", now=500)
    s.undo_launch("viejo", before)
    assert State(path).history("viejo") == {"playtime": 0, "launches": 1, "last_played": 100}
    never = s.record_launch("nuevo", now=600)
    s.undo_launch("nuevo", never)
    assert State(path).history("nuevo") == {} and "nuevo" not in State(path).recent()


def test_not_today_survives_a_restart_and_expires(tmp_path):
    """«Hoy no» en ¿Qué vemos? de la TV: antes se perdía al reiniciar Orbital."""
    path = tmp_path / "state.json"
    State(path).skip_today("tt0903747", now=1000)
    assert State(path).skipped(24 * 3600, now=1000 + 3600) == {"tt0903747"}
    assert State(path).skipped(24 * 3600, now=1000 + 25 * 3600) == set()
    assert State(path).skipped(24 * 3600, now=1000) == set()  # ya se olvidó y se guardó así
