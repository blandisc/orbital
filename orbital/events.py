"""Eventos de Orbital: quien hace algo lo publica y quien necesita saberlo se suscribe.

Así las piezas no se llaman entre sí: el lanzador publica "closed" y lo escuchan la interfaz (para
el aviso "De vuelta de…"), Stremio (para refrescar Seguir viendo) y Steam (para releer las horas).
Un suscriptor que falla no afecta a los demás ni a quien publica.
"""

from __future__ import annotations

import logging
import threading
from collections.abc import Callable

log = logging.getLogger(__name__)

Event = dict
Listener = Callable[[Event], None]


class EventBus:
    def __init__(self) -> None:
        self.listeners: list[Listener] = []  # público: el servidor reenvía todo a la interfaz
        self._lock = threading.Lock()

    def subscribe(self, listener: Listener) -> Callable[[], None]:
        """Se suscribe; devuelve cómo darse de baja."""
        with self._lock:
            self.listeners.append(listener)

        def unsubscribe() -> None:
            with self._lock:
                if listener in self.listeners:
                    self.listeners.remove(listener)
        return unsubscribe

    def publish(self, event: Event) -> None:
        with self._lock:
            listeners = list(self.listeners)
        for listener in listeners:
            try:
                listener(event)
            except Exception:  # noqa: BLE001 - un suscriptor roto no debe tumbar a quien publica
                log.exception("Error atendiendo el evento %s", event.get("type"))
