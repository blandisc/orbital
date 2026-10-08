import pytest
from fastapi.testclient import TestClient

from orbital.catalog import Catalog
from orbital.config import parse_config
from orbital.library import esde
from orbital.server import create_app

from conftest import FakeLauncher

GAMELIST = """<?xml version="1.0"?>
<alternativeEmulator>
    <label>Ryujinx (Standalone)</label>
</alternativeEmulator>
<gameList>
    <game>
        <path>./Zelda TOTK [0100F2C0115B6000][v0].nsp</path>
        <name>The Legend of Zelda: Tears of the Kingdom</name>
        <favorite>true</favorite>
    </game>
    <game>
        <path>./sub/Mario Kart 8 Deluxe.xci</path>
        <name>Mario Kart 8 Deluxe</name>
        <altemulator>Eden (Standalone)</altemulator>
    </game>
    <game>
        <path>./Hidden Game.nsp</path>
        <hidden>true</hidden>
    </game>
</gameList>
"""


@pytest.fixture
def esde_home(tmp_path):
    exe_dir = tmp_path / "ES-DE"
    home = exe_dir / "ES-DE"
    (home / "settings").mkdir(parents=True)
    (exe_dir / "ES-DE.exe").write_bytes(b"")
    (home / "settings" / "es_settings.xml").write_text(
        '<?xml version="1.0"?>\n<bool name="ScrapeCovers" value="true" />\n'
        '<string name="ROMDirectory" value="%ESPATH%/ROMs" />\n'
    )
    (home / "gamelists" / "switch").mkdir(parents=True)
    (home / "gamelists" / "switch" / "gamelist.xml").write_text(GAMELIST)
    roms = exe_dir / "ROMs" / "switch"
    (roms / "sub").mkdir(parents=True)
    for name in ["Zelda TOTK [0100F2C0115B6000][v0].nsp", "sub/Mario Kart 8 Deluxe.xci",
                 "Hidden Game.nsp", "Zelda TOTK [0100F2C0115B6800][v131072][UPD].nsp", "Metroid Dread.nsp"]:
        (roms / name).write_bytes(b"")
    covers = home / "downloaded_media" / "switch" / "covers"
    (covers / "sub").mkdir(parents=True)
    (covers / "Zelda TOTK [0100F2C0115B6000][v0].png").write_bytes(b"\x89PNG fake")
    (covers / "sub" / "Mario Kart 8 Deluxe.jpg").write_bytes(b"jpg")
    return home


@pytest.fixture
def catalog(esde_home):
    cfg = parse_config({
        "steam": {"enabled": False},
        "stremio": {"enabled": False},
        "esde": {"path": str(esde_home)},
        "detect": {"enabled": False},
        "emulators": [{
            "id": "switch", "name": "Nintendo Switch", "system": "switch", "executable": "ryujinx",
            "args": ["--fullscreen", "{rom}"], "extensions": [".nsp", ".xci"], "exclude": ["[upd]"],
        }],
    })
    cat = Catalog(cfg, FakeLauncher())
    cat.refresh()
    return cat


def test_settings_and_espath(esde_home):
    lib = esde.find(parse_config({"esde": {"path": str(esde_home)}}).esde)
    assert lib.rom_root == esde_home.parent / "ROMs"
    assert lib.media_root == esde_home / "downloaded_media"
    assert lib.executable == esde_home.parent / "ES-DE.exe"


def test_gamelist_names_hidden_exclude(catalog):
    titles = sorted(i.title for i in catalog.items() if i.category == "emulators")
    assert titles == ["Mario Kart 8 Deluxe", "Metroid Dread", "The Legend of Zelda: Tears of the Kingdom"]


def test_covers_and_favorites(catalog):
    zelda = catalog.find("zelda")
    assert zelda.favorite and zelda.art_path.endswith(".png")
    assert zelda.image == f"/api/art/{zelda.id}"
    assert catalog.find("mario kart").art_path.endswith("Mario Kart 8 Deluxe.jpg")
    assert catalog.find("metroid dread").image is None
    rows = catalog.grouped()
    assert rows[0]["title"] == "Favoritos" and [i["title"] for i in rows[0]["items"]] == [zelda.title]


def test_esde_app_shortcut(catalog):
    assert catalog.get("app:esde").argv[0].endswith("ES-DE.exe")


def test_voice_launches_with_gamelist_name(catalog):
    from orbital.voice import VoiceController
    assert VoiceController(catalog).handle_text("juega tears of the kingdom").ok
    assert catalog.launcher.ran[-1][:2] == ["ryujinx", "--fullscreen"]


