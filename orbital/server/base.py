"""Lo que usan las dos apps: quién pregunta (local o de fuera), la clave, los archivos de la interfaz y el guardia de
claves equivocadas."""

from __future__ import annotations

import hmac
import ipaddress
import logging
import mimetypes
import os
import time
from pathlib import Path
from urllib.parse import urlsplit

from fastapi import Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles

from ..api.deps import Deps
from ..api.live import SseHub
from ..api.play import humane_error  # noqa: F401 - se importa desde aquí
from ..api.ui import SETTINGS  # noqa: F401

log = logging.getLogger("orbital.server")  # el nombre de siempre: la bitácora no cambia

WEB_DIR = Path(__file__).parent.parent / "web"

_FORWARD_HEADERS = ("x-forwarded-for", "forwarded", "cf-connecting-ip", "x-real-ip")

EventBus = SseHub  # nombre anterior


_LOCAL_HOSTNAMES = {"127.0.0.1", "localhost", "::1"}


def is_local_request(request: Request) -> bool:
    """Local = viene del propio equipo, NO atravesó un proxy/túnel y va dirigida a localhost.

    Comprobar el Host importa: un túnel como Tailscale Funnel entrega las peticiones desde
    127.0.0.1 y sin garantía de cabeceras de reenvío, pero con Host "tu-equipo.ts.net".
    También evita ataques de DNS rebinding desde páginas web.
    """
    if any(h in request.headers for h in _FORWARD_HEADERS):
        return False
    try:
        hostname = urlsplit("//" + request.headers.get("host", "")).hostname or ""
    except ValueError:
        return False
    if hostname not in _LOCAL_HOSTNAMES:
        return False
    client = request.client.host if request.client else ""
    try:
        return ipaddress.ip_address(client).is_loopback
    except ValueError:
        return False


def token_ok(request: Request, expected: str) -> bool:
    header = request.headers.get("authorization", "").strip()
    # «Bearer», «bearer» o «BEARER» (RFC 6750 no distingue mayúsculas).
    token = header[7:].strip() if header[:7].lower() == "bearer " else header
    if not token or not expected:
        return False
    # En bytes: compare_digest con texto no ASCII lanzaba TypeError (500). Las cabeceras llegan como
    # latin-1: así se recuperan los bytes UTF-8 que mandó el cliente.
    try:
        sent = token.encode("latin-1")
    except UnicodeEncodeError:
        sent = token.encode("utf-8", "surrogatepass")
    return hmac.compare_digest(sent, expected.encode("utf-8", "surrogatepass"))


STORE_DELAY = 90  # s tras el primer escaneo antes de pedir fichas a la tienda de Steam (que el arranque termine primero)


def paused_path() -> Path:
    """Qué quedó congelado (para descongelarlo si Orbital se cierra de golpe)."""
    return Path(os.environ.get("LOCALAPPDATA") or Path.home() / ".local" / "state") / "orbital" / "paused.json"


def emulator_updates_for(d: Deps):
    """Las actualizaciones de los emuladores que tienes (ver emulator_updates.py)."""
    from .. import emulator_updates
    from ..library import emulators as emulator_lib

    def exes() -> list[Path]:
        found = (emulator_lib.resolve_executable(e) for e in d.catalog.emulators)
        return [emulator_updates.real_exe(p) for p in found if p is not None]

    from ..config import expand

    detect = d.config.detect

    def roms_root() -> Path | None:
        return Path(expand(detect.roms)) if detect.roms else None

    def install_root() -> Path | None:
        """Donde van los emuladores que instala Orbital: tu carpeta de emuladores (la primera de detect.dirs)."""
        return Path(expand(detect.dirs[0])) if detect.dirs else Path.home() / "Emuladores"

    def have_systems() -> set[str]:
        return {e.system for e in d.catalog.emulators if e.system and emulator_lib.resolve_executable(e)}

    def installed() -> None:  # un emulador nuevo: la biblioteca lo encuentra y la interfaz se pone al día
        d.catalog.refresh()
        d.hub.publish_threadsafe({"type": "library-changed"})

    return emulator_updates.EmulatorUpdates(
        exes, mode=lambda: d.catalog.state.settings().get("emulator_updates", "avisar"),
        busy=lambda: d.catalog.launcher.status() is not None,
        notify=lambda text: d.hub.publish_threadsafe({"type": "toast", "message": text}),
        roms_root=roms_root, have_systems=have_systems, install_root=install_root, on_installed=installed,
        variant=lambda source_id: d.catalog.state.settings().get("eden_build", "standard") if source_id == "eden" else None)


