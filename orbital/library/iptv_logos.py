"""Logos de los canales de TV en vivo: se bajan una vez, se ponen parejos y se guardan en disco.

Los logos de iptv-org vienen de donde sea (imgur y otros), de cualquier tamaño y de todos los modos: blancos para
fondo oscuro, negros para fondo claro, con un fondo blanco propio, enormes… Puestos tal cual en una casilla, unos
se salen, otros no se ven y otros son un cuadro blanco. Aquí cada uno se recorta, se reduce y, si es oscuro, va sobre
una placa clara; así todos se leen sobre el fondo oscuro de la interfaz. Se sirven desde Orbital (`/api/tv/logo`):
la TV no le pide imágenes a internet por su cuenta, una vez bajados funcionan sin conexión y cargan rápido
(unos 30 KB cada uno).
"""

from __future__ import annotations

import hashlib
import io
import ipaddress
import json
import logging
import os
import threading
import time
import urllib.error
import urllib.request
from collections.abc import Callable
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from urllib.parse import urlsplit

from PIL import Image, ImageDraw

from ..net import NET_ERRORS, read_body

log = logging.getLogger(__name__)

BOX = (320, 200)  # px máximos de un logo ya parejo: la casilla lo muestra a ~160 px (el doble, para pantallas nítidas)
PAD = 22  # px de la placa alrededor del logo
MAX_BYTES = 2 * 1024 * 1024
MAX_PIXELS = 16_000_000  # un logo de 4000 x 4000 es un abuso, no un logo
DARK_BELOW = 0.36  # luminosidad media (0 a 1) por debajo de la cual el logo es «oscuro» y va sobre placa
RETRY_AFTER = 24 * 3600  # s antes de volver a intentar un logo que no se pudo bajar (no existe, no es una imagen…)
RETRY_SOON = 15 * 60  # …y si fue pasajero (el sitio pidió calma con un 429, se cayó un momento, no hubo red): mucho antes
# Algunos sitios (Wikimedia, de donde salen varios) piden que quien baja imágenes diga quién es.
USER_AGENT = "Orbital/0.1 (+https://github.com/blandisc/orbital; logos de la TV en vivo)"
UPSCALE_MAX = 2.0  # un logo chico se agranda hasta el doble (más no: se vería borroso)
_PALETTE = Path(__file__).resolve().parents[1] / "web" / "styles" / "palette.json"


class LogoError(Exception):
    """Lo que llegó no sirve como logo (no es una imagen, está vacía, es enorme…)."""


def _plate_color() -> tuple[int, int, int]:
    """El «papel» de la paleta de Orbital (la misma que la interfaz y el reproductor)."""
    try:
        value = json.loads(_PALETTE.read_text(encoding="utf-8"))["paper"].lstrip("#")
        return int(value[0:2], 16), int(value[2:4], 16), int(value[4:6], 16)
    except (OSError, ValueError, KeyError):
        return 245, 244, 240


def _opaque_ratio(alpha: Image.Image) -> float:
    histogram = alpha.histogram()
    total = sum(histogram) or 1
    return sum(histogram[201:]) / total


