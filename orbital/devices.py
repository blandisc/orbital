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
REMOVED = "devices_removed"  # los ids quitados (sin huella): «Esta TV te quitó» contra «Tu TV es nueva» (TEC-30)
TV_ID = "tv_id"  # quién es esta consola: una TV reinstalada tiene otro (TEC-30)
MAX_REMOVED = 50
INVITES = "devices_invites"  # las invitaciones de un toque, por su huella (CX4-A)
INVITE_TTL = 7 * 86400  # s: lo que vive una invitación (viaja por iCloud al iPad)
UPGRADE_TTL = 180  # s: lo que espera el sí de la TV un iPhone que pasa del token a su llave (CX8-A)
CODE_TTL = 600  # s: lo que vive el código del QR
MAX_DEVICES = 10
SEEN_EVERY = 600  # s: «visto» va a disco una vez cada 10 min por aparato
HOUR = 3600
LIMITS = {"secret": 20, "rd_put": 5}  # por aparato y por hora (contrato, secrets › limits)
PLATFORMS = ("iphone", "ipad", "mac")  # las llaves de `enabled` del contrato
PAIRED = ("iphone", "ipad")  # CX1-B: la Mac nunca habla con la TV (solo recibe tu clave de Real-Debrid por iCloud)
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


def pairable(platform: object) -> str:
    if platform == "mac":
        raise PairError(422, "La Mac no se conecta a la TV: recibe tu clave de Real-Debrid por iCloud, desde tu iPhone.")
    return platform if platform in PAIRED else "iphone"


