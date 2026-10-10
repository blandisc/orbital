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

CDN = "https://cdn.cloudflare.steamstatic.com/steam/apps/{appid}/{name}.jpg"
LOGO = "https://cdn.cloudflare.steamstatic.com/steam/apps/{appid}/logo.png"
INSTALLED = "4"  # StateFlags: 4 = instalado y al día; otro valor = falta actualizar o se está instalando


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


def user_stats(steam_root: Path) -> dict[str, dict]:
    """Horas jugadas y última vez de cada juego, como las lleva Steam (también lo que jugaste
    fuera de Orbital). userdata/<cuenta>/config/localconfig.vdf: se usa la cuenta más reciente."""
    configs = sorted(steam_root.glob("userdata/*/config/localconfig.vdf"), key=lambda p: p.stat().st_mtime, reverse=True)
    if not configs:
        return {}
    try:
        data = vdf.loads(configs[0].read_text(encoding="utf-8", errors="replace"))
        apps = data["userlocalconfigstore"]["software"]["valve"]["steam"]["apps"]
    except (KeyError, ValueError, OSError, TypeError) as exc:
        log.warning("No pude leer las horas de Steam: %s", exc)
        return {}
    stats = {}
    for appid, info in apps.items():
        if not isinstance(info, dict):
            continue
        last, minutes = info.get("lastplayed"), info.get("playtime")
        stats[appid] = {
            "last_played": int(last) if str(last or "").isdigit() else 0,
            "playtime": int(minutes) * 60 if str(minutes or "").isdigit() else 0,
        }
    return stats


def scan(steam_root: Path) -> list[LibraryItem]:
    items: dict[str, LibraryItem] = {}
    stats = user_stats(steam_root)
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
            hero = local_art_path(steam_root, appid, "library_hero")
            items[appid] = LibraryItem(
                id=f"steam:{appid}",
                title=name,
                category="steam",
                source="steam",
                subtitle="Steam",
                image=None if art else CDN.format(appid=appid, name="library_600x900"),
                hero=None if hero else CDN.format(appid=appid, name="library_hero"),
                art_path=str(art) if art else None,
                hero_path=str(hero) if hero else None,
                steam_appid=int(appid) if appid.isdigit() else None,
                uri=f"steam://rungameid/{appid}",
                extra={
                    "logo": LOGO.format(appid=appid),
                    "size": int(state["sizeondisk"]) if str(state.get("sizeondisk", "")).isdigit() else 0,
                    "update": str(state.get("stateflags", INSTALLED)) != INSTALLED,
                    "steam_last_played": stats.get(appid, {}).get("last_played", 0),
                    "steam_playtime": stats.get(appid, {}).get("playtime", 0),
                },
            )
    return sorted(items.values(), key=lambda i: i.title.lower())


def local_art_path(steam_root: Path, appid: str, name: str = "library_600x900") -> Path | None:
    if not appid.isdigit():
        return None
    cache = steam_root / "appcache" / "librarycache"
    # Steam antiguo: <appid>_library_600x900.jpg; Steam reciente: <appid>/library_600x900.jpg
    for candidate in (cache / f"{appid}_{name}.jpg", cache / appid / f"{name}.jpg"):
        if candidate.exists():
            return candidate
    return None


def big_picture_uri() -> str:
    return "steam://open/bigpicture"
