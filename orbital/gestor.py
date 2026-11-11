"""El gestor tipo Trakt en la TV (olas 1 y 2, como el iPhone; docs/producto/live-activity-2026-11-08/):

- G1-A: el estado de un título («Mi lista» · «En Mi lista» · «Viendo» · «Vista» · «La dejé»), con las reglas de
  `TitleStatus.swift`. «La dejé» en una serie la esconde en Trakt (también en las «dejadas» de trakt.tv) y la saca de Mi
  lista; en una película la saca de Mi lista y de Seguir viendo.
- G2-A: el tablero de Guardado (En Mi lista · Viendo · Vistas · Las dejé, y «¿Las dejaste?»), como `SavedBoard.swift`.
- G3-A: varios a la vez, un envío por lista. G4-A: tus listas completas (nombre, quién la ve, orden, duplicar, borrar).

Lo que cambia Mi lista o lo dejado pasa por la cola de Trakt (`trakt_outbox.py`): sin internet se queda hecho y se manda
después. Lo de las listas (G4-A) necesita conexión, como en el iPhone.
"""

from __future__ import annotations

import logging
import time
from typing import TYPE_CHECKING

from . import net
from .library import trakt as trakt_api
from .trakt_outbox import HIDDEN, HISTORY, JOURNAL_KEY, NOTE, WATCHLIST, TraktOutbox, retryable

if TYPE_CHECKING:
    from .foryou import ForYou

log = logging.getLogger(__name__)

UNDO_WINDOW = 120  # s: «Deshacer» del aviso de «Vista» quita solo la vista de esa hora (±2 min), como el iPhone
STALE_AFTER = 182 * 24 * 3600  # una serie a medias sin verla en seis meses: «¿Las dejaste?»
STATUSES = ("in_list", "watching", "watched", "dropped")


def title_status(*, series: bool, in_list: bool, watched: int, released: int, upcoming: bool, dropped: bool) -> str:
    """Cómo vas con un título (`TitleStatus.decide` del iPhone): «none», «in_list», «watching», «watched» o «dropped»."""
    if series:
        if dropped:
            return "dropped"
        if watched > 0:
            return "watched" if released > 0 and watched >= released and not upcoming else "watching"
        return "in_list" if in_list else "none"
    if in_list:
        return "in_list"
    return "watched" if watched > 0 else "none"


def moves(kind: str, pile: str) -> list[str]:
    """«Mover a…» desde un montón del tablero (`SavedModel.moves`): «Viendo» es de series que dejaste; «Vista» desde aquí
    es de películas (una serie se marca episodio por episodio en su ficha)."""
    series = kind == "series"
    out = []
    if pile != "in_list":
        out.append("in_list")
    if series and pile == "dropped":
        out.append("watching")
    if not series and pile != "watched":
        out.append("watched")
    if pile != "dropped" and (series or pile == "in_list"):
        out.append("dropped")
    return out


def batch_actions(place: str) -> list[str]:
    """Lo que ofrece la barra de elegir varios en cada lugar (G3-A, `SavedModel.batchActions`)."""
    if place == "watchlist":
        return ["watched", "drop", "move", "remove"]
    if place.startswith("list:"):
        return ["watched", "drop", "move", "to_watchlist", "remove"]
    return {"watching": ["to_watchlist", "drop", "move"], "watched": ["to_watchlist", "move"],
            "dropped": ["resume", "to_watchlist"]}.get(place, [])


