"""Charts: el Top 10 oficial de Netflix (TSV público, por semana y país) y lo más popular de
JustWatch (GraphQL público) por plataforma. Ninguna de las dos fuentes pide clave.

  Netflix:   GET https://www.netflix.com/tudum/top10/<país>[/tv]  (la página pública de la semana, ~600 KB; la misma
             que usa el iPhone, así los dos enseñan la misma semana). Trae la tabla (puesto, título con su temporada,
             semanas en el Top 10) y la lista de semanas: la anterior (?week=AAAA-MM-DD) da el sube y baja. Un país que
             Netflix no publica: la global. Solo trae títulos, no IMDb: se resuelve (sin la temporada) con TMDB si hay
             clave o con la búsqueda de Cinemeta; lo que no se resuelve se omite. (Antes era el TSV de todas las semanas:
             32 MB por bajada e iba una semana atrás de la página.)

  JustWatch: POST https://apis.justwatch.com/graphql con la consulta (no documentada) `streamingCharts`
             (la de las tendencias diarias de su sitio), filtrada por país, plataforma (`packages`: su
             nombre corto de 3 letras) y tipo. Ya trae el id de IMDb. Ojo: su `rank`, `trend`,
             `trendDifference` y `daysInTop10` son del ranking GENERAL del país (la primera de Disney+ puede
             ser la 14.ª de todo México y «subir 531 lugares»): aquí el puesto es el lugar dentro de la
             plataforma (1-10) y el sube y baja sale de la foto del día anterior (ChartSnapshots). Mide
             interés en JustWatch, no vistas: la interfaz lo dice («Tendencia en JustWatch»). Si el esquema
             cambió, esa lista queda vacía y se avisa una sola vez; nunca tumba las demás.

  Cada título lleva `rank` (1-10), `movement` (+2 subió dos, −1 bajó uno, 0 igual; None si no hay con qué
  comparar: no se inventan flechas) y `new` (entró esta semana / este día).
"""

from __future__ import annotations

import html
import logging
import re
import sqlite3
import threading
import urllib.request
from collections.abc import Callable
from concurrent.futures import ThreadPoolExecutor
from datetime import date, timedelta
from pathlib import Path
from typing import Any

from ..net import NET_ERRORS, http_json
from . import cinemeta as cinemeta_api
from .tmdb import Tmdb

log = logging.getLogger(__name__)

NETFLIX_PAGE = "https://www.netflix.com/tudum/top10"
# Los países de la página de Netflix (ISO2 → nombre en la URL), los mismos que el iPhone (Charts.netflixCountries). Uno que
# no esté: el Top 10 global.
NETFLIX_COUNTRIES = {
    "MX": "mexico", "US": "united-states", "CA": "canada", "AR": "argentina", "BO": "bolivia", "BR": "brazil", "CL": "chile",
    "CO": "colombia", "CR": "costa-rica", "DO": "dominican-republic", "EC": "ecuador", "SV": "el-salvador", "GT": "guatemala",
    "HN": "honduras", "NI": "nicaragua", "PA": "panama", "PY": "paraguay", "PE": "peru", "UY": "uruguay", "VE": "venezuela",
    "ES": "spain", "GB": "united-kingdom", "FR": "france", "DE": "germany", "IT": "italy", "PT": "portugal", "JP": "japan",
    "KR": "south-korea", "AU": "australia", "IN": "india",
}
JUSTWATCH_URL = "https://apis.justwatch.com/graphql"
NETFLIX_TIMEOUT = 20


JUSTWATCH_IMAGES = "https://images.justwatch.com"

# shortName (y logo) de JustWatch por marca, comprobados en vivo contra `packages(country: MX)`: si
# JustWatch cambia un shortName, esa plataforma deja de traer nada (se avisa una vez), no tumba las
# demás; si solo cambia el logo, la portada rota a su ícono (ya lo maneja rail.js / browse.js).
JUSTWATCH_PACKAGES: dict[str, tuple[str, str, str]] = {
    "netflix": ("nfx", "Netflix", "/icon/207360008/s100/netflix.png"),
    "disney": ("dnp", "Disney+", "/icon/313118777/s100/disneyplus.png"),
    "hbo": ("mxx", "HBO Max", "/icon/332884837/s100/max.png"),
    "prime": ("prv", "Prime Video", "/icon/322992749/s100/amazonprimevideo.png"),
    "appletv": ("atp", "Apple TV+", "/icon/338367329/s100/appletvplus.png"),
    "paramount": ("pmp", "Paramount+", "/icon/242706661/s100/paramountplus.png"),
    "crunchyroll": ("cru", "Crunchyroll", "/icon/324213205/s100/crunchyroll.png"),
}


