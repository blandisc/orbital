"""Cuánto tarda un juego en terminarse, de HowLongToBeat (como Game Glance y HLTB for Deck).

HowLongToBeat no tiene API pública: su página pide un token (GET <búsqueda>/init) y con él busca (POST <búsqueda>).
La ruta de búsqueda ha cambiado varias veces (/api/search, /api/seek/…, /api/search/site): si la conocida falla, se
descubre otra vez en los scripts de su página. Si algo de esto deja de funcionar, el dato simplemente no sale.

Los resultados se guardan en disco (un mes; lo que no se encontró, unos días): la tele nunca espera a internet, solo
enseña lo que ya se sabe (Catalog los pone en `extra["hltb"]`). Se llenan en segundo plano con tus juegos recientes.
Basado en HLTB for Deck (MIT), vía Game Glance (MIT).
"""

from __future__ import annotations

import json
import logging
import re
import threading
import time
import urllib.error
import urllib.request
from difflib import SequenceMatcher
from pathlib import Path

from ..net import NET_ERRORS, read_body, read_json
from ..text import normalize

log = logging.getLogger(__name__)

SITE = "https://howlongtobeat.com"
DEFAULT_SEARCH = "/api/search/site"
# Un navegador de verdad: con otro agente, HowLongToBeat contesta 403.
USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"
KEEP = 30 * 86400
KEEP_MISS = 4 * 86400
MATCH = 0.78  # qué tan parecido debe ser el nombre


def _headers(extra: dict | None = None) -> dict:
    return {"User-Agent": USER_AGENT, "Origin": SITE, "Referer": f"{SITE}/", "Content-Type": "application/json", **(extra or {})}


def _request(url: str, body: dict | None = None, extra: dict | None = None, timeout: float = 12):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method="POST" if body is not None else "GET", headers=_headers(extra))
    return urllib.request.urlopen(req, timeout=timeout)


def hours(seconds) -> float | None:
    """Segundos → horas, al medio más cercano (HowLongToBeat da segundos)."""
    if not isinstance(seconds, (int, float)) or seconds <= 0:
        return None
    return round(seconds / 1800) / 2 or 0.5


def best_match(title: str, results: list[dict], year: int | str | None = None) -> dict | None:
    """El resultado con el nombre más parecido; con el año del juego, gana el de ese año («Star Wars: Battlefront II» de
    2005, no el de 2017); si empatan, el que más gente ha registrado."""
    want = normalize(title)
    year = int(year) if str(year or "").isdigit() else None
    scored = []
    for r in results:
        if not isinstance(r, dict):
            continue
        ratio = SequenceMatcher(None, want, normalize(str(r.get("game_name") or ""))).ratio()
        if ratio < MATCH:
            continue
        same_year = year is not None and r.get("release_world") == year
        scored.append((same_year, round(ratio, 2), r.get("comp_all_count") or 0, r))
    return max(scored, key=lambda s: s[:3])[3] if scored else None


def times_of(result: dict) -> dict | None:
    out = {"main": hours(result.get("comp_main")), "plus": hours(result.get("comp_plus")), "all": hours(result.get("comp_100"))}
    return out if any(out.values()) else None


