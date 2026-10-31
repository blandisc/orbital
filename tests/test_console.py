import json
import os
import stat
import time
from pathlib import Path

import pytest
from conftest import FakeLauncher
from fastapi.testclient import TestClient

from orbital.catalog import Catalog
from orbital.config import parse_config
from orbital.kiosk import KioskWindow, build_command, mark_clean_exit
from orbital.library import detect
from orbital.server import create_app
from orbital.voice import VoiceController


# --------------------------------------------------------------------- ventana
def test_kiosk_uses_dedicated_profile(tmp_path):
    cmd = build_command("msedge.exe", "http://127.0.0.1:8710", tmp_path / "perfil")
    assert cmd[:4] == ["msedge.exe", f"--user-data-dir={tmp_path / 'perfil'}", "--kiosk", "http://127.0.0.1:8710"]
    assert "--hide-crash-restore-bubble" in cmd and "--no-first-run" in cmd


def test_mark_clean_exit(tmp_path):
    prefs = tmp_path / "Default" / "Preferences"
    prefs.parent.mkdir(parents=True)
    prefs.write_text(json.dumps({"profile": {"exit_type": "Crashed", "name": "x"}}))
    mark_clean_exit(tmp_path)
    profile = json.loads(prefs.read_text())["profile"]
    assert profile == {"exit_type": "Normal", "exited_cleanly": True, "name": "x"}
    mark_clean_exit(tmp_path / "no-existe")  # no falla


@pytest.mark.skipif(os.name == "nt", reason="usa un script de shell como navegador falso")
def test_kiosk_open_and_close(tmp_path):
    fake = tmp_path / "browser.sh"
    fake.write_text("#!/bin/sh\nexec sleep 30\n")
    fake.chmod(fake.stat().st_mode | stat.S_IEXEC)
    kiosk = KioskWindow("http://x", str(fake), tmp_path / "perfil")
    assert kiosk.open() and kiosk.is_open
    assert kiosk.close() and not kiosk.is_open
    assert kiosk.close() is False


class FakeKiosk:
    def __init__(self):
        self.is_open = True
        self.exited_by_user = False
        self.calls = []

    def open(self):
        self.calls.append("open")
        self.is_open, self.exited_by_user = True, False
        return True

    def close(self):
        self.calls.append("close")
        self.is_open, self.exited_by_user = False, True
        return True


def test_game_end_reopens_window_unless_user_exited(library, monkeypatch):
    fronted = []
    monkeypatch.setattr("orbital.sessions.system.bring_to_front", lambda: fronted.append(1) or True)
    kiosk = FakeKiosk()
    create_app(library.config, library, kiosk)
    kiosk.is_open = False  # alguien cerró Edge (Alt+F4) mientras jugaba
    library.sessions.session_ended("emu:x", "Juego", 60)
    assert kiosk.calls == ["open"] and kiosk.is_open
    kiosk.close()  # Salir al escritorio a propósito: no la reabrimos sola
    library.sessions.session_ended("emu:x", "Juego", 60)
    assert kiosk.calls == ["open", "close"] and fronted == [1]


def test_back_from_a_game_video_memory_is_released_with_orbital_in_front_before_4k(library, monkeypatch):
    """Al volver de un juego, si DWM quedó lleno se libera ahí (junto al parpadeo de volver a 4K), con Orbital ya al
    frente para que no se asome el escritorio. Un video no: ese ya se libera antes de abrirse (player.before_open)."""
    from orbital import display

    order = []
    kiosk = FakeKiosk()
    create_app(library.config, library, kiosk)
    kiosk.open = lambda: order.append("orbital") or True
    library.sessions.release_video_memory = lambda: order.append("liberar") or True
    monkeypatch.setattr(display.resolution, "restore", lambda: order.append("4K") or True)
    library.sessions.session_ended("emu:x", "Super Smash Bros. Ultimate", 1800)
    assert order == ["orbital", "liberar", "4K"]
    order.clear()
    library.sessions.session_ended("media:player", "Sleepy Hollow", 1800)
    assert "liberar" not in order


