"""Juegos de PlayStation 3 (RPCS3).

Como los de PS4, un juego de PS3 suele ser una carpeta, no un archivo:
  · de disco: <carpeta>/PS3_GAME/ con PARAM.SFO (nombre), ICON0.PNG, PIC1.PNG y USRDIR/EBOOT.BIN; ES-DE nombra la carpeta
    «Juego.ps3» y RPCS3 trae su propia carpeta `games/` («Disc Games Can Be Put Here»);
  · instalado (PSN o desde disco): RPCS3/dev_hdd0/game/<SERIE>/ con PARAM.SFO de categoría HG;
  · un .iso (RPCS3 los abre directo).
Además, RPCS3 anota en config/games.yml dónde están los que ya abriste («SERIE: ruta»). A RPCS3 se le da el EBOOT.BIN
(o el .iso) con --no-gui y --fullscreen: abre el juego directo, a pantalla completa y sin su ventana.
"""

from __future__ import annotations

import logging
import os
from collections.abc import Iterable
from dataclasses import dataclass
from pathlib import Path

from .ps4 import read_sfo

log = logging.getLogger(__name__)

_TITLE_KEYS = ("TITLE_03", "TITLE")  # español, y si no, el de siempre
_MAX_SFO = 64 * 1024
_SKIP_DIRS = {"$locks", "＄locks", "shortcuts"}


@dataclass(frozen=True)
class Ps3Game:
    folder: Path
    boot: Path  # el EBOOT.BIN (o el .iso)
    title: str
    title_id: str | None
    icon: Path | None
    background: Path | None


def _sfo(path: Path) -> dict:
    try:
        with open(path, "rb") as f:
            return read_sfo(f.read(_MAX_SFO))
    except OSError:
        return {}


def _title(sfo: dict, fallback: str) -> str:
    for key in _TITLE_KEYS:
        value = sfo.get(key)
        if isinstance(value, str) and value.strip():
            return " ".join(value.split())
    return fallback.removesuffix(".ps3").removesuffix(".PS3")


def _art(folder: Path, name: str) -> Path | None:
    path = folder / name
    return path if path.is_file() else None


def disc_game(folder: Path) -> Ps3Game | None:
    """Un juego de disco: la carpeta con PS3_GAME/ dentro (o la PS3_GAME misma)."""
    game = folder / "PS3_GAME" if (folder / "PS3_GAME").is_dir() else folder if folder.name.upper() == "PS3_GAME" else None
    if game is None:
        return None
    boot = game / "USRDIR" / "EBOOT.BIN"
    if not boot.is_file():
        return None
    sfo = _sfo(game / "PARAM.SFO")
    root = game.parent if game.name.upper() == "PS3_GAME" else game
    title_id = sfo.get("TITLE_ID")
    return Ps3Game(root, boot, _title(sfo, root.name), title_id if isinstance(title_id, str) and title_id else None,
                   _art(game, "ICON0.PNG"), _art(game, "PIC1.PNG"))


def hdd_game(folder: Path) -> Ps3Game | None:
    """Un juego instalado en el disco duro de la consola (categoría HG). Las actualizaciones y los datos (GD) no cuentan."""
    sfo = _sfo(folder / "PARAM.SFO")
    boot = folder / "USRDIR" / "EBOOT.BIN"
    if sfo.get("CATEGORY") != "HG" or not boot.is_file():
        return None
    title_id = sfo.get("TITLE_ID")
    return Ps3Game(folder, boot, _title(sfo, folder.name), title_id if isinstance(title_id, str) and title_id else None,
                   _art(folder, "ICON0.PNG"), _art(folder, "PIC1.PNG"))


def find_games(roots: Iterable[Path], hdd: Path | None = None, extra: Iterable[Path] = (), depth: int = 2) -> list[Ps3Game]:
    """Los juegos de disco (y .iso) en esas carpetas, los instalados en `hdd` y los de `extra` (games.yml)."""
    found: dict[str, Ps3Game] = {}

    def add(game: Ps3Game | None) -> bool:
        if game is None:
            return False
        found.setdefault(os.path.normcase(str(game.boot)), game)
        return True

    def walk(folder: Path, left: int) -> None:
        if add(disc_game(folder)):
            return
        try:
            entries = sorted(folder.iterdir())
        except OSError:
            return
        for entry in entries:
            if entry.name in _SKIP_DIRS or entry.name.startswith("."):
                continue
            if entry.is_file() and entry.suffix.lower() == ".iso":
                add(Ps3Game(entry.parent, entry, _title({}, entry.stem), None, None, None))
            elif entry.is_dir() and left > 0:
                walk(entry, left - 1)

    for root in roots:
        if root.is_dir():
            walk(root, depth)
    for path in extra:
        if path.is_dir():
            add(disc_game(path)) or add(hdd_game(path))
    if hdd is not None and hdd.is_dir():
        try:
            for folder in sorted(hdd.iterdir()):
                if folder.is_dir() and folder.name not in _SKIP_DIRS:
                    add(hdd_game(folder))
        except OSError:
            pass
    return sorted(found.values(), key=lambda g: g.title.lower())


def known_paths(exe: Path | None) -> list[Path]:
    """Lo que RPCS3 anota en config/games.yml («SERIE: ruta»): los juegos que ya abriste ahí."""
    if exe is None:
        return []
    paths: list[Path] = []
    try:
        for line in (exe.parent / "config" / "games.yml").read_text(encoding="utf-8").splitlines():
            if ":" not in line or line.lstrip().startswith("#"):
                continue
            value = line.split(":", 1)[1].strip().strip("'\"")
            if value:
                paths.append(Path(value))
    except (OSError, UnicodeDecodeError):
        return []
    return paths
