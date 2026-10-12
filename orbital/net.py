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


def read_body(res, *, timeout: float, limit: int = MAX_BYTES) -> bytes:
    """Lee la respuesta completa en pedazos con un plazo total; corta si se pasa de `limit`."""
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
            raise ValueError("Respuesta demasiado grande")
        chunks.append(chunk)


def read_json(res, *, timeout: float, limit: int = MAX_BYTES):
    return json.loads(read_body(res, timeout=timeout, limit=limit).decode("utf-8"))
