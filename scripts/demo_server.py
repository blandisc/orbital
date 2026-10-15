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
sys.path.insert(0, str(Path(__file__).resolve().parent))

import demo_foryou  # noqa: E402
import demo_tv  # noqa: E402
import uvicorn  # noqa: E402

from orbital.catalog import Catalog  # noqa: E402
from orbital.config import parse_config  # noqa: E402
from orbital.library import cinemeta, geforcenow, stremio  # noqa: E402
from orbital.server import create_app  # noqa: E402

GAMES = {"367520": "Hollow Knight", "1145360": "Hades", "504230": "Celeste", "632360": "Risk of Rain 2",
         "1086940": "Baldur's Gate 3", "413150": "Stardew Valley", "1313140": "Cult of the Lamb", "440": "Team Fortress 2",
         "2499520": "Be My Horde"}
# Consolas inventadas (sin arte: así se ven los respaldos) para probar el Inicio y Tus consolas.
CONSOLES = {
    "switch": ("Nintendo Switch", ".nsp", ["Mario Party Superstars", "Super Mario Bros Wonder", "Zelda Tears of the Kingdom"]),
    "gc": ("Nintendo GameCube", ".iso", ["Pikmin 2", "Super Smash Bros. Melee"]),
    "gba": ("Game Boy Advance", ".gba", ["Pokemon Emerald", "Kirby Amazing Mirror", "Metroid Fusion"]),
    "psp": ("PlayStation Portable", ".iso", ["Metal Slug Anthology"]),
    "xbox360": ("Xbox 360", ".iso", ["Halo 3", "Gears of War"]),
    "wii": ("Nintendo Wii", ".iso", ["Wii Sports"]),
}
# Portadas de GBA de verdad (el navegador las trae de libretro): son cajas casi cuadradas, no pósters.
LIBRETRO = "https://thumbnails.libretro.com/Nintendo%20-%20Game%20Boy%20Advance/Named_Boxarts/"
GBA_ART = {"Pokemon Emerald": "Pokemon%20-%20Emerald%20Version%20(USA%2C%20Europe).png",
           "Kirby Amazing Mirror": "Kirby%20%26%20The%20Amazing%20Mirror%20(USA).png",
           "Metroid Fusion": "Metroid%20Fusion%20(USA).png"}
# Lo último que "jugaste" (minutos atrás): llena Continuar y el destacado.
PLAYED = {"steam:1145360": 30, "Mario Party Superstars": 240, "Pikmin 2": 1500, "steam:367520": 2900, "Pokemon Emerald": 4000}


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


def no_side_effects() -> None:
    """Nada de lo que se pulse en el demo toca este equipo: ni volumen, brillo o energía, ni apagar,
    ni ventanas, ni capturas, ni la música, ni cerrar programas, ni actualizar (git) la carpeta.
    (Un agente cambió el modo de energía de verdad desde el Panel rápido del demo.)"""
    from orbital import capture, memory, music, quick, system, updater
    from orbital.shell import ConsoleShell

    fake = {"level": 60, "muted": False, "brightness": 70, "mode": "balanced"}

    def set_volume(level=None, muted=None):
        if level is not None:
            fake["level"] = max(0, min(100, int(level)))
        if muted is not None:
            fake["muted"] = bool(muted)
        return {"level": fake["level"], "muted": fake["muted"]}

    def set_brightness(level):
        fake["brightness"] = max(0, min(100, int(level)))
        return fake["brightness"]

    quick.volume = lambda: {"level": fake["level"], "muted": fake["muted"]}
    quick.set_volume = set_volume
    quick.brightness = lambda: fake["brightness"]
    quick.set_brightness = set_brightness
    quick.power_mode = lambda: fake["mode"]
    quick.set_power_mode = lambda mode: fake.update(mode=mode) or mode
    system.power = lambda action: print(f"[demo] {action} (no se hizo)")
    capture.take = lambda title="": None
    music.command = lambda action: False
    memory.close = lambda exe, protect_pids=None: 0
    ConsoleShell.open_windows = lambda self: []
    ConsoleShell.focus_window = lambda self, hwnd: False
    updater.Updater.apply = lambda self, progress=lambda m: None: (False, "En el demo no se actualiza.")


def build(tmp: Path):
    apps = tmp / "Steam" / "steamapps"
    apps.mkdir(parents=True)
    (apps / "libraryfolders.vdf").write_text(
        '"libraryfolders"\n{\n\t"0"\n\t{\n\t\t"path"\t\t"%s"\n\t}\n}\n' % str(tmp / "Steam").replace("\\", "\\\\"))
    for appid, name in GAMES.items():
        (apps / f"appmanifest_{appid}.acf").write_text(f'"AppState"\n{{\n\t"appid"\t\t"{appid}"\n\t"name"\t\t"{name}"\n}}\n')
    emulators = []
    for system, (name, ext, titles) in CONSOLES.items():
        roms = tmp / "ROMs" / system
        roms.mkdir(parents=True)
        for title in titles:
            (roms / f"{title}{ext}").write_bytes(b"")
        emulators.append({"id": system, "name": name, "system": system, "executable": str(tmp / "emu.exe"),
                          "rom_dirs": [str(roms)], "extensions": [ext]})
    (tmp / "emu.exe").write_bytes(b"")
    config = parse_config({
        "server": {"token": "demo"},
        "emulators": emulators,
        "art": {"scrape": False, "dir": str(tmp / "media")},
        "steam": {"path": str(tmp / "Steam")},
        "stremio": {"executable": ""},
        "esde": {"enabled": False},
        "detect": {"enabled": False},
        "apps": [{"id": "yt", "name": "YouTube", "target": "https://youtube.com/tv", "category": "media"}],
    })
    # Sin internet ni programas de este equipo.
    no_side_effects()
    cinemeta.Cinemeta._get = lambda self, path: {"metas": []}
    stremio.find_stremio = lambda cfg: None
    geforcenow.install_dir = lambda: None
    geforcenow.read_shortcuts = list
    catalog = Catalog(config, DryLauncher())
    catalog.refresh()
    now = time.time()
    for item in catalog.store.all():
        minutes = PLAYED.get(item.id, PLAYED.get(item.title))
        if minutes:
            catalog.state.record_launch(item.id, now=now - minutes * 60)
    # «Para ti»: horas y un favorito (para «Tu más jugado» y «Tu favorito») y servicios de mentiras.
    refresh = catalog.refresh

    def refresh_with_gba_art(*args, **kwargs):  # cada vez que se vuelve a leer la biblioteca
        found = refresh(*args, **kwargs)
        for item in catalog.store.all():
            if item.system == "gba" and item.title in GBA_ART:
                item.image = LIBRETRO + GBA_ART[item.title]
                item.extra.pop("placeholder_cover", None)
        return found

    catalog.refresh = refresh_with_gba_art
    catalog.refresh()
    catalog.state.record_session("steam:1145360", 48 * 3600)
    catalog.state.record_session("steam:2499520", 5 * 3600)
    catalog.state.record_session("steam:1086940", 62 * 3600)
    catalog.set_prefs("steam:367520", favorite=True)
    demo_foryou.install(catalog)
    demo_tv.install(catalog, tmp)  # «TV en vivo»: canales y logos de mentiras, sin Internet ni mpv
    return create_app(config, catalog)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8730)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="orbital-demo-") as tmp:
        uvicorn.run(build(Path(tmp)), host="127.0.0.1", port=args.port, log_level="warning",
                    timeout_graceful_shutdown=2)  # con /api/events abierto no terminaba nunca


if __name__ == "__main__":
    main()
