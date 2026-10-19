"""Cosas del proceso de Orbital: su registro, que solo haya uno abierto y en qué carpetas vive.

  * RotatingStream: con pythonw (acceso directo) no hay consola; todo va a orbital.log, que se
    rota al pasar de MAX_LOG_BYTES (antes crecía días enteros sin límite).
  * single_instance(): un candado de Windows (mutex con nombre). El segundo Orbital lo nota al
    instante, aunque el primero aún esté cerrando y su puerto no responda.
  * packaged_app(): si Orbital corre dentro de una app empaquetada (MSIX, p. ej. la app de Claude),
    Windows virtualiza AppData y Orbital vería OTRA config que la del acceso directo. Se avisa.
"""

from __future__ import annotations

import ctypes
import logging
import os
import sys
import threading
from pathlib import Path

log = logging.getLogger(__name__)

MAX_LOG_BYTES = 5_000_000
LOG_BACKUPS = 3
MUTEX_NAME = "Local\\OrbitalConsole"
ERROR_ALREADY_EXISTS = 183
APPMODEL_ERROR_NO_PACKAGE = 15700


class RotatingStream:
    """Archivo de texto para sys.stdout/stderr que se rota solo (orbital.log -> .1 -> .2 -> .3)."""

    def __init__(self, path: Path, max_bytes: int = MAX_LOG_BYTES, backups: int = LOG_BACKUPS) -> None:
        self.path = path
        self.max_bytes = max_bytes
        self.backups = backups
        self._lock = threading.Lock()
        path.parent.mkdir(parents=True, exist_ok=True)
        # Cada arranque empieza en un archivo nuevo (el anterior queda como .1). Si otro Orbital lo tiene abierto (el clic
        # en el ícono con Orbital ya abierta), Windows no deja moverlo: se escribe al final del mismo. Antes ese error
        # mataba al clic sin decir nada (pythonw no tiene consola): «le doy clic y no inicia».
        rotated = self._rotate()
        self._file = self._open("w" if rotated else "a")

    def _open(self, mode: str):
        try:
            return open(self.path, mode, encoding="utf-8", buffering=1)  # noqa: SIM115 - vive todo el proceso
        except OSError:
            return open(os.devnull, "w", encoding="utf-8")  # noqa: SIM115 - sin registro, pero Orbital abre igual

    def _rotate(self) -> bool:
        """True si quedó rotado; False si un archivo estaba en uso (se sigue escribiendo en el actual)."""
        try:
            for i in range(self.backups - 1, 0, -1):
                older = self.path.with_suffix(f".log.{i}")
                if older.exists():
                    older.replace(self.path.with_suffix(f".log.{i + 1}"))
            if self.path.exists():
                self.path.replace(self.path.with_suffix(".log.1"))
            return True
        except OSError:
            return False

    def write(self, text: str) -> int:
        with self._lock:
            written = self._file.write(text)
            if self._file.tell() > self.max_bytes:
                self._file.close()
                self._file = self._open("w" if self._rotate() else "a")
            return written

    def flush(self) -> None:
        with self._lock:
            self._file.flush()

    def isatty(self) -> bool:
        return False

    def close(self) -> None:
        with self._lock:
            self._file.close()

    @property
    def encoding(self) -> str:
        return "utf-8"


_mutex = None  # vive mientras viva el proceso


def single_instance(name: str = MUTEX_NAME, wait: float = 0) -> bool:
    """True si somos el único Orbital (y desde ahora el candado es nuestro). Con `wait`, espera a que
    el anterior termine de cerrar (cerrar Orbital y abrirlo de inmediato). Fuera de Windows, True."""
    global _mutex
    if sys.platform != "win32":
        return True
    kernel32 = ctypes.windll.kernel32  # type: ignore[attr-defined]
    kernel32.CreateMutexW.restype = ctypes.c_void_p
    handle = kernel32.CreateMutexW(None, True, name)  # True: es nuestro mientras vivamos
    if not handle:
        return True  # no se pudo crear: mejor arrancar que quedarse sin consola
    if kernel32.GetLastError() == ERROR_ALREADY_EXISTS:
        # WAIT_OBJECT_0 (0) o WAIT_ABANDONED (0x80): el otro terminó y ahora el candado es nuestro.
        if kernel32.WaitForSingleObject(ctypes.c_void_p(handle), int(wait * 1000)) not in (0, 0x80):
            kernel32.CloseHandle(ctypes.c_void_p(handle))
            return False
    _mutex = handle
    return True


def packaged_app() -> str | None:
    """Nombre del paquete MSIX si Orbital corre dentro de uno (AppData virtualizado); None si no."""
    if sys.platform != "win32":
        return None
    length = ctypes.c_uint(0)
    kernel32 = ctypes.windll.kernel32  # type: ignore[attr-defined]
    if kernel32.GetCurrentPackageFullName(ctypes.byref(length), None) == APPMODEL_ERROR_NO_PACKAGE:
        return None
    buffer = ctypes.create_unicode_buffer(length.value or 256)
    if kernel32.GetCurrentPackageFullName(ctypes.byref(length), buffer) != 0:
        return "desconocido"
    return buffer.value


def virtualized_appdata(folder: Path | None = None) -> str | None:
    """Si Windows redirige lo que Orbital escribe en AppData (corre dentro de una app empaquetada,
    como la de Claude), devuelve a dónde va de verdad; None si escribe donde dice. Se escribe un
    archivo de prueba y se le pregunta a Windows su ruta final."""
    if sys.platform != "win32":
        return None
    from ctypes import wintypes

    # Un archivo NUEVO en la raíz de AppData es lo que Windows redirige (en una carpeta que ya
    # existe de verdad, como la de Orbital, no siempre): ahí se prueba y luego se borra.
    folder = folder or Path(os.environ.get("APPDATA", ""))
    probe = folder / ".orbital-donde"
    try:
        folder.mkdir(parents=True, exist_ok=True)
        probe.write_text("Orbital comprueba aquí si Windows redirige AppData.", encoding="utf-8")
        kernel32 = ctypes.windll.kernel32  # type: ignore[attr-defined]
        kernel32.CreateFileW.restype = wintypes.HANDLE
        handle = kernel32.CreateFileW(str(probe), 0x80, 7, None, 3, 0x02000000, None)  # leer atributos
        if handle in (None, wintypes.HANDLE(-1).value):
            return None
        buffer = ctypes.create_unicode_buffer(1024)
        kernel32.GetFinalPathNameByHandleW(handle, buffer, 1024, 0)
        kernel32.CloseHandle(handle)
    except OSError:
        return None
    finally:
        probe.unlink(missing_ok=True)
    real = buffer.value.removeprefix("\\\\?\\")
    return str(Path(real).parent) if "\\Packages\\" in real and "\\LocalCache\\" in real else None


def log_paths(config_path: Path | None, log_path: Path | None) -> None:
    """Al arrancar: qué carpetas usa Orbital (lo primero que hay que mirar si algo "desaparece")."""
    from .player import find_mpv

    log.info("Carpetas: config=%s · datos=%s · registro=%s · mpv=%s", config_path,
             Path(os.environ.get("LOCALAPPDATA", "")) / "orbital", log_path, find_mpv())
    redirected = virtualized_appdata()
    if redirected or packaged_app():
        log.warning("Windows redirige lo que Orbital guarda en AppData (a %s): corre dentro de otra app "
                    "y vería otra configuración. Ábrelo con su acceso directo.", redirected or "un paquete")
