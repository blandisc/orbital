"""Lanzador: el juego que sigue en otro proceso, y nada de claves en el registro."""

import subprocess
import threading
import time

from orbital import launcher as launcher_mod
from orbital import player
from orbital.catalog import bring_game_to_front  # la real (conftest la apaga para el resto)
from orbital.launcher import Launcher, Running, redact
from orbital.library import streams


class FakeProcess:
    def __init__(self, pid):
        self.pid = pid
        self.done = threading.Event()

    def wait(self, timeout=None):
        if not self.done.wait(timeout):
            raise subprocess.TimeoutExpired("x", timeout)
        return 0

    def poll(self):
        return 0 if self.done.is_set() else None


def make(procs, before=None):
    ended = []
    lau = Launcher(on_exit=lambda *args: ended.append(args))
    lau.POLL, lau.HANDOFF_GRACE = .02, .1
    lau.process_list = lambda: dict(procs)
    proc = FakeProcess(100)
    procs[100] = ("xemu.exe", 1)
    procs.update(before or {})
    running = Running("xbox:swbf2", "Battlefront II", proc, runner="xemu")
    lau.current = running
    thread = threading.Thread(target=lau._watch_process, args=(running,), daemon=True)
    thread.start()
    return lau, proc, ended, thread


def wait_for(cond, seconds=2.0):
    end = time.time() + seconds
    while time.time() < end and not cond():
        time.sleep(.01)
    return cond()


def test_relaunched_emulator_keeps_the_session():
    procs = {}
    lau, proc, ended, thread = make(procs, before={50: ("xemu.exe", 1)})  # otro xemu ya abierto: no es nuestro
    procs[200] = ("xemu.exe", 1)  # xemu se relanza…
    del procs[100]
    proc.done.set()  # …y el proceso original termina a los 2 s
    assert wait_for(lambda: lau.current.followers == {200})
    assert not ended and lau.status()["pid"] == 200  # sigue "en curso", con el pid nuevo
    del procs[200]  # ahora sí se cerró
    assert wait_for(lambda: ended)
    thread.join(1)
    assert ended[0][:2] == ("xbox:swbf2", "Battlefront II") and lau.status() is None


def test_launcher_child_keeps_the_session():
    procs = {}
    lau, proc, ended, thread = make(procs)
    procs[300] = ("eden.exe", 100)  # el lanzador abre el juego
    time.sleep(.1)  # el vigilante lo ve mientras el lanzador vive
    del procs[100]
    proc.done.set()
    assert wait_for(lambda: lau.current is not None and lau.current.followers == {300})
    assert not ended
    del procs[300]
    assert wait_for(lambda: ended)


def test_a_normal_exit_still_ends_the_session():
    procs = {}
    lau, proc, ended, thread = make(procs)
    del procs[100]
    proc.done.set()
    assert wait_for(lambda: ended)


def test_unrelated_consoles_never_count_as_the_game():
    procs = {}
    ended = []
    lau = Launcher(on_exit=lambda *args: ended.append(args))
    lau.POLL, lau.HANDOFF_GRACE = .02, .1
    lau.process_list = lambda: dict(procs)
    proc = FakeProcess(100)
    procs[100] = ("cmd.exe", 1)  # launch-eden.cmd
    running = Running("switch:zelda", "Zelda", proc)
    lau.current = running
    threading.Thread(target=lau._watch_process, args=(running,), daemon=True).start()
    procs[400] = ("cmd.exe", 1)  # otro cmd, de cualquier cosa
    del procs[100]
    proc.done.set()
    assert wait_for(lambda: ended)


def test_stop_closes_the_process_that_took_over(monkeypatch):
    killed = []
    monkeypatch.setattr(launcher_mod, "_taskkill", lambda pid, force=False: killed.append((pid, force)))
    monkeypatch.setattr(launcher_mod.sys, "platform", "win32")
    lau = Launcher()
    proc = FakeProcess(100)
    proc.done.set()
    lau.current = Running("xbox:swbf2", "Battlefront II", proc, followers={200})
    assert lau.stop(force=True) and killed == [(200, True)]


def test_logs_never_carry_keys():
    url = "https://torrentio.strem.fun/resolve/realdebrid/SECRETKEY123/abc/null/0/movie.mkv"
    assert redact(url) == "https://torrentio.strem.fun/…" and "SECRET" not in redact(url)
    assert redact("stremio:///player/eAEBxyz/abc") == "stremio:///player/…"
    assert redact("--fullscreen") == "--fullscreen" and redact("C:\\x\\eden.exe") == "C:\\x\\eden.exe"


