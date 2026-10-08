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


def test_corrupt_state_starts_fresh(tmp_path):
    path = tmp_path / "state.json"
    path.write_text("{no es json")
    assert State(path).recent() == []


def test_recent_favorite_hidden_rows(library):
    library.launch("steam:1145360")
    library.launch("steam:367520")
    rows = {r["id"]: r for r in library.grouped()}
    assert [i["title"] for i in rows["recent"]["items"]] == ["Hollow Knight", "Hades"]
    library.set_prefs("steam:367520", favorite=True, hidden=False)
    assert [i["title"] for i in library.grouped()[1]["items"]] == ["Hollow Knight"]
    library.set_prefs("steam:1145360", hidden=True)
    assert library.find("hades") is None and library.hidden_count() == 1
    assert "Hades" not in [i["title"] for r in library.grouped() for i in r["items"]]


def test_session_end_records_time_and_notifies(library):
    events = []
    library.listeners.append(events.append)
    library.launch("steam:367520")
    library.launcher.finish(1800)
    assert library.describe(library.get("steam:367520"))["playtime"] == 1800
    assert events == [{"type": "closed", "id": "steam:367520", "title": "Hollow Knight", "seconds": 1800}]


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
