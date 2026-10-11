import pytest

from orbital.shell import ConsoleShell


@pytest.fixture(autouse=True)
def no_steam_game(monkeypatch):
    # Que las pruebas no dependan de si Steam tiene un juego abierto en esta máquina.
    monkeypatch.setattr(ConsoleShell, "steam_running", staticmethod(lambda: False))

ORBITAL, GAME, DESKTOP_APP, LEGION, DESKTOP = 1, 2, 3, 4, 5


class FakeWindows:
    """Ventanas falsas: hwnd -> (título, pid, exe)."""

    def __init__(self):
        self.windows = {
            ORBITAL: ("Orbital - [InPrivate] - Microsoft Edge", 10, "msedge.exe"),
            GAME: ("Eden | Mario Party Superstars", 20, "eden.exe"),
            DESKTOP_APP: ("Bloc de notas", 30, "notepad.exe"),
            LEGION: ("Legion Space", 40, "legionspace.exe"),
            DESKTOP: ("Program Manager", 50, "explorer.exe"),
        }
        self.fg = GAME
        self.minimized = []
        self.suspended = set()
        self.resumed = []

    def foreground(self): return self.fg
    def is_window(self, h): return h in self.windows
    def title(self, h): return self.windows.get(h, ("", 0, ""))[0]
    def pid_of(self, h): return self.windows.get(h, ("", 0, ""))[1]
    def exe_name(self, pid): return next((w[2] for w in self.windows.values() if w[1] == pid), "")
    def process_tree(self, pid): return {pid, 20} if pid == 99 else {pid}  # launch-eden.cmd (99) -> eden (20)
    def main_window(self, pids): return next((h for h, w in self.windows.items() if w[1] in pids), 0)
    def minimize(self, h): self.minimized.append(h)
    def suspend(self, pids): self.suspended |= set(pids); return len(pids)
    def resume(self, pids): self.suspended -= set(pids); self.resumed.append(set(pids)); return len(pids)
    def app_windows(self): return [{"hwnd": h, "title": t, "exe": e} for h, (t, _, e) in self.windows.items()]

    def focus(self, h):
        self.fg = h
        return True


class FakeKiosk:
    def __init__(self, win):
        self.win = win

    def open(self):
        self.win.fg = ORBITAL
        return True


class FakeLauncher:
    def __init__(self, running=None):
        self.running = running
        self.stopped = False

    def status(self): return self.running

    def stop(self, force=False):
        self.forced = force
        self.stopped = self.running is not None and self.running.get("managed")
        return self.stopped


class FakeOverlay:
    def __init__(self):
        self.calls = []

    def show(self, title, detail, ms): self.calls.append(("show", title, detail))
    def closing(self, title): self.calls.append(("closing", title))
    def hide(self, delay_ms=0): self.calls.append(("hide",))


class FakePlayer:
    def __init__(self):
        self.calls = []
        self.remote = self

    def pause(self): self.calls.append("pause")
    def show_progress(self): self.calls.append("progress")
    def update(self, buttons, now): self.calls.append(("buttons", buttons))


class FakeCatalog:
    def __init__(self, running=None):
        self.launcher = FakeLauncher(running)
        self.player = FakePlayer()


def make(running=None):
    win = FakeWindows()
    overlay = FakeOverlay()
    shell = ConsoleShell(FakeCatalog(running), FakeKiosk(win), win=win, overlay=overlay)
    return shell, win, overlay


MANAGED = {"title": "Mario Party Superstars", "managed": True, "runner": "Eden", "pid": 99}


def test_home_goes_to_orbital_and_back():
    shell, win, _ = make(MANAGED)
    shell.home()
    assert win.fg == ORBITAL
    shell.home()
    assert win.fg == GAME  # de regreso a la misma ventana


def test_home_back_finds_game_by_process_tree():
    shell, win, _ = make(MANAGED)
    win.fg = ORBITAL  # Orbital abrió el juego y nunca vimos su ventana al frente
    shell.home()
    assert win.fg == GAME  # launch-eden.cmd -> eden.exe -> su ventana


def test_home_in_orbital_without_game_stays():
    shell, win, _ = make(None)
    win.fg = ORBITAL
    shell.home()
    assert win.fg == ORBITAL