# Los tipos que la interfaz y el iPhone necesitan con su nombre correcto. En Windows, `mimetypes` lee el registro, que
# puede no conocer .webp (Python 3.11 tampoco lo trae) o decir cualquier cosa de .js (un programa que se adueñó de la
# extensión): una imagen .webp salía como «application/octet-stream» y un .js como «text/plain». Esto manda encima.
WEB_TYPES = {
    ".webp": "image/webp", ".avif": "image/avif", ".svg": "image/svg+xml", ".woff2": "font/woff2", ".woff": "font/woff",
    ".js": "text/javascript", ".mjs": "text/javascript", ".css": "text/css", ".json": "application/json",
    ".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".ico": "image/x-icon", ".txt": "text/plain",
}


def register_web_types() -> None:
    """Pone los tipos de WEB_TYPES por encima de lo que diga el registro de Windows. Se puede llamar varias veces."""
    if not mimetypes.inited:
        mimetypes.init()  # primero lo del sistema (si no, su lectura perezosa después pisaría lo nuestro)
    for ext, kind in WEB_TYPES.items():
        mimetypes.add_type(kind, ext)


class WebFiles(StaticFiles):
    """La interfaz siempre se revalida (ETag y Last-Modified, `no-cache`): tras actualizar Orbital, Edge no mezcla CSS o JS
    viejos. R3-7 (11 nov 2026): el JS, el CSS, el SVG y el HTML viajan comprimidos con gzip si el navegador lo acepta (antes
    solo en el puerto público): ~1,5 MB de texto en ~140 peticiones al arrancar pasan a ~0,4 MB. Se comprime una vez por
    versión del archivo (su fecha y su tamaño) y se guarda en memoria; la ETag de lo comprimido es otra (`-gz`), así una
    actualización cambia las dos y la recarga trae lo nuevo. Brotli no: pediría otra dependencia para poco más."""

    PACKED = frozenset({".js", ".mjs", ".css", ".svg", ".html", ".json", ".webmanifest", ".txt"})
    MIN_SIZE = 1024  # lo más chico no gana nada

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self._gzipped: dict[str, tuple[int, int, bytes]] = {}

    def _gzip(self, path: str, stat_result: os.stat_result) -> bytes:
        import gzip

        mark = (stat_result.st_mtime_ns, stat_result.st_size)
        cached = self._gzipped.get(path)
        if cached and cached[:2] == mark:
            return cached[2]
        body = gzip.compress(Path(path).read_bytes(), compresslevel=6, mtime=0)
        self._gzipped[path] = (*mark, body)
        return body

    def file_response(self, full_path, stat_result, scope, status_code=200):
        from starlette.datastructures import Headers
        from starlette.responses import Response
        from starlette.staticfiles import NotModifiedResponse

        path = str(full_path)
        packable = status_code == 200 and Path(path).suffix.lower() in self.PACKED and stat_result.st_size >= self.MIN_SIZE
        request_headers = Headers(scope=scope)
        if not packable or "gzip" not in request_headers.get("accept-encoding", "").lower():
            response = super().file_response(full_path, stat_result, scope, status_code)
            response.headers["Cache-Control"] = "no-cache"
            if packable:
                response.headers["Vary"] = "Accept-Encoding"
            return response
        plain = FileResponse(full_path, stat_result=stat_result)  # su tipo, su fecha y su ETag
        headers = {"etag": plain.headers["etag"].removesuffix('"') + '-gz"', "last-modified": plain.headers["last-modified"],
                   "cache-control": "no-cache", "vary": "Accept-Encoding"}
        if self.is_not_modified(Headers(headers=headers), request_headers):
            return NotModifiedResponse(Headers(headers=headers))
        return Response(self._gzip(path, stat_result), media_type=plain.media_type,
                        headers={**headers, "content-encoding": "gzip"})


