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
    make_lnk(roms / "Bloc de notas.lnk", r"C:\Windows\notepad.exe", "")  # no es de este emulador: se ignora
    emu = EmulatorConfig(id="xbox360", name="Xbox 360", executable=str(exe), system="xbox360",
                         args=["--fullscreen", "{rom}"], rom_dirs=[str(roms)], extensions=[".iso", ".xex"])
    items = emulators.scan(emu)
    assert [i.title for i in items] == ["Call of Duty - Black Ops II", "Minecraft"]  # el .lnk manda en el nombre
    assert items[0].runners[0].argv == [str(exe), "--fullscreen", str(pkg)]
