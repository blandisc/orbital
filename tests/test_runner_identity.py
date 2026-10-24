"""El emulador elegido se queda aunque el archivo cambie de nombre o de carpeta."""

from pathlib import Path

from conftest import FakeLauncher

from orbital.catalog import Catalog
from orbital.config import parse_config
from orbital.library.identity import base_title_id, file_fingerprint, runner_keys, switch_title_id
from orbital.library.models import LibraryItem
from orbital.state import State


def test_switch_title_id_base_update_dlc_and_case():
    assert switch_title_id("Zelda TOTK [0100F2C0115B6000][v0].nsp") == "0100F2C0115B6000"
    assert switch_title_id("Zelda [0100f2c0115b6800][UPD].nsp") == "0100F2C0115B6000"
    assert switch_title_id("DLC [0100F2C0115B6001].nsp") == "0100F2C0115B6000"
    assert switch_title_id("BOTW (01007EF00011E000).xci") == "01007EF00011E000"
    assert switch_title_id("Mario Party Superstars[01006FE013472000][US][v0]") == "01006FE013472000"
    assert switch_title_id("Mario Kart 8 Deluxe.xci") is None
    assert base_title_id("01007ef00011e800") == "01007EF00011E000"
    assert base_title_id("01007EF00011E000") == "01007EF00011E000"


def test_runner_keys_switch_and_fallback():
    zelda = LibraryItem(
        id="emu:switch:abc123def456", title="The Legend of Zelda: Tears of the Kingdom",
        category="emulators", source="switch", system="switch",
        media_key="The Legend of Zelda Tears of the Kingdom [0100F2C0115B6000][v0][US]",
        extra={"fp": "deadbeef1234"},
    )
    keys = runner_keys(zelda)
    assert keys[0] == "emu:switch:tid:0100F2C0115B6000"
    assert "emu:switch:fp:deadbeef1234" in keys
    assert "emu:switch:title:the legend of zelda tears of the kingdom" in keys
    assert keys[-1] == zelda.id

    kirby = LibraryItem(
        id="emu:switch:kirbyoldid", title="Kirby and the Forgotten Land",
        category="emulators", source="switch", system="switch",
        media_key="Kirby and the Forgotten Land",
    )
    k = runner_keys(kirby)
    assert k[0] == "emu:switch:title:kirby and the forgotten land"
    assert "tid:" not in ",".join(k)
    assert k[-1] == kirby.id

    snes = LibraryItem(
        id="emu:snes:smw", title="Super Mario World", category="emulators", source="snes",
        system="snes", media_key="Super Mario World (USA)",
    )
    assert runner_keys(snes) == ["emu:snes:title:super mario world", "emu:snes:smw"]

    steam = LibraryItem(id="steam:367520", title="Hollow Knight", category="steam", source="steam")
    assert runner_keys(steam) == ["steam:367520"]


def test_fingerprint_skips_empty(tmp_path):
    empty = tmp_path / "empty.nsp"
    empty.write_bytes(b"")
    filled = tmp_path / "game.nsp"
    filled.write_bytes(b"nsp-header" * 20)
    assert file_fingerprint(empty) is None
    assert file_fingerprint(filled) == file_fingerprint(Path(str(filled)))
    other = tmp_path / "other.nsp"
    other.write_bytes(b"other-header" * 20)
    assert file_fingerprint(filled) != file_fingerprint(other)


def _payload(tag: str) -> bytes:
    return (tag.encode() * 40)[:256]


def _switch_catalog(tmp_path, files: dict[str, bytes], state=None) -> Catalog:
    roms = tmp_path / "roms" / "switch"
    roms.mkdir(parents=True, exist_ok=True)
    for name, data in files.items():
        dest = roms / name
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(data)
    emu = tmp_path / "emu"
    ryu, eden = emu / "Ryujinx.exe", emu / "eden.exe"
    emu.mkdir(exist_ok=True)
    ryu.write_bytes(b"")
    eden.write_bytes(b"")
    cfg = parse_config({
        "steam": {"enabled": False}, "stremio": {"enabled": False},
        "esde": {"enabled": False}, "detect": {"enabled": False},
        "emulators": [
            {"id": "switch", "name": "Nintendo Switch", "system": "switch",
             "executable": str(ryu), "args": ["--fullscreen", "{rom}"],
             "extensions": [".nsp", ".xci"], "exclude": ["[upd]"], "rom_dirs": [str(roms)]},
            {"id": "switch-eden", "name": "Eden", "system": "switch",
             "executable": str(eden), "args": ["-f", "-g", "{rom}"], "rom_dirs": [str(roms)]},
        ],
    })
    cat = Catalog(cfg, FakeLauncher(), state=state)
    cat.refresh()
    return cat


