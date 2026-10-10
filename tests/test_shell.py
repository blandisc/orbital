from orbital.shell import ConsoleShell

ORBITAL, GAME, DESKTOP_APP, LEGION = 1, 2, 3, 4


class FakeWindows:
    """Ventanas falsas: hwnd -> (título, pid, exe)."""

    def __init__(self):
        self.windows = {
            ORBITAL: ("Orbital - [InPrivate] - Microsoft Edge", 10, "msedge.exe"),
            GAME: ("Eden | Mario Party Superstars", 20, "eden.exe"),
            DESKTOP_APP: ("Bloc de notas", 30, "notepad.exe"),
            LEGION: ("Legion Space", 40, "legionspace.exe"),
        }
        self.fg = GAME
        self.minimized = []

    def foreground(self): return self.fg
    def is_window(self, h): return h in self.windows
    def title(self, h): return self.windows.get(h, ("", 0, ""))[0]
    def pid_of(self, h): return self.windows.get(h, ("", 0, ""))[1]
    def exe_name(self, pid): return next((w[2] for w in self.windows.values() if w[1] == pid), "")
    def process_tree(self, pid): return {pid, 20} if pid == 99 else {pid}  # launch-eden.cmd (99) -> eden (20)
    def main_window(self, pids): return next((h for h, w in self.windows.items() if w[1] in pids), 0)
    def minimize(self, h): self.minimized.append(h)

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


class FakeCatalog:
    def __init__(self, running=None):
        self.launcher = FakeLauncher(running)


def make(running=None):
    win = FakeWindows()
    events = []
    shell = ConsoleShell(FakeCatalog(running), FakeKiosk(win), events.append, win=win)
    return shell, win, events


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


def test_hold_select_start_asks_and_resume_returns_to_game():
    shell, win, events = make(MANAGED)
    shell.hold_start()
    assert win.fg == ORBITAL and events[-1]["type"] == "hold" and events[-1]["phase"] == "start"
    shell.hold_complete()
    assert events[-1] == {"type": "confirm-stop", "title": "Mario Party Superstars", "runner": "Eden"}
    assert shell.resume() and win.fg == GAME  # "Seguir jugando"


def test_hold_released_early_cancels_and_returns():
    shell, win, events = make(MANAGED)
    shell.hold_start()
    shell.hold_cancel()
    assert events[-1] == {"type": "hold", "phase": "cancel"} and win.fg == GAME


def test_hold_closes_managed_game():
    shell, win, _ = make(MANAGED)
    shell.hold_start()
    shell.hold_complete()
    assert shell.stop_game() and shell.catalog.launcher.stopped and shell.catalog.launcher.forced


def test_hold_also_works_with_emulator_opened_elsewhere():
    shell, win, events = make(None)  # Eden abierto desde ES-DE, no desde Orbital
    shell.hold_start()
    assert events[-1]["title"] == "Eden | Mario Party Superstars" and shell.hold["pid"] == 20


def test_hold_ignored_in_orbital_and_in_other_apps():
    shell, win, events = make(MANAGED)
    win.fg = ORBITAL
    shell.hold_start()  # en Orbital, Select/Start son el menú
    shell2, win2, events2 = make(None)
    win2.fg = DESKTOP_APP
    shell2.hold_start()  # el Bloc de notas no es un juego
    assert events == [] and events2 == [] and win2.fg == DESKTOP_APP


def test_legion_l_mirrors_home_and_double_press_keeps_legion_space():
    shell, win, _ = make(MANAGED)
    win.fg = LEGION
    shell.check_legion(LEGION, previous=GAME, now=100)
    assert win.minimized == [LEGION] and win.fg == ORBITAL
    win.fg = LEGION
    shell.check_legion(LEGION, previous=ORBITAL, now=110)
    assert win.fg == GAME  # desde Orbital, Legion L regresa al juego
    win.fg = LEGION
    shell.check_legion(LEGION, previous=GAME, now=111)  # dos toques seguidos
    assert win.fg == LEGION and win.minimized == [LEGION, LEGION]