def may_remove(mine: dict, target: str) -> bool:
    """CX5: un iPhone quita a cualquiera; los demás aparatos, solo a sí mismos (la TV, desde Cuentas, a todos)."""
    return mine.get("platform") == "iphone" or mine.get("device_id") == target


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
        self._upgrade: dict | None = None

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

    def tv_id(self) -> str:
        with self._lock:
            current = self.credentials.get(TV_ID)
            if not current:
                current = secrets.token_hex(8)
                self.credentials.set(TV_ID, current)
            return current

    def _removed(self) -> list[str]:
        try:
            raw = json.loads(self.credentials.get(REMOVED) or "[]")
        except ValueError:
            raw = []
        return [r for r in raw if isinstance(r, str)] if isinstance(raw, list) else []

    def any(self) -> bool:
        with self._lock:
            return bool(self._all())

    def listing(self, this: str | None = None) -> list[dict]:
        """[{device_id, name, platform, paired_at, seen, this}], el visto más reciente primero."""
        with self._lock:
            saved = self._all()
            out = [{"device_id": k, "name": v.get("name") or NAMES.get(v.get("platform"), "iPhone"),
                    "platform": v.get("platform") or "iphone", "paired_at": v.get("paired_at"),
                    "seen": v.get("seen") or v.get("paired_at"), "this": k == this,
                    **({"invited_by": (saved.get(v["invited_by"]) or {}).get("name")} if v.get("invited_by") else {})}
                   for k, v in saved.items()]
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

    def pair(self, code: object, name: object, platform: object, previous: str = "") -> dict:
        """Cambia el código del QR por una llave propia. PairError(404) para todo lo que falla (mismo mensaje). Con la
        llave vieja de ese aparato (`previous`, TEC-32) se queda con su renglón y su device_id: solo cambia el secreto
        y no ocupa otro lugar de los 10. Sin ella es un aparato nuevo."""
        mine = self._owner(previous) if previous else None
        kind = pairable(platform)
        with self._lock:
            now = self.clock()
            current = self._code
            invited_by = None
            if (isinstance(code, str) and current is not None and current[1] > now
                    and hmac.compare_digest(code.encode("utf-8", "surrogatepass"), current[0].encode())):
                self._check_room(mine)
                self._code = None  # de una sola vez
            else:  # CX4-A: la invitación de un toque del iPhone, solo para un iPad
                invited_by = self._invite_of(code, now) if kind == "ipad" else None
                if invited_by is None:
                    raise PairError(404, "Este código ya no sirve. Vuelve a abrir «Conectar iPhone» en la TV.")
                self._check_room(mine)
                self._drop_invites(lambda v: v.get("by") == invited_by)
            return self._issue(name, kind, now, mine, invited_by)

    def _check_room(self, mine: str | None) -> None:
        if mine is None and len(self._all()) >= MAX_DEVICES:
            raise PairError(409, "Ya hay 10 aparatos. Quita uno en Ajustes › Cuentas de la TV.")

    def _issue(self, name: object, kind: str, now: float, mine: str | None = None, invited_by: str | None = None) -> dict:
        """Una llave nueva (con el lock tomado). Con `mine`, el mismo renglón con otro secreto."""
        saved = dict(self._all())
        device_id = mine if mine in saved else secrets.token_hex(16)
        secret = secrets.token_urlsafe(32)
        before = saved.get(device_id) or {}
        saved[device_id] = {"name": clean_name(name, kind), "platform": kind, "hash": _hash(secret),
                            "paired_at": before.get("paired_at") or now, "seen": now}
        by = saved.get(invited_by or "") or {}
        if invited_by:
            saved[device_id]["invited_by"] = invited_by
        self._save(saved)
        return {"device_id": device_id, "key": f"{PREFIX}.{device_id}.{secret}", "name": saved[device_id]["name"],
                "platform": kind, "invited_by": by.get("name") if invited_by else None}

    # --- la invitación de un toque (CX4-A): el iPhone la pide con su llave; viaja por iCloud; un iPad la usa -------
    def _invites(self) -> dict:
        try:
            raw = json.loads(self.credentials.get(INVITES) or "{}")
        except ValueError:
            raw = {}
        return {k: v for k, v in raw.items() if isinstance(v, dict)} if isinstance(raw, dict) else {}

    def _drop_invites(self, which) -> None:
        kept = {k: v for k, v in self._invites().items() if not which(v)}
        self.credentials.set(INVITES, json.dumps(kept) if kept else None)

    def _invite_of(self, code: object, now: float) -> str | None:
        """Quién invitó con este código (si sigue vivo y su iPhone sigue emparejado)."""
        if not isinstance(code, str) or not code:
            return None
        found = self._invites().get(_hash(code))
        if not found or float(found.get("expires") or 0) <= now or found.get("by") not in self._all():
            return None
        return str(found["by"])

    def invite(self, by: str) -> dict:
        """Un código de una sola vez, de 7 días, para un iPad. Uno vivo por iPhone: pedir otro anula el anterior."""
        with self._lock:
            now = self.clock()
            self._drop_invites(lambda v: v.get("by") == by or float(v.get("expires") or 0) <= now)
            code = secrets.token_urlsafe(32)
            invites = self._invites()
            invites[_hash(code)] = {"by": by, "expires": now + INVITE_TTL}
            self.credentials.set(INVITES, json.dumps(invites))
            return {"code": code, "expires": now + INVITE_TTL, "platform": "ipad"}

    # --- de token del túnel a llave (CX8-A): una vez, con el sí en la pantalla de la TV ------------------------------
    def ask_upgrade(self, name: object, platform: object) -> str:
        """Un iPhone con el token de antes pide su llave: queda esperando el sí en la TV (uno a la vez, 3 min)."""
        kind = pairable(platform)
        with self._lock:
            self._check_room(None)
            ident = secrets.token_hex(8)
            self._upgrade = {"id": ident, "name": clean_name(name, kind), "platform": kind,
                             "expires": self.clock() + UPGRADE_TTL, "state": "waiting", "result": None}
            return ident

    def pending_upgrade(self) -> dict | None:
        with self._lock:
            up = self._upgrade
            if up is None or up["expires"] <= self.clock() or up["state"] != "waiting":
                return None
            return {"id": up["id"], "name": up["name"], "platform": up["platform"]}

    def decide_upgrade(self, ident: str, yes: bool) -> bool:
        """El sí (o el no) de la TV. False si ya no hay nada esperando con ese id."""
        with self._lock:
            up = self._upgrade
            if up is None or up["id"] != ident or up["state"] != "waiting" or up["expires"] <= self.clock():
                return False
            if yes:
                self._check_room(None)
                up["result"] = self._issue(up["name"], up["platform"], self.clock())
            up["state"] = "ok" if yes else "denied"
            return True

    def upgrade_result(self, ident: str) -> tuple[str, dict | None]:
        """("waiting" | "ok" | "denied" | "gone", llave). La llave se entrega una sola vez."""
        with self._lock:
            up = self._upgrade
            if up is None or up["id"] != ident:
                return "gone", None
            if up["state"] == "waiting" and up["expires"] <= self.clock():
                self._upgrade = None
                return "gone", None
            if up["state"] == "waiting":
                return "waiting", None
            self._upgrade = None
            return up["state"], up["result"]

    # --- la llave en cada petición ----------------------------------------------------------------------------------
    @staticmethod
    def is_key(token: str) -> bool:
        return token.startswith(PREFIX + ".")

    def _owner(self, token: str) -> str | None:
        """El device_id de una llave válida (sin anotar «visto»)."""
        parts = token.split(".")
        if len(parts) != 3 or parts[0] != PREFIX or not _ID.match(parts[1]):
            return None
        with self._lock:
            device = self._all().get(parts[1])
        if device is None or not hmac.compare_digest(_hash(parts[2]).encode(), str(device["hash"]).encode()):
            return None
        return parts[1]

    def check(self, token: str) -> tuple[str, dict | None]:
        """("ok", aparato) | ("removed", None): esta TV lo quitó | ("unknown", None): esta TV no lo conoce (se reinstaló,
        TEC-30) | ("bad", None)."""
        parts = token.split(".")
        if len(parts) != 3 or parts[0] != PREFIX or not _ID.match(parts[1]) or not parts[2]:
            return "bad", None
        with self._lock:
            device = self._all().get(parts[1])
            if device is None:
                return ("removed" if parts[1] in self._removed() else "unknown"), None
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
            self._drop_invites(lambda v: v.get("by") == device_id)  # su invitación muere con él
            removed = [r for r in self._removed() if r != device_id] + [device_id]
            self.credentials.set(REMOVED, json.dumps(removed[-MAX_REMOVED:]))
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
