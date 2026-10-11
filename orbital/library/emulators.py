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
from .models import LibraryItem, Runner
from .shortcuts import read_lnk, xenia_games

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


def runner_name(emu: EmulatorConfig, exe: Path | None) -> str:
    """Nombre corto para la interfaz: "Ryujinx", "Eden", "Dolphin"..."""
    if emu.esde_label:
        return emu.esde_label
    stem = (exe or Path(emu.executable.replace("*", ""))).stem
    return stem if any(c.isupper() for c in stem) else stem.capitalize()


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
    seen: set[str] = set()  # un juego, una tarjeta (aunque haya .lnk y paquete instalado)
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
        for entry in files:
            if not entry.is_file():
                continue
            rom = entry
            if entry.suffix.lower() == ".lnk":
                # Acceso directo que abre este emulador con un juego ("Call of Duty.lnk" -> Xenia + paquete):
                # se usa el juego al que apunta; el nombre y la portada siguen siendo los del .lnk en ES-DE.
                rom = _shortcut_rom(entry, {exe.name.lower() for exe in exes.values() if exe})
                if rom is None:
                    continue
            elif exts and entry.suffix.lower() not in exts:
                continue
            if any(word in entry.name.lower() for word in excluded):
                continue
            if str(rom).lower() in seen:
                continue
            seen.add(str(rom).lower())
            meta = esde.meta(system, entry) if system else None
            if meta and meta.hidden:
                continue
            runners = [
                Runner(c.id, runner_name(c, exes[c.id]), build_argv(c, exes[c.id], rom), str(exes[c.id].parent) if exes[c.id] else None)
                for c in candidates
                if c is emu or exes[c.id] is not None  # alternativas solo si están instaladas
            ]
            default = emu
            chosen = esde.chosen_emulator(system, rom) if system else None
            if chosen:
                default = next((c for c in candidates if esde_key(c) in chosen.lower()), emu)
            art = esde.cover(system, entry) if system else None
            hero = esde.hero(system, entry) if system else None
            items.append(
                LibraryItem(
                    id=_item_id(emu.id, rom),
                    title=(meta.name if meta and meta.name else clean_title(entry.name)),
                    category="emulators",
                    source=emu.id,
                    subtitle=emu.name,
                    runners=runners,
                    default_runner=default.id,
                    favorite=bool(meta and meta.favorite),
                    art_path=str(art) if art else None,
                    hero_path=str(hero) if hero else None,
                )
            )
    # Xbox 360: los juegos instalados dentro de Xenia (Games on Demand / Arcade), aunque no haya nada
    # en la carpeta de ROMs. El nombre sale de la cabecera del paquete.
    exe = exes.get(emu.id)
    if emu.system == "xbox360" and exe is not None:
        for package, name in xenia_games(exe.parent / "content"):
            if str(package).lower() in seen:
                continue
            seen.add(str(package).lower())
            items.append(LibraryItem(
                id=_item_id(emu.id, package), title=name, category="emulators", source=emu.id, subtitle=emu.name,
                runners=[Runner(emu.id, runner_name(emu, exe), build_argv(emu, exe, package), str(exe.parent))],
                default_runner=emu.id))
    return sorted(items, key=lambda i: i.title.lower())


def _shortcut_rom(lnk: Path, emulator_exes: set[str]) -> Path | None:
    """El juego al que apunta un .lnk que abre uno de estos emuladores (su último argumento-ruta)."""
    shortcut = read_lnk(lnk)
    if shortcut is None or Path(shortcut.target).name.lower() not in emulator_exes:
        return None
    paths = [a for a in shortcut.argv() if ("\\" in a or "/" in a) and not a.startswith("-")]
    return Path(paths[-1]) if paths else None