def test_voice_exit_and_reopen(library):
    kiosk = FakeKiosk()
    voice = VoiceController(library, kiosk)
    assert voice.handle_text("sal al escritorio").ok and kiosk.calls == ["close"]
    assert not voice.handle_text("sal al escritorio").ok  # ya estaba cerrada
    assert voice.handle_text("abre la consola").ok and kiosk.calls == ["close", "open"]
    assert not VoiceController(library).handle_text("cierra orbital").ok  # sin ventana propia


def test_exit_endpoint(library):
    kiosk = FakeKiosk()
    with TestClient(create_app(library.config, library, kiosk), base_url="http://127.0.0.1:8710", client=("127.0.0.1", 1)) as c:
        assert c.get("/api/ui").json() | {"alexa": None} == {"can_exit": True, "stremio_linked": False, "player": "stremio", "alexa": None}
        assert c.post("/api/ui/exit").json() == {"ok": True}
        for _ in range(40):
            if kiosk.calls:
                break
            time.sleep(0.05)
        assert kiosk.calls == ["close"]
    with TestClient(create_app(library.config, library), base_url="http://127.0.0.1:8710", client=("127.0.0.1", 1)) as c:
        assert c.get("/api/ui").json() | {"alexa": None} == {"can_exit": False, "stremio_linked": False, "player": "stremio", "alexa": None}
        assert c.post("/api/ui/exit").status_code == 409


# --------------------------------------------------------------------- detección
def touch(path: Path, mtime: float | None = None) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b"")
    if mtime:
        os.utime(path, (mtime, mtime))
    return path


@pytest.fixture
def downloads(tmp_path):
    d = tmp_path / "Downloads"
    touch(d / "ryujinx-1.3.1-win_x64" / "publish" / "Ryujinx.exe")
    touch(d / "Eden-Windows-v0.0.3" / "eden.exe")
    touch(d / "dolphin-2506" / "Dolphin-x64" / "Dolphin.exe")
    touch(d / "mGBA-0.10.5-win64" / "mGBA.exe")
    touch(d / "xemu-win-x86_64-0.8.92" / "xemu.exe", mtime=1_000)
    touch(d / "xemu-win-x86_64-0.8.100" / "xemu.exe", mtime=2_000)  # más reciente
    touch(d / "a" / "b" / "c" / "d" / "e" / "rpcs3.exe")  # demasiado hondo: no se detecta
    return d


def test_detects_known_emulators(downloads):
    result = detect.detect([detect.SearchDir(downloads)])
    assert [e.id for e in result.emulators] == ["switch", "switch-eden", "gamecube", "wii", "gba", "xbox"]
    assert result.found["xbox"].parent.name == "xemu-win-x86_64-0.8.100"
    eden = next(e for e in result.emulators if e.id == "switch-eden")
    assert eden.args == ["-f", "-g", "{rom}"] and eden.system == "switch" and eden.esde_label == "Eden"


def test_backup_copies_lose_even_if_newer(tmp_path):
    d = tmp_path / "Emulators"
    good = touch(d / "eden" / "eden.exe", mtime=1_000)
    touch(d / "eden.bak-pre-zen4-20261002-1439" / "eden.exe", mtime=2_000)
    touch(d / "ryujinx-old" / "Ryujinx.exe", mtime=2_000)
    only_backup = touch(d / "backup" / "mGBA" / "mGBA.exe")
    touch(d / "Dolphin-x64" / "Dolphin.exe")  # "-x64" no es un respaldo
    found = detect.find_executables([detect.SearchDir(d)])
    assert found["eden.exe"] == good
    assert found["ryujinx.exe"].parent.name == "ryujinx-old"  # si solo hay respaldo, se usa
    assert found["mgba.exe"] == only_backup and "dolphin.exe" in found


