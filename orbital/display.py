"""Resolución al jugar: los juegos a ~1080p y lo demás (Orbital, películas) a la resolución de la pantalla.

Con la tele a 4K, la gráfica de la Legion Go compone 4 veces más píxeles en todo (el juego, Windows y cada ventana) y cada
juego de Switch le deja a DWM ~100 MB que no devuelve (ver dwm_release.py): a 1080p, una cuarta parte. Los juegos de
Switch corren a 720p o 1080p de todos modos; la tele reescala. Las películas sí aprovechan el 4K: no se tocan.

Se baja al abrir un juego y se regresa al terminar. Se elige la resolución con la misma proporción de la pantalla (la tele
16:9 → 1920×1080; la de la Legion, 16:10 → 1920×1200) y su misma frecuencia si existe. El cambio es temporal para Windows
(CDS_FULLSCREEN): si Orbital se cierra de golpe, Windows regresa solo a la de siempre.
"""

from __future__ import annotations

import ctypes
import logging
import sys
import threading
from ctypes import wintypes

log = logging.getLogger(__name__)

Mode = tuple[int, int, int]  # ancho, alto, Hz
GAME_AREA = 1920 * 1200  # lo más grande que se usa al jugar
ENUM_CURRENT_SETTINGS = -1
CDS_FULLSCREEN = 0x4
DM_PELSWIDTH, DM_PELSHEIGHT, DM_DISPLAYFREQUENCY = 0x80000, 0x100000, 0x400000
DISP_CHANGE_SUCCESSFUL = 0


class _DevMode(ctypes.Structure):
    _fields_ = [("dmDeviceName", wintypes.WCHAR * 32), ("dmSpecVersion", wintypes.WORD), ("dmDriverVersion", wintypes.WORD),
                ("dmSize", wintypes.WORD), ("dmDriverExtra", wintypes.WORD), ("dmFields", wintypes.DWORD),
                ("dmPositionX", wintypes.LONG), ("dmPositionY", wintypes.LONG), ("dmDisplayOrientation", wintypes.DWORD),
                ("dmDisplayFixedOutput", wintypes.DWORD), ("dmColor", ctypes.c_short), ("dmDuplex", ctypes.c_short),
                ("dmYResolution", ctypes.c_short), ("dmTTOption", ctypes.c_short), ("dmCollate", ctypes.c_short),
                ("dmFormName", wintypes.WCHAR * 32), ("dmLogPixels", wintypes.WORD), ("dmBitsPerPel", wintypes.DWORD),
                ("dmPelsWidth", wintypes.DWORD), ("dmPelsHeight", wintypes.DWORD), ("dmDisplayFlags", wintypes.DWORD),
                ("dmDisplayFrequency", wintypes.DWORD), ("dmICMMethod", wintypes.DWORD), ("dmICMIntent", wintypes.DWORD),
                ("dmMediaType", wintypes.DWORD), ("dmDitherType", wintypes.DWORD), ("dmReserved1", wintypes.DWORD),
                ("dmReserved2", wintypes.DWORD), ("dmPanningWidth", wintypes.DWORD), ("dmPanningHeight", wintypes.DWORD)]


def _devmode() -> _DevMode:
    mode = _DevMode()
    mode.dmSize = ctypes.sizeof(_DevMode)
    return mode


def current() -> Mode | None:
    if sys.platform != "win32":
        return None
    mode = _devmode()
    if not ctypes.windll.user32.EnumDisplaySettingsW(None, ENUM_CURRENT_SETTINGS, ctypes.byref(mode)):  # type: ignore[attr-defined]
        return None
    return mode.dmPelsWidth, mode.dmPelsHeight, mode.dmDisplayFrequency


def available() -> set[Mode]:
    if sys.platform != "win32":
        return set()
    modes, i, mode = set(), 0, _devmode()
    while ctypes.windll.user32.EnumDisplaySettingsW(None, i, ctypes.byref(mode)):  # type: ignore[attr-defined]
        modes.add((mode.dmPelsWidth, mode.dmPelsHeight, mode.dmDisplayFrequency))
        i += 1
    return modes


def game_mode_for(now: Mode, modes: set[Mode]) -> Mode | None:
    """La resolución para jugar en esta pantalla: la misma proporción, lo más grande hasta 1920×1200, y su misma
    frecuencia (si no la tiene, la más alta). None si la pantalla ya es así de chica o no hay una que sirva."""
    width, height, hz = now
    if width * height <= GAME_AREA:
        return None
    same_shape = [m for m in modes if m[0] * height == m[1] * width and m[0] * m[1] <= GAME_AREA and m[1] >= 720]
    if not same_shape:
        return None
    best = max(m[0] * m[1] for m in same_shape)
    sizes = [m for m in same_shape if m[0] * m[1] == best]
    return next((m for m in sizes if m[2] == hz), max(sizes, key=lambda m: m[2]))


def _apply(mode: Mode | None) -> bool:
    """Cambia a `mode` (temporal) o, con None, regresa a la de siempre (la guardada en Windows)."""
    user32 = ctypes.windll.user32  # type: ignore[attr-defined]
    if mode is None:
        return user32.ChangeDisplaySettingsExW(None, None, None, 0, None) == DISP_CHANGE_SUCCESSFUL
    devmode = _devmode()
    devmode.dmPelsWidth, devmode.dmPelsHeight, devmode.dmDisplayFrequency = mode
    devmode.dmFields = DM_PELSWIDTH | DM_PELSHEIGHT | DM_DISPLAYFREQUENCY
    return user32.ChangeDisplaySettingsExW(None, ctypes.byref(devmode), None, CDS_FULLSCREEN, None) == DISP_CHANGE_SUCCESSFUL


class GameResolution:
    """Baja la resolución al abrir un juego y la regresa al terminar (una sola vez cada cosa, aunque se pida dos)."""

    def __init__(self, read=current, modes=available, apply=_apply) -> None:
        self.read, self.modes, self.apply = read, modes, apply
        self.lowered: Mode | None = None  # la resolución de antes, mientras se juega más bajo
        self._lock = threading.Lock()

    def for_game(self) -> bool:
        with self._lock:
            if self.lowered is not None:
                return False
            now = self.read()
            target = game_mode_for(now, self.modes()) if now else None
            if target is None:
                return False
            if not self.apply(target):
                log.warning("No pude cambiar la resolución a %dx%d para jugar", target[0], target[1])
                return False
            self.lowered = now
        log.info("Resolución para jugar: %dx%d a %d Hz (era %dx%d)", *target, now[0], now[1])
        return True

    def restore(self) -> bool:
        with self._lock:
            if self.lowered is None:
                return False
            before, self.lowered = self.lowered, None
            ok = self.apply(None)
        log.info("Resolución de vuelta a %dx%d%s", before[0], before[1], "" if ok else " (Windows no la cambió)")
        return ok


resolution = GameResolution()