def test_hold_shows_overlay_in_game_and_closes_hard():
    shell, win, overlay = make(MANAGED)
    shell.hold_start()
    assert win.fg == GAME  # el aviso va encima del juego: no sales de él
    assert overlay.calls == [("show", "Mantén para cerrar Eden", "Mario Party Superstars")]
    shell.hold_complete()
    assert overlay.calls[1:] == [("closing", "Cerrando Eden"), ("hide",)]
    assert shell.catalog.launcher.stopped and shell.catalog.launcher.forced  # de golpe, sin "¿Seguro?"


def test_hold_released_early_keeps_playing():
    shell, win, overlay = make(MANAGED)
    shell.hold_start()
    shell.hold_cancel()
    assert overlay.calls[-1] == ("hide",) and win.fg == GAME and not shell.catalog.launcher.stopped


def test_hold_also_works_with_emulator_opened_elsewhere():
    shell, win, overlay = make(None)  # Eden abierto desde ES-DE, no desde Orbital
    shell.hold_start()
    assert overlay.calls[0][2] == "Eden | Mario Party Superstars" and shell.hold["pid"] == 20


def test_hold_ignored_in_orbital_and_in_other_apps():
    shell, win, overlay = make(MANAGED)
    win.fg = ORBITAL
    shell.hold_start()  # en Orbital, Select/Start son el menú
    shell2, win2, overlay2 = make(None)
    win2.fg = DESKTOP_APP
    shell2.hold_start()  # el Bloc de notas no es un juego
    assert overlay.calls == [] and overlay2.calls == [] and win2.fg == DESKTOP_APP


def test_legion_l_one_tap_goes_to_orbital_and_back():
    shell, win, _ = make(MANAGED)
    win.fg = LEGION
    shell.check_legion(LEGION, previous=GAME, now=100)
    assert win.minimized == [LEGION] and win.fg == ORBITAL and win.suspended == {20}  # como Home, con pausa
    win.fg = LEGION
    shell.check_legion(LEGION, previous=ORBITAL, now=110)
    assert win.fg == GAME and not win.suspended  # desde Orbital, de vuelta al juego


def test_legion_l_twice_closes_the_game():
    shell, win, overlay = make(MANAGED)
    notes = []
    shell.catalog._notify = notes.append
    win.fg = LEGION
    shell.check_legion(LEGION, previous=GAME, now=100)
    assert notes and "otra vez para cerrar" in notes[0]["message"]
    win.fg = LEGION
    shell.check_legion(LEGION, previous=ORBITAL, now=101.2)  # segundo toque: ya estabas en Orbital
    assert shell.catalog.launcher.stopped and shell.catalog.launcher.forced and not win.suspended
    assert win.fg == ORBITAL and ("closing", "Cerrando Eden") in overlay.calls
    assert win.minimized == [LEGION, LEGION]  # Legion Space nunca se queda


def test_legion_l_twice_but_slow_is_just_two_taps():
    shell, win, _ = make(MANAGED)
    win.fg = LEGION
    shell.check_legion(LEGION, previous=GAME, now=100)
    win.fg = LEGION
    shell.check_legion(LEGION, previous=ORBITAL, now=105)
    assert win.fg == GAME and not shell.catalog.launcher.stopped


def test_open_windows_hides_orbital_and_only_focuses_listed():
    shell, win, _ = make(None)
    names = [w["app"] for w in shell.open_windows()]
    assert "Edge" not in names and names[:2] == ["Eden", "Notepad"]  # Orbital (Edge) no aparece
    assert shell.focus_window(DESKTOP_APP) and win.fg == DESKTOP_APP
    assert not shell.focus_window(12345)  # un identificador que no está en la lista: nunca


def test_hold_closes_steam_game_in_front(monkeypatch):
    shell, win, overlay = make(None)
    win.windows[DESKTOP_APP] = ("Hades II", 30, "hades2.exe")
    win.fg = DESKTOP_APP
    monkeypatch.setattr(ConsoleShell, "steam_running", staticmethod(lambda: True))
    shell.hold_start()
    assert shell.hold == {"title": "Hades II", "runner": None, "pid": 30}
    assert overlay.calls[0][1] == "Mantén para cerrar el juego"
    win.windows[DESKTOP_APP] = ("Steam", 30, "steamwebhelper.exe")  # Steam mismo: nunca
    shell.hold = None
    shell.hold_start()
    assert shell.hold is None