class FailedTokens:
    """Frena a quien prueba tokens por el túnel: tras varios intentos fallidos desde el mismo lugar,
    cada respuesta tarda más y, si sigue, se le bloquea un rato. Lo que entra por el túnel suele
    venir de 127.0.0.1, así que también cuenta la cabecera X-Forwarded-For si existe."""

    WINDOW = 300.0  # s que se recuerda un intento fallido
    SLOW_AFTER = 5  # fallos: a partir de aquí cada respuesta tarda más (hasta MAX_DELAY)
    BLOCK_AFTER = 30  # fallos en WINDOW: bloqueo
    BLOCK_FOR = 900.0
    MAX_DELAY = 5.0

    def __init__(self, clock=time.monotonic) -> None:
        self.clock = clock
        self._fails: dict[str, list[float]] = {}
        self._blocked: dict[str, float] = {}
        self._all: list[float] = []  # todos los fallos: quien inventa una X-Forwarded-For por intento igual se frena

    @staticmethod
    def key(request: Request) -> str:
        # El último valor es el que puso el túnel (el de confianza); los anteriores los escribe quien llama.
        forwarded = request.headers.get("x-forwarded-for", "").split(",")[-1].strip()
        return forwarded or (request.client.host if request.client else "?")

    def blocked(self, key: str) -> bool:
        until = self._blocked.get(key)
        if until and self.clock() < until:
            return True
        self._blocked.pop(key, None)
        return False

    def failed(self, key: str) -> float:
        """Anota un fallo; devuelve cuántos segundos esperar antes de responder."""
        now = self.clock()
        if len(self._fails) > 500:  # quien rota cabeceras no hace crecer esto sin tope
            self._fails = {k: v for k, v in self._fails.items() if v and now - v[-1] < self.WINDOW}
            if len(self._fails) > 500:  # aún muchos recientes: se quedan los 250 más nuevos
                self._fails = dict(sorted(self._fails.items(), key=lambda kv: kv[1][-1])[-250:])
        self._all = [t for t in self._all[-999:] if now - t < self.WINDOW] + [now]
        recent = [t for t in self._fails.get(key, []) if now - t < self.WINDOW] + [now]
        self._fails[key] = recent
        if len(recent) >= self.BLOCK_AFTER:
            self._blocked[key] = now + self.BLOCK_FOR
            log.warning("Demasiados tokens inválidos desde %s: bloqueado %d min", key, self.BLOCK_FOR // 60)
        # La espera crece por origen y también por el total (sin bloquear a todos: Alexa sigue respondiendo).
        mine = max(0, len(recent) - self.SLOW_AFTER) * 0.5
        overall = max(0, len(self._all) - self.SLOW_AFTER * 4) * 0.1
        return min(self.MAX_DELAY, max(mine, overall))

    def succeeded(self, key: str) -> None:
        self._fails.pop(key, None)


async def invalid_request(request: Request, exc: RequestValidationError) -> JSONResponse:
    """422 sin repetir lo que llegó: un NaN o un sustituto Unicode suelto en el cuerpo no se puede volver a escribir
    como JSON y el 422 de FastAPI terminaba en 500."""
    errors = [{"loc": [str(p) for p in e.get("loc", ())], "msg": str(e.get("msg", "")), "type": str(e.get("type", ""))}
              for e in exc.errors()]
    return JSONResponse({"detail": errors}, status_code=422)
