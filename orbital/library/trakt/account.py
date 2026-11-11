"""Tu cuenta de Trakt: conectar con un código, guardar y renovar la clave, y pedir páginas."""

from __future__ import annotations

import json
import time

from .base import KINDS, REDIRECTS, SCROBBLE_ACTIONS, TOKENS_KEY, DeviceCode, TraktAuthError, TraktError, _State


class _Account(_State):
    """Conectar, la clave y las llamadas."""

    # --- cuenta -----------------------------------------------------------------------------
    @property
    def configured(self) -> bool:
        # Las aplicaciones nuevas de developer.trakt.tv (PKCE) no dan Client Secret: basta el Client ID.
        return bool(self.client_id)

    def _client(self, **body) -> dict:
        """client_id y, si la aplicación tiene uno (las viejas), client_secret."""
        return {**body, "client_id": self.client_id, **({"client_secret": self.client_secret} if self.client_secret else {})}

    @property
    def linked(self) -> bool:
        return self._tokens() is not None

    def _tokens(self) -> dict | None:
        raw = self.credentials.get(TOKENS_KEY) if self.credentials else None
        try:
            data = json.loads(raw) if raw else None
        except ValueError:
            return None
        return data if isinstance(data, dict) and data.get("access_token") else None

    def _save(self, data: dict) -> None:
        tokens = {"access_token": data.get("access_token"), "refresh_token": data.get("refresh_token"),
                  "expires_at": float(data.get("created_at") or time.time()) + float(data.get("expires_in") or 0)}
        if not isinstance(tokens["access_token"], str) or not tokens["access_token"]:
            raise TraktError("Trakt no devolvió una sesión")
        self.credentials.set(TOKENS_KEY, json.dumps(tokens))

    def device_code(self) -> DeviceCode:
        status, data = self._call("POST", "/oauth/device/code", body={"client_id": self.client_id}, auth=False)
        if status != 200 or not isinstance(data, dict) or not data.get("device_code") or not data.get("user_code"):
            raise TraktError("Trakt no dio un código. Revisa la clave de la aplicación en Ajustes › Cuentas.")
        try:
            interval, expires = float(data.get("interval") or 5), float(data.get("expires_in") or 600)
        except (TypeError, ValueError):
            raise TraktError("Trakt respondió algo que no entiendo. Inténtalo de nuevo.") from None
        return DeviceCode(str(data["device_code"]), str(data["user_code"]),
                          str(data.get("verification_url") or "https://trakt.tv/activate"),
                          min(max(interval, 1.0), 60.0), time.time() + min(max(expires, 1.0), 3600.0))

    def poll_device(self, code: DeviceCode) -> str:
        """Una consulta: "linked", "pending", "slow" (más despacio) o "expired"/"denied"/"invalid"."""
        status, data = self._call("POST", "/oauth/device/token", auth=False,  # su 429 es «consulta más despacio»
                                  body=self._client(code=code.device_code), retries=0)
        if status == 200 and isinstance(data, dict):
            self._save(data)
            return "linked"
        return {400: "pending", 429: "slow", 404: "invalid", 409: "invalid", 410: "expired", 418: "denied"}.get(status, "pending")

    def _refresh(self, tokens: dict) -> dict:
        for redirect in REDIRECTS:  # el de la aplicación nueva y, si no, el de las viejas
            status, data = self._call("POST", "/oauth/token", auth=False, body=self._client(
                refresh_token=tokens.get("refresh_token"), redirect_uri=redirect, grant_type="refresh_token"))
            if status == 200 and isinstance(data, dict):
                break
        if status != 200 or not isinstance(data, dict):
            if status in (400, 401, 403):  # Trakt rechazó la renovación (revocada o vencida): ahora sí, a reconectar
                self.credentials.set(TOKENS_KEY, None)
                raise TraktAuthError("Tu sesión de Trakt caducó: vuelve a conectarla en Ajustes › Cuentas.")
            # Trakt caído o lento (5xx, 429): la sesión se queda; la próxima vez se vuelve a intentar renovar.
            raise TraktError(f"No pude renovar tu sesión de Trakt (HTTP {status}): lo intento de nuevo más tarde.",
                             status if isinstance(status, int) else None)
        self._save(data)
        return self._tokens() or {}

    def _access(self) -> str:
        with self._lock:  # dos listas a la vez no renuevan la sesión dos veces
            tokens = self._tokens()
            if not tokens:
                raise TraktAuthError("Conecta tu cuenta de Trakt en Ajustes › Cuentas.")
            if tokens.get("refresh_token") and time.time() > float(tokens.get("expires_at") or 0) - 3600:
                tokens = self._refresh(tokens)
            return str(tokens.get("access_token") or "")

    def access_token(self) -> str:
        """La sesión vigente (renovada si estaba por caducar): la toma prestada la app del iPhone."""
        return self._access()

    def session_expiry(self) -> float:
        return float((self._tokens() or {}).get("expires_at") or 0)

    def _get(self, path: str, *, auth: bool = True, **params):
        """Una lectura. Un 401 renueva la sesión una vez y reintenta (antes la borraba de inmediato y había que volver a
        conectar Trakt, aunque la renovación hubiera funcionado)."""
        status, data = self._call("GET", path, auth=auth, params=params or None)
        if status == 401 and auth:
            self._renew()  # si Trakt rechaza la renovación, _refresh borra la sesión y avisa
            status, data = self._call("GET", path, auth=auth, params=params or None)
        if status == 401 and auth:  # renovada y aun así rechazada: la sesión de verdad ya no sirve
            self.credentials.set(TOKENS_KEY, None)
            raise TraktAuthError("Trakt cerró tu sesión: vuelve a conectarla en Ajustes › Cuentas.")
        if status != 200:
            raise TraktError(f"Trakt respondió HTTP {status}")
        return data

    def _all_pages(self, path: str, **params) -> list:
        """Todas las páginas de una lectura que Trakt da de cien en cien (tu watchlist, tus listas, favoritos,
        calificaciones). Sin `page`, Trakt solo da las primeras 100: Mi lista de Fernando tiene 318 y se veían 100
        (4 nov 2026). Hasta 5 000."""
        rows: list = []
        for page in range(1, 51):
            got = self._get(path, **params, page=page, limit=100)
            got = got if isinstance(got, list) else []
            rows += got
            if len(got) < 100:
                break
        return rows

    def _renew(self) -> None:
        """Renueva la sesión ya (Trakt dijo 401 aunque aún no caducaba en nuestra cuenta)."""
        with self._lock:
            tokens = self._tokens()
            if not tokens or not tokens.get("refresh_token"):
                raise TraktAuthError("Conecta tu cuenta de Trakt en Ajustes › Cuentas.")
            self._refresh(tokens)

    def scrobble(self, action: str, target: dict, progress: float) -> None:
        """Le dice a Trakt qué estás viendo («Viendo ahora») y cuánto llevas; al parar con ≥ 80 % lo marca visto.
        `progress` va de 0 a 100. Un 409 es «ya registrado» (no es un error); un 401 renueva la sesión una vez y
        reintenta; lo demás se lanza como TraktError."""
        if action not in SCROBBLE_ACTIONS or not isinstance(target, dict) or not target:
            raise TraktError("Scrobble inválido")
        body = {**target, "progress": round(min(max(float(progress), 0.0), 100.0), 2)}
        status, _ = self._call("POST", f"/scrobble/{action}", body=body)
        if status == 401:
            self._renew()
            status, _ = self._call("POST", f"/scrobble/{action}", body=body)
        if status == 401:
            raise TraktAuthError("Trakt no acepta tu sesión: vuelve a conectarla en Ajustes › Cuentas.")
        if status not in (200, 201, 409):
            raise TraktError(f"Trakt respondió HTTP {status}", status)  # con su código: la cola decide si reintenta

    # --- guardar (como «Guardar en…» del iPhone) -------------------------------------------------
    def _send(self, method: str, path: str, body: dict | None = None, errors: dict[int, TraktError] | None = None,
              idempotent: bool = False):
        """Un cambio en tu cuenta: un 401 renueva la sesión una vez y reintenta. `errors`: el error de un código conocido
        (el 420 de los favoritos) en vez de «HTTP 420». `idempotent`: ver `_call`."""
        status, data = self._call(method, path, body=body, idempotent=idempotent)
        if status == 401:
            self._renew()
            status, data = self._call(method, path, body=body, idempotent=idempotent)
        if status == 401:
            raise TraktAuthError("Trakt no acepta tu sesión: vuelve a conectarla en Ajustes › Cuentas.")
        if status not in (200, 201, 204):
            raise (errors or {}).get(status) or TraktError(f"Trakt respondió HTTP {status}", status)
        return data

    @staticmethod
    def _one(kind: str, imdb: str) -> dict:
        if kind not in KINDS or not str(imdb).startswith("tt"):
            raise TraktError("Título inválido")
        return {KINDS[kind]: [{"ids": {"imdb": imdb}}]}
