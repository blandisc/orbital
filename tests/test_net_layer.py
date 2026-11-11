"""La capa de red común (orbital/net.py): reintentos con Retry-After, cortacircuitos, reserva de conexiones y NetError.

Un servidor HTTP local de verdad (127.0.0.1) hace de Trakt/TMDB: nada sale a internet.
"""

from __future__ import annotations

import http.server
import json
import socket
import threading
import urllib.error

import pytest

from orbital import net


class _Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"  # deja la conexión abierta entre pedidos (keep-alive)
    script: list = []  # (código, encabezados) por pedido; luego 200
    seen: list = []
    close_after = False

    def log_message(self, *args):
        pass

    def _reply(self):
        length = int(self.headers.get("Content-Length") or 0)
        sent = self.rfile.read(length) if length else b""
        self.seen.append((self.command, self.path, self.client_address[1], self.headers.get("Authorization"), sent))
        status, headers = self.script.pop(0) if self.script else (200, {})
        if status in (301, 302, 307) and "Location" not in headers:
            headers = {"Location": "/final"}
        body = json.dumps({"path": self.path, "status": status}).encode()
        self.send_response(status)
        for k, v in headers.items():
            self.send_header(k, v)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
        if self.close_after:  # cierra sin decirlo en los encabezados (una conexión ociosa que el servidor corta)
            self.close_connection = True

    do_GET = do_POST = _reply


@pytest.fixture
def server(monkeypatch):
    _Handler.script, _Handler.seen = [], []
    httpd = http.server.ThreadingHTTPServer(("127.0.0.1", 0), _Handler)
    thread = threading.Thread(target=httpd.serve_forever, daemon=True)
    thread.start()
    waits: list[float] = []
    monkeypatch.setattr(net, "_sleep", waits.append)
    monkeypatch.setattr(net, "_proxied", lambda: False)
    net.reset()
    yield f"http://127.0.0.1:{httpd.server_address[1]}", _Handler, waits
    httpd.shutdown()
    httpd.server_close()
    net.reset()


def test_a_429_waits_what_retry_after_says_and_retries(server):
    base, handler, waits = server
    handler.script = [(429, {"Retry-After": "2"}), (503, {})]
    status, data = net.http_json(f"{base}/sync")
    assert status == 200 and data == {"path": "/sync", "status": 200}
    assert waits == [2.0, 1.5] and len(handler.seen) == 3


def test_gives_up_after_the_retries_and_returns_the_status(server):
    base, handler, waits = server
    handler.script = [(503, {})] * 5
    status, _ = net.http_json(f"{base}/x")
    assert status == 503 and len(handler.seen) == 3  # uno más dos reintentos


def test_a_long_retry_after_is_not_waited(server):
    base, handler, waits = server
    handler.script = [(429, {"Retry-After": "120"})]
    status, _ = net.http_json(f"{base}/x")
    assert status == 429 and waits == [] and len(handler.seen) == 1  # pasa del tope total: se devuelve ya


def test_a_post_with_500_is_not_repeated(server):
    base, handler, waits = server
    handler.script = [(500, {})]
    status, _ = net.http_json(f"{base}/scrobble/stop", method="POST", body={"a": 1})
    assert status == 500 and len(handler.seen) == 1  # pudo haberse aplicado


def test_a_post_with_503_is_not_repeated_because_it_may_have_arrived(server):
    """El proxy de enfrente puede dar 502/503/504 DESPUÉS de que Trakt aplicó el POST (un `stop`: la vista quedaba doble)."""
    base, handler, waits = server
    for status in (502, 503, 504):
        handler.script, handler.seen = [(status, {})], []
        assert net.http_json(f"{base}/scrobble/stop", method="POST", body={"a": 1})[0] == status
        assert len(handler.seen) == 1


def test_a_post_with_429_is_repeated_and_an_idempotent_post_with_503_too(server):
    base, handler, waits = server
    handler.script = [(429, {"Retry-After": "1"})]
    assert net.http_json(f"{base}/sync/history", method="POST", body={})[0] == 200 and len(handler.seen) == 2
    handler.script, handler.seen = [(503, {})], []
    assert net.http_json(f"{base}/sync/watchlist", method="POST", body={}, idempotent=True)[0] == 200
    assert len(handler.seen) == 2  # quien llama sabe que repetirlo no cambia nada


def test_a_post_on_a_connection_the_server_closed_goes_once_by_a_new_one(server):
    """El servidor cierra una conexión ociosa sin avisar (como Cloudflare): el POST se va por una nueva, una sola vez."""
    import time

    base, handler, _ = server
    handler.close_after = True
    try:
        assert net.http_json(f"{base}/a")[0] == 200
        assert net.pool._free  # el cliente la guardó: no le dijeron que se cerraba
        time.sleep(.2)  # llega el cierre del servidor
    finally:
        handler.close_after = False
    assert net.http_json(f"{base}/scrobble/stop", method="POST", body={"a": 1})[0] == 200
    assert [s[0] for s in handler.seen].count("POST") == 1


def test_errors_that_are_answers_are_not_retried(server):
    base, handler, waits = server
    handler.script = [(400, {})]
    assert net.http_json(f"{base}/oauth/device/token", method="POST", body={})[0] == 400
    assert len(handler.seen) == 1


