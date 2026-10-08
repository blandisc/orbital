"""Detección de la biblioteca local de Steam."""

from __future__ import annotations

import logging
import os
import sys
from pathlib import Path

from . import vdf
from .models import LibraryItem

log = logging.getLogger(__name__)

# Herramientas que Steam instala como "apps" pero no son juegos.
_NOT_GAMES = ("proton", "steam linux runtime", "steamworks common", "steamvr")
_NOT_GAME_IDS = {"228980", "1070560", "1391110", "1628350"}

CDN = "https://cdn.cloudflare.steamstatic.com/steam/apps/{appid}/library_600x900.jpg"


def _windows_registry_path() -> Path | None:
    try:
        import winreg  # type: ignore[import-not-found]

        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, r"Software\Valve\Steam") as key:
            value, _ = winreg.QueryValueEx(key, "SteamPath")
            return Path(value)
    except OSError:
        return None


def candidate_paths() -> list[Path]:
    if sys.platform == "win32":
        paths = [p for p in [_windows_registry_path()] if p]
        pf86 = os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)")
        paths.append(Path(pf86) / "Steam")
        return paths
    home = Path.home()
    return [
        home / ".steam" / "steam",
        home / ".local" / "share" / "Steam",
        home / ".var" / "app" / "com.valvesoftware.Steam" / ".local" / "share" / "Steam",
        home / "Library" / "Application Support" / "Steam",
    ]


def find_steam(configured: str | None = None) -> Path | None:
    paths = [Path(configured)] if configured else candidate_paths()
    for p in paths:
        if (p / "steamapps").is_dir():
            return p
    return None


def library_folders(steam_root: Path) -> list[Path]:
    folders = [steam_root / "steamapps"]
    lf = steam_root / "steamapps" / "libraryfolders.vdf"
    if lf.exists():
        data = vdf.loads(lf.read_text(encoding="utf-8", errors="replace"))
        for entry in data.get("libraryfolders", {}).values():
            path = entry.get("path") if isinstance(entry, dict) else entry
            if path:
                folder = Path(path) / "steamapps"
                if folder not in folders:
                    folders.append(folder)
    return [f for f in folders if f.is_dir()]


def _is_game(appid: str, name: str) -> bool:
    lowered = name.lower()
    return appid not in _NOT_GAME_IDS and not any(word in lowered for word in _NOT_GAMES)


def scan(steam_root: Path) -> list[LibraryItem]:
    items: dict[str, LibraryItem] = {}
    for folder in library_folders(steam_root):
        for manifest in folder.glob("appmanifest_*.acf"):
            try:
                state = vdf.loads(manifest.read_text(encoding="utf-8", errors="replace"))["appstate"]
            except (KeyError, ValueError, OSError) as exc:
                log.warning("No se pudo leer %s: %s", manifest, exc)
                continue
            appid, name = state.get("appid"), state.get("name")
            if not appid or not name or not _is_game(appid, name) or appid in items:
                continue
            art = local_art_path(steam_root, appid)
            items[appid] = LibraryItem(
                id=f"steam:{appid}",
                title=name,
                category="steam",
                source="steam",
                subtitle="Steam",
                image=None if art else CDN.format(appid=appid),
                art_path=str(art) if art else None,
                uri=f"steam://rungameid/{appid}",
            )
    return sorted(items.values(), key=lambda i: i.title.lower())


def local_art_path(steam_root: Path, appid: str) -> Path | None:
    if not appid.isdigit():
        return None
    cache = steam_root / "appcache" / "librarycache"
    # Steam antiguo: <appid>_library_600x900.jpg; Steam reciente: <appid>/library_600x900.jpg
    for candidate in (cache / f"{appid}_library_600x900.jpg", cache / appid / "library_600x900.jpg"):
        if candidate.exists():
            return candidate
    return None


def big_picture_uri() -> str:
    return "steam://open/bigpicture"
