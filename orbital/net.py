"""Lectura HTTP robusta para los clientes de internet (Cinemeta, Stremio, arte, GeForce NOW).

Una red rara no puede tumbar a Orbital: una conexión cortada a media respuesta (IncompleteRead),
reiniciada, con basura en vez de HTTP (BadStatusLine) o que gotea un byte cada medio segundo cuenta como
cualquier otro error de red, con un plazo TOTAL (no solo por lectura) y un tamaño máximo.
"""

from __future__ import annotations

import http.client
import json
import time

# Todo lo que puede lanzar urllib al leer: URLError/HTTPError y TimeoutError son OSError.
NET_ERRORS = (OSError, http.client.HTTPException, ValueError)

MAX_BYTES = 16 * 1024 * 1024  # una respuesta de catálogo nunca pesa tanto


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
            raise ValueError("Respuesta demasiado grande")
        chunks.append(chunk)


def read_json(res, *, timeout: float, limit: int = MAX_BYTES):
    return json.loads(read_body(res, timeout=timeout, limit=limit).decode("utf-8"))


def http_json(url: str, *, method: str = "GET", headers: dict | None = None, body: dict | None = None,
              timeout: float = 10, form: dict | None = None) -> tuple[int, object]:
    """Una petición JSON que devuelve (código HTTP, cuerpo) también cuando el código es de error: Trakt
    dice «todavía no» con un 400 y «más despacio» con un 429. Los fallos de red sí se lanzan (NET_ERRORS)."""
    import urllib.error
    import urllib.request
    from urllib.parse import urlencode

    # `form`: como formulario (el inicio de sesión de Microsoft lo pide así); `body`: JSON.
    data = urlencode(form).encode() if form is not None else json.dumps(body).encode() if body is not None else None
    kind = "application/x-www-form-urlencoded" if form is not None else "application/json"
    req = urllib.request.Request(url, data=data, method=method,
                                 headers={"User-Agent": "Orbital", "Accept": "application/json",
                                          **({"Content-Type": kind} if data is not None else {}),
                                          **(headers or {})})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as res:
            raw = read_body(res, timeout=timeout)
            status = res.status
    except urllib.error.HTTPError as exc:
        try:
            raw = exc.read(64 * 1024)
        except NET_ERRORS:
            raw = b""
        status = exc.code
    text = raw.decode("utf-8", "replace").strip()
    try:
        return status, json.loads(text) if text else None
    except ValueError:
        return status, None
