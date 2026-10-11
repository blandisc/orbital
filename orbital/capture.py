"""Capturas de pantalla (Home + RB) y la galería de Orbital.

Primero se le pide a la Xbox Game Bar de Windows (Win + Alt + Impr Pant): captura bien los juegos
a pantalla completa y guarda en Vídeos\\Capturas. Si en 3 s no aparece el archivo (Game Bar
desactivada), Orbital captura la pantalla él mismo (GDI) en Imágenes\\Orbital.

Grabar clips no: depende de la "grabación en segundo plano" de Game Bar, un ajuste de Windows que
no se cambia sin preguntarte. Si la activas, Win + Alt + G guarda los últimos 30 s y la galería los
muestra igual.
"""

from __future__ import annotations

import ctypes
import logging
import struct
import sys
import time
import zlib
from ctypes import wintypes
from pathlib import Path

log = logging.getLogger(__name__)

IMAGE_EXT = {".png", ".jpg", ".jpeg"}
VIDEO_EXT = {".mp4", ".mkv"}
VK_LWIN, VK_MENU, VK_SNAPSHOT = 0x5B, 0x12, 0x2C


def _known_folder(guid: str) -> Path | None:
    if sys.platform != "win32":
        return None
    import uuid

    from .quick import _GUID

    path = ctypes.c_wchar_p()
    if ctypes.windll.shell32.SHGetKnownFolderPath(ctypes.byref(_GUID.of(guid)), 0, None, ctypes.byref(path)):  # type: ignore[attr-defined]
        return None
    try:
        return Path(path.value)
    finally:
        ctypes.windll.ole32.CoTaskMemFree(path)  # type: ignore[attr-defined]
        del uuid


def folders() -> list[Path]:
    """Dónde hay capturas: las de Game Bar (Vídeos\\Capturas) y las de Orbital (Imágenes\\Orbital)."""
    videos = _known_folder("{18989B1D-99B5-455B-841C-AB7C74E4DDFC}") or Path.home() / "Videos"
    pictures = _known_folder("{33E28130-4E1E-4676-835A-98395C3BC3BB}") or Path.home() / "Pictures"
    return [videos / "Captures", pictures / "Orbital"]


def gallery(limit: int = 60) -> list[dict]:
    """Las capturas y clips más recientes primero."""
    found = []
    for folder in folders():
        try:
            found += [p for p in folder.iterdir() if p.suffix.lower() in IMAGE_EXT | VIDEO_EXT]
        except OSError:
            continue
    found.sort(key=lambda p: p.stat().st_mtime, reverse=True)
    return [{"name": p.stem, "path": str(p), "kind": "video" if p.suffix.lower() in VIDEO_EXT else "image",
             "time": p.stat().st_mtime} for p in found[:limit]]


def _newest(after: float) -> Path | None:
    items = [g for g in gallery(5) if g["time"] >= after]
    return Path(items[0]["path"]) if items else None


def _game_bar_screenshot() -> Path | None:
    user32 = ctypes.windll.user32  # type: ignore[attr-defined]
    started = time.time() - 1
    for vk in (VK_LWIN, VK_MENU, VK_SNAPSHOT):
        user32.keybd_event(vk, 0, 0, 0)
    for vk in (VK_SNAPSHOT, VK_MENU, VK_LWIN):
        user32.keybd_event(vk, 0, 2, 0)
    deadline = time.time() + 3
    while time.time() < deadline:
        time.sleep(.25)
        found = _newest(started)
        if found:
            return found
    return None


def png(width: int, height: int, bgra: bytes) -> bytes:
    """Imagen BGRA (de arriba a abajo) -> PNG, sin librerías."""
    rgba = bytearray(bgra)
    rgba[0::4], rgba[2::4] = bgra[2::4], bgra[0::4]
    rgba[3::4] = bytes([255]) * (len(rgba) // 4)  # GDI deja el alfa en 0
    stride = width * 4
    raw = b"".join(b"\x00" + bytes(rgba[y * stride:(y + 1) * stride]) for y in range(height))

    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b""))


class _BitmapInfo(ctypes.Structure):
    _fields_ = [("biSize", wintypes.DWORD), ("biWidth", wintypes.LONG), ("biHeight", wintypes.LONG),
                ("biPlanes", wintypes.WORD), ("biBitCount", wintypes.WORD), ("biCompression", wintypes.DWORD),
                ("biSizeImage", wintypes.DWORD), ("biXPelsPerMeter", wintypes.LONG),
                ("biYPelsPerMeter", wintypes.LONG), ("biClrUsed", wintypes.DWORD), ("biClrImportant", wintypes.DWORD)]


def _gdi_screenshot(folder: Path, name: str) -> Path | None:
    user32, gdi32 = ctypes.windll.user32, ctypes.windll.gdi32  # type: ignore[attr-defined]
    user32.SetProcessDPIAware()
    width, height = user32.GetSystemMetrics(0), user32.GetSystemMetrics(1)
    for fn in (user32.GetDC, gdi32.CreateCompatibleDC, gdi32.CreateCompatibleBitmap, gdi32.SelectObject):
        fn.restype = wintypes.HANDLE
    screen = user32.GetDC(None)
    memory = gdi32.CreateCompatibleDC(wintypes.HANDLE(screen))
    bitmap = gdi32.CreateCompatibleBitmap(wintypes.HANDLE(screen), width, height)
    try:
        gdi32.SelectObject(wintypes.HANDLE(memory), wintypes.HANDLE(bitmap))
        gdi32.BitBlt(wintypes.HANDLE(memory), 0, 0, width, height, wintypes.HANDLE(screen), 0, 0, 0x00CC0020)  # SRCCOPY
        info = _BitmapInfo(ctypes.sizeof(_BitmapInfo), width, -height, 1, 32, 0, 0, 0, 0, 0, 0)  # de arriba a abajo
        buffer = ctypes.create_string_buffer(width * height * 4)
        if not gdi32.GetDIBits(wintypes.HANDLE(memory), wintypes.HANDLE(bitmap), 0, height, buffer,
                               ctypes.byref(info), 0):
            return None
        folder.mkdir(parents=True, exist_ok=True)
        path = folder / f"{name}.png"
        path.write_bytes(png(width, height, buffer.raw))
        return path
    finally:
        gdi32.DeleteObject(wintypes.HANDLE(bitmap))
        gdi32.DeleteDC(wintypes.HANDLE(memory))
        user32.ReleaseDC(None, wintypes.HANDLE(screen))


def take(title: str = "") -> Path | None:
    if sys.platform != "win32":
        return None
    try:
        found = _game_bar_screenshot()
        if found:
            return found
        log.info("Game Bar no guardó la captura: la hago yo")
        safe = "".join(c for c in title if c.isalnum() or c in " -_").strip() or "Orbital"
        return _gdi_screenshot(folders()[1], f"{safe} {time.strftime('%Y-%m-%d %H.%M.%S')}")
    except OSError as exc:
        log.warning("No pude capturar la pantalla: %s", exc)
        return None


def take_and_describe(title: str = "") -> dict:
    """La captura, como aviso para la interfaz."""
    path = take(title)
    if path is None:
        return {"type": "toast", "ok": False, "message": "No pude hacer la captura"}
    return {"type": "toast", "message": f"Captura guardada en {path.parent.name}", "capture": path.name}
