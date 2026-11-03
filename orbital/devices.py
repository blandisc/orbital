"""Las llaves por aparato (AD-3, K1-A; design/addons-contract.json › devices y secrets).

El QR de «Conectar iPhone» lleva un código de una sola vez (10 min); el iPhone lo cambia por su llave propia en POST
/api/devices/pair y la manda en Authorization: Bearer od1.<device_id>.<secreto>. La TV guarda solo la huella del
secreto (sha256: el secreto es al azar y largo, no hace falta una huella lenta), cifrada con las demás claves. Con el
primer aparato emparejado, el token del túnel queda solo para Alexa (K1-13): estuvo a la vista en el QR de antes.
"""

from __future__ import annotations

import hashlib
import hmac
import json
import re
import secrets
import threading
import time

PREFIX = "od1"
CREDENTIAL = "devices"  # en Credentials (DPAPI), junto a las otras claves
CODE_TTL = 600  # s: lo que vive el código del QR
MAX_DEVICES = 10
SEEN_EVERY = 600  # s: «visto» va a disco una vez cada 10 min por aparato
HOUR = 3600
LIMITS = {"secret": 20, "rd_put": 5}  # por aparato y por hora (contrato, secrets › limits)
PLATFORMS = ("iphone", "ipad", "mac")
NAMES = {"iphone": "iPhone", "ipad": "iPad", "mac": "Mac"}
# K1-13: lo único que el token del túnel abre en cuanto hay un aparato con llave (lo que usa la skill de Alexa).
ALEXA_PATHS = frozenset({"/api/ping", "/api/voice", "/api/voice/hints"})
_ID = re.compile(r"^[0-9a-f]{32}$")


class PairError(Exception):
    def __init__(self, status: int, detail: str) -> None:
        super().__init__(detail)
        self.status = status
        self.detail = detail


def _hash(secret: str) -> str:
    return hashlib.sha256(secret.encode("utf-8", "surrogatepass")).hexdigest()


def clean_name(name: object, platform: str) -> str:
    text = re.sub(r"[\x00-\x1f\x7f]", "", str(name or "")).strip()[:60]
    return text or NAMES.get(platform, "iPhone")


class Devices:
    """Los aparatos emparejados con esta consola, el código del QR que está a la vista y los límites de lo que lleva
    clave. Seguro entre hilos (lo usan el puerto público y la interfaz de la TV)."""

    def __init__(self, credentials, clock=time.time) -> None:
        self.credentials = credentials
        self.clock = clock
        self._lock = threading.Lock()
        self._code: tuple[str, float] | None = None
        self._uses: dict[tuple[str, str], list[float]] = {}
        self._cache: dict | None = None

    # --- lo guardado ------------------------------------------------------------------------------------------------
    def _all(self) -> dict:
        if self._cache is None:
            try:
                raw = json.loads(self.credentials.get(CREDENTIAL) or "{}")
            except ValueError:
                raw = {}
            ok = {}
            for k, v in (raw.items() if isinstance(raw, dict) else ()):
                if _ID.match(str(k)) and isinstance(v, dict) and isinstance(v.get("hash"), str):
                    ok[k] = v
            self._cache = ok
        return self._cache

    def _save(self, saved: dict) -> None:
        self._cache = saved
        self.credentials.set(CREDENTIAL, json.dumps(saved, separators=(",", ":")) if saved else None)

    def any(self) -> bool:
        with self._lock:
            return bool(self._all())

    def listing(self, this: str | None = None) -> list[dict]:
        """[{device_id, name, platform, paired_at, seen, this}], el visto más reciente primero."""
        with self._lock:
            saved = self._all()
            out = [{"device_id": k, "name": v.get("name") or NAMES.get(v.get("platform"), "iPhone"),
                    "platform": v.get("platform") or "iphone", "paired_at": v.get("paired_at"),
                    "seen": v.get("seen") or v.get("paired_at"), "this": k == this} for k, v in saved.items()]
        return sorted(out, key=lambda d: float(d["seen"] or 0), reverse=True)

    # --- el código del QR -------------------------------------------------------------------------------------------
    def code(self) -> str:
        """El código vigente; uno nuevo si no hay o ya venció. Uno a la vez: el anterior deja de servir."""
        with self._lock:
            now = self.clock()
            if self._code is None or self._code[1] <= now:
                self._code = (secrets.token_urlsafe(32), now + CODE_TTL)
            return self._code[0]

    def close_code(self) -> None:
        """Se cerró «Conectar iPhone»: el código muere con la pantalla."""
        with self._lock:
            self._code = None

    def pair(self, code: object, name: object, platform: object) -> dict:
        """Cambia el código del QR por una llave propia. PairError(404) para todo lo que falla (mismo mensaje)."""
        with self._lock:
            now = self.clock()
            current = self._code
            if (not isinstance(code, str) or current is None or current[1] <= now
                    or not hmac.compare_digest(code.encode("utf-8", "surrogatepass"), current[0].encode())):
                raise PairError(404, "Este código ya no sirve. Vuelve a abrir «Conectar iPhone» en la TV.")
            kind = platform if platform in PLATFORMS else "iphone"
            saved = dict(self._all())
            if len(saved) >= MAX_DEVICES:
                raise PairError(409, "Ya hay 10 aparatos. Quita uno en Ajustes › Cuentas de la TV.")
            self._code = None  # de una sola vez
            device_id = secrets.token_hex(16)
            secret = secrets.token_urlsafe(32)
            saved[device_id] = {"name": clean_name(name, kind), "platform": kind, "hash": _hash(secret),
                                "paired_at": now, "seen": now}
            self._save(saved)
            return {"device_id": device_id, "key": f"{PREFIX}.{device_id}.{secret}", "name": saved[device_id]["name"],
                    "platform": kind}

    # --- la llave en cada petición ----------------------------------------------------------------------------------
    @staticmethod
    def is_key(token: str) -> bool:
        return token.startswith(PREFIX + ".")

    def check(self, token: str) -> tuple[str, dict | None]:
        """("ok", aparato) | ("removed", None): el id tiene forma pero ya no está | ("bad", None)."""
        parts = token.split(".")
        if len(parts) != 3 or parts[0] != PREFIX or not _ID.match(parts[1]) or not parts[2]:
            return "bad", None
        with self._lock:
            device = self._all().get(parts[1])
            if device is None:
                return "removed", None
            if not hmac.compare_digest(_hash(parts[2]).encode(), str(device["hash"]).encode()):
                return "bad", None
            now = self.clock()
            if now - float(device.get("seen") or 0) >= SEEN_EVERY:
                saved = dict(self._all())
                saved[parts[1]] = {**device, "seen": now}
                self._save(saved)
            return "ok", {"device_id": parts[1], "name": device.get("name") or "", "platform": device.get("platform") or "iphone"}

    def remove(self, device_id: str) -> bool:
        with self._lock:
            saved = dict(self._all())
            if saved.pop(device_id, None) is None:
                return False
            self._save(saved)
        with self._lock:
            self._uses = {k: v for k, v in self._uses.items() if k[0] != device_id}
        return True

    def allow(self, device_id: str, kind: str) -> bool:
        """¿Le quedan usos de lo que lleva clave esta hora? (20 lecturas, 5 cambios de la clave de Real-Debrid)."""
        with self._lock:
            now = self.clock()
            recent = [t for t in self._uses.get((device_id, kind), []) if now - t < HOUR]
            if len(recent) >= LIMITS[kind]:
                self._uses[(device_id, kind)] = recent
                return False
            self._uses[(device_id, kind)] = recent + [now]
            return True
