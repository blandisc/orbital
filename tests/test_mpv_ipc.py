"""El cliente de mpv contra un mpv de verdad (si está instalado): sin ventana, en su propia tubería."""

import os
import subprocess
import sys
import time
import uuid
from pathlib import Path

import pytest

from orbital.mpv import Mpv

MPV = Path(os.environ.get("LOCALAPPDATA", "")) / "orbital" / "mpv" / "mpv.exe"
pytestmark = pytest.mark.skipif(sys.platform != "win32" or not MPV.exists(), reason="sin mpv instalado")


@pytest.fixture
def mpv():
    pipe = rf"\\.\pipe\orbital-test-{uuid.uuid4().hex}"
    process = subprocess.Popen([str(MPV), "--idle=yes", "--force-window=no", "--no-config", "--vo=null",
                                "--ao=null", f"--input-ipc-server={pipe}"])
    client = Mpv(pipe)
    deadline = time.monotonic() + 10
    while client.get("idle-active") is None and time.monotonic() < deadline:
        time.sleep(.1)
    yield client
    client.command("quit")
    client.close()
    process.wait(5)


def test_commands_reuse_one_connection(mpv):
    assert mpv.get("idle-active") is True
    connection = mpv._fh
    for _ in range(20):
        assert mpv.command("set_property", "volume", 40)["error"] == "success"
    assert mpv._fh is connection and mpv.get("volume") == 40


def test_observed_properties_arrive_without_asking(mpv):
    mpv.start_observing()
    mpv.command("set_property", "pause", True)
    deadline = time.monotonic() + 5
    while mpv._cache.get("pause") is not True and time.monotonic() < deadline:
        time.sleep(.05)
    assert mpv._cache.get("pause") is True and mpv.get("pause") is True


def test_reconnects_after_mpv_restarts(tmp_path):
    pipe = rf"\\.\pipe\orbital-test-{uuid.uuid4().hex}"
    argv = [str(MPV), "--idle=yes", "--force-window=no", "--no-config", "--vo=null", "--ao=null",
            f"--input-ipc-server={pipe}"]
    client = Mpv(pipe)
    for _ in range(2):  # el mismo cliente sirve para un mpv y para el siguiente
        process = subprocess.Popen(argv)
        deadline = time.monotonic() + 10
        while client.get("idle-active") is None and time.monotonic() < deadline:
            time.sleep(.1)
        assert client.get("idle-active") is True
        client.command("quit")
        process.wait(5)
    client.close()
