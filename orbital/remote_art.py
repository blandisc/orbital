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
from .net import NET_ERRORS, read_body

log = logging.getLogger(__name__)

HOSTS = ("images.metahub.space", "live.metahub.space", "episodes.metahub.space", "image.tmdb.org", "cdn.cloudflare.steamstatic.com",
         "cdn.akamai.steamstatic.com", "shared.cloudflare.steamstatic.com", "shared.akamai.steamstatic.com",
         "steamcdn-a.akamaihd.net", "thumbnails.libretro.com", "media.rawg.io", "walter-r2.trakt.tv",
         "cdn.thegamesdb.net", "upload.wikimedia.org")  # las dos últimas: «Elegir imagen» de los juegos
WIDTHS = (160, 240, 320, 480, 640, 960, 1280)
MAX_BYTES = 12 * 1024 * 1024
RETRY_AFTER = 15 * 60  # una imagen que no se pudo bajar no se vuelve a pedir en un rato (va la original)
KEEP_RAW = 3000  # originales en disco; los más viejos se borran

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
                    tmp = raw.with_suffix(".part")
                    tmp.write_bytes(data)
                    tmp.replace(raw)
                except NET_ERRORS as exc:
                    log.debug("No pude bajar %s: %s", url, exc)
                    if len(_misses) > 5000:
                        _misses.clear()
                    _misses[key] = time.monotonic()
                    return None
    return thumbs.thumbnail(raw, snap(width), root / "sized")


def prune(root: Path | None = None, keep: int = KEEP_RAW) -> int:
    """Borra los originales más viejos si hay demasiados (y sus copias reducidas se rehacen solas si se piden)."""
    folder = (root or cache_root()) / "raw"
    try:
        files = sorted(folder.glob("*.img"), key=lambda p: p.stat().st_mtime)
    except OSError:
        return 0
    removed = 0
    for path in files[: max(0, len(files) - keep)]:
        try:
            path.unlink()
            removed += 1
        except OSError:
            pass
    return removed
