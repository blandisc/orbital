"""Accesos directos de Windows (.lnk) y paquetes de Xbox 360, sin depender de PowerShell.

  * .lnk: ES-DE y la gente guardan accesos directos en las carpetas de ROMs ("Call of Duty.lnk" que
    abre Xenia con el juego). Se lee el destino y los argumentos del formato binario de Windows
    (MS-SHLLINK) para lanzar el mismo juego con el emulador de Orbital.
  * Xbox 360: los juegos instalados en Xenia (Games on Demand / Arcade) viven en
    content/<perfil>/<TitleID>/00007000|000D0000/<paquete>; su cabecera (LIVE/PIRS/CON) trae el nombre.
"""

from __future__ import annotations

import re
import sys
from dataclasses import dataclass
from pathlib import Path

HAS_ID_LIST, HAS_LINK_INFO, IS_UNICODE = 0x1, 0x2, 0x80
STRING_FLAGS = (0x4, 0x8, 0x10, 0x20, 0x40)  # nombre, ruta relativa, carpeta de trabajo, argumentos, icono


@dataclass
class Shortcut:
    target: str
    arguments: str = ""
    working_dir: str = ""

    def argv(self) -> list[str]:
        """Los argumentos como lista, sin las comillas (como los recibe el programa)."""
        return [a.strip('"') for a in re.findall(r'"[^"]*"|\S+', self.arguments)]


def _ansi(data: bytes) -> str:
    return data.decode("mbcs" if sys.platform == "win32" else "latin-1", "replace")


def read_lnk(path: Path) -> Shortcut | None:
    """Destino y argumentos de un .lnk (None si no es un acceso directo válido)."""
    try:
        b = path.read_bytes()
    except OSError:
        return None
    if len(b) < 0x4C or b[:4] != b"\x4c\x00\x00\x00":
        return None
    u16 = lambda o: int.from_bytes(b[o:o + 2], "little")  # noqa: E731
    u32 = lambda o: int.from_bytes(b[o:o + 4], "little")  # noqa: E731
    flags = u32(0x14)
    pos = 0x4C
    if flags & HAS_ID_LIST:
        pos += 2 + u16(pos)
    target = ""
    if flags & HAS_LINK_INFO:
        start, size = pos, u32(pos)
        header, info_flags = u32(start + 4), u32(start + 8)
        if info_flags & 1:  # VolumeIDAndLocalBasePath
            base = start + u32(start + 16)
            suffix = start + u32(start + 24)
            if header >= 0x24 and u32(start + 28):  # versión Unicode de la ruta
                base_u = start + u32(start + 28)
                end = base_u
                while end + 1 < len(b) and b[end:end + 2] != b"\x00\x00":
                    end += 2
                target = b[base_u:end].decode("utf-16-le", "replace")
            else:
                target = _ansi(b[base:b.index(b"\x00", base)])
            tail = _ansi(b[suffix:b.index(b"\x00", suffix)]) if suffix < len(b) else ""
            target += tail
        pos += size
    strings: dict[int, str] = {}
    for bit in STRING_FLAGS:
        if not flags & bit:
            continue
        count = u16(pos)
        pos += 2
        width = 2 if flags & IS_UNICODE else 1
        raw = b[pos:pos + count * width]
        pos += count * width
        strings[bit] = raw.decode("utf-16-le", "replace") if width == 2 else _ansi(raw)
    if not target and strings.get(0x8):  # sin ruta absoluta: la relativa, desde el .lnk
        target = str((path.parent / strings[0x8]).resolve())
    if not target:
        return None
    return Shortcut(target, strings.get(0x20, ""), strings.get(0x10, ""))


# ----------------------------------------------------------------------------- Xbox 360
PACKAGE_MAGIC = (b"LIVE", b"PIRS", b"CON ")
PACKAGE_TYPES = ("00007000", "000D0000")  # Games on Demand, Xbox Live Arcade
NAME_OFFSET, NAME_SIZE = 0x411, 0x80


def package_name(path: Path) -> str | None:
    """Nombre del juego guardado en la cabecera STFS del paquete (UTF-16 big endian)."""
    try:
        with path.open("rb") as fh:
            head = fh.read(NAME_OFFSET + NAME_SIZE)
    except OSError:
        return None
    if head[:4] not in PACKAGE_MAGIC or len(head) < NAME_OFFSET + NAME_SIZE:
        return None
    name = head[NAME_OFFSET:NAME_OFFSET + NAME_SIZE].decode("utf-16-be", "replace").split("\x00")[0].strip()
    return name or None


def xenia_games(content: Path) -> list[tuple[Path, str]]:
    """Juegos instalados en Xenia: [(paquete, nombre)]."""
    found = []
    if not content.is_dir():
        return found
    for kind in PACKAGE_TYPES:
        for package in content.glob(f"*/*/{kind}/*"):
            if package.is_file() and not package.suffix:
                name = package_name(package)
                if name:
                    found.append((package, name))
    return found
