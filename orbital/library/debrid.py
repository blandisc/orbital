"""Tu nube: Real-Debrid, TorBox o AllDebrid (Fernando, 18 nov 2026: «que pueda funcionar con TorBox, AllDebrid y Real-Debrid.
Solamente esos tres»). Lo común a los tres: sus nombres, qué quiere decir cada error y el cliente de cada uno.

Cada cliente (realdebrid.RealDebrid, torbox.TorBox, alldebrid.AllDebrid) habla con su servicio y contesta en la misma forma,
la de Real-Debrid, que es la que ya usa la libreta de pedidos (rd_requests): un torrent es {"id", "hash", "status",
"progress" (0-100), "seeders", "files": [{"id" (fileIdx + 1), "path", "bytes", "selected"}]} con `status` en el vocabulario de
Real-Debrid («downloaded», «downloading», «queued», «error»…). Así la libreta, sus estados y el contrato con el iPhone son
uno solo (design/debrid-services.json).
"""

from __future__ import annotations

import json
import logging
import re
import urllib.parse
from pathlib import Path

from ..shared import design_file

log = logging.getLogger(__name__)

SERVICES = ("realdebrid", "torbox", "alldebrid")
DEFAULT = "realdebrid"
NAMES = {"realdebrid": "Real-Debrid", "torbox": "TorBox", "alldebrid": "AllDebrid"}
TAGS = {"realdebrid": "RD", "torbox": "TB", "alldebrid": "AD"}  # lo que Torrentio pone en el nombre: «[TB+]», «[AD download]»
SITES = {"realdebrid": "real-debrid.com", "torbox": "torbox.app", "alldebrid": "alldebrid.com"}
# Dónde sacas tu clave (la TV lo enseña para abrirlo en el celular).
KEY_URLS = {"realdebrid": "https://real-debrid.com/apitoken", "torbox": "https://torbox.app/settings",
            "alldebrid": "https://alldebrid.com/apikeys/"}
RENEW_URLS = {"realdebrid": "https://real-debrid.com/premium", "torbox": "https://torbox.app/pricing",
              "alldebrid": "https://alldebrid.com/offer/"}
# Dónde se saca una cuenta (los planes): «Todavía no tengo» lo enseña con un QR para abrirlo en el celular.
SIGNUP_URLS = RENEW_URLS
# La clave de cada uno en el llavero de la consola (cifrada). La de Real-Debrid es la de siempre (corte S2).
KEYS = {"realdebrid": "realdebrid_token", "torbox": "torbox_token", "alldebrid": "alldebrid_token"}
CAUSES = ("invalid_session", "no_premium", "refused", "too_many", "slow_down", "gone", "other")
ERRORS_FILES = {s: design_file(f"{s}-errors.json") for s in SERVICES}
_KEY = re.compile(r"^[A-Za-z0-9-]{16,128}$")


def valid(service: object) -> str:
    """El servicio si es uno de los tres; si no, Real-Debrid (lo de antes no decía cuál: era ese)."""
    return service if isinstance(service, str) and service in SERVICES else DEFAULT


def name(service: str | None) -> str:
    return NAMES.get(valid(service), NAMES[DEFAULT])


def looks_like_key(key: str) -> bool:
    """Forma de clave: Real-Debrid y AllDebrid, letras y números; TorBox, un UUID con guiones."""
    return bool(_KEY.match(key or ""))


def load_errors(path: Path) -> tuple[dict[str, str], dict[int, str]]:
    """(código → causa, HTTP → causa) de design/<servicio>-errors.json. Los códigos van como texto («35» de Real-Debrid,
    «ACTIVE_LIMIT» de TorBox, «MAGNET_TOO_MANY_ACTIVE» de AllDebrid). Si el archivo falta o viene roto, solo lo mínimo por
    HTTP (y queda anotado): Orbital sigue, aunque distinga menos."""
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        codes: dict[str, str] = {}
        for k, v in data["codes"].items():  # renglón por renglón: uno mal escrito se salta, no tumba la tabla
            try:
                if v.get("cause") in CAUSES:
                    codes[str(k)] = v["cause"]
            except (KeyError, TypeError, AttributeError):
                log.error("%s: el código %r está mal escrito; lo salto", path.name, k)
        http = {int(k): v for k, v in data["http"].items() if isinstance(k, str) and k.isdigit() and v in CAUSES}
        return codes, http
    except (OSError, ValueError, KeyError, TypeError, AttributeError):
        log.error("No pude leer %s: sus errores se distinguen solo por su HTTP", path)
        return {}, {401: "invalid_session", 403: "no_premium", 404: "gone", 429: "slow_down", 509: "too_many"}


ERRORS = {s: load_errors(p) for s, p in ERRORS_FILES.items()}


def cause_of(service: str, status: int | None, code: object) -> str:
    """La causa de un error: primero su código; sin él (o desconocido), su HTTP; otro 5xx es «slow_down»."""
    codes, http = ERRORS.get(valid(service), ({}, {}))
    if code is not None and str(code) in codes:
        return codes[str(code)]
    if status is not None and status in http:
        return http[status]
    if status is not None and status >= 500:
        return "slow_down"
    return "other"


def words(service: str) -> dict[str, str]:
    """Lo que se dice de cada causa, en las palabras de design/vocabulario.json, con el nombre de tu nube."""
    n = name(service)
    return {"invalid_session": f"Vuelve a conectar {n}", "no_premium": "Tu cuenta no tiene Premium",
            "refused": f"{n} no lo dejó bajar", "too_many": "Muchas descargas activas",
            "gone": f"Ya no está en tu {n}", "slow_down": f"{n} está ocupado · inténtalo en un momento",
            "other": f"{n} no pudo con ese pedido"}


