"""«¿Qué vemos?» y «Tu año», como el iPhone (DecideModel y YearInReview), con lo que ya trae Para ti.

¿Qué vemos?: tres propuestas de tus sugerencias que no hayas visto ni apartado hoy, que quepan en el tiempo que tienes
(la hora lo propone: muy noche, poco; viernes en la noche y el fin de semana, dos horas o más) y en el ánimo o los géneros
que elijas. Lo que no trae su género o duración se le pregunta a Cinemeta (se recuerda).

Tu año: lo que viste desde el 1 de enero según tu historial de Trakt — horas, racha más larga, tu género, el mapa día por día
(películas, series o las dos) y lo que más viste.
"""

from __future__ import annotations

import random
import re
from collections import Counter
from datetime import date, datetime, timedelta

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


# --- Tu año ---------------------------------------------------------------------------------------------------------
def year_review(plays: list[dict], year: int, tz=None) -> dict:
    """Lo que muestra «Tu año» (como YearInReview del iPhone). Cada día: «movies», «series» o «both»."""
    days: dict[str, str] = {}
    by_day: dict[str, list[dict]] = {}
    minutes = movies = episodes = 0
    genres: Counter = Counter()
    counts: dict[str, dict] = {}
    for p in sorted(plays, key=lambda p: p["at"]):
        when = datetime.fromtimestamp(p["at"], tz).astimezone(tz)
        if when.year != year:
            continue
        day = when.date().isoformat()
        kind = "movies" if p["kind"] == "movie" else "series"
        days[day] = kind if days.get(day) in (None, kind) else "both"
        by_day.setdefault(day, []).append({"kind": p["kind"], "imdb": p["imdb"], "title": p["title"], "time": when.strftime("%H:%M"),
                                          "season": p.get("season"), "episode": p.get("episode"),
                                          "episode_title": p.get("episode_title")})
        minutes += int(p.get("minutes") or 0)
        if p["kind"] == "movie":
            movies += 1
        else:
            episodes += 1
        for g in p.get("genres") or []:
            genres[g] += 1
        top = counts.setdefault(p["imdb"], {"imdb": p["imdb"], "kind": p["kind"], "title": p["title"], "plays": 0})
        top["plays"] += 1
    longest = run = 0
    previous: date | None = None
    for day in sorted(days):
        d = date.fromisoformat(day)
        run = run + 1 if previous and d - previous == timedelta(days=1) else 1
        longest = max(longest, run)
        previous = d
    top_genre = min(genres.items(), key=lambda kv: (-kv[1], kv[0]))[0] if genres else None
    ranked = sorted(counts.values(), key=lambda t: (-t["plays"], t["title"]))[:10]
    return {"year": year, "hours": round(minutes / 60), "movies": movies, "episodes": episodes, "longest_streak": longest,
            "top_genre": top_genre, "days": days, "plays": by_day, "top": ranked}
