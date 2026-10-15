"""TMDB (themoviedb.org): lo más popular en cada plataforma de tu país y sinopsis en español.

  GET /watch/providers/{movie|tv}?watch_region=MX            -> plataformas (id, nombre, logo)
  GET /discover/{movie|tv}?with_watch_providers=…&watch_region=MX&sort_by=popularity.desc
  GET /{movie|tv}/{id}?append_to_response=external_ids       -> id de IMDb, duración, temporadas
  GET /find/{imdb}?external_source=imdb_id                   -> la ficha en español de algo de Trakt

Es «lo más popular disponible en Netflix» (popularidad de TMDB), no el Top 10 oficial de Netflix.
La clave puede ser la «API Key» (v3) o el «Read Access Token» (v4, empieza con eyJ).
"""

from __future__ import annotations

import logging
from urllib.parse import urlencode

from ..net import NET_ERRORS, http_json

log = logging.getLogger(__name__)

def _positive(value) -> int | None:
    """Un entero mayor que cero (lo demás de la API: None)."""
    return value if isinstance(value, int) and value > 0 else None


API = "https://api.themoviedb.org/3"
IMAGES = "https://image.tmdb.org/t/p"
KINDS = {"movie": "movie", "series": "tv"}
# Cómo se llama cada plataforma en TMDB (cambian de nombre: «HBO Max» → «Max» → «HBO Max»).
PLATFORMS = {
    "netflix": ("Netflix", ("netflix",)),
    "disney": ("Disney+", ("disney plus", "disney+")),
    "hbo": ("HBO Max", ("hbo max", "max")),
}


class TmdbError(Exception):
    pass


def image(path, size: str = "w500") -> str | None:
    return f"{IMAGES}/{size}{path}" if isinstance(path, str) and path.startswith("/") else None


def _year(text) -> int | None:
    return int(text[:4]) if isinstance(text, str) and text[:4].isdigit() else None


def match_platforms(rows) -> dict[str, dict]:
    """De la lista de plataformas de TMDB: Netflix, Disney+ y HBO Max (por nombre exacto, sin acentos ni mayúsculas)."""
    found: dict[str, dict] = {}
    for row in rows if isinstance(rows, list) else []:
        if not isinstance(row, dict) or not isinstance(row.get("provider_id"), int):
            continue
        name = str(row.get("provider_name") or "").strip().lower()
        for brand, (_, names) in PLATFORMS.items():
            if brand not in found and name in names:
                found[brand] = {"id": row["provider_id"], "logo": image(row.get("logo_path"), "w154")}
    return found


class Tmdb:
    def __init__(self, key: str, language: str = "es-MX", timeout: float = 10) -> None:
        self.key = key
        self.language = language
        self.timeout = timeout

    @property
    def configured(self) -> bool:
        return bool(self.key)

    def _get(self, path: str, **params):
        headers = {}
        if self.key.startswith("eyJ"):  # «Read Access Token» (v4)
            headers["Authorization"] = f"Bearer {self.key}"
        else:
            params["api_key"] = self.key
        params.setdefault("language", self.language)
        try:
            status, data = http_json(f"{API}{path}?{urlencode(params)}", headers=headers, timeout=self.timeout)
        except NET_ERRORS as exc:
            raise TmdbError(f"No pude conectar con TMDB: {exc}") from exc
        if status == 401:
            raise TmdbError("TMDB no aceptó la clave de config.yaml (para_ti.tmdb_key).")
        if status != 200 or not isinstance(data, dict):
            raise TmdbError(f"TMDB respondió HTTP {status}")
        return data

    def platforms(self, region: str) -> dict[str, dict]:
        rows = []
        for kind in ("movie", "tv"):
            rows += self._get(f"/watch/providers/{kind}", watch_region=region).get("results") or []
        return match_platforms(rows)

    def discover(self, kind: str, provider_id: int, region: str) -> list[dict]:
        data = self._get(f"/discover/{KINDS[kind]}", with_watch_providers=provider_id, watch_region=region,
                         sort_by="popularity.desc", with_watch_monetization_types="flatrate", page=1)
        return [r for r in data.get("results") or [] if isinstance(r, dict) and isinstance(r.get("id"), int)]

    def details(self, kind: str, tmdb_id: int) -> dict:
        """Lo que hace falta para la ficha, en español; con su id de IMDb (None si TMDB no lo tiene)."""
        raw = self._get(f"/{KINDS[kind]}/{int(tmdb_id)}", append_to_response="external_ids")
        external = raw.get("external_ids") if isinstance(raw.get("external_ids"), dict) else {}
        imdb = raw.get("imdb_id") or external.get("imdb_id")
        return {
            "kind": kind, "tmdb_id": raw.get("id"),
            "imdb": imdb if isinstance(imdb, str) and imdb.startswith("tt") else None,
            "title": str(raw.get("title") or raw.get("name") or "").strip(),
            "year": _year(raw.get("release_date") or raw.get("first_air_date")),
            "overview": str(raw.get("overview") or "").strip(),
            "runtime": _positive(raw.get("runtime")),
            "seasons": raw.get("number_of_seasons") if isinstance(raw.get("number_of_seasons"), int) else None,
            "episodes": raw.get("number_of_episodes") if isinstance(raw.get("number_of_episodes"), int) else None,
            "poster": image(raw.get("poster_path")), "backdrop": image(raw.get("backdrop_path"), "w1280"),
        }

    def find(self, imdb: str, kind: str) -> dict | None:
        """La ficha en español de un título de IMDb (lo de Trakt llega con sinopsis en inglés)."""
        data = self._get(f"/find/{imdb}", external_source="imdb_id")
        rows = data.get("movie_results" if kind == "movie" else "tv_results") or []
        first = rows[0] if rows and isinstance(rows[0], dict) and isinstance(rows[0].get("id"), int) else None
        return self.details(kind, first["id"]) if first else None
