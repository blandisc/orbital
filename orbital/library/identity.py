"""Identidad estable de un juego de emulador: el emulador elegido sobrevive a un cambio de nombre o de carpeta.

La ficha del juego sigue yendo por la ruta del archivo (`emu:switch:1f858275c03d`: historial, favoritos, arte).
El emulador se guarda además bajo una clave que no depende de esa ruta:

  * Switch con title ID en el nombre (`[01007EF00011E000]`): `emu:switch:tid:` + el de la base
    (mayúsculas; la actualización `…800` y el DLC `…001`–`…7FF` apuntan al juego `…000`).
  * Si no hay title ID: el título normalizado + el sistema (`emu:switch:title:mario kart 8 deluxe`).
    Barato, sin leer el archivo; un traslado o un rename que deja el nombre del juego lo sigue encontrando.
  * Huella corta del archivo (tamaño + los primeros 64 KiB): `emu:switch:fp:a1b2c3d4e5f6`.
    Sobrevive a un rename arbitrario. No se hashea el archivo entero (los NSP/XCI pesan varios GB).
    Los archivos vacíos no llevan huella (no son un juego real; en las pruebas chocaría).

Al leer se prueba en ese orden y al final la clave vieja por ruta, por si la migración aún no corrió.
"""

from __future__ import annotations

import hashlib
import re
from pathlib import Path

from ..text import normalize
from .models import LibraryItem

# [01007EF00011E000] o (01007EF00011E000): lo habitual en NSP/XCI de escena.
_SWITCH_TID_BRACKET = re.compile(r"[\[(]([0-9A-Fa-f]{16})[\])]")
# Por si va suelto en el nombre: Mario Party Superstars01006FE013472000.nsp (raro) o _0100…_.
_SWITCH_TID_TOKEN = re.compile(r"(?<![0-9A-Fa-f])(0100[0-9A-Fa-f]{12})(?![0-9A-Fa-f])")
_TAGS = re.compile(r"\s*[\(\[][^\)\]]*[\)\]]")

HEAD = 64 * 1024  # de un multi-GB basta la cabecera para distinguirlo; no se lee el resto


def switch_title_id(name: str) -> str | None:
    """Title ID de Switch en un nombre de archivo; None si no hay. Ya en mayúsculas y de la base."""
    if not name:
        return None
    found = _SWITCH_TID_BRACKET.search(name) or _SWITCH_TID_TOKEN.search(name)
    return base_title_id(found.group(1)) if found else None


def base_title_id(tid: str) -> str:
    """El title ID del juego: actualización (…800) y DLC (…001–…7FF) vuelven a la base …000."""
    tid = tid.upper()
    if len(tid) != 16:
        return tid
    try:
        suffix = int(tid[-3:], 16)
    except ValueError:
        return tid
    if suffix == 0x800 or 0x001 <= suffix <= 0x7FF:
        return f"{tid[:-3]}000"
    return tid


def file_fingerprint(path: Path, nbytes: int = HEAD) -> str | None:
    """Huella corta (tamaño + cabecera). None si no se puede leer o el archivo está vacío."""
    try:
        size = path.stat().st_size
        if size <= 0:
            return None
        with open(path, "rb") as fh:
            chunk = fh.read(nbytes)
    except OSError:
        return None
    return hashlib.sha1(f"{size}:".encode() + chunk).hexdigest()[:12]


def fingerprint_extra(path: Path) -> dict:
    fp = file_fingerprint(path)
    return {"fp": fp} if fp else {}


def _stem_slug(media_key: str) -> str:
    """El nombre del archivo (sin carpetas ni etiquetas [USA]/[0100…]) listo para comparar."""
    name = Path(str(media_key).replace("\\", "/")).name.replace("_", " ")
    name = _TAGS.sub("", name).strip()
    name = re.sub(r"\s{2,}", " ", name)
    return normalize(name)


def runner_keys(item: LibraryItem) -> list[str]:
    """Claves donde puede estar el emulador elegido, de la más estable a la de la ruta actual."""
    keys: list[str] = []
    system = item.system
    extra = item.extra or {}
    if system == "switch":
        tid = switch_title_id(item.media_key or "") or switch_title_id(item.title or "")
        if tid:
            keys.append(f"emu:switch:tid:{tid}")
    if system:
        fp = extra.get("fp")
        if isinstance(fp, str) and fp:
            keys.append(f"emu:{system}:fp:{fp}")
        slugs: list[str] = []
        if item.title:
            slugs.append(normalize(item.title))
        if item.media_key:
            slugs.append(_stem_slug(item.media_key))
        for slug in dict.fromkeys(s for s in slugs if s):
            keys.append(f"emu:{system}:title:{slug}")
    if item.id not in keys:
        keys.append(item.id)
    return keys
