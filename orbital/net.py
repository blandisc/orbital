"""Lectura HTTP robusta para los clientes de internet (Trakt, TMDB, Cinemeta, Stremio, arte, GeForce NOW).

Una red rara no puede tumbar a Orbital: una conexión cortada a media respuesta (IncompleteRead),
reiniciada, con basura en vez de HTTP (BadStatusLine) o que gotea un byte cada medio segundo cuenta como
cualquier otro error de red, con un plazo TOTAL (no solo por lectura) y un tamaño máximo.

`http_json` es la capa de red común de los servicios con API (A6, V5, F9 de la revisión del 10 nov 2026):

- reintenta un 429 o un 5xx una o dos veces, esperando lo que diga `Retry-After`, sin pasar de `RETRY_BUDGET`;
- reutiliza la conexión con cada servidor (una reserva por host, segura entre hilos): sin un apretón TLS por pedido;
- un cortacircuitos por servicio: tras `BREAKER_FAILURES` fallos seguidos lo da por caído `BREAKER_COOLDOWN` s y
  responde al momento con `ServiceDown`, para que quien llama use lo que tiene guardado en vez de esperar al plazo;
- los fallos de red salen como `NetError` (que es un OSError: quien atrapa `NET_ERRORS` u `OSError` sigue igual).

`NET_FAILURES` es «la red o el servicio fallaron», sin OSError ni ValueError genéricos (un disco lleno o un error
de programación no son «sin internet»). `NET_ERRORS` se queda tan amplio como antes para quien lee con urlopen
directo; los clientes se pasan a `NET_FAILURES` poco a poco.
"""

from __future__ import annotations

import email.utils
import functools
import http.client
import json
import logging
import ssl
import threading
import time
import urllib.error
import urllib.request
from urllib.parse import urlencode, urljoin, urlsplit

log = logging.getLogger(__name__)


class NetError(OSError):
    """La red o el servicio fallaron (sin conexión, plazo vencido, respuesta cortada o ilegible)."""


class ServiceDown(NetError):
    """El cortacircuitos tiene ese servicio por caído: ni se intentó (se usa lo guardado)."""


class TooLarge(NetError, ValueError):
    """La respuesta pasó del tamaño máximo (también es ValueError, como antes)."""


class BadResponse(NetError, ValueError):
    """Llegó algo que no es el JSON esperado (también es ValueError, como antes)."""


# Todo lo que puede lanzar urllib al leer: URLError/HTTPError y TimeoutError son OSError. Amplio a propósito (ver arriba).
NET_ERRORS = (OSError, http.client.HTTPException, ValueError)
# Solo lo que de verdad es «la red o el servicio fallaron».
NET_FAILURES = (NetError, urllib.error.URLError, TimeoutError, ConnectionError, ssl.SSLError, http.client.HTTPException,
                json.JSONDecodeError)

MAX_BYTES = 16 * 1024 * 1024  # una respuesta de catálogo nunca pesa tanto

RETRIES = 2  # reintentos de un 429/5xx (tres intentos en total como mucho)
RETRY_BUDGET = 8.0  # s: lo más que se espera en total entre reintentos; un Retry-After más largo no se espera
RETRY_STATUSES = frozenset({429, 502, 503, 504})  # en cualquier método: el servidor no hizo nada
RETRY_READ_STATUSES = frozenset({500})  # solo en lecturas: un POST con 500 pudo haberse aplicado
BREAKER_FAILURES = 5  # fallos seguidos de un servicio…
BREAKER_COOLDOWN = 60.0  # …y se da por caído este tiempo (s)
POOL_PER_HOST = 4  # conexiones libres que se guardan por servidor
POOL_IDLE = 30.0  # s: una conexión parada más tiempo se cierra (los servidores cortan las ociosas)
REDIRECTS = 5

_sleep = time.sleep  # las pruebas no esperan de verdad


