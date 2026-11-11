"""El tono dominante del arte, calculado una vez en el servidor (V3).

La interfaz de la TV sacaba el color de cada fondo leyendo píxeles en el navegador (`backdrop.js`, `getImageData`, ~15 ms
por título). Aquí se hace lo mismo que el cliente, con la misma imagen que él lee: la copia de 160 px que sirve el
servidor (`thumbs.py`), dibujada en 24 × 24, y el mismo algoritmo de `orbital/web/js/core/color.js` (`dominantHue` y
`paletteFor`): los píxeles se agrupan en 12 tonos y gana el grupo con más peso (saturación × qué tan lejos está del negro
y del blanco). Se guarda en disco por archivo (ruta, fecha y tamaño), así que cada imagen se mide una sola vez.

Sale como campo opcional `art_tone` de cada ítem: {"hue", "saturation", "tint", "accent"} o {"neutral": true} si el arte
es casi gris (el cliente usa entonces el grafito del tema). Si todavía no se midió, el campo no va y el cliente lo calcula
como siempre.
"""

from __future__ import annotations

import hashlib
import json
import logging
import threading
from pathlib import Path

log = logging.getLogger(__name__)

BUCKETS = 12
SAMPLE = 24  # px: el lienzo del cliente (backdrop.js, SAMPLE)
SOURCE_WIDTH = 160  # px: la copia que pide el cliente para medir (backdrop.js, tiny)
CACHE_MAX = 4000  # tonos guardados (cada uno pesa unos 120 bytes)


def rgb_to_hsl(r: float, g: float, b: float) -> tuple[float, float, float]:
    """Igual que `rgbToHsl` de color.js (h en grados, s y l de 0 a 1)."""
    r, g, b = r / 255, g / 255, b / 255
    hi, lo = max(r, g, b), min(r, g, b)
    light = (hi + lo) / 2
    if hi == lo:
        return 0.0, 0.0, light
    d = hi - lo
    sat = d / (2 - hi - lo) if light > .5 else d / (hi + lo)
    if hi == r:
        hue = (g - b) / d + (6 if g < b else 0)
    elif hi == g:
        hue = (b - r) / d + 2
    else:
        hue = (r - g) / d + 4
    return hue * 60, sat, light


def _js_round(value: float) -> int:
    """Math.round de JavaScript (las mitades hacia arriba), no el redondeo bancario de Python."""
    import math
    return math.floor(value + .5)


def hsl_to_rgb(h: float, s: float, light: float) -> tuple[int, int, int]:
    """Igual que `hslToRgb` de color.js."""
    def k(n: float) -> float:
        return (n + h / 30) % 12
    a = s * min(light, 1 - light)

    def f(n: float) -> float:
        return light - a * max(-1, min(k(n) - 3, min(9 - k(n), 1)))
    return _js_round(f(0) * 255), _js_round(f(8) * 255), _js_round(f(4) * 255)


