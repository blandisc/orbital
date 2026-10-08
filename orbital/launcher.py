"""Lanzamiento de procesos y URIs de forma multiplataforma (Windows / SteamOS / Linux)."""

from __future__ import annotations

import logging
import os
import shutil
import subprocess
import sys
import threading
from dataclasses import dataclass

log = logging.getLogger(__name__)


@dataclass
class Running:
    item_id: str
    title: str
    process: subprocess.Popen | None  # None cuando se lanzó vía URI (Steam, Stremio)


class Launcher:
    """Lanza juegos/apps y recuerda el último proceso para poder cerrarlo por voz."""

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self.current: Running | None = None

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

    def track(self, item_id: str, title: str, process: subprocess.Popen | None) -> None:
        with self._lock:
            self.current = Running(item_id, title, process)

    def status(self) -> dict | None:
        with self._lock:
            cur = self.current
            if cur is None:
                return None
            if cur.process is not None and cur.process.poll() is not None:
                self.current = None
                return None
            return {"id": cur.item_id, "title": cur.title, "managed": cur.process is not None}

    def stop(self) -> bool:
        """Cierra el proceso lanzado por Orbital. Devuelve False si no hay nada que cerrar."""
        with self._lock:
            cur, self.current = self.current, None
        if cur is None or cur.process is None or cur.process.poll() is not None:
            return False
        cur.process.terminate()
        try:
            cur.process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            cur.process.kill()
        return True
