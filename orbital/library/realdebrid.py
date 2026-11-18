"""Real-Debrid: pedirle lo que todavía no tiene y saber cuándo está listo (Fernando, 2 nov 2026, propuesta RD).

Torrentio con tu Real-Debrid solo enseña lo que Real-Debrid puede dar; si no lo tiene, a veces lo esconde del todo (así salía
«Sin versiones» con Nocturne, que sí existe en internet). Aquí: el token de tu Real-Debrid es el que ya vive en la dirección de
tu Torrentio (`realdebrid=…`); con él se le pide el torrent (`addMagnet`, `selectFiles`), se mira cuánto lleva
(`torrents/info`) y, ya bajado, se saca el enlace que abre el reproductor (`unrestrict/link`).

Solo habla con api.real-debrid.com y nunca guarda ni enseña el token.
"""

from __future__ import annotations

import json
import logging
import re
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

from ..net import NET_FAILURES, read_body, urlopen
from ..shared import design_file
from .debrid import DebridError, episode_file

log = logging.getLogger(__name__)

# A15 · qué quiere decir cada error de Real-Debrid, la misma tabla que lee el iPhone.
ERRORS_FILE = design_file("realdebrid-errors.json")  # desde git o dentro del paquete (shared.py)
CAUSES = ("invalid_session", "no_premium", "refused", "too_many", "slow_down", "gone", "other")


def load_errors(path: Path = ERRORS_FILE) -> tuple[dict[int, str], dict[int, str]]:
    """(error_code → causa, HTTP → causa) de design/realdebrid-errors.json. Si el archivo falta o viene roto, solo lo
    mínimo por HTTP (y queda anotado): Orbital sigue, aunque distinga menos."""
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        codes: dict[int, str] = {}
        for k, v in data["codes"].items():  # renglón por renglón: uno mal escrito se salta, no tumba la tabla
            try:
                if v.get("cause") in CAUSES:
                    codes[int(k)] = v["cause"]
            except (ValueError, KeyError, TypeError, AttributeError):
                log.error("realdebrid-errors.json: el código %r está mal escrito; lo salto", k)
        http = {int(k): v for k, v in data["http"].items() if isinstance(k, str) and k.isdigit() and v in CAUSES}
        return codes, http
    except (OSError, ValueError, KeyError, TypeError, AttributeError):
        log.error("No pude leer %s: los errores de Real-Debrid se distinguen solo por su HTTP", path)
        return {}, {401: "invalid_session", 403: "no_premium", 404: "gone", 429: "slow_down", 509: "too_many"}


ERROR_CODES, ERROR_HTTP = load_errors()


def cause_of(status: int | None, code: int | None) -> str:
    """La causa de un error: primero su error_code; sin él (o desconocido), su HTTP; otro 5xx es «slow_down»."""
    if code is not None and code in ERROR_CODES:
        return ERROR_CODES[code]
    if status is not None and status in ERROR_HTTP:
        return ERROR_HTTP[status]
    if status is not None and status >= 500:
        return "slow_down"
    return "other"

API = "https://api.real-debrid.com/rest/1.0"
TIMEOUT = 12
VIDEO = re.compile(r"\.(mkv|mp4|avi|m4v|mov|ts|webm)$", re.I)
DONE = {"downloaded"}
FAILED = {"error", "virus", "dead", "magnet_error"}
_TOKEN = re.compile(r"realdebrid=([A-Za-z0-9]+)")


class RealDebridError(DebridError):
    """Real-Debrid dijo que no (o no contestó). El mensaje va en palabras; `status` es el HTTP y `code` su error_code.
    Qué quiere decir cada uno lo dice design/realdebrid-errors.json (`cause`), igual que en el iPhone. Sin `status` ni
    `code` (no contestó, o una falla de Orbital) la causa es «other». Es un `debrid.DebridError`: quien atiende a cualquier
    nube lo atiende igual."""

    service = "realdebrid"

    @property
    def cause(self) -> str:
        return cause_of(self.status, self.code if isinstance(self.code, int) else None)


def token_in(url: str) -> str | None:
    """El token de Real-Debrid que va dentro de la dirección de un complemento (Torrentio, KnightCrawler…)."""
    m = _TOKEN.search(urllib.parse.unquote(url or ""))
    return m.group(1) if m else None


def without_debrid(base: str) -> str:
    """La misma dirección de Torrentio sin tu nube (cualquiera de las tres): `debrid.without_debrid`."""
    from .debrid import without_debrid as plain
    return plain(base)


def account_from(user: dict) -> dict:
    """El /user de Real-Debrid en la forma de las tres nubes."""
    expires = None
    raw = str(user.get("expiration") or "")
    if raw:
        from datetime import datetime
        try:
            expires = datetime.fromisoformat(raw.replace("Z", "+00:00")).timestamp()
        except ValueError:
            expires = None
    got = user.get("id")
    return {"id": str(got) if got is not None else None, "username": str(user.get("username") or "") or None,
            "premium": user.get("type") == "premium", "expires": expires}


def magnet(info_hash: str) -> str:
    return f"magnet:?xt=urn:btih:{info_hash}"


