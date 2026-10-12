"""Liberar memoria: qué se muestra, qué se puede cerrar y que nunca se cierre Orbital ni Windows."""

from orbital import memory


def fake_system(monkeypatch, procs, windows_pids=(), private=None):
    from orbital import windows

    monkeypatch.setattr(windows, "processes", lambda: procs)
    monkeypatch.setattr(windows, "app_windows", lambda: [{"hwnd": pid} for pid in windows_pids])
    monkeypatch.setattr(windows, "pid_of", lambda hwnd: hwnd)
    monkeypatch.setattr(memory, "_private_mb", lambda pid: (private or {}).get(pid, 100))
    monkeypatch.setattr(memory.sys, "platform", "win32")


def test_groups_programs_and_only_offers_safe_ones(monkeypatch):
    procs = {1: ("claude.exe", 0), 2: ("claude.exe", 1), 3: ("steam.exe", 0), 4: ("steamwebhelper.exe", 3),
             5: ("svchost.exe", 0), 6: ("notepad.exe", 0), 7: ("pythonw.exe", 0), 8: ("tray.exe", 0)}
    fake_system(monkeypatch, procs, windows_pids=[6], private={1: 3000, 2: 1500, 3: 400, 4: 600})
    apps = {a.exe: a for a in memory.usage(limit=20)}
    assert apps["claude.exe"].mb == 4500 and apps["claude.exe"].closable and apps["claude.exe"].warning
    assert apps["steam.exe"].mb == 1000 and apps["steam.exe"].closable  # steam + steamwebhelper juntos
    assert not apps["svchost.exe"].closable and not apps["pythonw.exe"].closable  # Windows y Orbital, nunca
    assert apps["notepad.exe"].closable  # tiene ventana
    assert not apps["tray.exe"].closable  # sin ventana y desconocido: no
    assert list(apps)[0] == "claude.exe"  # lo más grande primero


def test_close_refuses_protected_and_kills_the_rest(monkeypatch):
    procs = {1: ("discord.exe", 0), 2: ("discord.exe", 1), 9: ("eden.exe", 0)}
    fake_system(monkeypatch, procs, windows_pids=[9])
    killed = []
    monkeypatch.setattr(memory.subprocess, "run", lambda cmd, **kw: killed.append(cmd[2]))
    assert memory.close("discord.exe") == 200 and killed == ["1", "2"]
    import pytest

    with pytest.raises(PermissionError):
        memory.close("eden.exe", protect_pids={9})  # el juego abierto se cierra aparte
    with pytest.raises(LookupError):
        memory.close("spotify.exe")
