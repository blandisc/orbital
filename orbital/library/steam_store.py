"""La ficha de un juego en la tienda de Steam, en español: de qué trata, año, géneros y quién lo hizo.

Los juegos de consola traen esos datos de ES-DE (gamelist.xml); los de Steam y GeForce NOW no traían nada (solo nombre y
arte). La tienda los da sin cuenta ni clave:

  GET https://store.steampowered.com/api/appdetails?appids=<id>&l=spanish   -> {"<id>": {"success", "data": {...}}}

Se guardan en disco (`steam-store.json`) y se piden en segundo plano, de uno en uno y con calma (la tienda limita a
unas 200 consultas cada 5 minutos). Una ficha se vuelve a pedir al mes; un juego que no está en la tienda, a la semana.
"""

from __future__ import annotations

import json
import logging
import re
import threading
import time
from collections.abc import Callable
from pathlib import Path

from ..net import NET_ERRORS, http_json
from .rawg import plain

log = logging.getLogger(__name__)

URL = "https://store.steampowered.com/api/appdetails?appids={appid}&l=spanish"
REFRESH = 30 * 86400
RETRY_MISSING = 7 * 86400
PAUSE = 1.5  # s entre consulta y consulta


def parse(body: dict) -> dict:
    """De la respuesta de la tienda, lo que enseña Orbital (las mismas llaves que los juegos de ES-DE)."""
    year = re.search(r"\b(19|20)\d{2}\b", str((body.get("release_date") or {}).get("date") or ""))
    genres = [str(g.get("description")) for g in body.get("genres") or [] if isinstance(g, dict) and g.get("description")]
    developers = [str(d) for d in body.get("developers") or [] if d]
    info = {k: v for k, v in {
        "description": plain(str(body.get("short_description") or "")),
        "year": year.group(0) if year else None,
        "genres": genres[:3],
        "developer": ", ".join(developers[:2]) or None,
    }.items() if v}
    # ¿Se juega con control? «full» (todo) o «partial» (parte); sin el dato, «none» (teclado y ratón).
    info["controller"] = str(body.get("controller_support") or "none")
    return info


def fetch(appid: int, timeout: float = 10) -> dict | None:
    """La ficha de la tienda ({} si ese juego no está en la tienda); None si no se pudo preguntar (sin red, límite)."""
    try:
        status, data = http_json(URL.format(appid=int(appid)), timeout=timeout)
    except NET_ERRORS:
        return None
    if status != 200 or not isinstance(data, dict):
        return None  # 429: demasiadas consultas; se reintenta en la siguiente vuelta
    entry = data.get(str(appid))
    body = entry.get("data") if isinstance(entry, dict) and entry.get("success") else None
    if not isinstance(body, dict):
        return {}
    # El nombre y qué es (juego, DLC, música…): para los juegos de tu cuenta que no están instalados.
    return {**parse(body), "_name": str(body.get("name") or ""), "_type": str(body.get("type") or "")}


class SteamStore:
    def __init__(self, path: Path | None, fetch_fn: Callable[[int], dict | None] | None = None, clock=time.time,
                 sleep=time.sleep) -> None:
        self.path = path
        # Se busca al llamar (no al definir): las pruebas cambian steam_store.fetch por una que no sale a internet.
        self._fetch = fetch_fn or (lambda appid: fetch(appid))
        self._clock, self._sleep = clock, sleep
        self._lock = threading.Lock()
        self._data: dict[str, dict] = {}
        if path is not None:
            try:
                raw = json.loads(path.read_text(encoding="utf-8"))
                self._data = {k: v for k, v in raw.items() if isinstance(v, dict)} if isinstance(raw, dict) else {}
            except (OSError, ValueError):
                self._data = {}

    def cached(self, appid: int | None) -> dict:
        """Lo que se sabe de ese juego ({} si nada todavía)."""
        entry = self._data.get(str(appid)) if appid else None
        return {k: v for k, v in (entry.get("info") or {}).items() if not k.startswith("_")} if entry else {}

    def game_name(self, appid: int | str) -> str | None:
        """El nombre en la tienda si es un juego; None si no se sabe todavía o no es juego (DLC, banda sonora…)."""
        info = (self._data.get(str(appid)) or {}).get("info") or {}
        return info.get("_name") or None if info.get("_type") == "game" else None

    def known(self, appid: int | str) -> bool:
        return str(appid) in self._data

    def _stale(self, appid: int) -> bool:
        entry = self._data.get(str(appid))
        if not entry:
            return True
        if entry.get("info") and "controller" not in entry["info"]:
            return True  # guardada antes de saber si se juega con control: se vuelve a pedir una vez
        return self._clock() - float(entry.get("at") or 0) > (REFRESH if entry.get("info") else RETRY_MISSING)

    def warm(self, appids: list[int], limit: int = 60, stop: threading.Event | None = None) -> int:
        """Pide las fichas que faltan (o viejas), de una en una. Cuántas nuevas trajo."""
        got = 0
        for appid in dict.fromkeys(a for a in appids if a):
            if got >= limit or (stop is not None and stop.is_set()):
                break
            if not self._stale(appid):
                continue
            info = self._fetch(appid)
            if info is None:
                break  # sin red o la tienda pidió calma: se sigue en la siguiente vuelta
            with self._lock:
                self._data[str(appid)] = {"info": info, "at": self._clock()}
            got += 1
            self._sleep(PAUSE)
        if got:
            self.save()
        return got

    def save(self) -> None:
        if self.path is None:
            return
        with self._lock:
            text = json.dumps(self._data, ensure_ascii=False, separators=(",", ":"))
        try:
            self.path.parent.mkdir(parents=True, exist_ok=True)
            tmp = self.path.with_suffix(".tmp")
            tmp.write_text(text, encoding="utf-8")
            tmp.replace(self.path)
        except OSError as exc:
            log.info("No pude guardar las fichas de la tienda de Steam: %s", exc)
