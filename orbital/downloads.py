"""Descargas para ver sin internet (como Descargas del iPhone): una película o un episodio a la carpeta de videos de la
consola (Videos\\Orbital), para verlos en el avión o donde no haya red.

  * Qué se baja: tu copia de OneDrive si la hay; si no, una fuente directa de Real-Debrid, la de 1080p (se ve igual de
    bien en la pantalla de la Legion Go y pesa menos que la 4K), con el idioma de tus preferencias primero.
  * Una a la vez, en segundo plano, y se retoma donde iba si se corta (pide el resto con «Range»).
  * Lo descargado se ve con el reproductor de Orbital (mpv) directo del disco: sin internet no pasa nada.
  * Quitar una descarga borra su archivo (el que Orbital bajó, nada más).

El índice vive en la carpeta de descargas (descargas.json): si mueves la carpeta a otra máquina, viaja con ella.
"""

from __future__ import annotations

import json
import logging
import os
import re
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from collections.abc import Callable
from pathlib import Path

log = logging.getLogger(__name__)

CHUNK = 1 << 20  # 1 MB por lectura
PROGRESS_EVERY = 1.5  # s entre avisos de avance a la interfaz
TIMEOUT = 30
RETRIES = 3
VIDEO_EXTS = (".mkv", ".mp4", ".m4v", ".avi", ".mov", ".webm", ".ts")
INDEX_NAME = "descargas.json"
PREFERRED = ("1080p", "720p", "4K", "")  # el orden en que se elige la calidad para bajar


def default_dir() -> Path:
    return Path(os.environ.get("USERPROFILE") or Path.home()) / "Videos" / "Orbital"


def safe_name(text: str) -> str:
    """Un nombre de archivo válido en Windows («Dune: Parte dos» → «Dune - Parte dos»)."""
    text = re.sub(r"\s*:\s*", " - ", str(text or "").strip())
    text = re.sub(r'[<>"/\\|?*\x00-\x1f]', "", text).strip(" .")
    return (text or "Video")[:120]


def pick_source(sources: list, prefs_audio: str | None = None):
    """La fuente para bajar: tu OneDrive primero; luego directas (http, sin torrent), de 1080p si hay, el idioma
    de tus preferencias antes y nunca una grabación de cine ni un tráiler."""
    own = [s for s in sources if isinstance(s.stream, dict) and s.stream.get("onedrive")]
    if own:
        return own[0]
    direct = [s for s in sources if isinstance(s.stream, dict) and re.match(r"^https?://", str(s.stream.get("url") or ""), re.I)
              and not ({"CAM", "Tráiler"} & set(s.tags or []))]
    if not direct:
        return None

    def rank(s):
        res = PREFERRED.index(s.resolution) if s.resolution in PREFERRED else len(PREFERRED)
        lang = 0 if prefs_audio and prefs_audio in (s.languages or []) else 1
        return (lang, res, 0 if s.cached else 1)
    return sorted(direct, key=rank)[0]


def extension_for(url: str, release: str = "", content_type: str = "") -> str:
    for text in (urllib.parse.urlparse(url).path, release):
        ext = Path(str(text)).suffix.lower()
        if ext in VIDEO_EXTS:
            return ext
    return ".mp4" if "mp4" in content_type else ".mkv"


