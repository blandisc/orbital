"""Todos los sistemas y emuladores que conoce ES-DE, leídos de sus propias reglas.

ES-DE trae en `resources/systems/windows/` dos archivos: `es_systems.xml` (195 sistemas, cada uno con sus comandos:
«Mupen64Plus (Standalone)», «Snes9x» por RetroArch…) y `es_find_rules.xml` (dónde buscar cada emulador). Tus cambios van
en `ES-DE/custom_systems/` con los mismos nombres y mandan sobre los de fábrica.

Orbital los usa para reconocer cualquier sistema que tengas en la carpeta de ROMs aunque no esté en su lista propia
(library/detect.py, que sigue mandando porque sus argumentos están afinados para la TV: pantalla completa, sin menús).
Por cada sistema se toma el primer comando cuyo emulador está instalado (con RetroArch, solo si el núcleo existe);
los demás instalados quedan como alternativos, igual que en ES-DE.
"""

from __future__ import annotations

import glob
import logging
import os
import re
import shutil
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field
from pathlib import Path

from ..config import EmulatorConfig

log = logging.getLogger(__name__)

# Lo que Orbital no sabe armar todavía: inyectar archivos, ids de RPCS3 o un comando por la consola de Windows (eso lo
# usan los accesos directos .lnk, que Orbital ya abre por su cuenta).
_UNSUPPORTED = ("%INJECT%", "%RPCS3_GAMEID%", "%EMULATOR_OS-SHELL%")
_FLAGS = ("%HIDEWINDOW%", "%ESCAPESPECIALS%", "%RUNINBACKGROUND%")


@dataclass
class EsdeCommand:
    label: str
    text: str


@dataclass
class EsdeSystem:
    name: str
    fullname: str
    extensions: list[str]
    commands: list[EsdeCommand] = field(default_factory=list)


def _read(path: Path) -> ET.Element | None:
    try:
        return ET.parse(path).getroot()
    except (OSError, ET.ParseError) as exc:
        if not isinstance(exc, FileNotFoundError):
            log.info("No pude leer %s: %s", path, exc)
        return None


def load_systems(esde_dir: Path, custom_dir: Path | None) -> dict[str, EsdeSystem]:
    """Los sistemas de fábrica, con los de custom_systems encima (mismo nombre: manda el tuyo)."""
    systems: dict[str, EsdeSystem] = {}
    for path in (esde_dir / "resources" / "systems" / "windows" / "es_systems.xml",
                 *([custom_dir / "es_systems.xml"] if custom_dir else [])):
        root = _read(path)
        if root is None:
            continue
        for node in root.iter("system"):
            name = (node.findtext("name") or "").strip()
            if not name:
                continue
            extensions = sorted({e.lower() for e in (node.findtext("extension") or "").split() if e.startswith(".")})
            commands = [EsdeCommand((c.get("label") or "").strip(), (c.text or "").strip()) for c in node.findall("command")]
            systems[name] = EsdeSystem(name, (node.findtext("fullname") or name).strip(), extensions, commands)
    return systems


def load_find_rules(esde_dir: Path, custom_dir: Path | None) -> tuple[dict[str, list[tuple[str, str]]], dict[str, list[str]]]:
    """({EMULADOR: [(tipo, ruta)]}, {NÚCLEO: [carpetas]}); las reglas tuyas van primero."""
    emulators: dict[str, list[tuple[str, str]]] = {}
    cores: dict[str, list[str]] = {}
    for path in (*([custom_dir / "es_find_rules.xml"] if custom_dir else []),
                 esde_dir / "resources" / "systems" / "windows" / "es_find_rules.xml"):
        root = _read(path)
        if root is None:
            continue
        for node in root.iter("emulator"):
            entries = [(rule.get("type") or "", (e.text or "").strip()) for rule in node.iter("rule") for e in rule.iter("entry")]
            emulators.setdefault(node.get("name") or "", []).extend(entries)
        for node in root.iter("core"):
            cores.setdefault(node.get("name") or "", []).extend((e.text or "").strip() for e in node.iter("entry"))
    return emulators, cores


def _expand(entry: str, esde_dir: Path) -> str:
    return os.path.expandvars(entry.replace("%ESPATH%", str(esde_dir)))


def find_emulator(name: str, rules: dict[str, list[tuple[str, str]]], esde_dir: Path) -> Path | None:
    for kind, entry in rules.get(name, []):
        if not entry:
            continue
        if kind == "staticpath":
            path = _expand(entry, esde_dir)
            hits = glob.glob(path) if any(c in path for c in "*?") else ([path] if os.path.isfile(path) else [])
            hits = [h for h in hits if os.path.isfile(h)]
            if hits:
                return Path(max(hits, key=os.path.getmtime)).resolve()
        elif kind == "systempath":
            found = shutil.which(entry)
            if found:
                return Path(found)
    return None


