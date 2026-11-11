"""La API oficial de OpenSubtitles (api.opensubtitles.com, v1), directa, como el iPhone (OrbitalCore · OpenSubtitles.swift).

Su complemento de Stremio da dos o tres subtítulos por idioma; la API da decenas. Dos llaves distintas:
- la clave de la app (`Api-Key`, registrada una vez en opensubtitles.com/consumers): la variable de entorno
  `ORBITAL_OPENSUBTITLES_KEY` o `opensubtitles_api_key` en secrets.json (cifrado con DPAPI). Nunca en git ni en config.yaml.
  Sin ella no se usa la API y queda el complemento.
- tu cuenta (usuario y contraseña → un token), para bajar (cuota diaria, ~20 en las gratis): se guarda el token, nunca la
  contraseña, en secrets.json (`opensubtitles_account`).
Buscar no gasta cuota y se recuerda 10 min; bajar sí, y solo se baja el subtítulo que eliges o que se pone solo.
"""

from __future__ import annotations

import json
import logging
import os
import threading
import time
from urllib.parse import urlencode

from .. import __version__
from ..net import NET_FAILURES, http_json

log = logging.getLogger(__name__)

HOST = "https://api.opensubtitles.com/api/v1"
SIGN_UP = "https://www.opensubtitles.com/es/users/sign_up"
SCHEME = "opensubtitles://file/"  # así van en la lista: se cambian por la dirección de verdad al ponerlos
KEY_ENV = "ORBITAL_OPENSUBTITLES_KEY"
KEY_SECRET = "opensubtitles_api_key"
ACCOUNT_SECRET = "opensubtitles_account"
CACHE_SECONDS = 600


class OpenSubtitlesError(ValueError):
    """Con el motivo en español, para enseñarlo tal cual (ValueError: quien baja subtítulos ya lo atrapa)."""

    def __init__(self, message: str, code: str) -> None:
        super().__init__(message)
        self.code = code


NO_KEY = ("Esta versión de Orbital no trae la clave de OpenSubtitles", "no_key")
MISSING = ("Escribe tu usuario y tu contraseña de OpenSubtitles", "missing")
WRONG = ("El usuario o la contraseña no coinciden", "wrong_password")
NOT_CONNECTED = ("Conecta tu cuenta de OpenSubtitles para bajar este", "not_connected")
QUOTA = ("Ya usaste tus subtítulos de hoy en OpenSubtitles. Mañana hay más.", "quota")
OFFLINE = ("OpenSubtitles no contestó. Intenta de nuevo en un momento.", "offline")


def query(video_id: str, moviehash: str | None, languages: list[str]) -> list[tuple[str, str]] | None:
    """La búsqueda como la pide OpenSubtitles: parámetros en minúsculas y en orden alfabético (si no, redirige), el IMDb sin
    «tt» ni ceros al frente; de un episodio, el de la serie con temporada y capítulo. None si no es de IMDb."""
    parts = video_id.split(":")
    if not parts[0].startswith("tt") or not parts[0][2:].isdigit():
        return None
    items = {"order_by": "download_count"}
    number = str(int(parts[0][2:]))
    if len(parts) >= 3 and parts[1].isdigit() and parts[2].isdigit():
        items |= {"parent_imdb_id": number, "season_number": str(int(parts[1])), "episode_number": str(int(parts[2]))}
    else:
        items["imdb_id"] = number
    langs = sorted({lang.split("-")[0].lower() for lang in languages if lang})
    if langs:
        items["languages"] = ",".join(langs)
    if moviehash:
        items["moviehash"] = moviehash
    return sorted(items.items())


