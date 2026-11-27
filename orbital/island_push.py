"""LA-B (Fernando, 26 nov 2026): la TV mantiene al día la isla «Viendo en la TV» del iPhone, aunque la app esté cerrada.

Antes el iPhone preguntaba cada 5 s, solo con la app abierta: al cambiar de capítulo en la TV, la isla se quedaba en el
anterior hasta abrir Orbital. Ahora el iPhone le da a la TV el «buzón» de su actividad (`POST /api/companion/activity`) y
la TV, al cambiar lo que suena (otro capítulo, pausa, se movió la posición, terminó), le avisa por el servicio de Apple
(APNs). Sin servidores de fuera: la TV firma el aviso con la llave de Apple de Fernando.

La llave: `AuthKey_<ID>.p8` (developer.apple.com › Keys, con «Apple Push Notifications service») en la carpeta de
`config.yaml` (`%APPDATA%\\orbital`). Sin llave no pasa nada: la isla se pone al día como antes, al abrir la app.

Sin dependencias nuevas: la firma (ES256, P-256) y la conexión HTTP/2 que pide Apple van aquí, cortas y a la medida.
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import json
import logging
import socket
import ssl
import struct
import threading
import time
from collections.abc import Callable
from pathlib import Path

log = logging.getLogger(__name__)

TEAM_ID = "B7KRCF776Z"
TOPIC = "mx.iracheta.orbital.push-type.liveactivity"
HOSTS = {True: "api.sandbox.push.apple.com", False: "api.push.apple.com"}
APPLE_EPOCH = 978307200  # 1 ene 2001: así cuenta las fechas el iPhone (`Date` de Swift)
CHECK = 2.0  # s entre vistazos a lo que suena
DRIFT = 15.0  # s: si la posición se aleja más de esto de lo esperado, se avisa (igual que `DesignTokens.Widget.tvDrift`)
TOKEN_LIFE = 50 * 60  # s: Apple pide renovar la firma entre 20 y 60 min


# --- Firma ES256 (curva P-256) -----------------------------------------------------------------------------------------
_P = 0xFFFFFFFF00000001000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFF
_A = _P - 3
_N = 0xFFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551
_G = (0x6B17D1F2E12C4247F8BCE6E563A440F277037D812DEB33A0F4A13945D898C296,
      0x4FE342E2FE1A7F9B8EE7EB4A7C0F9E162BCE33576B315ECECBB6406837BF51F5)


def _add(p, q):
    if p is None:
        return q
    if q is None:
        return p
    if p[0] == q[0] and (p[1] + q[1]) % _P == 0:
        return None
    if p == q:
        m = (3 * p[0] * p[0] + _A) * pow(2 * p[1], -1, _P)
    else:
        m = (q[1] - p[1]) * pow(q[0] - p[0], -1, _P)
    x = (m * m - p[0] - q[0]) % _P
    return x, (m * (p[0] - x) - p[1]) % _P


def _mul(k: int, p=_G):
    out = None
    while k:
        if k & 1:
            out = _add(out, p)
        p = _add(p, p)
        k >>= 1
    return out


def _nonce(d: int, h: bytes) -> int:
    """El número de un solo uso, determinista (RFC 6979): sin depender de un buen azar."""
    x, h1 = d.to_bytes(32, "big"), (int.from_bytes(h, "big") % _N).to_bytes(32, "big")
    v, k = b"\x01" * 32, b"\x00" * 32
    k = hmac.new(k, v + b"\x00" + x + h1, hashlib.sha256).digest()
    v = hmac.new(k, v, hashlib.sha256).digest()
    k = hmac.new(k, v + b"\x01" + x + h1, hashlib.sha256).digest()
    v = hmac.new(k, v, hashlib.sha256).digest()
    while True:
        v = hmac.new(k, v, hashlib.sha256).digest()
        t = int.from_bytes(v, "big")
        if 1 <= t < _N:
            return t
        k = hmac.new(k, v + b"\x00", hashlib.sha256).digest()
        v = hmac.new(k, v, hashlib.sha256).digest()


def sign(d: int, message: bytes) -> bytes:
    """Firma ES256 de JWT: r || s, 32 bytes cada uno."""
    h = hashlib.sha256(message).digest()
    z = int.from_bytes(h, "big")
    while True:
        k = _nonce(d, h)
        point = _mul(k)
        assert point is not None  # k va de 1 a N-1: nunca da el punto al infinito
        r = point[0] % _N
        s = pow(k, -1, _N) * (z + r * d) % _N
        if r and s:
            return r.to_bytes(32, "big") + s.to_bytes(32, "big")


def verify(public, message: bytes, signature: bytes) -> bool:
    """Para las pruebas: la firma corresponde a la llave pública."""
    r, s = int.from_bytes(signature[:32], "big"), int.from_bytes(signature[32:], "big")
    z = int.from_bytes(hashlib.sha256(message).digest(), "big")
    w = pow(s, -1, _N)
    point = _add(_mul(z * w % _N), _mul(r * w % _N, public))
    return point is not None and point[0] % _N == r


def private_key(pem: str) -> int:
    """El número secreto de la llave `.p8` de Apple (PKCS#8 con una llave EC P-256)."""
    der = base64.b64decode("".join(line for line in pem.splitlines() if line and not line.startswith("-----")))
    at = der.find(b"\x02\x01\x01\x04\x20")  # ECPrivateKey: versión 1 y el secreto de 32 bytes
    if at < 0:
        raise ValueError("La llave no es de Apple (EC P-256)")
    return int.from_bytes(der[at + 5:at + 37], "big")


def _b64(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def provider_token(key_id: str, d: int, now: float | None = None) -> str:
    header = _b64(json.dumps({"alg": "ES256", "kid": key_id}).encode())
    claims = _b64(json.dumps({"iss": TEAM_ID, "iat": int(now if now is not None else time.time())}).encode())
    return f"{header}.{claims}.{_b64(sign(d, f'{header}.{claims}'.encode()))}"


# --- HTTP/2 mínimo (lo que pide Apple: una petición POST y su respuesta) ------------------------------------------------
def _frame(kind: int, flags: int, stream: int, payload: bytes = b"") -> bytes:
    return struct.pack(">I", len(payload))[1:] + bytes([kind, flags]) + struct.pack(">I", stream) + payload


def _literal(name: str, value: str) -> bytes:
    """HPACK sin índices ni Huffman (permitido y simple)."""
    def text(s: bytes) -> bytes:
        n = len(s)
        if n < 127:
            return bytes([n]) + s
        n -= 127
        out = bytearray([127])
        while n >= 128:
            out.append((n & 127) | 128)
            n >>= 7
        return bytes(out) + bytes([n]) + s
    return b"\x00" + text(name.encode()) + text(value.encode())


_DIGITS = {"00000": "0", "00001": "1", "00010": "2", "011001": "3", "011010": "4", "011011": "5", "011100": "6",
           "011101": "7", "011110": "8", "011111": "9"}  # HPACK Huffman de las cifras


def _status(block: bytes) -> int | None:
    """El `:status` (la primera cabecera de la respuesta): indexado (200 = 0x88) o literal con el nombre 8, en claro o en
    Huffman."""
    statics = {0x88: 200, 0x89: 204, 0x8A: 206, 0x8B: 304, 0x8C: 400, 0x8D: 404, 0x8E: 500}
    if not block:
        return None
    if block[0] in statics:
        return statics[block[0]]
    if block[0] not in (0x48, 0x08, 0x18) or len(block) < 2:
        return None
    n, raw = block[1] & 0x7F, block[2:2 + (block[1] & 0x7F)]
    if not block[1] & 0x80:
        return int(raw) if len(raw) == n and raw.isdigit() else None
    bits, text, code = "".join(f"{b:08b}" for b in raw), "", ""
    for bit in bits:
        code += bit
        if code in _DIGITS:
            text, code = text + _DIGITS[code], ""
        if len(text) == 3:
            return int(text)
    return None


def http2_post(host: str, path: str, headers: dict[str, str], body: bytes, timeout: float = 10.0) -> tuple[int | None, bytes]:
    """Un POST por HTTP/2 con TLS. Devuelve el estado y el cuerpo (Apple explica ahí el motivo de un rechazo)."""
    context = ssl.create_default_context()
    context.set_alpn_protocols(["h2"])
    with socket.create_connection((host, 443), timeout=timeout) as raw, context.wrap_socket(raw, server_hostname=host) as tls:
        if tls.selected_alpn_protocol() != "h2":
            raise OSError("El servidor no habla HTTP/2")
        block = b"".join(_literal(k, v) for k, v in
                         [(":method", "POST"), (":scheme", "https"), (":authority", host), (":path", path),
                          *headers.items(), ("content-length", str(len(body)))])
        tls.sendall(b"PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n" + _frame(4, 0, 0) + _frame(1, 4, 1, block) + _frame(0, 1, 1, body))
        status, data, buffer = None, b"", b""
        while True:
            while len(buffer) < 9 or len(buffer) < 9 + int.from_bytes(buffer[:3], "big"):
                chunk = tls.recv(65536)
                if not chunk:
                    return status, data
                buffer += chunk
            size, kind, flags = int.from_bytes(buffer[:3], "big"), buffer[3], buffer[4]
            stream, payload, buffer = int.from_bytes(buffer[5:9], "big") & 0x7FFFFFFF, buffer[9:9 + size], buffer[9 + size:]
            if kind == 4 and not flags & 1:
                tls.sendall(_frame(4, 1, 0))  # SETTINGS: se acepta
            elif kind == 7:  # GOAWAY
                return status, data or payload[8:]
            elif stream == 1 and kind == 1:
                if flags & 0x20:  # PRIORITY delante del bloque
                    payload = payload[5:]
                status = status or _status(payload)
                if flags & 1:
                    return status, data
            elif stream == 1 and kind == 0:
                data += payload
                if flags & 1:
                    return status, data
            elif stream == 1 and kind == 3:  # RST_STREAM
                return status, data


# --- Lo que se le manda a la isla -------------------------------------------------------------------------------------
def _episode(season: int | None, episode: int | None, label: str, language: str) -> str:
    if episode is None:
        return label
    english = language.lower().startswith("en")
    if season == 0:
        return ("Special" if english else "Especial") + f" · E{episode}"
    if season is None:
        return f"E{episode}"
    return f"{'S' if english else 'T'}{season} E{episode}"


def poster_name(now: dict) -> str:
    """El nombre con que el iPhone guarda el póster en su App Group (`WidgetLists.imageFileName`, con «tv-»)."""
    key = now.get("meta_id") or now.get("title") or ""
    return "tv-" + "".join(c if c.isalnum() else "_" for c in key) + ".jpg"


def content_state(now: dict, language: str, at: float) -> dict:
    """La `TVActivityAttributes.ContentState` del iPhone, armada aquí (las mismas llaves, las fechas en su cuenta)."""
    live = bool(now.get("live"))
    detail = (now.get("channel") or "") if live else _episode(now.get("season"), now.get("episode"),
                                                                 now.get("episode_label") or "", language)
    return {"title": now.get("episode_title") or now.get("title") or "", "detail": detail, "poster": poster_name(now),
            "position": float(now.get("position") or 0), "duration": float(now.get("duration") or 0),
            "measuredAt": at - APPLE_EPOCH, "paused": bool(now.get("paused")), "live": live, "language": language}


def worth_telling(last: dict | None, state: dict) -> bool:
    """Lo mismo que cuida el iPhone: otro título, pausa, en vivo, o la barra ya no cae donde iba."""
    if last is None:
        return True
    if any(last[k] != state[k] for k in ("title", "detail", "paused", "live", "language")):
        return True
    if abs((last["measuredAt"] - last["position"] + last["duration"]) - (state["measuredAt"] - state["position"] + state["duration"])) >= DRIFT:
        return True
    return state["paused"] and abs(last["position"] - state["position"]) >= DRIFT


class IslandPush:
    """Guarda el buzón del iPhone y, mientras haya algo en la TV, avisa a la isla cuando cambia."""

    def __init__(self, folder: Path, now: Callable[[], dict | None],
                 send: Callable[[str, str, dict[str, str], bytes], tuple[int | None, bytes]] = http2_post,
                 clock: Callable[[], float] = time.time) -> None:
        self.folder, self.now, self.send, self.clock = folder, now, send, clock
        self.file = folder / "island.json"
        self._last: dict | None = None
        self._jwt: tuple[float, str] | None = None
        self._thread: threading.Thread | None = None
        self._lock = threading.Lock()

    # El buzón
    def register(self, token: str, language: str, sandbox: bool) -> None:
        if not token or len(token) > 400 or any(c not in "0123456789abcdef" for c in token):
            raise ValueError("Buzón inválido")
        with self._lock:
            self.file.write_text(json.dumps({"token": token, "language": language[:12] or "es", "sandbox": bool(sandbox)}), "utf-8")
            self._last = None  # el buzón nuevo no ha visto nada: se le manda lo de ahora
        self.start()

    def registration(self) -> dict | None:
        try:
            data = json.loads(self.file.read_text("utf-8"))
        except (OSError, ValueError):
            return None
        return data if isinstance(data, dict) and data.get("token") else None

    # La llave
    def key(self) -> tuple[str, int] | None:
        for path in sorted(self.folder.glob("AuthKey_*.p8")):
            try:
                return path.stem.removeprefix("AuthKey_"), private_key(path.read_text("utf-8"))
            except (OSError, ValueError):
                log.warning("La llave de Apple %s no se pudo leer", path.name)
        return None

    def _token(self, key_id: str, d: int) -> str:
        if self._jwt is None or self.clock() - self._jwt[0] > TOKEN_LIFE:
            self._jwt = (self.clock(), provider_token(key_id, d, self.clock()))
        return self._jwt[1]

    # Un vistazo
    def tick(self) -> bool:
        """Revisa lo que suena y avisa si cambió. Da True si mandó algo."""
        reg, key = self.registration(), self.key()
        if reg is None or key is None:
            return False
        now = self.now()
        at = self.clock()
        if now is None or not (now.get("duration") or now.get("live")):
            if self._last is None or self._last.get("ended"):
                return False
            body = {"aps": {"timestamp": int(at), "event": "end", "dismissal-date": int(at), "content-state": self._last}}
            self._last = {"ended": True}
            return self._post(reg, key, body, priority="10")
        state = content_state(now, reg.get("language") or "es", at)
        if self._last is not None and not self._last.get("ended") and not worth_telling(self._last, state):
            return False
        self._last = state
        aps: dict = {"timestamp": int(at), "event": "update", "content-state": state}
        if not state["paused"] and not state["live"] and state["duration"] > 0:
            aps["stale-date"] = int(at + state["duration"] - state["position"])
        return self._post(reg, key, {"aps": aps}, priority="10")

    def _post(self, reg: dict, key: tuple[str, int], body: dict, priority: str) -> bool:
        headers = {"authorization": f"bearer {self._token(*key)}", "apns-topic": TOPIC, "apns-push-type": "liveactivity",
                   "apns-priority": priority, "content-type": "application/json"}
        try:
            status, reply = self.send(HOSTS[bool(reg.get("sandbox"))], f"/3/device/{reg['token']}", headers,
                                      json.dumps(body, separators=(",", ":")).encode())
        except OSError as error:
            log.info("Aviso a la isla sin mandar: %s", error)
            self._last = None  # se reintenta en el siguiente vistazo
            return False
        if status != 200:
            log.info("Apple no aceptó el aviso a la isla (%s): %s", status, reply[:200])
            if status == 410 or b"BadDeviceToken" in reply:  # la actividad ya no existe: se olvida el buzón
                self.file.unlink(missing_ok=True)
            elif status == 403:
                self._jwt = None
            return False
        return True

    def start(self) -> None:
        if (self._thread and self._thread.is_alive()) or self.registration() is None or self.key() is None:
            return
        self._thread = threading.Thread(target=self._run, name="island-push", daemon=True)
        self._thread.start()

    def _run(self) -> None:
        while self.registration() is not None:
            try:
                self.tick()
            except Exception:  # noqa: BLE001 - la isla nunca tumba a Orbital
                log.exception("Aviso a la isla")
            time.sleep(CHECK)