def split_command(text: str) -> list[str]:
    """Como lo parte ES-DE: por espacios, respetando lo que va entre comillas («--system "Nintendo 64"»)."""
    return [a.strip('"') for a in re.findall(r'"[^"]*"|[^\s"]+(?:"[^"]*")?[^\s"]*', text)]


def to_config(system: EsdeSystem, command: EsdeCommand, index: int, rules, cores, esde_dir: Path) -> EmulatorConfig | None:
    """Un comando de ES-DE como emulador de Orbital (None si su emulador no está o Orbital no lo sabe armar)."""
    text = command.text
    if any(token in text for token in _UNSUPPORTED):
        return None
    found = re.findall(r"%EMULATOR_([A-Z0-9-]+)%", text)
    if len(found) != 1:
        return None
    exe = find_emulator(found[0], rules, esde_dir)
    if exe is None:
        return None
    for flag in _FLAGS:
        text = text.replace(flag, "")
    text = re.sub(r"%STARTDIR%=\S+", "", text)  # Orbital abre los emuladores desde su carpeta
    if "%CORE_RETROARCH%" in text:
        core_dirs = [_expand(c.replace("%EMUPATH%", str(exe.parent)), esde_dir) for c in cores.get("RETROARCH", [])]
        core_dir = next((d for d in core_dirs if os.path.isdir(d)), None)
        core = re.search(r"%CORE_RETROARCH%[\\/](\S+?\.dll)", text)
        if core_dir is None or core is None or not os.path.isfile(os.path.join(core_dir, core.group(1))):
            return None
        text = text.replace("%CORE_RETROARCH%", core_dir)
    args = split_command(text)
    if not args or args[0] != f"%EMULATOR_{found[0]}%":
        return None
    replace = {"%ROM%": "{rom}", "%ROMRAW%": "{rom}", "%BASENAME%": "{rom_name}", "%FILENAME%": "{rom_file}",
               "%GAMEDIR%": "{rom_dir}", "%GAMEDIRRAW%": "{rom_dir}", "%EMUDIR%": str(exe.parent)}
    out: list[str] = []
    for arg in args[1:]:
        for key, value in replace.items():
            arg = arg.replace(key, value)
        if "%" in re.sub(r"%%", "", arg) and re.search(r"%[A-Z_]+%", arg):
            return None  # una variable que no conocemos: mejor no lanzarlo mal
        out.append(arg)
    label = command.label or found[0].title()
    return EmulatorConfig(
        id=f"esde-{system.name}" + (f"-{index}" if index else ""), name=system.fullname, executable=str(exe),
        system=system.name, args=out, extensions=[e for e in system.extensions if e != ".lnk"],
        esde_label=re.sub(r"\s*\(Standalone\)$", "", label))


def configs(esde_dir: Path, custom_dir: Path | None, rom_root: Path, covered: set[str],
            preferred: dict[str, str] | None = None) -> list[EmulatorConfig]:
    """Un emulador (y sus alternativos) por cada sistema con juegos en `rom_root` que Orbital no cubre ya (`covered`).
    `preferred`: el emulador elegido para el sistema en ES-DE (va primero si está instalado)."""
    systems = load_systems(esde_dir, custom_dir)
    if not systems:
        return []
    rules, cores = load_find_rules(esde_dir, custom_dir)
    out: list[EmulatorConfig] = []
    for name, system in systems.items():
        if name in covered or not _has_games(rom_root / name, system.extensions):
            continue
        commands = list(system.commands)
        chosen = (preferred or {}).get(name)
        if chosen:
            commands.sort(key=lambda c: c.label.lower() != chosen.lower())
        found = [c for c in (to_config(system, cmd, i, rules, cores, esde_dir) for i, cmd in enumerate(commands)) if c]
        if found:
            out += found
            log.info("ES-DE: %s con %s", system.fullname, ", ".join(c.esde_label or c.id for c in found))
        else:
            log.info("ES-DE: tienes juegos de %s pero ninguno de sus emuladores está instalado", system.fullname)
    return out


def _has_games(folder: Path, extensions: list[str], limit: int = 2000) -> bool:
    if not folder.is_dir():
        return False
    seen = 0
    for _root, _dirs, files in os.walk(folder):
        for name in files:
            if os.path.splitext(name)[1].lower() in extensions:
                return True
            seen += 1
            if seen > limit:
                return False
    return False
