"""Escaneo de ROMs y construcción del comando de cada emulador."""

from __future__ import annotations

import glob
import hashlib
import logging
import os
import re
import shutil
from pathlib import Path

from ..config import EmulatorConfig
from .esde import EsdeLibrary
from .models import LibraryItem

log = logging.getLogger(__name__)

# "Super Mario World (USA) [!]" -> "Super Mario World"
_TAGS = re.compile(r"\s*[\(\[][^\)\]]*[\)\]]")


def clean_title(filename: str) -> str:
    stem = Path(filename).stem.replace("_", " ")
    title = _TAGS.sub("", stem).strip()
    return re.sub(r"\s{2,}", " ", title) or stem


def resolve_executable(emu: EmulatorConfig) -> Path | None:
    """Admite comodines: 'Downloads\\xemu-*\\xemu.exe' o 'Downloads\\**\\Ryujinx.exe'.

    Si hay varias coincidencias (p. ej. dos versiones descargadas) usa la más reciente.
    """
    pattern = emu.executable
    if any(c in pattern for c in "*?["):
        matches = [Path(p) for p in glob.glob(pattern, recursive=True) if os.path.isfile(p)]
        return max(matches, key=lambda p: p.stat().st_mtime) if matches else None
    if Path(pattern).is_file():
        return Path(pattern)
    found = shutil.which(pattern)
    return Path(found) if found else None


def executable_found(emu: EmulatorConfig) -> bool:
    return resolve_executable(emu) is not None


def build_argv(emu: EmulatorConfig, exe: Path | None, rom: Path) -> list[str]:
    values = {"rom": str(rom), "rom_dir": str(rom.parent), "rom_name": rom.stem}
    return [str(exe or emu.executable)] + [arg.format_map(values) for arg in emu.args]


def _item_id(emu_id: str, rom: Path) -> str:
    digest = hashlib.sha1(str(rom).encode("utf-8")).hexdigest()[:12]
    return f"emu:{emu_id}:{digest}"


def rom_dirs(emu: EmulatorConfig, esde: EsdeLibrary | None) -> list[Path]:
    """Las carpetas de config.yaml; si no hay y el emulador tiene `system`, la de ES-DE."""
    if emu.rom_dirs:
        return [Path(d) for d in emu.rom_dirs]
    if esde and emu.system:
        return [esde.system_dir(emu.system)]
    return []


def esde_key(emu: EmulatorConfig) -> str:
    return (emu.esde_label or Path(emu.executable.replace("*", "")).stem).lower()


def split_alternatives(emus: list[EmulatorConfig]) -> list[tuple[EmulatorConfig, list[EmulatorConfig]]]:
    """Varios emuladores para el mismo sistema (Ryujinx + Eden) comparten una sola lista de juegos.

    El primero de config.yaml es el principal; los demás solo se usan si ES-DE los eligió.
    """
    groups: list[tuple[EmulatorConfig, list[EmulatorConfig]]] = []
    primary_by_system: dict[str, tuple[EmulatorConfig, list[EmulatorConfig]]] = {}
    for emu in emus:
        shared = emu.system and not emu.rom_dirs
        if shared and emu.system in primary_by_system:
            primary_by_system[emu.system][1].append(emu)
            continue
        group = (emu, [])
        groups.append(group)
        if shared:
            primary_by_system[emu.system] = group
    return groups


def scan(
    emu: EmulatorConfig,
    esde: EsdeLibrary | None = None,
    alternatives: list[EmulatorConfig] | None = None,
) -> list[LibraryItem]:
    candidates = [emu, *(alternatives or [])]
    exes = {c.id: resolve_executable(c) for c in candidates}
    for c in candidates:
        if exes[c.id] is None:
            log.warning("No encuentro el ejecutable de %s: %s", c.name, c.executable)
    items: list[LibraryItem] = []
    exts = set(emu.extensions)
    excluded = [e.lower() for e in emu.exclude]
    dirs = rom_dirs(emu, esde)
    if not dirs:
        log.warning("%s no tiene rom_dirs ni system de ES-DE", emu.name)
    for root in dirs:
        if not root.is_dir():
            log.warning("Carpeta de ROMs no encontrada para %s: %s", emu.name, root)
            continue
        # Solo enriquecemos con ES-DE si la carpeta es la del sistema en ES-DE.
        system = emu.system if esde and emu.system and root == esde.system_dir(emu.system) else None
        files = root.rglob("*") if emu.recursive else root.iterdir()
        for rom in files:
            if not rom.is_file() or (exts and rom.suffix.lower() not in exts):
                continue
            if any(word in rom.name.lower() for word in excluded):
                continue
            meta = esde.meta(system, rom) if system else None
            if meta and meta.hidden:
                continue
            runner = emu
            chosen = esde.chosen_emulator(system, rom) if system else None
            if chosen:
                runner = next((c for c in candidates if esde_key(c) in chosen.lower()), emu)
            exe = exes[runner.id]
            art = esde.cover(system, rom) if system else None
            items.append(
                LibraryItem(
                    id=_item_id(emu.id, rom),
                    title=(meta.name if meta and meta.name else clean_title(rom.name)),
                    category="emulators",
                    source=emu.id,
                    subtitle=emu.name if runner is emu else f"{emu.name} · {runner.name}",
                    argv=build_argv(runner, exe, rom),
                    cwd=str(exe.parent) if exe else None,
                    favorite=bool(meta and meta.favorite),
                    art_path=str(art) if art else None,
                )
            )
    return sorted(items, key=lambda i: i.title.lower())
