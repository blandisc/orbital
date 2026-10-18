"""Accesos directos (.lnk) en carpetas de ROMs y juegos de Xbox 360 instalados en Xenia."""

import subprocess
import sys

import pytest

from orbital.config import EmulatorConfig
from orbital.library import emulators
from orbital.library.shortcuts import package_name, read_lnk, xenia_games


def make_package(path, name, magic=b"LIVE"):
    path.parent.mkdir(parents=True, exist_ok=True)
    head = bytearray(0x600)
    head[:4] = magic
    raw = name.encode("utf-16-be")
    head[0x411:0x411 + len(raw)] = raw
    path.write_bytes(bytes(head))


def make_lnk(lnk, target, arguments):
    script = (f"$s = (New-Object -ComObject WScript.Shell).CreateShortcut('{lnk}'); "
              f"$s.TargetPath = '{target}'; $s.Arguments = '{arguments}'; $s.Save()")
    subprocess.run(["powershell", "-NoProfile", "-Command", script], check=True, capture_output=True)


def test_package_name_from_stfs_header(tmp_path):
    pkg = tmp_path / "content" / "0000000000000000" / "415608C3" / "00007000" / "3A2136"
    make_package(pkg, "COD: Black Ops II")
    assert package_name(pkg) == "COD: Black Ops II"
    (tmp_path / "otro").write_bytes(b"MZ" + bytes(0x600))
    assert package_name(tmp_path / "otro") is None
    assert xenia_games(tmp_path / "content") == [(pkg, "COD: Black Ops II")]


@pytest.mark.skipif(sys.platform != "win32", reason="crea un .lnk con Windows")
def test_read_lnk_target_and_arguments(tmp_path):
    exe = tmp_path / "xenia_canary_netplay.exe"
    exe.write_bytes(b"MZ")
    game = tmp_path / "content" / "game"
    lnk = tmp_path / "Call of Duty.lnk"
    make_lnk(lnk, exe, f'--fullscreen "{game}"')
    shortcut = read_lnk(lnk)
    assert shortcut.target.lower() == str(exe).lower()
    assert shortcut.argv() == ["--fullscreen", str(game)]
    assert read_lnk(tmp_path / "content") is None


@pytest.mark.skipif(sys.platform != "win32", reason="crea un .lnk con Windows")
def test_xbox360_shortcut_and_installed_game_are_one_card(tmp_path):
    emu_dir = tmp_path / "xenia_canary_netplay"
    emu_dir.mkdir()
    exe = emu_dir / "xenia_canary_netplay.exe"
    exe.write_bytes(b"MZ")
    pkg = emu_dir / "content" / "0000000000000000" / "415608C3" / "00007000" / "3A2136"
    make_package(pkg, "COD: Black Ops II")
    make_package(emu_dir / "content" / "0000000000000000" / "584111F7" / "000D0000" / "ABCD", "Minecraft")
    roms = tmp_path / "roms"
    roms.mkdir()
    make_lnk(roms / "Call of Duty - Black Ops II.lnk", exe, f'--fullscreen "{pkg}"')
    make_lnk(roms / "Bloc de notas.lnk", r"C:\Windows\notepad.exe", "")  # otro programa: un port para PC
    emu = EmulatorConfig(id="xbox360", name="Xbox 360", executable=str(exe), system="xbox360",
                         args=["--fullscreen", "{rom}"], rom_dirs=[str(roms)], extensions=[".iso", ".xex"])
    items = emulators.scan(emu)
    assert [i.title for i in items] == ["Bloc de notas", "Call of Duty - Black Ops II", "Minecraft"]  # el .lnk manda en el nombre
    assert items[1].runners[0].argv == [str(exe), "--fullscreen", str(pkg)]
    assert items[0].default_runner == "pc"


