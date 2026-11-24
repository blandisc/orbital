"""«Esta semana» (Fernando, 23 nov 2026, ED-B y ED-C): la tabla `listas/explorar.json` del repositorio, la misma que lee el
iPhone (`ExploreTable` en OrbitalCore). Las listas con fechas salen en su temporada y van primero; las demás rotan cada lunes.

En la TV salen en Colecciones (☰), junto a Criterion y el Top 250. Un capítulo (los especiales de Los Simpson) abre la ficha
de su serie en ese capítulo, como en el iPhone.
"""

from __future__ import annotations

import json
import re
from datetime import UTC, date, datetime
from pathlib import Path

TABLE_URL = "https://raw.githubusercontent.com/blandisc/orbital/main/listas/explorar.json"
TABLE_TTL = 86400  # s: la tabla se vuelve a pedir una vez al día (como el iPhone)
LOCAL_TABLE = Path(__file__).resolve().parents[2] / "listas" / "explorar.json"  # sin red: la que trae esta copia de Orbital

_EPISODE = re.compile(r"tt\d+:\d+:\d+")


def _month_day(text: str | None) -> tuple[int, int] | None:
    parts = str(text or "").split("-")
    if len(parts) != 2 or not all(p.isdigit() for p in parts):
        return None
    month, day = int(parts[0]), int(parts[1])
    return (month, day) if 1 <= month <= 12 and 1 <= day <= 31 else None


def dated(entry: dict) -> bool:
    return _month_day(entry.get("from")) is not None and _month_day(entry.get("to")) is not None


def in_season(entry: dict, today: date) -> bool:
    start, end = _month_day(entry.get("from")), _month_day(entry.get("to"))
    if start is None or end is None:
        return False
    now = (today.month, today.day)
    return start <= now <= end if start <= end else (now >= start or now <= end)


def this_week(table: dict, today: date) -> list[dict]:
    """Las de esta semana: las de temporada que van hoy y luego `rotate` de las demás (igual que el iPhone: semanas desde el
    lunes 5 ene 1970, así cambian el lunes)."""
    lists = [e for e in table.get("lists") or [] if isinstance(e, dict) and e.get("id")]
    seasonal = [e for e in lists if dated(e) and in_season(e, today)]
    wheel = [e for e in lists if not dated(e)]
    rotate = int(table.get("rotate") or 0)
    if not wheel or rotate <= 0:
        return seasonal
    if len(wheel) <= rotate:
        return seasonal + wheel
    midnight = datetime(today.year, today.month, today.day, tzinfo=UTC).timestamp()
    week = int((midnight - 4 * 86400) // (7 * 86400))
    start = (week * rotate) % len(wheel)
    return seasonal + [wheel[(start + i) % len(wheel)] for i in range(rotate)]


def written(entry: dict) -> list[dict]:
    """Los títulos escritos en la tabla. Un capítulo va con su id completo («tt0096697:7:11») y kind «episode»."""
    out = []
    for e in entry.get("items") or []:
        if not isinstance(e, dict) or not e.get("id"):
            continue
        kind = "episode" if _EPISODE.fullmatch(str(e["id"])) else (e.get("kind") or "movie")
        out.append({"imdb": e["id"], "kind": kind, "title": e.get("title") or "", "year": e.get("year")})
    return out


def episode(imdb: str) -> tuple[str, int, int] | None:
    """«tt0096697:7:11» → (serie, temporada, capítulo); None si es una película o una serie."""
    if not _EPISODE.fullmatch(str(imdb or "")):
        return None
    show, season, number = imdb.split(":")
    return show, int(season), int(number)


def local_table() -> dict:
    try:
        return json.loads(LOCAL_TABLE.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
