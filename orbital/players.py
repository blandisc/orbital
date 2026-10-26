"""Los jugadores de la consola, como en una consola de verdad.

El Jugador 1 es el control con el que abriste el juego; los demás, en el orden en que llegaron (no en el lugar que les dio
Windows: con dos mandos, el que conectaste primero era el «1» aunque abrieras con el otro). Un control que conectas a media
partida se suma al final. El orden se puede cambiar desde Orbital (Jugadores › «Hacer Jugador 1») y lo usan los
emuladores al abrir (emulator_input.py).
"""

from __future__ import annotations

import logging
import threading

from . import gamepad

log = logging.getLogger(__name__)

Device = tuple[int, int]  # (marca, modelo)

# Cómo se llama cada control para ti (por marca, y algunos por modelo).
NAMES = {0x17EF: "Legion Go", 0x3537: "GameSir", 0x045E: "Xbox", 0x054C: "PlayStation", 0x057E: "Nintendo",
         0x2DC8: "8BitDo", 0x0E6F: "PDP", 0x0F0D: "Hori", 0x24C6: "PowerA", 0x146B: "Nacon", 0x1532: "Razer"}
KINDS = {0x17EF: "legion", 0x3537: "gamesir", 0x045E: "xbox"}


def name_of(device: Device | None) -> str:
    return NAMES.get(device[0], "Control") if device else "Control"


class Players:
    """El orden de los jugadores (lugares de XInput, 0–3), al día con los mandos conectados."""

    def __init__(self, watcher=None) -> None:
        self.watcher = watcher
        self.order: list[int] = []  # lugares de XInput: el primero es el Jugador 1
        self._lock = threading.Lock()

    def _connected(self) -> dict[int, float]:
        """{lugar: cuándo llegó} de los mandos encendidos."""
        watcher = self.watcher or gamepad._watcher  # noqa: SLF001 - el único que sondea los mandos
        if watcher is None:
            return {}
        arrived = dict(getattr(watcher, "connected_at", {}))
        return {slot: arrived.get(slot, float("inf")) for slot in watcher.devices}

    def sync(self) -> list[int]:
        """Quita los que se fueron y suma al final los que llegaron (en el orden en que llegaron)."""
        connected = self._connected()
        with self._lock:
            kept = [s for s in self.order if s in connected]
            new = sorted((s for s in connected if s not in kept), key=lambda s: (connected[s], s))
            self.order = kept + new
            return list(self.order)

    def joined(self, slot: int) -> int:
        """Un control que acaba de llegar: su número de jugador (1, 2…)."""
        order = self.sync()
        return order.index(slot) + 1 if slot in order else len(order) + 1

    def for_launch(self) -> list[int]:
        """Al abrir un juego: el control con el que lo abriste es el Jugador 1 (los demás conservan su orden)."""
        order = self.sync()
        watcher = self.watcher or gamepad._watcher  # noqa: SLF001
        first = getattr(watcher, "last_used", None)
        if first in order:
            self.make_first(first)
        return list(self.order)

    def make_first(self, slot: int) -> bool:
        with self._lock:
            if slot not in self.order:
                return False
            self.order.remove(slot)
            self.order.insert(0, slot)
        log.info("Jugadores: el mando %d es ahora el Jugador 1", slot + 1)
        return True

    def devices(self, order: list[int] | None = None) -> list[Device]:
        """Marca y modelo de cada jugador, en orden (lo que acomodan los emuladores de Switch)."""
        watcher = self.watcher or gamepad._watcher  # noqa: SLF001
        known = dict(getattr(watcher, "devices", {}))
        return [known[s] for s in (self.order if order is None else order) if s in known]

    def versions(self) -> dict[Device, int]:
        """La versión del producto de cada control (Eden la lleva en su identificador)."""
        watcher = self.watcher or gamepad._watcher  # noqa: SLF001
        return dict(getattr(watcher, "versions", {}))

    def snapshot(self, battery=None) -> list[dict]:
        """Para la pantalla Jugadores: número, cuál control, batería."""
        order = self.sync()
        watcher = self.watcher or gamepad._watcher  # noqa: SLF001
        known = dict(getattr(watcher, "devices", {}))
        read = battery if battery is not None else gamepad._load_battery()  # noqa: SLF001
        out = []
        for n, slot in enumerate(order, start=1):
            device = known.get(slot)
            out.append({"player": n, "slot": slot, "name": name_of(device),
                        "kind": KINDS.get(device[0], "other") if device else "other",
                        "battery": read(slot) if read else None})
        return out


players = Players()  # el de la consola (lo usan las sesiones, la API y los avisos)
