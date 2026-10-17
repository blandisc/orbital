"""La ficha de un juego que no está en la tienda de Steam (Hearthstone, Diablo Immortal, World of Warcraft…), de Wikidata y
Wikipedia en español, sin cuenta ni clave:

  wbsearchentities  -> el elemento del juego (el primero que Wikidata describe como juego)
  wbgetentities     -> año (P577), desarrollador (P178) y géneros (P136), con sus nombres en español
  page/summary      -> de qué trata (el resumen del artículo en español)

Solo texto: la imagen de Wikipedia muchas veces no es la portada (en Hearthstone, una foto de cosplay). Se guarda en
disco y se pide en segundo plano, con calma; lo que no se encontró se vuelve a buscar al mes.
"""

from __future__ import annotations

import json
import logging
import re
import threading
import time
from collections.abc import Callable
from pathlib import Path
from urllib.parse import quote

from ..net import NET_ERRORS, http_json

log = logging.getLogger(__name__)

API = "https://www.wikidata.org/w/api.php"
SUMMARY = "https://es.wikipedia.org/api/rest_v1/page/summary/{title}"
HEADERS = {"User-Agent": "Orbital/1.0 (consola personal; https://github.com/blandisc/orbital)"}
REFRESH = 30 * 86400
PAUSE = 1.0
GAME = re.compile(r"videojuego|juego|video game", re.I)


def _get(url: str) -> dict | None:
    try:
        status, data = http_json(url, headers=HEADERS, timeout=12)
    except NET_ERRORS:
        return None
    return data if status == 200 and isinstance(data, dict) else None


def _year(claims: dict) -> str | None:
    for claim in claims.get("P577") or []:
        value = ((claim.get("mainsnak") or {}).get("datavalue") or {}).get("value") or {}
        if (m := re.match(r"[+-]?(\d{4})", str(value.get("time") or ""))):
            return m.group(1)
    return None


def _ids(claims: dict, prop: str, limit: int) -> list[str]:
    out = []
    for claim in claims.get(prop) or []:
        value = ((claim.get("mainsnak") or {}).get("datavalue") or {}).get("value") or {}
        if isinstance(value, dict) and value.get("id"):
            out.append(str(value["id"]))
    return out[:limit]


def _genre(name: str) -> str:
    """«Videojuego de rol de acción» -> «Rol de acción» (como los demás géneros de la biblioteca)."""
    name = re.sub(r"^(videojuego|juego) de (los |las |la |el )?", "", name.strip(), flags=re.I)
    return name[:1].upper() + name[1:]


def _first_sentences(text: str, limit: int = 320) -> str:
    text = re.sub(r"\s+", " ", text).strip()
    if len(text) <= limit:
        return text
    cut = text[:limit]
    end = cut.rfind(". ")
    return cut[: end + 1] if end > 80 else cut.rstrip() + "…"


def lookup(title: str) -> dict | None:
    """{"description", "year", "developer", "genres"} de ese juego ({} si no se encontró); None si no se pudo preguntar.
    (Las pruebas cambian esta por una que no sale a internet; `find` es la de verdad.)"""
    return find(title)


def find(title: str) -> dict | None:
    found = _get(f"{API}?action=wbsearchentities&search={quote(title)}&language=es&uselang=es&type=item&limit=6&format=json")
    if found is None:
        return None
    results = [r for r in found.get("search") or [] if isinstance(r, dict)]
    pick = next((r for r in results if GAME.search(str(r.get("description") or ""))), None)
    if pick is None:
        # «World of Warcraft: Midnight» (una expansión): el juego de antes de los dos puntos.
        return find(title.split(":", 1)[0].strip()) if ":" in title else {}
    entity = _get(f"{API}?action=wbgetentities&ids={pick['id']}&props=claims|sitelinks&format=json")
    if entity is None:
        return None
    body = (entity.get("entities") or {}).get(pick["id"]) or {}
    claims = body.get("claims") or {}
    developers, genres = _ids(claims, "P178", 2), _ids(claims, "P136", 3)
    names: dict[str, str] = {}
    if developers or genres:
        labels = _get(f"{API}?action=wbgetentities&ids={'|'.join(developers + genres)}&props=labels&languages=es|en&format=json") or {}
        for qid, item in (labels.get("entities") or {}).items():
            label = (item.get("labels") or {}).get("es") or (item.get("labels") or {}).get("en") or {}
            if label.get("value"):
                names[qid] = str(label["value"])
    description = ""
    page = ((body.get("sitelinks") or {}).get("eswiki") or {}).get("title")
    if page:
        summary = _get(SUMMARY.format(title=quote(str(page).replace(" ", "_"), safe="")))
        description = _first_sentences(str((summary or {}).get("extract") or ""))
    genre_names = [_genre(names[g]) for g in genres if g in names]
    return {k: v for k, v in {
        "description": description, "year": _year(claims),
        "developer": ", ".join(names[d] for d in developers if d in names) or None, "genres": genre_names,
    }.items() if v}


class WikiGames:
    def __init__(self, path: Path | None, lookup_fn: Callable[[str], dict | None] | None = None, clock=time.time,
                 sleep=time.sleep) -> None:
        self.path = path
        # Se busca al llamar (no al definir): las pruebas cambian wiki_games.lookup por una que no sale a internet.
        self._lookup = lookup_fn or (lambda title: lookup(title))
        self._clock, self._sleep = clock, sleep
        self._lock = threading.Lock()
        self._data: dict[str, dict] = {}
        if path is not None:
            try:
                raw = json.loads(path.read_text(encoding="utf-8"))
                self._data = {k: v for k, v in raw.items() if isinstance(v, dict)} if isinstance(raw, dict) else {}
            except (OSError, ValueError):
                self._data = {}

    @staticmethod
    def _key(title: str) -> str:
        return re.sub(r"\s+", " ", title.lower()).strip()

    def cached(self, title: str) -> dict:
        return dict((self._data.get(self._key(title)) or {}).get("info") or {})

    def warm(self, titles: list[str], limit: int = 40, stop: threading.Event | None = None) -> int:
        got = 0
        for title in dict.fromkeys(t for t in titles if t):
            if got >= limit or (stop is not None and stop.is_set()):
                break
            entry = self._data.get(self._key(title))
            if entry and self._clock() - float(entry.get("at") or 0) < REFRESH:
                continue
            info = self._lookup(title)
            if info is None:
                break  # sin red: otro día
            with self._lock:
                self._data[self._key(title)] = {"info": info, "at": self._clock()}
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
            log.info("No pude guardar las fichas de Wikipedia: %s", exc)