@functools.cache
def tls_context() -> ssl.SSLContext:
    """Un solo contexto TLS para todo Orbital. urllib armaba uno por conexión, y cada uno carga los certificados de
    Windows (424 en la Legion Go): 104 ms de CPU por pedido. Al arrancar se hacen cientos (fichas, arte, canales, GeForce
    NOW) y el servidor pasaba más de un minuto con un núcleo al 100 %: la interfaz respondía lenta justo al abrirla."""
    return ssl.create_default_context()


def share_tls() -> None:
    """Que todo urlopen (sin contexto propio) use el contexto compartido. Una vez, al arrancar."""
    urllib.request.install_opener(urllib.request.build_opener(urllib.request.HTTPSHandler(context=tls_context())))


def read_body(res, *, timeout: float, limit: int = MAX_BYTES, truncate: bool = False) -> bytes:
    """Lee la respuesta completa en pedazos con un plazo total; corta si se pasa de `limit`.
    `truncate`: en vez de fallar, se queda con los primeros `limit` bytes (para probar que un video abre
    sin bajarse el segmento entero)."""
    deadline = time.monotonic() + max(1.0, timeout * 2)
    chunks, size = [], 0
    while True:
        if time.monotonic() > deadline:
            raise TimeoutError("La respuesta tardó demasiado")
        # read1 devuelve lo que ya llegó (no espera a juntar 64 KB): el plazo se revisa en cada pedazo.
        chunk = getattr(res, "read1", res.read)(64 * 1024)
        if not chunk:
            return b"".join(chunks)
        size += len(chunk)
        if size > limit:
            if truncate:
                return b"".join(chunks + [chunk])[:limit]
            raise TooLarge("Respuesta demasiado grande")
        chunks.append(chunk)


def read_json(res, *, timeout: float, limit: int = MAX_BYTES):
    raw = read_body(res, timeout=timeout, limit=limit)
    try:
        return json.loads(raw.decode("utf-8"))
    except ValueError as exc:  # UnicodeDecodeError o JSONDecodeError
        raise BadResponse(f"Respuesta ilegible: {exc}") from exc


# --- cortacircuitos ---------------------------------------------------------------------------------------------------
class Breaker:
    """Fallos seguidos por servicio (host): errores de red y 5xx. Cualquier otra respuesta pone la cuenta en cero."""

    def __init__(self, failures: int = BREAKER_FAILURES, cooldown: float = BREAKER_COOLDOWN, clock=time.monotonic) -> None:
        self.failures, self.cooldown, self.clock = failures, cooldown, clock
        self._lock = threading.Lock()
        self._count: dict[str, int] = {}
        self._until: dict[str, float] = {}

    def check(self, host: str) -> None:
        with self._lock:
            until = self._until.get(host, 0.0)
            if until and self.clock() < until:
                raise ServiceDown(f"{host} no contesta; lo vuelvo a intentar en {until - self.clock():.0f} s")
            if until:  # pasó la espera: se deja intentar otra vez (si falla, se vuelve a abrir de inmediato)
                self._until.pop(host, None)
                self._count[host] = self.failures - 1

    def success(self, host: str) -> None:
        with self._lock:
            self._count.pop(host, None)
            self._until.pop(host, None)

    def failure(self, host: str) -> None:
        with self._lock:
            count = self._count.get(host, 0) + 1
            self._count[host] = count
            if count >= self.failures and host not in self._until:
                self._until[host] = self.clock() + self.cooldown
                log.info("%s falló %d veces seguidas: lo doy por caído %.0f s", host, count, self.cooldown)

    def down(self, host: str) -> bool:
        with self._lock:
            return self.clock() < self._until.get(host, 0.0)

    def reset(self) -> None:
        with self._lock:
            self._count.clear()
            self._until.clear()


