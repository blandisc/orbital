"""GeForce NOW: la app y tus juegos en la nube.

NVIDIA no publica una API de biblioteca (y no usamos tu sesión). Lo que sí existe: la app de GFN crea
accesos directos de cada juego (en el juego: ⋯ -> Crear acceso directo) que lanzan
GeForceNOWStreamer.exe --url-route="#?cmsId=<id>&launchSource=External…". Orbital los importa: cada
uno es una tarjeta que abre ese juego directo en la nube. Portada, fondo y logotipo se buscan en la
tienda de Steam por el nombre.
"""

from __future__ import annotations

import json
import logging
import os
import re
import subprocess
import sys
import urllib.request
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
    """'Apex Legends - Shortcut' / 'Apex Legends (GeForce NOW)' -> 'Apex Legends'."""
    name = re.sub(r"\s*-\s*(acceso directo|shortcut)$", "", name, flags=re.I)
    return re.sub(r"\s*\((geforce now|gfn)\)$", "", name, flags=re.I).strip()


class SteamArt:
    """Portada, fondo y logotipo de la tienda de Steam por nombre (en caché)."""

    def __init__(self) -> None:
        self._cache: dict[str, int | None] = {}

    def appid(self, title: str) -> int | None:
        key = title.lower()
        if key not in self._cache:
            try:
                req = urllib.request.Request(STEAM_SEARCH.format(term=quote(title)), headers={"User-Agent": "Orbital"})
                with urllib.request.urlopen(req, timeout=8) as res:
                    items = (json.load(res) or {}).get("items") or []
                exact = next((i for i in items if i.get("name", "").lower() == key), None)
                self._cache[key] = (exact or (items[0] if items else {})).get("id")
            except (OSError, ValueError):
                self._cache[key] = None
        return self._cache[key]


def items(art: SteamArt | None = None) -> list[LibraryItem]:
    art = art or SteamArt()
    found = []
    for sc in read_shortcuts():
        title = clean_title(sc["title"])
        appid = art.appid(title)
        found.append(LibraryItem(
            id=f"gfn:{sc['cms_id']}",
            title=title,
            category="geforcenow",
            source="geforcenow",
            subtitle="GeForce NOW",
            argv=[sc["target"], *_split_args(sc["arguments"])],
            image=STEAM_ART.format(appid=appid, name="library_600x900.jpg") if appid else None,
            hero=STEAM_ART.format(appid=appid, name="library_hero.jpg") if appid else None,
            extra={"logo": STEAM_ART.format(appid=appid, name="logo.png")} if appid else {},
        ))
    return sorted(found, key=lambda i: i.title.lower())


def _split_args(arguments: str) -> list[str]:
    """Argumentos del acceso directo, sin las comillas: GFN debe recibir --url-route=#?cmsId=…
    como lo recibe desde el acceso directo (Windows quita las comillas al leer la línea)."""
    return [token.replace('"', "") for token in re.findall(r'(?:[^\s"]+|"[^"]*")+', arguments.strip())]
