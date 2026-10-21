"""Xenia cambiando de programa (Black Ops II: campaña ↔ Zombies): Orbital lo relanza como la misma partida."""

from __future__ import annotations

import struct
import threading
import time
from pathlib import Path

from orbital import launcher as launcher_mod
from orbital import title_switch
from orbital.launcher import Launcher, Running

GAME = rb"C:\Orbital\Emuladores\xenia_canary_netplay\content\0000000000000000\415608C3\00007000\3A213694CA20E8B1940B"


def request(module: bytes, data: bytes = bytes(1000)) -> bytes:
    """Como la escribe Xenia: largo + ruta del juego, largo + programa, banderas, largo + datos."""
    return struct.pack("<H", len(GAME)) + GAME + struct.pack("<H", len(module)) + module + struct.pack("<II", 0, len(data)) + data


def test_reads_which_program_the_game_asks_for():
    assert title_switch.requested_module(request(b"default_mp.xex")) == "default_mp.xex"
    assert title_switch.requested_module(request(b"")) is None  # salir al tablero: no hay que relanzar
    assert title_switch.requested_module(b"\x01") is None  # dañado: no se adivina
    assert title_switch.xenia_dir([r"C:\Orbital\Emuladores\xenia_canary_netplay\launch-xenia.cmd", "x"]).name == "xenia_canary_netplay"
    assert title_switch.xenia_dir([r"C:\Emus\Eden\eden.exe", "x"]) is None
    assert title_switch.program_name("default_mp.xex") == "Cambiando a Multijugador y Zombies"


def test_each_request_relaunches_once_and_old_ones_are_ignored(tmp_path: Path):
    path = tmp_path / title_switch.LAUNCH_DATA
    path.write_bytes(request(b"default_mp.xex"))  # una vieja, de antes de abrir: la lee Xenia al arrancar
    now = [0.0]
    asked = []
    turns = iter(range(400))

    def sleep(seconds):
        now[0] += seconds
        turn = next(turns)
        if turn == 5:
            path.unlink()  # Xenia la leyó y la borró
        if turn == 20:
            path.write_bytes(request(b"default_mp.xex"))  # elegiste Zombies
        if turn == 60:
            path.write_bytes(request(b""))  # saliste al tablero

    title_switch.watch(tmp_path, still_playing=lambda: now[0] < 60, relaunch=asked.append, sleep=sleep, clock=lambda: now[0])
    assert asked == ["default_mp.xex"]  # una vez (ni la vieja ni la de salir)


class Proc:
    def __init__(self, pid):
        self.pid = pid
        self.done = threading.Event()

    def wait(self, timeout=None):
        import subprocess
        if not self.done.wait(timeout):
            raise subprocess.TimeoutExpired("x", timeout)
        return 0

    def poll(self):
        return 0 if self.done.is_set() else None


def test_relaunching_keeps_the_same_session(monkeypatch):
    old, new = Proc(100), Proc(200)
    killed = []
    monkeypatch.setattr(launcher_mod, "_taskkill", lambda pid, force=False: killed.append(pid) or old.done.set())
    ended = []
    lau = Launcher(on_exit=lambda *args: ended.append(args))
    lau.POLL, lau.HANDOFF_GRACE = .02, .05
    lau.process_list = dict
    lau.run = lambda argv, cwd=None: new
    running = Running("emu:xbox360:bo2", "Call of Duty: Black Ops II", old, runner="Xenia")
    lau.current = running
    threading.Thread(target=lau._watch_process, args=(running,), daemon=True).start()
    time.sleep(.05)
    assert lau.relaunch("emu:xbox360:bo2", ["launch-xenia.cmd", "x"])
    time.sleep(.2)
    assert not ended and lau.status()["pid"] == 200  # la misma partida, en el proceso nuevo
    assert killed == [100]
    new.done.set()
    end = time.time() + 2
    while not ended and time.time() < end:
        time.sleep(.01)
    assert ended and ended[0][0] == "emu:xbox360:bo2"  # y al cerrarse el nuevo, sí terminó


def test_relaunching_xenia_after_its_launcher_closed_keeps_the_session(monkeypatch):
    """Lo de verdad: launch-xenia.cmd ya se cerró y el juego vive en Xenia (su «seguidor»). Se cierra ese Xenia y se abre
    otro .cmd: sigue siendo la misma partida."""
    procs = {100: ("cmd.exe", 1), 150: ("powershell.exe", 100)}
    cmd, new = Proc(100), Proc(400)
    monkeypatch.setattr(launcher_mod, "_taskkill", lambda pid, force=False: procs.pop(pid, None))
    ended = []
    lau = Launcher(on_exit=lambda *args: ended.append(args))
    lau.POLL, lau.HANDOFF_GRACE = .05, .1
    lau.process_list = lambda: dict(procs)

    def run(argv, cwd=None):
        procs[400] = ("cmd.exe", 1)
        return new

    lau.run = run
    running = Running("emu:xbox360:bo2", "Call of Duty: Black Ops II", cmd, runner="Xenia")
    lau.current = running
    threading.Thread(target=lau._watch_process, args=(running,), daemon=True).start()
    time.sleep(.3)
    procs[300] = ("xenia_canary_netplay.exe", 150)  # PowerShell abre Xenia y se cierra, igual que el .cmd
    del procs[150], procs[100]
    cmd.done.set()
    end = time.time() + 2
    while 300 not in running.followers and time.time() < end:
        time.sleep(.02)
    assert 300 in running.followers
    assert lau.relaunch("emu:xbox360:bo2", ["launch-xenia.cmd", "x"])
    assert 300 not in procs  # se cerró el Xenia de verdad (no el .cmd, que ya no estaba)
    time.sleep(.3)
    assert not ended and lau.status()["id"] == "emu:xbox360:bo2"