def test_without_console_logs_go_to_file(tmp_path, monkeypatch):
    import sys

    from orbital import __main__ as entry

    monkeypatch.setenv("LOCALAPPDATA", str(tmp_path))
    assert entry.ensure_streams() is None  # con consola no toca nada
    (tmp_path / "orbital").mkdir()
    (tmp_path / "orbital" / "orbital.log").write_text("anterior", encoding="utf-8")
    monkeypatch.setattr(sys, "stdout", None)  # así arranca pythonw.exe
    monkeypatch.setattr(sys, "stderr", None)
    path = entry.ensure_streams()
    try:
        assert path == tmp_path / "orbital" / "orbital.log"
        print("Configuración lista")
        assert sys.stderr is sys.stdout
    finally:
        sys.stdout.close()
    assert path.read_text(encoding="utf-8") == "Configuración lista\n"
    assert (tmp_path / "orbital" / "orbital.log.1").read_text(encoding="utf-8") == "anterior"


def test_psp_accepts_chd():
    psp = next(k for k in detect.KNOWN if k.id == "psp")
    assert ".chd" in psp.extensions  # PPSSPP abre CHD desde la 1.15


def test_config_overrides_detection(downloads):
    mine = parse_config({"emulators": [{"id": "gba", "name": "GBA (RetroArch)", "executable": "retroarch"}]}).emulators
    result = detect.detect([detect.SearchDir(downloads)], skip_ids={"gba"})
    merged = detect.merge(mine, result.emulators)
    assert [e.id for e in merged][:2] == ["gba", "switch"]
    assert merged[0].name == "GBA (RetroArch)" and "gba" not in result.found


def test_catalog_uses_detected_emulators(downloads, tmp_path, monkeypatch):
    monkeypatch.setattr(Path, "home", lambda: tmp_path)
    roms = tmp_path / "ES-DE-data"
    (roms / "settings").mkdir(parents=True)
    (roms / "settings" / "es_settings.xml").write_text(f'<string name="ROMDirectory" value="{tmp_path / "ROMs"}" />')
    touch(tmp_path / "ROMs" / "switch" / "Metroid Dread.nsp")
    touch(tmp_path / "ROMs" / "xbox" / "Halo.iso")
    cfg = parse_config({"steam": {"enabled": False}, "stremio": {"enabled": False}, "esde": {"path": str(roms)}})
    cat = Catalog(cfg, FakeLauncher())
    cat.refresh()
    metroid = cat.find("metroid")
    assert [r.name for r in metroid.runners] == ["Ryujinx", "Eden"]
    assert cat.find("halo").runner().argv[1:3] == ["-full-screen", "-dvd_path"]
    assert "xbox" in cat.detected


def test_quick_crash_with_low_memory_says_so(library, monkeypatch):
    from orbital import health

    monkeypatch.setattr(health, "free_ram_mb", lambda: 900)
    monkeypatch.setattr(health, "commit_room_mb", lambda: 9000)
    monkeypatch.setattr(health, "dwm_gpu_mb", lambda: (16000, 1200))
    events = []
    library.listeners.append(events.append)

    library.sessions.session_ended("emu:x", "Mario Party", 4)
    closed = [e for e in events if e["type"] == "closed"][-1]
    assert closed["crashed"] and "suspender no lo arregla" in closed["low_memory"] and closed["low_memory_restart"]
    monkeypatch.setattr(health, "dwm_gpu_mb", lambda: (500, 100))
    monkeypatch.setattr(health, "free_ram_mb", lambda: 9000)
    library.sessions.session_ended("emu:x", "Mario Party", 4)
    assert "low_memory" not in [e for e in events if e["type"] == "closed"][-1]


def test_emulator_that_dies_on_start_is_retried_once(library, monkeypatch):
    import time as _time

    library.launcher.last_stopped_by_user = False
    events = []
    library.listeners.append(events.append)
    game = next(i for i in library.items() if i.source == "snes")
    library.sessions.launch(game.id)
    library.launcher.finish(3)  # truena al arrancar
    deadline = _time.monotonic() + 5
    while len(library.launcher.ran) < 2 and _time.monotonic() < deadline:
        _time.sleep(.05)
    assert len(library.launcher.ran) == 2  # se abrió otra vez, solo
    assert not [e for e in events if e["type"] == "closed"]  # sin aviso de error todavía
    library.launcher.finish(3)  # vuelve a tronar: ahora sí se avisa
    _time.sleep(2)
    assert len(library.launcher.ran) == 2
    assert [e for e in events if e["type"] == "closed"][-1]["crashed"]