def _luminance(image: Image.Image) -> float:
    """Qué tan claro es el logo (0 negro, 1 blanco), contando más lo que más se ve (los píxeles casi transparentes no cuentan)."""
    small = image.copy()
    small.thumbnail((64, 64))
    weight = total = 0.0
    data = small.tobytes()  # R, G, B, A de cada píxel, uno tras otro
    for i in range(0, len(data) - 3, 4):
        r, g, b, a = data[i], data[i + 1], data[i + 2], data[i + 3]
        weight += a
        total += a * (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255
    return total / weight if weight else 1.0


def _fit(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    scale = min(size[0] / image.width, size[1] / image.height)
    scale = min(scale, UPSCALE_MAX)
    if scale == 1:
        return image
    target = (max(1, round(image.width * scale)), max(1, round(image.height * scale)))
    return image.resize(target, Image.Resampling.LANCZOS)


def _rounded(image: Image.Image, radius: int) -> Image.Image:
    mask = Image.new("L", image.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, image.width - 1, image.height - 1), radius=radius, fill=255)
    out = image.copy()
    out.putalpha(Image.composite(image.getchannel("A"), Image.new("L", image.size, 0), mask))
    return out


def prepare(data: bytes) -> bytes:
    """El logo listo para la casilla (PNG). Lanza LogoError si no sirve.

    · con fondo propio (una foto o un cuadro blanco): se queda como es, con las esquinas redondeadas;
    · transparente y claro o de color: se recorta y se reduce, sin más;
    · transparente y oscuro (letras negras): va sobre una placa clara."""
    try:
        image = Image.open(io.BytesIO(data))
        if image.width * image.height > MAX_PIXELS:
            raise LogoError("demasiado grande")
        image = image.convert("RGBA")
    except LogoError:
        raise
    except (OSError, ValueError, Image.DecompressionBombError, SyntaxError) as exc:
        raise LogoError(f"no es una imagen ({type(exc).__name__})") from exc
    box = image.getchannel("A").point([0] * 25 + [255] * 231).getbbox()  # lo que se ve (opacidad > 24 de 255)
    if box is None:
        raise LogoError("transparente")
    image = image.crop(box)
    if image.width < 8 or image.height < 8:
        raise LogoError("muy chico")
    if _opaque_ratio(image.getchannel("A")) > 0.9:
        image = _rounded(_fit(image, BOX), 14)
    elif _luminance(image) < DARK_BELOW:
        inner = _fit(image, (BOX[0] - 2 * PAD, BOX[1] - 2 * PAD))
        plate = Image.new("RGBA", (inner.width + 2 * PAD, inner.height + 2 * PAD), (*_plate_color(), 255))
        plate.alpha_composite(inner, (PAD, PAD))
        image = _rounded(plate, 18)
    else:
        image = _fit(image, BOX)
    out = io.BytesIO()
    image.save(out, "PNG", optimize=True)
    return out.getvalue()


def trim(data: bytes) -> bytes:
    """El logo sin el aire transparente que trae alrededor (PNG). Los logos de títulos de metahub traen a veces casi la
    mitad de aire arriba (Midnight Mass): encima de su etiqueta quedaba un hueco que otros no tenían. Lanza LogoError."""
    try:
        image = Image.open(io.BytesIO(data))
        if image.width * image.height > MAX_PIXELS:
            raise LogoError("demasiado grande")
        image = image.convert("RGBA")
    except LogoError:
        raise
    except (OSError, ValueError, Image.DecompressionBombError, SyntaxError) as exc:
        raise LogoError(f"no es una imagen ({type(exc).__name__})") from exc
    box = image.getchannel("A").point([0] * 25 + [255] * 231).getbbox()  # lo que se ve (opacidad > 24 de 255)
    if box is None:
        raise LogoError("transparente")
    out = io.BytesIO()
    image.crop(box).save(out, "PNG", optimize=True)
    return out.getvalue()


def public_host(url: str) -> bool:
    """¿Se puede pedir esta dirección? Solo internet: ni localhost ni la red de la casa (una lista ajena no manda a Orbital
    a leer lo que hay en tu router o en tu equipo)."""
    parts = urlsplit(url)
    host = (parts.hostname or "").lower()
    if parts.scheme not in ("http", "https") or not host or host == "localhost" or host.endswith((".local", ".localhost", ".internal")):
        return False
    try:
        ip = ipaddress.ip_address(host)
    except ValueError:
        return True  # un nombre de internet
    return not (ip.is_private or ip.is_loopback or ip.is_link_local or ip.is_reserved or ip.is_multicast or ip.is_unspecified)


def download_logo(url: str, *, timeout: float = 8) -> bytes:
    """Los bytes del logo. Lanza NET_ERRORS (o LogoError) si no se puede."""
    if not public_host(url):
        raise LogoError("dirección no permitida")
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": "image/*"})
    with urllib.request.urlopen(req, timeout=timeout) as res:
        return read_body(res, timeout=timeout, limit=MAX_BYTES)


def transient(exc: Exception) -> bool:
    """¿Vale la pena reintentar pronto? Un 429/5xx, un plazo vencido o no tener red pasan; un 404 o un archivo que no es
    una imagen, no."""
    if isinstance(exc, urllib.error.HTTPError):
        return exc.code == 429 or exc.code >= 500
    return isinstance(exc, (TimeoutError, urllib.error.URLError)) and not isinstance(exc, LogoError)


class LogoCache:
    """Los logos ya parejos, en una carpeta (uno por dirección). Los que no se pudieron bajar se anotan un día entero
    para no insistir en cada pantalla."""

    def __init__(self, directory: Path | None, download: Callable[[str], bytes] | None = None, workers: int = 6) -> None:
        self.directory = directory
        # Se busca al llamar (no al definir): las pruebas cambian download_logo por una función que no sale a internet.
        self._download = download or (lambda url: download_logo(url))
        self._slots = threading.BoundedSemaphore(workers)  # unos cuantos a la vez: la TV no se ahoga mientras ve algo
        self._locks: dict[str, threading.Lock] = {}
        self._guard = threading.Lock()

    @staticmethod
    def key(url: str) -> str:
        return hashlib.sha1(url.encode("utf-8", "surrogatepass")).hexdigest()[:20]

    def _lock(self, key: str) -> threading.Lock:
        with self._guard:
            return self._locks.setdefault(key, threading.Lock())

    def _store(self, key: str, png: bytes) -> Path | None:
        if self.directory is None:
            return None
        path = self.directory / f"{key}.png"
        try:
            self.directory.mkdir(parents=True, exist_ok=True)
            tmp = path.with_suffix(".tmp")
            tmp.write_bytes(png)
            tmp.replace(path)
            path.with_suffix(".none").unlink(missing_ok=True)
        except OSError as exc:
            log.info("No pude guardar un logo: %s", exc)
            return None
        return path

    def _mark_missing(self, key: str, retry_after: float = RETRY_AFTER) -> None:
        """Anota que no se pudo bajar. La marca es la fecha del archivo: se «envejece» lo que falta para que, pasado
        `retry_after`, get() lo vuelva a intentar."""
        if self.directory is None:
            return
        try:
            self.directory.mkdir(parents=True, exist_ok=True)
            marker = self.directory / f"{key}.none"
            marker.touch()
            when = time.time() - (RETRY_AFTER - retry_after)
            os.utime(marker, (when, when))
        except OSError:
            pass

    def get(self, url: str | None) -> Path | None:
        """El archivo del logo (se baja la primera vez). None si no hay o no se pudo."""
        if not url or self.directory is None:
            return None
        key = self.key(url)
        png, missing = self.directory / f"{key}.png", self.directory / f"{key}.none"
        if png.is_file():
            return png
        try:
            if time.time() - missing.stat().st_mtime < RETRY_AFTER:
                return None
        except OSError:
            pass
        with self._lock(key):
            if png.is_file():  # otro hilo lo acaba de traer
                return png
            with self._slots:
                try:
                    return self._store(key, prepare(self._download(url)))
                except (LogoError, *NET_ERRORS) as exc:
                    log.debug("Logo sin bajar (%s): %s", urlsplit(url).hostname, exc)
                    self._mark_missing(key, RETRY_SOON if transient(exc) else RETRY_AFTER)
                    return None

    def put(self, url: str, data: bytes) -> Path | None:
        """Guarda un logo que ya se tiene (el demo y las pruebas). None si no sirve."""
        try:
            return self._store(self.key(url), prepare(data))
        except LogoError:
            return None

    def warm(self, urls: list[str], workers: int = 3) -> int:
        """Baja los que falten, de antemano (en segundo plano): la primera visita a la sección ya los tiene. Cuántos hay."""
        wanted = sorted({u for u in urls if u})
        with ThreadPoolExecutor(max_workers=max(1, workers), thread_name_prefix="tv-logos") as pool:
            return sum(1 for path in pool.map(self.get, wanted) if path is not None)
