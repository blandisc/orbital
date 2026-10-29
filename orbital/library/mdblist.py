"""MDBList (mdblist.com): listas armadas con las calificaciones de Rotten Tomatoes, IMDb, Metacritic…

Rotten Tomatoes no tiene API pública. MDBList junta sus calificaciones y deja armar listas con filtros («Certified
Fresh», Tomatómetro ≥ 60 %); de ahí sale «Aprobadas por la crítica» en Para ti (revision-plan.md, §3).

  GET https://api.mdblist.com/lists/{usuario}/{lista}/items?apikey=…   con tu clave (gratis, 1 000 consultas al día)
  GET https://mdblist.com/lists/{usuario}/{lista}/json                   las listas públicas, sin clave

Las dos formas que contesta: una lista de títulos, o {"movies": […], "shows": […]}. Cada título trae `imdb_id`,
`title`, `mediatype` («movie» o «show») y `release_year`. Solo cuenta lo que trae IMDb, como todo lo demás.
"""

from __future__ import annotations

import logging
import re
from urllib.parse import quote, urlencode

from ..net import NET_ERRORS, http_json

log = logging.getLogger(__name__)

API = "https://api.mdblist.com"
SITE = "https://mdblist.com"


class MdbListError(Exception):
    pass


def parse_ref(ref: str) -> tuple[str, str] | None:
    """«usuario/lista» o la dirección de la lista (mdblist.com/lists/usuario/lista) → (usuario, lista)."""
    text = str(ref or "").strip().removeprefix("https://").removeprefix("mdblist.com/lists/").strip("/")
    match = re.fullmatch(r"([\w.-]+)/([\w.-]+)", text)
    return (match.group(1), match.group(2)) if match else None


def entries(data) -> list[dict]:
    """La respuesta de MDBList → títulos en la forma de Orbital ({kind, imdb, title, year}), sin repetir."""
    rows = data if isinstance(data, list) else [
        *(data.get("movies") or []), *(data.get("shows") or [])] if isinstance(data, dict) else []
    found, seen = [], set()
    for row in rows:
        if not isinstance(row, dict):
            continue
        imdb, title = row.get("imdb_id") or row.get("imdbid"), row.get("title")
        kind = {"movie": "movie", "show": "series", "tv": "series"}.get(str(row.get("mediatype") or "").lower())
        if not isinstance(imdb, str) or not re.fullmatch(r"tt\d+", imdb) or not isinstance(title, str) or not kind:
            continue
        if imdb in seen:
            continue
        seen.add(imdb)
        year = row.get("release_year") or row.get("year")
        found.append({"kind": kind, "imdb": imdb, "title": title.strip(), "year": year if isinstance(year, int) else None,
                      "runtime": None, "genres": [], "episodes": None, "overview": "", "trakt_id": None, "rating": None})
    return found


class MdbList:
    def __init__(self, key: str = "", timeout: float = 10) -> None:
        self.key = key
        self.timeout = timeout

    def list_items(self, ref: str, limit: int = 60) -> list[dict]:
        """Los títulos de una lista pública. Con clave, por la API; sin clave (o si la API falla), su JSON público."""
        parsed = parse_ref(ref)
        if parsed is None:
            raise MdbListError(f"Lista de MDBList inválida: {ref}")
        user, name = (quote(p) for p in parsed)
        urls = [f"{SITE}/lists/{user}/{name}/json"]
        if self.key:
            urls.insert(0, f"{API}/lists/{user}/{name}/items?" + urlencode({"apikey": self.key, "limit": limit}))
        last = "no contestó"
        for url in urls:
            try:
                status, data = http_json(url, timeout=self.timeout)
            except NET_ERRORS as exc:
                last = str(exc)
                continue
            if status == 200:
                return entries(data)[:limit]
            last = "no aceptó la clave" if status in (401, 403) else f"HTTP {status}"
        raise MdbListError(f"MDBList {last}")

    def check(self) -> None:
        """Prueba la clave (Ajustes › Cuentas): MdbListError si MDBList no la acepta."""
        try:
            status, _ = http_json(f"{API}/user?" + urlencode({"apikey": self.key}), timeout=self.timeout)
        except NET_ERRORS as exc:
            raise MdbListError(f"No pude conectar con MDBList: {exc}") from exc
        if status in (401, 403):
            raise MdbListError("MDBList no aceptó esa clave: cópiala otra vez de Preferences › API.")
        if status != 200:
            raise MdbListError(f"MDBList respondió HTTP {status}")
