"""Detección automática de emuladores: busca ejecutables conocidos en las carpetas típicas.

Así no hace falta escribir rutas en config.yaml. Lo que se configure a mano tiene prioridad
(mismo `id`), y lo detectado solo rellena lo que falta.
"""

from __future__ import annotations

import logging
import os
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

from ..config import EmulatorConfig, expand

log = logging.getLogger(__name__)


@dataclass(frozen=True)
class KnownEmulator:
    id: str
    name: str  # nombre del sistema (fila en la interfaz)
    system: str  # carpeta de ES-DE
    exe_names: tuple[str, ...]
    args: tuple[str, ...]
    extensions: tuple[str, ...]
    exclude: tuple[str, ...] = ()
    label: str | None = None  # nombre corto del emulador si el .exe no lo deja claro


_SWITCH_EXT = (".nsp", ".xci", ".nca", ".nro")
_SWITCH_EXCLUDE = ("[UPD]", "[DLC]", "(Update)", "(DLC)")

# El orden importa: si hay dos para el mismo sistema, el primero es el principal
# (Ryujinx antes que Eden) y el resto quedan como alternativos.
KNOWN: tuple[KnownEmulator, ...] = (
    KnownEmulator("switch", "Nintendo Switch", "switch", ("ryujinx.exe", "ryujinx"),
                  ("--fullscreen", "{rom}"), _SWITCH_EXT, _SWITCH_EXCLUDE, "Ryujinx"),
    KnownEmulator("switch-eden", "Nintendo Switch", "switch", ("eden.exe", "eden"),
                  ("-f", "-g", "{rom}"), _SWITCH_EXT, _SWITCH_EXCLUDE, "Eden"),
    KnownEmulator("switch-citron", "Nintendo Switch", "switch", ("citron.exe", "citron"),
                  ("-f", "-g", "{rom}"), _SWITCH_EXT, _SWITCH_EXCLUDE, "Citron"),
    KnownEmulator("switch-sudachi", "Nintendo Switch", "switch", ("sudachi.exe", "sudachi"),
                  ("-f", "-g", "{rom}"), _SWITCH_EXT, _SWITCH_EXCLUDE, "Sudachi"),
    KnownEmulator("gamecube", "GameCube", "gc", ("dolphin.exe", "dolphin-emu"),
                  ("-b", "-e", "{rom}"), (".iso", ".rvz", ".gcz", ".ciso", ".gcm"), label="Dolphin"),
    KnownEmulator("wii", "Wii", "wii", ("dolphin.exe", "dolphin-emu"),
                  ("-b", "-e", "{rom}"), (".iso", ".rvz", ".wbfs", ".wia", ".wad"), label="Dolphin"),
    KnownEmulator("gba", "Game Boy Advance", "gba", ("mgba.exe", "mgba-qt"),
                  ("-f", "{rom}"), (".gba", ".zip", ".7z"), label="mGBA"),
    KnownEmulator("xbox", "Xbox", "xbox", ("xemu.exe", "xemu"),
                  ("-full-screen", "-dvd_path", "{rom}"), (".iso",), label="xemu"),
    KnownEmulator("xbox360", "Xbox 360", "xbox360", ("xenia_canary.exe", "xenia.exe"),
                  ("--fullscreen", "{rom}"), (".iso", ".xex", ".zar"), label="Xenia"),
    KnownEmulator("psx", "PlayStation", "psx", ("duckstation-qt-x64-releaseltcg.exe", "duckstation-qt"),
                  ("-batch", "-fullscreen", "{rom}"), (".cue", ".chd", ".m3u", ".pbp"), label="DuckStation"),
    KnownEmulator("ps2", "PlayStation 2", "ps2", ("pcsx2-qt.exe", "pcsx2-qt"),
                  ("-batch", "-fullscreen", "{rom}"), (".iso", ".chd", ".cso"), label="PCSX2"),
    KnownEmulator("psp", "PSP", "psp", ("ppssppwindows64.exe", "ppssppsdl"),
                  ("--fullscreen", "{rom}"), (".iso", ".cso", ".chd", ".pbp"), label="PPSSPP"),
    KnownEmulator("nds", "Nintendo DS", "nds", ("melonds.exe", "melonds"),
                  ("-f", "{rom}"), (".nds", ".zip"), label="melonDS"),
    KnownEmulator("wiiu", "Wii U", "wiiu", ("cemu.exe",),
                  ("-f", "-g", "{rom}"), (".wua", ".wux", ".rpx"), label="Cemu"),
)


@dataclass
class SearchDir:
    path: Path
    depth: int = 4  # cuántas subcarpetas bajar (Descargas suele tener "Ryujinx-1.2/publish/")


