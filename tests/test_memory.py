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


def test_before_a_heavy_game_with_little_memory_offers_what_to_close(monkeypatch):
    # El 2026-10-26 la consola tenía 5 GB libres en reposo y Claude (2,4 GB), Grok y Steam abiertos; con un juego de
    # Switch la RAM libre bajaba a ~150 MB y todo se trababa.
    procs = {1: ("claude.exe", 0), 2: ("claude.exe", 1), 3: ("steam.exe", 0), 4: ("svchost.exe", 0), 5: ("tiny.exe", 0)}
    fake_system(monkeypatch, procs, windows_pids=[5], private={1: 1600, 2: 800, 3: 600, 4: 3000, 5: 50})
    room = memory.before_play("switch", free_mb=2500)
    assert room["free_mb"] == 2500
    assert [a["exe"] for a in room["apps"]] == ["claude.exe", "steam.exe"]  # svchost nunca; tiny no vale la pena
    assert memory.before_play("switch", free_mb=6000) is None  # hay memoria: se juega directo
    assert memory.before_play("gba", free_mb=500) is None  # un juego ligero no necesita nada
    fake_system(monkeypatch, {4: ("svchost.exe", 0)}, private={4: 3000})
    assert memory.before_play("switch", free_mb=500) is None  # nada que se pueda cerrar: no se pregunta
