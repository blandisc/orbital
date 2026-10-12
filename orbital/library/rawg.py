"""RAWG (rawg.io): novedades, lo más popular y lo mejor calificado en juegos de PC.

  GET /api/games?dates=…&ordering=-added|-metacritic&parent_platforms=1   -> juegos
  GET /api/games/{id}/stores                                             -> tiendas (de aquí sale el id de Steam)
  GET /api/games/{id}                                                    -> descripción (en inglés)

Si el juego está en Steam se usan su portada vertical y su descripción en español (la tienda de Steam).
RAWG pide un enlace a rawg.io donde se muestran sus datos: la interfaz lo dice en el encabezado.
"""

from __future__ import annotations

import html
import logging
import re
from datetime import date, timedelta
from urllib.parse import urlencode

from ..net import NET_ERRORS, http_json

log = logging.getLogger(__name__)

API = "https://api.rawg.io/api"
STEAM_STORE = 1  # id de la tienda de Steam en RAWG
STEAM_APP = re.compile(r"store\.steampowered\.com/app/(\d+)")
STEAM_ART = "https://cdn.cloudflare.steamstatic.com/steam/apps/{appid}/{file}"
PC = 1  # «parent_platforms» de PC


class RawgError(Exception):
    pass


def _year(text) -> int | None:
    return int(text[:4]) if isinstance(text, str) and text[:4].isdigit() else None


def game(raw: dict) -> dict | None:
    if not isinstance(raw, dict) or not isinstance(raw.get("id"), int) or not str(raw.get("name") or "").strip():
        return None
    metacritic = raw.get("metacritic") if isinstance(raw.get("metacritic"), int) and raw.get("metacritic") > 0 else None
    return {"rawg_id": raw["id"], "title": str(raw["name"]).strip(), "year": _year(raw.get("released")),
            "released": raw.get("released") if isinstance(raw.get("released"), str) else None,
            "image": raw.get("background_image") if isinstance(raw.get("background_image"), str) else None,
            "metacritic": metacritic}


def steam_appid(stores) -> int | None:
    for row in stores if isinstance(stores, list) else []:
        if isinstance(row, dict) and row.get("store_id") == STEAM_STORE:
            found = STEAM_APP.search(str(row.get("url") or ""))
            if found:
                return int(found.group(1))
    return None


def plain(text: str) -> str:
    """La descripción de la tienda de Steam trae HTML: texto llano, sin etiquetas."""
    return re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", text or ""))).strip()


class Rawg:
    def __init__(self, key: str, timeout: float = 10) -> None:
        self.key = key
        self.timeout = timeout

    @property
    def configured(self) -> bool:
        return bool(self.key)

    def _get(self, path: str, **params):
        try:
            status, data = http_json(f"{API}{path}?{urlencode({'key': self.key, **params})}", timeout=self.timeout)
        except NET_ERRORS as exc:
            raise RawgError(f"No pude conectar con RAWG: {exc}") from exc
        if status in (401, 403):
            raise RawgError("RAWG no aceptó la clave de config.yaml (para_ti.rawg_key).")
        if status != 200 or not isinstance(data, dict):
            raise RawgError(f"RAWG respondió HTTP {status}")
        return data

    def games(self, list_id: str, today: date | None = None, size: int = 20) -> list[dict]:
        """«new»: lo que salió en los últimos 2 meses · «popular»: del último año, lo que más gente agregó ·
        «best»: lo mejor calificado en Metacritic."""
        today = today or date.today()
        if list_id == "new":
            params = {"dates": f"{today - timedelta(days=60)},{today}", "ordering": "-added"}
        elif list_id == "popular":
            params = {"dates": f"{today - timedelta(days=365)},{today}", "ordering": "-added"}
        elif list_id == "best":
            params = {"metacritic": "85,100", "ordering": "-metacritic"}
        else:
            raise RawgError("Lista desconocida")
        data = self._get("/games", parent_platforms=PC, page_size=size, **params)
        return [g for g in (game(r) for r in data.get("results") or []) if g]

    def steam_appid(self, rawg_id: int) -> int | None:
        return steam_appid(self._get(f"/games/{int(rawg_id)}/stores").get("results"))

    def description(self, rawg_id: int) -> str:
        return plain(str(self._get(f"/games/{int(rawg_id)}").get("description_raw") or ""))


def steam_description(appid: int, timeout: float = 8) -> str:
    """La descripción corta de la tienda de Steam, en español ("" si no hay)."""
    try:
        status, data = http_json(f"https://store.steampowered.com/api/appdetails?appids={int(appid)}&l=spanish&filters=basic",
                                 timeout=timeout)
    except NET_ERRORS:
        return ""
    entry = data.get(str(appid)) if status == 200 and isinstance(data, dict) else None
    body = entry.get("data") if isinstance(entry, dict) and entry.get("success") else None
    return plain(str(body.get("short_description") or "")) if isinstance(body, dict) else ""