class RealDebrid:
    service = "realdebrid"
    counts_active = True  # `active_count` dice cuántas deja tu cuenta: «Muchas descargas activas» espera lugar

    def __init__(self, token: str, opener=None) -> None:
        self.token = token
        self.opener = opener or urlopen

    def _call(self, method: str, path: str, form: dict | None = None):
        data = urllib.parse.urlencode(form).encode() if form is not None else None
        req = urllib.request.Request(f"{API}/{path}", data=data, method=method,
                                     headers={"Authorization": f"Bearer {self.token}", "User-Agent": "Orbital/0.1"})
        try:
            with self.opener(req, timeout=TIMEOUT) as res:
                body = read_body(res, timeout=TIMEOUT, limit=4 * 1024 * 1024)
        except urllib.error.HTTPError as exc:
            message, code = _why(exc)
            raise RealDebridError(message, exc.code, code) from exc
        except NET_FAILURES as exc:
            raise RealDebridError("No pude hablar con Real-Debrid. Revisa Internet") from exc
        return json.loads(body) if body.strip() else None

    def user(self) -> dict:
        return self._call("GET", "user") or {}

    def account(self) -> dict:
        """Tu cuenta en la forma de las tres nubes: {"id", "username", "premium", "expires" (segundos o None)}."""
        return account_from(self.user())

    def prepare(self, torrent: dict, file_idx: int | None = None, pack: bool = False) -> None:
        """Lo que Real-Debrid necesita antes de bajar: elegir los archivos (solo deja una vez) si el torrent espera."""
        if torrent.get("status") == "waiting_files_selection" and torrent.get("id"):
            self.select(torrent["id"], file_idx, pack)

    def add(self, info_hash: str, file_idx: int | None = None, pack: bool = False) -> str:
        """Pide el torrent y elige qué bajar (Real-Debrid solo deja elegir una vez): el archivo del episodio si se sabe cuál;
        en un paquete de temporada (`pack`, más de un video) todos sus videos, como Torrentio, para que los demás episodios
        queden listos sin volver a pedir nada (contrato «requests», `files`). El id del pedido."""
        added = self._call("POST", "torrents/addMagnet", {"magnet": magnet(info_hash)}) or {}
        rd_id = added.get("id")
        if not rd_id:
            raise RealDebridError("Real-Debrid no aceptó esa versión")
        self.select(rd_id, file_idx, pack)
        return rd_id

    def select(self, rd_id: str, file_idx: int | None = None, pack: bool = False) -> None:
        """Elige los archivos de un torrent que espera (waiting_files_selection)."""
        files = [f for f in self.info(rd_id).get("files") or [] if isinstance(f, dict)]
        videos = [f["id"] for f in files if VIDEO.search(str(f.get("path") or ""))]
        wanted = [f["id"] for f in files if file_idx is not None and f.get("id") == file_idx + 1]
        if not wanted or (pack and len(videos) > 1):
            wanted = videos
        self._call("POST", f"torrents/selectFiles/{rd_id}", {"files": ",".join(map(str, wanted)) if wanted else "all"})

    def info(self, rd_id: str) -> dict:
        return self._call("GET", f"torrents/info/{rd_id}") or {}

    def torrents(self, limit: int = 100) -> list[dict]:
        """Tus torrents más recientes, con una sola consulta (para ver cuánto llevan todos los pedidos a la vez)."""
        got = self._call("GET", f"torrents?limit={limit}") or []
        return [t for t in got if isinstance(t, dict)] if isinstance(got, list) else []

    def active_count(self) -> tuple[int, int] | None:
        """(descargas activas, cuántas deja tu cuenta) de `GET /torrents/activeCount`; None si no contesta bien."""
        got = self._call("GET", "torrents/activeCount") or {}
        nb, limit = got.get("nb"), got.get("limit")
        return (nb, limit) if isinstance(nb, int) and isinstance(limit, int) else None

    def delete(self, rd_id: str) -> None:
        """«Cancelar pedido». Si ya no estaba (404), cuenta como hecho."""
        try:
            self._call("DELETE", f"torrents/delete/{rd_id}")
        except RealDebridError as exc:
            if not exc.gone:
                raise

    def link(self, info: dict, file_idx: int | None = None, season: int | None = None,
             episode: int | None = None) -> tuple[str, str] | None:
        """Ya bajado: (enlace para el reproductor, nombre del archivo). El de ese archivo si se dice cuál (un episodio de un
        paquete); si no, el video más grande que eligió."""
        links = [x for x in info.get("links") or [] if isinstance(x, str)]
        files = [f for f in info.get("files") or [] if isinstance(f, dict) and f.get("selected")]
        if not links:
            return None
        pairs = list(zip(links, files, strict=False)) or [(links[0], {})]  # los enlaces van en el orden de los archivos elegidos
        exact = [p for p in pairs if file_idx is not None and p[1].get("id") == file_idx + 1]
        if exact:
            best = exact[0][0]
        else:
            pick = episode_file([f for _, f in pairs], None, season, episode)
            best = next((link for link, f in pairs if f is pick), None) or max(pairs, key=lambda p: p[1].get("bytes", 0))[0]
        out = self._call("POST", "unrestrict/link", {"link": best}) or {}
        url = out.get("download")
        return (url, str(out.get("filename") or "")) if isinstance(url, str) and url.startswith("https://") else None


def _why(exc: urllib.error.HTTPError) -> tuple[str, int | None]:
    """Los errores de Real-Debrid que importan, en las palabras de design/vocabulario.json (los demás, uno general), con
    su error_code."""
    try:
        code = json.loads(exc.read().decode() or "{}").get("error_code")
    except (ValueError, OSError, AttributeError):
        code = None
    code = code if isinstance(code, int) and not isinstance(code, bool) else None
    return WORDS.get(cause_of(exc.code, code), WORDS["other"]), code


WORDS = {"invalid_session": "Vuelve a conectar Real-Debrid", "no_premium": "Tu cuenta no tiene Premium",
         "refused": "Real-Debrid no lo dejó bajar", "too_many": "Muchas descargas activas",
         "gone": "Ya no está en tu Real-Debrid", "other": "Real-Debrid no pudo con ese pedido"}

