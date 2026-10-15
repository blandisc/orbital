"""Arte propio de Orbital: portada, fondo horizontal y logotipo de cada juego, sin depender de ES-DE.

Vive en %LOCALAPPDATA%\\orbital\\media\\<sistema>\\<tipo>\\<juego>.<ext>, con el mismo nombre que la
ROM (sin extensión). El escaneo prefiere este arte y solo cae al de ES-DE si aquí no hay nada; el
de ES-DE, además, se descarta si no sirve (una captura puesta como portada, por ejemplo).
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import struct
from pathlib import Path

IMAGE_EXTS = (".png", ".jpg", ".jpeg", ".webp")
# Respaldo para lo que no tiene arte (generado con Grok Imagine): siempre hay una imagen.
PLACEHOLDER_DIR = Path(__file__).resolve().parents[1] / "web" / "img" / "placeholders"


def placeholder(kind: str, system: str | None, seed: str = "") -> str:
    """URL del respaldo ya hecho: varias opciones por sistema (hero-switch-1.jpg, hero-switch-2.jpg…)
    y, si no hay de ese sistema, las genéricas. A cada juego le toca siempre la misma (por su id),
    así no se ven todos iguales y no cambia entre escaneos."""
    for prefix in ([f"{kind}-{system}", f"{kind}-generic"] if system else [f"{kind}-generic"]):
        options = sorted(p.name for p in PLACEHOLDER_DIR.glob(f"{prefix}*.jpg")
                         if re.fullmatch(rf"{re.escape(prefix)}(-\d+)?\.jpg", p.name))
        if options:
            pick = int(hashlib.sha1(seed.encode()).hexdigest(), 16) % len(options)
            return f"/img/placeholders/{options[pick]}"
    return f"/img/placeholders/{kind}-generic-1.jpg"
KINDS = ("cover", "hero", "logo")


def default_root() -> Path:
    base = os.environ.get("LOCALAPPDATA") or os.environ.get("XDG_DATA_HOME") or str(Path.home() / ".local" / "share")
    return Path(base) / "orbital" / "media"


def image_size(path: Path) -> tuple[int, int] | None:
    """Ancho y alto leyendo solo la cabecera (PNG, JPEG, WebP), sin librerías de imagen."""
    try:
        with path.open("rb") as f:
            head = f.read(32)
            if head.startswith(b"\x89PNG\r\n\x1a\n"):
                return struct.unpack(">II", head[16:24])
            if head[:4] == b"RIFF" and head[8:12] == b"WEBP":
                return _webp_size(head, f)
            if head[:2] == b"\xff\xd8":
                return _jpeg_size(f)
    except (OSError, struct.error, IndexError, ValueError):
        return None  # truncada o rara: como si no se supiera su tamaño (no tumba el escaneo)
    return None


def _webp_size(head: bytes, f) -> tuple[int, int] | None:
    f.seek(12)
    chunk = f.read(30)
    kind = chunk[:4]
    if kind == b"VP8X":
        w = int.from_bytes(chunk[12:15], "little") + 1
        h = int.from_bytes(chunk[15:18], "little") + 1
        return w, h
    if kind == b"VP8 ":
        w, h = struct.unpack("<HH", chunk[18:22])
        return w & 0x3FFF, h & 0x3FFF
    if kind == b"VP8L":
        bits = int.from_bytes(chunk[9:13], "little")
        return (bits & 0x3FFF) + 1, ((bits >> 14) & 0x3FFF) + 1
    return None


def _jpeg_size(f) -> tuple[int, int] | None:
    f.seek(2)
    while True:
        marker = f.read(2)
        if len(marker) < 2 or marker[0] != 0xFF:
            return None
        if marker[1] in (0xD8, 0x01) or 0xD0 <= marker[1] <= 0xD7:
            continue
        length = struct.unpack(">H", f.read(2))[0]
        if marker[1] in (0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF):
            h, w = struct.unpack(">xHH", f.read(5))
            return w, h
        f.seek(length - 2, 1)


# Cajas casi cuadradas: las de Game Boy Advance y DS son más anchas que las de un DVD.
SQUARE_BOXES = {"gba", "gb", "gbc", "nds", "n3ds", "3ds"}


def good(kind: str, size: tuple[int, int] | None, system: str | None = None) -> bool:
    """¿Sirve esta imagen para este uso? Descarta capturas como portada y fondos chicos o verticales."""
    if not size:
        return False
    w, h = size
    if kind == "cover":
        # Las portadas son verticales (en GBA casi cuadradas) y no diminutas; una captura de PSP (480x272) no.
        return min(w, h) >= 180 and h >= w * (0.85 if system in SQUARE_BOXES else 1.1)
    if kind == "hero":
        # Horizontal. Si es chica (captura de GBA, 240×160) igual sirve: se muestra en pixel art.
        return w >= 240 and w >= h * 1.2
    if kind == "logo":
        return w >= 200
    return True


HD_HERO = 960  # por debajo, el fondo es una captura chica: se dibuja nítida (pixel art), no borrosa


def low_res(path: str | Path | None) -> bool:
    size = image_size(Path(path)) if path else None
    return bool(size and size[0] < HD_HERO)


class MediaStore:
    """Las imágenes que Orbital consiguió (o que elegiste) para cada juego."""

    def __init__(self, root: Path | None = None) -> None:
        self.root = root or default_root()

    def path(self, system: str, key: str, kind: str) -> Path | None:
        base = self.root / system / kind / key
        for ext in IMAGE_EXTS:
            candidate = base.with_name(base.name + ext)
            if candidate.exists():
                return candidate
        return None

    def target(self, system: str, key: str, kind: str, ext: str) -> Path:
        path = self.root / system / kind / f"{key}{ext}"
        path.parent.mkdir(parents=True, exist_ok=True)
        return path

    def remove(self, system: str, key: str, kind: str) -> None:
        old = self.path(system, key, kind)
        if old:
            old.unlink()

    # Ficha del juego (nombre bien escrito, descripción, año, jugadores...), junto al arte.
    def meta(self, system: str, key: str) -> dict | None:
        try:
            return json.loads((self.root / system / "meta" / f"{key}.json").read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return None

    def save_meta(self, system: str, key: str, data: dict) -> None:
        path = self.root / system / "meta" / f"{key}.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8")

    # Lo que no te gustó: no se vuelve a poner aunque una fuente lo ofrezca otra vez.
    def _rejected_file(self) -> Path:
        return self.root / "rechazadas.json"

    def rejected(self) -> dict[str, list[str]]:
        try:
            data = json.loads(self._rejected_file().read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return {}
        # Solo la forma esperada: un archivo con «[]» o «5» ya no tumba «Cambiar imagen».
        return {k: v for k, v in data.items() if isinstance(v, list)} if isinstance(data, dict) else {}

    def reject(self, system: str, key: str, kind: str, url: str) -> None:
        data = self.rejected()
        data.setdefault(f"{system}/{key}/{kind}", [])
        if url not in data[f"{system}/{key}/{kind}"]:
            data[f"{system}/{key}/{kind}"].append(url)
        self.root.mkdir(parents=True, exist_ok=True)
        self._rejected_file().write_text(json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8")

    def is_rejected(self, system: str, key: str, kind: str, url: str) -> bool:
        return url in self.rejected().get(f"{system}/{key}/{kind}", [])

    def looks_rejected(self, system: str, key: str, kind: str, path: Path | str | None) -> bool:
        """¿Se ve igual que una imagen que rechazaste? La misma imagen llega con otra dirección (Hit & Run
        está dos veces en TheGamesDB, con el mismo dibujo): por dirección no se notaba y «Cambiar
        imagen» ponía otra vez la misma."""
        seen = [v.removeprefix("look:") for v in self.rejected().get(f"{system}/{key}/{kind}", [])
                if isinstance(v, str) and v.startswith("look:")]
        mine = image_look(path) if seen and path else None
        return bool(mine) and any(similar(mine, other) for other in seen)


def image_look(path: Path | str) -> str | None:
    """Cómo se ve una imagen, en 64 bits (gris, 8×8, cada punto más claro u oscuro que el promedio):
    la misma imagen con otra calidad o tamaño da casi lo mismo. Sin Pillow o sin imagen: None."""
    try:
        from PIL import Image

        with Image.open(path) as image:
            pixels = list(image.convert("L").resize((8, 8)).tobytes())  # 64 grises, de 0 a 255
    except Exception:  # noqa: BLE001 - una imagen rota no es «parecida» a nada
        return None
    mean = sum(pixels) / len(pixels)
    return f"{sum(1 << i for i, p in enumerate(pixels) if p > mean):016x}"


def similar(a: str, b: str, bits: int = 6) -> bool:
    try:
        return bin(int(a, 16) ^ int(b, 16)).count("1") <= bits
    except ValueError:
        return False
