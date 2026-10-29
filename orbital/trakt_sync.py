"""Trakt como la fuente de «lo tuyo» en la consola: Seguir viendo, Mi lista y lo visto (desacoplar Stremio, corte E).

El iPhone y la consola se pasan por Trakt dónde ibas, qué viste y qué guardaste. Aquí la consola lee eso y lo une con
la biblioteca de Stremio, que sigue de respaldo mientras dura la prueba (docs/producto/desacoplar-stremio/):

  - Seguir viendo: lo que tienes a medias en Trakt (/sync/playback) y el episodio que sigue de tus series
    (/shows/{id}/progress/watched). Por título gana lo más reciente entre Trakt y Stremio.
  - Lo terminado en otro aparato sale de Seguir viendo (una película vista, una serie al día sin episodio nuevo).
  - Mi lista: tu watchlist de Trakt. Lo que solo estaba en la biblioteca de Stremio ya no cuenta (decisión de Fernando).

Para no gastar llamadas, primero se pregunta /sync/last_activities (una llamada chica) y solo se baja lo que cambió.
Los elementos conservan el id «stremio:tt…» y la fuente «stremio»: así los llaman las preferencias, la voz y la
interfaz desde antes (es «tu biblioteca de videos», no la cuenta de Stremio).
"""

from __future__ import annotations

import logging
import threading
import time
from collections.abc import Callable
from concurrent.futures import ThreadPoolExecutor
from dataclasses import replace

from .library import stremio_api
from .library import trakt as trakt_api
from .library.models import LibraryItem

log = logging.getLogger(__name__)

CHECK_EVERY = 60  # s: cada cuánto se pregunta a Trakt si cambió algo (se pregunta al abrir Inicio, no hay sondeo aparte)
SHOWS = 15  # las últimas series que viste: de ellas sale «Sigue: T2 E6»
PARTS = ("paused", "watched", "watchlist")


def _time_left(seconds: float) -> str:
    from .watch import time_left  # watch.py importa este módulo: se pide al usarlo

    return time_left(seconds)


def _detail(kind: str, video_id: str) -> tuple[str, bool]:
    """«T2 E5» (episodio) o «Película»; y si es un episodio."""
    parts = video_id.split(":")
    if kind == "series" and len(parts) == 3 and parts[1].isdigit() and parts[2].isdigit():
        return f"T{int(parts[1])} E{int(parts[2])}", True
    return ("Película" if kind == "movie" else "Serie"), False


def continue_item(base: LibraryItem | None, *, kind: str, meta_id: str, video_id: str, title: str, when: float,
                  percent: float | None, runtime: float | None) -> LibraryItem:
    """Un título en Seguir viendo con lo que dice Trakt: a medias (`percent`) o el episodio que sigue (`percent` None).
    `base`: lo que ya había de ese título (la biblioteca de Stremio), para conservar su arte y sus datos."""
    detail, episode = _detail(kind, video_id)
    progress = percent / 100 if percent is not None else None
    left = runtime * (1 - progress) if runtime and progress is not None else 0
    subtitle = f"Sigue: {detail}" if progress is None and episode else " · ".join(filter(None, [detail, _time_left(left)]))
    eyebrow = " · ".join(filter(None, ["Película" if kind == "movie" else "Serie", detail if episode else ""]))
    extra = {**(base.extra if base else {}), "kind": kind, "meta_id": meta_id, "video_id": video_id,
             "left": round(left) if left >= 60 else None, "eyebrow": eyebrow, "from_trakt": True}
    extra.pop("new_episode", None)
    if base is None or base.extra.get("video_id") != video_id:
        extra.pop("episode_title", None)  # era de otro episodio: Cinemeta lo vuelve a poner
    if base is not None:
        return replace(base, category="continue", subtitle=subtitle, progress=progress, last_watched=when,
                       uri=f"stremio:///detail/{kind}/{meta_id}/{video_id}?autoPlay=true", extra=extra)
    return LibraryItem(id=f"stremio:{meta_id}", title=title, category="continue", source="stremio", subtitle=subtitle,
                       image=stremio_api.METAHUB_POSTER.format(id=meta_id),
                       hero=stremio_api.METAHUB_BACKGROUND.format(id=meta_id),
                       uri=f"stremio:///detail/{kind}/{meta_id}/{video_id}?autoPlay=true", progress=progress,
                       last_watched=when, extra=extra)


