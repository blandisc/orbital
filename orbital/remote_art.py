"""El arte de internet (metahub, TMDB, Steam, libretro) del tamaño en que se ve.

Una tarjeta de «Seguir viendo» de 133 px pedía el fondo de 1920 x 1080 de metahub: 8 MB ya decodificado, por cada una,
y el mosaico y las listas igual con cada póster. Edge guardaba todo eso en la memoria de su proceso de GPU (más de 1 GB
tras un rato). Aquí se baja una vez, se reduce al ancho que pide la tarjeta (thumbs.py, WebP) y se sirve desde el disco.

Solo se piden direcciones de los sitios de arte conocidos (nunca una dirección cualquiera: no es un proxy abierto).
Si algo falla, la ruta manda a la dirección original: nunca falta la imagen.
"""

from __future__ import annotations

import hashlib
import logging
import os
import threading
import time
import urllib.request
from pathlib import Path
from urllib.parse import urlsplit

from . import thumbs
from .atomic import atomic_write
from .net import NET_ERRORS, read_body

log = logging.getLogger(__name__)

HOSTS = ("images.metahub.space", "live.metahub.space", "episodes.metahub.space", "image.tmdb.org", "cdn.cloudflare.steamstatic.com",
         "cdn.akamai.steamstatic.com", "shared.cloudflare.steamstatic.com", "shared.akamai.steamstatic.com",
         "steamcdn-a.akamaihd.net", "thumbnails.libretro.com", "media.rawg.io", "walter-r2.trakt.tv",
         "cdn.thegamesdb.net", "upload.wikimedia.org", "cdn2.steamgriddb.com")  # las dos últimas: «Elegir imagen» de los juegos
WIDTHS = (160, 240, 320, 480, 640, 960, 1280, 1920)
MAX_BYTES = 12 * 1024 * 1024
RETRY_AFTER = 15 * 60  # una imagen que no se pudo bajar no se vuelve a pedir en un rato (va la original)
KEEP_RAW = 3000  # originales en disco; los más viejos se borran
SIZED_PER_RAW = 3  # copias reducidas por original, de media (cada original se pide en uno a tres anchos)
MAX_DISK = 1024 * 1024 * 1024  # 1 GB entre originales y copias: el disco de la Legion Go no es infinito
PRUNE_DELAY = 120  # s tras arrancar

_slots = threading.BoundedSemaphore(4)  # pocas a la vez: la TV no se ahoga
_locks: dict[str, threading.Lock] = {}
_guard = threading.Lock()
_misses: dict[str, float] = {}


def allowed(url: str) -> bool:
    parts = urlsplit(url or "")
    return parts.scheme == "https" and (parts.hostname or "").lower() in HOSTS


def snap(width: int) -> int:
    """Al ancho fijo más cercano por arriba (pocas copias por imagen)."""
    return next((w for w in WIDTHS if w >= width), WIDTHS[-1])


def cache_root() -> Path:
    return Path(os.environ.get("LOCALAPPDATA") or Path.home()) / "orbital" / "cache" / "art-web"


def fetch(url: str, timeout: float = 10) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": "Orbital/0.1", "Accept": "image/*"})
    with urllib.request.urlopen(req, timeout=timeout) as res:
        return read_body(res, timeout=timeout, limit=MAX_BYTES)


def _lock(key: str) -> threading.Lock:
    with _guard:
        return _locks.setdefault(key, threading.Lock())


def sized(url: str, width: int, root: Path | None = None, download=None) -> Path | None:
    """La copia de `url` a `width` de ancho (o el original bajado si ya es chico). None si no se pudo."""
    if not allowed(url):
        return None
    root = root or cache_root()
    key = hashlib.sha1(url.encode("utf-8", "surrogatepass")).hexdigest()[:24]
    raw = root / "raw" / f"{key}.img"
    if not raw.is_file():
        if time.monotonic() - _misses.get(key, -1e9) < RETRY_AFTER:
            return None
        with _lock(key):
            if not raw.is_file():
                try:
                    with _slots:
                        data = (download or fetch)(url)
                    raw.parent.mkdir(parents=True, exist_ok=True)
                    atomic_write(raw, data, durable=False)
                except NET_ERRORS as exc:
                    log.debug("No pude bajar %s: %s", url, exc)
                    if len(_misses) > 5000:
                        _misses.clear()
                    _misses[key] = time.monotonic()
                    return None
    return thumbs.thumbnail(raw, snap(width), root / "sized")


def prune(root: Path | None = None, keep: int = KEEP_RAW, max_bytes: int = MAX_DISK) -> int:
    """Pone el caché a dieta: los originales (raw/) y las copias reducidas (sized/) más viejos se borran si hay más de
    `keep` originales, más de `keep * SIZED_PER_RAW` copias o si entre los dos pasan de `max_bytes`. Lo que se borre se
    vuelve a bajar o a reducir solo cuando se pida. También limpia temporales abandonados. Devuelve cuántos borró."""
    base = root or cache_root()
    now = time.time()
    found: dict[str, list[tuple[float, int, Path]]] = {"raw": [], "sized": []}
    removed = 0
    for name in found:
        try:
            entries = list(os.scandir(base / name))
        except OSError:
            continue
        for entry in entries:
            try:
                if not entry.is_file():
                    continue
                stat = entry.stat()
            except OSError:
                continue
            path = Path(entry.path)
            if path.suffix in (".tmp", ".part"):  # una escritura que se cortó (más de una hora: ya nadie la termina)
                if now - stat.st_mtime > 3600 and _unlink(path):
                    removed += 1
                continue
            found[name].append((stat.st_mtime, stat.st_size, path))
    doomed: set[Path] = set()
    for name, limit in (("raw", keep), ("sized", keep * SIZED_PER_RAW)):
        files = sorted(found[name], key=lambda f: f[0])
        doomed.update(path for _, _, path in files[: max(0, len(files) - limit)])
    left = sorted((f for f in found["raw"] + found["sized"] if f[2] not in doomed), key=lambda f: f[0])
    total = sum(size for _, size, _ in left)
    for _, size, path in left:  # por tamaño: de lo más viejo a lo más nuevo hasta caber
        if total <= max_bytes:
            break
        doomed.add(path)
        total -= size
    for path in doomed:
        if _unlink(path):
            removed += 1
    if removed:
        log.info("Arte de internet: borré %d archivos viejos del caché", removed)
    return removed


def _unlink(path: Path) -> bool:
    try:
        path.unlink()
        return True
    except OSError:  # en uso (se está sirviendo) o ya no estaba
        return False


def prune_later(delay: float = PRUNE_DELAY) -> threading.Thread:
    """Al arrancar, en segundo plano y tras un rato (que el arranque termine primero)."""
    def run() -> None:
        time.sleep(delay)
        try:
            prune()
        except Exception:  # noqa: BLE001 - limpiar el caché nunca tumba a Orbital
            log.exception("Arte de internet: no pude limpiar el caché")

    thread = threading.Thread(target=run, daemon=True, name="art-prune")
    thread.start()
    return thread
