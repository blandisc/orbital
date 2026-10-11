"""GeForce NOW: la app y tus juegos en la nube.

NVIDIA no publica una API de biblioteca (y no usamos tu sesión). Orbital junta dos cosas locales:

  * Tu "Mi biblioteca": la app de GFN guarda en su caché (Service Worker de su Chromium) la última
    respuesta del panel Library, con cada juego, su variante (tienda), si se puede jugar y sus
    imágenes. Solo se lee ese archivo, ya en tu disco; se actualiza cada vez que abres la app.
  * Accesos directos de juegos (en el juego: ⋯ -> Crear acceso directo), que lanzan
    GeForceNOWStreamer.exe --url-route="#?cmsId=<id>&launchSource=External…".

Cada juego es una tarjeta que lo abre directo en la nube. Portada y logotipo se buscan en la tienda
de Steam por el nombre; si no hay, se usan las imágenes de GFN.
"""

from __future__ import annotations

import json
import logging
import os
import re
import subprocess
import sys
import threading
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from urllib.parse import quote

from .models import LibraryItem

log = logging.getLogger(__name__)

APP_EXE = "GeForceNOW.exe"
STREAMER_EXE = "GeForceNOWStreamer.exe"
STEAM_SEARCH = "https://store.steampowered.com/api/storesearch/?term={term}&l=english&cc=US"
STEAM_ART = "https://cdn.cloudflare.steamstatic.com/steam/apps/{appid}/{name}"


def install_dir() -> Path | None:
    if sys.platform != "win32":
        return None
    path = Path(os.environ.get("LOCALAPPDATA", "")) / "NVIDIA Corporation" / "GeForceNOW" / "CEF"
    return path if (path / APP_EXE).exists() else None


def app_item() -> LibraryItem | None:
    folder = install_dir()
    if folder is None:
        return None
    return LibraryItem(id="app:geforcenow", title="GeForce NOW", category="apps", source="geforcenow",
                       subtitle="Juegos en la nube", argv=[str(folder / APP_EXE)], cwd=str(folder))


def parse_route(arguments: str) -> dict | None:
    """'--url-route="#?cmsId=100013311&launchSource=External&shortName=x"' -> {"cmsId": …}."""
    match = re.search(r"--url-route=\"?#\?([^\"\s]+)", arguments)
    if not match:
        return None
    params = dict(p.split("=", 1) for p in match.group(1).split("&") if "=" in p)
    return params if params.get("cmsId") else None


def _shortcut_dirs() -> list[Path]:
    dirs = [Path.home() / "Desktop", Path(os.environ.get("PUBLIC", r"C:\Users\Public")) / "Desktop",
            Path(os.environ.get("APPDATA", "")) / "Microsoft" / "Windows" / "Start Menu" / "Programs"]
    onedrive = os.environ.get("OneDrive")
    if onedrive:
        dirs.append(Path(onedrive) / "Desktop")
    return [d for d in dirs if d.is_dir()]


def read_shortcuts() -> list[dict]:
    """Accesos directos de juegos de GFN: [{"title", "target", "arguments", "cms_id"}]."""
    if sys.platform != "win32":
        return []
    script = (
        "$sh = New-Object -ComObject WScript.Shell; "
        "Get-ChildItem -LiteralPath $env:ORBITAL_DIRS.Split('|') -Recurse -Filter *.lnk -ErrorAction SilentlyContinue | "
        "ForEach-Object { $l = $sh.CreateShortcut($_.FullName); "
        "if ($l.TargetPath -like '*GeForceNOW*' -and $l.Arguments -like '*url-route*') { "
        "[pscustomobject]@{title=$_.BaseName; target=$l.TargetPath; arguments=$l.Arguments} } } | ConvertTo-Json -Compress"
    )
    try:
        out = subprocess.run(["powershell", "-NoProfile", "-Command", script], capture_output=True, text=True,
                             encoding="utf-8", errors="replace", timeout=20,
                             env={**os.environ, "ORBITAL_DIRS": "|".join(map(str, _shortcut_dirs()))},
                             creationflags=subprocess.CREATE_NO_WINDOW).stdout.strip()  # type: ignore[attr-defined]
        found = json.loads(out) if out else []
    except (OSError, subprocess.TimeoutExpired, ValueError) as exc:
        log.info("No pude leer accesos directos de GeForce NOW: %s", exc)
        return []
    found = found if isinstance(found, list) else [found]
    games = []
    for sc in found:
        route = parse_route(sc.get("arguments") or "")
        if route:
            games.append({"title": sc["title"], "target": sc["target"], "arguments": sc["arguments"],
                          "cms_id": route["cmsId"]})
    return games


def clean_title(name: str) -> str:
    """'Apex Legends - Shortcut' / 'Apex Legends™ (GeForce NOW)' -> 'Apex Legends'."""
    name = re.sub(r"[™®©]", "", name)
    name = re.sub(r"\s*-\s*(acceso directo|shortcut)$", "", name, flags=re.I)
    return re.sub(r"\s*\((geforce now|gfn)\)$", "", name, flags=re.I).strip()


# ----------------------------------------------------------------------------- Mi biblioteca
STORES = {"STEAM": "Steam", "EPIC": "Epic", "EA_APP": "EA app", "UBISOFT": "Ubisoft", "BATTLENET": "Battle.net",
          "XBOX": "Xbox", "MICROSOFT": "Xbox", "GOG": "GOG", "NONE": ""}
LIBRARY_MARK = b"requestType=panels/Library"


def cache_dir() -> Path | None:
    base = Path(os.environ.get("LOCALAPPDATA", "")) / "NVIDIA Corporation" / "GeForceNOW" / "CefCache" / "Default"
    path = base / "Service Worker" / "CacheStorage"
    return path if path.is_dir() else None


