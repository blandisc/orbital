"""yt-dlp: el programa que le enseña a mpv a abrir un video de YouTube (los tráilers y, después, la sección de YouTube).

Orbital lo baja solo de los lanzamientos oficiales (github.com/yt-dlp/yt-dlp) a `%LOCALAPPDATA%\\orbital\\tools`, comprueba su
huella SHA-256 contra la lista que publica el mismo lanzamiento y lo mantiene al día: YouTube cambia seguido y una versión
vieja deja de abrir videos. Revisa al rato de arrancar y cada 12 h, y si falta cuando se pide un tráiler lo baja en ese
momento. Un yt-dlp ya instalado en el sistema (en el PATH) se usa si Orbital no tiene el suyo.
"""

from __future__ import annotations

import hashlib
import json
import logging
import os
import re
import threading
import time
import urllib.request
from collections.abc import Callable
from pathlib import Path
from shutil import which

from .emulator_updates import USER_AGENT, InstallError, download, http_get_json
from .net import NET_ERRORS

log = logging.getLogger(__name__)

REPO = "yt-dlp/yt-dlp"
EXE_NAME = "yt-dlp.exe"
SUMS_NAME = "SHA2-256SUMS"
MANIFEST = "yt-dlp.json"
CHECK_EVERY = 12 * 3600
MAX_DOWNLOAD = 80 * 1024 * 1024  # el .exe pesa ~18 MB
YOUTUBE_ID = re.compile(r"^[A-Za-z0-9_-]{11}$")


class YtDlpError(Exception):
    """No se pudo tener yt-dlp listo (el mensaje se le enseña a la persona)."""


def tools_dir() -> Path:
    return Path(os.environ.get("LOCALAPPDATA") or Path.home() / ".local" / "state") / "orbital" / "tools"


def watch_url(video: str) -> str:
    """La dirección que mpv abre para ese video. ValueError si no parece un id de YouTube."""
    if not YOUTUBE_ID.match(video or ""):
        raise ValueError("Ese no es un video de YouTube")
    return f"https://www.youtube.com/watch?v={video}"


def video_format(audio: str = "en", height: int = 1080) -> str:
    """Lo que yt-dlp elige: video hasta `height` y, si el video trae doblajes (YouTube los reparte en varias pistas), el
    audio en tu idioma; si no lo trae, el original."""
    wanted = f"[language^={audio}]" if re.fullmatch(r"[a-z]{2,3}", audio or "") and audio != "en" else ""
    best_audio = f"(ba{wanted}/ba)" if wanted else "ba"
    return f"bv*[height<={height}]+{best_audio}/b[height<={height}]/b"


def parse_sums(text: str, name: str = EXE_NAME) -> str | None:
    """La huella SHA-256 de `name` en un SHA2-256SUMS («<hex>  yt-dlp.exe»)."""
    for line in text.splitlines():
        parts = line.split()
        if len(parts) == 2 and parts[1].lstrip("*") == name and re.fullmatch(r"[0-9a-fA-F]{64}", parts[0]):
            return parts[0].lower()
    return None


def sha256_of(path: Path) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        while chunk := handle.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def http_get_text(url: str, timeout: float = 15) -> str:
    if not url.startswith("https://"):
        raise InstallError("Esa descarga no es segura (no es https).")
    with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": USER_AGENT}), timeout=timeout) as res:
        return res.read(1024 * 64).decode("utf-8", "replace")


