"""Portadas del tamaño en que se ven.

Las del scraper (ES-DE, ScreenScraper…) llegan de hasta 1500 x 2200 y 2,5 MB, para una tarjeta de unos
150 px: la TV decodificaba megapíxeles en cada cambio de consola y, con poca memoria, las portadas
tardaban en salir. Aquí se hace una copia reducida (WebP) una sola vez y se guarda junto al arte.

Sin Pillow (o con un archivo que no se puede leer) se sirve el original: nunca falta la portada.
"""

from __future__ import annotations

import hashlib
import logging
import threading
from pathlib import Path

log = logging.getLogger(__name__)

COVER_WIDTH = 480  # px: una tarjeta en la TV 4K al 300 % o en la Legion Go al 200 %, con margen
_lock = threading.Lock()


def thumbnail(path: Path, width: int, cache_dir: Path) -> Path:
    """La copia reducida de `path` (`width` de ancho) o el original si no hace falta o no se puede."""
    try:
        from PIL import Image
    except ImportError:
        return path
    try:
        stat = path.stat()
        key = hashlib.sha1(f"{path}|{stat.st_mtime_ns}|{stat.st_size}|{width}".encode("utf-8", "surrogatepass")).hexdigest()[:24]
        out = cache_dir / f"{key}.webp"
        if out.is_file():
            return out
        with Image.open(path) as image:
            if image.width <= width * 1.15:
                return path  # ya es chica (Steam): no vale la pena
            image.draft("RGB", (width, width * 4))  # los JPEG se decodifican ya reducidos: más rápido
            image.thumbnail((width, width * 4))
            converted = image.convert("RGBA" if image.mode in ("RGBA", "LA", "P") else "RGB")
            with _lock:
                cache_dir.mkdir(parents=True, exist_ok=True)
                tmp = out.with_suffix(".tmp")
                converted.save(tmp, "WEBP", quality=84, method=4)
                tmp.replace(out)
        return out
    except (OSError, ValueError, Image.DecompressionBombError) as exc:
        log.info("No pude reducir %s: %s", path, exc)
        return path


def warm(paths: list[Path], width: int, cache_dir: Path) -> None:
    """Prepara las copias de antemano (en segundo plano): la primera visita a cada consola ya es rápida."""
    for path in paths:
        if path.is_file():
            thumbnail(path, width, cache_dir)