def dominant_hue(pixels) -> dict | None:
    """`dominantHue` de color.js sobre RGBA plano (r, g, b, a, r, g, b, a…). None si la imagen es casi gris."""
    weight = [0.0] * BUCKETS
    hue_sum = [0.0] * BUCKETS
    sat_sum = [0.0] * BUCKETS
    for i in range(0, len(pixels) - 3, 4):
        if pixels[i + 3] < 128:
            continue
        hue, sat, light = rgb_to_hsl(pixels[i], pixels[i + 1], pixels[i + 2])
        if sat < .2 or light < .12 or light > .9:
            continue  # grises, negros y blancos no cuentan
        bucket = int(hue // (360 / BUCKETS)) % BUCKETS
        w = sat * (1 - abs(light - .5))
        weight[bucket] += w
        hue_sum[bucket] += hue * w
        sat_sum[bucket] += sat * w
    best = weight.index(max(weight))
    if weight[best] == 0:
        return None
    return {"hue": hue_sum[best] / weight[best], "saturation": sat_sum[best] / weight[best]}


def palette_for(dominant: dict | None) -> dict:
    """`paletteFor` de color.js: el tinte oscuro del fondo y la luz de acento, como «rgb(r g b)»."""
    if not dominant:
        return {"neutral": True}
    hue, sat = dominant["hue"], dominant["saturation"]
    tint = hsl_to_rgb(hue, min(sat, .55), .2)
    accent = hsl_to_rgb(hue, min(max(sat, .35), .75), .76)
    return {"hue": round(hue, 2), "saturation": round(sat, 4),
            "tint": "rgb({} {} {})".format(*tint), "accent": "rgb({} {} {})".format(*accent)}


def sample_pixels(path: Path, thumbs_dir: Path | None = None) -> bytes | None:
    """Los píxeles RGBA que lee el cliente: la copia de 160 px (o el original, si ya es chico) en un lienzo de 24 × 24."""
    try:
        from PIL import Image
    except ImportError:
        return None
    source = path
    if thumbs_dir is not None:
        from . import thumbs
        source = thumbs.thumbnail(path, SOURCE_WIDTH, thumbs_dir)
    try:
        with Image.open(source) as image:
            small = image.convert("RGBA").resize((SAMPLE, SAMPLE), Image.Resampling.BILINEAR)
            return small.tobytes()
    except (OSError, ValueError, Image.DecompressionBombError) as exc:
        log.info("No pude medir el tono de %s: %s", path, exc)
        return None


def tone_of(path: Path, thumbs_dir: Path | None = None) -> dict | None:
    """El tono del arte en `path` (None si no se pudo leer la imagen)."""
    pixels = sample_pixels(path, thumbs_dir)
    return None if pixels is None else palette_for(dominant_hue(pixels))


class ArtTones:
    """Los tonos ya medidos, en memoria y en `<thumbs>/tones.json`. `peek` nunca mide (lo llama la lista de la
    biblioteca, que debe contestar ya); `warm` mide lo que falte, en segundo plano."""

    def __init__(self, thumbs_dir: Path) -> None:
        self.thumbs_dir = thumbs_dir
        self.file = thumbs_dir / "tones.json"
        self._lock = threading.Lock()
        self._tones: dict[str, dict] = {}
        try:
            data = json.loads(self.file.read_text(encoding="utf-8"))
            self._tones = {k: v for k, v in data.items() if isinstance(v, dict)} if isinstance(data, dict) else {}
        except (OSError, ValueError):
            pass

    @staticmethod
    def key(path: Path) -> str | None:
        try:
            stat = path.stat()
        except OSError:
            return None
        return hashlib.sha1(f"{path}|{stat.st_mtime_ns}|{stat.st_size}".encode("utf-8", "surrogatepass")).hexdigest()[:20]

    def peek(self, path: str | Path | None) -> dict | None:
        if not path:
            return None
        key = self.key(Path(path))
        with self._lock:
            return self._tones.get(key) if key else None

    def measure(self, path: Path) -> dict | None:
        key = self.key(path)
        if key is None:
            return None
        with self._lock:
            if key in self._tones:
                return self._tones[key]
        tone = tone_of(path, self.thumbs_dir)
        if tone is not None:
            with self._lock:
                self._tones[key] = tone
                while len(self._tones) > CACHE_MAX:
                    self._tones.pop(next(iter(self._tones)))
        return tone

    def save(self) -> None:
        from .atomic import atomic_write
        with self._lock:
            text = json.dumps(self._tones, separators=(",", ":"))
        try:
            atomic_write(self.file, text, durable=False)
        except OSError:
            log.info("No pude guardar los tonos del arte", exc_info=True)

    def warm(self, paths: list[Path]) -> int:
        """Mide lo que falte y guarda una vez al final. Devuelve cuántos se midieron."""
        done = 0
        for path in paths:
            if self.peek(path) is None and path.is_file() and self.measure(path) is not None:
                done += 1
        if done:
            self.save()
        return done