class YtDlp:
    """Dónde está yt-dlp y cómo tenerlo al día. `get_json`, `get_text` y `fetch` se cambian en las pruebas (sin internet)."""

    def __init__(self, folder: Path | None = None, *, get_json: Callable[[str], object] | None = None,
                 get_text: Callable[[str], str] | None = None, fetch: Callable[[str, Path], Path] | None = None) -> None:
        self.folder = folder
        self.get_json = get_json or (lambda url: http_get_json(url))
        self.get_text = get_text or (lambda url: http_get_text(url))
        self.fetch = fetch or (lambda url, dest: download(url, dest, limit=MAX_DOWNLOAD))
        self._installing = threading.Lock()
        self._stop = threading.Event()

    @property
    def dir(self) -> Path:
        return self.folder or tools_dir()

    @property
    def exe(self) -> Path:
        return self.dir / EXE_NAME

    def path(self) -> str | None:
        """El yt-dlp que se usa: el de Orbital o, si no hay, el del sistema."""
        if self.exe.is_file():
            return str(self.exe)
        return which("yt-dlp")

    def version(self) -> str | None:
        """La versión que bajó Orbital (la guarda al instalar)."""
        try:
            data = json.loads((self.dir / MANIFEST).read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return None
        return data.get("version") if isinstance(data, dict) and isinstance(data.get("version"), str) else None

    def latest(self) -> tuple[str, str, str]:
        """(versión, dirección del .exe, dirección de las huellas) del último lanzamiento. YtDlpError si no se pudo saber."""
        try:
            data = self.get_json(f"https://api.github.com/repos/{REPO}/releases/latest")
            assets = {a["name"]: a["browser_download_url"] for a in data.get("assets") or [] if isinstance(a, dict)}  # type: ignore[union-attr]
            return str(data["tag_name"]), assets[EXE_NAME], assets[SUMS_NAME]  # type: ignore[index]
        except (*NET_ERRORS, KeyError, TypeError, AttributeError) as exc:
            raise YtDlpError("No pude buscar yt-dlp (revisa tu conexión).") from exc

    def install(self) -> str:
        """Baja el último yt-dlp, comprueba su huella y lo deja en su lugar. Devuelve su versión."""
        with self._installing:
            version, exe_url, sums_url = self.latest()
            if self.exe.is_file() and self.version() == version:
                return version
            part = self.dir / (EXE_NAME + ".new")
            try:
                self.dir.mkdir(parents=True, exist_ok=True)
                expected = parse_sums(self.get_text(sums_url))
                if expected is None:
                    raise YtDlpError("No pude comprobar la descarga de yt-dlp.")
                self.fetch(exe_url, part)
                if sha256_of(part) != expected:
                    raise YtDlpError("La descarga de yt-dlp llegó dañada; no la instalé.")
                try:
                    os.replace(part, self.exe)
                except PermissionError as exc:  # se está usando (abriendo un video): se queda el de antes
                    raise YtDlpError("yt-dlp se está usando; lo actualizo después.") from exc
            except (*NET_ERRORS, InstallError) as exc:
                raise YtDlpError(str(exc) if isinstance(exc, InstallError) else "No pude bajar yt-dlp (revisa tu conexión).") from exc
            finally:
                part.unlink(missing_ok=True)
            (self.dir / MANIFEST).write_text(json.dumps({"version": version, "installed_at": time.strftime("%Y-%m-%d %H:%M")}),
                                             encoding="utf-8")
            log.info("yt-dlp %s instalado", version)
            return version

    def ensure(self) -> str:
        """El yt-dlp listo para usar; si no hay ninguno, lo baja ahora. YtDlpError en palabras si no se puede."""
        found = self.path()
        if found:
            return found
        self.install()
        found = self.path()
        if not found:
            raise YtDlpError("No pude dejar yt-dlp listo.")
        return found

    def update(self) -> str | None:
        """Una vuelta de mantenimiento: baja la versión nueva (o la primera). Devuelve la versión instalada, o None si ya
        estaba al día. Nunca lanza: un tropiezo se anota y se reintenta en la próxima vuelta."""
        try:
            before = self.version() if self.exe.is_file() else None
            version = self.install()
        except YtDlpError as exc:
            log.info("yt-dlp: %s", exc)
            return None
        return version if version != before else None

    def start(self, first_delay: float = 120) -> None:
        """Lo deja al día al rato de arrancar y cada 12 h (en segundo plano)."""
        def loop() -> None:
            wait = first_delay
            while not self._stop.wait(wait):
                try:
                    self.update()
                except Exception:  # noqa: BLE001 - nunca tumba a Orbital
                    log.exception("yt-dlp")
                wait = CHECK_EVERY

        threading.Thread(target=loop, daemon=True, name="yt-dlp").start()

    def stop(self) -> None:
        self._stop.set()
