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
import sys
import threading
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from urllib.parse import quote

from ..net import NET_ERRORS, read_json
from .models import LibraryItem

log = logging.getLogger(__name__)

APP_EXE = "GeForceNOW.exe"
# Lo que lanzaban los accesos directos viejos. En la app de ahora (2.0.89) ya no hace nada: se cierra en 0,1 s sin abrir el
# juego (medido 2026-10-20). Quien entiende --url-route es la app misma, y si ya está abierta, cambia su ventana al juego.
STREAMER_EXE = "GeForceNOWStreamer.exe"
APP_TITLE = "GeForce NOW"  # la ventana de la app en su biblioteca; con un juego: «STAR WARS™ Battlefront II on GeForce NOW»


def in_game_title(title: str) -> bool:
    """¿El título de la ventana de la app es el de un juego en la nube (no su biblioteca ni una ventana sin título)?"""
    return bool(title) and title.strip() != APP_TITLE and APP_TITLE in title


def in_session() -> bool:
    """¿Hay un juego abierto en la app? Al salir del juego la app vuelve a su biblioteca y sigue abierta: lo que cuenta es
    el título de su ventana, no que el programa siga."""
    from .. import windows
    return any(in_game_title(windows.title(h)) for h in windows.windows_of(windows.pids_by_exe(APP_EXE)))
STEAM_SEARCH = "https://store.steampowered.com/api/storesearch/?term={term}&l=english&cc=US"
STEAM_ART = "https://cdn.cloudflare.steamstatic.com/steam/apps/{appid}/{name}"


PUBLIC_LIST = "https://static.nvidiagrid.net/supported-public-game-list/locales/gfnpc-en-US.json"
PUBLIC_REFRESH = 24 * 3600


def fetch_public() -> list | None:
    """La lista pública de NVIDIA con todo lo que se puede jugar en GeForce NOW (sin cuenta). None si no se pudo."""
    try:
        req = urllib.request.Request(PUBLIC_LIST, headers={"User-Agent": "Mozilla/5.0 Orbital"})
        with urllib.request.urlopen(req, timeout=20) as res:
            data = read_json(res, timeout=20, limit=8 * 1024 * 1024)
    except NET_ERRORS:
        return None
    return data if isinstance(data, list) else None


def cloud_by_steam(path: Path | None, now: float | None = None) -> dict[str, dict]:
    """{número de Steam: {"cms_id", "title"}} de los juegos de Steam que se pueden jugar en GeForce NOW. Se baja una
    vez al día y se guarda; sin red, la copia guardada."""
    now = now if now is not None else time.time()
    games = None
    if path is not None and path.exists() and now - path.stat().st_mtime < PUBLIC_REFRESH:
        games = _read_json(path)
    if games is None:
        games = fetch_public()
        if games is not None and path is not None:
            try:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(json.dumps(games), encoding="utf-8")
            except OSError as exc:
                log.info("No pude guardar la lista de GeForce NOW: %s", exc)
        elif path is not None and path.exists():
            games = _read_json(path)
    out: dict[str, dict] = {}
    for game in games or []:
        if not isinstance(game, dict) or game.get("status") != "AVAILABLE" or not game.get("id"):
            continue
        if (m := re.search(r"/app/(\d+)", str(game.get("steamUrl") or ""))):
            out[m.group(1)] = {"cms_id": str(game["id"]), "title": clean_title(str(game.get("title") or ""))}
    return out


