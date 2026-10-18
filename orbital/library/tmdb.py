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
# Los estudios de «Estudios» (su id en TMDB), los mismos que el iPhone (Tmdb.studios).
STUDIOS = [(41077, "A24"), (3, "Pixar"), (10342, "Studio Ghibli"), (420, "Marvel Studios"), (1, "Lucasfilm"),
           (3172, "Blumhouse"), (521, "DreamWorks Animation"), (90733, "NEON")]

PLATFORMS = {
    "netflix": ("Netflix", ("netflix",)),
    "disney": ("Disney+", ("disney plus", "disney+")),
    "hbo": ("HBO Max", ("hbo max", "max")),
}


class TmdbError(Exception):
    pass


class TmdbKeyError(TmdbError):
    """TMDB no aceptó la clave (no es la red)."""


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
            raise TmdbKeyError("TMDB no aceptó la clave. Revísala en Ajustes › Cuentas.")
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

    def fresh(self, kind: str, provider_id: int, region: str, today: str, since_series: str, since_movies: str) -> list[dict]:
        """Lo nuevo en una plataforma, con las reglas del iPhone: series con episodios en las dos últimas semanas; películas
        estrenadas en los últimos tres meses que ya están ahí (TMDB no dice cuándo llegó algo: esto es lo más cercano)."""
        dates = ({"air_date.gte": since_series, "air_date.lte": today} if kind == "series"
                 else {"primary_release_date.gte": since_movies, "primary_release_date.lte": today, "vote_count.gte": 10})
        data = self._get(f"/discover/{KINDS[kind]}", with_watch_providers=provider_id, watch_region=region,
                         with_watch_monetization_types="flatrate", sort_by="popularity.desc", page=1, **dates)
        return [r for r in data.get("results") or [] if isinstance(r, dict) and isinstance(r.get("id"), int)]

    def studio(self, company_id: int, kind: str = "movie") -> list[dict]:
        """Lo más popular de un estudio (A24, Pixar, Ghibli…), con al menos 50 votos, como el iPhone."""
        data = self._get(f"/discover/{KINDS[kind]}", with_companies=int(company_id), sort_by="popularity.desc",
                         **{"vote_count.gte": 50}, page=1)
        return [r for r in data.get("results") or [] if isinstance(r, dict) and isinstance(r.get("id"), int)]

    def company_logo(self, company_id: int) -> str | None:
        """El logo de un estudio (PNG transparente de TMDB), para Películas y series › Estudios."""
        raw = self._get(f"/company/{int(company_id)}")
        return image(raw.get("logo_path"), "w300") if isinstance(raw, dict) else None

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
            # La calificación de TMDB (0–10), para la ficha («TMDB 84 %», como el iPhone); None sin votos.
            "rating": round(float(raw["vote_average"]), 1) if isinstance(raw.get("vote_average"), (int, float))
            and raw.get("vote_average") and (raw.get("vote_count") or 0) > 0 else None,
        }

    def images(self, kind: str, tmdb_id: int, limit: int = 18) -> dict[str, list[str]]:
        """Los pósters y fondos de un título (para «Cambiar el arte»): primero los en español, luego inglés y sin texto."""
        raw = self._get(f"/{KINDS[kind]}/{int(tmdb_id)}/images", include_image_language="es,en,null", language="es")
        order = {"es": 0, "en": 1, None: 2}

        def pick(rows, size):
            rows = [r for r in rows or [] if isinstance(r, dict) and r.get("file_path")]
            rows.sort(key=lambda r: (order.get(r.get("iso_639_1"), 3), -float(r.get("vote_average") or 0)))
            return [url for r in rows[:limit] if (url := image(r["file_path"], size))]

        return {"posters": pick(raw.get("posters"), "w500"), "backgrounds": pick(raw.get("backdrops"), "w1280")}

    def find_id(self, imdb: str, kind: str) -> int | None:
        """El id de TMDB de un título de IMDb (None si TMDB no lo tiene)."""
        data = self._get(f"/find/{imdb}", external_source="imdb_id")
        rows = data.get("movie_results" if kind == "movie" else "tv_results") or []
        first = rows[0] if isinstance(rows, list) and rows and isinstance(rows[0], dict) else None
        return _positive(first.get("id")) if first else None

    def translation(self, kind: str, tmdb_id: int, language: str, episodes: bool = False) -> dict:
        """Título, sinopsis, géneros y (en series) los episodios en ese idioma: {(temporada, episodio): {…}}."""
        raw = self._get(f"/{KINDS[kind]}/{int(tmdb_id)}", language=language)
        found = {"title": str(raw.get("title") or raw.get("name") or "").strip(),
                 "overview": str(raw.get("overview") or "").strip(),
                 "genres": [g["name"] for g in raw.get("genres") or [] if isinstance(g, dict) and isinstance(g.get("name"), str)][:3],
                 "episodes": {}}
        numbers = [s.get("season_number") for s in raw.get("seasons") or [] if isinstance(s, dict)]
        numbers = [n for n in numbers if isinstance(n, int) and n >= 0]
        for start in range(0, len(numbers) if episodes and kind == "series" else 0, 20):  # TMDB: 20 por consulta
            batch = numbers[start:start + 20]
            data = self._get(f"/tv/{int(tmdb_id)}", language=language,
                             append_to_response=",".join(f"season/{n}" for n in batch))
            for n in batch:
                season = data.get(f"season/{n}") if isinstance(data.get(f"season/{n}"), dict) else {}
                for ep in season.get("episodes") or []:
                    if isinstance(ep, dict) and isinstance(ep.get("episode_number"), int):
                        found["episodes"][(n, ep["episode_number"])] = {
                            "name": str(ep.get("name") or "").strip(), "overview": str(ep.get("overview") or "").strip()}
        return found

    def search(self, kind: str, title: str, year: int | None = None) -> dict | None:
        """Busca un título por nombre (y año, si se tiene) y devuelve su ficha completa, con su id de
        IMDb. Para charts.py: ahí solo hay título, no id de TMDB."""
        params: dict[str, object] = {"query": title}
        if year:
            params["year" if kind == "movie" else "first_air_date_year"] = year
        data = self._get(f"/search/{KINDS[kind]}", **params)
        results = [r for r in data.get("results") or [] if isinstance(r, dict) and isinstance(r.get("id"), int)]
        return self.details(kind, results[0]["id"]) if results else None

    def find(self, imdb: str, kind: str) -> dict | None:
        """La ficha en español de un título de IMDb (lo de Trakt llega con sinopsis en inglés)."""
        data = self._get(f"/find/{imdb}", external_source="imdb_id")
        rows = data.get("movie_results" if kind == "movie" else "tv_results") or []
        first = rows[0] if rows and isinstance(rows[0], dict) and isinstance(rows[0].get("id"), int) else None
        return self.details(kind, first["id"]) if first else None
