"""Actualizaciones de los emuladores: cuál tiene versión nueva y, si se puede, instalarla.

Cada emulador conocido sabe dónde publica sus versiones (GitHub, la página de Dolphin, el Forgejo de Eden…). La versión
instalada sale del propio .exe (su recurso de versión de Windows) o, si Orbital la instaló, de `.orbital-version.json`
junto al .exe. Si no hay forma de saberla (Dolphin, Eden, Xenia no la ponen), se compara la fecha del .exe con la de la
última versión: «parece que hay una más nueva».

Instalar solo se ofrece cuando la versión viene en un .zip con el .exe adentro (xemu, PPSSPP, shadPS4, Cemu,
melonDS): se baja, se guarda lo que se va a reemplazar en `.orbital-respaldo/` (si algo falla, se regresa) y se
descomprime encima, sin tocar partidas ni ajustes (solo se escriben los archivos que trae el .zip). Los demás (vienen
en .7z o con instalador) se avisan con su página para bajarlos a mano.

El modo («avisar», «auto» o «nunca») es un ajuste (Ajustes › Mantenimiento › Emuladores). En automático, Orbital revisa
al arrancar y cada 12 h, e instala solo lo que puede instalar y nunca con un juego abierto.
"""

from __future__ import annotations

import json
import logging
import os
import re
import shutil
import threading
import time
import urllib.request
import zipfile
from collections.abc import Callable
from dataclasses import dataclass, field
from datetime import UTC, datetime
from pathlib import Path

from .net import NET_ERRORS, read_json

log = logging.getLogger(__name__)

MODES = ("avisar", "auto", "nunca")
CHECK_EVERY = 12 * 3600  # en automático; al pedirlo a mano se revisa siempre
CACHE_FOR = 3600  # una revisión reciente se reusa (GitHub deja 60 consultas por hora sin cuenta)
MAX_DOWNLOAD = 700 * 1024 * 1024
MANIFEST = ".orbital-version.json"
BACKUP = ".orbital-respaldo"  # la carpeta empieza con punto: la detección de emuladores no entra ahí
USER_AGENT = "Orbital/0.1 (+https://github.com/blandisc/orbital; actualizaciones de emuladores)"
DATE_SLACK = 3 * 86400  # sin número de versión: el .exe se da por viejo si es 3 días más antiguo que la última


@dataclass(frozen=True)
class Source:
    id: str
    name: str
    exe_names: tuple[str, ...]
    kind: str  # "github" | "dolphin" | "forgejo" | "gitlab"
    repo: str
    page: str  # dónde bajarla a mano
    asset: str | None = None  # el .zip de Windows x64 (regex); None: solo se avisa
    dated: bool = False  # sin número de versión que comparar (versión «latest» o un commit): por fecha


SOURCES: tuple[Source, ...] = (
    Source("xemu", "xemu", ("xemu.exe",), "github", "xemu-project/xemu", "https://xemu.app/#download",
           r"^xemu-[\d.]+-windows-x86_64\.zip$"),
    Source("ppsspp", "PPSSPP", ("ppssppwindows64.exe",), "github", "hrydgard/ppsspp", "https://www.ppsspp.org/download/",
           r"^PPSSPP-v[\d.]+-Windows-x64\.zip$"),
    Source("shadps4", "shadPS4", ("shadps4.exe",), "github", "shadps4-emu/shadPS4", "https://shadps4.net/",
           r"^shadps4-win64-sdl-.*\.zip$"),
    Source("cemu", "Cemu", ("cemu.exe",), "github", "cemu-project/Cemu", "https://cemu.info/", r"^cemu-[\d.]+-windows-x64\.zip$"),
    Source("melonds", "melonDS", ("melonds.exe",), "github", "melonDS-emu/melonDS", "https://melonds.kuribo64.net/",
           r"^melonDS-[\d.]+-windows-x86_64\.zip$"),
    Source("mgba", "mGBA", ("mgba.exe",), "github", "mgba-emu/mgba", "https://mgba.io/downloads.html"),
    Source("pcsx2", "PCSX2", ("pcsx2-qt.exe",), "github", "PCSX2/pcsx2", "https://pcsx2.net/downloads"),
    Source("duckstation", "DuckStation", ("duckstation-qt-x64-releaseltcg.exe",), "github", "stenzek/duckstation",
           "https://www.duckstation.org/", dated=True),
    Source("xenia", "Xenia Canary", ("xenia_canary.exe",), "github", "xenia-canary/xenia-canary-releases",
           "https://github.com/xenia-canary/xenia-canary-releases/releases", dated=True),
    Source("dolphin", "Dolphin", ("dolphin.exe",), "dolphin", "https://dolphin-emu.org/update/latest/beta/",
           "https://dolphin-emu.org/download/", dated=True),
    Source("eden", "Eden", ("eden.exe",), "forgejo", "https://git.eden-emu.dev/api/v1/repos/eden-emu/eden/releases?limit=1",
           "https://eden-emu.dev/", dated=True),
    Source("ryujinx", "Ryujinx", ("ryujinx.exe",), "gitlab", "https://git.ryujinx.app/api/v4/projects/ryubing%2Fryujinx/releases?per_page=1",
           "https://ryujinx.app/download"),
)


