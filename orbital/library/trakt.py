"""Trakt (trakt.tv): tus listas, lo que estás viendo, recomendaciones, tendencias y lo más popular.

Se conecta con el «código en el celular» de Trakt (device code): la consola enseña un código, tú lo
escribes en trakt.tv/activate y listo; nunca se teclea una contraseña con el mando. Las claves de
la aplicación (client id y secret) van en config.yaml (`para_ti`); la sesión de tu cuenta, cifrada en
secrets.json (credentials.py).

  POST /oauth/device/code   {client_id}                          -> {device_code, user_code, verification_url, interval, expires_in}
  POST /oauth/device/token  {code, client_id[, client_secret]}     -> 200 sesión · 400 aún no · 404/409/410/418 se acabó · 429 más despacio
  POST /oauth/token         {refresh_token, … grant_type}         -> sesión nueva (la de Trakt dura poco)
  GET  /recommendations/{movies|shows} · /sync/watchlist · /users/me/lists(/{id}/items)
  POST /scrobble/{start|pause|stop}   {movie|show+episode, progress}  -> 201 · 409 ya registrado · 401 renovar sesión
  GET  /{movies|shows}/trending · /{movies|shows}/popular · /sync/history/episodes · /shows/{id}/progress/watched

Solo cuenta lo que trae id de IMDb: así se ve con Cinemeta y Stremio, como todo lo demás.
"""

from __future__ import annotations

import json
import logging
import re
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
REDIRECTS = ("https://localhost/", "https://localhost", "urn:ietf:wg:oauth:2.0:oob")  # Trakt le agrega la «/»
KINDS = {"movie": "movies", "series": "shows"}


SCROBBLE_ACTIONS = ("start", "pause", "stop")


def scrobble_target(kind: str, meta_id: str, video_id: str | None) -> dict | None:
    """Lo que Trakt necesita para saber qué ves: la película (IMDb) o la serie con su temporada y episodio
    (el video_id de Stremio es `tt123:2:5`). None si no hay forma de identificarlo (no se manda nada)."""
    if not isinstance(meta_id, str) or not re.fullmatch(r"tt\d+", meta_id):
        return None
    if kind == "movie":
        return {"movie": {"ids": {"imdb": meta_id}}}
    if kind == "series":
        match = re.fullmatch(r"(tt\d+):(\d+):(\d+)", str(video_id or ""))
        if match and match.group(1) == meta_id:
            return {"show": {"ids": {"imdb": meta_id}},
                    "episode": {"season": int(match.group(2)), "number": int(match.group(3))}}
    return None


PLAYBACK_TTL = 60  # s: el avance de Trakt (/sync/playback) se vuelve a pedir a lo más cada minuto (como el iPhone)
RESUME_BACK = 10  # s antes del punto de Trakt: su porcentaje se redondea y la duración de la copia puede ser otra
WATCHED_PERCENT = 80  # Trakt marca visto desde 80 %: arriba de eso no hay punto que retomar


def playback_key(kind: str, meta_id: str, video_id: str | None) -> str | None:
    """La llave con la que se cruza el avance de Trakt: «tt123» (película) o «tt123:2:5» (episodio)."""
    target = scrobble_target(kind, meta_id, video_id)
    if target is None:
        return None
    if "episode" in target:
        return f"{meta_id}:{target['episode']['season']}:{target['episode']['number']}"
    return meta_id


def playback_entry(row) -> tuple[str, dict] | None:
    """Una fila de GET /sync/playback → («tt123» o «tt123:2:5», {percent, paused_at, runtime}). None si no se entiende."""
    if not isinstance(row, dict) or not isinstance(row.get("progress"), (int, float)):
        return None
    when = _when(row.get("paused_at"))
    if when is None:
        return None
    if row.get("type") == "movie":
        movie = row.get("movie") if isinstance(row.get("movie"), dict) else {}
        imdb, runtime = (movie.get("ids") or {}).get("imdb"), movie.get("runtime")
        key = imdb if isinstance(imdb, str) and re.fullmatch(r"tt\d+", imdb) else None
    elif row.get("type") == "episode":
        show = row.get("show") if isinstance(row.get("show"), dict) else {}
        ep = row.get("episode") if isinstance(row.get("episode"), dict) else {}
        imdb, runtime = (show.get("ids") or {}).get("imdb"), ep.get("runtime")
        ok = isinstance(imdb, str) and re.fullmatch(r"tt\d+", imdb) and isinstance(ep.get("season"), int) \
            and isinstance(ep.get("number"), int)
        key = f"{imdb}:{ep['season']}:{ep['number']}" if ok else None
    else:
        key = None
    if key is None:
        return None
    return key, {"percent": float(row["progress"]), "paused_at": when,
                 "runtime": float(runtime) * 60 if isinstance(runtime, (int, float)) and runtime > 0 else None}


