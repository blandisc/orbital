"""Trakt (trakt.tv): tus listas, lo que estás viendo, recomendaciones, tendencias y lo más popular.

Se conecta con el «código en el celular» de Trakt (device code): la consola enseña un código, tú lo
escribes en trakt.tv/activate y listo; nunca se teclea una contraseña con el mando. Las claves de
la aplicación (client id y secret) van en config.yaml (`para_ti`); la sesión de tu cuenta, cifrada en
secrets.json (credentials.py).

  POST /oauth/device/code   {client_id}                          -> {device_code, user_code, verification_url, interval, expires_in}
  POST /oauth/device/token  {code, client_id, client_secret}     -> 200 sesión · 400 aún no · 404/409/410/418 se acabó · 429 más despacio
  POST /oauth/token         {refresh_token, … grant_type}         -> sesión nueva (la de Trakt dura poco)
  GET  /recommendations/{movies|shows} · /sync/watchlist · /users/me/lists(/{id}/items)
  GET  /{movies|shows}/trending · /{movies|shows}/popular · /sync/history/episodes · /shows/{id}/progress/watched

Solo cuenta lo que trae id de IMDb: así se ve con Cinemeta y Stremio, como todo lo demás.
"""

from __future__ import annotations

import json
import logging
import threading
import time
from dataclasses import dataclass
from urllib.parse import urlencode

from ..net import NET_ERRORS, http_json

log = logging.getLogger(__name__)

def _positive(value) -> int | None:
    """Un entero mayor que cero (lo demás de la API: None)."""
    return value if isinstance(value, int) and value > 0 else None


API = "https://api.trakt.tv"
TOKENS_KEY = "trakt_tokens"
# Lo que se escribe en «Redirect URIs» al crear la aplicación. Orbital entra con un código (no usa
# redirección), pero renovar la sesión lo pide y tiene que coincidir: developer.trakt.tv ya solo acepta
# https://, así que va https://localhost; las aplicaciones viejas tienen el valor de antes.
REDIRECTS = ("https://localhost", "urn:ietf:wg:oauth:2.0:oob")
KINDS = {"movie": "movies", "series": "shows"}


class TraktError(Exception):
    pass


class TraktAuthError(TraktError):
    """Trakt ya no acepta la sesión: hay que volver a conectar la cuenta."""


@dataclass
class DeviceCode:
    device_code: str
    user_code: str
    verification_url: str
    interval: float
    expires_at: float

    def public(self) -> dict:
        return {"code": self.user_code, "url": self.verification_url.removeprefix("https://"),
                "expires_in": max(0, int(self.expires_at - time.time()))}


def entry(raw: dict | None, kind: str) -> dict | None:
    """Una película o serie de Trakt en la forma de Orbital; None si no trae IMDb (no se podría ver)."""
    if not isinstance(raw, dict):
        return None
    ids = raw.get("ids") if isinstance(raw.get("ids"), dict) else {}
    imdb = ids.get("imdb")
    title = raw.get("title")
    if not isinstance(imdb, str) or not imdb.startswith("tt") or not isinstance(title, str) or not title.strip():
        return None
    year = raw.get("year") if isinstance(raw.get("year"), int) else None
    runtime = _positive(raw.get("runtime"))
    episodes = _positive(raw.get("aired_episodes"))
    return {"kind": kind, "imdb": imdb, "title": title.strip(), "year": year, "runtime": runtime,
            "episodes": episodes, "overview": str(raw.get("overview") or "").strip(),
            "trakt_id": ids.get("trakt") if isinstance(ids.get("trakt"), int) else None}


def _typed(rows) -> list[dict]:
    """Filas mezcladas («type»: movie/show) → solo películas y series con IMDb, sin repetir."""
    found, seen = [], set()
    for row in rows if isinstance(rows, list) else []:
        if not isinstance(row, dict):
            continue
        kind_name = row.get("type")
        kind = {"movie": "movie", "show": "series"}.get(kind_name) if isinstance(kind_name, str) else None
        item = entry(row.get(kind_name), kind) if kind and isinstance(kind_name, str) else None
        if item and item["imdb"] not in seen:
            seen.add(item["imdb"])
            found.append(item)
    return found


