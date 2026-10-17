"""Ventanas y procesos de Windows (ctypes, sin dependencias). En otros sistemas todo devuelve vacío."""

from __future__ import annotations

import ctypes
import logging
import os
import sys
import time
from ctypes import wintypes

log = logging.getLogger(__name__)

WIN = sys.platform == "win32"
if WIN:
    user32 = ctypes.windll.user32  # type: ignore[attr-defined]
    kernel32 = ctypes.windll.kernel32  # type: ignore[attr-defined]
    user32.GetForegroundWindow.restype = wintypes.HWND
    user32.GetWindowThreadProcessId.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.DWORD)]
    kernel32.OpenProcess.restype = wintypes.HANDLE
    kernel32.CreateToolhelp32Snapshot.restype = wintypes.HANDLE

SW_MINIMIZE = 6
SW_RESTORE = 9


def foreground() -> int:
    return (user32.GetForegroundWindow() or 0) if WIN else 0


def is_window(hwnd: int) -> bool:
    return bool(WIN and hwnd and user32.IsWindow(hwnd) and user32.IsWindowVisible(hwnd))


def title(hwnd: int) -> str:
    if not WIN or not hwnd:
        return ""
    length = user32.GetWindowTextLengthW(hwnd)
    buf = ctypes.create_unicode_buffer(length + 1)
    user32.GetWindowTextW(hwnd, buf, length + 1)
    return buf.value


def pid_of(hwnd: int) -> int:
    if not WIN or not hwnd:
        return 0
    pid = wintypes.DWORD()
    user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
    return pid.value


def exe_name(pid: int) -> str:
    """Nombre del ejecutable en minúsculas ("eden.exe"), o "" si no se puede leer."""
    return os.path.basename(exe_path(pid)).lower()


def exe_path(pid: int) -> str:
    """Ruta completa del ejecutable de un proceso, o "" si no se puede leer."""
    if not WIN or not pid:
        return ""
    handle = kernel32.OpenProcess(0x1000, False, pid)  # PROCESS_QUERY_LIMITED_INFORMATION
    if not handle:
        return ""
    try:
        size = wintypes.DWORD(1024)
        buf = ctypes.create_unicode_buffer(size.value)
        if kernel32.QueryFullProcessImageNameW(handle, 0, buf, ctypes.byref(size)):
            return buf.value
        return ""
    finally:
        kernel32.CloseHandle(handle)


def focus(hwnd: int) -> bool:
    """Trae una ventana al frente (restaurándola si estaba minimizada)."""
    if not is_window(hwnd):
        return False
    if user32.IsIconic(hwnd):
        user32.ShowWindow(hwnd, SW_RESTORE)
    # Windows bloquea SetForegroundWindow desde segundo plano; un Alt sintético lo permite.
    user32.keybd_event(0x12, 0, 0, 0)
    ok = bool(user32.SetForegroundWindow(hwnd))
    user32.keybd_event(0x12, 0, 2, 0)
    if not ok or user32.GetForegroundWindow() != hwnd:
        # Si aun así se niega (otra app tiene el "candado" del foco), SwitchToThisWindow es lo
        # que usa Alt+Tab y Windows lo respeta.
        user32.SwitchToThisWindow(hwnd, True)
        time.sleep(.05)
    return user32.GetForegroundWindow() == hwnd


def minimize(hwnd: int) -> None:
    if is_window(hwnd):
        user32.ShowWindow(hwnd, SW_MINIMIZE)


class _ProcessEntry(ctypes.Structure):
    _fields_ = [("dwSize", wintypes.DWORD), ("cntUsage", wintypes.DWORD), ("th32ProcessID", wintypes.DWORD),
                ("th32DefaultHeapID", ctypes.c_size_t), ("th32ModuleID", wintypes.DWORD),
                ("cntThreads", wintypes.DWORD), ("th32ParentProcessID", wintypes.DWORD),
                ("pcPriClassBase", ctypes.c_long), ("dwFlags", wintypes.DWORD), ("szExeFile", ctypes.c_wchar * 260)]