def latest_resume(stremio_seconds: float, stremio_when: float | None, duration: float | None,
                  trakt: dict | None) -> float:
    """Dónde seguir: lo más reciente entre Stremio (segundos exactos) y Trakt (porcentaje, a segundos con la duración de
    Stremio para ese video o, si no la hay, la que dice Trakt), como ResumePoint.latest del iPhone. 0 = desde el inicio."""
    if not trakt or (stremio_when is not None and stremio_when >= trakt["paused_at"]):
        return stremio_seconds  # lo de Stremio es más nuevo (también si ahí ya lo terminaste: 0)
    if not 0 < trakt["percent"] < WATCHED_PERCENT:
        return stremio_seconds
    length = duration if duration and duration > 0 else trakt.get("runtime")
    if not length:
        return stremio_seconds  # sin duración no se sabe a qué segundo va el porcentaje
    return max(0.0, trakt["percent"] / 100 * length - RESUME_BACK)


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
    genres = [str(g).replace("-", " ").title() for g in raw.get("genres") or [] if isinstance(g, str)][:4]  # «Science Fiction»
    rating = raw.get("rating")
    return {"kind": kind, "imdb": imdb, "title": title.strip(), "year": year, "runtime": runtime, "genres": genres,
            "episodes": episodes, "overview": str(raw.get("overview") or "").strip(),
            "trakt_id": ids.get("trakt") if isinstance(ids.get("trakt"), int) else None,
            # La calificación de Trakt (0–10): para ordenar una lista «Mejor calificadas en Trakt», como en el iPhone.
            "rating": round(float(rating), 1) if isinstance(rating, (int, float)) and rating > 0 else None}


def _when(value) -> float | None:
    """«2026-10-16T01:00:00.000Z» → segundos desde 1970 (None si no se entiende)."""
    from datetime import datetime

    if not isinstance(value, str) or not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None


