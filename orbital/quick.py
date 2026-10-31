"""Panel rápido: volumen, brillo, modo de energía y batería, directo con Windows (sin PowerShell).

  * Volumen: Core Audio (IAudioEndpointVolume) del altavoz predeterminado.
  * Brillo: la pantalla integrada por IOCTL_VIDEO_*_DISPLAY_BRIGHTNESS (\\\\.\\LCD).
  * Modo de energía: el de Configuración → Energía (Mejor eficiencia / Equilibrado / Mejor
    rendimiento), con PowerSetActiveOverlayScheme. Los modos propios de Legion Space (TDP) no:
    Lenovo no publica cómo cambiarlos.
  * Batería: GetSystemPowerStatus.

Cada función devuelve None si ese control no existe en este equipo (y la interfaz lo oculta).
"""

from __future__ import annotations

import ctypes
import logging
import subprocess
import sys
import threading
import uuid
from ctypes import wintypes

log = logging.getLogger(__name__)
WIN = sys.platform == "win32"
_com_lock = threading.Lock()

# --------------------------------------------------------------------------------- volumen
CLSID_MMDeviceEnumerator = "{BCDE0395-E52F-467C-8E3D-C4579291692E}"
IID_IMMDeviceEnumerator = "{A95664D2-9614-4F35-A746-DE8DB63617E6}"
IID_IAudioEndpointVolume = "{5CDF2C82-841E-4546-9722-0CF74078229A}"


class _GUID(ctypes.Structure):
    _fields_ = [("Data1", wintypes.DWORD), ("Data2", wintypes.WORD), ("Data3", wintypes.WORD),
                ("Data4", ctypes.c_ubyte * 8)]

    @classmethod
    def of(cls, text: str) -> _GUID:
        g = cls()
        ctypes.memmove(ctypes.byref(g), uuid.UUID(text).bytes_le, 16)
        return g


def _method(obj: ctypes.c_void_p, index: int, *argtypes):
    """El método `index` de la tabla virtual de un objeto COM (HRESULT, this primero)."""
    vtable = ctypes.cast(obj, ctypes.POINTER(ctypes.POINTER(ctypes.c_void_p))).contents
    return ctypes.WINFUNCTYPE(ctypes.c_long, ctypes.c_void_p, *argtypes)(vtable[index])


def _release(obj: ctypes.c_void_p) -> None:
    if obj:
        ctypes.WINFUNCTYPE(ctypes.c_ulong, ctypes.c_void_p)(
            ctypes.cast(obj, ctypes.POINTER(ctypes.POINTER(ctypes.c_void_p))).contents[2])(obj)


def _with_endpoint(action):
    """Abre el control de volumen del altavoz predeterminado, llama `action(endpoint)` y lo suelta."""
    if not WIN:
        return None
    ole32 = ctypes.windll.ole32  # type: ignore[attr-defined]
    with _com_lock:
        ole32.CoInitializeEx(None, 0)  # cada hilo de FastAPI puede ser otro
        enumerator, device, endpoint = ctypes.c_void_p(), ctypes.c_void_p(), ctypes.c_void_p()
        try:
            if ole32.CoCreateInstance(ctypes.byref(_GUID.of(CLSID_MMDeviceEnumerator)), None, 1,  # INPROC
                                      ctypes.byref(_GUID.of(IID_IMMDeviceEnumerator)), ctypes.byref(enumerator)):
                return None
            # GetDefaultAudioEndpoint(eRender=0, eMultimedia=1)
            if _method(enumerator, 4, ctypes.c_int, ctypes.c_int, ctypes.POINTER(ctypes.c_void_p))(
                    enumerator, 0, 1, ctypes.byref(device)):
                return None
            # IMMDevice::Activate(iid, CLSCTX_ALL, NULL, &endpoint)
            if _method(device, 3, ctypes.POINTER(_GUID), wintypes.DWORD, ctypes.c_void_p,
                       ctypes.POINTER(ctypes.c_void_p))(device, ctypes.byref(_GUID.of(IID_IAudioEndpointVolume)),
                                                        23, None, ctypes.byref(endpoint)):
                return None
            return action(endpoint)
        except OSError as exc:
            log.info("Sin control de volumen: %s", exc)
            return None
        finally:
            for obj in (endpoint, device, enumerator):
                _release(obj)


def volume() -> dict | None:
    """{"level": 0-100, "muted": bool} del altavoz predeterminado."""
    def read(ep):
        level, muted = ctypes.c_float(), wintypes.BOOL()
        if _method(ep, 9, ctypes.POINTER(ctypes.c_float))(ep, ctypes.byref(level)):
            return None
        _method(ep, 15, ctypes.POINTER(wintypes.BOOL))(ep, ctypes.byref(muted))
        return {"level": round(level.value * 100), "muted": bool(muted.value)}
    return _with_endpoint(read)


def set_volume(level: int | None = None, muted: bool | None = None) -> dict | None:
    def write(ep):
        if level is not None:
            _method(ep, 7, ctypes.c_float, ctypes.c_void_p)(ep, max(0, min(100, level)) / 100, None)
        if muted is not None:
            _method(ep, 14, wintypes.BOOL, ctypes.c_void_p)(ep, bool(muted), None)
        return True
    return volume() if _with_endpoint(write) else None


# --------------------------------------------------------------------------------- brillo
IOCTL_QUERY_SUPPORTED = 0x00230494
IOCTL_QUERY = 0x00230498
IOCTL_SET = 0x0023049C