def process_tree(root: int) -> set[int]:
    """`root` y todos sus descendientes (launch-eden.cmd -> eden.exe)."""
    if not WIN or not root:
        return {root} if root else set()
    snapshot = kernel32.CreateToolhelp32Snapshot(0x2, 0)  # TH32CS_SNAPPROCESS
    if snapshot in (None, wintypes.HANDLE(-1).value):
        return {root}
    children: dict[int, list[int]] = {}
    try:
        entry = _ProcessEntry()
        entry.dwSize = ctypes.sizeof(entry)
        ok = kernel32.Process32FirstW(snapshot, ctypes.byref(entry))
        while ok:
            children.setdefault(entry.th32ParentProcessID, []).append(entry.th32ProcessID)
            ok = kernel32.Process32NextW(snapshot, ctypes.byref(entry))
    finally:
        kernel32.CloseHandle(snapshot)
    tree, pending = {root}, [root]
    while pending:
        for child in children.get(pending.pop(), []):
            if child not in tree:
                tree.add(child)
                pending.append(child)
    return tree


def command_line(pid: int) -> str:
    """La línea de comandos de un proceso ("" si no se puede leer). Sin WMI ni PowerShell:
    NtQueryInformationProcess(ProcessCommandLineInformation), Windows 8.1 o posterior."""
    if not WIN or not pid:
        return ""
    handle = kernel32.OpenProcess(0x1000, False, pid)  # PROCESS_QUERY_LIMITED_INFORMATION
    if not handle:
        return ""
    try:
        query = ctypes.windll.ntdll.NtQueryInformationProcess
        query.argtypes = [wintypes.HANDLE, ctypes.c_int, ctypes.c_void_p, wintypes.ULONG, ctypes.POINTER(wintypes.ULONG)]
        size = wintypes.ULONG(0)
        query(handle, 60, None, 0, ctypes.byref(size))  # 60 = ProcessCommandLineInformation
        if not size.value:
            return ""
        buf = ctypes.create_string_buffer(size.value)
        if query(handle, 60, buf, size, ctypes.byref(size)) != 0:
            return ""

        class _UnicodeString(ctypes.Structure):
            _fields_ = [("Length", ctypes.c_ushort), ("MaximumLength", ctypes.c_ushort), ("Buffer", ctypes.c_void_p)]

        text = _UnicodeString.from_buffer(buf)
        return ctypes.wstring_at(text.Buffer, text.Length // 2) if text.Buffer else ""
    finally:
        kernel32.CloseHandle(handle)


def processes() -> dict[int, tuple[str, int]]:
    """Todos los procesos: pid -> (ejecutable en minúsculas, pid del padre). Una sola foto."""
    if not WIN:
        return {}
    snapshot = kernel32.CreateToolhelp32Snapshot(0x2, 0)
    if snapshot in (None, wintypes.HANDLE(-1).value):
        return {}
    found: dict[int, tuple[str, int]] = {}
    try:
        entry = _ProcessEntry()
        entry.dwSize = ctypes.sizeof(entry)
        ok = kernel32.Process32FirstW(snapshot, ctypes.byref(entry))
        while ok:
            found[entry.th32ProcessID] = (entry.szExeFile.lower(), entry.th32ParentProcessID)
            ok = kernel32.Process32NextW(snapshot, ctypes.byref(entry))
    finally:
        kernel32.CloseHandle(snapshot)
    return found


def pids_by_exe(name: str) -> set[int]:
    """Procesos cuyo ejecutable se llama `name` ("stremio-shell-ng.exe")."""
    if not WIN:
        return set()
    snapshot = kernel32.CreateToolhelp32Snapshot(0x2, 0)
    if snapshot in (None, wintypes.HANDLE(-1).value):
        return set()
    found: set[int] = set()
    try:
        entry = _ProcessEntry()
        entry.dwSize = ctypes.sizeof(entry)
        ok = kernel32.Process32FirstW(snapshot, ctypes.byref(entry))
        while ok:
            if entry.szExeFile.lower() == name.lower():
                found.add(entry.th32ProcessID)
            ok = kernel32.Process32NextW(snapshot, ctypes.byref(entry))
    finally:
        kernel32.CloseHandle(snapshot)
    return found


def main_window(pids: set[int]) -> int:
    """La primera ventana visible con título que pertenezca a alguno de esos procesos."""
    if not WIN or not pids:
        return 0
    found: list[int] = []

    @ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
    def enum(hwnd, _):
        if user32.IsWindowVisible(hwnd) and user32.GetWindowTextLengthW(hwnd) and pid_of(hwnd) in pids:
            found.append(hwnd)
            return False
        return True

    user32.EnumWindows(enum, 0)
    return found[0] if found else 0


GWL_EXSTYLE = -20
WS_EX_TOOLWINDOW = 0x00000080
GW_OWNER = 4
DWMWA_CLOAKED = 14
_SHELL_TITLES = {"Program Manager", "Windows Input Experience", "Settings", "Configuración"}


def _cloaked(hwnd: int) -> bool:
    """Windows 11 deja "ocultas" (cloaked) ventanas de apps suspendidas: no cuentan como abiertas."""
    value = ctypes.c_int(0)
    try:
        ctypes.windll.dwmapi.DwmGetWindowAttribute(hwnd, DWMWA_CLOAKED, ctypes.byref(value), ctypes.sizeof(value))
    except OSError:
        return False
    return bool(value.value)


def app_windows() -> list[dict]:
    """Ventanas de aplicación abiertas, como en Alt+Tab: visibles, con título, sin dueño y no herramientas."""
    if not WIN:
        return []
    found: list[dict] = []

    @ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
    def enum(hwnd, _):
        if not user32.IsWindowVisible(hwnd) or user32.GetWindow(hwnd, GW_OWNER):
            return True
        if user32.GetWindowLongW(hwnd, GWL_EXSTYLE) & WS_EX_TOOLWINDOW:
            return True
        name = title(hwnd)
        if not name or name in _SHELL_TITLES or _cloaked(hwnd):
            return True
        found.append({"hwnd": int(hwnd), "title": name, "exe": exe_name(pid_of(hwnd))})
        return True

    user32.EnumWindows(enum, 0)
    return found


PROCESS_SUSPEND_RESUME = 0x0800


def _nt_process_call(pids: set[int], function: str) -> int:
    """Llama NtSuspendProcess/NtResumeProcess sobre cada proceso. Devuelve cuántos funcionaron."""
    if not WIN:
        return 0
    call = getattr(ctypes.windll.ntdll, function)
    done = 0
    for pid in pids:
        handle = kernel32.OpenProcess(PROCESS_SUSPEND_RESUME, False, pid)
        if not handle:
            continue
        try:
            if call(handle) == 0:  # STATUS_SUCCESS
                done += 1
        finally:
            kernel32.CloseHandle(handle)
    return done


def suspend(pids: set[int]) -> int:
    """Congela procesos (pausa universal: imagen, sonido y lógica se detienen al instante)."""
    return _nt_process_call(pids, "NtSuspendProcess")


def resume(pids: set[int]) -> int:
    return _nt_process_call(pids, "NtResumeProcess")


def windows_of(pids: set[int]) -> list[int]:
    """Ventanas visibles con título de esos procesos (un emulador tiene varias: lista y juego)."""
    if not WIN or not pids:
        return []
    found: list[int] = []

    @ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
    def enum(hwnd, _):
        if user32.IsWindowVisible(hwnd) and user32.GetWindowTextLengthW(hwnd) and pid_of(hwnd) in pids:
            found.append(hwnd)
        return True

    user32.EnumWindows(enum, 0)
    return found


def set_topmost(hwnd: int, on: bool) -> bool:
    """Siempre encima (la pantalla de carga de Orbital tapa las ventanas del emulador mientras abre)."""
    if not WIN or not hwnd:
        return False
    user32.SetWindowPos.argtypes = [wintypes.HWND, wintypes.HWND, ctypes.c_int, ctypes.c_int, ctypes.c_int,
                                    ctypes.c_int, wintypes.UINT]
    # HWND_TOPMOST (-1) / HWND_NOTOPMOST (-2); SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE
    return bool(user32.SetWindowPos(hwnd, -1 if on else -2, 0, 0, 0, 0, 0x2 | 0x1 | 0x10))


def place_below(hwnd: int, above: int) -> bool:
    """Pone `hwnd` justo debajo de `above` sin activarla. Hace falta tras quitar el "siempre encima":
    HWND_NOTOPMOST deja la ventana arriba de todas las normales (Orbital tapaba al juego que tenía el foco)."""
    if not WIN or not hwnd or not above:
        return False
    user32.SetWindowPos.argtypes = [wintypes.HWND, wintypes.HWND, ctypes.c_int, ctypes.c_int, ctypes.c_int,
                                    ctypes.c_int, wintypes.UINT]
    return bool(user32.SetWindowPos(hwnd, above, 0, 0, 0, 0, 0x2 | 0x1 | 0x10))


def window_at_center() -> int:
    """La ventana que de verdad se ve en el centro de la pantalla (no siempre es la del foco)."""
    if not WIN:
        return 0
    user32.WindowFromPoint.restype = wintypes.HWND
    user32.WindowFromPoint.argtypes = [wintypes.POINT]
    user32.GetAncestor.restype = wintypes.HWND
    user32.GetAncestor.argtypes = [wintypes.HWND, wintypes.UINT]
    point = wintypes.POINT(user32.GetSystemMetrics(0) // 2, user32.GetSystemMetrics(1) // 2)
    child = user32.WindowFromPoint(point)
    return (user32.GetAncestor(child, 2) or 0) if child else 0  # GA_ROOT


def covers_center(hwnd: int) -> bool:
    """¿La ventana ocupa el centro de la pantalla? (Si no, que ahí se vea Orbital no es que lo tape.)"""
    rect = window_rect(hwnd)
    if not rect:
        return False
    left, top, right, bottom = rect
    x, y = user32.GetSystemMetrics(0) // 2, user32.GetSystemMetrics(1) // 2
    return left <= x < right and top <= y < bottom


GWL_EXSTYLE, WS_EX_LAYERED, LWA_ALPHA = -20, 0x80000, 0x2


def set_alpha(hwnd: int, alpha: int | None) -> bool:
    """Transparencia de toda la ventana (0-255), para fundir Orbital sobre el juego en vez de cortar.
    `None` la deja como estaba (opaca, sin el estilo de capa).

    Poner y quitar el estilo de capa no es lo que hace crecer a DWM (medido 2026-10-11 en la Legion
    Go: 10 altas/bajas seguidas, +13 MB; DWM crece cientos de MB cada 5 min sin que Orbital abra nada)."""
    if not WIN or not hwnd:
        return False
    user32.GetWindowLongW.argtypes = [wintypes.HWND, ctypes.c_int]
    user32.SetWindowLongW.argtypes = [wintypes.HWND, ctypes.c_int, ctypes.c_long]
    user32.SetLayeredWindowAttributes.argtypes = [wintypes.HWND, wintypes.DWORD, ctypes.c_ubyte, wintypes.DWORD]
    style = user32.GetWindowLongW(hwnd, GWL_EXSTYLE)
    if alpha is None:
        if style & WS_EX_LAYERED:
            user32.SetLayeredWindowAttributes(hwnd, 0, 255, LWA_ALPHA)
            user32.SetWindowLongW(hwnd, GWL_EXSTYLE, style & ~WS_EX_LAYERED)
        return True
    if not style & WS_EX_LAYERED:
        user32.SetWindowLongW(hwnd, GWL_EXSTYLE, style | WS_EX_LAYERED)
    return bool(user32.SetLayeredWindowAttributes(hwnd, 0, max(0, min(255, int(alpha))), LWA_ALPHA))


def window_rect(hwnd: int) -> tuple[int, int, int, int] | None:
    """(izquierda, arriba, derecha, abajo): para saber si la ventana del juego ya dejó de cambiar de tamaño."""
    if not WIN or not hwnd:
        return None
    rect = wintypes.RECT()
    if not user32.GetWindowRect(hwnd, ctypes.byref(rect)):
        return None
    return rect.left, rect.top, rect.right, rect.bottom


def is_fullscreen(hwnd: int) -> bool:
    """¿La ventana cubre todo su monitor? (para no alternar pantalla completa por error)."""
    if not WIN or not hwnd:
        return False
    rect = wintypes.RECT()
    user32.GetWindowRect(hwnd, ctypes.byref(rect))
    monitor = user32.MonitorFromWindow(hwnd, 2)  # MONITOR_DEFAULTTONEAREST

    class MonitorInfo(ctypes.Structure):
        _fields_ = [("cbSize", wintypes.DWORD), ("rcMonitor", wintypes.RECT),
                    ("rcWork", wintypes.RECT), ("dwFlags", wintypes.DWORD)]

    info = MonitorInfo()
    info.cbSize = ctypes.sizeof(info)
    if not user32.GetMonitorInfoW(monitor, ctypes.byref(info)):
        return False
    m = info.rcMonitor
    return rect.left <= m.left and rect.top <= m.top and rect.right >= m.right and rect.bottom >= m.bottom


# --- la identidad de una ventana en la barra de tareas ------------------------------------------------------------------
# La ventana de Orbital es de Edge: sin esto, abajo salía el ícono de Edge, agrupada con tu Edge normal. Con su propio
# AppUserModelID (y el ícono y el nombre para fijarla) la barra la trata como otra aplicación: «Orbital», con su ícono.
class _Guid(ctypes.Structure):
    _fields_ = [("a", wintypes.DWORD), ("b", wintypes.WORD), ("c", wintypes.WORD), ("d", ctypes.c_ubyte * 8)]

    @classmethod
    def of(cls, text: str) -> _Guid:
        g = cls()
        ctypes.oledll.ole32.CLSIDFromString(ctypes.c_wchar_p(text), ctypes.byref(g))  # type: ignore[attr-defined]
        return g


class _PropertyKey(ctypes.Structure):
    _fields_ = [("fmtid", _Guid), ("pid", wintypes.DWORD)]


class _PropVariant(ctypes.Structure):
    _fields_ = [("vt", wintypes.USHORT), ("r1", wintypes.USHORT), ("r2", wintypes.USHORT), ("r3", wintypes.USHORT),
                ("value", ctypes.c_void_p), ("pad", ctypes.c_void_p)]


_APP_MODEL = "{9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3}"  # PKEY_AppUserModel_*: 2 relanzar, 3 ícono, 4 nombre, 5 id
VT_LPWSTR, WM_SETICON, IMAGE_ICON, LR_LOADFROMFILE = 31, 0x0080, 1, 0x0010


def set_app_identity(hwnd: int, app_id: str, icon: str, name: str, command: str) -> bool:
    """Le da a una ventana (de otro proceso, como el kiosko de Edge) su propia identidad en la barra de tareas: id de
    aplicación, ícono, nombre y cómo volver a abrirla si la fijas. Además le pone el ícono a la ventana (Alt+Tab)."""
    if not WIN or not hwnd:
        return False
    try:
        store = ctypes.c_void_p()
        shell32 = ctypes.windll.shell32  # type: ignore[attr-defined]
        iid = _Guid.of("{886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99}")  # IPropertyStore
        if shell32.SHGetPropertyStoreForWindow(wintypes.HWND(hwnd), ctypes.byref(iid), ctypes.byref(store)) != 0:
            return False
        vtable = ctypes.cast(ctypes.cast(store, ctypes.POINTER(ctypes.c_void_p))[0], ctypes.POINTER(ctypes.c_void_p))
        set_value = ctypes.WINFUNCTYPE(ctypes.HRESULT, ctypes.c_void_p, ctypes.POINTER(_PropertyKey),
                                       ctypes.POINTER(_PropVariant))(vtable[6])
        commit = ctypes.WINFUNCTYPE(ctypes.HRESULT, ctypes.c_void_p)(vtable[7])
        release = ctypes.WINFUNCTYPE(wintypes.ULONG, ctypes.c_void_p)(vtable[2])
        texts = []  # vivos hasta el Commit
        try:
            # El id va al final: con él cambia el grupo, y para entonces el ícono y el nombre ya están puestos.
            for pid, value in ((2, command), (3, icon), (4, name), (5, app_id)):
                texts.append(ctypes.create_unicode_buffer(value))
                variant = _PropVariant(vt=VT_LPWSTR, value=ctypes.cast(texts[-1], ctypes.c_void_p))
                set_value(store, ctypes.byref(_PropertyKey(_Guid.of(_APP_MODEL), pid)), ctypes.byref(variant))
            commit(store)
        finally:
            release(store)
        user32.LoadImageW.restype = wintypes.HANDLE
        for which, size in ((1, 256), (0, 32)):  # ICON_BIG, ICON_SMALL
            handle = user32.LoadImageW(None, icon, IMAGE_ICON, size, size, LR_LOADFROMFILE)
            if handle:
                user32.SendMessageW(wintypes.HWND(hwnd), WM_SETICON, which, handle)
        return True
    except OSError as exc:
        log.debug("No pude darle identidad a la ventana %s: %s", hwnd, exc)
        return False