# --- reserva de conexiones --------------------------------------------------------------------------------------------
class Pool:
    """Conexiones abiertas por servidor. Cada una la usa un solo hilo a la vez: se saca de la reserva, se usa y se
    devuelve (o se cierra si el servidor pidió cerrarla). Seguro entre hilos."""

    def __init__(self, per_host: int = POOL_PER_HOST, idle: float = POOL_IDLE, clock=time.monotonic) -> None:
        self.per_host, self.idle, self.clock = per_host, idle, clock
        self._lock = threading.Lock()
        self._free: dict[tuple, list[tuple[http.client.HTTPConnection, float]]] = {}

    def take(self, key: tuple, timeout: float) -> tuple[http.client.HTTPConnection, bool]:
        """(conexión, si ya se había usado)."""
        now = self.clock()
        stale = []
        conn = None
        with self._lock:
            free = self._free.get(key) or []
            while free:
                candidate, since = free.pop()
                if now - since <= self.idle:
                    conn = candidate
                    break
                stale.append(candidate)
        for old in stale:
            old.close()
        if conn is not None:
            conn.timeout = timeout
            if conn.sock is not None:
                conn.sock.settimeout(timeout)
            return conn, True
        return _connect(key, timeout), False

    def give(self, key: tuple, conn: http.client.HTTPConnection) -> None:
        with self._lock:
            free = self._free.setdefault(key, [])
            if len(free) < self.per_host:
                free.append((conn, self.clock()))
                return
        conn.close()

    def clear(self) -> None:
        with self._lock:
            conns = [c for free in self._free.values() for c, _ in free]
            self._free.clear()
        for conn in conns:
            conn.close()


def _connect(key: tuple, timeout: float) -> http.client.HTTPConnection:
    scheme, host, port = key
    if scheme == "https":
        return http.client.HTTPSConnection(host, port, timeout=timeout, context=tls_context())
    return http.client.HTTPConnection(host, port, timeout=timeout)


breaker = Breaker()
pool = Pool()


def reset() -> None:
    """Olvida los servicios caídos y cierra las conexiones guardadas (pruebas, o al cambiar de red)."""
    breaker.reset()
    pool.clear()


@functools.cache
def _proxied() -> bool:
    """Con un proxy configurado (Windows lo lee del registro) se usa urllib, que sabe pasar por él."""
    try:
        proxies = urllib.request.getproxies()
    except Exception:  # noqa: BLE001 - un registro raro no tumba la red
        return False
    return bool(proxies.get("https") or proxies.get("http"))


_STALE = (http.client.RemoteDisconnected, ConnectionResetError, ConnectionAbortedError, BrokenPipeError)


def _send(key: tuple, method: str, target: str, data: bytes | None, headers: dict, timeout: float):
    """Un pedido por una conexión de la reserva. Si una conexión reutilizada ya estaba cerrada por el servidor, se
    repite una vez con una nueva (el servidor no llegó a recibir el pedido)."""
    for fresh in (False, True):
        conn, reused = pool.take(key, timeout) if not fresh else (_connect(key, timeout), False)
        try:
            conn.request(method, target, body=data, headers=headers)
            res = conn.getresponse()
        except _STALE:
            conn.close()
            if reused and not fresh:
                continue
            raise
        except BaseException:
            conn.close()
            raise
        try:
            raw = read_body(res, timeout=timeout)
        except BaseException:
            conn.close()
            raise
        if res.will_close:
            conn.close()
        else:
            pool.give(key, conn)
        return res.status, raw, res.headers
    raise NetError("No pude conectar")  # no se llega: el segundo intento devuelve o lanza


def _via_pool(url: str, method: str, data: bytes | None, headers: dict, timeout: float):
    for _ in range(REDIRECTS + 1):
        parts = urlsplit(url)
        if parts.scheme not in ("http", "https") or not parts.hostname:
            raise NetError(f"Dirección inválida: {url[:80]}")
        key = (parts.scheme, parts.hostname, parts.port or (443 if parts.scheme == "https" else 80))
        target = (parts.path or "/") + (f"?{parts.query}" if parts.query else "")
        status, raw, res_headers = _send(key, method, target, data, headers, timeout)
        location = res_headers.get("Location")
        if status not in (301, 302, 303, 307, 308) or not location:
            return status, raw, res_headers
        if method not in ("GET", "HEAD"):
            if status in (307, 308):  # como urllib: un POST no se repite solo en otro lado
                return status, raw, res_headers
            method, data = "GET", None
            headers = {k: v for k, v in headers.items() if k.lower() not in ("content-type", "content-length")}
        new = urljoin(url, location)
        if urlsplit(new).hostname != parts.hostname:  # la sesión no viaja a otro servidor
            headers = {k: v for k, v in headers.items() if k.lower() != "authorization"}
        url = new
    raise NetError("Demasiadas redirecciones")


