"""AllDebrid: pedirle lo que todavía no tiene y saber cuándo está listo, en la forma de Real-Debrid (debrid.py).

API v4 / v4.1 (https://docs.alldebrid.com): `Authorization: Bearer <clave>`; cada respuesta es {"status": "success", "data"}
o {"status": "error", "error": {"code", "message"}} y `code` («AUTH_BAD_APIKEY», «MAGNET_TOO_MANY_ACTIVE»…) lo traduce
design/alldebrid-errors.json. Se usa: v4/user (tu cuenta), v4/magnet/upload (pedir), v4.1/magnet/status (cuánto llevan),
v4/magnet/files (los archivos y sus enlaces), v4/link/unlock (el enlace para el reproductor) y v4/magnet/delete
(cancelar). AllDebrid no hace elegir archivos y deja 30 a la vez.

Solo habla con api.alldebrid.com y nunca guarda ni enseña la clave.
"""

from __future__ import annotations

import json
import time
import urllib.error
import urllib.parse
import urllib.request

from ..net import NET_FAILURES, read_body, urlopen
from .debrid import DebridError, episode_file, words

API = "https://api.alldebrid.com"
TIMEOUT = 12
ACTIVE_LIMIT = 30  # «Maximum of 30 active magnets reached» (MAGNET_TOO_MANY_ACTIVE)
DELAYED_TRIES = 5


class AllDebridError(DebridError):
    service = "alldebrid"


def status_of(code: object) -> str:
    """El `status` de Real-Debrid que corresponde a un statusCode de AllDebrid (0 en cola, 1 bajando, 2-3 moviendo o
    subiendo, 4 listo; del 5 al 15, error: 7 y 15 son «nadie lo comparte»)."""
    if code == 4:
        return "downloaded"
    if code == 0:
        return "queued"
    if code in (1, 2, 3):
        return "downloading" if code == 1 else "uploading"
    if code in (7, 15):
        return "dead"
    return "error" if isinstance(code, int) else "queued"


def _flatten(nodes: list, prefix: str = "") -> list[dict]:
    """El árbol de archivos de AllDebrid («n» nombre, «e» carpeta, «s» tamaño, «l» enlace) en una lista, en su orden."""
    out: list[dict] = []
    for node in nodes or []:
        if not isinstance(node, dict):
            continue
        path = f"{prefix}{node.get('n') or ''}"
        if isinstance(node.get("e"), list):
            out.extend(_flatten(node["e"], f"{path}/"))
        elif isinstance(node.get("l"), str):
            out.append({"path": path, "bytes": node.get("s") or 0, "link": node["l"]})
    return out


def shape(m: dict, files: list[dict] | None = None) -> dict:
    """Un magnet de AllDebrid en la forma de Real-Debrid. Los archivos van numerados en el orden del árbol (+ 1)."""
    size = m.get("size") or 0
    done = m.get("downloaded") or 0
    status = status_of(m.get("statusCode"))
    percent = round(done * 100 / size) if isinstance(size, (int, float)) and size > 0 and isinstance(done, (int, float)) else 0
    return {"id": str(m["id"]) if m.get("id") is not None else None, "hash": str(m.get("hash") or "").lower(),
            "status": status, "progress": 100 if status == "downloaded" else max(0, min(100, percent)),
            "seeders": m.get("seeders") if isinstance(m.get("seeders"), int) else None,
            "files": [{"id": i + 1, "selected": 1, **f} for i, f in enumerate(files or [])],
            "filename": str(m.get("filename") or "")}