class _Brightness(ctypes.Structure):
    _fields_ = [("policy", ctypes.c_ubyte), ("ac", ctypes.c_ubyte), ("dc", ctypes.c_ubyte)]


def _lcd(code: int, inp=None, out=None) -> bool:
    kernel32 = ctypes.windll.kernel32  # type: ignore[attr-defined]
    kernel32.CreateFileW.restype = wintypes.HANDLE
    handle = kernel32.CreateFileW("\\\\.\\LCD", 0xC0000000, 3, None, 3, 0, None)  # leer/escribir
    if handle in (None, wintypes.HANDLE(-1).value):
        return False
    try:
        returned = wintypes.DWORD()
        return bool(kernel32.DeviceIoControl(
            handle, code, ctypes.byref(inp) if inp is not None else None, ctypes.sizeof(inp) if inp is not None else 0,
            ctypes.byref(out) if out is not None else None, ctypes.sizeof(out) if out is not None else 0,
            ctypes.byref(returned), None))
    finally:
        kernel32.CloseHandle(handle)


def brightness() -> int | None:
    """Brillo de la pantalla integrada (0-100), el del modo en que está (enchufada o batería)."""
    if not WIN:
        return None
    value = _Brightness()
    if not _lcd(IOCTL_QUERY, out=value):
        return None
    status = battery()
    return int(value.ac if status is None or status["plugged"] else value.dc)


def set_brightness(level: int) -> int | None:
    if not WIN:
        return None
    level = max(5, min(100, int(level)))  # 0 deja la pantalla negra: nunca
    current = _Brightness()
    if not _lcd(IOCTL_QUERY, out=current):
        return None
    status = battery()
    plugged = status is None or status["plugged"]
    # Solo el del modo actual (enchufada o batería); el otro se queda como estaba.
    new = _Brightness(1, level, current.dc) if plugged else _Brightness(2, current.ac, level)
    if _lcd(IOCTL_SET, inp=new) and brightness() == level:
        return level
    # En la Legion Go el IOCTL dice «listo» y no cambia nada (regresión S2, 2026-10-30: el brillo se quedaba en 26): el camino
    # de Windows (WMI, el mismo del deslizador de Configuración), que además guarda el nivel en el plan de energía.
    _wmi_brightness(level)
    return brightness()


def _wmi_brightness(level: int) -> bool:
    """WmiSetBrightness por PowerShell (sin ventana): ~1 s, solo cuando el IOCTL no sirvió."""
    script = ("$m = Get-CimInstance -Namespace root/wmi -ClassName WmiMonitorBrightnessMethods -ErrorAction Stop; "
              f"Invoke-CimMethod -InputObject $m -MethodName WmiSetBrightness -Arguments @{{Timeout=1; Brightness=[byte]{int(level)}}}")
    try:
        done = subprocess.run(["powershell", "-NoProfile", "-NonInteractive", "-Command", script], capture_output=True, timeout=10,
                              creationflags=subprocess.CREATE_NO_WINDOW)  # type: ignore[attr-defined]
    except (OSError, subprocess.TimeoutExpired) as exc:
        log.debug("No pude poner el brillo por WMI: %s", exc)
        return False
    return done.returncode == 0


# --------------------------------------------------------------------------------- energía
POWER_MODES = {
    "efficiency": "961cc777-2547-4f9d-8174-7d86181b8a7a",
    "balanced": "00000000-0000-0000-0000-000000000000",
    "performance": "ded574b5-45a0-4f42-8737-46345c09c238",
}


def power_mode() -> str | None:
    if not WIN:
        return None
    try:
        get = ctypes.windll.powrprof.PowerGetEffectiveOverlayScheme  # type: ignore[attr-defined]
    except AttributeError:
        return None
    guid = _GUID()
    if get(ctypes.byref(guid)) != 0:
        return None
    text = str(uuid.UUID(bytes_le=bytes(guid)))
    return next((name for name, value in POWER_MODES.items() if value == text), "balanced")


def set_power_mode(mode: str) -> str | None:
    if not WIN or mode not in POWER_MODES:
        return None
    try:
        put = ctypes.windll.powrprof.PowerSetActiveOverlayScheme  # type: ignore[attr-defined]
    except AttributeError:
        return None
    if put(ctypes.byref(_GUID.of("{" + POWER_MODES[mode] + "}"))) != 0:
        return None
    return power_mode()


# --------------------------------------------------------------------------------- batería
class _PowerStatus(ctypes.Structure):
    _fields_ = [("ACLineStatus", ctypes.c_ubyte), ("BatteryFlag", ctypes.c_ubyte),
                ("BatteryLifePercent", ctypes.c_ubyte), ("SystemStatusFlag", ctypes.c_ubyte),
                ("BatteryLifeTime", wintypes.DWORD), ("BatteryFullLifeTime", wintypes.DWORD)]


def battery() -> dict | None:
    """{"percent", "plugged", "minutes_left"} o None si no hay batería."""
    if not WIN:
        return None
    status = _PowerStatus()
    if not ctypes.windll.kernel32.GetSystemPowerStatus(ctypes.byref(status)):  # type: ignore[attr-defined]
        return None
    if status.BatteryFlag & 128 or status.BatteryLifePercent == 255:  # sin batería
        return None
    seconds = status.BatteryLifeTime
    return {"percent": status.BatteryLifePercent, "plugged": status.ACLineStatus == 1,
            "minutes_left": None if seconds in (0xFFFFFFFF, 0) else seconds // 60}


def snapshot() -> dict:
    return {"volume": volume(), "brightness": brightness(), "power_mode": power_mode(), "battery": battery()}