def test_remote_only_drives_stremio():
    shell, win, _ = make(None)
    sent = []
    win.windows[DESKTOP_APP] = ("Stremio", 30, "stremio-shell-ng.exe")
    win.fg = GAME  # Eden al frente: el mando es del emulador
    shell.on_buttons(0, 0x1000, 1.0, send=sent.append)
    assert sent == []
    win.fg = DESKTOP_APP  # Stremio al frente: A = Espacio (pausa)
    shell.on_buttons(0, 0, 2.0, send=sent.append)
    shell.on_buttons(0, 0x1000, 2.1, send=sent.append)
    assert sent == [0x20]


def test_home_on_desktop_opens_orbital_and_stays():
    shell, win, _ = make(None)
    win.fg = DESKTOP  # escritorio (también tras "Salir al escritorio")
    shell.home()
    assert win.fg == ORBITAL
    shell.home()  # sin juego abierto: Orbital no "regresa" al escritorio
    assert win.fg == ORBITAL


def test_home_from_game_still_returns_after_passing_by_desktop():
    shell, win, _ = make(MANAGED)
    shell.home()  # juego -> Orbital
    win.fg = DESKTOP  # el usuario se asoma al escritorio
    shell.home()  # escritorio -> Orbital (no reemplaza al juego como destino)
    assert win.fg == ORBITAL
    shell.home()
    assert win.fg == GAME


def test_home_pauses_the_emulator_and_resumes_on_return(tmp_path):
    shell, win, _ = make(MANAGED)
    shell.pause_file = tmp_path / "paused.json"
    shell.home()  # Eden al frente -> Orbital, Eden congelado
    assert win.fg == ORBITAL and win.suspended == {20} and shell.is_paused
    assert shell.pause_file.read_text() == "[20]"
    shell.home()  # de vuelta: primero se descongela
    assert win.fg == GAME and not win.suspended and not shell.is_paused


def test_pause_never_freezes_stremio_or_other_apps():
    shell, win, _ = make(None)
    win.windows[DESKTOP_APP] = ("Stremio", 30, "stremio-shell-ng.exe")
    win.fg = DESKTOP_APP
    shell.home()
    assert win.suspended == set()


def test_crash_recovery_resumes_frozen_game(tmp_path):
    shell, win, _ = make(None)
    shell.pause_file = tmp_path / "paused.json"
    shell.pause_file.write_text("[20, 21]")
    shell.recover_paused()
    assert win.resumed == [{20, 21}] and not shell.pause_file.exists()


def test_closing_a_paused_game_unfreezes_first():
    shell, win, _ = make(MANAGED)
    shell.home()
    shell.hold = {"title": "x", "runner": "Eden", "pid": None}
    shell.stop_game()
    assert not win.suspended and shell.catalog.launcher.stopped


def test_orbital_player_pauses_normally_and_gets_the_gamepad():
    player_running = {"title": "Interstellar", "managed": True, "runner": "Reproductor", "pid": 30}
    shell, win, _ = make(player_running)
    win.windows[DESKTOP_APP] = ("Interstellar", 30, "mpv.exe")
    win.fg = DESKTOP_APP
    sent = []
    shell.on_buttons(0, 0x1000, 1.0, send=sent.append)
    assert shell.player.calls == [("buttons", 0x1000)] and sent == []  # comandos a mpv, no teclas
    shell.home()
    assert win.fg == ORBITAL and win.suspended == set()  # pausa de video, no congelar
    assert shell.player.calls[-1] == "pause"
    shell.home()
    assert win.fg == DESKTOP_APP and shell.player.calls[-1] == "progress"


def test_opening_something_else_closes_the_previous_game():
    shell, win, _ = make(dict(MANAGED, id="eden:mario"))
    shell.close_previous("steam:1")
    assert shell.catalog.launcher.stopped and shell.catalog.launcher.forced
    shell, win, _ = make(dict(MANAGED, id="eden:mario"))
    shell.close_previous("eden:mario")  # el mismo juego ("Continuar"): no se cierra
    assert not shell.catalog.launcher.stopped


def test_frozen_game_closes_after_the_limit(tmp_path):
    shell, win, _ = make(MANAGED)
    notes = []
    shell.catalog._notify = notes.append
    shell.home()  # congelado
    start = shell.paused_since
    assert not shell.check_idle(start + 59 * 60)
    assert shell.check_idle(start + 60 * 60)
    assert shell.catalog.launcher.stopped and not shell.is_paused and not win.suspended  # se descongela para cerrar
    assert notes and "llevaba 60 min" in notes[0]["message"]
