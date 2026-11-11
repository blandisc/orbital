"""Lo que viste (vistas, historial, «Tu año»), notas, el calendario, el avance y lo que sigue."""

from __future__ import annotations

import re
import time

from .base import (
    KINDS,
    NOTE_LIMIT,
    PLAYBACK_TTL,
    SAME_VIEWING_WINDOW,
    TraktAuthError,
    TraktError,
    _dict,
    _iso,
    _positive,
    _typed,
    _when,
    activity_stamps,
    entry,
    history_body,
    history_play,
    playback_entry,
    playback_row,
    show_completed,
    show_progress,
)
from .lists import _Lists


class _History(_Lists):
    """Lo que viste, notas, el calendario y el avance."""

    # --- ola 3 del gestor (O3-B, 10 nov 2026, como `Trakt+History.swift`): tus vistas, tu historial, tu nota y tus temporadas
    def viewings(self, kind: str, imdb: str, season: int | None = None, episode: int | None = None) -> list[dict]:
        """Cada vez que viste esta película o este capítulo ({id, at}), la más nueva primero. El id es el de esa vista en tu
        historial: lo que se borra."""
        if kind not in KINDS or not re.fullmatch(r"tt[0-9]{1,12}", imdb or ""):
            raise TraktError("Título inválido")
        typ = "movie" if kind == "movie" else "show"
        found = self._get(f"/search/imdb/{imdb}", type=typ)
        first = _dict(found[0]) if isinstance(found, list) and found else {}
        trakt_id = _dict(_dict(first.get(typ)).get("ids")).get("trakt")
        if not isinstance(trakt_id, int):
            return []
        out = []
        for raw in self._all_pages(f"/sync/history/{typ}s/{trakt_id}"):
            row = _dict(raw)
            ep = _dict(row.get("episode"))
            if season is not None and (ep.get("season") != season or ep.get("number") != episode):
                continue
            at = _when(row.get("watched_at"))
            if isinstance(row.get("id"), int) and at is not None:
                out.append({"id": row["id"], "at": at})
        return sorted(out, key=lambda v: -v["at"])

    def remove_viewings(self, ids: list[int]) -> None:
        """Borra solo esas vistas de tu historial (las demás se quedan)."""
        clean = [i for i in ids if isinstance(i, int) and i > 0]
        if clean:
            self._send("POST", "/sync/history/remove", {"ids": clean}, idempotent=True)

    def history(self, page: int = 1, limit: int = 100) -> list[dict]:
        """Tu historial, lo más nuevo primero: {id, at, kind, imdb, title, year, season, episode, episode_title}."""
        rows = self._get("/sync/history", page=max(1, int(page)), limit=limit)
        out = []
        for raw in rows if isinstance(rows, list) else []:
            row = _dict(raw)
            at = _when(row.get("watched_at"))
            movie = _dict(row.get("movie"))
            show, ep = _dict(row.get("show")), _dict(row.get("episode"))
            item = movie or show
            imdb = _dict(item.get("ids")).get("imdb")
            if not isinstance(row.get("id"), int) or at is None or not isinstance(imdb, str):
                continue
            found = {"id": row["id"], "at": at, "kind": "movie" if movie else "series", "imdb": imdb,
                     "title": str(item.get("title") or imdb), "year": item.get("year") if isinstance(item.get("year"), int) else None,
                     "season": None, "episode": None, "episode_title": None}
            if not movie:
                if not isinstance(ep.get("season"), int) or not isinstance(ep.get("number"), int):
                    continue
                found.update(season=ep["season"], episode=ep["number"], episode_title=str(ep.get("title") or "") or None)
            out.append(found)
        return out

    def is_vip(self) -> bool:
        """¿Tu cuenta de Trakt es VIP? (las notas viven en Trakt solo así)."""
        user = _dict(_dict(self._get("/users/settings")).get("user"))
        return user.get("vip") is True or user.get("vip_ep") is True

    def my_notes(self) -> dict[str, dict]:
        """Tus notas de películas y series en Trakt: {IMDb: {id, text}}."""
        out: dict[str, dict] = {}
        for typ in ("movies", "shows"):
            for raw in self._all_pages(f"/users/me/notes/{typ}"):
                row = _dict(raw)
                item = _dict(row.get("movie") or row.get("show"))
                imdb, note = _dict(item.get("ids")).get("imdb"), _dict(row.get("note"))
                if isinstance(imdb, str) and isinstance(note.get("id"), int) and isinstance(note.get("notes"), str):
                    out[imdb] = {"id": note["id"], "text": note["notes"]}
        return out

    def set_note(self, kind: str, imdb: str, text: str, existing: int | None) -> int | None:
        """Escribe (o, con texto vacío, borra) tu nota de una película o serie; siempre privada. Devuelve su id."""
        if kind not in KINDS or not re.fullmatch(r"tt[0-9]{1,12}", imdb or ""):
            raise TraktError("Título inválido")
        clean = text.strip()[:NOTE_LIMIT]
        if not clean:
            if existing:
                try:
                    self._send("DELETE", f"/notes/{existing}")
                except TraktAuthError:
                    raise
                except TraktError as exc:
                    if exc.status != 404:
                        raise
            return None
        if existing:
            try:
                data = self._send("PUT", f"/notes/{existing}", {"notes": clean, "privacy": "private", "spoiler": False})
                return _dict(data).get("id") or existing
            except TraktAuthError:
                raise
            except TraktError as exc:
                if exc.status != 404:  # la borraste en trakt.tv: se hace otra
                    raise
        data = self._send("POST", "/notes", {("movie" if kind == "movie" else "show"): {"ids": {"imdb": imdb}},
                                             "notes": clean, "privacy": "private", "spoiler": False})
        found = _dict(data).get("id")
        return found if isinstance(found, int) else None

    def season_rating(self, imdb: str, season: int) -> int | None:
        """Tu calificación (1–10) de una temporada, o None."""
        for raw in self._all_pages("/sync/ratings/seasons"):
            row = _dict(raw)
            if _dict(_dict(row.get("show")).get("ids")).get("imdb") == imdb and _dict(row.get("season")).get("number") == season:
                return row.get("rating") if isinstance(row.get("rating"), int) else None
        return None

    def set_season_rating(self, imdb: str, season: int, rating: int | None) -> None:
        """Califica una temporada (1–10) o, con None, quita tu calificación."""
        if not re.fullmatch(r"tt[0-9]{1,12}", imdb or "") or not isinstance(season, int):
            raise TraktError("Título inválido")
        one = {"number": season, **({} if rating is None else {"rating": int(rating)})}
        self._send("POST", "/sync/ratings" + ("/remove" if rating is None else ""), {"shows": [{"ids": {"imdb": imdb}, "seasons": [one]}]})

    def my_rating(self, kind: str, imdb: str) -> int | None:
        """Tu calificación de un título (1–10) o None si no lo has calificado."""
        rows = self._all_pages(f"/sync/ratings/{KINDS[kind]}")
        for row in rows if isinstance(rows, list) else []:
            item = row.get(KINDS[kind][:-1]) if isinstance(row, dict) else None
            if isinstance(item, dict) and (item.get("ids") or {}).get("imdb") == imdb:
                return row.get("rating")
        return None

    def list_items(self, list_id: str) -> list[dict]:
        """Todos los títulos de tu lista. Trakt los da de cien en cien (con `page`): antes solo se leía la primera página y
        una lista de 210 parecía de 100 (4 nov 2026, «Mi lista Stremio»)."""
        if not str(list_id).isdigit():
            raise TraktError("Lista inválida")
        return _typed(self._all_pages(f"/users/me/lists/{list_id}/items", extended="full"))

    def public_list_items(self, user: str, slug: str) -> list[dict]:
        """Los títulos de la lista pública de otra persona (sin tu sesión): «Aprobadas por la crítica» de series."""
        if not re.fullmatch(r"[\w.-]+", str(user)) or not re.fullmatch(r"[\w.-]+", str(slug)):
            raise TraktError("Lista inválida")
        return _typed(self._get(f"/users/{user}/lists/{slug}/items", auth=False, extended="full"))

    def trending(self, kind: str, limit: int = 30) -> list[dict]:
        rows = self._get(f"/{KINDS[kind]}/trending", auth=False, limit=limit, extended="full")
        key = "movie" if kind == "movie" else "show"
        return [e for e in (entry(r.get(key), kind) for r in rows if isinstance(r, dict)) if e] if isinstance(rows, list) else []

    def popular(self, kind: str, limit: int = 30, years: int | None = None) -> list[dict]:
        """Lo más popular; con `years`, de ese año (Por año)."""
        params = {"limit": limit, "extended": "full", **({"years": int(years)} if years else {})}
        rows = self._get(f"/{KINDS[kind]}/popular", auth=False, **params)
        return [e for e in (entry(r, kind) for r in rows) if e] if isinstance(rows, list) else []

    def search(self, kind: str, query: str, limit: int = 15) -> list[dict]:
        """Buscar sin sesión (respaldo de Buscar cuando Cinemeta falla, como el iPhone). Solo lo que trae IMDb."""
        key = "movie" if kind == "movie" else "show"
        rows = self._get(f"/search/{key}", auth=False, query=query, limit=limit, extended="full")
        return [e for e in (entry(r.get(key), kind) for r in rows if isinstance(r, dict)) if e] if isinstance(rows, list) else []

    def rating(self, kind: str, imdb: str) -> float | None:
        """La calificación de Trakt de un título (0–10; para la ficha, como el iPhone). None si no la tiene."""
        if not isinstance(imdb, str) or not imdb.startswith("tt") or not imdb[2:].isdigit():
            return None
        raw = self._get(f"/{KINDS[kind]}/{imdb}", auth=False, extended="full")
        found = entry(raw, kind) if isinstance(raw, dict) else None
        return found.get("rating") if found else None

    def watched_ids(self) -> list[str]:
        """Los IMDb de lo que ya viste (películas y series), para «Ocultar lo que ya vi» en una lista."""
        found: list[str] = []
        for kind, key in (("movies", "movie"), ("shows", "show")):
            rows = self._get(f"/sync/watched/{kind}", extended="full") if kind == "shows" else self._get(f"/sync/watched/{kind}")
            for row in rows if isinstance(rows, list) else []:
                if kind == "shows" and not show_completed(row):
                    continue  # una serie a la mitad no cuenta como vista (como el iPhone)
                raw = row.get(key) if isinstance(row, dict) else None
                imdb = (raw.get("ids") or {}).get("imdb") if isinstance(raw, dict) and isinstance(raw.get("ids"), dict) else None
                if isinstance(imdb, str) and imdb.startswith("tt"):
                    found.append(imdb)
        return found

    def related(self, kind: str, imdb: str, limit: int = 15) -> list[dict]:
        """Lo que Trakt relaciona con un título («Porque viste X»), como el iPhone."""
        if not isinstance(imdb, str) or not imdb.startswith("tt") or not imdb[2:].isdigit():
            return []
        rows = self._get(f"/{KINDS[kind]}/{imdb}/related", auth=False, limit=limit, extended="full")
        return [e for e in (entry(r, kind) for r in rows) if e] if isinstance(rows, list) else []

    def recent_watched(self, limit: int = 12) -> list[dict]:
        """Los últimos títulos distintos que viste (una película, o la serie de un episodio), el más reciente primero,
        para «Porque viste X»: los 12 que el iPhone deja elegir (ForYou.recentSeeds: historial de 40)."""
        rows = self._get("/sync/history", limit=40, extended="full")
        found: list[dict] = []
        for row in rows if isinstance(rows, list) else []:
            if not isinstance(row, dict):
                continue
            e = entry(row.get("movie"), "movie") if row.get("type") == "movie" else entry(row.get("show"), "series")
            if e and all(f["imdb"] != e["imdb"] for f in found):
                found.append({**e, "watched_at": _when(row.get("watched_at"))})
                if len(found) >= limit:
                    break
        return found

    HISTORY_PAGE = 250

    def plays(self, since: str, until: str, max_pages: int = 20) -> list[dict]:
        """«Tu año»: cada cosa que viste entre dos fechas (ISO 8601), como el iPhone (Trakt.plays): {at (segundos), kind,
        imdb, title, minutes, genres, season, episode, episode_title}. Son varias páginas de 250."""
        found: list[dict] = []
        page_size = 0
        for page in range(1, max(1, max_pages) + 1):
            rows = self._get("/sync/history", start_at=since, end_at=until, extended="full", limit=self.HISTORY_PAGE, page=page)
            rows = rows if isinstance(rows, list) else []
            for row in rows:
                play = history_play(row)
                if play:
                    found.append(play)
            # La última trae menos que la primera (o nada): si Trakt pone su propio tope por página, «menos de 250» cortaba
            # en la primera (como el iPhone).
            if not rows or len(rows) < page_size:
                break
            page_size = page_size or len(rows)
        return found

    def last_watched(self) -> dict | None:
        """Lo último que viste (una película, o la serie de tu último episodio)."""
        recent = self.recent_watched(1)
        return recent[0] if recent else None

    def calendar(self, start: str, days: int = 15) -> list[dict]:
        """Los episodios que salen de las series que sigues, desde `start` (AAAA-MM-DD, en hora universal) y `days` días:
        {serie (como entry), season, episode, title, aired (segundos desde 1970), network, runtime}. Sin IMDb, no entra."""
        rows = self._get(f"/calendars/my/shows/{start}/{max(1, min(int(days), 31))}", extended="full")
        found = []
        for row in rows if isinstance(rows, list) else []:
            if not isinstance(row, dict):
                continue
            show = entry(row.get("show"), "series")
            ep = row.get("episode") if isinstance(row.get("episode"), dict) else {}
            aired = _when(row.get("first_aired"))
            season, number = ep.get("season"), ep.get("number")
            if not show or aired is None or not isinstance(season, int) or not isinstance(number, int):
                continue
            raw_show = row["show"]
            network = raw_show.get("network") if isinstance(raw_show.get("network"), str) else ""
            found.append({**show, "season": season, "episode": number, "episode_title": str(ep.get("title") or "").strip(),
                          "aired": aired, "network": network.strip(),
                          "runtime": _positive(ep.get("runtime")) or show.get("runtime")})
        return sorted(found, key=lambda e: e["aired"])

    def playback(self, now: float | None = None) -> dict[str, dict]:
        """Dónde ibas en cada película y episodio según Trakt (GET /sync/playback: lo que pausaste o cerraste entre 1 y
        79 %, desde cualquier app: el iPhone, la TV…), con un minuto de caché. {«tt123» o «tt123:2:5»: avance}."""
        now = time.time() if now is None else now
        cached = self._playback
        if cached is not None and now - cached[0] < PLAYBACK_TTL:
            return cached[1]
        rows = self._get("/sync/playback", extended="full", limit=100)
        found: dict[str, dict] = {}
        for row in rows if isinstance(rows, list) else []:
            parsed = playback_entry(row)
            if parsed and (parsed[0] not in found or parsed[1]["paused_at"] > found[parsed[0]]["paused_at"]):
                found[parsed[0]] = parsed[1]
        self._playback = (now, found)
        return found

    def forget_playback(self) -> None:
        """Pausaste o cerraste: lo que se pidió a Trakt ya no es lo último (la siguiente vez se pide otra vez)."""
        self._playback = None

    # --- lo tuyo, para Seguir viendo, la ficha y Mi lista (trakt_sync.py) ---------------------------------------------
    def last_activities(self) -> dict[str, str]:
        """Cuándo cambió por última vez tu avance, lo visto y tu watchlist (una llamada chica)."""
        return activity_stamps(self._get("/sync/last_activities"))

    def hidden_shows(self) -> set[str]:
        """Las series que escondiste (SS1-A: «Esconder» en el iPhone, «Dejar de seguir» aquí) y las que dejaste en trakt.tv
        («Drop», G1-A): {IMDb}. Algunas rutas de Trakt ya las quitan solas y otras no (/sync/playback, /sync/history), así
        que la consola las quita ella."""
        rows = self._get("/users/hidden/progress_watched", type="show", limit=1000)
        try:
            dropped = self._get("/users/hidden/dropped", type="show", limit=1000)
        except TraktAuthError:
            raise
        except TraktError:  # «dejadas» es extra: sin ella, cuentan las escondidas
            dropped = []
        found = set()
        for row in [*(rows if isinstance(rows, list) else []), *(dropped if isinstance(dropped, list) else [])]:
            imdb = _dict(_dict(_dict(row).get("show")).get("ids")).get("imdb")
            if isinstance(imdb, str) and imdb.startswith("tt"):
                found.add(imdb)
        return found

    def playback_rows(self) -> list[dict]:
        """Todo lo que tienes a medias en Trakt (entre 1 y 79 %), con su nombre, lo más reciente primero."""
        rows = self._get("/sync/playback", extended="full", limit=100)
        found = [r for r in (playback_row(row) for row in rows) if r] if isinstance(rows, list) else []
        return sorted(found, key=lambda r: r["paused_at"], reverse=True)

    def show_progress(self, imdb: str) -> dict | None:
        """Qué episodios de una serie viste y cuál sigue (Trakt acepta el id de IMDb). None si no se entiende."""
        if not isinstance(imdb, str) or not re.fullmatch(r"tt\d+", imdb):
            return None
        return show_progress(self._get(f"/shows/{imdb}/progress/watched", hidden="false", specials="false"))

    def recent_shows(self, limit: int = 15) -> list[dict]:
        """Las últimas series que viste (como entry, lo más reciente primero), para armar «Sigue: T2 E6»."""
        rows = self._get("/sync/history/episodes", limit=100, extended="full")
        shows, seen = [], set()
        for row in rows if isinstance(rows, list) else []:
            show = entry(row.get("show") if isinstance(row, dict) else None, "series")
            if show and show["imdb"] not in seen:
                seen.add(show["imdb"])
                shows.append(show)
                if len(shows) >= limit:
                    break
        return shows

    def watchlist_rows(self) -> list[dict]:
        """Tu watchlist (Mi lista) con cuándo guardaste cada título (`listed_at`, en segundos), lo último primero."""
        rows = self._all_pages("/sync/watchlist", extended="full", sort_by="added", sort_how="desc")
        found, seen = [], set()
        for row in rows if isinstance(rows, list) else []:
            name = str(_dict(row).get("type") or "")
            kind = {"movie": "movie", "show": "series"}.get(name)
            item = entry(_dict(row).get(name), kind) if kind else None
            if item and item["imdb"] not in seen:
                seen.add(item["imdb"])
                found.append({**item, "listed_at": _when(row.get("listed_at")) or 0.0})
        return sorted(found, key=lambda e: e["listed_at"], reverse=True)

    def watched_movies(self) -> dict[str, float]:
        """Las películas que viste y cuándo fue la última vez: {IMDb: segundos}."""
        rows = self._get("/sync/watched/movies")
        found: dict[str, float] = {}
        for row in rows if isinstance(rows, list) else []:
            imdb = _dict(_dict(_dict(row).get("movie")).get("ids")).get("imdb")
            when = _when(_dict(row).get("last_watched_at"))
            if isinstance(imdb, str) and imdb.startswith("tt") and when is not None:
                found[imdb] = when
        return found

    def add_history(self, target: dict, watched_at: float | str | None = None) -> None:
        """Marca visto (una película o un episodio). No es idempotente: dos envíos son dos vistas."""
        self._send("POST", "/sync/history", history_body(target, watched_at))

    def viewed_near(self, target: dict, at: float, window: float = SAME_VIEWING_WINDOW) -> bool:
        """¿Trakt ya tiene una vista de esta película o de este capítulo a menos de `window` s de `at`? La cola lo pregunta
        antes de mandar una vista: si el envío anterior sí llegó pero la respuesta se perdió, ya está y no se repite."""
        if "movie" in target:
            kind, imdb, ep = "movies", _dict(target["movie"].get("ids")).get("imdb"), None
        elif "episode" in target:
            kind, imdb, ep = "episodes", _dict(_dict(target.get("show")).get("ids")).get("imdb"), target["episode"]
        else:
            return False  # la serie completa: no hay una sola vista que buscar
        rows = self._get(f"/sync/history/{kind}", start_at=_iso(at - window), end_at=_iso(at + window), limit=100)
        for raw in rows if isinstance(rows, list) else []:
            row = _dict(raw)
            when = _when(row.get("watched_at"))
            if when is None or abs(when - at) > window:
                continue
            if ep is None:
                if _dict(_dict(row.get("movie")).get("ids")).get("imdb") == imdb:
                    return True
                continue
            got = _dict(row.get("episode"))
            if (_dict(_dict(row.get("show")).get("ids")).get("imdb") == imdb and got.get("season") == ep.get("season")
                    and got.get("number") == ep.get("number")):
                return True
        return False

    def remove_history(self, target: dict) -> None:
        """Lo desmarca (todas las veces que lo viste)."""
        self._send("POST", "/sync/history/remove", history_body(target), idempotent=True)

    def remove_playback(self, playback_id: int) -> None:
        """«Quitar de Seguir viendo»: borra ese avance de Trakt."""
        if not isinstance(playback_id, int):
            raise TraktError("Avance inválido")
        self._send("DELETE", f"/sync/playback/{playback_id}")
        self._playback = None

    def watching(self, limit: int = 12) -> list[dict]:
        """Las series que estás viendo (lo más reciente primero) con el episodio que sigue; las terminadas no."""
        rows = self._get("/sync/history/episodes", limit=100)
        shows, seen = [], set()
        for row in rows if isinstance(rows, list) else []:
            show = entry(row.get("show") if isinstance(row, dict) else None, "series")
            if show and show["imdb"] not in seen and show["trakt_id"]:
                seen.add(show["imdb"])
                shows.append(show)
            if len(shows) >= limit:
                break
        found = []
        for show in shows:
            try:
                progress = self._get(f"/shows/{show['trakt_id']}/progress/watched", hidden="false", specials="false")
            except TraktAuthError:
                raise
            except TraktError:  # una serie que falla no tumba las demás
                continue
            nxt = progress.get("next_episode") if isinstance(progress, dict) else None
            if isinstance(nxt, dict) and isinstance(nxt.get("season"), int) and isinstance(nxt.get("number"), int):
                found.append({**show, "next": {"season": nxt["season"], "episode": nxt["number"]}})
        return found
