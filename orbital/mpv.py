"""Cliente de mpv por su tubería JSON (--input-ipc-server), con conexiones que se quedan abiertas.

Antes cada comando y cada lectura abría la tubería de nuevo (~10 veces por segundo durante una
película). Ahora hay dos conexiones:

  * Comandos: una sola, que se reabre si mpv se reinicia. Pide a mpv no mandarle eventos, así que
    cada respuesta es la de su comando.
  * Observador: un hilo que pide a mpv avisar cuando cambian las propiedades que Orbital mira cada
    segundo (pausa, posición, duración…) y las guarda. `get()` de esas propiedades no habla con mpv.

En Windows una misma conexión no puede leer en un hilo y escribir en otro a la vez (las operaciones
se forman en fila): por eso son dos conexiones y no una.
"""

from __future__ import annotations

import json
import logging
import threading
import time

log = logging.getLogger(__name__)

PIPE = r"\\.\pipe\orbital-mpv"
# Lo que Orbital consulta cada segundo: mpv avisa cuando cambian y no hay que preguntar.
OBSERVED = ("pause", "time-pos", "duration", "idle-active", "eof-reached", "paused-for-cache",
            "cache-buffering-state", "chapter", "volume")


class Mpv:
    def __init__(self, pipe: str = PIPE, observe: tuple[str, ...] = OBSERVED) -> None:
        self.pipe = pipe
        self.observe = observe
        self._lock = threading.Lock()
        self._fh = None  # conexión de comandos
        self._cache: dict[str, object] = {}
        self._cache_lock = threading.Lock()
        self._observer: threading.Thread | None = None
        self._observing = False

    # --- comandos ------------------------------------------------------------------------------
    def _connect(self):
        fh = open(self.pipe, "r+b", buffering=0)  # noqa: SIM115 - se queda abierta
        fh.write(b'{"command": ["disable_event", "all"]}\n')  # que solo lleguen respuestas
        fh.readline()
        return fh

    def _send(self, payload: dict, label) -> dict | None:
        line = (json.dumps(payload) + "\n").encode()
        with self._lock:
            for attempt in (1, 2):  # si mpv se reinició, la conexión vieja ya no sirve: una nueva
                try:
                    if self._fh is None:
                        self._fh = self._connect()
                    self._fh.write(line)
                    for _ in range(20):  # por si quedó algún evento antes de disable_event
                        reply = self._fh.readline()
                        if not reply:
                            raise OSError("mpv cerró la conexión")
                        data = json.loads(reply)
                        if "error" in data:
                            return data
                    return None
                except (OSError, ValueError) as exc:
                    self._close_commands()
                    if attempt == 2:
                        log.debug("mpv no respondió a %s: %s", label, exc)
        return None

    def _close_commands(self) -> None:
        if self._fh is not None:
            try:
                self._fh.close()
            except OSError:
                pass
            self._fh = None

    def command(self, *args) -> dict | None:
        return self._send({"command": list(args)}, args)

    def command_named(self, **args) -> dict | None:
        """Comando con argumentos por nombre (osd-overlay los necesita)."""
        return self._send({"command": args}, args.get("name"))

    def get(self, prop: str):
        if prop in self.observe and self._observing:
            with self._cache_lock:
                if prop in self._cache:
                    return self._cache[prop]
        reply = self.command("get_property", prop)
        return reply.get("data") if reply and reply.get("error") == "success" else None

    def show(self, text: str, ms: int = 1800) -> None:
        self.command("show-text", text, ms)

    # --- observador ----------------------------------------------------------------------------
    def start_observing(self) -> None:
        """Arranca (una vez por mpv) el hilo que recibe los cambios de las propiedades observadas."""
        if self._observer is not None and self._observer.is_alive():
            return
        with self._cache_lock:
            self._cache.clear()
        self._observer = threading.Thread(target=self._observe_loop, daemon=True, name="mpv-observer")
        self._observer.start()

    def _observe_loop(self) -> None:
        deadline = time.monotonic() + 10  # mpv tarda un momento en abrir su tubería
        fh = None
        while fh is None and time.monotonic() < deadline:
            try:
                fh = open(self.pipe, "r+b", buffering=0)  # noqa: SIM115
            except OSError:
                time.sleep(.2)
        if fh is None:
            return
        try:
            for i, prop in enumerate(self.observe, start=1):
                fh.write((json.dumps({"command": ["observe_property", i, prop]}) + "\n").encode())
            self._observing = True
            while True:
                line = fh.readline()
                if not line:
                    break  # mpv se cerró
                try:
                    data = json.loads(line)
                except ValueError:
                    continue
                if data.get("event") == "property-change" and data.get("name") in self.observe:
                    with self._cache_lock:
                        self._cache[data["name"]] = data.get("data")
        except OSError:
            pass
        finally:
            self._observing = False
            with self._cache_lock:
                self._cache.clear()
            try:
                fh.close()
            except OSError:
                pass

    def close(self) -> None:
        with self._lock:
            self._close_commands()
