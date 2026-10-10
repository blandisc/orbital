"""Pruebas que solo tienen sentido en Windows real (procesos, .cmd, taskkill)."""

import os
import subprocess
import sys
import time

import pytest

from orbital.kiosk import KioskWindow
from orbital.launcher import Launcher

pytestmark = pytest.mark.skipif(os.name != "nt", reason="solo Windows")


def alive(pid: int) -> bool:
    out = subprocess.run(["tasklist", "/FI", f"PID eq {pid}", "/NH"], capture_output=True, text=True).stdout
    return str(pid) in out


def wait_for(predicate, timeout=10.0):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if predicate():
            return True
        time.sleep(0.1)
    return False


def test_stop_closes_whole_tree_of_cmd_wrapper(tmp_path):
    # Como launch-eden.cmd: un .cmd que abre el emulador con start /wait.
    pid_file = tmp_path / "child.pid"
    child = tmp_path / "child.py"
    child.write_text(f"import os, time\nopen(r'{pid_file}', 'w').write(str(os.getpid()))\ntime.sleep(60)\n")
    wrapper = tmp_path / "launch-fake.cmd"
    wrapper.write_text(f'@echo off\nstart /wait "" "{sys.executable}" "{child}" %*\n')

    exited = []
    launcher = Launcher(on_exit=lambda item_id, title, secs: exited.append(item_id))
    proc = launcher.run([str(wrapper), "--fullscreen", "C:\\ROMs\\Mi juego (USA).nsp"])
    launcher.track("emu:x", "Juego", proc)
    assert wait_for(lambda: pid_file.exists() and pid_file.read_text())
    child_pid = int(pid_file.read_text())

    assert launcher.stop()
    assert wait_for(lambda: not alive(child_pid)), "el emulador siguió abierto"
    assert wait_for(lambda: exited == ["emu:x"])  # se registra el tiempo jugado


def test_kiosk_open_and_close(tmp_path):
    fake = tmp_path / "browser.cmd"
    fake.write_text("@ping -n 30 127.0.0.1 >nul\n")
    kiosk = KioskWindow("http://x", str(fake), tmp_path / "perfil")
    assert kiosk.open() and kiosk.is_open and not kiosk.exited_by_user
    assert kiosk.close() and not kiosk.is_open and kiosk.exited_by_user
    assert kiosk.close() is False


def test_kiosk_reopens_when_closed_without_exit(tmp_path):
    # Una "ventana" que se cierra sola al instante: se reabre, pero máximo 3 veces por minuto.
    count = tmp_path / "count.txt"
    fake = tmp_path / "browser.cmd"
    fake.write_text(f"@echo x>>\"{count}\"\n")
    kiosk = KioskWindow("http://x", str(fake), tmp_path / "perfil")
    kiosk.REOPEN_DELAY = 0.05
    assert kiosk.open()
    assert wait_for(lambda: count.exists() and len(count.read_text().split()) == 4)  # 1 + 3 reaperturas
    time.sleep(0.5)
    assert len(count.read_text().split()) == 4


def test_kiosk_not_reopened_after_exit_to_desktop(tmp_path):
    fake = tmp_path / "browser.cmd"
    fake.write_text("@ping -n 30 127.0.0.1 >nul\n")
    kiosk = KioskWindow("http://x", str(fake), tmp_path / "perfil")
    kiosk.REOPEN_DELAY = 0.05
    assert kiosk.open() and kiosk.close()
    time.sleep(0.4)
    assert not kiosk.is_open
