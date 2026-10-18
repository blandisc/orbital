"""Detección de la biblioteca local de Steam."""

from __future__ import annotations

import logging
import os
import re
import subprocess
import sys
import time
from pathlib import Path

from . import vdf
from .models import LibraryItem, added_at

log = logging.getLogger(__name__)

# Herramientas que Steam instala como "apps" pero no son juegos.
_NOT_GAMES = ("proton", "steam linux runtime", "steamworks common", "steamvr")
# Lo que la tienda llama «juego» pero no se juega: servidores, herramientas, pruebas, demos y reproductores (salían en la
# fila de Steam: «Left 4 Dead 2 Dedicated Server», «Halo MCC Mod Uploader», «Resident Evil 6 Benchmark Tool»…).
_NOT_GAME_WORDS = re.compile(r"\b(dedicated server|sdk|mod tools?|mod uploader|benchmark( tool)?|playtest|demo|"
                             r"stress test|performance test|video player|source filmmaker|soundtrack|ost|test server)\b", re.I)
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
    return appid not in _NOT_GAME_IDS and not any(word in lowered for word in _NOT_GAMES) and not _NOT_GAME_WORDS.search(name)


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
        last, minutes = str(info.get("lastplayed") or ""), str(info.get("playtime") or "")
        stats[appid] = {
            "last_played": int(last) if last.isdigit() else 0,
            "playtime": int(minutes) * 60 if minutes.isdigit() else 0,
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
                    "added": added_at(folder / "common" / state["installdir"]) if state.get("installdir") else None,
                },
            )
    return sorted(items.values(), key=lambda i: i.title.lower())


def owned_appids(steam_root: Path) -> set[str]:
    """Los juegos de tu cuenta, instalados o no. Sin cuenta ni clave: Steam guarda el arte de toda tu biblioteca en
    appcache/librarycache (un archivo o carpeta por juego, con su número) y lo que has abierto en localconfig.vdf.
    Puede traer algo que no es juego (una banda sonora, un DLC): la tienda dice qué es cada uno (steam_store)."""
    found: set[str] = set()
    cache = steam_root / "appcache" / "librarycache"
    try:
        found |= {m.group(0) for p in cache.iterdir() if (m := re.match(r"\d+", p.name))}
    except OSError:
        pass
    found |= {a for a in user_stats(steam_root) if a.isdigit()}
    return {a for a in found if a not in _NOT_GAME_IDS}


def uninstalled_item(appid: str, title: str, *, cloud: bool = False) -> LibraryItem:
    """Un juego de tu cuenta que no está instalado: «Instalar» abre la instalación de Steam. `cloud`: también se juega
    en GeForce NOW (ahí está, en su fila)."""
    return LibraryItem(
        id=f"steam:{appid}",
        title=title,
        category="steam",
        source="steam",
        subtitle="Steam · Sin instalar · En GeForce NOW" if cloud else "Steam · Sin instalar",
        image=CDN.format(appid=appid, name="library_600x900"),
        hero=CDN.format(appid=appid, name="library_hero"),
        steam_appid=int(appid),
        uri=f"steam://install/{appid}",
        extra={"logo": LOGO.format(appid=appid), "installed": False},
    )


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


# --- Steam en segundo plano -------------------------------------------------------------------
# Abrir un juego con steam://rungameid cuando Steam está cerrado muestra TODA la ventana de Steam
# (inicio, biblioteca…) antes del juego. Con Steam ya abierto en silencio (-silent: solo el ícono
# junto al reloj) el enlace va directo al juego y la pantalla de carga de Orbital lo cubre.
NO_WINDOW = getattr(subprocess, "CREATE_NO_WINDOW", 0)
DETACHED = getattr(subprocess, "DETACHED_PROCESS", 0) | getattr(subprocess, "CREATE_NEW_PROCESS_GROUP", 0)


def is_running() -> bool:
    """¿Está abierto el cliente de Steam? (steam.exe)."""
    if sys.platform != "win32":
        return False
    try:
        out = subprocess.run(["tasklist", "/FI", "IMAGENAME eq steam.exe", "/NH"], capture_output=True, text=True,
                             timeout=5, creationflags=NO_WINDOW).stdout
    except (OSError, subprocess.SubprocessError):
        return False
    return "steam.exe" in out.lower()


def start_silent(steam_root: Path | None) -> bool:
    """Abre Steam sin ventana (si no estaba abierto). True si ya estaba o se pudo abrir."""
    if is_running():
        return True
    exe = steam_root / "steam.exe" if steam_root else None
    if not exe or not exe.exists():
        return False
    try:
        subprocess.Popen([str(exe), "-silent"], cwd=str(steam_root), stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, creationflags=DETACHED)
    except OSError:
        log.warning("No pude abrir Steam en segundo plano", exc_info=True)
        return False
    log.info("Steam abierto en segundo plano (sin ventana)")
    return True


def ready_silent(steam_root: Path | None, timeout: float = 8.0) -> None:
    """Antes de abrir un juego: si Steam estaba cerrado, lo abre en silencio y espera a que esté."""
    if is_running() or not start_silent(steam_root):
        return
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline and not is_running():
        time.sleep(.25)
    time.sleep(1.5)  # recién abierto: que tome el enlace en vez de abrir su ventana
