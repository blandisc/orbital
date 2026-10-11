"""Los elementos del catálogo en memoria, a salvo entre hilos (escaneo, Stremio, Steam y peticiones a la vez)."""

from __future__ import annotations

import threading
from collections.abc import Callable, Iterable

from .library.models import LibraryItem


class ItemStore:
    def __init__(self) -> None:
        self._items: dict[str, LibraryItem] = {}
        self._lock = threading.Lock()

    def all(self) -> list[LibraryItem]:
        with self._lock:
            return list(self._items.values())

    def get(self, item_id: str) -> LibraryItem | None:
        with self._lock:
            return self._items.get(item_id)

    def replace(self, items: Iterable[LibraryItem]) -> None:
        """Todo de nuevo (un escaneo completo)."""
        fresh = {item.id: item for item in items}
        with self._lock:
            self._items = fresh

    def replace_source(self, source: str, items: Iterable[LibraryItem]) -> None:
        """Solo lo de una fuente ("stremio", "cinemeta"): lo demás se queda como está."""
        fresh = {item.id: item for item in items}
        with self._lock:
            self._items = {k: v for k, v in self._items.items() if v.source != source}
            self._items.update(fresh)

    def update(self, change: Callable[[LibraryItem], None], where: Callable[[LibraryItem], bool]) -> None:
        """Modifica en su lugar los elementos que cumplan `where` (p. ej. las horas de Steam)."""
        with self._lock:
            for item in self._items.values():
                if where(item):
                    change(item)