@pytest.mark.skipif(sys.platform != "win32", reason="crea un .lnk con Windows")
def test_esde_lookups_use_the_shortcut_not_the_installed_game(tmp_path):
    # Con ES-DE, Orbital preguntaba por la ruta del paquete (fuera de la carpeta de ROMs) y no arrancaba.
    emu_dir = tmp_path / "xenia"
    emu_dir.mkdir()
    exe = emu_dir / "xenia_canary_netplay.exe"
    exe.write_bytes(b"MZ")
    pkg = emu_dir / "content" / "0" / "415608C3" / "00007000" / "3A2136"
    make_package(pkg, "COD: Black Ops II")
    roms = tmp_path / "ROMs" / "xbox360"
    roms.mkdir(parents=True)
    lnk = roms / "Call of Duty - Black Ops II.lnk"
    make_lnk(lnk, exe, f'--fullscreen "{pkg}"')

    class FakeEsde:
        asked = []

        def system_dir(self, system): return roms

        def _check(self, rom):
            self.asked.append(rom)
            rom.relative_to(roms)  # truena si no es un archivo de la carpeta de ROMs
            return None

        meta = lambda self, system, rom: self._check(rom)  # noqa: E731
        chosen_emulator = meta
        cover = meta
        logo = meta
        hero = meta

    emu = EmulatorConfig(id="xbox360", name="Xbox 360", executable=str(exe), system="xbox360",
                         args=["--fullscreen", "{rom}"], extensions=[".iso"])
    items = emulators.scan(emu, FakeEsde())
    assert [i.title for i in items] == ["Call of Duty - Black Ops II"] and set(FakeEsde.asked) == {lnk}


@pytest.mark.skipif(sys.platform != "win32", reason="crea un .lnk con Windows")
def test_geforce_now_shortcuts_without_powershell(tmp_path, monkeypatch):
    from orbital.library import geforcenow

    monkeypatch.undo()  # el conftest apaga la lectura real de accesos directos de GFN

    exe = tmp_path / "NVIDIA Corporation" / "GeForceNOW" / "CEF" / "GeForceNOW.exe"
    exe.parent.mkdir(parents=True)
    exe.write_bytes(b"MZ")
    desktop = tmp_path / "Desktop"
    (desktop / "Juegos").mkdir(parents=True)
    make_lnk(desktop / "Juegos" / "Fortnite.lnk", exe, '--url-route="#?cmsId=100013311&launchSource=External"')
    make_lnk(desktop / "Bloc de notas.lnk", tmp_path / "notepad.exe", "")
    games = geforcenow.read_shortcuts([desktop])
    assert [(g["title"], g["cms_id"]) for g in games] == [("Fortnite", "100013311")]
    assert games[0]["target"].lower() == str(exe).lower()


@pytest.mark.skipif(sys.platform != "win32", reason="crea un .lnk con Windows")
def test_a_pc_port_shortcut_shows_up_in_its_consoles_section(tmp_path):
    """God of War III de PS4 con gow3_pc: su acceso directo en ROMs/ps4 sale en PlayStation 4 y abre el port directo."""
    port = tmp_path / "GoW3-PC" / "Play God of War III.exe"
    port.parent.mkdir()
    port.write_bytes(b"MZ")
    roms = tmp_path / "ROMs" / "ps4"
    roms.mkdir(parents=True)
    make_lnk(roms / "God of War III Remastered.lnk", port, "")
    emu_exe = tmp_path / "shadPS4" / "shadPS4.exe"
    emu_exe.parent.mkdir()
    emu_exe.write_bytes(b"MZ")
    make_lnk(roms / "Abre shadPS4.lnk", emu_exe, "")  # abre el emulador sin juego: no es un port
    cfg = EmulatorConfig(id="ps4", name="PlayStation 4", system="ps4", executable=str(emu_exe), args=["{rom}"],
                         rom_dirs=[str(roms)], extensions=[])
    items = emulators.scan(cfg)
    assert [i.title for i in items] == ["God of War III Remastered"]
    game = items[0]
    assert game.source == "ps4" and game.default_runner == "pc" and game.extra["port"]
    assert game.runners[0].argv == [str(port)] and game.runners[0].name == "PC"
    assert game.runners[0].cwd.lower() == str(port.parent).lower()
