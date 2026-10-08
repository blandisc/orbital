"""Integración con el sistema operativo: traer Orbital al frente y estado del Wi-Fi."""

from __future__ import annotations

import logging
import re
import subprocess
import sys
import time

log = logging.getLogger(__name__)

WINDOW_TITLE = "Orbital"


def bring_to_front(title: str = WINDOW_TITLE) -> bool:
    """Pone en primer plano la ventana cuyo título contiene `title` (solo Windows)."""
    if sys.platform != "win32":
        return False
    try:
        import ctypes
        from ctypes import wintypes

        user32 = ctypes.windll.user32  # type: ignore[attr-defined]
        found: list[int] = []

        @ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
        def enum(hwnd, _):
            if user32.IsWindowVisible(hwnd):
                length = user32.GetWindowTextLengthW(hwnd)
                buf = ctypes.create_unicode_buffer(length + 1)
                user32.GetWindowTextW(hwnd, buf, length + 1)
                if title in buf.value:
                    found.append(hwnd)
                    return False
            return True

        user32.EnumWindows(enum, 0)
        if not found:
            return False
        hwnd = found[0]
        if user32.IsIconic(hwnd):
            user32.ShowWindow(hwnd, 9)  # SW_RESTORE
        # Windows bloquea SetForegroundWindow desde procesos en segundo plano; pulsar Alt
        # de forma sintética es el truco habitual para que lo permita.
        user32.keybd_event(0x12, 0, 0, 0)
        user32.SetForegroundWindow(hwnd)
        user32.keybd_event(0x12, 0, 2, 0)
        return True
    except Exception:  # noqa: BLE001 - es una ayuda; nunca debe romper nada
        log.exception("No se pudo traer Orbital al frente")
        return False


_SIGNAL = re.compile(r"^\s*\S+\s*:\s*(\d{1,3})\s*%\s*$", re.MULTILINE)
_SSID = re.compile(r"^\s*SSID\s*:\s*(.+?)\s*$", re.MULTILINE)


def parse_netsh(output: str) -> dict | None:
    """Interpreta `netsh wlan show interfaces` en cualquier idioma: la única línea que
    termina en porcentaje es la de la señal."""
    signal = _SIGNAL.search(output)
    if not signal:
        return None
    ssid = _SSID.search(output)
    return {"signal": int(signal.group(1)), "ssid": ssid.group(1) if ssid else None}


_wifi_cache: tuple[float, dict | None] = (0.0, None)


def wifi() -> dict | None:
    global _wifi_cache
    if sys.platform != "win32":
        return None
    if time.time() - _wifi_cache[0] < 20:
        return _wifi_cache[1]
    try:
        out = subprocess.run(
            ["netsh", "wlan", "show", "interfaces"], capture_output=True, text=True,
            errors="replace", timeout=3, creationflags=subprocess.CREATE_NO_WINDOW,  # type: ignore[attr-defined]
        ).stdout
        result = parse_netsh(out)
    except (OSError, subprocess.TimeoutExpired):
        result = None
    _wifi_cache = (time.time(), result)
    return result