def test_runner_survives_rename_and_move(tmp_path):
    cat = _switch_catalog(tmp_path, {
        "Zelda TOTK [0100F2C0115B6000][v0].nsp": _payload("totk"),
        "Luigi's Mansion 3.nsp": _payload("luigi"),
    })
    zelda = cat.find("zelda")
    luigi = cat.find("luigi")
    cat.set_prefs(zelda.id, runner="switch-eden")
    cat.set_prefs(luigi.id, runner="switch-eden")
    roms = tmp_path / "roms" / "switch"
    (roms / "Zelda TOTK [0100F2C0115B6000][v0].nsp").rename(roms / "TOTK.nsp")
    moved = roms / "moved"
    moved.mkdir()
    (roms / "Luigi's Mansion 3.nsp").rename(moved / "Luigi's Mansion 3.nsp")
    cat.refresh()
    again_z = cat.find("totk")
    again_l = cat.find("luigi")
    assert again_z.id != zelda.id and cat.describe(again_z)["runner"] == "switch-eden"
    assert again_l.id != luigi.id and cat.describe(again_l)["runner"] == "switch-eden"
    cat.sessions.launch(again_z.id)
    assert cat.launcher.ran[-1][0].endswith("eden.exe")


def test_migration_from_path_keys_is_idempotent_and_keeps_old(tmp_path):
    state = State(tmp_path / "state.json")
    cat = _switch_catalog(tmp_path, {
        "The Legend of Zelda - Breath of the Wild.nsp": _payload("botw"),
        "Mario Kart 8 Deluxe [0100152000022000][USA][v0].nsp": _payload("mk8"),
    }, state=state)
    botw = cat.find("breath of the wild")
    mk8 = cat.find("mario kart")
    # Como el state.json de hoy: solo la clave por ruta.
    cat.state.set_pref(botw.id, "runner", "switch-eden")
    cat.state.set_pref(mk8.id, "runner", "switch-eden")
    assert cat.describe(botw)["runner"] == "switch-eden"  # se lee la clave vieja
    n = cat.state.migrate_runner_prefs([(botw.id, runner_keys(botw)), (mk8.id, runner_keys(mk8))])
    assert n >= 2
    for game in (botw, mk8):
        for key in runner_keys(game):
            assert cat.state.prefs(key).get("runner") == "switch-eden"
    # No se pierde la entrada vieja ni al repetir.
    assert cat.state.prefs(botw.id)["runner"] == "switch-eden"
    assert cat.state.migrate_runner_prefs([(botw.id, runner_keys(botw)), (mk8.id, runner_keys(mk8))]) == 0
    again = State(tmp_path / "state.json")
    assert again.prefs(botw.id)["runner"] == "switch-eden"
    assert again.prefs("emu:switch:tid:0100152000022000")["runner"] == "switch-eden"
    assert again.prefs("emu:switch:title:the legend of zelda breath of the wild")["runner"] == "switch-eden"


def test_refresh_migrates_existing_path_prefs(tmp_path):
    state = State(tmp_path / "state.json")
    files = {"Super Smash Bros Ultimate.nsp": _payload("smash")}
    cat = _switch_catalog(tmp_path, files, state=state)
    smash = cat.find("smash")
    cat.state.set_pref(smash.id, "runner", "switch-eden")
    cat.refresh()
    smash = cat.find("smash")
    assert "emu:switch:title:super smash bros ultimate" in cat.state._data["prefs"]
    assert cat.describe(smash)["runner"] == "switch-eden"


def test_non_switch_fallback_is_title_and_system(tmp_path):
    roms = tmp_path / "roms"
    roms.mkdir()
    (roms / "Super Mario World (USA).sfc").write_bytes(_payload("smw"))
    emu = tmp_path / "emu"
    emu.mkdir()
    (emu / "a.exe").write_bytes(b"")
    (emu / "b.exe").write_bytes(b"")
    cfg = parse_config({
        "steam": {"enabled": False}, "stremio": {"enabled": False},
        "esde": {"enabled": False}, "detect": {"enabled": False},
        "emulators": [
            {"id": "snes", "name": "Super Nintendo", "system": "snes",
             "executable": str(emu / "a.exe"), "args": ["{rom}"],
             "rom_dirs": [str(roms)], "extensions": [".sfc"]},
            {"id": "snes-alt", "name": "Otra", "system": "snes",
             "executable": str(emu / "b.exe"), "args": ["-alt", "{rom}"],
             "rom_dirs": [str(roms)]},
        ],
    })
    cat = Catalog(cfg, FakeLauncher(), state=State(tmp_path / "state.json"))
    cat.refresh()
    smw = cat.find("super mario world")
    assert smw.system == "snes" and {r.id for r in smw.runners} == {"snes", "snes-alt"}
    cat.set_prefs(smw.id, runner="snes-alt")
    (roms / "Super Mario World (USA).sfc").rename(roms / "Super Mario World.sfc")
    cat.refresh()
    again = cat.find("super mario world")
    assert again.id != smw.id and cat.describe(again)["runner"] == "snes-alt"
    (roms / "Super Mario World.sfc").rename(roms / "SMW.sfc")
    cat.refresh()
    short = cat.find("smw")
    assert cat.describe(short)["runner"] == "snes-alt"  # huella: el nombre ya no coincide
