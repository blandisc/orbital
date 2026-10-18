"""Juegos nuevos sin reiniciar: vigila las carpetas de juegos (las de cada emulador y las de Steam) mientras Orbital está
abierto. Antes solo se buscaba al arrancar o con «Buscar juegos nuevos»: un juego copiado con Orbital abierto no salía
hasta el siguiente arranque.

Barato: cada `interval` segundos se listan esas carpetas (nombre, tamaño y fecha de cada archivo, sin abrirlos). Si algo
cambió, se espera a que deje de cambiar (copiar un ISO de 8 GB tarda minutos: no se escanea a medias) y entonces se
reescanea la biblioteca, que también busca su portada, logo y datos. La tele recibe «library-changed» y un aviso con el
nombre de lo que llegó."""

from __future__ import annotations

import logging
import os
import threading
from collections.abc import Callable
from pathlib import Path

log = logging.getLogger(__name__)

INTERVAL = 20.0  # s entre revisiones
MAX_FILES = 20_000  # por si alguien apunta una carpeta enorme: no se recorre entera cada 20 s
DEPTH = 2  # con subcarpetas, hasta dos niveles: un juego nuevo siempre cambia ahí (una carpeta de PS3 trae cientos de archivos)


def _entries(folder: Path, depth: int):
    """(ruta, tamaño, fecha) de lo que hay en `folder`, bajando `depth` niveles más."""
    try:
        listing = list(os.scandir(folder))
    except OSError:
        return  # la carpeta no existe (todavía) o no se deja leer
    for entry in listing:
        try:
            st = entry.stat(follow_symlinks=False)
            yield entry.path.lower(), st.st_size if entry.is_file(follow_symlinks=False) else -1, int(st.st_mtime)
            if depth > 0 and entry.is_dir(follow_symlinks=False):
                yield from _entries(Path(entry.path), depth - 1)
        except OSError:
            continue  # se está copiando o se acaba de borrar: en la siguiente vuelta


NAMES_ONLY = "names"  # en vez de True/False: solo cuenta qué archivos hay (Steam reescribe los suyos a cada rato)


def folder_signature(folders: list[tuple[Path, bool | str]]) -> frozenset:
    """Lo que hay en esas carpetas: (ruta, tamaño, fecha). `True` en la tupla: también subcarpetas (hasta DEPTH);
    NAMES_ONLY: solo los nombres (un juego de Steam nuevo es un appmanifest nuevo; Steam reescribe los que ya están
    al arrancar y al actualizar, y eso reescaneaba la biblioteca sin que hubiera nada nuevo)."""
    seen: set[tuple[str, int, int]] = set()
    for folder, mode in folders:
        for n, (path, size, mtime) in enumerate(_entries(folder, DEPTH if mode is True else 0)):
            if n >= MAX_FILES:
                break
            seen.add((path, 0, 0) if mode == NAMES_ONLY else (path, size, mtime))
    return frozenset(seen)


class LibraryWatcher:
    """Revisa las carpetas en su propio hilo y llama a `on_change()` cuando lo nuevo ya terminó de llegar.

    `folders()` dice qué carpetas vigilar (se vuelve a preguntar en cada vuelta: un emulador recién instalado entra solo)."""

    def __init__(self, folders: Callable[[], list[tuple[Path, bool | str]]], on_change: Callable[[], object],
                 interval: float = INTERVAL) -> None:
        self.folders = folders
        self.on_change = on_change
        self.interval = interval
        self._stop = threading.Event()
        self._thread: threading.Thread | None = None
        self._known: frozenset | None = None
        self._pending: frozenset | None = None  # cambió, pero aún no se estabiliza

    def start(self) -> None:
        if self._thread is not None:
            return
        self._known = self._signature()
        self._thread = threading.Thread(target=self._run, daemon=True, name="vigilante-juegos")
        self._thread.start()

    def stop(self) -> None:
        self._stop.set()

    def _signature(self) -> frozenset:
        try:
            return folder_signature(self.folders())
        except Exception:  # noqa: BLE001 - el vigilante nunca tumba a Orbital
            log.exception("No pude revisar las carpetas de juegos")
            return self._known or frozenset()

    def check(self) -> bool:
        """Una vuelta. True si llamó a on_change (lo nuevo ya no estaba cambiando)."""
        now = self._signature()
        if now == self._known:
            self._pending = None
            return False
        if now != self._pending:  # cambió (o sigue cambiando: una copia en curso): se espera una vuelta más
            self._pending = now
            return False
        changed = sorted({p for p, _, _ in (now ^ (self._known or frozenset()))})[:3]
        self._known, self._pending = now, None
        log.info("Carpetas de juegos con cambios (%s): vuelvo a buscar juegos", ", ".join(changed))
        try:
            self.on_change()
        except Exception:  # noqa: BLE001
            log.exception("No pude volver a buscar juegos")
        return True

    def accept(self) -> None:
        """Ya se escaneó por otro lado (al arrancar, «Buscar juegos nuevos»): lo de ahora es lo conocido."""
        self._known, self._pending = self._signature(), None

    def _run(self) -> None:
        while not self._stop.wait(self.interval):
            self.check()
