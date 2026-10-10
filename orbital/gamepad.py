"""Atajos globales del mando: funcionan aunque el juego esté al frente.

El navegador solo ve el mando cuando Orbital tiene el foco, así que estos atajos se leen
aquí, en el servidor, con XInput (Windows):

  * Home (botón Guía), solo      -> ir a Orbital / volver al juego. Se dispara al SOLTARLO y
                                   solo si no se tocó otro botón: Home+X, Home+B... siguen siendo
                                   de los emuladores (Eden los usa).
  * Select + Start, mantenidos   -> "¿Cerrar el juego?" (con anillo de progreso).

La lógica de botones (ComboDetector) es pura y tiene pruebas; el sondeo de XInput solo
existe en Windows.
"""

from __future__ import annotations

import ctypes
import logging
import sys
import threading
import time
from collections.abc import Callable

log = logging.getLogger(__name__)

GUIDE = 0x0400
BACK = 0x0020
START = 0x0010

HOLD_ARM = 0.25  # s con Select+Start antes de reaccionar (evita toques accidentales)
HOLD_TOTAL = 1.5  # s hasta preguntar si cerrar


class ComboDetector:
    """Convierte el estado de los botones de UN mando en eventos.

    Eventos: "home", "hold-start", "hold-cancel", "hold-complete".
    """

    def __init__(self, arm: float = HOLD_ARM, total: float = HOLD_TOTAL) -> None:
        self.arm = arm
        self.total = total
        self._guide = False
        self._guide_chord = False  # se tocó otro botón mientras Home estaba presionado
        self._combo_since: float | None = None
        self._phase = "idle"  # idle -> armed -> done

    def update(self, buttons: int, now: float) -> list[str]:
        events: list[str] = []
        guide = bool(buttons & GUIDE)
        if guide and buttons & ~GUIDE:
            self._guide_chord = True
        if not guide and self._guide:
            if not self._guide_chord:
                events.append("home")
            self._guide_chord = False
        self._guide = guide

        combo = bool(buttons & BACK) and bool(buttons & START)
        if not combo:
            if self._phase == "armed":
                events.append("hold-cancel")
            self._combo_since, self._phase = None, "idle"
            return events
        if self._combo_since is None:
            self._combo_since = now
        held = now - self._combo_since
        if self._phase == "idle" and held >= self.arm:
            self._phase = "armed"
            events.append("hold-start")
        if self._phase == "armed" and held >= self.total:
            self._phase = "done"  # hasta soltar, no se repite
            events.append("hold-complete")
        return events


class _XInputGamepad(ctypes.Structure):
    _fields_ = [("wButtons", ctypes.c_ushort), ("bLeftTrigger", ctypes.c_ubyte), ("bRightTrigger", ctypes.c_ubyte),
                ("sThumbLX", ctypes.c_short), ("sThumbLY", ctypes.c_short),
                ("sThumbRX", ctypes.c_short), ("sThumbRY", ctypes.c_short)]


class _XInputState(ctypes.Structure):
    _fields_ = [("dwPacketNumber", ctypes.c_uint), ("Gamepad", _XInputGamepad)]


def _load_get_state():
    """XInputGetStateEx (ordinal 100): como XInputGetState pero incluye el botón Guía."""
    dll = ctypes.WinDLL("xinput1_4.dll")
    fn = dll[100]
    fn.argtypes = [ctypes.c_uint, ctypes.POINTER(_XInputState)]
    fn.restype = ctypes.c_uint
    return fn


class GamepadWatcher:
    """Hilo que sondea los 4 mandos XInput y entrega eventos a `on_event(nombre)`."""

    POLL = 1 / 60

    def __init__(self, on_event: Callable[[str], None]) -> None:
        self.on_event = on_event
        self._detectors = [ComboDetector() for _ in range(4)]
        self._stop = threading.Event()

    def start(self) -> bool:
        if sys.platform != "win32":
            return False
        try:
            get_state = _load_get_state()
        except (OSError, AttributeError) as exc:
            log.warning("Sin XInput: los atajos del mando (Home, Select+Start) no funcionarán: %s", exc)
            return False
        threading.Thread(target=self._run, args=(get_state,), daemon=True, name="gamepad").start()
        log.info("Atajos del mando activos: Home = Orbital/juego · Select+Start mantenido = cerrar juego")
        return True

    def stop(self) -> None:
        self._stop.set()

    def _run(self, get_state) -> None:
        state = _XInputState()
        while not self._stop.is_set():
            now = time.monotonic()
            for slot, detector in enumerate(self._detectors):
                buttons = state.Gamepad.wButtons if get_state(slot, ctypes.byref(state)) == 0 else 0
                for event in detector.update(buttons, now):
                    try:
                        self.on_event(event)
                    except Exception:  # noqa: BLE001 - un fallo aquí no debe matar el hilo
                        log.exception("Error atendiendo %s", event)
            self._stop.wait(self.POLL)
