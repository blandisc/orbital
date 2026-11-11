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


def test_only_orbitals_own_mpv_is_closed_at_startup():
    from orbital.mpv import PIPE
    from orbital.playback import close_orphan_players

    procs = {10: ("mpv.exe", 1), 11: ("mpv.exe", 1), 12: ("msedge.exe", 1), 13: ("mpv.exe", 1)}
    lines = {10: f'"C:/orbital/mpv.exe" --input-ipc-server={PIPE} --fullscreen', 11: "mpv.exe mi-pelicula.mkv",
             12: f"msedge.exe --input-ipc-server={PIPE}", 13: r"mpv.exe --input-ipc-server=\\.\pipe\orbital-test-1"}
    killed: list[int] = []
    assert close_orphan_players(lambda: procs, lambda pid: lines[pid], killed.append) == 1
    assert killed == [10]  # ni tu otro mpv, ni Edge, ni el de las pruebas
