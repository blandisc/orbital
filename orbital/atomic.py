"""Guardar un archivo sin que un apagón lo deje a medias.

`atomic_write` escribe primero a un temporal único junto al archivo, lo empuja al disco (`flush` + `os.fsync`) y solo
entonces lo pone en su lugar con `os.replace`, que en Windows y en Unix cambia uno por otro de un jalón: quien lee
ve el archivo viejo completo o el nuevo completo, nunca la mitad. Con `backup=True` el archivo anterior queda
como `<nombre>.bak` antes del cambio, y `backup_path` dice dónde buscarlo si el principal resulta dañado.
"""

from __future__ import annotations

import contextlib
import logging
import os
import shutil
import tempfile
import threading
import time
from pathlib import Path

log = logging.getLogger(__name__)


def tmp_path(path: Path) -> Path:
    """El nombre de temporal de antes (fijo). Ya no se usa al escribir (cada escritura tiene el suyo, ver `_temp`); se
    queda para limpiar uno viejo que hubiera quedado tirado."""
    return path.with_name(path.name + ".tmp")


def backup_path(path: Path) -> Path:
    return path.with_name(path.name + ".bak")


# Dos hilos que guardan el mismo archivo (la caché de «Para ti» y su temporizador, los tonos del arte) se turnan: así el
# que guarda después queda al final, sin pisarse a la mitad. Un número fijo de candados (por el nombre): no crece.
_LOCKS = [threading.Lock() for _ in range(64)]
REPLACE_TRIES = 10  # Windows: un lector con el archivo abierto impide cambiarlo un instante («Acceso denegado»)
REPLACE_WAIT = 0.02  # s entre intentos (en total, a lo más ~1 s)
WINDOWS = os.name == "nt"


def _lock_for(path: Path) -> threading.Lock:
    return _LOCKS[hash(os.path.normcase(os.path.abspath(path))) % len(_LOCKS)]


def _temp(path: Path) -> tuple[int, Path]:
    """Un temporal ÚNICO junto al archivo (misma carpeta, mismo disco: `os.replace` es de un jalón). Con un nombre fijo,
    dos escrituras a la vez se borraban o se mezclaban el temporal (165 FileNotFoundError en 600 escrituras)."""
    fd, name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=path.parent)
    return fd, Path(name)


def _replace(src: Path, dst: Path) -> None:
    """`os.replace` con un reintento breve en Windows si alguien tiene el archivo abierto en ese instante."""
    for attempt in range(REPLACE_TRIES):
        try:
            os.replace(src, dst)
            return
        except PermissionError:
            if not WINDOWS or attempt == REPLACE_TRIES - 1:
                raise
            time.sleep(REPLACE_WAIT * (attempt + 1))


def _permissions(tmp: Path, path: Path, mode: int | None) -> None:
    """`mkstemp` crea el temporal solo para su dueño (0600): se le ponen los permisos pedidos o los del archivo de antes
    (o los de siempre, 0644), para que guardar no cambie quién puede leerlo. En Windows no aplica."""
    if os.name == "nt":
        return
    if mode is None:
        try:
            mode = path.stat().st_mode & 0o777
        except OSError:
            mode = 0o644
    tmp.chmod(mode)


def atomic_write(path: Path, data: str | bytes, *, encoding: str = "utf-8", errors: str = "strict",
                 backup: bool = False, mode: int | None = None, durable: bool = True) -> None:
    """Escribe `data` en `path` de forma atómica. Lanza OSError si no se pudo (el archivo anterior queda intacto).

    `mode` (solo fuera de Windows) fija los permisos antes de que el archivo aparezca con su nombre.
    `durable=False` se salta el `fsync`: para cachés que se rehacen solas (imágenes) y se escriben en ráfagas.
    Seguro entre hilos: cada escritura usa su propio temporal y las del mismo archivo se turnan.
    """
    payload = data.encode(encoding, errors) if isinstance(data, str) else data
    path.parent.mkdir(parents=True, exist_ok=True)
    with _lock_for(path):
        fd, tmp = _temp(path)
        try:
            with os.fdopen(fd, "wb") as out:
                out.write(payload)
                out.flush()
                if durable:
                    os.fsync(out.fileno())
            _permissions(tmp, path, mode)
            if backup and path.exists():
                _keep_backup(path, mode, durable)
            _replace(tmp, path)
        except BaseException:
            with contextlib.suppress(OSError):
                tmp.unlink(missing_ok=True)  # no se queda un .tmp tirado
            raise
    if durable and os.name != "nt":
        _sync_dir(path.parent)  # en Unix el cambio de nombre también tiene que llegar al disco


def atomic_write_text(path: Path, text: str, *, encoding: str = "utf-8", **kwargs) -> None:
    """`atomic_write` de un texto con los saltos de línea de `Path.write_text`: en Windows, «\r\n». Para cambiar a
    atómico un `write_text` sin que el archivo cambie ni un byte (las configuraciones de los emuladores)."""
    atomic_write(path, text.replace("\n", os.linesep) if os.linesep != "\n" else text, encoding=encoding, **kwargs)


def _keep_backup(path: Path, mode: int | None, durable: bool = True) -> None:
    """Copia el archivo actual a `.bak` (también atómico y, si se pide, empujado al disco: un `.bak` a medias no sirve
    para recuperar nada). Si no se puede, se avisa y se sigue: no estorba guardar."""
    bak = backup_path(path)
    part: Path | None = None
    try:
        fd, part = _temp(bak)
        with os.fdopen(fd, "wb") as out, open(path, "rb") as src:
            shutil.copyfileobj(src, out)
            out.flush()
            if durable:
                os.fsync(out.fileno())
        _permissions(part, bak, mode)
        _replace(part, bak)
    except OSError as exc:
        if part is not None:
            with contextlib.suppress(OSError):
                part.unlink(missing_ok=True)
        log.info("No pude respaldar %s: %s", path, exc)


def _sync_dir(folder: Path) -> None:
    try:
        fd = os.open(folder, os.O_RDONLY)
    except OSError:
        return
    try:
        os.fsync(fd)
    except OSError:
        pass
    finally:
        os.close(fd)