class AllDebrid:
    service = "alldebrid"
    counts_active = True

    def __init__(self, token: str, opener=None) -> None:
        self.token = token
        self.opener = opener or urlopen

    def _call(self, method: str, path: str, form: list[tuple[str, str]] | None = None):
        data = urllib.parse.urlencode(form).encode() if form is not None else None
        req = urllib.request.Request(f"{API}/{path}", data=data, method=method,
                                     headers={"Authorization": f"Bearer {self.token}", "User-Agent": "Orbital/0.1"})
        try:
            with self.opener(req, timeout=TIMEOUT) as res:
                raw = read_body(res, timeout=TIMEOUT, limit=8 * 1024 * 1024)
        except urllib.error.HTTPError as exc:
            raise _error(exc.code, _body(exc)) from exc
        except NET_FAILURES as exc:
            raise AllDebridError("No pude hablar con AllDebrid. Revisa Internet") from exc
        got = json.loads(raw) if raw.strip() else {}
        if isinstance(got, dict) and got.get("status") == "error":
            raise _error(None, got)
        return got.get("data") if isinstance(got, dict) else None

    def user(self) -> dict:
        got = self._call("GET", "v4/user") or {}
        user = got.get("user") if isinstance(got, dict) else None
        return user if isinstance(user, dict) else {}

    def account(self) -> dict:
        """AllDebrid no da un número de cuenta: el nombre de usuario hace de id."""
        user = self.user()
        until = user.get("premiumUntil")
        name = str(user.get("username") or "") or None
        return {"id": name, "username": name, "premium": user.get("isPremium") is True,
                "expires": float(until) if isinstance(until, (int, float)) and until > 0 else None}

    def add(self, info_hash: str, file_idx: int | None = None, pack: bool = False) -> str:
        got = self._call("POST", "v4/magnet/upload", [("magnets[]", info_hash)]) or {}
        magnets = got.get("magnets") if isinstance(got, dict) else None
        first = magnets[0] if isinstance(magnets, list) and magnets and isinstance(magnets[0], dict) else {}
        if isinstance(first.get("error"), dict):
            raise _error(None, {"error": first["error"]})
        if first.get("id") is None:
            raise AllDebridError("AllDebrid no aceptó esa versión")
        return str(first["id"])

    def prepare(self, torrent: dict, file_idx: int | None = None, pack: bool = False) -> None:
        """AllDebrid no pide nada antes de bajar."""

    def _status(self, form: list[tuple[str, str]] | None = None) -> list[dict]:
        got = self._call("POST", "v4.1/magnet/status", form or []) or {}
        magnets = got.get("magnets") if isinstance(got, dict) else None
        if isinstance(magnets, dict):  # con «id» llega uno solo
            magnets = [magnets]
        return [m for m in magnets or [] if isinstance(m, dict)]

    def torrents(self, limit: int = 100) -> list[dict]:
        return [shape(m) for m in self._status()[:limit]]

    def _files(self, magnet_id: str) -> list[dict]:
        got = self._call("POST", "v4/magnet/files", [("id[]", str(magnet_id))]) or {}
        magnets = got.get("magnets") if isinstance(got, dict) else None
        first = magnets[0] if isinstance(magnets, list) and magnets and isinstance(magnets[0], dict) else {}
        if isinstance(first.get("error"), dict):
            raise _error(None, {"error": first["error"]})
        return _flatten(first.get("files") or [])

    def info(self, rd_id: str) -> dict:
        found = self._status([("id", str(rd_id))])
        if not found:
            raise AllDebridError(words("alldebrid")["gone"], 404, "MAGNET_INVALID_ID")
        m = found[0]
        files = self._files(rd_id) if m.get("statusCode") == 4 else []
        return shape(m, files)

    def active_count(self) -> tuple[int, int] | None:
        busy = [m for m in self._status([("status", "active")])]
        return len(busy), ACTIVE_LIMIT

    def delete(self, rd_id: str) -> None:
        try:
            self._call("POST", "v4/magnet/delete", [("id", str(rd_id))])
        except AllDebridError as exc:
            if not exc.gone:
                raise

    def link(self, info: dict, file_idx: int | None = None, season: int | None = None,
             episode: int | None = None) -> tuple[str, str] | None:
        if info.get("status") != "downloaded":
            return None
        pick = episode_file(info.get("files") or [], file_idx, season, episode)
        if pick is None or not pick.get("link"):
            return None
        got = self._call("POST", "v4/link/unlock", [("link", pick["link"])]) or {}
        url = got.get("link") if isinstance(got, dict) else None
        name = str(got.get("filename") or "") if isinstance(got, dict) else ""
        delayed = got.get("delayed") if isinstance(got, dict) else None
        for _ in range(DELAYED_TRIES if not url and delayed else 0):  # AllDebrid a veces arma el enlace aparte
            time.sleep(1)
            wait = self._call("POST", "v4/link/delayed", [("id", str(delayed))]) or {}
            if isinstance(wait, dict) and wait.get("status") == 2:
                url = wait.get("link")
                break
            if isinstance(wait, dict) and wait.get("status") == 3:
                break
        return (url, name or str(pick.get("path") or "").rsplit("/", 1)[-1]) \
            if isinstance(url, str) and url.startswith("https://") else None


def _body(exc: urllib.error.HTTPError) -> dict:
    try:
        got = json.loads(exc.read().decode() or "{}")
    except (ValueError, OSError, AttributeError):
        return {}
    return got if isinstance(got, dict) else {}


def _error(status: int | None, body: dict) -> AllDebridError:
    err = body.get("error") if isinstance(body.get("error"), dict) else {}
    code = err.get("code") if isinstance(err.get("code"), str) else None
    probe = AllDebridError("", status, code)
    said = words("alldebrid")
    return AllDebridError(said.get(probe.cause, said["other"]), status, code)
