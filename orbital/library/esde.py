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

# Orden de preferencia: la portada encaja en las tarjetas verticales; el fondo grande
# (héroe) queda mejor con fanart o capturas horizontales.
COVER_KINDS = ("covers", "miximages", "screenshots")
HERO_KINDS = ("fanart", "screenshots", "titlescreens")
IMAGE_EXTS = (".png", ".jpg", ".jpeg", ".webp")


@dataclass
class GameMeta:
    name: str | None = None
    favorite: bool = False
    hidden: bool = False
    altemulator: str | None = None  # emulador elegido para este juego en ES-DE


@dataclass
class Gamelist:
    games: dict[str, GameMeta] = field(default_factory=dict)
    # Emulador alternativo elegido para todo el sistema (<alternativeEmulator><label>).
    system_emulator: str | None = None


@dataclass
class EsdeLibrary:
    home: Path  # carpeta de datos (settings/, gamelists/, downloaded_media/)
    rom_root: Path
    media_root: Path
    executable: Path | None = None
    _gamelists: dict[str, Gamelist] = field(default_factory=dict)

    def system_dir(self, system: str) -> Path:
        return self.rom_root / system

    def gamelist(self, system: str) -> Gamelist:
        if system not in self._gamelists:
            self._gamelists[system] = load_gamelist(self.home / "gamelists" / system / "gamelist.xml")
        return self._gamelists[system]

    def meta(self, system: str, rom: Path) -> GameMeta:
        key = _key(rom.relative_to(self.system_dir(system)))
        return self.gamelist(system).games.get(key, GameMeta())

    def chosen_emulator(self, system: str, rom: Path) -> str | None:
        """Etiqueta del emulador elegido en ES-DE: primero el del juego, luego el del sistema."""
        return self.meta(system, rom).altemulator or self.gamelist(system).system_emulator

    def cover(self, system: str, rom: Path) -> Path | None:
        return self.media(system, rom, COVER_KINDS)

    def hero(self, system: str, rom: Path) -> Path | None:
        return self.media(system, rom, HERO_KINDS)

    def media(self, system: str, rom: Path, kinds: tuple[str, ...]) -> Path | None:
        rel = rom.relative_to(self.system_dir(system)).with_suffix("")
        for kind in kinds:
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


def load_gamelist(path: Path) -> Gamelist:
    if not path.exists():
        return Gamelist()
    text = path.read_text(encoding="utf-8", errors="replace")
    # ES-DE escribe varios elementos raíz (<alternativeEmulator> + <gameList>); los envolvemos.
    text = re.sub(r"^\s*<\?xml[^>]*\?>", "", text)
    try:
        root = ET.fromstring(f"<root>{text}</root>")
    except ET.ParseError as exc:
        log.warning("gamelist inválido %s: %s", path, exc)
        return Gamelist()
    games = {}
    for node in root.iter("game"):
        rom_path = node.findtext("path")
        if rom_path:
            games[_key(rom_path)] = GameMeta(
                name=(node.findtext("name") or "").strip() or None,
                favorite=_bool(node.findtext("favorite")),
                hidden=_bool(node.findtext("hidden")),
                altemulator=(node.findtext("altemulator") or "").strip() or None,
            )
    label = (root.findtext("alternativeEmulator/label") or "").strip() or None
    return Gamelist(games=games, system_emulator=label)


def read_settings(home: Path) -> dict[str, str]:
    path = home / "settings" / "es_settings.xml"
    if not path.exists():
        return {}
    text = path.read_text(encoding="utf-8", errors="replace")
    return dict(re.findall(r'<string\s+name="([^"]+)"\s+value="([^"]*)"', text))


def _portable_homes(base: Path) -> list[Path]:
    """ES-DE portable descomprimido en `base` (p. ej. Descargas\\ES-DE\\ES-DE.exe + datos en ES-DE\\)."""
    try:
        dirs = [base, *(p for p in base.iterdir() if p.is_dir())]
    except OSError:
        return []
    return [d / "ES-DE" for d in dirs if (d / "ES-DE.exe").is_file()]


def candidate_homes() -> list[Path]:
    homes = [Path.home() / "ES-DE"]
    if sys.platform == "win32":
        # Versión portable típica: C:\ES-DE\ES-DE.exe con los datos en C:\ES-DE\ES-DE
        for drive in ("C:\\", "D:\\"):
            homes += [Path(drive) / "ES-DE" / "ES-DE", Path(drive) / "ES-DE"]
        for base in (Path.home() / "Downloads", Path.home() / "Desktop"):
            homes += _portable_homes(base)
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

    # Sin ROMDirectory, ES-DE usa ~/ROMs, salvo en modo portable (portable.txt): ahí es %ESPATH%\ROMs.
    portable = (Path(espath) / "portable.txt").is_file()
    rom_root = resolve(settings.get("ROMDirectory"), Path(espath) / "ROMs" if portable else Path.home() / "ROMs")
    media_root = resolve(settings.get("MediaDirectory"), home / "downloaded_media")
    log.info("ES-DE: datos=%s ROMs=%s", home, rom_root)
    return EsdeLibrary(home=home, rom_root=rom_root, media_root=media_root, executable=exe)
