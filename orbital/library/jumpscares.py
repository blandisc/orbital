"""Los sustos de una película (Where's The Jump): en qué segundo, qué pasa y si es de los fuertes (PA7-B, como el iPhone).

Where's The Jump es un sitio hecho a mano por su comunidad: cada película tiene una página con sus sustos, uno por renglón
(«00:13:35 – A ladder cracks…»), y los fuertes van en negritas. Se busca por nombre en inglés y año, y se confirma con el id
de IMDb que trae la página. El mismo camino que `JumpScares.swift` del iPhone (y las mismas pruebas con la misma página).
"""

from __future__ import annotations

import html as html_lib
import logging
import re
import unicodedata
import urllib.request
from collections.abc import Callable
from dataclasses import dataclass
from urllib.parse import quote_plus

from ..net import NET_FAILURES, read_body, urlopen

log = logging.getLogger("orbital.jumpscares")

SITE = "https://wheresthejump.com"
TIMEOUT = 10
MAX_CANDIDATES = 4  # de la búsqueda del sitio, cuántas páginas se abren hasta dar con esa película


@dataclass(frozen=True)
class JumpScare:
    time: float  # segundos
    text: str
    major: bool  # de los fuertes (en negritas en la página)

    def public(self) -> dict:
        return {"time": self.time, "text": self.text, "major": self.major}


def slugify(text: str) -> str:
    """«Insidious: Chapter 2» → «insidious-chapter-2» (como el sitio arma sus direcciones)."""
    plain = unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode().lower()
    plain = plain.replace("&", "and").replace("'", "").replace("’", "")
    return "-".join(p for p in re.split(r"[^a-z0-9]+", plain) if p)


def page_url(title: str, year: int | None) -> str:
    """«jump-scares-in-insidious-2010»."""
    return f"{SITE}/jump-scares-in-{slugify(title)}{f'-{year}' if year else ''}/"


def search_url(title: str) -> str:
    return f"{SITE}/?s={quote_plus(title)}"


def search_results(page: str, year: int | None) -> list[str]:
    """Las páginas de la búsqueda del sitio, las de ese año (o uno cerca) primero."""
    seen: list[str] = []
    for link in re.findall(r"https://wheresthejump\.com/jump-scares-in-[a-z0-9-]+/", page):
        if link not in seen:
            seen.append(link)

    def close(link: str) -> int:
        tail = link.rstrip("/").rsplit("-", 1)[-1]
        return abs(int(tail) - year) if year and tail.isdigit() else 9

    return sorted(seen, key=close)


_ROW = re.compile(r"(<strong>|<b>)?\s*(\d{1,2}):(\d{2}):(\d{2})\s*(?:<[^>]+>\s*)*(?:–|&#8211;|-|&ndash;)\s*([^<]{3,220})")


def parse(page: str) -> list[JumpScare]:
    """«00:13:35 – A ladder cracks…», un renglón por susto; los que van en `<strong>` son los fuertes."""
    cleaned = re.sub(r"<(script|style)[\s\S]*?</\1>", " ", page)
    out: dict[float, JumpScare] = {}
    for m in _ROW.finditer(cleaned):
        seconds = int(m.group(2)) * 3600 + int(m.group(3)) * 60 + int(m.group(4))
        if seconds in out:
            continue
        out[seconds] = JumpScare(float(seconds), html_lib.unescape(m.group(5)).replace("\xa0", " ").strip(), m.group(1) is not None)
    return sorted(out.values(), key=lambda s: s.time)


def checked(page: str, imdb: str | None) -> list[JumpScare] | None:
    """La página es de esa película (su id de IMDb aparece) y trae su lista."""
    if imdb and f"title/{imdb}" not in page:
        return None
    return parse(page)


def _get(url: str) -> str | None:
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 Orbital"})
    try:
        with urlopen(req, timeout=TIMEOUT) as res:
            if getattr(res, "status", 200) != 200:
                return None
            return read_body(res, timeout=TIMEOUT).decode("utf-8", errors="replace")
    except NET_FAILURES as exc:
        log.info("Where's The Jump: %s (%s)", url, exc)
        return None


def scares(title: str, year: int | None, imdb: str | None, *, get: Callable[[str], str | None] | None = None) -> list[JumpScare] | None:
    """Los sustos de una película; [] si la página existe pero no tiene, None si no hay página (o no es esa película)."""
    fetch = get or _get
    # 1) La página directa (nombre y año); el año de Cinemeta a veces es uno más o menos que el del sitio.
    for y in [year, year - 1, year + 1] if year else []:
        found = fetch(page_url(title, y))
        if found and (listed := checked(found, imdb)) is not None:
            return listed
    # 2) La búsqueda del sitio: los primeros resultados, hasta el que sea esa película (su id de IMDb).
    page = fetch(search_url(title))
    if not page:
        return None
    for link in search_results(page, year)[:MAX_CANDIDATES]:
        found = fetch(link)
        if found and (listed := checked(found, imdb)) is not None:
            return listed
    return None
