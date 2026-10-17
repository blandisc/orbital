"""Juegos de PlayStation 4 (shadPS4).

Un juego de PS4 no es un archivo: es una carpeta (CUSA00001, o «Bloodborne.ps4» como la nombra ES-DE) con su
`eboot.bin` y, en `sce_sys/`, el nombre (param.sfo), el ícono (icon0.png) y un fondo (pic1.png). Se buscan en la
carpeta de ROMs (ROMs/ps4 de ES-DE) y en las carpetas de juegos que ya le diste a shadPS4.
"""

from __future__ import annotations

import logging
import os
import struct
import tomllib
from collections.abc import Iterable
from dataclasses import dataclass
from pathlib import Path

log = logging.getLogger(__name__)

# El nombre en el idioma de la consola: español de Latinoamérica, español, y si no, el de siempre.
_TITLE_KEYS = ("TITLE_20", "TITLE_03", "TITLE")
_MAX_SFO = 64 * 1024


@dataclass(frozen=True)
class Ps4Game:
    folder: Path
    eboot: Path
    title: str
    title_id: str | None
    icon: Path | None
    background: Path | None


def read_sfo(data: bytes) -> dict[str, str | int]:
    """Las entradas de un param.sfo (formato PSF: cabecera, índice, tabla de llaves y de datos)."""
    if len(data) < 20 or data[:4] != b"\0PSF":
        return {}
    key_start, data_start, count = struct.unpack_from("<III", data, 8)
    out: dict[str, str | int] = {}
    for i in range(min(count, 512)):
        at = 20 + i * 16
        if at + 16 > len(data):
            break
        key_off, fmt, length, _max, data_off = struct.unpack_from("<HHIII", data, at)
        k0 = key_start + key_off
        key = data[k0:data.find(b"\0", k0)].decode("ascii", "replace") if k0 < len(data) else ""
        raw = data[data_start + data_off:data_start + data_off + length]
        if not key:
            continue
        if fmt == 0x0404 and len(raw) >= 4:
            out[key] = struct.unpack("<I", raw[:4])[0]
        else:
            out[key] = raw.split(b"\0", 1)[0].decode("utf-8", "replace").strip()
    return out


def _title(sfo: dict, folder: Path) -> str:
    for key in _TITLE_KEYS:
        value = sfo.get(key)
        if isinstance(value, str) and value:
            return " ".join(value.split())
    name = folder.name.removesuffix(".ps4")
    return name


def game_at(folder: Path) -> Ps4Game | None:
    """El juego de esa carpeta (None si no trae eboot.bin)."""
    eboot = folder / "eboot.bin"
    if not eboot.is_file():
        return None
    sys_dir = folder / "sce_sys"
    sfo: dict = {}
    try:
        with open(sys_dir / "param.sfo", "rb") as f:
            sfo = read_sfo(f.read(_MAX_SFO))
    except OSError:
        pass
    icon, pic = sys_dir / "icon0.png", sys_dir / "pic1.png"
    title_id = sfo.get("TITLE_ID")
    return Ps4Game(folder, eboot, _title(sfo, folder), title_id if isinstance(title_id, str) and title_id else None,
                   icon if icon.is_file() else None, pic if pic.is_file() else None)


def find_games(roots: Iterable[Path], depth: int = 2) -> list[Ps4Game]:
    """Los juegos dentro de esas carpetas (la carpeta misma, o hasta `depth` niveles abajo). Las actualizaciones
    instaladas aparte (CUSA00001-UPDATE, -patch) no cuentan como otro juego."""
    found: dict[str, Ps4Game] = {}
    seen: set[str] = set()

    def walk(folder: Path, left: int) -> None:
        key = os.path.normcase(str(folder))
        if key in seen:
            return
        seen.add(key)
        game = game_at(folder)
        if game is not None:
            if not folder.name.upper().endswith(("-UPDATE", "-PATCH", "-DLC")):
                found.setdefault(os.path.normcase(str(game.eboot)), game)
            return
        if left <= 0:
            return
        try:
            children = sorted(p for p in folder.iterdir() if p.is_dir() and not p.name.startswith("."))
        except OSError:
            return
        for child in children:
            walk(child, left - 1)

    for root in roots:
        if root.is_dir():
            walk(root, depth)
    return sorted(found.values(), key=lambda g: g.title.lower())


def _config_files(exe: Path) -> list[Path]:
    appdata = Path(os.environ.get("APPDATA") or Path.home())
    return [exe.parent / "user" / "config.toml", appdata / "shadPS4" / "config.toml"]


def install_dirs(exe: Path | None) -> list[Path]:
    """Las carpetas de juegos que le diste a shadPS4 (su config.toml: «installDirs»)."""
    if exe is None:
        return []
    dirs: list[Path] = []

    def collect(node) -> None:
        if isinstance(node, dict):
            for key, value in node.items():
                if key.lower() in ("installdirs", "install_dirs") and isinstance(value, list):
                    dirs.extend(Path(v) for v in value if isinstance(v, str) and v)
                else:
                    collect(value)

    for path in _config_files(exe):
        try:
            collect(tomllib.loads(path.read_text(encoding="utf-8")))
        except (OSError, tomllib.TOMLDecodeError, UnicodeDecodeError) as exc:
            if not isinstance(exc, FileNotFoundError):
                log.debug("No pude leer %s: %s", path, exc)
    return dirs