def list_item(entry: dict) -> LibraryItem:
    """Un título de tu watchlist que no estaba en la biblioteca: solo para la fila Mi lista."""
    kind, meta_id = entry["kind"], entry["imdb"]
    return LibraryItem(id=f"stremio:{meta_id}", title=entry["title"], category="stremio", source="stremio",
                       subtitle="Película" if kind == "movie" else "Serie",
                       image=stremio_api.METAHUB_POSTER.format(id=meta_id),
                       hero=stremio_api.METAHUB_BACKGROUND.format(id=meta_id),
                       uri=f"stremio:///detail/{kind}/{meta_id}",
                       extra={"kind": kind, "meta_id": meta_id, "video_id": meta_id if kind == "movie" else None,
                              "in_library": True, "listed_at": entry.get("listed_at") or 0.0, "from_trakt": True,
                              "eyebrow": "Película" if kind == "movie" else "Serie"})


def merge(items: list[LibraryItem], playback: list[dict], shows: dict[str, dict], movies: dict[str, float],
          watchlist: list[dict] | None, dismissed: Callable[[str], float | None] = lambda imdb: None) -> list[LibraryItem]:
    """La biblioteca de Stremio (`items`) unida con lo de Trakt. No toca `items`: devuelve otra lista.

    `playback`: lo que tienes a medias (Trakt.playback_rows). `shows`: {IMDb: serie + show_progress}. `movies`: películas
    vistas {IMDb: cuándo}. `watchlist`: Trakt.watchlist_rows, o None si no se sabe (entonces Mi lista se queda como está).
    `dismissed`: cuándo lo quitaste de Seguir viendo en la consola (lo de antes de eso no lo regresa).
    """
    out = [replace(i, extra=dict(i.extra)) for i in items]
    where = {i.extra.get("meta_id"): n for n, i in enumerate(out) if i.extra.get("meta_id")}

    # Lo más reciente de Trakt por título: a medias, o el episodio que sigue de una serie.
    best: dict[str, dict] = {}
    for row in playback:
        if row["meta_id"] not in best or row["paused_at"] > best[row["meta_id"]]["when"]:
            best[row["meta_id"]] = {**row, "when": row["paused_at"]}
    for imdb, show in shows.items():
        when, nxt = show.get("last_watched"), show.get("next")
        if when is None or (imdb in best and best[imdb]["when"] >= when):
            continue  # lo que dejaste a medias es más nuevo que el último episodio terminado
        best[imdb] = {"kind": "series", "meta_id": imdb, "title": show.get("title") or imdb, "when": when, "percent": None,
                      "runtime": None, "video_id": f"{imdb}:{nxt[0]}:{nxt[1]}" if nxt else None}

    for imdb, found in best.items():
        if (dismissed(imdb) or 0) >= found["when"]:
            continue
        n = where.get(imdb)
        base = out[n] if n is not None else None
        if base is not None and base.category == "continue" and (base.last_watched or 0) >= found["when"]:
            continue  # Stremio sabe algo más nuevo (lo viste en la consola después)
        if found["video_id"] is None:  # serie al día, sin episodio que siga: fuera de Seguir viendo
            if n is not None and out[n].category == "continue":
                out[n] = replace(out[n], category="stremio")
            continue
        item = continue_item(base, kind=found["kind"], meta_id=imdb, video_id=found["video_id"], title=found["title"],
                             when=found["when"], percent=found["percent"], runtime=found.get("runtime"))
        if n is None:
            where[imdb] = len(out)
            out.append(item)
        else:
            out[n] = item

    # Una película que terminaste en otro aparato después de lo que dice Stremio ya no está a medias.
    for n, item in enumerate(out):
        imdb = item.extra.get("meta_id")
        if item.category == "continue" and item.extra.get("kind") == "movie" and imdb in movies \
                and movies[imdb] > (item.last_watched or 0) and imdb not in best:
            out[n] = replace(item, category="stremio")

    if watchlist is not None:
        listed = {e["imdb"]: e for e in watchlist}
        for item in out:
            imdb = item.extra.get("meta_id")
            item.extra["in_library"] = imdb in listed
            if imdb in listed:
                item.extra["listed_at"] = listed[imdb].get("listed_at") or 0.0
        for imdb, e in listed.items():
            if imdb not in where:
                where[imdb] = len(out)
                out.append(list_item(e))
    return out


