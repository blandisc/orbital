"""Lectura de los datos de ES-DE: carpeta de ROMs, gamelists (nombres/favoritos) y portadas."""

from __future__ import annotations

import logging
import os
import re
import shutil
import sys
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field
from pathlib import Path

from ..config import EsdeConfig, expand

log = logging.getLogger(__name__)

# Orden de preferencia de la imagen: la portada encaja mejor en las tarjetas verticales.
MEDIA_KINDS = ("covers", "miximages", "screenshots")
IMAGE_EXTS = (".png", ".jpg", ".jpeg", ".webp")


@dataclass
class GameMeta:
    name: str | None = None
    favorite: bool = False
    hidden: bool = False


@dataclass
class EsdeLibrary:
    home: Path  # carpeta de datos (settings/, gamelists/, downloaded_media/)
    rom_root: Path
    media_root: Path
    executable: Path | None = None
    _gamelists: dict[str, dict[str, GameMeta]] = field(default_factory=dict)

    def system_dir(self, system: str) -> Path:
        return self.rom_root / system

    def meta(self, system: str, rom: Path) -> GameMeta:
        if system not in self._gamelists:
            self._gamelists[system] = load_gamelist(self.home / "gamelists" / system / "gamelist.xml")
        return self._gamelists[system].get(_key(rom.relative_to(self.system_dir(system))), GameMeta())

    def cover(self, system: str, rom: Path) -> Path | None:
        rel = rom.relative_to(self.system_dir(system)).with_suffix("")
        for kind in MEDIA_KINDS:
            base = self.media_root / system / kind / rel
            for ext in IMAGE_EXTS:
                candidate = base.with_name(base.name + ext)
                if candidate.exists():
                    return candidate
        return None


def _key(rel: Path | str) -> str:
    return str(rel).replace("\\", "/").removeprefix("./").lower()


def _bool(text: str | None) -> bool:
    return (text or "").strip().lower() == "true"


def load_gamelist(path: Path) -> dict[str, GameMeta]:
    if not path.exists():
        return {}
    text = path.read_text(encoding="utf-8", errors="replace")
    # ES-DE escribe varios elementos raíz (<alternativeEmulator> + <gameList>); los envolvemos.
    text = re.sub(r"^\s*<\?xml[^>]*\?>", "", text)
    try:
        root = ET.fromstring(f"<root>{text}</root>")
    except ET.ParseError as exc:
        log.warning("gamelist inválido %s: %s", path, exc)
        return {}
    games = {}
    for node in root.iter("game"):
        rom_path = node.findtext("path")
        if rom_path:
            games[_key(rom_path)] = GameMeta(
                name=(node.findtext("name") or "").strip() or None,
                favorite=_bool(node.findtext("favorite")),
                hidden=_bool(node.findtext("hidden")),
            )
    return games


def read_settings(home: Path) -> dict[str, str]:
    path = home / "settings" / "es_settings.xml"
    if not path.exists():
        return {}
    text = path.read_text(encoding="utf-8", errors="replace")
    return dict(re.findall(r'<string\s+name="([^"]+)"\s+value="([^"]*)"', text))


def candidate_homes() -> list[Path]:
    homes = [Path.home() / "ES-DE"]
    if sys.platform == "win32":
        # Versión portable típica: C:\ES-DE\ES-DE.exe con los datos en C:\ES-DE\ES-DE
        for drive in ("C:\\", "D:\\"):
            homes += [Path(drive) / "ES-DE" / "ES-DE", Path(drive) / "ES-DE"]
    return homes


def _executable(cfg: EsdeConfig, home: Path) -> Path | None:
    if cfg.executable:
        return Path(expand(cfg.executable))
    local = Path(os.environ.get("LOCALAPPDATA", Path.home() / "AppData" / "Local"))
    candidates = [
        home.parent / "ES-DE.exe",  # portable (datos en ES-DE\\ES-DE)
        home / "ES-DE.exe",
        local / "Programs" / "ES-DE" / "ES-DE.exe",  # instalador
        Path(r"C:\Program Files\ES-DE\ES-DE.exe"),
    ]
    for candidate in candidates:
        if candidate.exists():
            return candidate
    found = shutil.which("es-de") or shutil.which("ES-DE")
    return Path(found) if found else None


def find(cfg: EsdeConfig) -> EsdeLibrary | None:
    if not cfg.enabled:
        return None
    homes = [Path(expand(cfg.path))] if cfg.path else candidate_homes()
    home = next((h for h in homes if (h / "settings").is_dir() or (h / "gamelists").is_dir()), None)
    if home is None:
        log.info("ES-DE no encontrado")
        return None
    settings = read_settings(home)
    exe = _executable(cfg, home)
    # %ESPATH% = carpeta donde está ES-DE.exe (se usa en instalaciones portables).
    espath = str(exe.parent if exe else home.parent)

    def resolve(value: str | None, default: Path) -> Path:
        if not value:
            return default
        return Path(expand(value.replace("%ESPATH%", espath)))

    rom_root = resolve(settings.get("ROMDirectory"), Path.home() / "ROMs")
    media_root = resolve(settings.get("MediaDirectory"), home / "downloaded_media")
    log.info("ES-DE: datos=%s ROMs=%s", home, rom_root)
    return EsdeLibrary(home=home, rom_root=rom_root, media_root=media_root, executable=exe)
