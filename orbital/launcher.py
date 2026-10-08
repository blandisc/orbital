"""Lanzamiento de procesos y URIs de forma multiplataforma (Windows / SteamOS / Linux)."""

from __future__ import annotations

import logging
import os
import shutil
import subprocess
import sys
import threading
import time
from collections.abc import Callable
from dataclasses import dataclass, field

log = logging.getLogger(__name__)

# on_exit(item_id, title, segundos_jugados)
ExitCallback = Callable[[str, str, float], None]


@dataclass
class Running:
    item_id: str
    title: str
    process: subprocess.Popen | None  # None cuando se lanzó vía URI (Steam, Stremio)
    started: float = field(default_factory=time.time)


def steam_running_appid() -> int | None:
    """AppID del juego de Steam en ejecución (0 = ninguno). None si no se puede saber."""
    if sys.platform != "win32":
        return None
    try:
        import winreg  # type: ignore[import-not-found]

        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, r"Software\Valve\Steam") as key:
            value, _ = winreg.QueryValueEx(key, "RunningAppID")
            return int(value)
    except (OSError, ValueError):
        return None


class Launcher:
    """Lanza juegos/apps, sabe cuándo terminan y avisa (para volver a Orbital y medir tiempo)."""

    STEAM_START_TIMEOUT = 120  # s que esperamos a que Steam marque el juego como iniciado
    POLL = 2.0

    def __init__(self, on_exit: ExitCallback | None = None) -> None:
        self._lock = threading.Lock()
        self.current: Running | None = None
        self.on_exit = on_exit

    def open_uri(self, uri: str) -> None:
        log.info("Abriendo URI %s", uri)
        if sys.platform == "win32":
            os.startfile(uri)  # type: ignore[attr-defined]
        elif sys.platform == "darwin":
            subprocess.Popen(["open", uri])
        else:
            opener = shutil.which("xdg-open") or shutil.which("gio")
            if not opener:
                raise RuntimeError("No se encontró xdg-open para abrir " + uri)
            cmd = [opener, "open", uri] if opener.endswith("gio") else [opener, uri]
            subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def run(self, argv: list[str], cwd: str | None = None) -> subprocess.Popen:
        log.info("Ejecutando %s", argv)
        kwargs: dict = {"cwd": cwd, "stdout": subprocess.DEVNULL, "stderr": subprocess.DEVNULL}
        if sys.platform == "win32":
            kwargs["creationflags"] = subprocess.CREATE_NEW_PROCESS_GROUP  # type: ignore[attr-defined]
        else:
            kwargs["start_new_session"] = True
        return subprocess.Popen(argv, **kwargs)

    def track(self, item_id: str, title: str, process: subprocess.Popen | None,
              steam_appid: int | None = None) -> None:
        running = Running(item_id, title, process)
        with self._lock:
            self.current = running
        if process is not None:
            threading.Thread(target=self._watch_process, args=(running,), daemon=True).start()
        elif steam_appid and steam_running_appid() is not None:
            threading.Thread(target=self._watch_steam, args=(running, steam_appid), daemon=True).start()

    def _watch_process(self, running: Running) -> None:
        running.process.wait()
        self._finished(running)

    def _watch_steam(self, running: Running, appid: int) -> None:
        deadline = time.time() + self.STEAM_START_TIMEOUT
        while steam_running_appid() != appid:
            if time.time() > deadline or self.current is not running:
                return  # no llegó a arrancar o ya se abrió otra cosa
            time.sleep(self.POLL)
        running.started = time.time()
        while steam_running_appid() == appid:
            time.sleep(self.POLL)
        self._finished(running)

    def _finished(self, running: Running) -> None:
        with self._lock:
            if self.current is running:
                self.current = None
        elapsed = time.time() - running.started
        log.info("%s terminó tras %.0f s", running.title, elapsed)
        if self.on_exit:
            try:
                self.on_exit(running.item_id, running.title, elapsed)
            except Exception:  # noqa: BLE001 - un fallo aquí no debe tumbar el hilo vigilante
                log.exception("Error en on_exit")

    def status(self) -> dict | None:
        with self._lock:
            cur = self.current
            if cur is None:
                return None
            if cur.process is not None and cur.process.poll() is not None:
                self.current = None
                return None
            return {"id": cur.item_id, "title": cur.title, "managed": cur.process is not None,
                    "started": cur.started}

    def stop(self) -> bool:
        """Cierra el proceso lanzado por Orbital. Devuelve False si no hay nada que cerrar."""
        with self._lock:
            cur = self.current
        if cur is None or cur.process is None or cur.process.poll() is not None:
            return False
        cur.process.terminate()
        try:
            cur.process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            cur.process.kill()
        return True
