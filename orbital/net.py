"""Lectura HTTP robusta para los clientes de internet (Trakt, TMDB, Cinemeta, Stremio, arte, GeForce NOW).

Una red rara no puede tumbar a Orbital: una conexión cortada a media respuesta (IncompleteRead),
reiniciada, con basura en vez de HTTP (BadStatusLine) o que gotea un byte cada medio segundo cuenta como
cualquier otro error de red, con un plazo TOTAL (no solo por lectura) y un tamaño máximo.

`http_json` es la capa de red común de los servicios con API (A6, V5, F9 de la revisión del 10 nov 2026):

- reintenta un 429 (o un 5xx, solo en lo idempotente) una o dos veces, esperando lo que diga `Retry-After`, sin pasar de
  `RETRY_BUDGET`; un POST que pudo haber llegado nunca se repite solo;
- reutiliza la conexión con cada servidor (una reserva por host, segura entre hilos): sin un apretón TLS por pedido;
- un cortacircuitos por servicio: tras `BREAKER_FAILURES` fallos seguidos lo da por caído `BREAKER_COOLDOWN` s y
  responde al momento con `ServiceDown`, para que quien llama use lo que tiene guardado en vez de esperar al plazo;
- los fallos de red salen como `NetError` (que es un OSError: quien atrapa `NET_ERRORS` u `OSError` sigue igual).

`NET_FAILURES` es «la red o el servicio fallaron», sin OSError ni ValueError genéricos (un disco lleno o un error
de programación no son «sin internet»: llegan a la bitácora). Quien lee con urllib directo abre con `urlopen` de aquí y
lee con `read_body`/`read_json`: así todo fallo de la red sale como algo de `NET_FAILURES`. `NET_ERRORS` se queda tan
amplio como antes solo para lo que todavía no se pasa.
"""

from __future__ import annotations

import email.utils
import functools
import http.client
import json
import logging
import select
import ssl
import threading
import time
import urllib.error
import urllib.request
import weakref
from collections.abc import Callable
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
RETRY_STATUSES = frozenset({429})  # en cualquier método: el servidor no hizo nada (Trakt frena antes de aplicar)
# Solo en lo idempotente (GET, HEAD, PUT, DELETE o quien llama lo pide con `idempotent=True`): un 502/503/504 lo puede
# dar el proxy de enfrente DESPUÉS de que el servidor ya aplicó un POST (el `stop` de un scrobble: la vista quedaba doble).
RETRY_SAFE_STATUSES = frozenset({500, 502, 503, 504})
IDEMPOTENT_METHODS = frozenset({"GET", "HEAD", "PUT", "DELETE", "OPTIONS"})
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


def read_chunk(res, size: int) -> bytes:
    """Un pedazo de la respuesta (read1 si lo hay: lo que ya llegó). Una respuesta cortada a media lectura
    (IncompleteRead, un socket raro) sale como NetError; un plazo vencido, como TimeoutError."""
    try:
        return getattr(res, "read1", res.read)(size)
    except (NetError, TimeoutError):
        raise
    except (OSError, http.client.HTTPException) as exc:
        raise NetError(str(exc) or type(exc).__name__) from exc


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
        chunk = read_chunk(res, 64 * 1024)
        if not chunk:
            return b"".join(chunks)
        size += len(chunk)
        if size > limit:
            if truncate:
                return b"".join(chunks + [chunk])[:limit]
            raise TooLarge("Respuesta demasiado grande")
        chunks.append(chunk)


def request(url: str, **kwargs) -> urllib.request.Request:
    """`urllib.request.Request` con una dirección que urllib no sabe abrir (la de un complemento o una lista mal escrita
    en Ajustes: «unknown url type») como NetError, igual que si no contestara."""
    try:
        return urllib.request.Request(url, **kwargs)
    except ValueError as exc:
        raise NetError(f"Dirección inválida: {str(url)[:80]}") from exc


def urlopen(req, *, timeout: float, **kwargs):
    """`urllib.request.urlopen` con los fallos de la red como algo de `NET_FAILURES`: una dirección que urllib no sabe
    abrir (la de un complemento o una lista mal escrita) o un socket raro salen como NetError; HTTPError (con su código),
    URLError y TimeoutError, tal cual. Se busca `urllib.request.urlopen` en cada llamada: las pruebas lo reemplazan."""
    try:
        return urllib.request.urlopen(req, timeout=timeout, **kwargs)
    except (urllib.error.URLError, NetError, TimeoutError, http.client.HTTPException):
        raise
    except ValueError as exc:  # «unknown url type»
        raise NetError(f"Dirección inválida: {exc}") from exc
    except OSError as exc:
        raise NetError(str(exc) or type(exc).__name__) from exc


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
        self.on_recover: Callable[[str], None] | None = None  # un servicio que fallaba volvió a contestar

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
            was_failing = self._count.pop(host, None) is not None
            was_failing = self._until.pop(host, None) is not None or was_failing
        if was_failing and self.on_recover is not None:
            self.on_recover(host)

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
_listeners: list[Callable[[], Callable[[str], None] | None]] = []
_listeners_lock = threading.Lock()