def build_board(watchlist: list[dict], watched: dict, dropped: set[str], dropped_names: dict[str, str] | None = None,
                now: float | None = None) -> dict:
    """Los cuatro montones con las reglas de `SavedBoard.build` del iPhone. `watchlist`: entradas de Trakt (lo último
    primero); `watched`: `Trakt.watched_state()`; `dropped`: las series que dejaste."""
    now = time.time() if now is None else now
    movies, shows = watched.get("movies") or {}, watched.get("shows") or {}
    listed = {e["imdb"] for e in watchlist}
    info = {**movies, **shows}
    last = {imdb: (row.get("last") or 0.0) for imdb, row in info.items()}
    in_list = [e for e in watchlist if e["imdb"] not in dropped]

    def entry(imdb: str) -> dict | None:
        found = next((e for e in watchlist if e["imdb"] == imdb), None) or info.get(imdb)
        if found:
            return {k: v for k, v in found.items() if k not in ("last", "fraction", "airing")}
        name = (dropped_names or {}).get(imdb)
        return {"kind": "series", "imdb": imdb, "title": name, "year": None} if name else None

    seen, going = [], []
    for imdb, row in shows.items():
        if imdb in dropped or not row.get("fraction"):
            continue
        (seen if row["fraction"] >= 1 and not row.get("airing") else going).append(imdb)
    seen += [imdb for imdb in movies if imdb not in listed]
    recent = sorted
    old = {imdb for imdb in going if last.get(imdb) and now - last[imdb] > STALE_AFTER}

    def pile(ids) -> list[dict]:
        return [e for e in (entry(i) for i in recent(ids, key=lambda i: -last.get(i, 0.0))) if e]

    return {"in_list": in_list, "watching": pile([i for i in going if i not in old]), "stale": pile(old),
            "watched": pile(seen), "dropped": pile(dropped), "last": {i: t for i, t in last.items() if t}}