class Downloads:
    """La cola de descargas. `resolve(job) -> (url, release)` da la dirección del archivo al momento de bajarlo (las de
    Real-Debrid y OneDrive caducan); `publish(event)` avisa a la interfaz."""

    def __init__(self, folder: Path | None, resolve: Callable[[dict], tuple[str, str]], publish: Callable[[dict], None],
                 opener: Callable = urllib.request.urlopen, autostart: bool = True) -> None:
        self.folder = Path(folder) if folder else default_dir()
        self.resolve = resolve
        self.publish = publish
        self.opener = opener
        self._jobs: dict[str, dict] = {}
        self._lock = threading.Lock()
        self._save_lock = threading.Lock()  # una escritura del índice a la vez (comparten el .tmp)
        self._wake = threading.Event()
        self._cancel: set[str] = set()
        self._load()
        if autostart:
            threading.Thread(target=self._worker, name="descargas", daemon=True).start()

    # --- índice -------------------------------------------------------------------------------------------------------
    @property
    def index_path(self) -> Path:
        return self.folder / INDEX_NAME

    def _load(self) -> None:
        try:
            raw = json.loads(self.index_path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return
        for job in raw if isinstance(raw, list) else []:
            if isinstance(job, dict) and isinstance(job.get("id"), str):
                if job.get("status") == "downloading":
                    job["status"] = "queued"  # se cortó al cerrar Orbital: se retoma
                self._jobs[job["id"]] = job

    def _save(self) -> None:
        with self._save_lock:
            with self._lock:
                data = json.dumps(list(self._jobs.values()), ensure_ascii=False, indent=1)
            try:
                self.folder.mkdir(parents=True, exist_ok=True)
                tmp = self.index_path.with_suffix(".tmp")
                tmp.write_text(data, encoding="utf-8", errors="replace")  # un surrogate suelto no tumba el hilo
                tmp.replace(self.index_path)
            except OSError as exc:
                log.warning("No pude guardar la lista de descargas: %s", exc)

    # --- lo que pide la interfaz --------------------------------------------------------------------------------------
    def public(self, job: dict) -> dict:
        out = {k: job.get(k) for k in ("id", "kind", "meta_id", "video_id", "title", "detail", "poster", "status", "size",
                                        "done", "error", "added", "season", "episode", "quality")}
        out["progress"] = round(job["done"] / job["size"], 3) if job.get("size") else None
        return out

    def list(self) -> list[dict]:
        with self._lock:
            jobs = sorted(self._jobs.values(), key=lambda j: -(j.get("added") or 0))
        return [self.public(j) for j in jobs]

    def find(self, video_id: str) -> dict | None:
        with self._lock:
            return next((j for j in self._jobs.values() if j.get("video_id") == video_id), None)

    def add(self, kind: str, meta_id: str, video_id: str, title: str, *, detail: str = "", poster: str | None = None,
            season: int | None = None, episode: int | None = None) -> dict:
        if kind not in ("movie", "series") or not re.fullmatch(r"tt\d{1,12}(:\d{1,4}:\d{1,5})?", video_id or ""):
            raise ValueError("Video inválido")
        existing = self.find(video_id)
        if existing and existing.get("status") != "failed":
            return self.public(existing)
        job_id = re.sub(r"[^a-z0-9]+", "-", video_id.lower()).strip("-")
        name = safe_name(f"{title} - T{season}E{episode:02d}" if kind == "series" and season is not None and episode is not None else title)
        job = {"id": job_id, "kind": kind, "meta_id": meta_id, "video_id": video_id, "title": title, "detail": detail,
               "poster": poster, "season": season, "episode": episode, "status": "queued", "size": 0, "done": 0,
               "error": None, "added": time.time(), "name": name, "file": None, "quality": None}
        with self._lock:
            self._jobs[job_id] = job
            self._cancel.discard(job_id)
        self._save()
        self._wake.set()
        self.publish({"type": "downloads"})
        return self.public(job)

    def remove(self, job_id: str) -> bool:
        """Quita la descarga (y su archivo, el que bajó Orbital). Si se está bajando, se detiene."""
        with self._lock:
            job = self._jobs.pop(job_id, None)
            self._cancel.add(job_id)
        if not job:
            return False
        for path in (job.get("file"), job.get("partial")):
            if path and Path(path).parent == self.folder:
                try:
                    Path(path).unlink(missing_ok=True)
                except OSError as exc:
                    log.info("No pude quitar %s: %s", path, exc)
        self._save()
        self.publish({"type": "downloads"})
        return True

    def retry(self, job_id: str) -> bool:
        with self._lock:
            job = self._jobs.get(job_id)
            if not job or job.get("status") != "failed":
                return False
            job.update(status="queued", error=None)
            self._cancel.discard(job_id)
        self._save()
        self._wake.set()
        self.publish({"type": "downloads"})
        return True

    def file_for(self, video_id: str) -> Path | None:
        """El archivo ya bajado de ese video (None si no está completo o ya no existe)."""
        job = self.find(video_id)
        if job and job.get("status") == "done" and job.get("file") and Path(job["file"]).is_file():
            return Path(job["file"])
        return None

    # --- bajar ------------------------------------------------------------------------------------------------------
    def _next(self) -> dict | None:
        with self._lock:
            queued = sorted((j for j in self._jobs.values() if j.get("status") == "queued"), key=lambda j: j.get("added") or 0)
            if queued:
                queued[0]["status"] = "downloading"
                return queued[0]
        return None

    def _worker(self) -> None:
        while True:
            job = self._next()
            if not job:
                self._wake.wait(30)
                self._wake.clear()
                continue
            self.run(job)

    def run(self, job: dict) -> None:
        """Baja un trabajo (retoma lo que ya había). Deja su estado en «done» o «failed»."""
        self.publish({"type": "downloads"})
        try:
            url, release = self.resolve(job)
            if not url:
                raise ValueError("No encontré una fuente directa para bajar esto (las de torrent sin Real-Debrid no se pueden).")
            self._fetch(job, url, release)
            if job["id"] in self._cancel:
                return
            job.update(status="done", error=None)
            log.info("Descargado: %s (%s)", job["title"], job.get("file"))
            self.publish({"type": "toast", "tone": "success", "message": job["title"], "detail": "Listo para ver sin internet"})
        except Exception as exc:  # noqa: BLE001 - una descarga que falla no tumba la cola
            if job["id"] in self._cancel:
                return
            log.warning("No pude descargar %s: %s", job.get("title"), exc)
            job.update(status="failed", error=str(exc)[:200] or "No se pudo descargar.")
            self.publish({"type": "toast", "ok": False, "message": f"No pude descargar {job['title']}. Inténtalo de nuevo desde Descargas."})
        finally:
            if job["id"] not in self._cancel:
                self._save()
            self.publish({"type": "downloads"})

    def _fetch(self, job: dict, url: str, release: str) -> None:
        self.folder.mkdir(parents=True, exist_ok=True)
        partial = Path(job.get("partial") or self.folder / f"{job['name']}.part")
        job["partial"] = str(partial)
        last_error: Exception | None = None
        for attempt in range(RETRIES):
            have = partial.stat().st_size if partial.exists() else 0
            request = urllib.request.Request(url, headers={"User-Agent": "Orbital", **({"Range": f"bytes={have}-"} if have else {})})
            try:
                with self.opener(request, timeout=TIMEOUT) as response:
                    status = getattr(response, "status", 200)
                    if have and status != 206:  # el servidor no retoma: se empieza de cero
                        have = 0
                    length = int(response.headers.get("Content-Length") or 0)
                    job["size"] = have + length if length else job.get("size") or 0
                    ext = extension_for(getattr(response, "url", url) or url, release, response.headers.get("Content-Type") or "")
                    job["done"] = have
                    last = 0.0
                    with open(partial, "ab" if have else "wb") as out:
                        while True:
                            if job["id"] in self._cancel:
                                return
                            chunk = response.read(CHUNK)
                            if not chunk:
                                break
                            out.write(chunk)
                            job["done"] += len(chunk)
                            if time.time() - last > PROGRESS_EVERY:
                                last = time.time()
                                self.publish({"type": "downloads", "id": job["id"], "done": job["done"], "size": job["size"]})
                if job["size"] and job["done"] < job["size"]:
                    raise OSError("La descarga se cortó antes de terminar")
                final = self.folder / f"{job['name']}{ext}"
                partial.replace(final)
                job.update(file=str(final), partial=None, size=job["done"])
                return
            except (OSError, urllib.error.URLError) as exc:
                last_error = exc
                log.info("Descarga de %s cortada (intento %s): %s", job["title"], attempt + 1, exc)
                time.sleep(min(10, 2 ** attempt))
        raise last_error or OSError("No se pudo descargar")