class DebridError(Exception):
    """Tu nube dijo que no (o no contestó). El mensaje va en palabras; `status` es el HTTP y `code` su código de error.
    Qué quiere decir cada uno lo dice design/<servicio>-errors.json (`cause`), igual que en el iPhone. Sin `status` ni
    `code` (no contestó, o una falla de Orbital) la causa es «other»."""

    service = DEFAULT

    def __init__(self, message: str, status: int | None = None, code: object = None, service: str | None = None) -> None:
        super().__init__(message)
        self.status, self.code = status, code
        if service:
            self.service = valid(service)

    @property
    def cause(self) -> str:
        return cause_of(self.service, self.status, self.code)

    @property
    def gone(self) -> bool:
        """Ese torrent ya no está en tu cuenta (lo borraste o lo canceló otro aparato)."""
        return self.cause == "gone"

    @property
    def too_many(self) -> bool:
        """Un límite de tu cuenta (descargas a la vez, tráfico, uso justo): se vuelve a pedir cuando haya lugar."""
        return self.cause == "too_many"

    @property
    def refused(self) -> bool:
        """Tu nube no deja bajar esa versión: no se vuelve a pedir."""
        return self.cause == "refused"

    @property
    def slow_down(self) -> bool:
        """Muchas preguntas seguidas o un servicio de paso caído: se espera y se vuelve a preguntar."""
        return self.cause == "slow_down"

    @property
    def bad_key(self) -> bool:
        return self.cause == "invalid_session"

    @property
    def no_premium(self) -> bool:
        return self.cause == "no_premium"


def error(service: str | None, message: str) -> DebridError:
    """Un error en palabras, de la clase de esa nube (RealDebridError, TorBoxError o AllDebridError)."""
    from . import alldebrid, realdebrid, torbox
    kind = {"realdebrid": realdebrid.RealDebridError, "torbox": torbox.TorBoxError,
            "alldebrid": alldebrid.AllDebridError}[valid(service)]
    return kind(message)


def account(client) -> dict:
    """{"id", "username", "premium", "expires"} de cualquier cliente (uno sin `account`, con la forma de Real-Debrid)."""
    if hasattr(client, "account"):
        return client.account()
    from .realdebrid import account_from
    return account_from(client.user())


def client(service: str, token: str, opener=None):
    """El cliente de ese servicio con tu clave."""
    from . import alldebrid, realdebrid, torbox  # aquí: cada uno importa este módulo
    kind = {"realdebrid": realdebrid.RealDebrid, "torbox": torbox.TorBox, "alldebrid": alldebrid.AllDebrid}[valid(service)]
    return kind(token, opener=opener)


_IN_URL = re.compile(r"(?<![A-Za-z])(realdebrid|torbox|alldebrid)=([A-Za-z0-9-]+)")


def key_in(url: str) -> tuple[str, str] | None:
    """(servicio, clave) que va dentro de la dirección de un complemento (Torrentio: «torbox=…»). None si no trae."""
    m = _IN_URL.search(urllib.parse.unquote(url or ""))
    return (m.group(1), m.group(2)) if m else None


def without_debrid(base: str) -> str:
    """La misma dirección de Torrentio, con tus opciones (orden, idioma, calidades) pero sin tu nube: así enseña los
    torrents que existen aunque tu nube no los tenga."""
    from .torrentio import SECRET_KEYS
    decoded = urllib.parse.unquote(base)
    head, _, tail = decoded.partition("://")
    host, _, path = tail.partition("/")
    options = [o for o in path.split("|")
               if o and not o.startswith(tuple(f"{k}=" for k in (*SECRET_KEYS, "debridoptions")))]
    rest = "|".join(options)
    return f"{head}://{host}/{urllib.parse.quote(rest, safe='=,')}".rstrip("/")


def magnet(info_hash: str) -> str:
    return f"magnet:?xt=urn:btih:{info_hash}"


VIDEO = re.compile(r"\.(mkv|mp4|avi|m4v|mov|ts|webm)$", re.I)


def episode_file(files: list[dict], file_idx: int | None, season: int | None = None,
                 episode: int | None = None) -> dict | None:
    """El archivo que toca de un torrent ya bajado (forma de Real-Debrid: «id» = fileIdx + 1): el de ese índice si está;
    si no (AllDebrid y TorBox no siempre numeran igual que el torrent), el que dice «S01E03» / «1x03» en su nombre; si no,
    el video más grande."""
    files = [f for f in files if isinstance(f, dict)]
    videos = [f for f in files if VIDEO.search(str(f.get("path") or ""))] or files
    if season is not None and episode is not None:  # el nombre manda: no depende de cómo numera cada servicio
        mark = re.compile(rf"(?i)(s0*{season}[ ._-]?e0*{episode}(?!\d)|(?<!\d)0*{season}x0*{episode}(?!\d))")
        named = [f for f in videos if mark.search(str(f.get("path") or ""))]
        if named:
            return max(named, key=lambda f: f.get("bytes") or 0)
    if file_idx is not None:
        exact = next((f for f in files if f.get("id") == file_idx + 1), None)
        if exact is not None:
            return exact
    return max(videos, key=lambda f: f.get("bytes") or 0) if videos else None