def justwatch_logo(brand: str) -> str | None:
    pkg = JUSTWATCH_PACKAGES.get(brand)
    return f"{JUSTWATCH_IMAGES}{pkg[2]}" if pkg else None

# Las tendencias diarias de JustWatch por plataforma (la consulta de su página «Streaming Charts»), recortada a
# lo que se usa. Vienen en orden; `streamingChartInfo` se pide solo para comprobar que el esquema sigue igual.
_JUSTWATCH_QUERY = """
query GetStreamingCharts($country: Country!, $language: Language!, $first: Int!, $filter: StreamingChartsFilter) {
  streamingCharts(country: $country, first: $first, filter: $filter) {
    edges {
      streamingChartInfo { rank }
      node {
        objectType
        content(country: $country, language: $language) {
          title
          originalReleaseYear
          externalIds { imdbId }
        }
      }
    }
  }
}
"""
JUSTWATCH_FETCH = 20  # se piden de más: algunos no traen IMDb y quedan fuera; se enseñan 10

_OBJECT_TYPE = {"movie": "MOVIE", "series": "SHOW"}


class ChartsError(Exception):
    pass


def _fold(text: str) -> str:
    """Para comparar títulos sin pensar en mayúsculas o signos (igual que foryou.fold, sin import circular)."""
    return re.sub(r"[^a-z0-9]+", "", str(text or "").lower())


_jw_warned: set[str] = set()
_jw_warned_lock = threading.Lock()


def _jw_warn_once(brand: str, exc: Exception) -> None:
    with _jw_warned_lock:
        if brand in _jw_warned:
            return
        _jw_warned.add(brand)
    log.warning("Para ti: JustWatch cambió (o no respondió) para %s, se deja esa lista vacía: %s", brand, exc)


# ---------------------------------------------------------------- Netflix: su página por país
def _open(url: str, timeout: float):
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0", "Accept-Language": "en-US"})
    return urllib.request.urlopen(req, timeout=timeout)


def netflix_page_url(region: str, kind: str, week: str | None = None) -> str:
    """La página del Top 10 de ese país (o la global, si Netflix no publica el de ese país), de películas o de series."""
    slug = NETFLIX_COUNTRIES.get(region.upper())
    url = NETFLIX_PAGE + (f"/{slug}" if slug else "") + ("/tv" if kind == "series" else "")
    return url + (f"?week={week}" if week else "")


_ROW = re.compile(r'<span class="rank">(\d+)</span>.*?<button>(.*?)</button></td><td data-uia="top10-table-row-weeks">(\d+)</td>', re.S)
_WEEK = re.compile(r'"endDate":"(\d{4}-\d{2}-\d{2})"')
# «Below: Limited Series» → «Below»; «Physical 100: Mexico: Season 1» → «Physical 100: Mexico»: la página trae la temporada
# pegada al nombre y, para encontrar la serie, va sin ella (como `showTitle` en el iPhone).
_SEASON = re.compile(r":\s*(Season|Limited Series|Temporada|Miniserie|Part|Parte|Volume|Vol\.|Book|Chapter|Series)\b[^:]*$", re.I)


def show_title(title: str) -> str:
    return _SEASON.sub("", title).strip()


def parse_netflix_page(page: str) -> tuple[list[dict], list[str]]:
    """La tabla de la página (puesto, título, semanas en el Top 10) y las semanas que conoce (la última es la que enseña)."""
    rows = []
    for rank, title, weeks in _ROW.findall(page):
        title = html.unescape(re.sub(r"<[^>]+>", "", title)).strip()
        if title and len(rows) < 10:
            rows.append({"title": title, "rank": int(rank), "weeks": int(weeks)})
    return sorted(rows, key=lambda r: r["rank"]), sorted(set(_WEEK.findall(page)))


def _read_page(url: str, open_url: Callable[[str], Any] | None) -> tuple[list[dict], list[str]]:
    opener = open_url or (lambda u: _open(u, NETFLIX_TIMEOUT))
    try:
        with opener(url) as res:
            return parse_netflix_page(res.read().decode("utf-8", errors="replace"))
    except NET_ERRORS as exc:
        raise ChartsError(f"No pude leer el Top 10 de Netflix: {exc}") from exc