def test_kiosk_allows_the_microphone_only_for_orbital(tmp_path):
    from orbital.kiosk import allow_microphone

    prefs = tmp_path / "Default" / "Preferences"
    assert allow_microphone(tmp_path, "http://127.0.0.1:8710/")  # sin perfil todavía: se crea
    mic = json.loads(prefs.read_text())["profile"]["content_settings"]["exceptions"]["media_stream_mic"]
    assert list(mic) == ["http://127.0.0.1:8710,*"] and mic["http://127.0.0.1:8710,*"]["setting"] == 1
    data = json.loads(prefs.read_text())
    data["profile"]["exit_type"] = "Crashed"  # lo demás del perfil se conserva
    prefs.write_text(json.dumps(data))
    assert allow_microphone(tmp_path, "http://127.0.0.1:8710/?seccion=foryou")
    assert json.loads(prefs.read_text())["profile"]["exit_type"] == "Crashed"
    assert not allow_microphone(tmp_path, "no-es-una-url")


def test_the_kiosk_never_asks_for_the_microphone_again(tmp_path):
    """El quiosco de Edge es InPrivate: no hereda el «Permitir» guardado y preguntaba en cada sesión."""
    from orbital.kiosk import build_command

    assert "--use-fake-ui-for-media-stream" in build_command("msedge.exe", "http://127.0.0.1:8710", tmp_path)


def test_a_launch_cancelled_on_the_loading_screen_is_not_a_played_session(library):
    """S3-A5: B en la pantalla de carga y el emulador se cierra a los segundos: la interfaz ya dijo «Cancelé…»; su "closed"
    no es «De vuelta de…» ni deja una partida en la bandeja del iPhone. Lo siguiente que abras sí cuenta."""
    library.state.set_setting("companion_seen", 1)
    events = []
    library.listeners.append(events.append)
    game = next(i for i in library.items() if i.source == "snes")
    library.sessions.launch(game.id)
    assert library.sessions.forget_launch()
    library.sessions.session_ended(game.id, game.title, 4)
    assert [e for e in events if e["type"] == "closed"][-1].get("cancelled") is True
    assert library.state.inbox() == []
    library.sessions.launch(game.id)  # lo vuelves a abrir y lo juegas
    library.sessions.session_ended(game.id, game.title, 60)
    assert "cancelled" not in [e for e in events if e["type"] == "closed"][-1]
    assert [i["action"] for i in library.state.inbox()] == ["played"]


class _EndedEdge:
    def __init__(self, code):
        self.returncode = code

    def wait(self):
        return self.returncode


class _EndedEdge:
    def __init__(self, code):
        self.returncode = code

    def wait(self):
        return self.returncode


def test_closing_the_window_quits_but_a_crashed_edge_is_reopened(tmp_path, monkeypatch):
    """S3-D3: Alt+F4 (Edge sale con 0) cierra Orbital, como siempre. Si Edge truena o lo matan (otro código), no lo
    cerraste tú: se reabre (antes Orbital entero se cerraba y la tele se quedaba en el escritorio)."""
    closed, opened = [], []
    kiosk = KioskWindow("http://x", "edge", tmp_path / "perfil", keep_open=False, on_closed=lambda: closed.append(1),
                        hide_taskbar=False)
    kiosk.REOPEN_DELAY = 0
    monkeypatch.setattr(kiosk, "open", lambda: opened.append(1) or True)
    crashed = _EndedEdge(1)
    kiosk._process = crashed
    kiosk._watch(crashed)
    assert opened == [1] and closed == []
    by_user = _EndedEdge(0)
    kiosk._process = by_user
    kiosk._watch(by_user)
    assert opened == [1] and closed == [1]