def _via_urllib(url: str, method: str, data: bytes | None, headers: dict, timeout: float):
    req = urllib.request.Request(url, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as res:
            return res.status, read_body(res, timeout=timeout), res.headers
    except urllib.error.HTTPError as exc:
        try:
            raw = exc.read(64 * 1024)
        except NET_ERRORS:
            raw = b""
        return exc.code, raw, exc.headers


def retry_after(value: str | None, attempt: int) -> float:
    """Cuánto esperar antes del siguiente intento: lo que diga el servidor (segundos o una fecha) o 0,5 s, 1,5 s…"""
    if value:
        value = value.strip()
        try:
            return max(0.0, float(value))
        except ValueError:
            pass
        try:
            when = email.utils.parsedate_to_datetime(value)
            return max(0.0, when.timestamp() - time.time())
        except (TypeError, ValueError, IndexError, OverflowError):
            pass
    return 0.5 + attempt


def http_json(url: str, *, method: str = "GET", headers: dict | None = None, body: dict | None = None,
              timeout: float = 10, form: dict | None = None, retries: int = RETRIES) -> tuple[int, object]:
    """Una petición JSON que devuelve (código HTTP, cuerpo) también cuando el código es de error: Trakt
    dice «todavía no» con un 400 y «más despacio» con un 429. Un 429/5xx se reintenta (`retries`, dentro de
    `RETRY_BUDGET`); si sigue, se devuelve tal cual. Los fallos de red se lanzan como NetError (y ServiceDown
    si el servicio está dado por caído)."""
    # `form`: como formulario (el inicio de sesión de Microsoft lo pide así); `body`: JSON.
    data = urlencode(form).encode() if form is not None else json.dumps(body).encode() if body is not None else None
    kind = "application/x-www-form-urlencoded" if form is not None else "application/json"
    all_headers = {"User-Agent": "Orbital", "Accept": "application/json",
                   **({"Content-Type": kind} if data is not None else {}), **(headers or {})}
    host = (urlsplit(url).hostname or "").lower()
    breaker.check(host)
    send = _via_urllib if _proxied() else _via_pool
    deadline = time.monotonic() + RETRY_BUDGET
    attempt = 0
    while True:
        try:
            status, raw, res_headers = send(url, method, data, all_headers, timeout)
        except NET_FAILURES as exc:
            breaker.failure(host)
            if isinstance(exc, NetError):
                raise
            raise NetError(str(exc) or type(exc).__name__) from exc
        except OSError as exc:  # gaierror, un socket raro: sigue siendo la red
            breaker.failure(host)
            raise NetError(str(exc) or type(exc).__name__) from exc
        retryable = status in RETRY_STATUSES or (status in RETRY_READ_STATUSES and method in ("GET", "HEAD"))
        if not retryable:
            breaker.success(host)
            break
        wait = retry_after(res_headers.get("Retry-After") if res_headers else None, attempt)
        if attempt >= retries or time.monotonic() + wait > deadline:
            # Un 5xx que sigue cuenta para el cortacircuitos; un 429 no: el servicio está vivo, solo pide calma.
            breaker.failure(host) if status >= 500 else breaker.success(host)
            break
        log.info("%s respondió HTTP %d: reintento en %.1f s", host, status, wait)
        _sleep(wait)
        attempt += 1
    text = raw.decode("utf-8", "replace").strip()
    try:
        return status, json.loads(text) if text else None
    except ValueError:
        return status, None