def parse(data: object) -> list[dict]:
    """La respuesta de /subtitles → opciones como las de los complementos (subtitles.parse_options), los de tu copia
    exacta primero y luego los más bajados."""
    out = []
    for item in (data.get("data") if isinstance(data, dict) else None) or []:
        attrs = item.get("attributes") if isinstance(item, dict) else None
        if not isinstance(attrs, dict):
            continue
        files = attrs.get("files") or []
        file_id = files[0].get("file_id") if files and isinstance(files[0], dict) else None
        lang = attrs.get("language")
        if not isinstance(file_id, int) or not isinstance(lang, str):
            continue
        downloads = attrs.get("download_count")
        release = attrs.get("release")
        out.append({"url": f"{SCHEME}{file_id}", "lang": lang, "release": release if isinstance(release, str) else None,
                    "downloads": downloads if isinstance(downloads, int) else None, "source": "OpenSubtitles",
                    "hearing_impaired": bool(attrs.get("hearing_impaired")), "forced": bool(attrs.get("foreign_parts_only")),
                    "exact": bool(attrs.get("moviehash_match")), "file_id": str(file_id)})
    order = {id(o): i for i, o in enumerate(out)}
    return sorted(out, key=lambda o: (not o["exact"], -(o["downloads"] or -1), order[id(o)]))


def merge(official: list[dict], others: list[dict]) -> list[dict]:
    """Los de la API primero; de los complementos, lo que no repita (la misma dirección o el mismo archivo de OpenSubtitles,
    que su complemento numera igual)."""
    files = {o["file_id"] for o in official if o.get("file_id")}
    seen, out = set(), []
    for option in official + others:
        if option.get("source") == "OpenSubtitles" and option.get("file_id") in files and not option["url"].startswith(SCHEME):
            continue
        if option["url"] not in seen:
            seen.add(option["url"])
            out.append(option)
    return out