class Gestor:
    def __init__(self, foryou: ForYou) -> None:
        self.foryou = foryou
        state = foryou.services.state
        self.outbox = TraktOutbox(lambda: state.settings().get("trakt_outbox"), lambda v: state.set_setting("trakt_outbox", v),
                                  lambda: state.settings().get(JOURNAL_KEY), lambda v: state.set_setting(JOURNAL_KEY, v))
        self.outbox.on_sent = self._sent_from_queue
        net.on_recover(self._trakt_back)

    def _trakt_back(self, host: str) -> None:
        """Trakt vuelve a contestar tras unos fallos (regresó el internet): lo que esperaba sale, en segundo plano."""
        if host == trakt_api.HOST and self.outbox.pending:
            self.outbox.kick(self.trakt)

    def _sent_from_queue(self, targets: set[str]) -> None:
        """Lo que la cola mandó en segundo plano: se olvida lo guardado de esos lugares y la interfaz se entera."""
        keys = {"trakt:watched", "trakt:watched-state"} if HISTORY in targets else set()
        if WATCHLIST in targets:
            keys.add("trakt:watchlist")
        if HIDDEN in targets:
            keys |= {"trakt:hidden", "trakt:calendar", "trakt:watching"}
        keys |= {f"trakt:list:{t}" for t in targets if t.isdigit()}
        self._changed(*sorted(keys))

    # --- de dónde sale cada cosa -------------------------------------------------------------------------------------
    @property
    def trakt(self) -> trakt_api.Trakt:
        return self.foryou.trakt

    @property
    def library(self):
        return getattr(getattr(self.foryou.services, "watch", None), "trakt_library", None)

    def _settings(self) -> dict:
        return self.foryou.services.state.settings()

    def _require(self) -> trakt_api.Trakt:
        if not self.trakt.linked:
            raise trakt_api.TraktAuthError("Conecta Trakt en Ajustes › Cuentas.")
        return self.trakt

    def dropped(self) -> set[str]:
        """Las series que dejaste: las escondidas en Trakt (desde cualquier aparato, o «Drop» en trakt.tv) menos las que solo
        apagaste con la campana aquí (también las oculta allá, pero no las dejaste), más lo que la cola aún no manda."""
        library = self.library
        hidden = set(getattr(library, "hidden", None) or ()) | self._trakt_hidden()
        mine = set(self._settings().get("dropped_shows") or [])
        bell_only = set(self._settings().get("unfollowed_shows") or []) - mine
        found = (hidden - bell_only) | mine
        for imdb, drop in self.outbox.pending_hidden().items():
            (found.add if drop else found.discard)(imdb)
        return found

    def _trakt_hidden(self) -> set[str]:
        """Lo escondido y dejado según Trakt, guardado un rato (la ficha y el tablero no esperan a que Seguir viendo lo lea)."""
        if not self.trakt.linked:
            return set()
        from .foryou import MINE_TTL, SERVICE_ERRORS

        try:
            return set(self.foryou.cache.get("trakt:hidden", MINE_TTL, lambda: sorted(self.trakt.hidden_shows()), stale=True))
        except SERVICE_ERRORS as exc:
            log.info("Trakt: no pude leer lo que dejaste: %s", exc)
            return set()

    def _remember_dropped(self, imdbs: list[str], dropped: bool) -> None:
        self.foryou.cache.clear("trakt:hidden")
        state = self.foryou.services.state
        mine = set(state.settings().get("dropped_shows") or [])
        mine = mine | set(imdbs) if dropped else mine - set(imdbs)
        state.set_setting("dropped_shows", sorted(mine) or None)
        library = self.library
        if library is not None:
            library.forget("hidden")
            if dropped:
                library.hidden.update(imdbs)
            else:
                library.hidden.difference_update(imdbs)

    def _queue(self, items: list[dict]) -> str:
        for item in items:
            self.outbox.enqueue(item)
        self.outbox.kick(self.trakt)
        return "queued"

    def _send(self, item: dict, run) -> str:
        """Lo manda ya; sin internet (o con Trakt caído) lo deja en la cola. «sent» o «queued». Nunca espera a que la cola
        se vacíe (eso va en segundo plano): solo si ese mismo título en ese mismo lugar ya esperaba, va detrás en la cola."""
        if self.outbox.waiting([item]):
            return self._queue([item])
        try:
            run()
        except Exception as exc:
            if not retryable(exc):
                raise
            log.info("Trakt: a la cola (%s): %s", item, exc)
            return self._queue([item])
        self.outbox.kick(self.trakt)  # Trakt contestó: si algo esperaba, ya
        return "sent"

    def _send_many(self, items: list[dict], run) -> str:
        """Como `_send`, con varios en un solo envío: si alguno ya esperaba, todos van a la cola (en orden)."""
        if self.outbox.waiting(items):
            return self._queue(items)
        try:
            run()
        except Exception as exc:
            if not retryable(exc):
                raise
            log.info("Trakt: a la cola (%d): %s", len(items), exc)
            return self._queue(items)
        self.outbox.kick(self.trakt)
        return "sent"

    def _changed(self, *keys: str) -> None:
        for key in keys:
            self.foryou.cache.clear(key)
        library = self.library
        if library is not None:
            library.forget("watchlist")
        self.foryou.publish({"type": "foryou-changed"})

    # --- G1-A: el estado de un título --------------------------------------------------------------------------------
    def state_of(self, imdb: str) -> dict:
        """Lo que la ficha necesita para su botón de estado: si la dejaste y si la campana está prendida."""
        dropped = imdb in self.dropped()
        return {"dropped": dropped, "following": not dropped and imdb not in self.foryou.unfollowed()}

    def set_watchlist(self, items: list[tuple[str, str]], add: bool) -> str:
        """Pone o quita varios ([(kind, imdb)]) de Mi lista, con la cola."""
        self._require()
        clean = [(k, i) for k, i in items if k in trakt_api.KINDS and str(i).startswith("tt")]
        if not clean:
            raise ValueError("Título inválido")
        queued = [{"target": WATCHLIST, "imdb": imdb, "kind": kind, "add": add} for kind, imdb in clean]
        done = self._send_many(queued, lambda: self.trakt.set_items(WATCHLIST, clean, add))
        if self.library is not None:
            for kind, imdb in clean:
                self.library.note_watchlist(kind, imdb, add)
        self._changed("trakt:watchlist")
        return done

    def set_dropped(self, kind: str, imdb: str, dropped: bool, following: bool = False) -> str:
        """«La dejé» (o regresar a «Viendo»). Una serie se esconde en Trakt (Seguir viendo, tus estrenos, los avisos y las
        «dejadas» de trakt.tv) y sale de Mi lista; regresar no prende la campana (`following`). Una película sale de Mi lista
        y de Seguir viendo: Trakt no guarda películas dejadas. Lo visto se queda."""
        self._require()
        if kind == "movie":
            if not dropped:
                return "sent"
            result = self.set_watchlist([(kind, imdb)], False)
            watch = getattr(self.foryou.services, "watch", None)
            if watch is not None:
                try:
                    watch.dismiss_continue(imdb)
                except Exception as exc:  # noqa: BLE001 - lo de Mi lista ya quedó
                    log.info("La dejé: no pude quitarla de Seguir viendo: %s", exc)
            return result
        # Regresar sin la campana: vuelve a Seguir viendo pero sigue fuera de tu calendario (como `unhide(following: false)`).
        sections = trakt_api.DROPPED_SECTIONS if dropped or following else ("progress_watched", "dropped")
        item = {"target": HIDDEN, "imdb": imdb, "kind": "series", "add": dropped, "sections": list(sections)}
        result = self._send(item, lambda: self.trakt.set_hidden([imdb], dropped, sections))
        self._remember_dropped([imdb], dropped)
        bell = set(self._settings().get("unfollowed_shows") or [])
        bell = bell - {imdb} if not dropped and following else bell | {imdb}
        self.foryou.services.state.set_setting("unfollowed_shows", sorted(bell) or None)
        if dropped:
            if self.library is not None and self.library.in_watchlist(imdb):
                self.set_watchlist([("series", imdb)], False)
        self._changed("trakt:calendar", "trakt:watching")
        return result

    # --- G2-A: el tablero -------------------------------------------------------------------------------------------
    def board(self) -> dict:
        """Guardado por estado, con la cifra de cada montón y tus listas abajo."""
        if not self.trakt.linked:
            return {"trakt": False}
        from .foryou import MINE_TTL, video_item

        t = self.trakt
        self.outbox.kick(t)  # lo que esperaba sale en segundo plano; lo pendiente ya se cuenta abajo
        watchlist = list(self.foryou.cache.get("trakt:watchlist", MINE_TTL, t.watchlist))
        pending = self.outbox.pending_in(WATCHLIST)
        watchlist = [e for e in watchlist if pending.get(e["imdb"]) is not False]
        watched = self.foryou.cache.get("trakt:watched-state", MINE_TTL, t.watched_state)
        board = build_board(watchlist, watched, self.dropped(), now=time.time())
        why = {"in_list": "En Mi lista", "watching": "Sigues viéndola", "stale": "¿La dejaste?", "watched": "Vista", "dropped": "La dejaste"}
        out = {name: [{**video_item(e, why[name]), "pile": name} for e in board[name] if e.get("title")] for name in why}
        return {"trakt": True, **out, "last": board["last"], "lists": self.lists()}

    def automatic_changes(self, board: dict) -> list[dict]:
        """Lo que cambió solo desde la última vez que abriste el tablero (`automaticChanges`): algo que pasó a Vistas o una
        vista que regresó a Viendo. Se recuerda el estado de cada título para la próxima."""
        state = self.foryou.services.state
        before = state.settings().get("saved_statuses") or {}
        now: dict[str, str] = {}
        titles: dict[str, str] = {}
        for pile in ("in_list", "watching", "stale", "watched", "dropped"):
            for item in board.get(pile) or []:
                now[item["meta_id"]] = "watching" if pile == "stale" else pile
                titles[item["meta_id"]] = item["title"]
        state.set_setting("saved_statuses", now or None)
        out = []
        for imdb, status in now.items():
            old = before.get(imdb)
            if old is None or old == status or old == "dropped":
                continue
            if status == "watched" or (status == "watching" and old == "watched"):
                out.append({"id": imdb, "title": titles[imdb], "to": status})
        return out

    # --- G3-A: varios a la vez --------------------------------------------------------------------------------------
    def set_many(self, where: str, items: list[tuple[str, str]], add: bool) -> str:
        """Pone o quita varios de Mi lista («watchlist») o de una de tus listas («list:123»): un envío; sin red, a la cola."""
        if where == WATCHLIST:
            return self.set_watchlist(items, add)
        if not where.startswith("list:") or not where[5:].isdigit():
            raise ValueError("¿Guardar dónde?")
        self._require()
        list_id = where[5:]
        clean = [(k, i) for k, i in items if k in trakt_api.KINDS and str(i).startswith("tt")]
        queued = [{"target": list_id, "imdb": imdb, "kind": kind, "add": add} for kind, imdb in clean]
        done = self._send_many(queued, lambda: self.trakt.set_items(list_id, clean, add))
        self._changed(f"trakt:list:{list_id}", "trakt:lists")
        return done

    def drop_many(self, items: list[tuple[str, str]]) -> str:
        """«Las dejé» con varios: las series se esconden en un solo envío por sección; las películas salen de Mi lista."""
        self._require()
        shows = [i for k, i in items if k == "series"]
        movies = [(k, i) for k, i in items if k == "movie"]
        done = "sent"
        if shows:
            sections = trakt_api.DROPPED_SECTIONS
            hidden = [{"target": HIDDEN, "imdb": imdb, "kind": "series", "add": True, "sections": list(sections)} for imdb in shows]
            done = self._send_many(hidden, lambda: self.trakt.set_hidden(shows, True, sections))
            self._remember_dropped(shows, True)
            bell = set(self._settings().get("unfollowed_shows") or []) | set(shows)
            self.foryou.services.state.set_setting("unfollowed_shows", sorted(bell))
        listed = [("series", i) for i in shows if self.library is not None and self.library.in_watchlist(i)] + movies
        if listed and self.set_watchlist(listed, False) == "queued":
            done = "queued"
        self._changed("trakt:calendar", "trakt:watching")
        return done

    def mark_movies_watched(self, imdbs: list[str]) -> None:
        """«Vistas» con varios: solo películas, hoy; salen de Mi lista (Trakt lo hace solo al verlas)."""
        t = self._require()
        for imdb in imdbs:
            t.add_history({"movie": {"ids": {"imdb": imdb}}}, time.time())
        self._changed("trakt:watched", "trakt:watched-state", "trakt:watchlist")

    def unmark_movies_watched(self, imdbs: list[str]) -> None:
        """El «Deshacer» de «Vistas»: salen de lo visto."""
        t = self._require()
        gone = [{"movie": {"ids": {"imdb": imdb}}} for imdb in imdbs]
        # Las «La vi otra vez» que esperaban: si se mandaran después, Trakt la regresaría a vista.
        self.outbox.discard(lambda i: not (i.get("target") == HISTORY and i.get("add") and i.get("video") in gone))
        for target in gone:
            t.remove_history(target)
        self._changed("trakt:watched", "trakt:watched-state")

    # --- G4-A: tus listas (necesita conexión) -----------------------------------------------------------------------
    def lists(self) -> list[dict]:
        if not self.trakt.linked:
            return []
        from .foryou import MINE_TTL

        rows = self.foryou.cache.get("trakt:lists", MINE_TTL, self.trakt.lists, stale=True)
        if any("privacy" not in row for row in rows):  # guardadas en disco antes de G4-A (sin quién la ve ni cuántos)
            self.foryou.cache.clear("trakt:lists")
            rows = self.foryou.cache.get("trakt:lists", MINE_TTL, self.trakt.lists)
        return rows

    def _list_id(self, where: str) -> str:
        if not where.startswith("list:") or not where[5:].isdigit():
            raise ValueError("Lista inválida")
        return where[5:]

    def create_list(self, name: str) -> dict:
        clean = name.strip()
        if not clean:
            raise ValueError("Ponle nombre a la lista")
        made = self._require().create_list(clean[:100])
        self._changed("trakt:lists", "trakt:listkeys")
        return {"id": f"list:{made}", "name": clean[:100]}

    def rename_list(self, where: str, name: str) -> None:
        if not name.strip():
            raise ValueError("Ponle nombre a la lista")
        self._require().update_list(self._list_id(where), name=name)
        self._changed("trakt:lists")

    def set_privacy(self, where: str, privacy: str) -> None:
        if privacy not in trakt_api.PRIVACIES:
            raise ValueError("¿Quién la ve?")
        self._require().update_list(self._list_id(where), privacy=privacy)
        self._changed("trakt:lists")

    def delete_list(self, where: str) -> None:
        list_id = self._list_id(where)
        self._require().delete_list(list_id)
        self.foryou.services.state.set_setting(f"saved_order_{list_id}", None)
        self._changed("trakt:lists", f"trakt:list:{list_id}")

    def duplicate_list(self, where: str, name: str) -> dict:
        made = self._require().duplicate_list(self._list_id(where), name.strip()[:100] or "Copia")
        self._changed("trakt:lists")
        return {"id": f"list:{made}", "name": name.strip()[:100]}

    def reorder(self, where: str, imdbs: list[str]) -> None:
        """«Ordenar a mano»: Mi lista o una de tus listas, en Trakt."""
        target = WATCHLIST if where == WATCHLIST else self._list_id(where)
        self._require().reorder(target, [i for i in imdbs if str(i).startswith("tt")])
        self._changed("trakt:watchlist" if target == WATCHLIST else f"trakt:list:{target}")

    # --- ola 3 (O3-B, 10 nov 2026, como `WatchService+Viewings.swift` y `NotesModel`): corregir lo que viste --------------
    @staticmethod
    def _target(kind: str, imdb: str, video_id: str | None) -> dict:
        found = trakt_api.scrobble_target(kind, imdb, video_id if kind == "series" else imdb)
        if found is None:
            raise ValueError("Título inválido")
        return found

    def _pending_history(self) -> tuple[list[dict], set[int]]:
        """Lo que la cola aún no manda: vistas que entran y los ids que salen."""
        pending = [i for i in self.outbox.pending if i.get("target") == HISTORY]
        adds = [i for i in pending if i.get("add")]
        gone = {n for i in pending if not i.get("add") for n in i.get("ids") or []}
        return adds, gone

    def viewings(self, kind: str, imdb: str, video_id: str | None = None) -> list[dict]:
        """Cada vez que viste esta película o este capítulo, la más nueva primero ({id, at}; id 0: aún en la cola)."""
        return self.viewings_now(kind, imdb, video_id)[0]

    def viewings_now(self, kind: str, imdb: str, video_id: str | None = None) -> tuple[list[dict], bool]:
        """Como `viewings`, y si Trakt no contestó (sin internet): entonces solo lo que espera en la cola, para que «La vi
        otra vez» se pueda usar igual (pasada de pulido, 10 nov 2026)."""
        t = self._require()
        target = self._target(kind, imdb, video_id)
        ep = target.get("episode") or {}
        self.outbox.kick(t)  # lo que esperaba sale en segundo plano; mientras, se muestra desde la cola
        adds, gone = self._pending_history()
        queued = [{"id": 0, "at": i["at"]} for i in adds if i.get("video") == target]
        try:
            remote = [v for v in t.viewings(kind, imdb, ep.get("season"), ep.get("number")) if v["id"] not in gone]
            offline = False
            # La cola pudo haberla mandado mientras se leía: la misma vista no sale dos veces.
            queued = [q for q in queued if not any(abs(r["at"] - q["at"]) <= trakt_api.SAME_VIEWING_WINDOW for r in remote)]
        except trakt_api.TraktAuthError:
            raise
        except trakt_api.TraktError as exc:
            if not retryable(exc):
                raise
            remote, offline = [], True
        return sorted(queued + remote, key=lambda v: -v["at"]), offline

    def _history_send(self, item: dict, run) -> str:
        result = self._send(item, run)
        self._changed("trakt:watched", "trakt:watched-state")
        return result

    @staticmethod
    def _add_key(imdb: str, video_id: str | None, at: float) -> str:
        return f"{video_id or imdb}@{at:.0f}"

    def add_viewing(self, kind: str, imdb: str, video_id: str | None, at: float) -> str:
        """«La vi otra vez» (o la nueva fecha de una vista): una vista más en tu historial."""
        self._require()
        target = self._target(kind, imdb, video_id)
        item = {"target": HISTORY, "imdb": self._add_key(imdb, video_id, at), "kind": kind, "add": True, "video": target, "at": at}
        return self._history_send(item, lambda: self.trakt.add_history(target, at))

    def remove_viewings(self, ids: list[int]) -> str:
        """Borra solo esas vistas (una repetida, las repetidas del historial)."""
        self._require()
        clean = sorted({i for i in ids if isinstance(i, int) and i > 0})
        if not clean:
            return "sent"
        item = {"target": HISTORY, "imdb": "remove:" + ",".join(map(str, clean)), "kind": "movie", "add": False, "ids": clean}
        return self._history_send(item, lambda: self.trakt.remove_viewings(clean))

    def move_viewing(self, viewing_id: int, kind: str, imdb: str, video_id: str | None, at: float) -> str:
        """Cambia la fecha de una vista: la nueva entra primero (si falla, no se pierde nada) y luego sale la vieja."""
        added = self.add_viewing(kind, imdb, video_id, at)  # si Trakt la rechaza, sube el error y la vieja no se toca
        if added == "queued":  # la nueva espera: la vieja sale solo cuando la nueva entre (la cola lo respeta)
            if viewing_id:
                self.outbox.enqueue({"target": HISTORY, "imdb": f"remove:{viewing_id}", "kind": kind, "add": False,
                                     "ids": [viewing_id], "after": self._add_key(imdb, video_id, at)})
            return "queued"
        return self.remove_viewings([viewing_id])

    def undo_viewing(self, kind: str, imdb: str, video_id: str | None, at: float) -> bool:
        """«Deshacer» del aviso de «Vista»: quita solo la vista que se acaba de marcar (la de la hora marcada, ±2 min); las de
        antes se quedan, también una que ya estaba cerca (como el iPhone, 10 nov 2026). Si aún espera en la cola, sale de ahí."""
        target = self._target(kind, imdb, video_id)
        waiting = [i for i in self.outbox.pending if i.get("target") == HISTORY and i.get("add") and i.get("video") == target
                   and abs(i.get("at", 0) - at) <= UNDO_WINDOW]
        if waiting:
            keys = {i["imdb"] for i in waiting}
            self.outbox.discard(lambda i: i.get("imdb") not in keys)
            return True
        found = self.viewings(kind, imdb, video_id)
        mine = min(found, key=lambda v: abs(v["at"] - at), default=None)
        if mine is None or abs(mine["at"] - at) > UNDO_WINDOW or not mine["id"]:
            return False
        self.remove_viewings([mine["id"]])
        return True

    def history(self, page: int = 1) -> dict:
        """Tu historial (de 100 en 100), sin lo que ya borraste aquí, con las vistas repetidas marcadas."""
        _, gone = self._pending_history()
        entries = [e for e in self._require().history(page) if e["id"] not in gone]
        return {"entries": entries, "repeats": sorted(trakt_api.repeats(entries)), "more": len(entries) >= 90}

    # Tu nota: con Trakt VIP vive en Trakt (privada); sin VIP, solo en esta tele (y la hoja lo dice). Como `NotesModel`.
    def vip(self) -> bool | None:
        state = self.foryou.services.state
        try:
            found = self._require().is_vip()
        except trakt_api.TraktAuthError:
            raise
        except trakt_api.TraktError:  # sin red: lo último que se supo
            saved = state.settings().get("trakt_vip")
            return saved if isinstance(saved, bool) else None
        state.set_setting("trakt_vip", found)
        return found

    def _local_notes(self) -> dict:
        found = self._settings().get("notes_local")
        return found if isinstance(found, dict) else {}

    def note(self, kind: str, imdb: str) -> dict:
        """{text, vip}: tu nota de este título y dónde se guarda. Con VIP, las de esta tele pasan solas a Trakt."""
        vip = self.vip()
        pending = next((i for i in reversed(self.outbox.pending) if i.get("target") == NOTE and i.get("imdb") == imdb), None)
        if pending is not None:
            return {"text": pending.get("text") or "", "vip": vip}
        local = self._local_notes()
        if vip:
            notes = self.trakt.my_notes()
            for key, (text, k) in list(local.items()):  # las de la tele, a Trakt
                if key not in notes:
                    self.outbox.enqueue({"target": NOTE, "imdb": key, "kind": k, "text": text, "add": True})
            if local:
                self.foryou.services.state.set_setting("notes_local", None)
                self.outbox.kick(self.trakt)  # salen en segundo plano; la de este título ya se sabe
                if imdb in local and imdb not in notes:
                    return {"text": local[imdb][0], "vip": True}
            return {"text": (notes.get(imdb) or {}).get("text") or "", "vip": True}
        return {"text": (local.get(imdb) or ["", kind])[0], "vip": vip}

    def set_note(self, kind: str, imdb: str, text: str) -> dict:
        """Guarda (o, vacía, borra) tu nota. Con VIP va a Trakt (sin red, espera); sin VIP, a esta tele."""
        if kind not in trakt_api.KINDS or not str(imdb).startswith("tt"):
            raise ValueError("Título inválido")
        clean = text.strip()[:trakt_api.NOTE_LIMIT]
        vip = self.vip()
        if vip:
            existing = (self.trakt.my_notes().get(imdb) or {}).get("id")
            item = {"target": NOTE, "imdb": imdb, "kind": kind, "text": clean, "note_id": existing, "add": True}
            queued = self._send(item, lambda: self.trakt.set_note(kind, imdb, clean, existing)) == "queued"
            return {"vip": True, "queued": queued}
        local = self._local_notes()
        if clean:
            local[imdb] = [clean, kind]
        else:
            local.pop(imdb, None)
        self.foryou.services.state.set_setting("notes_local", local or None)
        return {"vip": vip, "queued": False}

    # Estrellas de temporada (G7-A): 1–5 aquí, el doble en Trakt.
    def season_stars(self, imdb: str, season: int) -> int | None:
        rating = self._require().season_rating(imdb, season)
        return max(1, min(5, round(rating / 2))) if rating else None

    def rate_season(self, imdb: str, season: int, stars: int | None) -> None:
        self._require().set_season_rating(imdb, season, None if stars is None else max(1, min(5, int(stars))) * 2)