def test_connections_are_reused(server):
    base, handler, _ = server
    for _ in range(3):
        assert net.http_json(f"{base}/a")[0] == 200
    ports = {port for _, _, port, _, _ in handler.seen}
    assert len(ports) == 1  # una sola conexión (mismo puerto del cliente) para los tres pedidos


def test_a_connection_the_server_closed_is_replaced(server):
    base, handler, _ = server
    assert net.http_json(f"{base}/a")[0] == 200
    for conn, _ in next(iter(net.pool._free.values())):
        conn.sock.shutdown(socket.SHUT_RDWR)  # como si el servidor la hubiera cerrado por ociosa
    assert net.http_json(f"{base}/b")[0] == 200


def test_redirects_are_followed_and_the_session_stays_home(server):
    base, handler, _ = server
    handler.script = [(302, {"Location": "/final"})]
    status, data = net.http_json(f"{base}/start", headers={"Authorization": "Bearer x"})
    assert status == 200 and data["path"] == "/final"
    assert handler.seen[1][3] == "Bearer x"  # mismo servidor: la sesión sigue
    handler.script = [(302, {})]
    status, _ = net.http_json(f"{base}/form", method="POST", body={"a": 1})
    assert status == 200 and handler.seen[-1][0] == "GET"  # como urllib: 302 a un POST sigue como GET


def test_network_failures_are_net_errors_and_open_the_breaker(monkeypatch):
    net.reset()
    calls = []

    def down(*args):
        calls.append(1)
        raise ConnectionRefusedError("rechazada")

    monkeypatch.setattr(net, "_via_pool", down)
    monkeypatch.setattr(net, "_proxied", lambda: False)
    for _ in range(net.BREAKER_FAILURES):
        with pytest.raises(net.NetError):
            net.http_json("https://api.trakt.tv/x")
    with pytest.raises(net.ServiceDown):
        net.http_json("https://api.trakt.tv/y")
    assert len(calls) == net.BREAKER_FAILURES  # el sexto ni se intentó
    assert isinstance(net.ServiceDown("x"), OSError)  # quien atrapa OSError sigue igual
    net.reset()


def test_the_breaker_reopens_after_the_cooldown_and_one_success_closes_it():
    now = [0.0]
    breaker = net.Breaker(failures=2, cooldown=60, clock=lambda: now[0])
    breaker.failure("h")
    breaker.failure("h")
    with pytest.raises(net.ServiceDown):
        breaker.check("h")
    breaker.check("otro")  # cada servicio por su lado
    now[0] = 61
    breaker.check("h")  # pasó la espera: se deja intentar
    breaker.failure("h")  # falla otra vez: vuelve a caer de inmediato
    assert breaker.down("h")
    now[0] = 130
    breaker.check("h")
    breaker.success("h")
    breaker.failure("h")
    assert not breaker.down("h")


def test_net_failures_leave_out_generic_errors():
    assert not issubclass(ValueError, net.NET_FAILURES) and not issubclass(PermissionError, net.NET_FAILURES)
    assert issubclass(urllib.error.URLError, net.NET_FAILURES) and issubclass(TimeoutError, net.NET_FAILURES)
    assert issubclass(net.TooLarge, ValueError) and issubclass(net.BadResponse, ValueError)  # quien atrapaba ValueError


def test_retry_after_reads_seconds_and_dates():
    assert net.retry_after("3", 0) == 3.0
    assert net.retry_after(None, 0) == 0.5 and net.retry_after("", 1) == 1.5
    assert net.retry_after("Wed, 21 Oct 2015 07:28:00 GMT", 0) == 0.0  # una fecha pasada: ya


def test_reading_with_urllib_fails_as_the_network_and_nothing_else(monkeypatch):
    """F9 · quien lee con urllib (complementos, listas, logos) ve los fallos de la red como NET_FAILURES; una dirección
    mal escrita también (antes era un ValueError suelto)."""
    with pytest.raises(net.NetError):
        net.request("localhost/sin-esquema")

    class Cut:
        def read1(self, n):
            raise ConnectionAbortedError("cortada")

        read = read1

    with pytest.raises(net.NET_FAILURES):
        net.read_body(Cut(), timeout=1)

    def broken(req, timeout=None, **kwargs):
        raise OSError(51, "Network is unreachable")

    monkeypatch.setattr(net.urllib.request, "urlopen", broken)
    with pytest.raises(net.NetError):
        net.urlopen("https://example.test/", timeout=1)


def test_a_programming_error_is_never_no_internet(monkeypatch):
    """Un error de programación llega a la bitácora con su nombre: no se disfraza de «sin internet»."""
    from orbital.library import tmdb

    def bug(url, **kwargs):
        raise TypeError("un error de programación")

    monkeypatch.setattr(tmdb, "http_json", bug)
    with pytest.raises(TypeError):
        tmdb.Tmdb("clave")._get("/movie/1")

    def offline(url, **kwargs):
        raise net.NetError("sin red")

    monkeypatch.setattr(tmdb, "http_json", offline)
    with pytest.raises(tmdb.TmdbError):
        tmdb.Tmdb("clave")._get("/movie/1")
