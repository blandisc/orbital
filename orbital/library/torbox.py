"""TorBox: pedirle lo que todavía no tiene y saber cuándo está listo, en la forma de Real-Debrid (debrid.py).

API v1 (https://api.torbox.app/docs): `Authorization: Bearer <clave>`; cada respuesta es {"success", "error", "detail",
"data"} y `error` es un código de texto («BAD_TOKEN», «ACTIVE_LIMIT»…) que design/torbox-errors.json traduce a la causa.
Se usa: user/me (tu cuenta), torrents/createtorrent (pedir), torrents/mylist (cuánto llevan), torrents/requestdl (el
enlace del archivo) y torrents/controltorrent (cancelar). TorBox no hace elegir archivos: baja el torrent entero.

Solo habla con api.torbox.app y nunca guarda ni enseña la clave.
"""

from __future__ import annotations

import json
import urllib.error
import urllib.parse
import urllib.request
import uuid

from ..net import NET_FAILURES, read_body, urlopen
from .debrid import DebridError, episode_file, magnet, words

API = "https://api.torbox.app/v1/api"
TIMEOUT = 12
# download_state de TorBox que todavía no empieza a bajar (lo demás es «bajando»).
WAITING = {"metaDL", "checkingResumeData", "queued", "paused"}


class TorBoxError(DebridError):
    service = "torbox"


def status_of(t: dict) -> str:
    """El `status` de Real-Debrid que corresponde a un torrent de TorBox."""
    state = str(t.get("download_state") or "")
    if t.get("download_present") or (t.get("download_finished") and state in ("cached", "completed", "uploading", "seeding")):
        return "downloaded"
    if "error" in state.lower() or "fail" in state.lower():
        return "error"
    if state in WAITING:
        return "queued"
    return "downloading"  # downloading, stalled, uploading antes de estar presente…


def shape(t: dict) -> dict:
    """Un torrent de TorBox en la forma de Real-Debrid. Los archivos: «id» es su lugar en la lista + 1 (el fileIdx de
    Torrentio), y «tb» el id de TorBox para pedir el enlace."""
    files = []
    for i, f in enumerate(f for f in t.get("files") or [] if isinstance(f, dict)):
        files.append({"id": i + 1, "tb": f.get("id"), "path": str(f.get("name") or f.get("short_name") or ""),
                      "bytes": f.get("size") or 0, "selected": 1})
    progress = t.get("progress")
    percent = round(float(progress) * 100) if isinstance(progress, (int, float)) and progress <= 1 else int(progress or 0)
    status = status_of(t)
    return {"id": str(t["id"]) if t.get("id") is not None else None, "hash": str(t.get("hash") or "").lower(),
            "status": status, "progress": 100 if status == "downloaded" else max(0, min(100, percent)),
            "seeders": t.get("seeds") if isinstance(t.get("seeds"), int) else None, "files": files,
            "filename": str(t.get("name") or "")}


def _multipart(fields: dict[str, str]) -> tuple[bytes, str]:
    boundary = uuid.uuid4().hex
    out = b""
    for key, value in fields.items():
        out += (f"--{boundary}\r\nContent-Disposition: form-data; name=\"{key}\"\r\n\r\n{value}\r\n").encode()
    return out + f"--{boundary}--\r\n".encode(), f"multipart/form-data; boundary={boundary}"


