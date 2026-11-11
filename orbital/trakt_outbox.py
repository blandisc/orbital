"""La cola de Trakt de la TV (como `TraktOutbox.swift` del iPhone): lo que cambiaste en Mi lista, en tus listas o en las
series que dejaste y Trakt aún no recibió (sin internet, Trakt caído u ocupado). Se guarda en el estado (sobrevive a un
reinicio), lo último que elegiste para un título en un lugar es lo que cuenta y se manda en cuanto se pueda; varios
seguidos a la misma lista van en un solo envío (G3-A, 10 nov 2026).

Un elemento: {"target": «watchlist» | «hidden» | id de una lista, "imdb", "kind", "add", "sections"?}.

También lo que el reproductor no pudo avisarle a Trakt (F4, como WatchService del iPhone): una película o un episodio que
terminaste entra como vista (HISTORY, con la hora en que terminaste) y un avance a medias como PROGRESS (`start` y, 2 s
después, `pause` con ese avance, solo si Trakt no tiene uno más nuevo de otro aparato).
"""

from __future__ import annotations

import logging
import threading
import time
from collections.abc import Callable

from .library import trakt as trakt_api

log = logging.getLogger(__name__)

KEY = "trakt_outbox"
WATCHLIST, HIDDEN = "watchlist", "hidden"
# Ola 3 (O3-B): una vista que entra o las que salen de tu historial (`imdb` es su llave única: título y momento, o los ids)
# y tu nota con VIP. Cada una va sola, no en lote.
HISTORY, NOTE = "history", "note"
PROGRESS = "progress"  # un avance del reproductor que Trakt no recibió (`imdb` es la llave del video: tt1 o tt1:2:5)
SINGLE = (HIDDEN, HISTORY, NOTE, PROGRESS)
PROGRESS_GAP = 2.0  # s entre el `start` y la `pause` (Trakt los ordena por hora), como el respaldo de scrobble.py


def retryable(exc: Exception) -> bool:
    """¿Vale la pena guardarlo para después? Sin red, sin sesión ahora o Trakt ocupado/caído: sí. Un título inválido o una
    lista que ya no existe: no (reintentarlo no lo arregla)."""
    if isinstance(exc, trakt_api.TraktAuthError):
        return True
    if isinstance(exc, trakt_api.TraktError):
        status = exc.status
        return status is None and str(exc).startswith("No pude conectar") or status in (401, 408, 429) or (status or 0) >= 500
    return True


class TraktOutbox:
    def __init__(self, load: Callable[[], list | None], save: Callable[[list | None], None]) -> None:
        self._load, self._save = load, save
        self._lock = threading.Lock()
        self._flushing = False
        self.sleep: Callable[[float], None] = time.sleep

    @property
    def pending(self) -> list[dict]:
        with self._lock:
            return [dict(i) for i in self._load() or [] if isinstance(i, dict)]

    def enqueue(self, item: dict) -> None:
        with self._lock:
            items = [i for i in self._load() or [] if isinstance(i, dict)
                     and not (i.get("target") == item["target"] and i.get("imdb") == item["imdb"])]
            self._save([*items, item])

    def pending_hidden(self) -> dict[str, bool]:
        """Las series que dejaste (o volviste a ver) y Trakt aún no sabe: IMDb → dejada. Lo que diga Trakt no las pisa."""
        return {i["imdb"]: bool(i.get("add")) for i in self.pending if i.get("target") == HIDDEN}

    def pending_in(self, target: str) -> dict[str, bool]:
        """Lo pendiente en Mi lista o en una lista: IMDb → entra (True) o sale (False)."""
        return {i["imdb"]: bool(i.get("add")) for i in self.pending if i.get("target") == target}

    def discard(self, keep) -> None:
        """Quita de la cola lo que ya no debe mandarse (`keep(item)` False): «Quitar de vistas» limpia las «La vi otra vez»
        que esperaban, o Trakt las regresaría."""
        with self._lock:
            items = [i for i in self._load() or [] if not isinstance(i, dict) or keep(i)]
            self._save(items or None)

    def _drop(self, done: list[dict]) -> None:
        with self._lock:
            items = [i for i in self._load() or [] if i not in done]
            self._save(items or None)

    def _send_progress(self, t: trakt_api.Trakt, item: dict) -> None:
        """El avance que quedó pendiente, salvo que Trakt ya tenga uno más nuevo (lo viste en otro aparato después)."""
        playback = getattr(t, "playback", None)
        rows = playback() if callable(playback) else None
        newer = (rows.get(item["imdb"]) or {}).get("paused_at") if isinstance(rows, dict) else None
        if isinstance(newer, (int, float)) and newer >= float(item.get("at") or 0):
            log.info("Trakt: ya tiene un avance más nuevo de %s; no mando el viejo", item["imdb"])
            return
        progress = float(item.get("progress") or 0)
        t.scrobble("start", item["video"], progress)
        self.sleep(PROGRESS_GAP)
        t.scrobble("pause", item["video"], progress)
        if hasattr(t, "forget_playback"):
            t.forget_playback()

    def flush(self, t: trakt_api.Trakt | None) -> int:
        """Manda lo pendiente, en orden. Se detiene al primer error que se puede reintentar; lo que no se puede (lista
        borrada, título inválido) se descarta."""
        if t is None or not getattr(t, "linked", False):
            return 0
        with self._lock:
            if self._flushing:
                return 0
            self._flushing = True
        sent = 0
        failed: set[str] = set()  # lo que Trakt rechazó: lo que dependía de eso ya no se manda
        try:
            queue = self.pending
            while queue:
                item = queue[0]
                run = [item]
                if item["target"] not in SINGLE:
                    for nxt in queue[1:]:
                        if nxt["target"] != item["target"] or nxt.get("add") != item.get("add"):
                            break
                        run.append(nxt)
                if item.get("after") in failed:  # la vieja de una fecha cambiada: la nueva no entró, así que se queda
                    log.info("Trakt: la nueva no entró; dejo la vista vieja (%s)", item)
                    self._drop(run)
                    queue = queue[len(run):]
                    continue
                try:
                    if item["target"] == HIDDEN:
                        t.set_hidden([item["imdb"]], bool(item.get("add")), tuple(item.get("sections") or trakt_api.HIDDEN_SECTIONS))
                    elif item["target"] == HISTORY:  # ola 3: una vista que entra (con su fecha) o las que salen (por id)
                        if item.get("add"):
                            t.add_history(item["video"], item["at"])
                        else:
                            t.remove_viewings(item.get("ids") or [])
                    elif item["target"] == NOTE:
                        t.set_note(item["kind"], item["imdb"], item.get("text") or "", item.get("note_id"))
                    elif item["target"] == PROGRESS:
                        self._send_progress(t, item)
                    else:
                        t.set_items(item["target"], [(i["kind"], i["imdb"]) for i in run], bool(item.get("add")))
                    sent += len(run)
                except Exception as exc:  # noqa: BLE001 - lo que no se puede reintentar se descarta; lo demás espera
                    if retryable(exc):
                        log.info("Trakt: la cola espera (%s)", exc)
                        break
                    log.info("Trakt: descarto %s de la cola: %s", item, exc)
                    failed.update(i["imdb"] for i in run)
                self._drop(run)
                queue = queue[len(run):]
        finally:
            with self._lock:
                self._flushing = False
        return sent
