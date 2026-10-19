"""Tus videos de OneDrive dentro de Orbital: los de la carpeta que eliges en Ajustes, reconocidos por su nombre y con su
ficha (Cinemeta). Salen en Películas y series («En tu OneDrive») y, si un título está ahí, «Tu OneDrive» es su fuente
recomendada: se ve directo en el reproductor de Orbital (sin Real-Debrid). Ver library/onedrive.py."""

from __future__ import annotations

import json
import logging
import threading
import time
from pathlib import Path

from .library import cinemeta, onedrive, streams

log = logging.getLogger(__name__)

FOLDER_KEY = "onedrive_folder"
RESCAN_EVERY = 6 * 3600  # s: lo nuevo que subas aparece solo
INDEX = 9_000  # el número de fuente de «Tu OneDrive» (las de los complementos van de 0 en adelante)
ADDON = "Tu OneDrive"


def _norm(text: str) -> str:
    import re
    import unicodedata
    text = unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode().lower()
    return re.sub(r"[^a-z0-9]+", " ", text).strip()


class OneDriveLibrary:
    def __init__(self, client: onedrive.OneDrive, cinemeta_client, state, cache: Path | None = None, publish=None) -> None:
        self.client = client
        self.cinemeta = cinemeta_client
        self.state = state
        self.cache = cache  # onedrive-library.json: lo encontrado y qué título es cada nombre (no se vuelve a buscar)
        self.publish = publish or (lambda event: None)
        self.files: list[dict] = []
        self.matches: dict[str, dict | None] = {}  # "movie|dune part two|2024" -> {"imdb", "title", "year"} o None
        self.scanned_at = 0.0
        self.scanning = False
        self.error: str | None = None
        self._lock = threading.Lock()
        self._load()

    # --- estado ------------------------------------------------------------------------------------
    @property
    def folder(self) -> str:
        return str(self.state.settings().get(FOLDER_KEY) or "")

    def set_folder(self, path: str) -> None:
        path = "/".join(p for p in str(path or "").replace("\\", "/").split("/") if p and p not in (".", ".."))
        self.state.set_setting(FOLDER_KEY, path)
        self.files, self.scanned_at = [], 0.0
        self.scan_soon()

    def status(self) -> dict:
        titles = {(f["kind"], f.get("imdb")) for f in self.files if f.get("imdb")}
        return {"configured": self.client.configured, "linked": self.client.linked, "folder": self.folder,
                "videos": len(self.files), "titles": len(titles), "scanning": self.scanning, "error": self.error}

    def _load(self) -> None:
        if not self.cache or not self.cache.exists():
            return
        try:
            raw = json.loads(self.cache.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return
        self.files = [f for f in raw.get("files") or [] if isinstance(f, dict)]
        self.matches = raw.get("matches") or {}
        self.scanned_at = float(raw.get("scanned_at") or 0)

    def _save(self) -> None:
        if not self.cache:
            return
        try:
            self.cache.parent.mkdir(parents=True, exist_ok=True)
            tmp = self.cache.with_suffix(".tmp")
            tmp.write_text(json.dumps({"files": self.files, "matches": self.matches, "scanned_at": self.scanned_at},
                                      ensure_ascii=False), encoding="utf-8")
            tmp.replace(self.cache)
        except OSError as exc:
            log.info("OneDrive: no pude guardar lo encontrado: %s", exc)

    # --- buscar ------------------------------------------------------------------------------------
    def scan_soon(self) -> None:
        if self.scanning or not self.client.linked or not self.folder:
            return
        threading.Thread(target=self.scan, daemon=True, name="onedrive-scan").start()

    def maybe_rescan(self) -> None:
        if time.time() - self.scanned_at > RESCAN_EVERY:
            self.scan_soon()

    def scan(self) -> int:
        """Lee la carpeta elegida y reconoce cada video (una búsqueda por título distinto; lo ya reconocido no se repite)."""
        if not self.client.linked or not self.folder:
            return 0
        with self._lock:
            if self.scanning:
                return 0
            self.scanning = True
        try:
            found = self.client.videos(self.folder)
            for f in found:
                key = f"{f['kind']}|{_norm(f['title'])}|{f.get('year') or ''}"
                if key not in self.matches:
                    self.matches[key] = self._match(f["kind"], f["title"], f.get("year"))
                hit = self.matches.get(key)
                if hit:
                    f.update(imdb=hit["imdb"], show_title=hit["title"], show_year=hit.get("year"))
            self.files, self.scanned_at, self.error = found, time.time(), None
            self._save()
            log.info("OneDrive: %d videos en «%s» (%d reconocidos)", len(found), self.folder, sum(1 for f in found if f.get("imdb")))
            self.publish({"type": "onedrive-changed"})
            return len(found)
        except onedrive.OneDriveError as exc:
            self.error = str(exc)
            log.info("OneDrive: no pude leer la carpeta: %s", exc)
            return 0
        finally:
            self.scanning = False

    def _match(self, kind: str, title: str, year: int | None) -> dict | None:
        """La ficha de ese nombre: la que tenga el mismo año (±1) o, si no hay año, la primera."""
        try:
            results = self.cinemeta.search(kind, title)
        except cinemeta.CinemetaError:
            return None
        def year_of(m: dict) -> int | None:
            text = str(m.get("releaseInfo") or m.get("year") or "")[:4]
            return int(text) if text.isdigit() else None
        if year:  # con año, solo la de ese año (otra con el mismo nombre sería otra película)
            pick = next((m for m in results if (y := year_of(m)) and abs(y - year) <= 1), None)
        else:
            pick = results[0] if results else None
        if not pick or not str(pick.get("id", "")).startswith("tt"):
            return None
        return {"imdb": pick["id"], "title": pick.get("name") or title, "year": year_of(pick)}

    # --- para la tele ------------------------------------------------------------------------------
    def titles(self) -> list[dict]:
        """Lo de OneDrive como entradas de Para ti (una por película o serie): la fila «En tu OneDrive»."""
        seen: dict[tuple[str, str], dict] = {}
        for f in self.files:
            if f.get("imdb") and (f["kind"], f["imdb"]) not in seen:
                seen[(f["kind"], f["imdb"])] = {"kind": f["kind"], "imdb": f["imdb"], "title": f.get("show_title") or f["title"],
                                                "year": f.get("show_year") or f.get("year")}
        return list(seen.values())

    def library(self) -> dict:
        """Mi media (como el iPhone): cada película o serie una vez, lo más reciente primero (cuándo lo subiste), con
        cuántos archivos tiene; y lo que no se reconoció («Sin ficha»), que se puede ver tal cual."""
        titles: dict[tuple[str, str], dict] = {}
        unmatched = []
        for f in self.files:
            if not f.get("imdb"):
                unmatched.append({"id": f["id"], "name": f["name"], "path": f.get("path") or f["name"], "size": f.get("size") or 0,
                                  "added": f.get("added")})
                continue
            key = (f["kind"], f["imdb"])
            t = titles.setdefault(key, {"kind": f["kind"], "imdb": f["imdb"], "title": f.get("show_title") or f["title"],
                                        "year": f.get("show_year") or f.get("year"), "added": None, "files": 0, "episodes": set()})
            t["files"] += 1
            if f.get("added") and (t["added"] is None or f["added"] > t["added"]):
                t["added"] = f["added"]
            if f["kind"] == "series" and f.get("season") is not None and f.get("episode") is not None:
                t["episodes"].add((f["season"], f["episode"]))
        out = [{**t, "episodes": len(t["episodes"])} for t in titles.values()]
        out.sort(key=lambda t: -(t["added"] or 0))
        unmatched.sort(key=lambda f: -(f["added"] or 0))
        return {"titles": out, "unmatched": unmatched, "folder": self.folder, "scanned_at": self.scanned_at or None,
                "scanning": self.scanning, "error": self.error}

    def file_url(self, file_id: str) -> str | None:
        """La dirección temporal de un archivo de tu carpeta (uno «Sin ficha», para verlo tal cual)."""
        if not any(f.get("id") == file_id for f in self.files):
            return None
        return self.client.stream_url(file_id)

    def file_for(self, kind: str, video_id: str) -> dict | None:
        """El archivo de ese título (película) o episodio («tt123:1:3»)."""
        parts = str(video_id).split(":")
        imdb = parts[0]
        for f in self.files:
            if f.get("imdb") != imdb or f["kind"] != kind:
                continue
            if kind == "movie" or (len(parts) == 3 and f.get("season") == int(parts[1]) and f.get("episode") == int(parts[2])):
                return f
        return None

    def source(self, kind: str, video_id: str) -> streams.Source | None:
        """«Tu OneDrive» como fuente (la recomendada: está en tu nube, arranca sin esperar)."""
        f = self.file_for(kind, video_id) if self.client.linked else None
        if not f:
            return None
        name = f["name"].lower()
        resolution = next((r for r, words in (("4K", ("2160", "4k", "uhd")), ("1080p", ("1080",)), ("720p", ("720",)))
                           if any(w in name for w in words)), "")
        return streams.Source(index=INDEX, addon=ADDON, stream={"onedrive": f["id"]}, transport_url="", resolution=resolution,
                              size=int(f.get("size") or 0), cached=True, release=f["name"], score=10_000)

    def stream_url(self, source: streams.Source) -> str | None:
        item = source.stream.get("onedrive") if source and isinstance(source.stream, dict) else None
        return self.client.stream_url(item) if item else None


class Linker:
    """Conectar OneDrive con un código (como Trakt): se pide, se muestra en la tele y se espera en segundo plano a que lo
    escribas en microsoft.com/link. Avisa con «onedrive-linked» o «onedrive-link-failed»."""

    def __init__(self, library: OneDriveLibrary, sleep=time.sleep) -> None:
        self.library = library
        self.sleep = sleep
        self._code: onedrive.DeviceCode | None = None
        self._lock = threading.Lock()

    def start(self) -> dict:
        code = self.library.client.device_code()
        with self._lock:
            self._code = code
        threading.Thread(target=self.wait, args=(code,), daemon=True, name="onedrive-link").start()
        return code.public()

    def cancel(self) -> None:
        with self._lock:
            self._code = None

    def wait(self, code) -> str:
        interval = max(1.0, code.interval)
        while time.time() < code.expires_at:
            self.sleep(interval)
            with self._lock:
                if self._code is not code:
                    return "cancelled"
            try:
                result = self.library.client.poll_device(code)
            except (onedrive.OneDriveError, *onedrive.NET_ERRORS, ValueError, TypeError):
                continue
            if result == "slow":
                interval += 5
            elif result == "linked":
                with self._lock:
                    self._code = None
                self.library.publish({"type": "onedrive-linked"})
                self.library.scan_soon()
                return result
            elif result != "pending":
                break
        with self._lock:
            if self._code is code:
                self._code = None
        self.library.publish({"type": "onedrive-link-failed", "message": "El código caducó. Pide otro para conectar OneDrive."})
        return "expired"
