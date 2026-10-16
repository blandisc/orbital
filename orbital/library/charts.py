"""Charts: el Top 10 oficial de Netflix (TSV público, por semana y país) y lo más popular de
JustWatch (GraphQL público) por plataforma. Ninguna de las dos fuentes pide clave.

  Netflix:   GET https://www.netflix.com/tudum/top10/data/all-weeks-countries.tsv  (varios MB: se
             lee en streaming y se filtra por país sin cargar el archivo entero en memoria).
             Columnas: country_name, country_iso2, week, category (Films|TV), weekly_rank,
             show_title, season_title, cumulative_weeks_in_top_10. Se toma la semana más reciente
             del país de Orbital y, para el sube y baja, la anterior (el TSV trae todas las semanas);
             sin datos de ese país, cae a .../all-weeks-global.tsv (otro
             esquema: category "Films (English)" / "TV (English)" / … , sin país).
             Solo trae títulos, no IMDb: se resuelve con TMDB (si hay clave) o, si no, con la
             búsqueda de Cinemeta. Lo que no se resuelve se omite (sin IMDb no hay con qué enlazarlo).

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

import csv
import io
import logging
import re
import sqlite3
import threading
import time
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

NETFLIX_COUNTRIES_URL = "https://www.netflix.com/tudum/top10/data/all-weeks-countries.tsv"
NETFLIX_GLOBAL_URL = "https://www.netflix.com/tudum/top10/data/all-weeks-global.tsv"
JUSTWATCH_URL = "https://apis.justwatch.com/graphql"
NETFLIX_TIMEOUT = 30

CATEGORY_KIND = {"Films": "movie", "TV": "series"}

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


# ---------------------------------------------------------------- Netflix: el TSV
def _open(url: str, timeout: float):
    req = urllib.request.Request(url, headers={"User-Agent": "Orbital"})
    return urllib.request.urlopen(req, timeout=timeout)


def _country_rows(url: str, iso2: str | None, *, open_url: Callable[[str], Any] | None = None,
                   timeout: float = NETFLIX_TIMEOUT) -> list[dict[str, str]]:
    """Lee el TSV en streaming (línea por línea, sin guardarlo entero) y se queda solo con las filas
    del país pedido (o todas, si `iso2` es None: el archivo global no tiene columna de país)."""
    opener = open_url or (lambda u: _open(u, timeout))
    deadline = time.monotonic() + max(10.0, timeout)
    try:
        with opener(url) as res:
            wrapper = io.TextIOWrapper(res, encoding="utf-8", errors="replace", newline="")
            reader = csv.reader(wrapper, delimiter="\t")
            try:
                header = next(reader)
            except StopIteration:
                return []
            idx = {name: i for i, name in enumerate(header)}
            country_col = idx.get("country_iso2")
            rows: list[dict[str, str]] = []
            for n, cols in enumerate(reader):
                if n % 5000 == 0 and time.monotonic() > deadline:
                    raise TimeoutError("El Top 10 de Netflix tardó demasiado en llegar")
                if len(cols) != len(header):
                    continue
                if country_col is not None and iso2 is not None and cols[country_col] != iso2:
                    continue
                rows.append(dict(zip(header, cols, strict=True)))
            return rows
    except NET_ERRORS as exc:
        raise ChartsError(f"No pude leer el Top 10 de Netflix: {exc}") from exc


def _weeks(rows: list[dict[str, str]]) -> list[str]:
    return sorted({week for r in rows if (week := r.get("week"))})


def _week_rows(rows: list[dict[str, str]], week: str | None) -> list[dict[str, str]]:
    return [r for r in rows if week and r.get("week") == week]


def _with_movement(latest: dict[str, list[dict]], previous: dict[str, list[dict]] | None, week: str) -> dict[str, list[dict]]:
    """El sube y baja contra la semana anterior: +2 si subió dos, None si la semana pasada no estaba (o no hay semana
    pasada). `new`: su primera semana en el Top 10, o no estaba la semana pasada."""
    for kind, entries in latest.items():
        before = None if previous is None else {_fold(e["title"]): e["rank"] for e in previous.get(kind, [])}
        for e in entries:
            was = None if before is None else before.get(_fold(e["title"]))
            e["movement"] = was - e["rank"] if was is not None else None
            e["new"] = e.get("weeks") == 1 or (before is not None and was is None)
            e["week"] = week
    return latest


def _rows_to_top10(rows: list[dict[str, str]], kind_of: Callable[[dict[str, str]], str | None]) -> dict[str, list[dict]]:
    out: dict[str, list[dict]] = {"movie": [], "series": []}
    for row in rows:
        kind = kind_of(row)
        if kind not in out or len(out[kind]) >= 10:
            continue
        title = str(row.get("show_title") or "").strip()
        rank = str(row.get("weekly_rank") or "")
        if not title or not rank.isdigit():
            continue
        weeks_raw = str(row.get("cumulative_weeks_in_top_10") or "")
        out[kind].append({"title": title, "rank": int(rank), "weeks": int(weeks_raw) if weeks_raw.isdigit() else None})
    for kind in out:
        out[kind].sort(key=lambda e: e["rank"])
    return out


def _global_top10(rows: list[dict[str, str]]) -> dict[str, list[dict]]:
    """El archivo global separa «(English)» de «(Non-English)»: se prefiere la de inglés (el Top 10
    global que de verdad se enseña); si no está, cualquiera que empiece con «Films»/«TV». `rows`: las de una semana."""
    latest = rows
    out: dict[str, list[dict]] = {}
    for prefix, kind in CATEGORY_KIND.items():
        preferred = [r for r in latest if r.get("category") == f"{prefix} (English)"]
        out[kind] = preferred or [r for r in latest if str(r.get("category") or "").startswith(prefix)]
    return {kind: _rows_to_top10(out[kind], lambda r, k=kind: k)[kind] for kind in out}


def fetch_netflix_top10(region: str, *, open_url: Callable[[str], Any] | None = None) -> dict[str, list[dict]]:
    """El Top 10 oficial de Netflix de la semana más reciente: hasta 10 películas y 10 series, con
    `title`, `rank` (1..10), `weeks` (semanas acumuladas en el Top 10), `movement` y `new` (contra la semana
    anterior) y `week`. Sin datos del país pedido: el Top 10 global (edición en inglés)."""
    country = _country_rows(NETFLIX_COUNTRIES_URL, region.upper(), open_url=open_url)
    weeks = _weeks(country)
    kind_of = lambda r: CATEGORY_KIND.get(str(r.get("category") or ""))  # noqa: E731
    if weeks:
        latest = _rows_to_top10(_week_rows(country, weeks[-1]), kind_of)
        previous = _rows_to_top10(_week_rows(country, weeks[-2]), kind_of) if len(weeks) > 1 else None
        return _with_movement(latest, previous, weeks[-1])
    global_rows = _country_rows(NETFLIX_GLOBAL_URL, None, open_url=open_url)
    weeks = _weeks(global_rows)
    if not weeks:
        return {"movie": [], "series": []}
    latest = _global_top10(_week_rows(global_rows, weeks[-1]))
    previous = _global_top10(_week_rows(global_rows, weeks[-2])) if len(weeks) > 1 else None
    return _with_movement(latest, previous, weeks[-1])


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
    rows = fetch_netflix_top10(region, open_url=open_url).get(kind, [])

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