class TraktLibrary:
    """Lo tuyo en Trakt, guardado en memoria y al día con /sync/last_activities."""

    def __init__(self, trakt: Callable[[], trakt_api.Trakt | None] | None = None, clock: Callable[[], float] = time.time) -> None:
        self.trakt = trakt or (lambda: None)  # se pide cada vez: las claves de Trakt pueden cambiar
        self.clock = clock
        self._lock = threading.Lock()
        self.playback: list[dict] = []
        self.shows: dict[str, dict] = {}
        self.movies: dict[str, float] = {}
        self.watchlist: list[dict] | None = None
        self._stamps: dict[str, str] = {}
        self._checked = 0.0
        self.error: str | None = None
        self.dismissed: Callable[[str], float | None] = lambda imdb: None  # watch.py: «Quitar de Seguir viendo»

    def client(self) -> trakt_api.Trakt | None:
        try:
            t = self.trakt()
        except Exception:  # noqa: BLE001 - Para ti aún no existe
            return None
        return t if t is not None and getattr(t, "linked", False) else None

    @property
    def active(self) -> bool:
        return self.client() is not None

    def stale(self) -> bool:
        return self.clock() - self._checked >= CHECK_EVERY

    def snapshot(self) -> tuple[list[dict], dict[str, dict], dict[str, float], list[dict] | None]:
        with self._lock:
            return list(self.playback), dict(self.shows), dict(self.movies), self.watchlist

    def merged(self, items: list[LibraryItem]) -> list[LibraryItem]:
        if not self.active:
            return items
        return merge(items, *self.snapshot(), dismissed=self.dismissed)

    def refresh(self, force: bool = False) -> bool:
        """Pregunta a Trakt qué cambió y baja solo eso. True si algo cambió (hay que volver a armar la biblioteca)."""
        self._checked = self.clock()
        t = self.client()
        if t is None:
            with self._lock:
                had = bool(self.playback or self.shows or self.movies or self.watchlist is not None)
                self.playback, self.shows, self.movies, self.watchlist, self._stamps = [], {}, {}, None, {}
            return had
        try:
            stamps = t.last_activities()
        except trakt_api.TraktError as exc:
            self.error = str(exc)
            log.info("Trakt: no pude ver qué cambió: %s", exc)
            return False
        loaders = {"paused": self._load_playback, "watched": self._load_watched, "watchlist": self._load_watchlist}
        changed = False
        for part in PARTS:
            if not force and part in self._stamps and self._stamps[part] == stamps.get(part):
                continue
            try:
                loaders[part](t)
            except trakt_api.TraktError as exc:  # esa parte se reintenta la próxima vez; lo demás sí se actualiza
                self.error = str(exc)
                log.info("Trakt: no pude leer %s: %s", part, exc)
                continue
            self._stamps[part] = stamps.get(part, "")
            changed = True
        if changed:
            self.error = None
        return changed

    def forget(self, part: str = "paused") -> None:
        """Algo cambió desde aquí (pausaste, guardaste): la próxima vez se baja aunque la marca parezca igual."""
        self._stamps.pop(part, None)
        self._checked = 0.0

    def _load_playback(self, t: trakt_api.Trakt) -> None:
        rows = t.playback_rows()
        with self._lock:
            self.playback = rows

    def _load_watchlist(self, t: trakt_api.Trakt) -> None:
        rows = t.watchlist_rows()
        with self._lock:
            self.watchlist = rows

    def _load_watched(self, t: trakt_api.Trakt) -> None:
        movies = t.watched_movies()
        recent = t.recent_shows(SHOWS)

        def progress(show: dict) -> tuple[dict, dict | None]:
            try:
                return show, t.show_progress(show["imdb"])
            except trakt_api.TraktAuthError:
                raise
            except trakt_api.TraktError:  # una serie que falla no tumba las demás
                return show, None

        shows: dict[str, dict] = {}
        with ThreadPoolExecutor(max_workers=4) as pool:
            for show, found in pool.map(progress, recent):
                if found:
                    shows[show["imdb"]] = {**show, **found}
        with self._lock:
            self.movies, self.shows = movies, shows

    def watched_episodes(self, imdb: str) -> tuple[set[str], tuple[str, float] | None]:
        """Para la ficha de una serie: los episodios vistos («tt…:2:5») y el que sigue con cuándo viste el último
        (None si no hay). Pregunta a Trakt en el momento (la ficha puede ser de una serie que no está entre las últimas)."""
        t = self.client()
        if t is None:
            return set(), None
        found = self.shows.get(imdb) or t.show_progress(imdb)
        if not found:
            return set(), None
        watched = {f"{imdb}:{s}:{e}" for s, e in found.get("watched") or set()}
        nxt, when = found.get("next"), found.get("last_watched")
        return watched, ((f"{imdb}:{nxt[0]}:{nxt[1]}", when) if nxt and when is not None else None)

    def in_watchlist(self, imdb: str) -> bool | None:
        """¿Está en tu watchlist? None si no se sabe (sin Trakt o aún sin leer)."""
        if not self.active or self.watchlist is None:
            return None
        return any(e["imdb"] == imdb for e in self.watchlist)
