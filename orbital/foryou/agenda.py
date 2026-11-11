"""Lo que sale: el calendario de estrenos, lo nuevo de lo tuyo y tus juegos.
"""

from __future__ import annotations

import logging
import random
from datetime import date, datetime, timedelta

from .base import CALENDAR_DAYS, GAME_CATEGORIES, LATEST_PAST_DAYS, RECS_TTL, SERVICE_ERRORS, SLOW_TTL
from .items import calendar_item, game_item
from .titles import _Titles

log = logging.getLogger("orbital.foryou")  # el mismo nombre de siempre: la bitácora no cambia


class _Agenda(_Titles):
    """Lo que sale: el calendario de estrenos, lo nuevo de lo tuyo y tus juegos."""

    # --- próximos estrenos -----------------------------------------------------------------------
    def calendar(self, now: datetime | None = None) -> list[dict]:
        """Los episodios que salen (hoy y los próximos días) de las series que sigues en Trakt, con la hora de aquí. Varios
        de la misma serie el mismo día (las plataformas sueltan tres juntos) van en una sola sugerencia: «E4–E6»."""
        now = now or datetime.now().astimezone()
        start = (now - timedelta(days=1)).date().isoformat()  # Trakt va en hora universal: un día antes, para no perder lo de hoy
        rows = self.cache.get(f"trakt:calendar:{start}", RECS_TTL, lambda: self.trakt.calendar(start, CALENDAR_DAYS + 2))
        today = now.date()
        return self._airings(rows, today, today + timedelta(days=CALENDAR_DAYS), today)

    def latest(self, now: datetime | None = None) -> list[dict]:
        """«Lo nuevo de lo tuyo» (como el Inicio del iPhone): lo que salió de tus series la semana pasada y lo que viene en
        las próximas dos, en orden de día. Trakt da hasta 31 días por pedido: alcanza en uno."""
        now = now or datetime.now().astimezone()
        today = now.date()
        first = today - timedelta(days=LATEST_PAST_DAYS)
        start = (first - timedelta(days=1)).isoformat()  # hora universal: un día antes
        days = LATEST_PAST_DAYS + CALENDAR_DAYS + 2
        rows = self.cache.get(f"trakt:calendar:{start}:{days}", RECS_TTL, lambda: self.trakt.calendar(start, days))
        return self._airings(rows, first, today + timedelta(days=CALENDAR_DAYS), today)

    def calendar_month(self, year: int, month: int, now: datetime | None = None) -> dict:
        """El mes completo (como «Sale hoy › el mes» del iPhone): lo que sale cada día de las series que sigues, también
        los días que ya pasaron. Trakt da hasta 31 días por pedido: el mes va en dos mitades (con un día de más a cada lado
        por la hora universal)."""
        now = now or datetime.now().astimezone()
        first = date(year, month, 1)
        following = date(year + (month == 12), month % 12 + 1, 1)
        start = first - timedelta(days=1)
        span = (following - first).days + 2
        rows: list[dict] = []
        for offset, days in ((0, 16), (16, span - 16)):
            begin = (start + timedelta(days=offset)).isoformat()
            ttl = RECS_TTL if following > now.date() else SLOW_TTL  # un mes que ya pasó no cambia
            rows += self.cache.get(f"trakt:calendar:{begin}:{days}", ttl, lambda b=begin, d=days: self.trakt.calendar(b, d))
        return {"month": f"{year:04d}-{month:02d}", "today": now.date().isoformat(),
                "items": self._airings(rows, first, following, now.date())}

    def _airings(self, rows: list[dict], first: date, end: date, today: date) -> list[dict]:
        """Los estrenos entre dos fechas (con la hora de aquí); varios de la misma serie el mismo día, en uno («E4–E6»)."""
        groups: dict[tuple, dict] = {}
        seen: set[tuple] = set()
        gone = self.unfollowed()  # las que dejaste de seguir (Trakt tarda en ocultarlas de su calendario)
        for row in rows:
            if (row["imdb"], row["season"], row["episode"]) in seen or row["imdb"] in gone:  # las dos mitades se tocan en un día
                continue
            seen.add((row["imdb"], row["season"], row["episode"]))
            when = datetime.fromtimestamp(row["aired"]).astimezone()
            day = when.date()
            if not first <= day < end:
                continue
            key = (day, row["imdb"])
            group = groups.get(key)
            if group:
                group["last"] = max(group["last"], row["episode"])
                group["first"] = min(group["first"], row["episode"])
                group["count"] += 1
                continue
            groups[key] = {**row, "when": when, "first": row["episode"], "last": row["episode"], "count": 1}
        return [calendar_item(g, today) for g in sorted(groups.values(), key=lambda g: (g["when"], g["title"]))]

    def airing_today(self) -> dict[str, str]:
        """{IMDb: «19:00»} de lo que sale hoy, para marcarlo en el Inicio («Sale hoy»). Sin Trakt o sin red: nada."""
        if not self.trakt.linked:
            return {}
        try:
            items = self.calendar()
        except SERVICE_ERRORS:
            return {}
        return {i["meta_id"]: i["time"] for i in items if i["today"]}

    # --- tus juegos ----------------------------------------------------------------------------
    def local_games(self, seed: int | None = None, lucky: int = 3) -> list[dict]:
        """Favoritos, los más jugados, los que nunca has abierto y uno al azar (cambia cada día)."""
        rng = random.Random(seed if seed is not None else date.today().toordinal())
        described = [self.services.describe(i) for i in self.services.items() if i.category in GAME_CATEGORIES]
        last = lambda d: d.get("last_played") or 0  # noqa: E731
        played = lambda d: float(d.get("playtime") or 0)  # noqa: E731
        favorites = sorted((d for d in described if d.get("favorite")), key=last, reverse=True)[:8]
        taken = {d["id"] for d in favorites}
        most = sorted((d for d in described if d["id"] not in taken and played(d) >= 3600), key=played, reverse=True)[:6]
        taken |= {d["id"] for d in most}
        fresh = [d for d in described if d["id"] not in taken and not played(d) and not last(d)]
        rng.shuffle(fresh)
        fresh = fresh[:8]
        taken |= {d["id"] for d in fresh}
        rest = [d for d in described if d["id"] not in taken]
        lucky_picks = rng.sample(rest, min(lucky, len(rest)))
        picks = ([game_item(d, "Tu favorito") for d in favorites] + [game_item(d, "Tu más jugado") for d in most]
                 + [game_item(d, "Sin jugar") for d in fresh] + [game_item(d, "Al azar") for d in lucky_picks])
        hidden = self.services.state.dismissed()
        return [p for p in picks if p["key"] not in hidden]
