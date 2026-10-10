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
    if not WIN or not pid:
        return ""
    handle = kernel32.OpenProcess(0x1000, False, pid)  # PROCESS_QUERY_LIMITED_INFORMATION
    if not handle:
        return ""
    try:
        size = wintypes.DWORD(1024)
        buf = ctypes.create_unicode_buffer(size.value)
        if kernel32.QueryFullProcessImageNameW(handle, 0, buf, ctypes.byref(size)):
            return os.path.basename(buf.value).lower()
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