def _read_json(path: Path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None


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


def read_shortcuts(dirs: list[Path] | None = None) -> list[dict]:
    """Accesos directos de juegos de GFN: [{"title", "target", "arguments", "cms_id"}].
    Se leen los .lnk directamente (antes: PowerShell + WScript.Shell, ~0,5 s por escaneo)."""
    from .shortcuts import read_lnk

    games = []
    for folder in dirs if dirs is not None else _shortcut_dirs():
        try:
            links = sorted(folder.rglob("*.lnk"))
        except OSError:
            continue
        for link in links:
            sc = read_lnk(link)
            if sc is None or "geforcenow" not in sc.target.lower() or "url-route" not in sc.arguments:
                continue
            route = parse_route(sc.arguments)
            if route:
                games.append({"title": link.stem, "target": sc.target, "arguments": sc.arguments,
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
                # Uno que agregaste a mano viene con playStatus «UNKNOWN» aunque se pueda jugar (Empire of the Ants se
                # quedaba fuera): manda lo que dice el juego (playabilityState).
                playable = (lib(variant).get("playStatus") in (None, "PLAYABLE", "UNKNOWN")
                            and (app.get("gfn") or {}).get("playabilityState") in (None, "PLAYABLE"))
                if not playable:
                    continue  # en tu biblioteca pero no se puede jugar (no está en GFN, membresía…)
                images = app.get("images") or {}
                games.append({
                    "recent": len(games),  # el orden del panel: del jugado más reciente al más viejo
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
            items = sum(len(s.get("items") or []) for p in (data.get("data") or {}).get("panels") or [] for s in p.get("sections") or [])
            if items >= 40:  # el panel trae solo tus 40 más recientes: los de atrás no se ven (salvo los de Steam)
                log.info("GeForce NOW: tu biblioteca trae %d juegos (los más recientes); puede haber más que no se ven", items)
            return games
    return []


def library_argv(app: str, game: dict) -> list[str]:
    """Lo que abre ese juego en la nube: la app con su ruta (la del acceso directo de GFN)."""
    route = f"#?cmsId={game['cms_id']}&launchSource=External&shortName={game['short_name']}&parentGameId="
    return [app, f"--url-route={route}"]


def _app_target(target: str) -> str:
    """Un acceso directo viejo apunta al Streamer, que ya no abre nada: el de la app, en la misma carpeta."""
    path = Path(target)
    return str(path.with_name(APP_EXE)) if path.name.lower() == STREAMER_EXE.lower() else target


class SteamArt:
    """Portada, fondo y logotipo de la tienda de Steam por nombre (en caché).

    Con `path`, lo encontrado se guarda en disco: antes cada arranque de Orbital volvía a preguntar
    a Steam por los ~40 juegos de GFN (2 s de pantalla de arranque). "No está en Steam" se vuelve a
    preguntar a la semana; un fallo de red, en el siguiente arranque."""

    RETRY_MISSING = 7 * 24 * 3600

    def __init__(self, path: Path | None = None) -> None:
        self.path = path
        self._cache: dict[str, int | None] = {}
        self._missing_since: dict[str, float] = {}
        self._dirty = False
        self._lock = threading.Lock()
        if path and path.exists():
            try:
                saved = json.loads(path.read_text(encoding="utf-8"))
                now = time.time()
                self._cache = {k: v for k, v in saved.get("appids", {}).items() if isinstance(v, int)}
                for key, since in saved.get("missing", {}).items():
                    if now - since < self.RETRY_MISSING:
                        self._cache[key], self._missing_since[key] = None, since
            except (OSError, ValueError, AttributeError) as exc:
                log.info("Caché de portadas ilegible (se rehace): %s", exc)

    def appid(self, title: str) -> int | None:
        key = title.lower()
        with self._lock:
            if key in self._cache:
                return self._cache[key]
        try:
            req = urllib.request.Request(STEAM_SEARCH.format(term=quote(title)), headers={"User-Agent": "Orbital"})
            with urllib.request.urlopen(req, timeout=8) as res:
                data = read_json(res, timeout=8)
            items = (data.get("items") if isinstance(data, dict) else None) or []
            # "Apex Legends™" en Steam es "Apex Legends" aquí.
            exact = next((i for i in items if clean_title(i.get("name", "")).lower() == key), None)
            found = (exact or (items[0] if items else {})).get("id")
            remember = True
        except (*NET_ERRORS, AttributeError, TypeError):
            found, remember = None, False  # sin red: no se guarda en disco, se reintenta al arrancar
        with self._lock:
            self._cache[key] = found
            if remember:
                self._dirty = True
                if found is None:
                    self._missing_since[key] = time.time()
        return found

    def save(self) -> None:
        with self._lock:
            if not self.path or not self._dirty:
                return
            data = {"appids": {k: v for k, v in self._cache.items() if v is not None},
                    "missing": dict(self._missing_since)}
            self._dirty = False
        try:
            self.path.parent.mkdir(parents=True, exist_ok=True)
            tmp = self.path.with_suffix(".tmp")
            tmp.write_text(json.dumps(data), encoding="utf-8")
            tmp.replace(self.path)
        except OSError as exc:
            log.info("No pude guardar la caché de portadas: %s", exc)


def items(art: SteamArt | None = None, cloud: list[tuple[str, dict]] | None = None) -> list[LibraryItem]:
    """Tus juegos de GeForce NOW: tus accesos directos, tu «Mi biblioteca» (los 40 jugados más recientes que guarda la
    app) y `cloud`: los juegos de tu cuenta de Steam que se pueden jugar en la nube ([(número de Steam, juego)])."""
    art = art or SteamArt()
    found: dict[str, LibraryItem] = {}
    for sc in read_shortcuts():
        title = clean_title(sc["title"])
        found[sc["cms_id"]] = _item(art, sc["cms_id"], title, [_app_target(sc["target"]), *_split_args(sc["arguments"])])
    folder = install_dir()
    if folder is not None:
        library = read_library_cache()
        # Portadas de Steam en paralelo (una consulta por juego; con 40 juegos, en serie tardaba).
        with ThreadPoolExecutor(max_workers=8) as pool:
            list(pool.map(lambda game: art.appid(game["title"]), library))
        for game in library:
            if game["cms_id"] not in found:
                found[game["cms_id"]] = _item(art, game["cms_id"], game["title"],
                                              library_argv(str(folder / APP_EXE), game), game)
        titles = {i.title.lower() for i in found.values()}
        appids = {i.steam_appid for i in found.values() if i.steam_appid}
        for appid, game in cloud or []:
            if game["cms_id"] in found or int(appid) in appids or game["title"].lower() in titles:
                continue  # ya estaba en tu biblioteca de GeForce NOW
            found[game["cms_id"]] = _item(art, game["cms_id"], game["title"],
                                          library_argv(str(folder / APP_EXE), {**game, "short_name": ""}),
                                          {"store": "Steam"}, appid=int(appid))
    if hasattr(art, "save"):
        art.save()
    return sorted(found.values(), key=lambda i: i.title.lower())


def _item(art: SteamArt, cms_id: str, title: str, argv: list[str], game: dict | None = None,
          appid: int | None = None) -> LibraryItem:
    appid = appid or art.appid(title)
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
        extra={**({"logo": STEAM_ART.format(appid=appid, name="logo.png")} if appid else {}),
               **({"recent_rank": game["recent"]} if "recent" in game else {})},
        steam_appid=appid,  # el mismo juego en la tienda de Steam: de ahí su descripción, año y géneros
    )


def _split_args(arguments: str) -> list[str]:
    """Argumentos del acceso directo, sin las comillas: GFN debe recibir --url-route=#?cmsId=…
    como lo recibe desde el acceso directo (Windows quita las comillas al leer la línea)."""
    return [token.replace('"', "") for token in re.findall(r'(?:[^\s"]+|"[^"]*")+', arguments.strip())]