def on_recover(callback: Callable[[str], None]) -> None:
    """Avísame cuando un servicio que fallaba vuelva a contestar (regresó el internet): la cola de Trakt sale sola. Un
    método se guarda con referencia débil: un gestor que ya no existe no se queda escuchando."""
    try:
        ref: Callable[[], Callable[[str], None] | None] = weakref.WeakMethod(callback)  # type: ignore[arg-type]
    except TypeError:
        ref = lambda: callback  # noqa: E731 - una función suelta vive lo que el módulo
    with _listeners_lock:
        _listeners[:] = [r for r in _listeners if r() is not None] + [ref]


def _recovered(host: str) -> None:
    with _listeners_lock:
        callbacks = [cb for cb in (r() for r in _listeners) if cb is not None]
    for callback in callbacks:
        try:
            callback(host)
        except Exception:  # noqa: BLE001 - quien escucha nunca tumba una petición
            log.exception("Error avisando que %s volvió", host)


breaker.on_recover = _recovered


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


def _closed_by_peer(conn: http.client.HTTPConnection) -> bool:
    """¿El servidor ya cerró esta conexión guardada? Una conexión ociosa sana no tiene nada que leer: si el socket se ve
    legible, lo que hay es el cierre (o basura). Se revisa ANTES de mandar, así un POST nunca se repite a ciegas."""
    sock = conn.sock
    if sock is None:
        return False
    try:
        readable, _, _ = select.select([sock], [], [], 0)
    except (OSError, ValueError):  # un socket ya cerrado
        return True
    return bool(readable)


def _send(key: tuple, method: str, target: str, data: bytes | None, headers: dict, timeout: float, safe: bool = True):
    """Un pedido por una conexión de la reserva. Una conexión guardada que el servidor ya cerró se cambia por una nueva
    antes de mandar nada. Si aun así falla al primer byte, se repite una vez con una nueva solo si el pedido es
    idempotente (`safe`): un POST que pudo haber llegado no se repite."""
    for fresh in (False, True):
        conn, reused = pool.take(key, timeout) if not fresh else (_connect(key, timeout), False)
        if reused and _closed_by_peer(conn):
            conn.close()
            conn, reused = _connect(key, timeout), False
        try:
            conn.request(method, target, body=data, headers=headers)
            res = conn.getresponse()
        except _STALE:
            conn.close()
            if reused and not fresh and safe:
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


def _via_pool(url: str, method: str, data: bytes | None, headers: dict, timeout: float, safe: bool = True):
    for _ in range(REDIRECTS + 1):
        parts = urlsplit(url)
        if parts.scheme not in ("http", "https") or not parts.hostname:
            raise NetError(f"Dirección inválida: {url[:80]}")
        key = (parts.scheme, parts.hostname, parts.port or (443 if parts.scheme == "https" else 80))
        target = (parts.path or "/") + (f"?{parts.query}" if parts.query else "")
        status, raw, res_headers = _send(key, method, target, data, headers, timeout, safe)
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


def _via_urllib(url: str, method: str, data: bytes | None, headers: dict, timeout: float, safe: bool = True):
    req = request(url, data=data, method=method, headers=headers)
    try:
        with urlopen(req, timeout=timeout) as res:
            return res.status, read_body(res, timeout=timeout), res.headers
    except urllib.error.HTTPError as exc:
        try:
            raw = exc.read(64 * 1024)
        except (OSError, http.client.HTTPException):  # el cuerpo del error, cortado: basta el código
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
              timeout: float = 10, form: dict | None = None, retries: int = RETRIES,
              idempotent: bool | None = None) -> tuple[int, object]:
    """Una petición JSON que devuelve (código HTTP, cuerpo) también cuando el código es de error: Trakt
    dice «todavía no» con un 400 y «más despacio» con un 429. Un 429 se reintenta siempre; un 5xx, solo si el pedido es
    idempotente (GET, HEAD, PUT, DELETE, o `idempotent=True` de quien sabe que repetirlo no cambia nada), siempre
    dentro de `retries` y `RETRY_BUDGET`; si sigue, se devuelve tal cual. Los fallos de red se lanzan como NetError (y
    ServiceDown si el servicio está dado por caído)."""
    # `form`: como formulario (el inicio de sesión de Microsoft lo pide así); `body`: JSON.
    data = urlencode(form).encode() if form is not None else json.dumps(body).encode() if body is not None else None
    kind = "application/x-www-form-urlencoded" if form is not None else "application/json"
    all_headers = {"User-Agent": "Orbital", "Accept": "application/json",
                   **({"Content-Type": kind} if data is not None else {}), **(headers or {})}
    host = (urlsplit(url).hostname or "").lower()
    breaker.check(host)
    send = _via_urllib if _proxied() else _via_pool
    safe = method.upper() in IDEMPOTENT_METHODS if idempotent is None else bool(idempotent)
    deadline = time.monotonic() + RETRY_BUDGET
    attempt = 0
    while True:
        try:
            status, raw, res_headers = send(url, method, data, all_headers, timeout, safe)
        except NET_FAILURES as exc:
            breaker.failure(host)
            if isinstance(exc, NetError):
                raise
            raise NetError(str(exc) or type(exc).__name__) from exc
        except OSError as exc:  # gaierror, un socket raro: sigue siendo la red
            breaker.failure(host)
            raise NetError(str(exc) or type(exc).__name__) from exc
        retryable = status in RETRY_STATUSES or (status in RETRY_SAFE_STATUSES and safe)
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