def parse_library(data: dict) -> list[dict]:
    """De la respuesta del panel Library: tus juegos que se pueden jugar, con su variante elegida."""
    games = []
    for panel in (data.get("data") or {}).get("panels") or []:
        for section in panel.get("sections") or []:
            for entry in section.get("items") or []:
                app = entry.get("app") or {}
                variants = app.get("variants") or []
                lib = lambda v: ((v.get("gfn") or {}).get("library") or {})  # noqa: E731
                variant = next((v for v in variants if lib(v).get("selected")), None) \
                    or next((v for v in variants if lib(v).get("status")), None)
                if not variant or not app.get("title"):
                    continue
                playable = lib(variant).get("playStatus") in (None, "PLAYABLE") and \
                    (app.get("gfn") or {}).get("playabilityState") in (None, "PLAYABLE")
                if not playable:
                    continue  # en tu biblioteca pero no se puede jugar (no está en GFN, membresía…)
                images = app.get("images") or {}
                games.append({
                    "title": clean_title(app["title"]), "cms_id": str(variant["id"]),
                    "short_name": variant.get("shortName") or "", "store": STORES.get(variant.get("appStore") or "", ""),
                    "banner": images.get("TV_BANNER"), "hero": images.get("HERO_IMAGE") or images.get("TV_BANNER"),
                })
    return games


def read_library_cache(folder: Path | None = None) -> list[dict]:
    """Tu biblioteca según la última vez que la app de GFN la cargó (la respuesta más reciente)."""
    folder = folder or cache_dir()
    if folder is None:
        return []
    candidates = []
    for path in folder.glob("*/*/*_0"):
        try:
            if path.stat().st_size > 5_000_000:
                continue
            with path.open("rb") as fh:
                if LIBRARY_MARK in fh.read(4096):
                    candidates.append(path)
        except OSError:
            continue
    for path in sorted(candidates, key=lambda p: p.stat().st_mtime, reverse=True):
        raw = path.read_bytes()
        start = raw.find(b'{"data"')
        if start < 0:
            continue
        try:
            data, _ = json.JSONDecoder().raw_decode(raw[start:].decode("utf-8", "replace"))
        except ValueError:
            continue
        games = parse_library(data)
        if games:
            return games
    return []


def library_argv(streamer: str, game: dict) -> list[str]:
    """Lo mismo que lanza un acceso directo de GFN para ese juego."""
    route = f"#?cmsId={game['cms_id']}&launchSource=External&shortName={game['short_name']}&parentGameId="
    return [streamer, f"--url-route={route}"]


class SteamArt:
    """Portada, fondo y logotipo de la tienda de Steam por nombre (en caché)."""

    def __init__(self) -> None:
        self._cache: dict[str, int | None] = {}
        self._lock = threading.Lock()

    def appid(self, title: str) -> int | None:
        key = title.lower()
        with self._lock:
            if key in self._cache:
                return self._cache[key]
        try:
            req = urllib.request.Request(STEAM_SEARCH.format(term=quote(title)), headers={"User-Agent": "Orbital"})
            with urllib.request.urlopen(req, timeout=8) as res:
                items = (json.load(res) or {}).get("items") or []
            # "Apex Legends™" en Steam es "Apex Legends" aquí.
            exact = next((i for i in items if clean_title(i.get("name", "")).lower() == key), None)
            found = (exact or (items[0] if items else {})).get("id")
        except (OSError, ValueError):
            found = None
        with self._lock:
            self._cache[key] = found
        return found


def items(art: SteamArt | None = None) -> list[LibraryItem]:
    art = art or SteamArt()
    found: dict[str, LibraryItem] = {}
    for sc in read_shortcuts():
        title = clean_title(sc["title"])
        found[sc["cms_id"]] = _item(art, sc["cms_id"], title, [sc["target"], *_split_args(sc["arguments"])])
    folder = install_dir()
    if folder is not None:
        library = read_library_cache()
        # Portadas de Steam en paralelo (una consulta por juego; con 40 juegos, en serie tardaba).
        with ThreadPoolExecutor(max_workers=8) as pool:
            list(pool.map(lambda game: art.appid(game["title"]), library))
        for game in library:
            if game["cms_id"] not in found:
                found[game["cms_id"]] = _item(art, game["cms_id"], game["title"],
                                              library_argv(str(folder / STREAMER_EXE), game), game)
    return sorted(found.values(), key=lambda i: i.title.lower())


def _item(art: SteamArt, cms_id: str, title: str, argv: list[str], game: dict | None = None) -> LibraryItem:
    appid = art.appid(title)
    game = game or {}
    store = game.get("store")
    return LibraryItem(
        id=f"gfn:{cms_id}",
        title=title,
        category="geforcenow",
        source="geforcenow",
        subtitle=f"GeForce NOW · {store}" if store else "GeForce NOW",
        argv=argv,
        # Portada vertical de Steam (las filas son de portadas); si no, el banner de GFN.
        image=STEAM_ART.format(appid=appid, name="library_600x900.jpg") if appid else game.get("banner"),
        hero=STEAM_ART.format(appid=appid, name="library_hero.jpg") if appid else game.get("hero"),
        extra={"logo": STEAM_ART.format(appid=appid, name="logo.png")} if appid else {},
    )


def _split_args(arguments: str) -> list[str]:
    """Argumentos del acceso directo, sin las comillas: GFN debe recibir --url-route=#?cmsId=…
    como lo recibe desde el acceso directo (Windows quita las comillas al leer la línea)."""
    return [token.replace('"', "") for token in re.findall(r'(?:[^\s"]+|"[^"]*")+', arguments.strip())]