def test_art_endpoint_only_serves_known_items(catalog):
    with TestClient(create_app(catalog.config, catalog), base_url="http://127.0.0.1:8710", client=("127.0.0.1", 1)) as c:
        zelda = catalog.find("zelda")
        assert c.get(f"/api/art/{zelda.id}").content == b"\x89PNG fake"
        assert c.get(f"/api/art/{catalog.find('metroid').id}").status_code == 404
        assert c.get("/api/art/../../etc/passwd").status_code == 404


def test_missing_gamelist_falls_back_to_filename(tmp_path):
    assert esde.load_gamelist(tmp_path / "nope.xml") == esde.Gamelist()
    bad = tmp_path / "bad.xml"
    bad.write_text("<gameList><game>")
    assert esde.load_gamelist(bad) == esde.Gamelist()


def make_switch_catalog(esde_home, tmp_path, system_label=None):
    downloads = tmp_path / "Downloads"
    for rel in ["publish/Ryujinx.exe", "Eden-Windows-v0.0.3/eden.exe"]:
        (downloads / rel).parent.mkdir(parents=True, exist_ok=True)
        (downloads / rel).write_bytes(b"")
    if system_label:
        gl = esde_home / "gamelists" / "switch" / "gamelist.xml"
        gl.write_text(gl.read_text().replace("Ryujinx (Standalone)", system_label))
    cfg = parse_config({
        "steam": {"enabled": False}, "stremio": {"enabled": False},
        "esde": {"path": str(esde_home)},
        "detect": {"enabled": False},
        "emulators": [
            {"id": "switch", "name": "Nintendo Switch", "system": "switch",
             "executable": str(downloads / "**" / "Ryujinx.exe"), "args": ["--fullscreen", "{rom}"],
             "extensions": [".nsp", ".xci"], "exclude": ["[upd]"]},
            {"id": "switch-eden", "name": "Eden", "system": "switch",
             "executable": str(downloads / "Eden-*" / "eden.exe"), "args": ["-f", "-g", "{rom}"]},
        ],
    })
    cat = Catalog(cfg, FakeLauncher())
    cat.refresh()
    return cat


def test_two_switch_emulators_share_one_list(esde_home, tmp_path):
    cat = make_switch_catalog(esde_home, tmp_path)
    switch_games = [i for i in cat.items() if i.category == "emulators"]
    assert len(switch_games) == 3 and {i.source for i in switch_games} == {"switch"}
    assert [r["title"] for r in cat.grouped() if r["id"].startswith("emulators")] == ["Nintendo Switch"]


def test_esde_choice_per_game_and_glob_paths(esde_home, tmp_path):
    cat = make_switch_catalog(esde_home, tmp_path)
    mk = cat.find("mario kart")  # <altemulator>Eden (Standalone)</altemulator>
    argv = mk.runner().argv
    assert argv[0].endswith("eden.exe") and argv[1:3] == ["-f", "-g"]
    assert [r.name for r in mk.runners] == ["Ryujinx", "Eden"]
    zelda = cat.find("zelda")  # sistema: Ryujinx (Standalone) -> principal
    argv = zelda.runner().argv
    assert argv[0].endswith("Ryujinx.exe") and argv[1] == "--fullscreen"


def test_system_level_choice(esde_home, tmp_path):
    cat = make_switch_catalog(esde_home, tmp_path, system_label="Eden (Standalone)")
    assert cat.find("metroid dread").runner().argv[0].endswith("eden.exe")


def test_hero_prefers_fanart(esde_home, catalog):
    fanart = esde_home / "downloaded_media" / "switch" / "fanart"
    fanart.mkdir(parents=True)
    (fanart / "Metroid Dread.jpg").write_bytes(b"fan")
    catalog.refresh()
    metroid = catalog.find("metroid dread")
    assert metroid.hero_path.endswith("fanart/Metroid Dread.jpg") and metroid.hero.endswith("?kind=hero")
    with TestClient(create_app(catalog.config, catalog), base_url="http://127.0.0.1:8710", client=("127.0.0.1", 1)) as c:
        assert c.get(metroid.hero).content == b"fan"


def test_prefer_alternative_runner(esde_home, tmp_path):
    cat = make_switch_catalog(esde_home, tmp_path)
    zelda = cat.find("zelda")
    cat.launch(zelda.id, "switch-eden")  # X: abrir una vez con Eden
    assert cat.launcher.ran[-1][0].endswith("eden.exe")
    assert cat.describe(zelda)["runner"] == "switch"  # el predeterminado no cambia
    cat.set_prefs(zelda.id, runner="switch-eden")  # "Usar siempre Eden"
    cat.launch(zelda.id)
    assert cat.launcher.ran[-1][0].endswith("eden.exe")
    with pytest.raises(ValueError):
        cat.set_prefs(zelda.id, runner="dolphin")
