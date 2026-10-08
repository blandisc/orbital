"""Escaneo de ROMs y construcción del comando de cada emulador."""

from __future__ import annotations

import hashlib
import logging
import re
import shutil
from pathlib import Path

from ..config import EmulatorConfig
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


def scan(emu: EmulatorConfig) -> list[LibraryItem]:
    items: list[LibraryItem] = []
    exts = set(emu.extensions)
    for rom_dir in emu.rom_dirs:
        root = Path(rom_dir).expanduser()
        if not root.is_dir():
            log.warning("Carpeta de ROMs no encontrada para %s: %s", emu.name, root)
            continue
        files = root.rglob("*") if emu.recursive else root.iterdir()
        for rom in files:
            if not rom.is_file() or (exts and rom.suffix.lower() not in exts):
                continue
            items.append(
                LibraryItem(
                    id=_item_id(emu.id, rom),
                    title=clean_title(rom.name),
                    category="emulators",
                    source=emu.id,
                    subtitle=emu.name,
                    argv=build_argv(emu, rom),
                    cwd=str(Path(emu.executable).parent) if Path(emu.executable).exists() else None,
                )
            )
    return sorted(items, key=lambda i: i.title.lower())
