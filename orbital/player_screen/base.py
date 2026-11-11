"""Lo que usan todas las piezas del reproductor en pantalla: la bitácora, cuánto queda «adelantando» y cómo se preparan las
imágenes que mpv pone encima (la imagen de fondo de la tarjeta y el logo del título en pausa)."""

from __future__ import annotations

import logging

log = logging.getLogger("orbital.player_screen")  # el nombre de siempre: la bitácora no cambia

SEEK_LINGER = 2.0  # s que se queda la vista de «adelantar» (en pausa vuelve a la de pausa)


def still_bgra(raw: bytes, url: str, size: tuple[int, int], radius: int,
               steps: tuple[float, ...]) -> tuple[list[str], int, int]:
    """El cuadro del episodio -> archivos BGRA (alfa premultiplicado, para mpv overlay-add) del tamaño exacto de su lugar
    (recortado para llenarlo, sin estirarlo), con las esquinas redondeadas y una copia por cada paso de transparencia
    (`steps`): así entra y sale con la tarjeta. (rutas, ancho, alto)."""
    import hashlib
    import io
    import tempfile
    from pathlib import Path as _Path

    from PIL import Image, ImageDraw, ImageOps

    w, h = size
    image = ImageOps.fit(Image.open(io.BytesIO(raw)).convert("RGB"), (w, h), Image.Resampling.LANCZOS)
    big = Image.new("L", (w * 4, h * 4), 0)  # la esquina, dibujada en grande y reducida: sin dientes
    ImageDraw.Draw(big).rounded_rectangle((0, 0, w * 4 - 1, h * 4 - 1), radius * 4, fill=255)
    mask = big.resize((w, h), Image.Resampling.LANCZOS)
    folder = _Path(tempfile.gettempdir()) / "orbital-stills"
    folder.mkdir(exist_ok=True)
    key = hashlib.sha1(url.encode("utf-8", "surrogatepass")).hexdigest()[:16]
    paths = []
    for step in steps:
        rgba = image.convert("RGBA")
        rgba.putalpha(mask.point([round(v * step) for v in range(256)]))  # el filo con su suavizado, más transparente
        r, g, b, a = rgba.convert("RGBa").split()  # RGBa: alfa premultiplicado
        path = folder / f"{key}-{w}x{h}-{round(step * 100)}.bgra"
        path.write_bytes(Image.merge("RGBa", (b, g, r, a)).tobytes())
        paths.append(str(path))
    return paths, w, h


def logo_bgra(raw: bytes, key: str, box: tuple[float, float]) -> tuple[str, int, int] | None:
    """PNG del logo -> archivo BGRA con alfa premultiplicado (lo que pide mpv overlay-add), del tamaño que cabe en `box`
    (px). (ruta, ancho, alto) o None si no es una imagen."""
    import io
    import re as _re
    import tempfile
    from pathlib import Path as _Path

    from PIL import Image

    image = Image.open(io.BytesIO(raw)).convert("RGBA")
    ratio = min(box[0] / image.width, box[1] / image.height)
    size = (max(1, round(image.width * ratio)), max(1, round(image.height * ratio)))
    image = image.resize(size, Image.Resampling.LANCZOS)
    r, g, b, a = image.convert("RGBa").split()  # RGBa: alfa premultiplicado
    data = Image.merge("RGBa", (b, g, r, a)).tobytes()
    folder = _Path(tempfile.gettempdir()) / "orbital-logos"
    folder.mkdir(exist_ok=True)
    path = folder / f"{_re.sub(r'[^A-Za-z0-9_-]', '_', key)}-{size[0]}x{size[1]}.bgra"
    path.write_bytes(data)
    return str(path), size[0], size[1]
