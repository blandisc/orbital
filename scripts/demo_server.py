"""Orbital de mentiras para probar la interfaz (pruebas de humo, Playwright, revisar a mano).

Una biblioteca inventada en una carpeta temporal, sin tu config, sin tu estado, sin internet y sin
abrir nada de verdad (el lanzador solo anota). No interfiere con el Orbital real: otro puerto.

    python scripts/demo_server.py [--port 8730]
"""

from __future__ import annotations

import argparse
import sys
import tempfile
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import uvicorn  # noqa: E402

from orbital.catalog import Catalog  # noqa: E402
from orbital.config import parse_config  # noqa: E402
from orbital.library import cinemeta, geforcenow, stremio  # noqa: E402
from orbital.server import create_app  # noqa: E402

GAMES = {"367520": "Hollow Knight", "1145360": "Hades", "504230": "Celeste", "632360": "Risk of Rain 2",
         "1086940": "Baldur's Gate 3", "413150": "Stardew Valley"}


class DryLauncher:
    """Como el de verdad, pero no abre nada: recuerda qué "está abierto"."""

    def __init__(self) -> None:
        self.current = None
        self.on_exit = None
        self.on_timeout = None
        self.last_stopped_by_user = False

    def open_uri(self, uri):
        pass

    def run(self, argv, cwd=None):
        return object()

    def track_exe(self, item_id, title, exe, runner=None):
        self.track(item_id, title, None, runner=runner)

    def track(self, item_id, title, process, steam_appid=None, runner=None):
        self.current = {"id": item_id, "title": title, "managed": True, "runner": runner, "started": time.time(),
                        "pid": None}

    def status(self):
        return dict(self.current) if self.current else None

    def stop(self, force=False):
        cur, self.current = self.current, None
        self.last_stopped_by_user = True
        if cur and self.on_exit:
            self.on_exit(cur["id"], cur["title"], time.time() - cur["started"])
        return cur is not None


def build(tmp: Path):
    apps = tmp / "Steam" / "steamapps"
    apps.mkdir(parents=True)
    (apps / "libraryfolders.vdf").write_text(
        '"libraryfolders"\n{\n\t"0"\n\t{\n\t\t"path"\t\t"%s"\n\t}\n}\n' % str(tmp / "Steam").replace("\\", "\\\\"))
    for appid, name in GAMES.items():
        (apps / f"appmanifest_{appid}.acf").write_text(f'"AppState"\n{{\n\t"appid"\t\t"{appid}"\n\t"name"\t\t"{name}"\n}}\n')
    config = parse_config({
        "server": {"token": "demo"},
        "steam": {"path": str(tmp / "Steam")},
        "stremio": {"executable": ""},
        "esde": {"enabled": False},
        "detect": {"enabled": False},
        "apps": [{"id": "yt", "name": "YouTube", "target": "https://youtube.com/tv", "category": "media"}],
    })
    # Sin internet ni programas de este equipo.
    cinemeta.Cinemeta._get = lambda self, path: {"metas": []}
    stremio.find_stremio = lambda cfg: None
    geforcenow.install_dir = lambda: None
    geforcenow.read_shortcuts = list
    return create_app(config, Catalog(config, DryLauncher()))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8730)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="orbital-demo-") as tmp:
        uvicorn.run(build(Path(tmp)), host="127.0.0.1", port=args.port, log_level="warning")


if __name__ == "__main__":
    main()