def history_play(row) -> dict | None:
    """Una fila del historial de Trakt → lo que cuenta «Tu año». None si no trae fecha o IMDb."""
    if not isinstance(row, dict):
        return None
    at = _when(row.get("watched_at"))
    movie = row.get("type") == "movie"
    item = row.get("movie") if movie else row.get("show")
    ids = item.get("ids") if isinstance(item, dict) and isinstance(item.get("ids"), dict) else {}
    imdb = ids.get("imdb")
    if at is None or not isinstance(imdb, str) or not imdb.startswith("tt") or not isinstance(item.get("title"), str):
        return None
    ep = {} if movie or not isinstance(row.get("episode"), dict) else row["episode"]
    minutes = _positive(item.get("runtime")) if movie else (_positive(ep.get("runtime")) or _positive(item.get("runtime")))
    assert isinstance(item, dict)
    return {"at": at, "kind": "movie" if movie else "series", "imdb": imdb, "title": item["title"].strip(), "minutes": minutes or 0,
            "genres": [g for g in item.get("genres") or [] if isinstance(g, str)],
            "season": ep.get("season") if isinstance(ep.get("season"), int) else None,
            "episode": ep.get("number") if isinstance(ep.get("number"), int) else None,
            "episode_title": str(ep.get("title") or "").strip() or None}


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
        self._playback: tuple[float, dict[str, dict]] | None = None  # (cuándo se pidió, {llave: avance})

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

    def unlink(self) -> None:
        tokens = self._tokens()
        self.credentials.set(TOKENS_KEY, None)
        if tokens:  # que la sesión deje de servir también en Trakt (si no hay internet, da igual)
            try:
                http_json(f"{API}/oauth/revoke", method="POST", timeout=self.timeout,
                          body=self._client(token=tokens["access_token"]))
            except NET_ERRORS:
                pass

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
        status, data = self._call("POST", "/oauth/device/token", auth=False,
                                  body=self._client(code=code.device_code))
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
            raise TraktError(f"No pude renovar tu sesión de Trakt (HTTP {status}): lo intento de nuevo más tarde.")
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
            raise TraktError(f"Trakt respondió HTTP {status}")

    # --- guardar (como «Guardar en…» del iPhone) -------------------------------------------------
    def _send(self, method: str, path: str, body: dict | None = None):
        """Un cambio en tu cuenta: un 401 renueva la sesión una vez y reintenta."""
        status, data = self._call(method, path, body=body)
        if status == 401:
            self._renew()
            status, data = self._call(method, path, body=body)
        if status == 401:
            raise TraktAuthError("Trakt no acepta tu sesión: vuelve a conectarla en Ajustes › Cuentas.")
        if status not in (200, 201, 204):
            raise TraktError(f"Trakt respondió HTTP {status}")
        return data

    @staticmethod
    def _one(kind: str, imdb: str) -> dict:
        if kind not in KINDS or not str(imdb).startswith("tt"):
            raise TraktError("Título inválido")
        return {KINDS[kind]: [{"ids": {"imdb": imdb}}]}

    def set_watchlist(self, kind: str, imdb: str, add: bool) -> None:
        self._send("POST", "/sync/watchlist" + ("" if add else "/remove"), self._one(kind, imdb))

    def set_list_item(self, list_id: str, kind: str, imdb: str, add: bool) -> None:
        if not str(list_id).isdigit():
            raise TraktError("Lista inválida")
        self._send("POST", f"/users/me/lists/{list_id}/items" + ("" if add else "/remove"), self._one(kind, imdb))

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

    def popular(self, kind: str, limit: int = 30, years: int | None = None) -> list[dict]:
        """Lo más popular; con `years`, de ese año (Por año)."""
        params = {"limit": limit, "extended": "full", **({"years": int(years)} if years else {})}
        rows = self._get(f"/{KINDS[kind]}/popular", auth=False, **params)
        return [e for e in (entry(r, kind) for r in rows) if e] if isinstance(rows, list) else []

    def search(self, kind: str, query: str, limit: int = 15) -> list[dict]:
        """Buscar sin sesión (respaldo de Buscar cuando Cinemeta falla, como el iPhone). Solo lo que trae IMDb."""
        key = "movie" if kind == "movie" else "show"
        rows = self._get(f"/search/{key}", auth=False, query=query, limit=limit, extended="full")
        return [e for e in (entry(r.get(key), kind) for r in rows if isinstance(r, dict)) if e] if isinstance(rows, list) else []

    def rating(self, kind: str, imdb: str) -> float | None:
        """La calificación de Trakt de un título (0–10; para la ficha, como el iPhone). None si no la tiene."""
        if not isinstance(imdb, str) or not imdb.startswith("tt") or not imdb[2:].isdigit():
            return None
        raw = self._get(f"/{KINDS[kind]}/{imdb}", auth=False, extended="full")
        found = entry(raw, kind) if isinstance(raw, dict) else None
        return found.get("rating") if found else None

    def watched_ids(self) -> list[str]:
        """Los IMDb de lo que ya viste (películas y series), para «Ocultar lo que ya vi» en una lista."""
        found: list[str] = []
        for kind, key in (("movies", "movie"), ("shows", "show")):
            rows = self._get(f"/sync/watched/{kind}")
            for row in rows if isinstance(rows, list) else []:
                raw = row.get(key) if isinstance(row, dict) else None
                imdb = (raw.get("ids") or {}).get("imdb") if isinstance(raw, dict) and isinstance(raw.get("ids"), dict) else None
                if isinstance(imdb, str) and imdb.startswith("tt"):
                    found.append(imdb)
        return found

    def related(self, kind: str, imdb: str, limit: int = 15) -> list[dict]:
        """Lo que Trakt relaciona con un título («Porque viste X»), como el iPhone."""
        if not isinstance(imdb, str) or not imdb.startswith("tt") or not imdb[2:].isdigit():
            return []
        rows = self._get(f"/{KINDS[kind]}/{imdb}/related", auth=False, limit=limit, extended="full")
        return [e for e in (entry(r, kind) for r in rows) if e] if isinstance(rows, list) else []

    def recent_watched(self, limit: int = 12) -> list[dict]:
        """Los últimos títulos distintos que viste (una película, o la serie de un episodio), el más reciente primero,
        para «Porque viste X»: los 12 que el iPhone deja elegir (ForYou.recentSeeds: historial de 40)."""
        rows = self._get("/sync/history", limit=40, extended="full")
        found: list[dict] = []
        for row in rows if isinstance(rows, list) else []:
            if not isinstance(row, dict):
                continue
            e = entry(row.get("movie"), "movie") if row.get("type") == "movie" else entry(row.get("show"), "series")
            if e and all(f["imdb"] != e["imdb"] for f in found):
                found.append({**e, "watched_at": _when(row.get("watched_at"))})
                if len(found) >= limit:
                    break
        return found

    HISTORY_PAGE = 250

    def plays(self, since: str, until: str, max_pages: int = 20) -> list[dict]:
        """«Tu año»: cada cosa que viste entre dos fechas (ISO 8601), como el iPhone (Trakt.plays): {at (segundos), kind,
        imdb, title, minutes, genres, season, episode, episode_title}. Son varias páginas de 250."""
        found: list[dict] = []
        for page in range(1, max(1, max_pages) + 1):
            rows = self._get("/sync/history", start_at=since, end_at=until, extended="full", limit=self.HISTORY_PAGE, page=page)
            rows = rows if isinstance(rows, list) else []
            for row in rows:
                play = history_play(row)
                if play:
                    found.append(play)
            if len(rows) < self.HISTORY_PAGE:
                break
        return found

    def last_watched(self) -> dict | None:
        """Lo último que viste (una película, o la serie de tu último episodio)."""
        recent = self.recent_watched(1)
        return recent[0] if recent else None

    def calendar(self, start: str, days: int = 15) -> list[dict]:
        """Los episodios que salen de las series que sigues, desde `start` (AAAA-MM-DD, en hora universal) y `days` días:
        {serie (como entry), season, episode, title, aired (segundos desde 1970), network, runtime}. Sin IMDb, no entra."""
        rows = self._get(f"/calendars/my/shows/{start}/{max(1, min(int(days), 31))}", extended="full")
        found = []
        for row in rows if isinstance(rows, list) else []:
            if not isinstance(row, dict):
                continue
            show = entry(row.get("show"), "series")
            ep = row.get("episode") if isinstance(row.get("episode"), dict) else {}
            aired = _when(row.get("first_aired"))
            season, number = ep.get("season"), ep.get("number")
            if not show or aired is None or not isinstance(season, int) or not isinstance(number, int):
                continue
            raw_show = row["show"]
            network = raw_show.get("network") if isinstance(raw_show.get("network"), str) else ""
            found.append({**show, "season": season, "episode": number, "episode_title": str(ep.get("title") or "").strip(),
                          "aired": aired, "network": network.strip(),
                          "runtime": _positive(ep.get("runtime")) or show.get("runtime")})
        return sorted(found, key=lambda e: e["aired"])

    def playback(self, now: float | None = None) -> dict[str, dict]:
        """Dónde ibas en cada película y episodio según Trakt (GET /sync/playback: lo que pausaste o cerraste entre 1 y
        79 %, desde cualquier app: el iPhone, la TV…), con un minuto de caché. {«tt123» o «tt123:2:5»: avance}."""
        now = time.time() if now is None else now
        cached = self._playback
        if cached is not None and now - cached[0] < PLAYBACK_TTL:
            return cached[1]
        rows = self._get("/sync/playback", extended="full", limit=100)
        found: dict[str, dict] = {}
        for row in rows if isinstance(rows, list) else []:
            parsed = playback_entry(row)
            if parsed and (parsed[0] not in found or parsed[1]["paused_at"] > found[parsed[0]]["paused_at"]):
                found[parsed[0]] = parsed[1]
        self._playback = (now, found)
        return found

    def forget_playback(self) -> None:
        """Pausaste o cerraste: lo que se pidió a Trakt ya no es lo último (la siguiente vez se pide otra vez)."""
        self._playback = None

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
