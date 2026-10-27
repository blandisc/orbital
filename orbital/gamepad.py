"""Atajos globales del mando: funcionan aunque el juego esté al frente.

El navegador solo ve el mando cuando Orbital tiene el foco, así que estos atajos se leen
aquí, en el servidor, con XInput (Windows):

  * Home (botón Guía), solo      -> ir a Orbital / volver al juego. Se dispara al SOLTARLO y
                                   solo si no se tocó otro botón: Home+X, Home+B... siguen siendo
                                   de los emuladores (Eden los usa).
  * Cerrar el juego, mantenido (barra que se llena encima del juego), según el mando:
      - GameSir: LB + RB + Select. Sus combinaciones propias chocaban con Home + Start + Select: Start + Select
        sostenidos le cambian el modo (XInput/Switch/Android), Home + Start le reinicia los ajustes, y desde la
        actualización de Windows de 2026-10-18 mantener Home abre la Vista de tareas.
      - Controles de la Legion Go: Start + Select (no tienen Home ni cambian de modo).
      - Los demás: Start + Select + Home.

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

from . import input_log

log = logging.getLogger(__name__)

GUIDE = 0x0400
BACK = 0x0020
START = 0x0010

LB_BUTTON, RB_BUTTON = 0x0100, 0x0200

CLOSE_COMBO = GUIDE | BACK | START  # Start + Select + Home: los mandos que no son GameSir ni de la Legion
LEGION_CLOSE_COMBO = BACK | START  # controles de la Legion Go: no tienen Home y no cambian de modo
GAMESIR_CLOSE_COMBO = LB_BUTTON | RB_BUTTON | BACK  # sin Home ni Start: esos son combos del propio GameSir
LENOVO_VENDOR = 0x17EF
GAMESIR_VENDOR = 0x3537
CLOSE_LABELS = {CLOSE_COMBO: "Start + Select + Home", LEGION_CLOSE_COMBO: "Start + Select",
                GAMESIR_CLOSE_COMBO: "LB + RB + Select"}


VENDORS = {LENOVO_VENDOR: "legion", GAMESIR_VENDOR: "gamesir", 0x045E: "xbox"}


def connected_controllers() -> list[dict]:
    """Los mandos conectados ahora y qué atajo de cerrar usa cada uno (para la pantalla Controles)."""
    if sys.platform != "win32":
        return []
    try:
        get_state, vendor = _load_get_state(), _load_vendor()
    except (OSError, AttributeError):
        return []
    state, found = _XInputState(), []
    battery = _load_battery()
    for slot in range(4):
        if get_state(slot, ctypes.byref(state)) != 0:
            continue
        vid = vendor(slot) if vendor else None
        found.append({"slot": slot + 1, "kind": VENDORS.get(vid or 0, "other"),
                      "close": CLOSE_LABELS[close_combo_for(vid)],
                      "battery": battery(slot) if battery else None})
    return found


def close_combo_for(vendor_id: int | None) -> int:
    """Qué botones mantener para cerrar el juego según la marca del mando."""
    return {LENOVO_VENDOR: LEGION_CLOSE_COMBO, GAMESIR_VENDOR: GAMESIR_CLOSE_COMBO}.get(vendor_id or 0, CLOSE_COMBO)
HOLD_ARM = 0.25  # s con el combo antes de reaccionar (evita toques accidentales)
HOLD_TOTAL = 1.5  # s hasta preguntar si cerrar


class ComboDetector:
    """Convierte el estado de los botones de UN mando en eventos.

    Eventos: "home", "hold-start", "hold-cancel", "hold-complete", y con Home mantenido:
    Home + LB = "quick" (panel rápido), Home + RB = "capture" (captura de pantalla).
    """

    def __init__(self, arm: float = HOLD_ARM, total: float = HOLD_TOTAL, combo: int = CLOSE_COMBO) -> None:
        self.arm = arm
        self.total = total
        self.combo = combo
        self._guide = False
        self._guide_chord = False  # se tocó otro botón mientras Home estaba presionado
        self._chord_seen = 0  # botones ya contados en este Home mantenido (uno por pulsación)
        self._combo_since: float | None = None
        self._phase = "idle"  # idle -> armed -> done

    def update(self, buttons: int, now: float) -> list[str]:
        events: list[str] = []
        guide = bool(buttons & GUIDE)
        self._chord_seen &= buttons  # lo que se soltó cuenta otra vez (Home + X, X: dos capturas)
        if guide and buttons & ~GUIDE:
            self._guide_chord = True
            new = buttons & ~GUIDE & ~self._chord_seen
            self._chord_seen |= buttons & ~GUIDE
            events += [name for bit, name in HOME_CHORDS.items() if new & bit]
        if not guide:
            self._chord_seen = 0
        if not guide and self._guide:
            if not self._guide_chord:
                events.append("home")
            self._guide_chord = False
        self._guide = guide

        combo = (buttons & self.combo) == self.combo
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


# Botones XInput -> teclas virtuales de Windows, para apps sin soporte de mando (Stremio).
DPAD_UP, DPAD_DOWN, DPAD_LEFT, DPAD_RIGHT = 0x0001, 0x0002, 0x0004, 0x0008
A_BUTTON, B_BUTTON, X_BUTTON, Y_BUTTON = 0x1000, 0x2000, 0x4000, 0x8000
# Con Home mantenido. LB/RB y no X/Y/B: esos ya los usa Eden (Home+X modo dock, Home+B pantalla completa).
HOME_CHORDS = {LB_BUTTON: "quick", RB_BUTTON: "capture"}
# Los gatillos son analógicos en XInput; para el reproductor cuentan como botones (bits que XInput no usa).
LT, RT = 0x10000, 0x20000
TRIGGER_PRESSED = 100  # de 255


def with_triggers(left: int, right: int) -> int:
    return (LT if left > TRIGGER_PRESSED else 0) | (RT if right > TRIGGER_PRESSED else 0)


# Los sticks (cualquiera de los dos) como dirección, en bits aparte de la cruceta: en el reproductor
# despiertan los controles y mueven el foco de los paneles, pero no adelantan ni suben el volumen.
STICK_UP, STICK_DOWN, STICK_LEFT, STICK_RIGHT = 0x40000, 0x80000, 0x100000, 0x200000
# Como la interfaz (core/input.js): se activa al 55 % del recorrido y se suelta por debajo del 35 % (histéresis). Antes
# era un solo umbral al 61 %: un stick que rondaba el borde se soltaba y se volvía a apretar solo, y en un panel el foco
# brincaba o se trababa. Y la dirección se conserva hasta que cambia con claridad (en diagonal ya no alterna).
STICK_PUSHED = 18000  # de 32767
STICK_RELEASED = 11500
STICK_REST = 6500  # en el centro: lo que hace falta ver una vez para que un stick recién conectado cuente


def _direction(x: int, y: int) -> int:
    if abs(x) >= abs(y):
        return STICK_RIGHT if x > 0 else STICK_LEFT
    return STICK_UP if y > 0 else STICK_DOWN  # en XInput, arriba es positivo


def stick_bits(axes: tuple[int, ...], previous: tuple[int, ...] = ()) -> tuple[int, ...]:
    """(lx, ly, rx, ry) y lo de cada stick en la vuelta anterior -> la dirección de cada uno (0 = suelto), con histéresis."""
    out = []
    for n, (x, y) in enumerate(zip(axes[::2], axes[1::2], strict=False)):
        before = previous[n] if n < len(previous) else 0
        push = max(abs(x), abs(y))
        if before:
            now = _direction(x, y)
            out.append(0 if push < STICK_RELEASED else now if push >= STICK_PUSHED and now != before else before)
        else:
            out.append(_direction(x, y) if push >= STICK_PUSHED else 0)
    return tuple(out)


def with_sticks(*axes: int) -> int:
    """(lx, ly, rx, ry) -> la dirección de cada stick empujado, por su eje dominante (sin memoria)."""
    bits = 0
    for b in stick_bits(axes):
        bits |= b
    return bits

VK_SPACE, VK_ESCAPE, VK_LEFT, VK_UP, VK_RIGHT, VK_DOWN, VK_F11 = 0x20, 0x1B, 0x25, 0x26, 0x27, 0x28, 0x7A
PLAYER_KEYS = {
    A_BUTTON: VK_SPACE,  # pausa / reanuda
    B_BUTTON: VK_ESCAPE,  # volver
    Y_BUTTON: VK_F11,  # pantalla completa (en Stremio 5 es F11; F no hace nada)
    DPAD_LEFT: VK_LEFT, DPAD_RIGHT: VK_RIGHT,  # retroceder / adelantar
    DPAD_UP: VK_UP, DPAD_DOWN: VK_DOWN,  # volumen
}
REPEATING = {DPAD_LEFT, DPAD_RIGHT, DPAD_UP, DPAD_DOWN}


class KeyRemote:
    """Convierte botones del mando en teclas (con autorrepetición en la cruceta).

    Ignora todo mientras Home o Select/Start estén presionados: esos son atajos de Orbital.
    """

    def __init__(self, keymap: dict[int, int] = PLAYER_KEYS, delay: float = .35, rate: float = .12) -> None:
        self.keymap = keymap
        self.delay = delay
        self.rate = rate
        self._next: dict[int, float] = {}

    def update(self, buttons: int, now: float) -> list[int]:
        if buttons & (GUIDE | BACK | START):
            self._next.clear()
            return []
        keys = []
        for bit, vk in self.keymap.items():
            if not buttons & bit:
                self._next.pop(bit, None)
            elif bit not in self._next:
                self._next[bit] = now + self.delay
                keys.append(vk)
            elif bit in REPEATING and now >= self._next[bit]:
                self._next[bit] = now + self.rate
                keys.append(vk)
        return keys

    def reset(self) -> None:
        self._next.clear()


def send_key(vk: int) -> None:
    """Pulsa y suelta una tecla como si fuera del teclado (Windows)."""
    user32 = ctypes.windll.user32
    user32.keybd_event(vk, 0, 0, 0)
    user32.keybd_event(vk, 0, 2, 0)  # KEYEVENTF_KEYUP


class _XInputGamepad(ctypes.Structure):
    _fields_ = [("wButtons", ctypes.c_ushort), ("bLeftTrigger", ctypes.c_ubyte), ("bRightTrigger", ctypes.c_ubyte),
                ("sThumbLX", ctypes.c_short), ("sThumbLY", ctypes.c_short),
                ("sThumbRX", ctypes.c_short), ("sThumbRY", ctypes.c_short)]


class _XInputState(ctypes.Structure):
    _fields_ = [("dwPacketNumber", ctypes.c_uint), ("Gamepad", _XInputGamepad)]


class _XInputCapabilities(ctypes.Structure):
    _fields_ = [("Type", ctypes.c_ubyte), ("SubType", ctypes.c_ubyte), ("Flags", ctypes.c_ushort),
                ("Gamepad", _XInputGamepad), ("wLeftMotorSpeed", ctypes.c_ushort), ("wRightMotorSpeed", ctypes.c_ushort)]


class _XInputCapabilitiesEx(ctypes.Structure):
    _fields_ = [("Capabilities", _XInputCapabilities), ("VendorId", ctypes.c_ushort), ("ProductId", ctypes.c_ushort),
                ("ProductVersion", ctypes.c_ushort), ("unk1", ctypes.c_ushort), ("unk2", ctypes.c_uint)]


def _load_ids():
    """XInputGetCapabilitiesEx (ordinal 108): la marca y el modelo (VendorId, ProductId) de cada mando. None si no existe."""
    try:
        fn = ctypes.WinDLL("xinput1_4.dll")[108]  # type: ignore[index]
    except (OSError, AttributeError):
        return None
    fn.argtypes = [ctypes.c_uint, ctypes.c_uint, ctypes.c_uint, ctypes.POINTER(_XInputCapabilitiesEx)]
    fn.restype = ctypes.c_uint

    def ids(slot: int) -> tuple[int, int] | None:
        caps = _XInputCapabilitiesEx()
        return (caps.VendorId, caps.ProductId) if fn(1, slot, 0, ctypes.byref(caps)) == 0 else None
    return ids


def _load_version():
    """La versión del producto de cada mando (va en el identificador de SDL que usan Eden y compañía). None si no hay."""
    try:
        fn = ctypes.WinDLL("xinput1_4.dll")[108]  # type: ignore[index]
    except (OSError, AttributeError):
        return None
    fn.argtypes = [ctypes.c_uint, ctypes.c_uint, ctypes.c_uint, ctypes.POINTER(_XInputCapabilitiesEx)]
    fn.restype = ctypes.c_uint

    def version(slot: int) -> int | None:
        caps = _XInputCapabilitiesEx()
        return caps.ProductVersion if fn(1, slot, 0, ctypes.byref(caps)) == 0 else None
    return version


def _load_vendor():
    """La marca (VendorId) de cada mando. None si no existe."""
    ids = _load_ids()
    if ids is None:
        return None

    def vendor(slot: int) -> int | None:
        found = ids(slot)
        return found[0] if found else None
    return vendor


_watcher: GamepadWatcher | None = None  # el que sondea los mandos (uno por Orbital)


def play_order() -> list[tuple[int, int]]:
    """Los controles encendidos para un juego, como en una consola: primero el que usaste por última vez (el que apretó
    A para abrirlo), luego los demás en su lugar de XInput. [(marca, modelo), …] (emulator_input los acomoda)."""
    watcher = _watcher
    if watcher is None:
        return []
    devices = dict(watcher.devices)
    first = watcher.last_used if watcher.last_used in devices else None
    slots = ([first] if first is not None else []) + [s for s in sorted(devices) if s != first]
    return [devices[s] for s in slots]


class _BatteryInformation(ctypes.Structure):
    _fields_ = [("BatteryType", ctypes.c_ubyte), ("BatteryLevel", ctypes.c_ubyte)]


BATTERY_LEVELS = {0: "empty", 1: "low", 2: "medium", 3: "full"}


def _load_battery():
    """XInputGetBatteryInformation: «wired» (con cable), «full», «medium», «low», «empty» o None."""
    try:
        fn = ctypes.WinDLL("xinput1_4.dll").XInputGetBatteryInformation
    except (OSError, AttributeError):
        return None
    fn.argtypes = [ctypes.c_uint, ctypes.c_ubyte, ctypes.POINTER(_BatteryInformation)]
    fn.restype = ctypes.c_uint

    def read(slot: int) -> str | None:
        info = _BatteryInformation()
        if fn(slot, 0, ctypes.byref(info)) != 0:  # 0 = BATTERY_DEVTYPE_GAMEPAD
            return None
        if info.BatteryType == 1:  # BATTERY_TYPE_WIRED
            return "wired"
        if info.BatteryType in (0, 0xFF):  # desconectado o desconocido
            return None
        return BATTERY_LEVELS.get(info.BatteryLevel)

    return read


class _XInputVibration(ctypes.Structure):
    _fields_ = [("wLeftMotorSpeed", ctypes.c_ushort), ("wRightMotorSpeed", ctypes.c_ushort)]


def rumble(slot: int, seconds: float = .35, strength: float = .6) -> bool:
    """Hace vibrar ESE mando un momento: «¿cuál es el Jugador 2?» se contesta sintiéndolo en la mano."""
    if sys.platform != "win32":
        return False
    try:
        fn = ctypes.WinDLL("xinput1_4.dll").XInputSetState
    except (OSError, AttributeError):
        return False
    fn.argtypes = [ctypes.c_uint, ctypes.POINTER(_XInputVibration)]
    fn.restype = ctypes.c_uint
    level = int(max(0.0, min(1.0, strength)) * 65535)
    if fn(slot, ctypes.byref(_XInputVibration(level, level))) != 0:
        return False
    timer = threading.Timer(seconds, lambda: fn(slot, ctypes.byref(_XInputVibration(0, 0))))
    timer.daemon = True
    timer.start()
    return True


def _load_get_state():
    """XInputGetStateEx (ordinal 100): como XInputGetState pero incluye el botón Guía."""
    dll = ctypes.WinDLL("xinput1_4.dll")
    fn = dll[100]  # type: ignore[index]
    fn.argtypes = [ctypes.c_uint, ctypes.POINTER(_XInputState)]
    fn.restype = ctypes.c_uint
    return fn


class GamepadWatcher:
    """Hilo que sondea los 4 mandos XInput y entrega eventos a `on_event(nombre)`."""

    # 30 lecturas por segundo con un mando conectado: de sobra para un toque de Home (dura ~80 ms) y la cruceta del
    # reproductor. Sin ninguno, 4 por segundo, solo para notar cuando conectas uno. Antes eran 60 siempre: el servidor
    # gastaba CPU sin parar aunque no hubiera mando (y es lo que más hacía con Orbital quieta y un juego al frente).
    POLL = 1 / 30
    POLL_IDLE = 1 / 4
    QUIET = 3.0  # s tras arrancar o despertar en que los mandos que aparecen ya estaban: no se avisan

    def __init__(self, on_event: Callable[[str], None],
                 on_buttons: Callable[[int, int, float], None] | None = None) -> None:
        self.on_event = on_event
        self.on_buttons = on_buttons  # (mando, botones, ahora): para el control remoto de Stremio
        self._detectors = [ComboDetector() for _ in range(4)]
        self._stop = threading.Event()
        self._redetect = threading.Event()
        self.hold_label = ""  # el atajo de cerrar que se está manteniendo («LB + RB + Select»), para el aviso
        self.devices: dict[int, tuple[int, int]] = {}  # lugar -> (marca, modelo) de cada mando encendido
        self.last_used: int | None = None  # el lugar del último mando que apretó un botón (el Jugador 1 de un juego)
        self.last_input = time.monotonic()  # cuándo se apretó algo por última vez (para saber si la consola está sola)
        self.guide_at = float("-inf")  # cuándo se apretó el botón del centro (Home/Xbox) por última vez (ver shell)
        self.connected_at: dict[int, float] = {}  # lugar -> cuándo llegó (el orden de los jugadores, ver players.py)
        self.versions: dict[tuple[int, int], int] = {}  # (marca, modelo) -> versión del producto (ver emulator_input)
        # (lugar, conectado, (marca, modelo)): un mando que llega o se va. No suena por los que ya estaban al arrancar
        # ni al despertar (ver QUIET).
        self.on_pad: Callable[[int, bool, tuple[int, int] | None], None] | None = None

    def start(self) -> bool:
        if sys.platform != "win32":
            return False
        try:
            get_state = _load_get_state()
        except (OSError, AttributeError) as exc:
            log.warning("Sin XInput: los atajos del mando (Home, Select+Start) no funcionarán: %s", exc)
            return False
        global _watcher
        _watcher = self
        threading.Thread(target=self._run, args=(get_state,), daemon=True, name="gamepad").start()
        log.info("Atajos del mando activos: Home = Orbital/juego · cerrar juego = Start+Select+Home "
                 "(GameSir: LB+RB+Select · controles de la Legion Go: Start+Select)")
        return True

    def stop(self) -> None:
        self._stop.set()

    def _pad_changed(self, slot: int, connected: bool, device: tuple[int, int] | None, quiet: bool) -> None:
        if self.on_pad is None or quiet:
            return
        try:
            self.on_pad(slot, connected, device)
        except Exception:  # noqa: BLE001 - un aviso roto no tumba el hilo de los mandos
            log.exception("Error avisando del mando %d", slot + 1)

    def redetect(self) -> None:
        """Tras suspender, los mandos se reconectan: volver a ver la marca de cada uno."""
        self._redetect.set()

    def _run(self, get_state) -> None:
        state = _XInputState()
        ids = _load_ids()
        version = _load_version()
        was_connected = [False] * 4
        pressed = [0] * 4  # los botones de la vuelta anterior: un botón nuevo dice quién está jugando
        sticks_armed = [False] * 4  # ya se le vio el stick en el centro desde que se conectó
        stick_state: list[tuple[int, ...]] = [()] * 4  # la dirección de cada stick en la vuelta anterior (histéresis)
        traced: list[tuple | None] = [None] * 4  # lo último anotado en entrada.log, por lugar
        quiet_until = time.monotonic() + self.QUIET
        while not self._stop.is_set():
            now = time.monotonic()
            if self._redetect.is_set():
                self._redetect.clear()
                was_connected = [False] * 4
                quiet_until = now + self.QUIET
                # Nada queda "mantenido" de antes de dormir (sin disparar eventos al soltar).
                self._detectors = [ComboDetector() for _ in range(4)]
            for slot, detector in enumerate(self._detectors):
                connected = get_state(slot, ctypes.byref(state)) == 0
                if connected and not was_connected[slot] and ids:
                    # Un mando nuevo en este lugar: su atajo de cerrar depende de la marca.
                    found = ids(slot)
                    vid = found[0] if found else None
                    if found:
                        self.devices[slot] = found
                        ver = version(slot) if version else None
                        if ver is not None:
                            self.versions[found] = ver
                    detector.combo = close_combo_for(vid)
                    log.info("Mando %d (%s): cerrar juego con %s", slot + 1, "%04X:%04X" % found if found else "?",
                             CLOSE_LABELS[detector.combo])
                    self.connected_at.setdefault(slot, now)
                    self._pad_changed(slot, True, found, quiet=now < quiet_until)
                if was_connected[slot] and not connected:
                    # Se desconectó con botones apretados: eso no es «soltar Home» (no abre Orbital).
                    self._detectors[slot] = detector = ComboDetector(combo=detector.combo)
                if was_connected[slot] and not connected:
                    self.connected_at.pop(slot, None)
                    self._pad_changed(slot, False, self.devices.get(slot), quiet=False)
                if not connected:
                    self.devices.pop(slot, None)
                was_connected[slot] = connected
                buttons = state.Gamepad.wButtons if connected else 0
                if buttons & ~pressed[slot]:
                    self.last_used = slot
                    self.last_input = now
                    if buttons & GUIDE and not pressed[slot] & GUIDE:
                        self.guide_at = now
                pressed[slot] = buttons
                if connected:  # diagnóstico (entrada.log): lo que reporta XInput, solo cuando cambia
                    pad = state.Gamepad
                    sig = (buttons, pad.bLeftTrigger // 32, pad.bRightTrigger // 32,
                           *(round(a / 4096) for a in (pad.sThumbLX, pad.sThumbLY, pad.sThumbRX, pad.sThumbRY)))
                    if traced[slot] != sig:
                        traced[slot] = sig
                        input_log.record([{"from": "xinput", "slot": slot, "buttons": f"{buttons:04x}",
                                           "lt": pad.bLeftTrigger, "rt": pad.bRightTrigger,
                                           "lx": pad.sThumbLX, "ly": pad.sThumbLY, "rx": pad.sThumbRX, "ry": pad.sThumbRY}])
                elif traced[slot] is not None:
                    traced[slot] = None
                    input_log.record([{"from": "xinput", "slot": slot, "gone": True}])
                for event in detector.update(buttons, now):
                    if event == "hold-start":
                        self.hold_label = CLOSE_LABELS.get(detector.combo, "")
                    try:
                        self.on_event(event)
                    except Exception:  # noqa: BLE001 - un fallo aquí no debe matar el hilo
                        log.exception("Error atendiendo %s", event)
                if self.on_buttons:
                    if connected:
                        pad = state.Gamepad
                        buttons |= with_triggers(pad.bLeftTrigger, pad.bRightTrigger)
                        # Solo el stick izquierdo, como en la interfaz: el derecho no hace nada en el reproductor, y en el
                        # mando del usuario se queda abajo a tope (ry = -32768 en entrada.log, también al soltarlo) y el
                        # pulgar lo roza al picar B; «abajo» sin parar volvía a enseñar los controles que B acababa de quitar.
                        axes = (pad.sThumbLX, pad.sThumbLY)
                        # Un stick recién conectado no cuenta hasta verlo en el centro (algunos llegan con el eje cargado
                        # y el reproductor lo tomaba como empujado sin parar).
                        if not sticks_armed[slot] and max(abs(a) for a in axes) < STICK_REST:
                            sticks_armed[slot] = True
                        if sticks_armed[slot]:
                            stick_state[slot] = stick_bits(axes, stick_state[slot])
                            for bit in stick_state[slot]:
                                buttons |= bit
                    else:
                        sticks_armed[slot], stick_state[slot] = False, ()
                    try:
                        self.on_buttons(slot, buttons, now)
                    except Exception:  # noqa: BLE001
                        log.exception("Error en el control remoto")
            self._stop.wait(self.POLL if any(was_connected) else self.POLL_IDLE)