@dataclass
class Detection:
    emulators: list[EmulatorConfig] = field(default_factory=list)
    found: dict[str, Path] = field(default_factory=dict)  # id -> ejecutable


def default_search_dirs(extra: list[str] | None = None, esde_exe: Path | None = None) -> list[SearchDir]:
    home = Path.home()
    dirs = [SearchDir(Path(expand(d))) for d in extra or []]
    if esde_exe:
        dirs.append(SearchDir(esde_exe.parent / "Emulators"))  # convención de ES-DE portable
    dirs += [
        SearchDir(home / "Downloads"),
        SearchDir(home / "Desktop", 3),
        SearchDir(home / "Emulators"),
        SearchDir(home / "Emuladores"),
        SearchDir(home / "ES-DE" / "Emulators"),
    ]
    if sys.platform == "win32":
        local = Path(os.environ.get("LOCALAPPDATA", home / "AppData" / "Local"))
        for drive in ("C:\\", "D:\\", "E:\\"):
            dirs += [SearchDir(Path(drive) / "Emuladores"), SearchDir(Path(drive) / "Emulators"),
                     SearchDir(Path(drive) / "ES-DE" / "Emulators")]
        dirs += [
            SearchDir(local / "Programs", 2),
            SearchDir(Path(os.environ.get("ProgramFiles", r"C:\Program Files")), 2),
        ]
    else:
        dirs += [SearchDir(Path("/usr/bin"), 0), SearchDir(home / "Applications", 2)]
    return dirs


def _walk(root: Path, depth: int):
    """Recorre carpetas sin seguir enlaces y sin bajar más de `depth` niveles."""
    try:
        entries = list(os.scandir(root))
    except OSError:
        return
    for entry in entries:
        try:
            if entry.is_file(follow_symlinks=False):
                yield Path(entry.path)
            elif depth > 0 and entry.is_dir(follow_symlinks=False) and not entry.name.startswith("."):
                yield from _walk(Path(entry.path), depth - 1)
        except OSError:
            continue


_BACKUP_DIR = re.compile(r"\.bak|[-_. ](bak|backup|old|respaldo)\b|^(bak|backup|old|respaldo)\b", re.IGNORECASE)


def _is_backup(path: Path, root: Path) -> bool:
    """¿Está dentro de una carpeta de respaldo (eden.bak-2026…, ryujinx-old)?"""
    try:
        parts = path.parent.relative_to(root).parts
    except ValueError:
        parts = path.parent.parts
    return any(_BACKUP_DIR.search(part) for part in parts)


def find_executables(dirs: list[SearchDir]) -> dict[str, Path]:
    """Nombre de ejecutable en minúsculas -> la copia más reciente encontrada.

    Las copias en carpetas de respaldo solo se usan si no hay otra: la fecha del .exe viene del
    zip original, así que un respaldo puede parecer "más nuevo" que la versión en uso.
    """
    wanted = {name for known in KNOWN for name in known.exe_names}
    found: dict[str, tuple[tuple[bool, float], Path]] = {}
    seen: set[Path] = set()
    for search in dirs:
        root = search.path
        if not root.is_dir() or root in seen:
            continue
        seen.add(root)
        for path in _walk(root, search.depth):
            name = path.name.lower()
            if name not in wanted:
                continue
            try:
                rank = (not _is_backup(path, root), path.stat().st_mtime)
            except OSError:
                continue
            if name not in found or rank > found[name][0]:
                found[name] = (rank, path)
    return {name: path for name, (_, path) in found.items()}


def detect(dirs: list[SearchDir], skip_ids: set[str] = frozenset()) -> Detection:
    executables = find_executables(dirs)
    result = Detection()
    for known in KNOWN:
        if known.id in skip_ids:
            continue
        exe = next((executables[n] for n in known.exe_names if n in executables), None)
        if exe is None:
            continue
        result.found[known.id] = exe
        result.emulators.append(EmulatorConfig(
            id=known.id,
            name=known.name,
            executable=str(exe),
            system=known.system,
            args=list(known.args),
            extensions=list(known.extensions),
            exclude=list(known.exclude),
            esde_label=known.label,
        ))
    if result.found:
        log.info("Emuladores detectados: %s", ", ".join(f"{k}={v}" for k, v in result.found.items()))
    return result


def merge(configured: list[EmulatorConfig], detected: list[EmulatorConfig]) -> list[EmulatorConfig]:
    """Lo configurado manda; lo detectado se añade después, respetando el orden de KNOWN.

    Si configuraste un emulador para un sistema (p. ej. tu propio Switch), los detectados de ese
    mismo sistema quedan como alternativos, nunca como principal.
    """
    ids = {e.id for e in configured}
    return [*configured, *(e for e in detected if e.id not in ids)]
