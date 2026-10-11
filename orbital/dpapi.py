"""Cifrado de Windows atado a tu usuario (DPAPI), para guardar claves en disco.

Lo cifrado aquí solo lo puede descifrar tu usuario de Windows en este equipo: si alguien copia
secrets.json a otra PC (o lo lee otro usuario), no le sirve. Fuera de Windows no cifra (devuelve
None y quien llama guarda como antes).
"""

from __future__ import annotations

import base64
import ctypes
import sys
from ctypes import wintypes

ENTROPY = b"orbital-console"  # sal fija: otras apps con DPAPI no descifran lo de Orbital por error
CRYPTPROTECT_UI_FORBIDDEN = 0x1


class _Blob(ctypes.Structure):
    _fields_ = [("cbData", wintypes.DWORD), ("pbData", ctypes.POINTER(ctypes.c_char))]


def _blob(data: bytes) -> tuple[_Blob, ctypes.Array]:
    buffer = ctypes.create_string_buffer(data, len(data))
    return _Blob(len(data), ctypes.cast(buffer, ctypes.POINTER(ctypes.c_char))), buffer


def _call(function: str, data: bytes) -> bytes | None:
    crypt32 = ctypes.windll.crypt32  # type: ignore[attr-defined]
    kernel32 = ctypes.windll.kernel32  # type: ignore[attr-defined]
    source, _keep = _blob(data)
    entropy, _keep2 = _blob(ENTROPY)
    out = _Blob()
    args = [ctypes.byref(source), None, ctypes.byref(entropy), None, None, CRYPTPROTECT_UI_FORBIDDEN, ctypes.byref(out)]
    if function == "CryptProtectData":
        args[1] = "Orbital"
    if not getattr(crypt32, function)(*args):
        return None
    try:
        return ctypes.string_at(out.pbData, out.cbData)
    finally:
        kernel32.LocalFree(out.pbData)


def available() -> bool:
    return sys.platform == "win32"


def protect(text: str) -> str | None:
    """Texto -> base64 cifrado con tu usuario de Windows (None si no se puede)."""
    if not available():
        return None
    data = _call("CryptProtectData", text.encode("utf-8"))
    return base64.b64encode(data).decode("ascii") if data is not None else None


def unprotect(token: str) -> str | None:
    """Lo contrario de protect(); None si no es tuyo o está dañado."""
    if not available():
        return None
    try:
        raw = base64.b64decode(token, validate=True)
    except ValueError:
        return None
    data = _call("CryptUnprotectData", raw)
    return data.decode("utf-8") if data is not None else None


PREFIX = "dpapi:"


def seal(text: str) -> str:
    """Para guardar en config.yaml: "dpapi:<cifrado>" en Windows; el texto tal cual si no se puede."""
    sealed = protect(text)
    return PREFIX + sealed if sealed else text


def reveal(value: str) -> str:
    """Lo contrario de seal(): un valor "dpapi:…" descifrado; cualquier otro, tal cual."""
    if not value.startswith(PREFIX):
        return value
    plain = unprotect(value[len(PREFIX):])
    if plain is None:
        raise ValueError("No pude descifrar el token (se cifró con otro usuario de Windows o en otro equipo)")
    return plain
