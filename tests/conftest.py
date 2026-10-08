from __future__ import annotations

import pytest

from orbital.catalog import Catalog
from orbital.config import parse_config


class FakeLauncher:
    def __init__(self):
        self.opened: list[str] = []
        self.ran: list[list[str]] = []
        self.current = None
        self.on_exit = None
        self.steam_appids: list[int | None] = []

    def open_uri(self, uri):
        self.opened.append(uri)

    def run(self, argv, cwd=None):
        self.ran.append(argv)
        return object()  # basta con que no sea None: cuenta como proceso propio

    def track(self, item_id, title, process, steam_appid=None):
        self.steam_appids.append(steam_appid)
        self.current = {"id": item_id, "title": title, "managed": process is not None}

    def status(self):
        return self.current

    def finish(self, seconds):
        """Simula que el juego en curso se cerró tras `seconds` segundos."""
        cur, self.current = self.current, None
        self.on_exit(cur["id"], cur["title"], seconds)

    def stop(self):
        was = self.current is not None and self.current["managed"]
        self.current = None
        return was


def write_steam(root, games):
    apps = root / "steamapps"
    apps.mkdir(parents=True)
    (apps / "libraryfolders.vdf").write_text(
        '"libraryfolders"\n{\n\t"0"\n\t{\n\t\t"path"\t\t"%s"\n\t}\n}\n' % str(root).replace("\\", "\\\\")
    )
    for appid, name in games.items():
        (apps / f"appmanifest_{appid}.acf").write_text(
            f'"AppState"\n{{\n\t"appid"\t\t"{appid}"\n\t"name"\t\t"{name}"\n}}\n'
        )


@pytest.fixture
def library(tmp_path):
    steam_root = tmp_path / "Steam"
    write_steam(steam_root, {
        "367520": "Hollow Knight",
        "1145360": "Hades",
        "1493710": "Proton Experimental",
    })
    roms = tmp_path / "roms"
    (roms / "sub").mkdir(parents=True)
    (roms / "Super Mario World (USA).sfc").write_bytes(b"")
    (roms / "sub" / "Chrono_Trigger [!].smc").write_bytes(b"")
    (roms / "notes.txt").write_text("x")
    cfg = parse_config({
        "server": {"token": "secreto"},
        "steam": {"path": str(steam_root)},
        "stremio": {"executable": "stremio-test"},
        "esde": {"enabled": False},
        "emulators": [{
            "id": "snes", "name": "Super Nintendo", "executable": "retroarch",
            "args": ["-L", "snes9x", "{rom}"], "rom_dirs": [str(roms)], "extensions": ["sfc", ".SMC"],
        }],
        "apps": [{"id": "yt", "name": "YouTube", "target": "https://youtube.com/tv", "category": "media"}],
    })
    catalog = Catalog(cfg, FakeLauncher())
    catalog.refresh()
    return catalog
