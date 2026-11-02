"""«¿Qué vemos?», como el iPhone (DecideModel), con lo que ya trae Para ti.

¿Qué vemos?: tres propuestas de tus sugerencias que no hayas visto ni apartado hoy, que quepan en el tiempo que tienes
(la hora lo propone: muy noche, poco; viernes en la noche y el fin de semana, dos horas o más) y en el ánimo o los géneros
que elijas. Lo que no trae su género o duración se le pregunta a Cinemeta (se recuerda).
"""

from __future__ import annotations

import random
import re
from datetime import datetime

TIMES = ("short", "hour", "long")
MOODS = {
    "light": {"comedy", "animation", "family", "adventure", "musical"},
    "intense": {"thriller", "action", "horror", "crime", "war"},
    "think": {"drama", "documentary", "sci-fi", "mystery", "history", "biography"},
    "together": {"romance", "comedy", "fantasy", "music"},
}
TRIO = 3
SKIP_HOURS = 24


def context_time(now: datetime) -> str:
    """El tiempo según la hora (como el iPhone): muy noche, poco; viernes en la noche y el fin de semana, mucho."""
    if now.hour >= 23 or now.hour < 5:
        return "short"
    if now.weekday() >= 5 or (now.weekday() == 4 and now.hour >= 18):
        return "long"
    return "hour"


def normalized(genre: str) -> str:
    """«Science Fiction», «science-fiction» y «Sci-Fi» son el mismo."""
    g = str(genre).strip().lower().replace("-", " ")
    return "sci-fi" if g in ("science fiction", "sci fi") else g


def fits(minutes: int | None, time: str) -> bool:
    """¿Cabe en el tiempo que tienes? (una serie cuenta por episodio). Sin dato: no para «30 min»."""
    if not minutes or minutes <= 0:
        return time != "short"
    return minutes <= 35 if time == "short" else minutes <= 75 if time == "hour" else True


def matches(genres: list[str], mood: str | None, picked: set[str]) -> bool:
    found = {normalized(g) for g in genres}
    if picked:
        return bool(found & picked)
    if mood in MOODS:
        return bool(found & MOODS[mood])
    return True


def fnv_order(day: int, imdb: str) -> int:
    """El orden revuelto del mazo «¿Qué vemos hoy?», el mismo que el iPhone (MatchDeckModel.hash: FNV-1a de «día:imdb» con su
    mezcla final): el mismo orden si vuelves a abrirlo hoy, y otro mañana."""
    x = 14_695_981_039_346_656_037
    for byte in f"{day}:{imdb}".encode():
        x = ((x ^ byte) * 1_099_511_628_211) & 0xFFFF_FFFF_FFFF_FFFF
    x ^= x >> 33
    x = (x * 0xFF51_AFD7_ED55_8CCD) & 0xFFFF_FFFF_FFFF_FFFF
    x ^= x >> 33
    return x


def runtime_minutes(text) -> int | None:
    """«2h 49min», «169 min», «45» → minutos (None si no se entiende)."""
    if isinstance(text, (int, float)):
        return int(text) or None
    s = str(text or "").lower()
    hours = re.search(r"(\d+)\s*h", s)
    mins = re.search(r"(\d+)\s*m", s)
    if hours or mins:
        return (int(hours[1]) * 60 if hours else 0) + (int(mins[1]) if mins else 0) or None
    bare = re.fullmatch(r"\s*(\d+)\s*", s)
    return int(bare[1]) or None if bare else None


def choose(pool: list[dict], *, time: str, mood: str | None = None, kind: str | None = None, genres: set[str] | None = None,
           exclude: set[str] | frozenset[str] = frozenset(), details: dict[str, dict] | None = None, rng: random.Random | None = None,
           count: int = TRIO) -> list[dict]:
    """Las que caben, al azar (lo que sigues primero). Si ninguna cabe en el tiempo, las más cercanas del ánimo pedido."""
    rng = rng or random.Random()
    details = details or {}
    genres = {normalized(g) for g in genres or ()}
    seen: set[str] = set()
    candidates = []
    for item in pool:
        imdb = item.get("meta_id")
        if not imdb or imdb in seen or imdb in exclude or item.get("kind") not in ("movie", "series"):
            continue
        if kind and item["kind"] != kind:
            continue
        seen.add(imdb)
        candidates.append(item)
    following = [i for i in candidates if i.get("episode")]
    rest = [i for i in candidates if not i.get("episode")]
    rng.shuffle(following)
    rng.shuffle(rest)
    picked, closest = [], []
    for item in following + rest:
        d = details.get(item["meta_id"], {})
        if not matches(item.get("genres") or d.get("genres") or [], mood, genres):
            continue
        (picked if fits(item.get("runtime") or d.get("minutes"), time) else closest).append(item)
        if len(picked) >= count:
            break
    # Las que no caben, de la más corta a la más larga (sin duración, al final): antes salían al azar y con «media hora»
    # aparecían películas de casi dos horas mientras el texto decía que cabían (regresión S2, 2026-10-30).
    closest.sort(key=lambda i: i.get("runtime") or details.get(i["meta_id"], {}).get("minutes") or 10_000)
    return (picked + closest)[:count]


