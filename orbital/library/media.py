"""Arte propio de Orbital: portada, fondo horizontal y logotipo de cada juego, sin depender de ES-DE.

Vive en %LOCALAPPDATA%\\orbital\\media\\<sistema>\\<tipo>\\<juego>.<ext>, con el mismo nombre que la
ROM (sin extensión). El escaneo prefiere este arte y solo cae al de ES-DE si aquí no hay nada; el
de ES-DE, además, se descarta si no sirve (una captura puesta como portada, por ejemplo).
"""

from __future__ import annotations

import json
import os
import struct
from pathlib import Path

IMAGE_EXTS = (".png", ".jpg", ".jpeg", ".webp")
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
    except OSError:
        return None
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
        return w >= 960 and w >= h * 1.4
    if kind == "logo":
        return w >= 200
    return True


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
            return json.loads(self._rejected_file().read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return {}

    def reject(self, system: str, key: str, kind: str, url: str) -> None:
        data = self.rejected()
        data.setdefault(f"{system}/{key}/{kind}", [])
        if url not in data[f"{system}/{key}/{kind}"]:
            data[f"{system}/{key}/{kind}"].append(url)
        self.root.mkdir(parents=True, exist_ok=True)
        self._rejected_file().write_text(json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8")

    def is_rejected(self, system: str, key: str, kind: str, url: str) -> bool:
        return url in self.rejected().get(f"{system}/{key}/{kind}", [])
