"""Escribir desde el celular: correo, contraseña o una clave larga se teclean en el teléfono, no con el mando.

La TV abre un formulario (Conectar Stremio, la clave de TMDB…) y pide un código de un solo uso; el QR de la pantalla abre
`https://<tu túnel>/escribir/<código>`, una página de Orbital con esos mismos campos. Lo que mandas desde el celular
se guarda aquí hasta que la TV lo recoge (una vez) y llena el formulario.

Por qué es seguro:
- El código es largo y al azar (como un token), sirve para un solo envío y caduca a los 10 minutos.
- Solo hay uno vivo a la vez: abrir otro formulario o cerrar éste lo anula.
- Lo escrito nunca viaja por los avisos (SSE): el aviso solo dice «llegó» y la TV lo pide a la API local, que lo borra.
- La página no lleva el token de Orbital ni nada guardado: solo los nombres de los campos.
"""

from __future__ import annotations

import secrets
import threading
import time
from collections.abc import Callable
from dataclasses import dataclass, field

TTL = 600.0  # s: lo que dura un código
MAX_FIELDS = 4
MAX_VALUE = 512  # una clave de API mide 32-64; un correo, menos de 100


@dataclass
class Pending:
    code: str
    title: str
    fields: list[dict]
    expires: float
    values: dict[str, str] | None = None
    sent: bool = False
    extra: dict = field(default_factory=dict)


def clean_fields(fields) -> list[dict]:
    """Solo nombre, etiqueta y si es secreto (lo demás que mande la interfaz se ignora)."""
    out = []
    for f in (fields if isinstance(fields, list) else [])[:MAX_FIELDS]:
        if not isinstance(f, dict):
            continue
        name, label = str(f.get("name") or "")[:40], str(f.get("label") or "")[:80]
        if name.isidentifier() and label:
            out.append({"name": name, "label": label, "secret": bool(f.get("secret")), "optional": bool(f.get("optional"))})
    return out


class RemoteInput:
    def __init__(self, publish: Callable[[dict], None] | None = None, clock: Callable[[], float] = time.monotonic) -> None:
        self._publish = publish or (lambda event: None)
        self._clock = clock
        self._lock = threading.Lock()
        self._pending: Pending | None = None

    def start(self, title: str, fields) -> str | None:
        """Un código nuevo para este formulario (el anterior deja de servir). None si no hay campos válidos."""
        cleaned = clean_fields(fields)
        if not cleaned:
            return None
        with self._lock:
            self._pending = Pending(secrets.token_urlsafe(18), str(title or "")[:80], cleaned, self._clock() + TTL)
            return self._pending.code

    def _alive(self, code: str) -> Pending | None:
        p = self._pending
        if p is None or not code or not secrets.compare_digest(p.code, str(code)):
            return None
        if self._clock() > p.expires:
            self._pending = None
            return None
        return p

    def form(self, code: str) -> dict | None:
        """Lo que pinta la página del celular (sin valores). None si el código no sirve o ya se usó."""
        with self._lock:
            p = self._alive(code)
            return None if p is None or p.sent else {"title": p.title, "fields": p.fields}

    def submit(self, code: str, values) -> str | None:
        """Lo escrito en el celular. None si quedó; si no, por qué no («caducó», «falta…»)."""
        with self._lock:
            p = self._alive(code)
            if p is None or p.sent:
                return "Este código ya no sirve. Vuelve a abrir el formulario en la tele."
            if not isinstance(values, dict):
                return "No llegó nada."
            got: dict[str, str] = {}
            for f in p.fields:
                value = values.get(f["name"], "")
                if not isinstance(value, str) or len(value) > MAX_VALUE:
                    return f"«{f['label']}» no es válido."
                if not f["optional"] and not value.strip():
                    return f"Falta «{f['label']}»."
                got[f["name"]] = value
            p.values, p.sent = got, True
        self._publish({"type": "remote-input", "code": code})  # solo «llegó»: lo escrito se pide aparte
        return None

    def take(self, code: str) -> dict[str, str] | None:
        """La TV recoge lo escrito una sola vez (y el código se termina)."""
        with self._lock:
            p = self._alive(code)
            if p is None or p.values is None:
                return None
            values, self._pending = p.values, None
            return values

    def cancel(self, code: str | None = None) -> None:
        with self._lock:
            if code is None or (self._pending and secrets.compare_digest(self._pending.code, str(code))):
                self._pending = None