@dataclass
class Release:
    version: str
    date: float | None  # cuándo salió (epoch)
    asset_url: str | None = None
    asset_size: int | None = None
    notes_url: str | None = None


@dataclass
class Status:
    source: Source
    exe: Path
    installed: str | None
    latest: Release | None = None
    update: bool = False
    likely: bool = False  # sin número de versión: lo dice la fecha
    error: str | None = None
    extra: dict = field(default_factory=dict)

    @property
    def can_install(self) -> bool:
        return bool(self.update and self.source.asset and self.latest and self.latest.asset_url)

    def public(self) -> dict:
        return {"id": self.source.id, "name": self.source.name, "installed": self.installed,
                "latest": self.latest.version if self.latest else None, "update": self.update, "likely": self.likely,
                "can_install": self.can_install, "page": self.source.page, "error": self.error,
                "folder": str(self.exe.parent)}


# --- versiones ----------------------------------------------------------------------------------------------------------
def version_tuple(text: str | None) -> tuple[int, ...]:
    """«v.0.20.0» → (0, 20, 0); «0.10.5.0» → (0, 10, 5); «1.3.3+e2143d4» → (1, 3, 3). Sin números: ()."""
    numbers = [int(n) for n in re.findall(r"\d+", (text or "").split("+", 1)[0])]
    while len(numbers) > 1 and numbers[-1] == 0:
        numbers.pop()
    return tuple(numbers)


def file_version(exe: Path) -> str | None:
    """La versión que trae el .exe (Propiedades › Detalles en Windows). None si no la trae."""
    if os.name != "nt":
        return None
    import ctypes
    from ctypes import wintypes

    try:
        api = ctypes.windll.version
        size = api.GetFileVersionInfoSizeW(str(exe), None)
        if not size:
            return None
        buf = ctypes.create_string_buffer(size)
        if not api.GetFileVersionInfoW(str(exe), 0, size, buf):
            return None
        ptr, length = ctypes.c_void_p(), wintypes.UINT()
        if not api.VerQueryValueW(buf, "\\VarFileInfo\\Translation", ctypes.byref(ptr), ctypes.byref(length)) or not length.value:
            return None
        lang, page = ctypes.cast(ptr, ctypes.POINTER(ctypes.c_ushort * 2)).contents
        for key in ("ProductVersion", "FileVersion"):
            query = f"\\StringFileInfo\\{lang:04x}{page:04x}\\{key}"
            if api.VerQueryValueW(buf, query, ctypes.byref(ptr), ctypes.byref(length)) and length.value:
                value = ctypes.wstring_at(ptr, length.value - 1).strip()
                if version_tuple(value):  # «mgba» (el ProductVersion de mGBA) no es una versión
                    return value
    except (OSError, AttributeError, ValueError):
        return None
    return None


