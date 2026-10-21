"""Juegos de Xbox 360 con varios programas: cambiar de uno a otro sin salir del juego.

Black Ops II trae dos: la campaña (default.xex) y el multijugador con Zombies (default_mp.xex). Al elegir Zombies el juego
le pide a la consola «abre el otro programa» (XamLoaderLaunchTitle). Esta versión de Xenia (canary netplay) lo intenta
dentro del mismo proceso y el programa nuevo choca con el anterior («Failed to bind socket, error 10048»: el puerto de red
sigue tomado), pero antes deja la petición escrita en launch_data.bin, que lee al arrancar. Por eso había que pulsar OK,
salir de Xenia y volver a abrirlo.

Ahora Orbital vigila ese archivo mientras corre un juego de Xenia: cuando aparece con un programa pedido, cierra ese Xenia
y lo vuelve a abrir igual (en un proceso limpio Xenia lee la petición y carga el programa nuevo con sus datos). Sin programa
(salir al tablero), no se relanza nada.
"""

from __future__ import annotations

import logging
import struct
import threading
import time
from collections.abc import Callable
from pathlib import Path

log = logging.getLogger(__name__)

LAUNCH_DATA = "launch_data.bin"
POLL = .25
SETTLE = .5  # s: que Xenia termine de escribir el archivo
STALE_GRACE = 30.0  # s: una petición vieja de antes de abrir la lee y la borra Xenia al arrancar; esa no cuenta


def xenia_dir(argv: list[str]) -> Path | None:
    """La carpeta de Xenia si lo que se lanza es Xenia (su .exe o su launch-xenia.cmd)."""
    if not argv:
        return None
    first = Path(argv[0])
    return first.parent if "xenia" in first.name.lower() else None


def requested_module(data: bytes) -> str | None:
    """El programa que pide abrir la petición («default_mp.xex»); None si no pide ninguno o no se entiende.
    Formato: u16 largo + ruta del juego, u16 largo + programa, luego las banderas y los datos del juego."""
    try:
        (path_len,) = struct.unpack_from("<H", data, 0)
        (module_len,) = struct.unpack_from("<H", data, 2 + path_len)
        module = data[4 + path_len:4 + path_len + module_len].decode("utf-8", "replace").strip("\0 ")
    except (struct.error, ValueError):
        return None
    return module or None


def program_name(module: str) -> str:
    """Cómo decirle al programa en la pantalla de carga: «default_mp.xex» es el multijugador (y Zombies)."""
    name = module.lower()
    if "_mp" in name or "zm" in name:
        return "Cambiando a Multijugador y Zombies"
    if name == "default.xex":
        return "Volviendo al menú principal"
    return "Cambiando de modo"


def watch(folder: Path, still_playing: Callable[[], bool], relaunch: Callable[[str], None],
          sleep=time.sleep, clock=time.monotonic) -> None:
    """Hasta que el juego se cierre: cada petición de cambiar de programa, `relaunch(programa)`."""
    path = folder / LAUNCH_DATA
    stale_until = clock() + STALE_GRACE if path.exists() else 0.0
    while still_playing():
        sleep(POLL)
        if not path.exists():
            stale_until = 0.0
            continue
        if clock() < stale_until:
            continue  # la de antes de abrir: Xenia la está leyendo
        sleep(SETTLE)
        try:
            module = requested_module(path.read_bytes())
        except OSError:
            continue
        if module is None:
            stale_until = clock() + STALE_GRACE  # salir al tablero: que Xenia se cierre solo (y no releerla en bucle)
            continue
        log.info("El juego pide abrir %s: relanzo Xenia para cambiar de programa", module)
        relaunch(module)
        stale_until = clock() + STALE_GRACE  # la del relanzamiento: la lee el Xenia nuevo


def start(folder: Path, still_playing: Callable[[], bool], relaunch: Callable[[str], None]) -> threading.Thread:
    thread = threading.Thread(target=watch, args=(folder, still_playing, relaunch), daemon=True, name="title-switch")
    thread.start()
    return thread
