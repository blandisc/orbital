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
    runner: str | None = None  # "Eden", "Ryujinx"... para preguntar "¿Cerrar…?"
    exe: str | None = None  # apps de instancia única (Stremio): se vigila el ejecutable, no el proceso


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
            if argv and argv[0].lower().endswith((".cmd", ".bat")):
                # Un .cmd (launch-eden.cmd) abriría una consola negra encima de Orbital.
                kwargs["creationflags"] |= subprocess.CREATE_NO_WINDOW  # type: ignore[attr-defined]
        else:
            kwargs["start_new_session"] = True
        return subprocess.Popen(argv, **kwargs)

    def track(self, item_id: str, title: str, process: subprocess.Popen | None,
              steam_appid: int | None = None, runner: str | None = None) -> None:
        running = Running(item_id, title, process, runner=runner)
        with self._lock:
            self.current = running
        if process is not None:
            threading.Thread(target=self._watch_process, args=(running,), daemon=True).start()
        elif steam_appid and steam_running_appid() is not None:
            threading.Thread(target=self._watch_steam, args=(running, steam_appid), daemon=True).start()

    EXE_START_TIMEOUT = 30  # s para que aparezca el ejecutable vigilado

    def track_exe(self, item_id: str, title: str, exe: str, runner: str | None = None) -> None:
        """Para apps de instancia única: si ya estaba abierta, el proceso que lanzamos le pasa el
        enlace y termina al instante. Lo fiable es vigilar que su ejecutable siga existiendo."""
        running = Running(item_id, title, None, runner=runner, exe=exe)
        with self._lock:
            self.current = running
        threading.Thread(target=self._watch_exe, args=(running,), daemon=True).start()

    def _watch_exe(self, running: Running) -> None:
        from . import windows

        deadline = time.time() + self.EXE_START_TIMEOUT
        while not windows.pids_by_exe(running.exe):
            if self.current is not running:
                return
            if time.time() > deadline:
                with self._lock:
                    if self.current is running:
                        self.current = None
                return
            time.sleep(self.POLL / 2)
        while windows.pids_by_exe(running.exe):
            if self.current is not running:
                return  # se abrió otra cosa: ya no es lo que estamos midiendo
            time.sleep(self.POLL)
        self._finished(running)

    def _watch_process(self, running: Running) -> None:
        running.process.wait()
        self._finished(running)

    def _watch_steam(self, running: Running, appid: int) -> None:
        deadline = time.time() + self.STEAM_START_TIMEOUT
        while steam_running_appid() != appid:
            if self.current is not running:
                return  # ya se abrió otra cosa
            if time.time() > deadline:
                # No llegó a arrancar: que no quede "En curso" para siempre.
                with self._lock:
                    if self.current is running:
                        self.current = None
                log.info("%s no arrancó en %d s; deja de estar en curso", running.title, self.STEAM_START_TIMEOUT)
                return
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
            return {"id": cur.item_id, "title": cur.title, "managed": cur.process is not None or cur.exe is not None,
                    "started": cur.started, "runner": cur.runner,
                    "pid": cur.process.pid if cur.process is not None else _exe_pid(cur.exe)}

    def stop(self, force: bool = False) -> bool:
        """Cierra el proceso lanzado por Orbital. Devuelve False si no hay nada que cerrar.

        `force`: ya lo confirmaste en Orbital, así que se cierra de inmediato. Sin esto, algunos
        emuladores (Eden con "confirmar al detener") abren su propio "¿Seguro?" con el mando a medias.
        """
        with self._lock:
            cur = self.current
        if cur is not None and cur.exe and sys.platform == "win32":
            subprocess.run(["taskkill", "/IM", cur.exe, "/T", "/F"], capture_output=True,
                           creationflags=subprocess.CREATE_NO_WINDOW)  # type: ignore[attr-defined]
            return True
        if cur is None or cur.process is None or cur.process.poll() is not None:
            return False
        if sys.platform == "win32":
            # terminate() solo cierra el proceso directo: con un .cmd (launch-eden.cmd) o un
            # emulador que abre hijos, el juego seguiría abierto. taskkill /T cierra el árbol,
            # primero pidiendo cerrar las ventanas y, si no responden, a la fuerza.
            _taskkill(cur.process.pid, force=force)
            try:
                cur.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                _taskkill(cur.process.pid, force=True)
            return True
        cur.process.terminate()
        try:
            cur.process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            cur.process.kill()
        return True


def _exe_pid(exe: str | None) -> int | None:
    if not exe:
        return None
    from . import windows

    pids = windows.pids_by_exe(exe)
    return min(pids) if pids else None


def _taskkill(pid: int, force: bool = False) -> None:
    cmd = ["taskkill", "/PID", str(pid), "/T"] + (["/F"] if force else [])
    subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                   creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