class Hltb:
    def __init__(self, path: Path | None, request=None, clock=time.time) -> None:
        self.path = path
        # Se busca al llamar (no al definir): las pruebas cambian _request por una sin internet.
        self._request = request or (lambda *args, **kwargs: _request(*args, **kwargs))
        self.clock = clock
        self._lock = threading.Lock()
        self._search = DEFAULT_SEARCH
        self._auth: dict | None = None
        self._data: dict[str, dict] = {}
        if path and path.is_file():
            try:
                self._data = json.loads(path.read_text(encoding="utf-8"))
            except (OSError, ValueError):
                self._data = {}

    # --- lo guardado ----------------------------------------------------------------------------------------------
    @staticmethod
    def _key(title: str, year=None) -> str:
        return f"{normalize(title)}|{year or ''}"

    def cached(self, title: str, year=None) -> dict | None:
        entry = self._data.get(self._key(title, year))
        return entry.get("times") if entry else None

    def _fresh(self, title: str, year=None) -> bool:
        entry = self._data.get(self._key(title, year))
        if not entry:
            return False
        return self.clock() - entry.get("at", 0) < (KEEP if entry.get("times") else KEEP_MISS)

    def _save(self) -> None:
        if self.path is None:
            return
        try:
            self.path.parent.mkdir(parents=True, exist_ok=True)
            tmp = self.path.with_suffix(".tmp")
            tmp.write_text(json.dumps(self._data, ensure_ascii=False), encoding="utf-8")
            tmp.replace(self.path)
        except OSError as exc:
            log.info("No pude guardar los tiempos de HowLongToBeat: %s", exc)

    # --- HowLongToBeat ---------------------------------------------------------------------------------------------
    def _token(self) -> dict | None:
        with self._request(f"{SITE}{self._search}/init?t={int(self.clock() * 1000)}") as res:
            data = read_json(res, timeout=12)
        if not isinstance(data, dict) or not isinstance(data.get("token"), str):
            return None
        auth = {"token": data["token"]}
        for name, value in data.items():
            if isinstance(value, str) and name != "token":
                if "key" in name.lower() and "hp_key" not in auth:
                    auth["hp_key"] = value
                elif "val" in name.lower() and "hp_val" not in auth:
                    auth["hp_val"] = value
        return auth

    def _discover(self) -> str:
        """La ruta de búsqueda vigente, leída de los scripts de la página (si no se encuentra, la de siempre)."""
        try:
            with self._request(SITE) as res:
                html = read_body(res, timeout=12).decode("utf-8", "replace")
            for src in re.findall(r'<script[^>]+src="(/_next/static/[^"]+\.js)"', html):
                with self._request(f"{SITE}{src}") as res:
                    script = read_body(res, timeout=12, limit=8 * 1024 * 1024).decode("utf-8", "replace")
                if "searchTerms" not in script:
                    continue
                found = re.findall(r'fetch\(\s*["`\']/api/([\w/]+?)["`\'][^)]{0,200}?method:\s*["`\']POST', script)
                for path in found:
                    path = path.rstrip("/").removesuffix("/init")
                    if f"/api/{path}/init" in script:
                        return f"/api/{path}"
                if found:
                    return f"/api/{found[0].rstrip('/')}"
        except NET_ERRORS as exc:
            log.debug("HowLongToBeat: no pude descubrir la búsqueda: %s", exc)
        return DEFAULT_SEARCH

    def _post(self, title: str) -> list[dict]:
        body = {"searchType": "games", "searchTerms": title.split(), "searchPage": 1, "size": 20,
                "searchOptions": {"games": {"userId": 0, "platform": "", "sortCategory": "name", "rangeCategory": "main",
                                            "rangeTime": {"min": 0, "max": 0},
                                            "gameplay": {"perspective": "", "flow": "", "genre": "", "difficulty": ""},
                                            "modifier": "hide_dlc"},
                                  "users": {}, "filter": "", "sort": 0, "randomizer": 0}}
        extra = {"x-auth-token": self._auth["token"]}
        if self._auth.get("hp_key") and self._auth.get("hp_val"):
            extra |= {"x-hp-key": self._auth["hp_key"], "x-hp-val": self._auth["hp_val"]}
            body[self._auth["hp_key"]] = self._auth["hp_val"]
        with self._request(f"{SITE}{self._search}", body=body, extra=extra) as res:
            data = read_json(res, timeout=12)
        return data.get("data") if isinstance(data, dict) and isinstance(data.get("data"), list) else []

    def search(self, title: str) -> list[dict]:
        """Busca (con token; si falla, token nuevo; si vuelve a fallar, redescubre la ruta)."""
        for attempt in range(3):
            try:
                if attempt == 2:
                    self._search = self._discover()
                    self._auth = None
                if self._auth is None:
                    self._auth = self._token()
                    if self._auth is None:
                        continue
                return self._post(title)
            except urllib.error.HTTPError as exc:
                if exc.code not in (401, 403, 404):
                    raise
                self._auth = None
        return []

    def lookup(self, title: str, year=None) -> dict | None:
        """Los tiempos de ese juego (de lo guardado o, si no, de HowLongToBeat). None si no se encontró."""
        with self._lock:
            if self._fresh(title, year):
                return self.cached(title, year)
            try:
                found = best_match(title, self.search(title), year)
            except NET_ERRORS as exc:
                log.info("HowLongToBeat no contestó (%s): %s", title, exc)
                return self.cached(title, year)
            times = times_of(found) if found else None
            self._data[self._key(title, year)] = {"at": self.clock(), "times": times}
            self._save()
            return times

    def warm(self, games: list[tuple[str, object]], pause: float = 1.5) -> int:
        """Llena lo que falta (en segundo plano), con calma entre uno y otro. `games`: [(nombre, año)]. Devuelve cuántos
        encontró."""
        found = 0
        for title, year in games:
            if self._fresh(title, year):
                continue
            if self.lookup(title, year):
                found += 1
            time.sleep(pause)
        return found