def manifest_version(exe: Path) -> str | None:
    try:
        data = json.loads((exe.parent / MANIFEST).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None
    if data.get("exe", exe.name).lower() != exe.name.lower():
        return None
    return data.get("version") if isinstance(data.get("version"), str) else None


def installed_version(exe: Path, version_of: Callable[[Path], str | None] = file_version) -> str | None:
    return version_of(exe) or manifest_version(exe)


def _epoch(text: str | None) -> float | None:
    if not text:
        return None
    try:
        return datetime.fromisoformat(text.replace("Z", "+00:00")).astimezone(UTC).timestamp()
    except ValueError:
        return None


# --- de dónde sale la última versión ------------------------------------------------------------------------------------
def http_get_json(url: str, timeout: float = 15):
    headers = {"User-Agent": USER_AGENT, "Accept": "application/json"}
    if "api.github.com" in url:
        headers["Accept"] = "application/vnd.github+json"
    with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=timeout) as res:
        return read_json(res, timeout=timeout)


def latest_release(source: Source, get_json=http_get_json) -> Release:
    """La última versión publicada (lanza NET_ERRORS o ValueError si no se pudo saber)."""
    if source.kind == "github":
        data = get_json(f"https://api.github.com/repos/{source.repo}/releases/latest")
        asset = None
        if source.asset:
            asset = next((a for a in data.get("assets") or [] if re.search(source.asset, a.get("name") or "", re.IGNORECASE)), None)
        published = _epoch(data.get("published_at"))
        if source.dated:  # «latest» o un commit: lo que cuenta es la fecha (y los archivos, que se resuben)
            dates = [_epoch(a.get("updated_at")) for a in data.get("assets") or []]
            published = max([d for d in dates if d] or [published or 0]) or None
        return Release(str(data.get("tag_name") or ""), published, asset and asset.get("browser_download_url"),
                       asset and asset.get("size"), data.get("html_url"))
    if source.kind == "dolphin":
        data = get_json(source.repo)
        return Release(str(data.get("shortrev") or ""), _epoch(data.get("date")))
    if source.kind in ("forgejo", "gitlab"):
        data = get_json(source.repo)
        first = data[0] if isinstance(data, list) and data else {}
        return Release(str(first.get("tag_name") or ""), _epoch(first.get("published_at") or first.get("released_at")
                                                                or first.get("created_at")))
    raise ValueError(f"fuente desconocida: {source.kind}")


def compare(source: Source, exe: Path, installed: str | None, latest: Release) -> tuple[bool, bool]:
    """(hay una más nueva, solo por la fecha)."""
    if not source.dated and installed and version_tuple(installed) and version_tuple(latest.version):
        return version_tuple(latest.version) > version_tuple(installed), False
    try:
        mtime = exe.stat().st_mtime
    except OSError:
        return False, True
    return bool(latest.date and mtime + DATE_SLACK < latest.date), True


def source_for(exe: Path) -> Source | None:
    name = exe.name.lower()
    return next((s for s in SOURCES if name in s.exe_names), None)


def real_exe(path: Path) -> Path:
    """El .exe del emulador aunque se abra con un .cmd propio (launch-eden.cmd junto a eden.exe)."""
    if source_for(path) is not None:
        return path
    for source in SOURCES:
        for name in source.exe_names:
            for candidate in (path.parent / name, *path.parent.glob(name)):
                if candidate.is_file():
                    return candidate
    return path


# --- instalar ---------------------------------------------------------------------------------------------------------
class InstallError(Exception):
    """No se pudo instalar (el mensaje se le enseña a la persona)."""


def download(url: str, dest: Path, timeout: float = 30, limit: int = MAX_DOWNLOAD) -> Path:
    if not url.startswith("https://"):
        raise InstallError("Esa descarga no es segura (no es https).")
    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp = dest.with_suffix(dest.suffix + ".part")
    size = 0
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": "application/octet-stream"})
    with urllib.request.urlopen(req, timeout=timeout) as res, open(tmp, "wb") as out:
        while chunk := res.read(1024 * 1024):
            size += len(chunk)
            if size > limit:
                raise InstallError("La descarga es demasiado grande.")
            out.write(chunk)
    tmp.replace(dest)
    return dest


