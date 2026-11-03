"""Escribir desde el celular: correo, contraseña o una clave larga se teclean en el teléfono, no con el mando.

La TV abre un formulario (Conectar Stremio, la clave de TMDB…) y pide un código de un solo uso; el QR de la pantalla abre
`https://<tu túnel>/escribir/<código>`, una página de Orbital con esos mismos campos. Lo que mandas desde el celular
se guarda aquí hasta que la TV lo recoge (una vez) y llena el formulario.

Por qué es seguro:
- El código es largo y al azar (como un token), sirve para un solo envío y caduca a los 10 minutos.
- Solo hay uno vivo a la vez: abrir otro formulario o cerrar éste lo anula.
- Lo escrito nunca viaja por los avisos (SSE): el aviso solo dice «llegó» y la TV lo pide a la API local, que lo borra.
- La página no lleva el token de Orbital ni nada guardado: solo los nombres de los campos.

Con propósito «realdebrid» (CA2-A, la clave desde cualquier celular): los campos los pone el servidor, la clave la prueba
el servidor con Real-Debrid antes de aceptarla (un fallo no gasta el código; cinco sí), dura 20 min, la página y la TV
enseñan las mismas dos palabras y la TV pregunta «¿Usar la cuenta …?» antes de guardar. La interfaz nunca la recoge.
"""

from __future__ import annotations

import secrets
import threading
import time
from collections.abc import Callable
from dataclasses import dataclass, field

TTL = 600.0  # s: lo que dura un código
TTLS = {"realdebrid": 1200.0}  # la clave de Real-Debrid: 20 min (hay que ir a buscarla a real-debrid.com)
MAX_FAILS = 5  # claves que Real-Debrid no reconoce: al quinto fallo el código se acaba
# El código de acceso rápido (sin escanear: «…ts.net/clave · KQ7MXR»): sin letras que se confundan (0/O, 1/I/L, 5/S, 2/Z,
# 8/B). 6 de 25 = 244 millones; con 5 fallos en total (no por IP: por el túnel todo llega de 127.0.0.1) adivinarlo es
# imposible en la práctica.
SHORT_ALPHABET = "ACDEFGHJKMNPQRTUVWXY34679"
SHORT_LEN = 6
# Las dos palabras que la página y la TV enseñan iguales: así sabes que el QR es de tu TV.
WORDS = ("sol", "luna", "río", "mar", "nube", "pino", "roca", "lago", "faro", "vela", "tren", "puma", "búho", "coral",
         "hoja", "miel", "trigo", "nieve", "brisa", "cielo", "monte", "playa", "selva", "isla", "duna", "fresa", "mango",
         "limón", "menta", "cacao", "rayo", "trueno", "ola", "perla", "jade", "plata", "cobre", "arena", "musgo", "cedro")
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
    purpose: str | None = None
    words: str | None = None
    lead: str = ""
    submit_label: str = ""
    fails: int = 0
    short: str | None = None


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

    def start(self, title: str, fields, purpose: str | None = None, lead: str = "", submit_label: str = "") -> str | None:
        """Un código nuevo para este formulario (el anterior deja de servir). None si no hay campos válidos."""
        cleaned = clean_fields(fields)
        if not cleaned:
            return None
        with self._lock:
            words = " ".join(secrets.choice(WORDS) for _ in range(2)) if purpose else None
            short = "".join(secrets.choice(SHORT_ALPHABET) for _ in range(SHORT_LEN)) if purpose else None
            self._pending = Pending(secrets.token_urlsafe(18), str(title or "")[:80], cleaned,
                                    self._clock() + TTLS.get(purpose or "", TTL), purpose=purpose, words=words,
                                    lead=str(lead or "")[:240], submit_label=str(submit_label or "")[:40], short=short)
            return self._pending.code

    def short(self, code: str) -> str | None:
        with self._lock:
            p = self._alive(code)
            return p.short if p else None

    def resolve(self, short: str) -> str | None:
        """El código largo detrás de un código de acceso rápido. Un código que no es cuenta como fallo del que está vivo:
        al quinto (en total, venga de donde venga) se acaba y la TV enseña otro."""
        typed = "".join(ch for ch in str(short or "").upper() if ch.isalnum())[:SHORT_LEN + 4]
        with self._lock:
            p = self._pending
            if p is None or p.short is None or p.sent:
                return None
            live = self._alive(p.code)
            if live is None:
                return None
            if typed and secrets.compare_digest(typed, live.short or ""):
                return live.code
            live.fails += 1
            if live.fails >= MAX_FAILS:
                self._pending = None
                self._publish({"type": "remote-input", "code": live.code, "expired": True})  # la TV enseña uno nuevo
            return None

    def words(self, code: str) -> str | None:
        with self._lock:
            p = self._alive(code)
            return p.words if p else None

    def purpose(self, code: str) -> str | None:
        with self._lock:
            p = self._alive(code)
            return p.purpose if p and not p.sent else None

    def fail(self, code: str, why: str) -> str:
        """Lo escrito no sirvió (Real-Debrid no reconoce la clave): no gasta el código, salvo al quinto fallo."""
        with self._lock:
            p = self._alive(code)
            if p is None:
                return "Este código ya no sirve. Vuelve a abrir el formulario en la tele."
            p.fails += 1
            if p.fails >= MAX_FAILS:
                self._pending = None
                self._publish({"type": "remote-input", "code": code, "expired": True})  # la TV enseña uno nuevo
                return f"{why}. Fueron muchos intentos: escanea el código nuevo de la tele."
            return f"{why}. Revísala e inténtalo otra vez."

    def _alive(self, code: str) -> Pending | None:
        p = self._pending
        if p is None or not code or not str(code).isascii() or not secrets.compare_digest(p.code, str(code)):
            return None
        if self._clock() > p.expires:
            self._pending = None
            return None
        return p

    def form(self, code: str) -> dict | None:
        """Lo que pinta la página del celular (sin valores). None si el código no sirve o ya se usó."""
        with self._lock:
            p = self._alive(code)
            if p is None or p.sent:
                return None
            out = {"title": p.title, "fields": p.fields, "minutes": round(TTLS.get(p.purpose or "", TTL) / 60)}
            if p.purpose:
                out.update(purpose=p.purpose, words=p.words, lead=p.lead, submit_label=p.submit_label)
            return out

    def submit(self, code: str, values, extra: dict | None = None) -> str | None:
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
            p.extra.update(extra or {})
            event: dict = {"type": "remote-input", "code": code}
            if p.purpose:  # la TV pregunta «¿Usar la cuenta …?» (nunca la clave)
                event.update(purpose=p.purpose, account=p.extra.get("account"))
        self._publish(event)  # solo «llegó»: lo escrito se pide aparte
        return None

    def take(self, code: str, purpose: str | None = None) -> dict[str, str] | None:
        """La TV recoge lo escrito una sola vez (y el código se termina). Lo de un propósito (la clave de Real-Debrid)
        solo lo recoge su propia ruta del servidor, nunca la interfaz."""
        with self._lock:
            p = self._alive(code)
            if p is None or p.values is None or p.purpose != purpose:
                return None
            values, self._pending = p.values, None
            return values

    def cancel(self, code: str | None = None) -> None:
        with self._lock:
            if code is None or (self._pending and secrets.compare_digest(self._pending.code, str(code))):
                self._pending = None