def test_czech_dub_is_not_taken_for_english():
    czech = {"name": "[RD+] Torrentio\n1080p", "title": "Konec Oak Street (2026) CZ dabing\n👤 12 💾 2.1 GB",
             "url": "https://x/1"}
    english = {"name": "[RD+] Torrentio\n1080p", "title": "The.End.of.Oak.Street.2026.1080p.WEB-DL\n👤 40 💾 4 GB",
               "url": "https://x/2"}
    found = [streams.parse(czech, "Torrentio", "t", 0), streams.parse(english, "Torrentio", "t", 1)]
    assert found[0].languages == ["cs"] and found[1].languages == ["en"]
    assert streams.rank(found, streams.Preferences(), "movie")[0].index == 1
    assert found[0].public()["languages"] == ["Checo"]


def test_player_warns_when_audio_is_another_language():
    assert player.wrong_audio([{"type": "audio", "lang": "cze"}], "en")
    assert not player.wrong_audio([{"type": "audio", "lang": "cze"}, {"type": "audio", "lang": "eng"}], "en")
    assert not player.wrong_audio([{"type": "audio"}], "en")  # sin etiqueta no se sabe
    assert not player.wrong_audio([{"type": "audio", "lang": "und"}], "en")


class FocusWindows:
    """Orbital (1) al frente; el emulador (pid 20) abre su lista (2) y luego el juego (3)."""

    def __init__(self, fg_title="Orbital - Microsoft Edge", fg_exe="msedge.exe"):
        self.fg = 1
        self.windows = {1: (fg_title, 10, fg_exe, False)}
        self.focused = []
        self.topmost = []

    def open(self, hwnd, title, fullscreen=False):
        self.windows[hwnd] = (title, 20, "eden.exe", fullscreen)

    def foreground(self): return self.fg
    def title(self, h): return self.windows[h][0]
    def pid_of(self, h): return self.windows[h][1]
    def exe_name(self, pid): return next(w[2] for w in self.windows.values() if w[1] == pid)
    def process_tree(self, pid): return {pid}
    def windows_of(self, pids): return [h for h, w in self.windows.items() if w[1] in pids]
    def main_window(self, pids): return next(iter(self.windows_of(pids)), 0)
    def is_fullscreen(self, h): return self.windows[h][3]
    def set_topmost(self, h, on): self.topmost.append((h, on)); return True

    def focus(self, h):
        self.focused.append(h)
        self.fg = h
        return True


class StatusLauncher:
    def __init__(self, status): self._status = status
    def status(self): return self._status


def test_game_ready_detection():
    from orbital.catalog import game_ready
    assert not game_ready([("Eden 0.0.3", False)], "Mario Party Superstars", "Eden")  # la lista de juegos
    assert game_ready([("Eden | Mario Party Superstars | v1.1", False)], "Mario Party Superstars", "Eden")
    assert game_ready([("xemu", True)], "Star Wars: Battlefront II", "xemu")  # pantalla completa
    assert not game_ready([("Cargando shaders…", False)], "Zelda", None)


def test_loading_screen_covers_the_emulator_until_the_game_is_ready():
    win = FocusWindows()
    win.open(2, "Eden 0.0.3")  # la lista de juegos de Eden: fea, tapada
    events, steps = [], []

    def sleep(seconds):
        steps.append(seconds)
        if len(steps) == 2:
            win.open(3, "Eden | Mario Party Superstars")  # ya el juego

    shown = bring_game_to_front(StatusLauncher({"id": "x", "pid": 20}), "x", "Mario Party Superstars", "Eden",
                                notify=events.append, timeout=5, win=win, sleep=sleep)
    assert shown and win.focused == [3]
    assert win.topmost == [(1, True), (1, False)]  # Orbital encima mientras abría, y luego ya no
    assert events == [{"type": "launch-ready", "id": "x"}]


def test_skip_shows_whatever_is_there():
    import threading
    win = FocusWindows()
    win.open(2, "Eden 0.0.3")
    skip = threading.Event()
    skip.set()  # B en la pantalla de carga
    assert bring_game_to_front(StatusLauncher({"id": "x", "pid": 20}), "x", "Zelda", "Eden", skip=skip,
                               timeout=5, win=win, sleep=lambda s: None)
    assert win.focused == [2] and win.topmost[-1] == (1, False)


def test_game_that_dies_while_loading_leaves_orbital_unpinned():
    win = FocusWindows()
    assert not bring_game_to_front(StatusLauncher(None), "x", "Zelda", timeout=5, win=win, sleep=lambda s: None)
    assert win.topmost == [(1, True), (1, False)] and win.focused == []


def test_never_steals_focus_from_another_app():
    win = FocusWindows(fg_title="Discord", fg_exe="discord.exe")
    win.open(2, "Eden | Zelda")
    assert not bring_game_to_front(StatusLauncher({"id": "x", "pid": 20}), "x", "Zelda", timeout=1, win=win,
                                   sleep=lambda s: None)
    assert win.focused == [] and win.topmost == []  # sin pantalla de carga encima de otra app