class Trakt:
    def __init__(self, client_id: str, client_secret: str, credentials, timeout: float = 10) -> None:
        self.client_id = client_id
        self.client_secret = client_secret
        self.credentials = credentials
        self.timeout = timeout
        self._lock = threading.Lock()

    # --- cuenta -----------------------------------------------------------------------------
    @property
    def configured(self) -> bool:
        return bool(self.client_id and self.client_secret)

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

    def unlink(self) -> None:
        tokens = self._tokens()
        self.credentials.set(TOKENS_KEY, None)
        if tokens:  # que la sesión deje de servir también en Trakt (si no hay internet, da igual)
            try:
                http_json(f"{API}/oauth/revoke", method="POST", timeout=self.timeout,
                          body={"token": tokens["access_token"], "client_id": self.client_id, "client_secret": self.client_secret})
            except NET_ERRORS:
                pass

    def device_code(self) -> DeviceCode:
        status, data = self._call("POST", "/oauth/device/code", body={"client_id": self.client_id}, auth=False)
        if status != 200 or not isinstance(data, dict) or not data.get("device_code") or not data.get("user_code"):
            raise TraktError("Trakt no dio un código. Revisa la clave de la aplicación en Ajustes › Cuentas.")
        return DeviceCode(str(data["device_code"]), str(data["user_code"]),
                          str(data.get("verification_url") or "https://trakt.tv/activate"),
                          float(data.get("interval") or 5), time.time() + float(data.get("expires_in") or 600))

    def poll_device(self, code: DeviceCode) -> str:
        """Una consulta: "linked", "pending", "slow" (más despacio) o "expired"/"denied"/"invalid"."""
        status, data = self._call("POST", "/oauth/device/token", auth=False,
                                  body={"code": code.device_code, "client_id": self.client_id, "client_secret": self.client_secret})
        if status == 200 and isinstance(data, dict):
            self._save(data)
            return "linked"
        return {400: "pending", 429: "slow", 404: "invalid", 409: "invalid", 410: "expired", 418: "denied"}.get(status, "pending")

    def _refresh(self, tokens: dict) -> dict:
        for redirect in REDIRECTS:  # el de la aplicación nueva y, si no, el de las viejas
            status, data = self._call("POST", "/oauth/token", auth=False, body={
                "refresh_token": tokens.get("refresh_token"), "client_id": self.client_id, "client_secret": self.client_secret,
                "redirect_uri": redirect, "grant_type": "refresh_token"})
            if status == 200 and isinstance(data, dict):
                break
        if status != 200 or not isinstance(data, dict):
            self.credentials.set(TOKENS_KEY, None)
            raise TraktAuthError("Tu sesión de Trakt caducó: vuelve a conectarla en Ajustes › Cuentas.")
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

    # --- peticiones --------------------------------------------------------------------------
    def _call(self, method: str, path: str, *, body: dict | None = None, auth: bool = True, params: dict | None = None):
        headers = {"trakt-api-version": "2", "trakt-api-key": self.client_id}
        if auth:
            headers["Authorization"] = f"Bearer {self._access()}"
        url = f"{API}{path}" + (f"?{urlencode(params)}" if params else "")
        try:
            return http_json(url, method=method, headers=headers, body=body, timeout=self.timeout)
        except NET_ERRORS as exc:
            raise TraktError(f"No pude conectar con Trakt: {exc}") from exc

    def _get(self, path: str, *, auth: bool = True, **params):
        status, data = self._call("GET", path, auth=auth, params=params or None)
        if status == 401 and auth:
            self.credentials.set(TOKENS_KEY, None)
            raise TraktAuthError("Trakt cerró tu sesión: vuelve a conectarla en Ajustes › Cuentas.")
        if status != 200:
            raise TraktError(f"Trakt respondió HTTP {status}")
        return data

    # --- listas ------------------------------------------------------------------------------
    def username(self) -> str:
        data = self._get("/users/settings")
        user = data.get("user") if isinstance(data, dict) else None
        name = user.get("name") or user.get("username") if isinstance(user, dict) else None
        return str(name or "")

    def recommendations(self, kind: str, limit: int = 30) -> list[dict]:
        rows = self._get(f"/recommendations/{KINDS[kind]}", limit=limit, ignore_collected="true",
                         ignore_watchlisted="true", extended="full")
        return [e for e in (entry(r, kind) for r in rows or []) if e] if isinstance(rows, list) else []

    def watchlist(self) -> list[dict]:
        rows = self._get("/sync/watchlist", extended="full", sort_by="added", sort_how="desc")
        if isinstance(rows, list):
            rows = sorted((r for r in rows if isinstance(r, dict)), key=lambda r: str(r.get("listed_at") or ""), reverse=True)
        return _typed(rows)

    def lists(self) -> list[dict]:
        rows = self._get("/users/me/lists")
        found = []
        for row in rows if isinstance(rows, list) else []:
            if not isinstance(row, dict):
                continue
            ids = row.get("ids") if isinstance(row.get("ids"), dict) else {}
            name, trakt_id = row.get("name"), ids.get("trakt")
            if isinstance(name, str) and name.strip() and trakt_id:
                found.append({"id": str(trakt_id), "name": name.strip()})
        return found

    def list_items(self, list_id: str) -> list[dict]:
        if not str(list_id).isdigit():
            raise TraktError("Lista inválida")
        return _typed(self._get(f"/users/me/lists/{list_id}/items", extended="full"))

    def trending(self, kind: str, limit: int = 30) -> list[dict]:
        rows = self._get(f"/{KINDS[kind]}/trending", auth=False, limit=limit, extended="full")
        key = "movie" if kind == "movie" else "show"
        return [e for e in (entry(r.get(key), kind) for r in rows if isinstance(r, dict)) if e] if isinstance(rows, list) else []

    def popular(self, kind: str, limit: int = 30) -> list[dict]:
        rows = self._get(f"/{KINDS[kind]}/popular", auth=False, limit=limit, extended="full")
        return [e for e in (entry(r, kind) for r in rows) if e] if isinstance(rows, list) else []

    def watching(self, limit: int = 12) -> list[dict]:
        """Las series que estás viendo (lo más reciente primero) con el episodio que sigue; las terminadas no."""
        rows = self._get("/sync/history/episodes", limit=100)
        shows, seen = [], set()
        for row in rows if isinstance(rows, list) else []:
            show = entry(row.get("show") if isinstance(row, dict) else None, "series")
            if show and show["imdb"] not in seen and show["trakt_id"]:
                seen.add(show["imdb"])
                shows.append(show)
            if len(shows) >= limit:
                break
        found = []
        for show in shows:
            try:
                progress = self._get(f"/shows/{show['trakt_id']}/progress/watched", hidden="false", specials="false")
            except TraktAuthError:
                raise
            except TraktError:  # una serie que falla no tumba las demás
                continue
            nxt = progress.get("next_episode") if isinstance(progress, dict) else None
            if isinstance(nxt, dict) and isinstance(nxt.get("season"), int) and isinstance(nxt.get("number"), int):
                found.append({**show, "next": {"season": nxt["season"], "episode": nxt["number"]}})
        return found
