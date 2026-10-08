"""Escaneo de ROMs y construcción del comando de cada emulador."""

from __future__ import annotations

import hashlib
import logging
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


def build_argv(emu: EmulatorConfig, rom: Path) -> list[str]:
    exe = emu.executable
    if not Path(exe).exists():
        exe = shutil.which(exe) or exe
    values = {"rom": str(rom), "rom_dir": str(rom.parent), "rom_name": rom.stem}
    return [exe] + [arg.format_map(values) for arg in emu.args]


def _item_id(emu_id: str, rom: Path) -> str:
    digest = hashlib.sha1(str(rom).encode("utf-8")).hexdigest()[:12]
    return f"emu:{emu_id}:{digest}"


def executable_found(emu: EmulatorConfig) -> bool:
    return Path(emu.executable).exists() or shutil.which(emu.executable) is not None


def rom_dirs(emu: EmulatorConfig, esde: EsdeLibrary | None) -> list[Path]:
    """Las carpetas de config.yaml; si no hay y el emulador tiene `system`, la de ES-DE."""
    if emu.rom_dirs:
        return [Path(d) for d in emu.rom_dirs]
    if esde and emu.system:
        return [esde.system_dir(emu.system)]
    return []


def scan(emu: EmulatorConfig, esde: EsdeLibrary | None = None) -> list[LibraryItem]:
    if not executable_found(emu):
        log.warning("No encuentro el ejecutable de %s: %s", emu.name, emu.executable)
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
            art = esde.cover(system, rom) if system else None
            items.append(
                LibraryItem(
                    id=_item_id(emu.id, rom),
                    title=(meta.name if meta and meta.name else clean_title(rom.name)),
                    category="emulators",
                    source=emu.id,
                    subtitle=emu.name,
                    argv=build_argv(emu, rom),
                    cwd=str(Path(emu.executable).parent) if Path(emu.executable).exists() else None,
                    favorite=bool(meta and meta.favorite),
                    art_path=str(art) if art else None,
                )
            )
    return sorted(items, key=lambda i: i.title.lower())