def _members(archive: zipfile.ZipFile, exe_name: str) -> tuple[str, list[zipfile.ZipInfo]]:
    """El prefijo de carpeta donde viene el .exe dentro del .zip («», o «PPSSPP-v1.20/») y lo que hay que sacar."""
    infos = [i for i in archive.infolist() if not i.is_dir()]
    exe = next((i for i in infos if Path(i.filename).name.lower() == exe_name.lower()), None)
    if exe is None:
        raise InstallError(f"El .zip no trae {exe_name}.")
    prefix = exe.filename[: len(exe.filename) - len(Path(exe.filename).name)]
    return prefix, [i for i in infos if i.filename.startswith(prefix)]


def _safe_target(folder: Path, relative: str) -> Path:
    target = (folder / relative).resolve()
    if folder.resolve() not in target.parents:
        raise InstallError("El .zip trae rutas raras; no lo instalé.")
    return target


def install_zip(zip_path: Path, exe: Path, version: str) -> None:
    """Descomprime encima de la carpeta del emulador. Antes guarda en `.orbital-respaldo/` cada archivo que se va a
    reemplazar; si algo falla a medias, los regresa."""
    folder = exe.parent
    backup = folder / BACKUP
    try:
        archive = zipfile.ZipFile(zip_path)
    except (zipfile.BadZipFile, OSError) as exc:
        raise InstallError("La descarga llegó dañada.") from exc
    with archive:
        prefix, members = _members(archive, exe.name)
        plan = [(m, _safe_target(folder, m.filename[len(prefix):])) for m in members if m.filename[len(prefix):]]
        shutil.rmtree(backup, ignore_errors=True)  # solo se guarda el último respaldo
        written: list[Path] = []
        saved: list[tuple[Path, Path]] = []
        try:
            for _member, target in plan:
                if target.is_file():
                    copy = backup / target.relative_to(folder)
                    copy.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(target, copy)
                    saved.append((copy, target))
            for member, target in plan:
                target.parent.mkdir(parents=True, exist_ok=True)
                with archive.open(member) as src, open(target, "wb") as out:
                    shutil.copyfileobj(src, out)
                written.append(target)
        except Exception as exc:
            for target in written:  # lo nuevo fuera…
                target.unlink(missing_ok=True)
            for copy, target in saved:  # …y lo de antes de regreso
                shutil.copy2(copy, target)
            if isinstance(exc, InstallError):
                raise
            raise InstallError(f"No pude escribir en {folder.name} ({type(exc).__name__}). Lo dejé como estaba.") from exc
    previous = installed_version(exe)
    (folder / MANIFEST).write_text(json.dumps({"exe": exe.name, "version": version, "previous": previous,
                                               "installed_at": time.strftime("%Y-%m-%d %H:%M")}), encoding="utf-8")


