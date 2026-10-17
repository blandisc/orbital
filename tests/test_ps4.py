from __future__ import annotations

import struct

from orbital.config import EmulatorConfig
from orbital.library import detect, emulators, ps4


def sfo(entries: dict[str, str]) -> bytes:
    keys = b"".join(k.encode() + b"\0" for k in entries)
    values = [v.encode() + b"\0" for v in entries.values()]
    key_start = 20 + 16 * len(entries)
    data_start = key_start + len(keys) + (-len(keys) % 4)
    index, k_off, d_off = b"", 0, 0
    for (k, _), v in zip(entries.items(), values, strict=True):
        index += struct.pack("<HHIII", k_off, 0x0204, len(v), len(v), d_off)
        k_off += len(k) + 1
        d_off += len(v)
    return (b"\0PSF" + struct.pack("<IIII", 0x101, key_start, data_start, len(entries)) + index + keys
            + b"\0" * (-len(keys) % 4) + b"".join(values))


def make_game(folder, **titles):
    (folder / "sce_sys").mkdir(parents=True)
    (folder / "eboot.bin").write_bytes(b"\0")
    (folder / "sce_sys" / "param.sfo").write_bytes(sfo({"TITLE_ID": "CUSA00900", **titles}))
    (folder / "sce_sys" / "icon0.png").write_bytes(b"png")


def test_param_sfo_gives_the_spanish_title_when_there_is_one(tmp_path):
    make_game(tmp_path / "CUSA00900", TITLE="Bloodborne", TITLE_20="Bloodborne (LATAM)")
    game = ps4.game_at(tmp_path / "CUSA00900")
    assert game.title == "Bloodborne (LATAM)" and game.title_id == "CUSA00900"
    assert game.icon == tmp_path / "CUSA00900" / "sce_sys" / "icon0.png" and game.background is None
    assert ps4.read_sfo(b"basura") == {}


def test_games_are_folders_and_updates_are_not_another_game(tmp_path):
    make_game(tmp_path / "Bloodborne.ps4", TITLE="Bloodborne")
    make_game(tmp_path / "sub" / "CUSA00900-UPDATE", TITLE="Bloodborne")
    (tmp_path / "vacia").mkdir()
    assert [g.title for g in ps4.find_games([tmp_path])] == ["Bloodborne"]


def test_shadps4_is_detected_and_its_games_open_with_their_eboot(tmp_path, monkeypatch):
    emu_dir = tmp_path / "Emulators" / "shadPS4"
    emu_dir.mkdir(parents=True)
    exe = emu_dir / "shadPS4.exe"
    exe.write_bytes(b"")
    found = detect.detect([detect.SearchDir(tmp_path / "Emulators")])
    ps4_cfg = next(e for e in found.emulators if e.id == "ps4")
    games = tmp_path / "juegos-ps4"
    make_game(games / "CUSA00900", TITLE="Bloodborne")
    (emu_dir / "user").mkdir()
    (emu_dir / "user" / "config.toml").write_text(f"[GUI]\ninstallDirs = ['{(games).as_posix()}']\n", encoding="utf-8")
    monkeypatch.setenv("APPDATA", str(tmp_path / "nada"))
    cfg = EmulatorConfig(**{**ps4_cfg.__dict__, "rom_dirs": [str(tmp_path / "ROMs" / "ps4")]})
    items = emulators.scan(cfg)
    assert [i.title for i in items] == ["Bloodborne"]
    argv = items[0].runners[0].argv
    assert argv == [str(exe), "--fullscreen", "true", "--game", str(games / "CUSA00900" / "eboot.bin")]
    assert items[0].art_path.endswith("icon0.png") and items[0].system == "ps4"


def test_ps3_disc_installed_and_iso_games_open_in_rpcs3(tmp_path):
    from orbital.library import ps3

    emu_dir = tmp_path / "Emulators" / "RPCS3"
    (emu_dir / "config").mkdir(parents=True)
    exe = emu_dir / "rpcs3.exe"
    exe.write_bytes(b"")
    # De disco, en ROMs/ps3 como lo nombra ES-DE
    disc = tmp_path / "ROMs" / "ps3" / "Demons Souls.ps3" / "PS3_GAME"
    (disc / "USRDIR").mkdir(parents=True)
    (disc / "USRDIR" / "EBOOT.BIN").write_bytes(b"")
    (disc / "PARAM.SFO").write_bytes(sfo({"TITLE": "Demon's Souls", "TITLE_ID": "BLUS30443", "CATEGORY": "DG"}))
    # Instalado en el disco duro de la consola (HG) y una actualización (GD) que no cuenta
    for serial, category in (("NPUB30001", "HG"), ("BLUS30443", "GD")):
        hdd = emu_dir / "dev_hdd0" / "game" / serial
        (hdd / "USRDIR").mkdir(parents=True)
        (hdd / "USRDIR" / "EBOOT.BIN").write_bytes(b"")
        (hdd / "PARAM.SFO").write_bytes(sfo({"TITLE": "Journey", "TITLE_ID": serial, "CATEGORY": category}))
    (emu_dir / "games").mkdir()
    (emu_dir / "games" / "Gran Turismo 5.iso").write_bytes(b"")
    found = detect.detect([detect.SearchDir(tmp_path / "Emulators")])
    cfg = next(e for e in found.emulators if e.id == "ps3")
    items = emulators.scan(EmulatorConfig(**{**cfg.__dict__, "rom_dirs": [str(tmp_path / "ROMs" / "ps3")]}))
    assert [i.title for i in items] == ["Demon's Souls", "Gran Turismo 5", "Journey"]
    assert items[0].runners[0].argv == [str(exe), "--no-gui", "--fullscreen", str(disc / "USRDIR" / "EBOOT.BIN")]
    assert ps3.known_paths(exe) == []
