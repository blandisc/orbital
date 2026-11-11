"""Guardar un archivo sin que un apagón lo deje a medias.

`atomic_write` escribe primero a un temporal junto al archivo, lo empuja al disco (`flush` + `os.fsync`) y solo
entonces lo pone en su lugar con `os.replace`, que en Windows y en Unix cambia uno por otro de un jalón: quien lee
ve el archivo viejo completo o el nuevo completo, nunca la mitad. Con `backup=True` el archivo anterior queda
como `<nombre>.bak` antes del cambio, y `backup_path` dice dónde buscarlo si el principal resulta dañado.
"""

from __future__ import annotations

import contextlib
import logging
import os
import shutil
from pathlib import Path

log = logging.getLogger(__name__)


def tmp_path(path: Path) -> Path:
    return path.with_name(path.name + ".tmp")


def backup_path(path: Path) -> Path:
    return path.with_name(path.name + ".bak")


def atomic_write(path: Path, data: str | bytes, *, encoding: str = "utf-8", errors: str = "strict",
                 backup: bool = False, mode: int | None = None, durable: bool = True) -> None:
    """Escribe `data` en `path` de forma atómica. Lanza OSError si no se pudo (el archivo anterior queda intacto).

    `mode` (solo fuera de Windows) fija los permisos antes de que el archivo aparezca con su nombre.
    `durable=False` se salta el `fsync`: para cachés que se rehacen solas (imágenes) y se escriben en ráfagas.
    """
    payload = data.encode(encoding, errors) if isinstance(data, str) else data
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = tmp_path(path)
    try:
        with open(tmp, "wb") as out:
            out.write(payload)
            out.flush()
            if durable:
                os.fsync(out.fileno())
        if mode is not None and os.name != "nt":
            tmp.chmod(mode)
        if backup and path.exists():
            _keep_backup(path, mode)
        os.replace(tmp, path)
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


def _keep_backup(path: Path, mode: int | None) -> None:
    """Copia el archivo actual a `.bak` (también atómico). Si no se puede, se avisa y se sigue: no estorba guardar."""
    bak = backup_path(path)
    part = bak.with_name(bak.name + ".tmp")
    try:
        shutil.copyfile(path, part)
        if mode is not None and os.name != "nt":
            part.chmod(mode)
        os.replace(part, bak)
    except OSError as exc:
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
