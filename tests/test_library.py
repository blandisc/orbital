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
    library.sessions.launch("steam:367520")
    assert library.launcher.opened == ["steam://rungameid/367520"]
    assert library.launcher.steam_appids == [367520]
    library.sessions.launch("media:stremio")
    assert library.launcher.ran == [["stremio-test"]]


def test_config_rejects_unknown_and_duplicates():
    with pytest.raises(ValueError, match="desconocidas"):
        parse_config({"server": {"prot": 1}})
    with pytest.raises(ValueError, match="duplicados"):
        parse_config({"apps": [{"id": "a", "name": "A", "target": "x"}, {"id": "a", "name": "B", "target": "y"}]})


def test_steam_hours_size_update_and_recent_outside_orbital(tmp_path):
    from conftest import FakeLauncher, write_steam

    from orbital.catalog import Catalog
    from orbital.config import parse_config
    from orbital.library import steam

    root = tmp_path / "Steam"
    write_steam(root, {"427520": "Factorio", "2767030": "Marvel Rivals"})
    rivals = root / "steamapps" / "appmanifest_2767030.acf"
    rivals.write_text(rivals.read_text().replace('"name"', '"StateFlags"\t\t"6"\n\t"SizeOnDisk"\t\t"93500000000"\n\t"name"'))
    config = root / "userdata" / "123" / "config"
    config.mkdir(parents=True)
    (config / "localconfig.vdf").write_text(
        '"UserLocalConfigStore"\n{\n"Software"\n{\n"Valve"\n{\n"Steam"\n{\n"apps"\n{\n'
        '"427520"\n{\n"LastPlayed"\t\t"1787548526"\n"Playtime"\t\t"2226"\n}\n}\n}\n}\n}\n}\n')
    factorio, marvel = sorted(steam.scan(root), key=lambda i: i.title)
    assert factorio.extra["steam_playtime"] == 2226 * 60 and factorio.extra["steam_last_played"] == 1787548526
    assert factorio.extra["logo"].endswith("/427520/logo.png") and not factorio.extra["update"]
    assert marvel.extra["update"] and marvel.extra["size"] == 93_500_000_000

    cat = Catalog(parse_config({"steam": {"path": str(root)}, "stremio": {"enabled": False},
                                "esde": {"enabled": False}, "detect": {"enabled": False}}), FakeLauncher())
    cat.refresh()
    recent = next(r for r in cat.grouped() if r["id"] == "recent")
    assert [i["title"] for i in recent["items"]] == ["Factorio"]  # jugado en Steam, no desde Orbital
    assert recent["items"][0]["playtime"] == 2226 * 60


def test_refresh_steam_stats_after_playing(library, monkeypatch):
    import orbital.library.steam as steam

    events = []
    library.listeners.append(events.append)
    monkeypatch.setattr(steam, "user_stats", lambda root: {"367520": {"last_played": 1790000000, "playtime": 7200}})
    library.refresh_steam_stats()
    hollow = library.describe(library.get("steam:367520"))
    assert hollow["playtime"] == 7200 and hollow["last_played"] == 1790000000
    assert events[-1] == {"type": "library-changed"}


def test_library_from_last_start_is_shown_while_scanning(library, tmp_path):
    library._snapshot = tmp_path / "library.json"
    library.refresh()  # guarda la biblioteca
    assert library._snapshot.exists()
    from orbital.catalog import Catalog
    from tests.conftest import FakeLauncher

    fresh = Catalog(library.config, FakeLauncher())
    fresh._snapshot = library._snapshot
    assert fresh.load_snapshot()  # sin escanear: ya está todo
    assert {i.id for i in fresh.items()} == {i.id for i in library.items()}
    fresh._snapshot.write_text("{dañado", encoding="utf-8")
    assert not fresh.load_snapshot()


def test_steam_game_opens_with_steam_already_in_the_background(library, monkeypatch):
    """Con Steam cerrado, steam://rungameid mostraba toda su ventana: antes se abre en silencio."""
    from orbital.library import steam

    calls = []
    monkeypatch.setattr(steam, "ready_silent", lambda root: calls.append(root))
    item = next(i for i in library.items() if i.title == "Hollow Knight")
    library.sessions.launch(item.id)
    assert len(calls) == 1
    assert library.launcher.opened[-1] == "steam://rungameid/367520"
    library.config.steam.silent_start = False
    library.sessions.launch(item.id)
    assert len(calls) == 1  # apagado en config.yaml: como antes