class OpenSubtitles:
    def __init__(self, credentials, languages=lambda: ["es", "en"], http=http_json, clock=time.time) -> None:
        self.credentials = credentials
        self.languages = languages
        self.http = http
        self.clock = clock
        self._lock = threading.Lock()
        self._searches: dict[str, tuple[float, list[dict]]] = {}
        self._links: dict[str, str] = {}

    # --- la clave de la app y tu cuenta ---
    def api_key(self) -> str:
        return (os.environ.get(KEY_ENV) or self.credentials.get(KEY_SECRET) or "").strip()

    @property
    def available(self) -> bool:
        return bool(self.api_key())

    def account(self) -> dict | None:
        raw = self.credentials.get(ACCOUNT_SECRET)
        try:
            data = json.loads(raw) if isinstance(raw, str) else None
        except ValueError:
            return None
        return data if isinstance(data, dict) and data.get("token") else None

    def status(self) -> dict:
        """Lo que ve la interfaz (sin el token)."""
        account = self.account() or {}
        return {"available": self.available, "connected": bool(account), "username": account.get("username"),
                "remaining": account.get("remaining"), "allowed": account.get("allowed"), "sign_up": SIGN_UP}

    def _save(self, account: dict | None) -> None:
        self.credentials.set(ACCOUNT_SECRET, json.dumps(account) if account else None)

    def _headers(self, token: str | None = None) -> dict:
        headers = {"Api-Key": self.api_key(), "User-Agent": f"Orbital v{__version__}"}
        if token:
            headers["Authorization"] = f"Bearer {token}"
        return headers

    def _root(self, account: dict | None) -> str:
        base = (account or {}).get("base")
        return f"https://{base}/api/v1" if isinstance(base, str) and base else HOST

    def login(self, username: str, password: str) -> dict:
        """Entra con tu usuario y contraseña; guarda el token (la contraseña no). OpenSubtitlesError si no se pudo."""
        if not self.available:
            raise OpenSubtitlesError(*NO_KEY)
        user = (username or "").strip()
        if not user or not password:
            raise OpenSubtitlesError(*MISSING)
        try:
            code, body = self.http(f"{HOST}/login", method="POST", headers=self._headers(),
                                   body={"username": user, "password": password}, timeout=15)
        except NET_FAILURES as exc:
            raise OpenSubtitlesError(*OFFLINE) from exc
        if code == 401:
            raise OpenSubtitlesError(*WRONG)
        if code >= 400 or not isinstance(body, dict) or not body.get("token"):
            raise OpenSubtitlesError(f"OpenSubtitles contestó con un error ({code})", "status")
        info = body.get("user") if isinstance(body.get("user"), dict) else {}
        allowed = info.get("allowed_downloads")
        remaining = info.get("remaining_downloads", allowed)
        self.adopt({"username": user, "token": body["token"], "base": body.get("base_url"), "allowed": allowed,
                    "remaining": remaining, "vip": bool(info.get("vip"))})
        return self.status()

    def adopt(self, account: dict) -> None:
        """Tu cuenta tal cual (la que manda el iPhone, sin contraseña)."""
        self._save({k: account.get(k) for k in ("username", "token", "base", "allowed", "remaining", "vip")})
        with self._lock:
            self._links.clear()

    def logout(self) -> None:
        self._save(None)
        with self._lock:
            self._links.clear()

    # --- buscar ---
    def search(self, video_id: str, fingerprint: tuple[str, int] | None = None) -> list[dict] | None:
        """Los subtítulos de un video, o None si la API no está, no contestó o se negó (queda el complemento)."""
        if not self.available:
            return None
        items = query(video_id, fingerprint[0] if fingerprint else None, self.languages())
        if items is None:
            return None
        url = f"{HOST}/subtitles?{urlencode(items)}"
        with self._lock:
            hit = self._searches.get(url)
            if hit and hit[0] > self.clock():
                return hit[1]
        try:
            code, body = self.http(url, headers=self._headers(), timeout=15)
        except NET_FAILURES as exc:
            log.info("OpenSubtitles no contestó: %s", exc)
            return None
        if code >= 400:
            log.info("OpenSubtitles contestó %s", code)
            return None
        options = parse(body)
        with self._lock:
            self._searches[url] = (self.clock() + CACHE_SECONDS, options)
            if len(self._searches) > 100:
                now = self.clock()
                self._searches = {k: v for k, v in self._searches.items() if v[0] > now}
        return options

    # --- bajar ---
    def resolve(self, url: str) -> str:
        """La dirección de verdad de un subtítulo de la API (gasta una de tu cuota; el mismo no se pide dos veces)."""
        if not url.startswith(SCHEME):
            return url
        file_id = url[len(SCHEME):]
        with self._lock:
            if file_id in self._links:
                return self._links[file_id]
        account = self.account()
        if not account or not self.available:
            raise OpenSubtitlesError(*(NOT_CONNECTED if self.available else NO_KEY))
        try:
            code, body = self.http(f"{self._root(account)}/download", method="POST", headers=self._headers(account["token"]),
                                   body={"file_id": int(file_id)}, timeout=15)
        except (*NET_FAILURES, TypeError) as exc:
            raise OpenSubtitlesError(*OFFLINE) from exc
        if code == 401:
            self._save(None)
            raise OpenSubtitlesError(*NOT_CONNECTED)
        if code in (406, 429):
            raise OpenSubtitlesError(*QUOTA)
        link = body.get("link") if isinstance(body, dict) else None
        if code >= 400 or not isinstance(link, str) or not link.startswith("https://"):
            raise OpenSubtitlesError(f"OpenSubtitles contestó con un error ({code})", "status")
        if isinstance(body, dict) and isinstance(body.get("remaining"), int):
            self._save({**account, "remaining": body["remaining"]})
        with self._lock:
            self._links[file_id] = link
        return link


_current: OpenSubtitles | None = None


def install(client: OpenSubtitles | None) -> None:
    """El de esta Orbital, para que el reproductor cambie «opensubtitles://file/…» por la dirección al bajarlo."""
    global _current
    _current = client


def resolve(url: str) -> str:
    if not url.startswith(SCHEME):
        return url
    if _current is None:
        raise OpenSubtitlesError(*NO_KEY)
    return _current.resolve(url)