def fetch_netflix_top10(region: str, kind: str, *, open_url: Callable[[str], Any] | None = None) -> list[dict]:
    """El Top 10 oficial de Netflix de la semana más reciente, de su página pública por país (`netflix.com/tudum/top10`,
    ~600 KB: el iPhone usa la misma, así enseñan la misma semana; el TSV de todas las semanas pesaba 32 MB e iba una
    semana atrás). Cada uno con `title` (sin la temporada), `rank`, `weeks`, `movement` y `new` contra la semana
    anterior (`?week=`), y `week`."""
    rows, weeks = _read_page(netflix_page_url(region, kind), open_url)
    if not rows:
        return []
    previous = None
    if len(weeks) > 1:
        try:
            previous = _read_page(netflix_page_url(region, kind, weeks[-2]), open_url)[0]
        except ChartsError:
            previous = None  # sin la semana pasada: sin flechas (no se inventan)
    before = None if previous is None else {_fold(r["title"]): r["rank"] for r in previous}
    out = []
    for r in rows:
        was = None if before is None else before.get(_fold(r["title"]))
        out.append({"title": show_title(r["title"]), "rank": r["rank"], "weeks": r["weeks"],
                    "movement": was - r["rank"] if was is not None else None,
                    "new": r["weeks"] == 1 or (before is not None and was is None), "week": weeks[-1] if weeks else None})
    return out


# ---------------------------------------------------------------- Netflix: título → IMDb
def resolve_imdb(title: str, kind: str, *, tmdb: Tmdb | None, cinemeta: cinemeta_api.Cinemeta | None) -> str | None:
    """Título (sin año: el TSV de Netflix no lo trae) → id de IMDb. Con TMDB si hay clave; si no,
    con la búsqueda de Cinemeta. Sin ninguna, o sin nada parecido: None (se omite ese título)."""
    if tmdb is not None and tmdb.configured:
        found = tmdb.search(kind, title)
        return found["imdb"] if found and found.get("imdb") else None
    if cinemeta is not None:
        results = cinemeta.search(kind, title)
        match = _best_match(title, results)
        return str(match["id"]) if match else None
    return None


def _best_match(title: str, metas: list[dict]) -> dict | None:
    target = _fold(title)
    for meta in metas:
        if isinstance(meta, dict) and _fold(str(meta.get("name") or "")) == target:
            return meta
    return metas[0] if metas and isinstance(metas[0], dict) else None


def netflix_entries(region: str, kind: str, *, open_url: Callable[[str], Any] | None = None,
                     tmdb: Tmdb | None = None, cinemeta: cinemeta_api.Cinemeta | None = None) -> list[dict]:
    """El Top 10 de Netflix de ese tipo, ya con `imdb` (los que no se pudieron resolver, fuera)."""
    rows = fetch_netflix_top10(region, kind, open_url=open_url)

    def resolve(row: dict) -> dict | None:
        try:
            imdb = resolve_imdb(row["title"], kind, tmdb=tmdb, cinemeta=cinemeta)
        except NET_ERRORS:
            return None
        return {**row, "imdb": imdb} if imdb else None

    with ThreadPoolExecutor(max_workers=6) as pool:
        resolved = list(pool.map(resolve, rows))
    return [r for r in resolved if r]


# ---------------------------------------------------------------- JustWatch
def fetch_justwatch_chart(brand: str, region: str, kind: str, *,
                          post: Callable[..., tuple[int, Any]] | None = None) -> list[dict]:
    """La tendencia de hoy en esa plataforma (JustWatch), hasta 10 títulos con `imdb`, `title`, `year` y
    `rank` (su lugar en la plataforma, 1-10). Sin esa plataforma, o si el esquema cambió: lista vacía (se avisa
    una sola vez). El sube y baja lo pone ChartSnapshots (el `trend` de JustWatch es del ranking general)."""
    pkg = JUSTWATCH_PACKAGES.get(brand)
    if not pkg:
        return []
    short_name = pkg[0]
    send = post or http_json
    body = {
        "operationName": "GetStreamingCharts",
        "variables": {
            "country": region.upper(),
            "language": "es",
            "first": JUSTWATCH_FETCH,
            "filter": {"category": "DAILY_POPULARITY_SAME_CONTENT_TYPE", "objectType": _OBJECT_TYPE[kind], "packages": [short_name]},
        },
        "query": _JUSTWATCH_QUERY,
    }
    try:
        status, data = send(JUSTWATCH_URL, method="POST", body=body, timeout=12)
    except NET_ERRORS as exc:
        raise ChartsError(f"No pude conectar con JustWatch: {exc}") from exc
    if status != 200 or not isinstance(data, dict) or data.get("errors"):
        raise ChartsError(f"JustWatch respondió HTTP {status}" + (f": {data.get('errors')}" if isinstance(data, dict) else ""))
    try:
        edges = data["data"]["streamingCharts"]["edges"]
        out: list[dict] = []
        for edge in edges:
            node = edge["node"]
            content = node["content"]
            imdb = (content.get("externalIds") or {}).get("imdbId")
            title = content.get("title")
            if not (isinstance(imdb, str) and re.fullmatch(r"tt\d+", imdb)) or not isinstance(title, str) or not title.strip():
                continue
            out.append({"imdb": imdb, "title": title.strip(), "year": content.get("originalReleaseYear"), "rank": len(out) + 1})
            if len(out) >= 10:
                break
        return out
    except (KeyError, TypeError) as exc:
        _jw_warn_once(brand, exc)
        return []


