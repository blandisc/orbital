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

from ..net import NET_ERRORS, read_body

log = logging.getLogger(__name__)

API = "https://api.real-debrid.com/rest/1.0"
TIMEOUT = 12
VIDEO = re.compile(r"\.(mkv|mp4|avi|m4v|mov|ts|webm)$", re.I)
DONE = {"downloaded"}
FAILED = {"error", "virus", "dead", "magnet_error"}
_TOKEN = re.compile(r"realdebrid=([A-Za-z0-9]+)")


class RealDebridError(Exception):
    """Real-Debrid dijo que no (o no contestó). El mensaje va en palabras; `status` es el HTTP y `code` su error_code
    (21 = muchas descargas a la vez, 34–36 = no permitido, 8/9 = clave que ya no sirve, 20 = sin Premium)."""

    def __init__(self, message: str, status: int | None = None, code: int | None = None) -> None:
        super().__init__(message)
        self.status, self.code = status, code

    @property
    def gone(self) -> bool:
        """Ese torrent ya no está en tu cuenta (lo borraste o lo canceló otro aparato)."""
        return self.status == 404

    @property
    def too_many(self) -> bool:
        return self.code == 21 or self.status == 509

    @property
    def refused(self) -> bool:
        return self.code in (34, 35, 36)

    @property
    def bad_key(self) -> bool:
        return self.status in (401, 403) and self.code in (8, 9, None)

    @property
    def no_premium(self) -> bool:
        return self.code == 20 or (self.status == 403 and self.code not in (8, 9, None))


def token_in(url: str) -> str | None:
    """El token de Real-Debrid que va dentro de la dirección de un complemento (Torrentio, KnightCrawler…)."""
    m = _TOKEN.search(urllib.parse.unquote(url or ""))
    return m.group(1) if m else None


def without_debrid(base: str) -> str:
    """La misma dirección de Torrentio, con tus opciones (orden, idioma, calidades) pero sin Real-Debrid: así enseña los
    torrents que existen aunque Real-Debrid no los tenga."""
    decoded = urllib.parse.unquote(base)
    head, _, tail = decoded.partition("://")
    host, _, path = tail.partition("/")
    options = [o for o in path.split("|") if o and not o.startswith(("realdebrid=", "debridoptions="))]
    rest = "|".join(options)
    return f"{head}://{host}/{urllib.parse.quote(rest, safe='=,')}".rstrip("/")


def magnet(info_hash: str) -> str:
    return f"magnet:?xt=urn:btih:{info_hash}"


class RealDebrid:
    def __init__(self, token: str, opener=None) -> None:
        self.token = token
        self.opener = opener or urllib.request.urlopen

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
        except NET_ERRORS as exc:
            raise RealDebridError("No pude hablar con Real-Debrid. Revisa Internet") from exc
        return json.loads(body) if body.strip() else None

    def user(self) -> dict:
        return self._call("GET", "user") or {}

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

    def delete(self, rd_id: str) -> None:
        """«Cancelar pedido». Si ya no estaba (404), cuenta como hecho."""
        try:
            self._call("DELETE", f"torrents/delete/{rd_id}")
        except RealDebridError as exc:
            if not exc.gone:
                raise

    def link(self, info: dict, file_idx: int | None = None) -> tuple[str, str] | None:
        """Ya bajado: (enlace para el reproductor, nombre del archivo). El de ese archivo si se dice cuál (un episodio de un
        paquete); si no, el video más grande que eligió."""
        links = [x for x in info.get("links") or [] if isinstance(x, str)]
        files = [f for f in info.get("files") or [] if isinstance(f, dict) and f.get("selected")]
        if not links:
            return None
        pairs = list(zip(links, files, strict=False)) or [(links[0], {})]  # los enlaces van en el orden de los archivos elegidos
        exact = [p for p in pairs if file_idx is not None and p[1].get("id") == file_idx + 1]
        best = exact[0][0] if exact else max(pairs, key=lambda p: p[1].get("bytes", 0))[0]
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
    code = code if isinstance(code, int) else None
    if exc.code in (401, 403) and code in (8, 9, None):
        return "Vuelve a conectar Real-Debrid", code
    if code == 20 or exc.code == 403:
        return "Tu cuenta no tiene Premium", code
    if code in (34, 35, 36):
        return "Real-Debrid no lo dejó bajar", code
    if exc.code == 509 or code == 21:
        return "Muchas descargas activas", code
    if exc.code == 404:
        return "Ya no está en tu Real-Debrid", code
    return "Real-Debrid no pudo con ese pedido", code