# --- el servicio ------------------------------------------------------------------------------------------------------
class EmulatorUpdates:
    """Revisa (con caché) e instala. `emulator_exes()` da los .exe de los emuladores que tienes; `busy()` dice si hay un
    juego abierto (no se instala nada encima); `mode()` lee el ajuste; `notify(texto)` avisa en la tele."""

    def __init__(self, emulator_exes: Callable[[], list[Path]], *, mode: Callable[[], str], busy: Callable[[], bool],
                 notify: Callable[[str], None] = lambda text: None, cache_dir: Path | None = None,
                 get_json=None, fetch=None, version_of: Callable[[Path], str | None] | None = None,
                 clock: Callable[[], float] = time.time) -> None:
        self.emulator_exes, self.mode, self.busy, self.notify = emulator_exes, mode, busy, notify
        self.cache_dir = cache_dir
        # Se buscan al llamar (no al definir): las pruebas cambian http_get_json y download por unas sin internet.
        self.get_json = get_json or (lambda url: http_get_json(url))
        self.fetch = fetch or (lambda url, dest: download(url, dest))
        self.version_of = version_of or (lambda exe: file_version(exe))
        self.clock = clock
        self._lock = threading.Lock()
        self._installing = threading.Lock()
        self._last: tuple[float, list[Status]] | None = None
        self._stop = threading.Event()

    def _targets(self) -> list[tuple[Source, Path]]:
        seen: dict[str, tuple[Source, Path]] = {}
        for exe in self.emulator_exes():
            source = source_for(exe)
            if source and source.id not in seen:
                seen[source.id] = (source, exe)
        return list(seen.values())

    def check(self, force: bool = False) -> list[Status]:
        with self._lock:
            if not force and self._last and self.clock() - self._last[0] < CACHE_FOR:
                return self._last[1]
            result: list[Status] = []
            for source, exe in self._targets():
                status = Status(source, exe, installed_version(exe, self.version_of))
                try:
                    status.latest = latest_release(source, self.get_json)
                    status.update, status.likely = compare(source, exe, status.installed, status.latest)
                except (*NET_ERRORS, KeyError, TypeError) as exc:
                    status.error = "No pude revisar (sin conexión o el sitio no contestó)."
                    log.info("Actualizaciones: no pude revisar %s: %s", source.name, exc)
                result.append(status)
            self._last = (self.clock(), result)
            return result

    def summary(self, force: bool = False) -> dict:
        items = self.check(force)
        return {"mode": self.mode(), "checked_at": self._last[0] if self._last else None,
                "installing": self._installing.locked(), "items": [s.public() for s in items]}

    def install(self, source_id: str) -> str:
        """Instala la última versión de ese emulador. Devuelve el mensaje para la tele; lanza InstallError si no."""
        if self.busy():
            raise InstallError("Cierra el juego primero: no actualizo un emulador abierto.")
        if not self._installing.acquire(blocking=False):
            raise InstallError("Ya estoy actualizando otro emulador.")
        try:
            status = next((s for s in self.check() if s.source.id == source_id), None)
            if status is None:
                raise InstallError("No tienes ese emulador.")
            if not status.update:
                return f"{status.source.name} ya está al día."
            if not status.can_install:
                raise InstallError(f"{status.source.name} se actualiza a mano: {status.source.page}")
            cache = self.cache_dir or Path(os.environ.get("LOCALAPPDATA") or Path.home()) / "orbital" / "cache" / "emulator-updates"
            name = re.sub(r"[^\w.-]", "_", f"{status.source.id}-{status.latest.version}.zip")
            try:
                cache.mkdir(parents=True, exist_ok=True)
                zip_path = self.fetch(status.latest.asset_url, cache / name)
            except NET_ERRORS as exc:
                raise InstallError("No pude bajar la versión nueva (revisa tu conexión).") from exc
            install_zip(zip_path, status.exe, status.latest.version)
            Path(zip_path).unlink(missing_ok=True)
            log.info("Actualizaciones: %s %s → %s", status.source.name, status.installed, status.latest.version)
            self._last = None  # la próxima revisión ya ve la versión nueva
            return f"{status.source.name} actualizado a {status.latest.version}."
        finally:
            self._installing.release()

    def run_auto(self) -> list[str]:
        """Una vuelta del modo automático: instala lo que se puede instalar solo. Devuelve lo que hizo."""
        mode = self.mode()
        if mode == "nunca":
            return []
        done: list[str] = []
        statuses = self.check(force=True)
        if mode == "avisar":  # solo lo seguro (con número de versión): «parece más nueva» no merece un aviso
            pending = [s.source.name for s in statuses if s.update and not s.likely]
            if pending:
                self.notify(f"Hay versión nueva de {', '.join(pending)} (Ajustes › Mantenimiento › Emuladores).")
            return []
        for status in statuses:
            if not status.can_install or self.busy():
                continue
            try:
                done.append(self.install(status.source.id))
            except InstallError as exc:
                log.info("Actualizaciones: %s", exc)
        if done:
            self.notify(" ".join(done))
        return done

    def start(self, first_delay: float = 90) -> None:
        """Revisa sola al rato de arrancar y cada 12 h (en segundo plano)."""
        def loop() -> None:
            wait = first_delay
            while not self._stop.wait(wait):
                try:
                    self.run_auto()
                except Exception:  # noqa: BLE001 - nunca tumba a Orbital
                    log.exception("Actualizaciones de emuladores")
                wait = CHECK_EVERY

        threading.Thread(target=loop, daemon=True, name="emulator-updates").start()

    def stop(self) -> None:
        self._stop.set()