# ---------------------------------------------------------------- fotos diarias (para el sube y baja)
class ChartSnapshots:
    """Una foto por día de cada lista (título y puesto), unas 8 semanas, en SQLite: así el sube y baja y «Nuevo» no
    dependen de que Orbital siga abierto desde ayer. Sin carpeta (pruebas), en memoria. Una falla del archivo no tumba
    la lista: se enseña sin flechas."""

    KEEP_DAYS = 56

    def __init__(self, path: Path | None = None) -> None:
        self._path = path
        self._lock = threading.Lock()
        self._mem: dict[tuple[str, str, str], dict[str, int]] = {}

    def _connect(self) -> sqlite3.Connection:
        assert self._path is not None
        self._path.parent.mkdir(parents=True, exist_ok=True)
        db = sqlite3.connect(self._path, timeout=5)
        db.execute("CREATE TABLE IF NOT EXISTS chart_snapshot (list_id TEXT NOT NULL, kind TEXT NOT NULL, day TEXT NOT NULL, "
                   "imdb TEXT NOT NULL, rank INTEGER NOT NULL, PRIMARY KEY (list_id, kind, day, imdb))")
        return db

    def _previous_and_save(self, list_id: str, kind: str, day: str, ranks: dict[str, int]) -> dict[str, int] | None:
        oldest = (date.fromisoformat(day) - timedelta(days=self.KEEP_DAYS)).isoformat()
        if self._path is None:
            earlier = sorted(d for (lid, k, d) in self._mem if lid == list_id and k == kind and d < day)
            self._mem[(list_id, kind, day)] = dict(ranks)
            return dict(self._mem[(list_id, kind, earlier[-1])]) if earlier else None
        with self._connect() as db:
            row = db.execute("SELECT MAX(day) FROM chart_snapshot WHERE list_id = ? AND kind = ? AND day < ? AND day >= ?",
                             (list_id, kind, day, oldest)).fetchone()
            previous = dict(db.execute("SELECT imdb, rank FROM chart_snapshot WHERE list_id = ? AND kind = ? AND day = ?",
                                       (list_id, kind, row[0])).fetchall()) if row and row[0] else None
            db.execute("DELETE FROM chart_snapshot WHERE list_id = ? AND kind = ? AND day = ?", (list_id, kind, day))
            db.executemany("INSERT INTO chart_snapshot VALUES (?, ?, ?, ?, ?)", [(list_id, kind, day, i, r) for i, r in ranks.items()])
            db.execute("DELETE FROM chart_snapshot WHERE day < ?", (oldest,))
        return previous

    def annotate(self, list_id: str, kind: str, entries: list[dict], today: date | None = None) -> list[dict]:
        """Guarda la foto de hoy y marca cada título contra la del día anterior que haya (la de hoy se reemplaza si se
        vuelve a pedir: el sube y baja de un día no cambia en cada recarga)."""
        day = (today or date.today()).isoformat()
        ranks = {e["imdb"]: e["rank"] for e in entries if e.get("imdb")}
        try:
            with self._lock:
                previous = self._previous_and_save(list_id, kind, day, ranks)
        except (sqlite3.Error, OSError, ValueError) as exc:
            log.warning("Para ti: no pude guardar la foto de %s (%s): %s", list_id, kind, exc)
            previous = None
        for e in entries:
            imdb = e.get("imdb")
            was = previous.get(imdb) if previous is not None and isinstance(imdb, str) else None
            e["movement"] = was - e["rank"] if was is not None else None
            e["new"] = previous is not None and was is None
        return entries