class TorBox:
    service = "torbox"
    counts_active = False  # no dice cuántas deja tu plan: lo de «Muchas descargas activas» se vuelve a intentar

    def __init__(self, token: str, opener=None) -> None:
        self.token = token
        self.opener = opener or urlopen

    def _call(self, method: str, path: str, query: dict | None = None, form: dict | None = None, body: dict | None = None):
        url = f"{API}/{path}" + (f"?{urllib.parse.urlencode(query)}" if query else "")
        headers = {"Authorization": f"Bearer {self.token}", "User-Agent": "Orbital/0.1"}
        data = None
        if form is not None:
            data, headers["Content-Type"] = _multipart(form)
        elif body is not None:
            data, headers["Content-Type"] = json.dumps(body).encode(), "application/json"
        req = urllib.request.Request(url, data=data, method=method, headers=headers)
        try:
            with self.opener(req, timeout=TIMEOUT) as res:
                raw = read_body(res, timeout=TIMEOUT, limit=8 * 1024 * 1024)
        except urllib.error.HTTPError as exc:
            raise _error(exc.code, _body(exc)) from exc
        except NET_FAILURES as exc:
            raise TorBoxError("No pude hablar con TorBox. Revisa Internet") from exc
        got = json.loads(raw) if raw.strip() else {}
        if isinstance(got, dict) and got.get("success") is False:
            raise _error(None, got)
        return got.get("data") if isinstance(got, dict) else None

    def user(self) -> dict:
        got = self._call("GET", "user/me")
        return got if isinstance(got, dict) else {}

    def account(self) -> dict:
        user = self.user()
        expires = None
        raw = str(user.get("premium_expires_at") or "")
        if raw:
            from datetime import datetime
            try:
                expires = datetime.fromisoformat(raw.replace("Z", "+00:00")).timestamp()
            except ValueError:
                expires = None
        plan = user.get("plan")
        got = user.get("id")
        return {"id": str(got) if got is not None else None, "username": str(user.get("email") or "") or None,
                "premium": isinstance(plan, int) and plan > 0, "expires": expires}

    def add(self, info_hash: str, file_idx: int | None = None, pack: bool = False) -> str:
        """Pide el torrent (entero: TorBox no deja elegir archivos). El id del pedido."""
        got = self._call("POST", "torrents/createtorrent", form={"magnet": magnet(info_hash), "seed": "3",
                                                                  "allow_zip": "false"}) or {}
        tid = got.get("torrent_id") if isinstance(got, dict) else None
        if tid is None:
            raise TorBoxError("TorBox no aceptó esa versión")
        return str(tid)

    def prepare(self, torrent: dict, file_idx: int | None = None, pack: bool = False) -> None:
        """TorBox no pide nada antes de bajar."""

    def torrents(self, limit: int = 100) -> list[dict]:
        got = self._call("GET", "torrents/mylist", {"bypass_cache": "true", "limit": str(limit)}) or []
        return [shape(t) for t in got if isinstance(t, dict)] if isinstance(got, list) else []

    def info(self, rd_id: str) -> dict:
        got = self._call("GET", "torrents/mylist", {"bypass_cache": "true", "id": str(rd_id)})
        if not isinstance(got, dict) or not got:
            raise TorBoxError(words("torbox")["gone"], 404, "ITEM_NOT_FOUND")
        return shape(got)

    def active_count(self) -> tuple[int, int] | None:
        return None  # TorBox no dice el límite de tu plan

    def delete(self, rd_id: str) -> None:
        """«Cancelar pedido». Si ya no estaba, cuenta como hecho."""
        try:
            self._call("POST", "torrents/controltorrent", body={"torrent_id": int(rd_id), "operation": "delete"})
        except TorBoxError as exc:
            if not exc.gone:
                raise

    def link(self, info: dict, file_idx: int | None = None, season: int | None = None,
             episode: int | None = None) -> tuple[str, str] | None:
        """Ya bajado: (enlace para el reproductor, nombre del archivo)."""
        if info.get("status") != "downloaded" or not info.get("id"):
            return None
        pick = episode_file(info.get("files") or [], file_idx, season, episode)
        if pick is None or pick.get("tb") is None:
            return None
        url = self._call("GET", "torrents/requestdl", {"token": self.token, "torrent_id": str(info["id"]),
                                                       "file_id": str(pick["tb"])})
        name = str(pick.get("path") or "").rsplit("/", 1)[-1]
        return (url, name) if isinstance(url, str) and url.startswith("https://") else None


def _body(exc: urllib.error.HTTPError) -> dict:
    try:
        got = json.loads(exc.read().decode() or "{}")
    except (ValueError, OSError, AttributeError):
        return {}
    return got if isinstance(got, dict) else {}


def _error(status: int | None, body: dict) -> TorBoxError:
    code = body.get("error") if isinstance(body.get("error"), str) else None
    err = TorBoxError("", status, code)
    said = words("torbox")
    return TorBoxError(said.get(err.cause, said["other"]), status, code)
