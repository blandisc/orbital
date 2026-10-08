import pytest

from orbital.config import parse_config
from orbital.library import vdf
from orbital.library.emulators import clean_title


def test_vdf_nested_comments_and_escapes():
    data = vdf.loads('// comentario\n"Root"\n{\n "Path" "C:\\\\Games"\n "Sub" { "k" "v" }\n}')
    assert data == {"root": {"path": "C:\\Games", "sub": {"k": "v"}}}


def test_vdf_unbalanced():
    with pytest.raises(ValueError):
        vdf.loads('"a" { "b" "c" } }')


def test_steam_scan_skips_tools(library):
    steam = [i for i in library.items() if i.category == "steam"]
    assert [i.title for i in steam] == ["Hades", "Hollow Knight"]
    assert steam[1].uri == "steam://rungameid/367520"
    assert library.get("steam:bigpicture").uri == "steam://open/bigpicture"


def test_emulator_scan_filters_and_cleans(library):
    roms = sorted(i.title for i in library.items() if i.category == "emulators")
    assert roms == ["Chrono Trigger", "Super Mario World"]
    item = library.find("super mario world")
    argv = item.runner().argv
    assert argv[1:3] == ["-L", "snes9x"] and argv[3].endswith("Super Mario World (USA).sfc")


def test_clean_title():
    assert clean_title("Zelda_-_Link's_Awakening (USA, Europe) (Rev 2).gb") == "Zelda - Link's Awakening"


def test_grouped_order(library):
    assert [r["id"] for r in library.grouped()] == ["steam", "emulators:snes", "media", "apps"]


def test_find_fuzzy(library):
    assert library.find("hollow").title == "Hollow Knight"
    assert library.find("jades").title == "Hades"
    assert library.find("chrono trigger").title == "Chrono Trigger"
    assert library.find("tetris") is None


def test_launch_uri_vs_process(library):
    library.launch("steam:367520")
    assert library.launcher.opened == ["steam://rungameid/367520"]
    assert library.launcher.steam_appids == [367520]
    library.launch("media:stremio")
    assert library.launcher.ran == [["stremio-test"]]


def test_config_rejects_unknown_and_duplicates():
    with pytest.raises(ValueError, match="desconocidas"):
        parse_config({"server": {"prot": 1}})
    with pytest.raises(ValueError, match="duplicados"):
        parse_config({"apps": [{"id": "a", "name": "A", "target": "x"}, {"id": "a", "name": "B", "target": "y"}]})
