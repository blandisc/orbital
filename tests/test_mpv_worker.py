"""El hilo fijo de comandos de mpv (F9): un solo hilo para todos los comandos, y uno nuevo solo si mpv se cuelga."""

from __future__ import annotations

import json
import threading

from orbital.mpv import Mpv


class Pipe:
    """Una tubería de mentira: contesta cada comando con su número, o se queda callada (mpv colgado)."""

    def __init__(self, hang: threading.Event | None = None) -> None:
        self.hang = hang
        self.pending: list[int] = []
        self.threads: set[str] = set()
        self.closed = False

    def write(self, data: bytes) -> int:
        self.threads.add(threading.current_thread().name)
        self.pending.append(json.loads(data)["request_id"])
        return len(data)

    def readline(self) -> bytes:
        if self.hang is not None:
            self.hang.wait(5)
            return b""
        return (json.dumps({"error": "success", "data": 1, "request_id": self.pending.pop(0)}) + "\n").encode()

    def close(self) -> None:
        self.closed = True


def test_every_command_goes_through_one_fixed_thread(monkeypatch):
    pipe = Pipe()
    m = Mpv(pipe="no-existe")
    monkeypatch.setattr(m, "_connect", lambda: pipe)
    before = threading.active_count()
    for _ in range(30):
        assert m.command("set_property", "volume", 40)["error"] == "success"
    assert pipe.threads == {"mpv-ipc"} and threading.active_count() <= before + 1  # antes: un hilo por comando
    m.close()


def test_a_hung_mpv_is_left_behind_and_the_next_command_opens_another(monkeypatch):
    released = threading.Event()
    pipes = [Pipe(hang=released), Pipe()]
    m = Mpv(pipe="no-existe")
    m.TIMEOUT = 0.3
    monkeypatch.setattr(m, "_connect", lambda: pipes.pop(0))
    assert m.command("get_property", "pause") is None  # mpv no contestó a tiempo: Orbital no se cuelga
    assert m.command("get_property", "pause")["error"] == "success"  # conexión y hilo nuevos
    released.set()
    m.close()


def test_the_connection_left_behind_for_being_slow_is_closed_when_mpv_lets_go(monkeypatch):
    """Revisión del 11 nov 2026: la conexión abandonada por lenta nunca se cerraba (una tubería abierta por cada cuelgue)."""
    import time

    released = threading.Event()
    stuck, fresh = Pipe(hang=released), Pipe()
    pipes = [stuck, fresh]
    m = Mpv(pipe="no-existe")
    m.TIMEOUT = 0.3
    monkeypatch.setattr(m, "_connect", lambda: pipes.pop(0))
    assert m.command("get_property", "pause") is None
    assert m.command("get_property", "pause")["error"] == "success"
    assert not stuck.closed  # mientras mpv la tiene agarrada no se toca (en Windows cerrarla ahí podría colgarse)
    released.set()  # mpv suelta la lectura
    deadline = time.monotonic() + 5
    while not stuck.closed and time.monotonic() < deadline:
        time.sleep(0.01)
    assert stuck.closed and not fresh.closed  # se cierra la vieja; la nueva sigue sirviendo
    assert m._fh is fresh and m.command("get_property", "pause")["error"] == "success"
    m.close()


def test_a_thread_left_behind_never_reconnects_over_the_new_one(monkeypatch):
    """El hilo atorado, al soltarse con error, ya no abre otra conexión ni escribe en la del hilo nuevo."""
    import time

    class Counting(Pipe):
        writes = 0

        def write(self, data: bytes) -> int:
            self.writes += 1
            return super().write(data)

    released = threading.Event()
    stuck, fresh = Pipe(hang=released), Counting()
    opened = []

    def connect():
        pipe = [stuck, fresh][len(opened)] if len(opened) < 2 else Pipe()
        opened.append(pipe)
        return pipe

    m = Mpv(pipe="no-existe")
    m.TIMEOUT = 0.3
    monkeypatch.setattr(m, "_connect", connect)
    assert m.command("get_property", "pause") is None
    assert m.command("get_property", "pause")["error"] == "success"
    released.set()  # la lectura vieja termina en «mpv cerró la conexión»: antes reintentaba con una nueva
    time.sleep(0.2)
    assert len(opened) == 2 and m._fh is fresh and fresh.writes == 1  # solo el comando del hilo nuevo
    m.close()


def test_only_orbitals_own_mpv_is_closed_at_startup():
    from orbital.mpv import PIPE
    from orbital.playback import close_orphan_players

    procs = {10: ("mpv.exe", 1), 11: ("mpv.exe", 1), 12: ("msedge.exe", 1), 13: ("mpv.exe", 1)}
    lines = {10: f'"C:/orbital/mpv.exe" --input-ipc-server={PIPE} --fullscreen', 11: "mpv.exe mi-pelicula.mkv",
             12: f"msedge.exe --input-ipc-server={PIPE}", 13: r"mpv.exe --input-ipc-server=\\.\pipe\orbital-test-1"}
    killed: list[int] = []
    assert close_orphan_players(lambda: procs, lambda pid: lines[pid], killed.append) == 1
    assert killed == [10]  # ni tu otro mpv, ni Edge, ni el de las pruebas


def test_the_startup_sweep_never_closes_a_video_this_orbital_just_opened():
    """Revisión del 11 nov 2026: la limpieza corre en segundo plano; si en ese rato pediste algo desde el iPhone, el mpv
    recién abierto tiene la misma tubería y se cerraba. Ahora solo cierra los que no abrió este Orbital."""
    from orbital.mpv import PIPE
    from orbital.playback import close_orphan_players

    me, dead_orbital = 4000, 3000
    procs = {10: ("mpv.exe", dead_orbital), 20: ("mpv.exe", me)}  # el huérfano y el que acabas de pedir
    line = f'"C:/orbital/mpv.exe" --input-ipc-server={PIPE} --fullscreen'
    killed: list[int] = []
    assert close_orphan_players(lambda: procs, lambda pid: line, killed.append, me=me) == 1
    assert killed == [10]


def test_by_default_the_sweep_knows_this_process_is_orbital():
    import os

    from orbital.mpv import PIPE
    from orbital.playback import close_orphan_players

    procs = {20: ("mpv.exe", os.getpid())}
    killed: list[int] = []
    assert close_orphan_players(lambda: procs, lambda pid: f"mpv.exe --input-ipc-server={PIPE}", killed.append) == 0
    assert killed == []
