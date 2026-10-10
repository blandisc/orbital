"""Lanzamiento de procesos y URIs de forma multiplataforma (Windows / SteamOS / Linux)."""

from __future__ import annotations

import logging
import os
import re
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
    # El proceso lanzado ya terminó pero el juego sigue en otro (xemu se relanza a sí mismo; un
    # lanzador abre el juego y se cierra): se vigilan estos pids en su lugar.
    followers: set[int] = field(default_factory=set)


def redact(arg: str) -> str:
    """Para el registro: las URLs de video llevan claves (Real-Debrid va en la ruta de Torrentio) y
    los enlaces al reproductor de Stremio las llevan codificadas. Solo queda el sitio."""
    text = str(arg)
    if text.startswith("stremio:///player/"):
        return "stremio:///player/…"
    match = re.match(r"(https?://[^/\s]+)/\S+", text)
    return f"{match.group(1)}/…" if match else text


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
        log.info("Abriendo URI %s", redact(uri))
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
        log.info("Ejecutando %s", [redact(a) for a in argv])
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

    HANDOFF_GRACE = 1.5  # s tras cerrarse el proceso para ver si el juego siguió en otro

    def process_list(self) -> dict[int, tuple[str, int]]:
        from . import windows
        return windows.processes()

    def _watch_process(self, running: Running) -> None:
        """Vigila el proceso y, si se cierra, a quien tomó su lugar: hijos que sigan vivos (un
        lanzador que abre el juego y termina) o una copia nueva del mismo programa (xemu se relanza
        a sí mismo a los 2 s). Sin esto Orbital salía encima del juego como si se hubiera cerrado."""
        pid = running.process.pid
        snapshot = self.process_list()
        exe = snapshot.get(pid, ("", 0))[0]
        if exe in NOT_RELAUNCH:
            exe = ""  # otro cmd.exe abierto luego por cualquier cosa no es "el juego relanzado"
        before = {p for p, (name, _) in snapshot.items() if exe and name == exe and p != pid}  # ya abiertos: no son nuestros
        family: dict[int, str] = {}  # descendientes vistos (pid -> ejecutable)
        while True:
            try:
                running.process.wait(timeout=self.POLL / 2)
                break
            except subprocess.TimeoutExpired:
                family.update(_descendants(self.process_list(), pid))
        deadline = time.monotonic() + self.HANDOFF_GRACE
        while True:
            if self.current is not running:
                return  # se abrió otra cosa: ya no es lo que estamos midiendo
            snapshot = self.process_list()
            alive = {p for p, name in family.items() if snapshot.get(p, ("",))[0] == name}
            relaunched = {p for p, (name, _) in snapshot.items() if exe and name == exe and p != pid and p not in before}
            followers = alive | relaunched
            for p in list(followers):  # y lo que ellos abran
                followers |= set(_descendants(snapshot, p))
            family.update({p: snapshot[p][0] for p in followers if p in snapshot})
            if followers:
                if not running.followers:
                    log.info("%s sigue abierto en otro proceso (%s)", running.title, sorted(followers))
                running.followers = followers
                time.sleep(self.POLL)
            elif time.monotonic() < deadline and not running.followers:
                time.sleep(.25)  # quizá el relevo aún no aparece
            else:
                break
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
            # Si el proceso terminó, quien decide si el juego sigue (en otro proceso) es el vigilante.
            if cur.process is not None and cur.process.poll() is not None:
                pid = min(cur.followers) if cur.followers else cur.process.pid
            else:
                pid = cur.process.pid if cur.process is not None else _exe_pid(cur.exe)
            return {"id": cur.item_id, "title": cur.title, "managed": cur.process is not None or cur.exe is not None,
                    "started": cur.started, "runner": cur.runner, "pid": pid}

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
        if cur is not None and cur.process is not None and cur.process.poll() is not None and cur.followers:
            for pid in sorted(cur.followers):  # el juego siguió en otro proceso: se cierra ese
                _taskkill(pid, force=force)
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


# Intérpretes y ayudantes de Windows: nunca son "el juego que siguió en otro proceso".
NOT_RELAUNCH = {"cmd.exe", "powershell.exe", "pwsh.exe", "conhost.exe", "python.exe", "pythonw.exe",
                "wscript.exe", "cscript.exe", "explorer.exe", "werfault.exe"}


def _descendants(snapshot: dict[int, tuple[str, int]], root: int) -> dict[int, str]:
    """Hijos, nietos… de `root` en una foto de procesos (pid -> ejecutable), sin consolas."""
    children: dict[int, list[int]] = {}
    for pid, (_, parent) in snapshot.items():
        children.setdefault(parent, []).append(pid)
    found, pending = {}, [root]
    while pending:
        for child in children.get(pending.pop(), []):
            if child not in found and child != root:
                found[child] = snapshot[child][0]
                pending.append(child)
    return {p: name for p, name in found.items() if name not in ("conhost.exe", "werfault.exe")}


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
