"""La cola de Trakt de la TV (como `TraktOutbox.swift` del iPhone): lo que cambiaste en Mi lista, en tus listas o en las
series que dejaste y Trakt aún no recibió (sin internet, Trakt caído u ocupado). Se guarda en el estado (sobrevive a un
reinicio), lo último que elegiste para un título en un lugar es lo que cuenta y se manda en cuanto se pueda; varios
seguidos a la misma lista van en un solo envío (G3-A, 10 nov 2026).

Un elemento: {"target": «watchlist» | «hidden» | id de una lista, "imdb", "kind", "add", "sections"?}.

También lo que el reproductor no pudo avisarle a Trakt (F4, como WatchService del iPhone): una película o un episodio que
terminaste entra como vista (HISTORY, con la hora en que terminaste) y un avance a medias como PROGRESS (`start` y, 2 s
después, `pause` con ese avance, solo si Trakt no tiene uno más nuevo de otro aparato).

Reglas al vaciarla (como el iPhone, revisión del 11 nov 2026):
- Un elemento que falla de forma reintentable (Trakt 5xx en ese envío) no detiene a los de OTROS títulos; los del mismo
  título o capítulo que vienen detrás esperan con él, para que siempre gane tu última intención (visto → no visto termina
  en «no visto»). Si lo que falla es todo (sin red, sin sesión, «más despacio»), se detiene: los demás fallarían igual.
- Lo que lleva `EXPIRE_DAYS` días sin poder mandarse vence.
- Cada descarte (definitivo o vencido) queda en una bitácora (`discarded()`, en /api/diagnostics como `trakt_queue`).
"""

from __future__ import annotations

import logging
import threading
import time
from collections.abc import Callable

from .library import trakt as trakt_api
from .net import NET_FAILURES

log = logging.getLogger(__name__)

KEY = "trakt_outbox"
WATCHLIST, HIDDEN = "watchlist", "hidden"
# Ola 3 (O3-B): una vista que entra o las que salen de tu historial (`imdb` es su llave única: título y momento, o los ids)
# y tu nota con VIP. Cada una va sola, no en lote.
HISTORY, NOTE = "history", "note"
PROGRESS = "progress"  # un avance del reproductor que Trakt no recibió (`imdb` es la llave del video: tt1 o tt1:2:5)
SINGLE = (HIDDEN, HISTORY, NOTE, PROGRESS)
PROGRESS_GAP = 2.0  # s entre el `start` y la `pause` (Trakt los ordena por hora), como el respaldo de scrobble.py
EXPIRE_DAYS = 30  # como el iPhone: lo que no se pudo mandar en un mes ya no se manda
JOURNAL_KEY = "trakt_outbox_log"
JOURNAL_SIZE = 100  # descartes que se recuerdan


def retryable(exc: BaseException) -> bool:
    """¿Vale la pena guardarlo para después? Sin red, sin sesión ahora o Trakt ocupado/caído: sí. Un título inválido, una
    lista que ya no existe (un 4xx definitivo) o un error de programación: no (reintentarlo no lo arregla, y si se quedara
    atoraría la cola para siempre)."""
    if isinstance(exc, trakt_api.TraktAuthError):
        return True
    if isinstance(exc, trakt_api.TraktError):
        status = exc.status
        return status is None and str(exc).startswith("No pude conectar") or status in (401, 408, 429) or (status or 0) >= 500
    return isinstance(exc, NET_FAILURES)  # la red, aunque no venga envuelta como TraktError


def stops_everything(exc: BaseException) -> bool:
    """¿El fallo es de todo Trakt (sin red, sin sesión, «más despacio») y no de ese envío? Entonces no se sigue con los
    demás: fallarían igual (y sin red cada uno esperaría su plazo)."""
    if isinstance(exc, trakt_api.TraktAuthError) or isinstance(exc, NET_FAILURES):
        return True
    if isinstance(exc, trakt_api.TraktError):
        return exc.status in (401, 429) or exc.status is None
    return False


def title_key(item: dict) -> str:
    """El título o capítulo de un elemento: «tt1» o «tt1:2:5» (sin la hora de una vista). Entre los del mismo título se
    respeta el orden. Una vista que sale por id va con la que la reemplaza (`after`), si la hay."""
    if item.get("target") == HISTORY and not item.get("add") and item.get("after"):
        return str(item["after"]).split("@")[0]
    return str(item.get("imdb") or "").split("@")[0]


class TraktOutbox:
    def __init__(self, load: Callable[[], list | None], save: Callable[[list | None], None],
                 journal_load: Callable[[], list | None] | None = None,
                 journal_save: Callable[[list | None], None] | None = None) -> None:
        self._load, self._save = load, save
        memory: dict = {}
        self._journal_load = journal_load or (lambda: memory.get("v"))
        self._journal_save = journal_save or (lambda v: memory.__setitem__("v", v))
        self.clock: Callable[[], float] = time.time
        self._lock = threading.Lock()
        self._flush_lock = threading.Lock()  # un vaciado a la vez; el segundo espera y encuentra lo que quedó
        self._worker: threading.Thread | None = None  # el único hilo que vacía la cola en segundo plano
        self._again = False  # llegó otro aviso mientras vaciaba: una vuelta más
        self.sleep: Callable[[float], None] = time.sleep
        self.on_sent: Callable[[set[str]], None] | None = None  # lo que salió (sus destinos): el gestor relee lo suyo

    @property
    def pending(self) -> list[dict]:
        with self._lock:
            return [dict(i) for i in self._load() or [] if isinstance(i, dict) and "target" in i and "imdb" in i]

    def enqueue(self, item: dict) -> None:
        item = {**item, "queued_at": item.get("queued_at") or self.clock()}
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

    def discarded(self) -> list[dict]:
        """La bitácora de lo que salió de la cola sin mandarse, lo más nuevo al final: {at, why («rechazado» o «vencido»),
        reason, target, imdb, kind}."""
        with self._lock:
            return [dict(e) for e in self._journal_load() or [] if isinstance(e, dict)]

    def _note_discard(self, items: list[dict], why: str, reason: str) -> None:
        now = self.clock()
        rows = [{"at": now, "why": why, "reason": reason[:200], "target": i.get("target"), "imdb": i.get("imdb"),
                 "kind": i.get("kind")} for i in items]
        with self._lock:
            journal = [e for e in self._journal_load() or [] if isinstance(e, dict)]
            self._journal_save((journal + rows)[-JOURNAL_SIZE:])

    def _expire(self) -> None:
        """Pone la hora a lo que no la tenía (de antes de esta regla) y saca lo que ya venció."""
        now = self.clock()
        with self._lock:
            items = [i for i in self._load() or [] if isinstance(i, dict)]
            stamped = [i if isinstance(i.get("queued_at"), (int, float)) else {**i, "queued_at": now} for i in items]
            old = [i for i in stamped if now - i["queued_at"] > EXPIRE_DAYS * 86400]
            keep = [i for i in stamped if i not in old]
            if old or stamped != items:
                self._save(keep or None)
        if old:
            log.warning("Trakt: vencieron %d de la cola (más de %d días sin poder mandarse): %s", len(old), EXPIRE_DAYS,
                        [i.get("imdb") for i in old])
            self._note_discard(old, "vencido", f"Más de {EXPIRE_DAYS} días sin poder mandarse")

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

    def _send_viewing(self, t: trakt_api.Trakt, item: dict) -> None:
        """Una vista que espera. Antes se pregunta a Trakt si ya la tiene (±10 min): el envío anterior pudo haber llegado
        aunque la respuesta se perdiera (el `stop` del reproductor o «La vi otra vez» sin respuesta), y mandarla otra vez
        la dejaría doble en tu historial. Si la pregunta falla por la red, la vista sigue esperando: nunca se pierde."""
        at = item.get("at")
        check = getattr(t, "viewed_near", None)
        if isinstance(at, (int, float)) and callable(check):
            try:
                found = check(item["video"], float(at))
            except Exception as exc:  # noqa: BLE001 - sin red espera; una respuesta rara no deja la vista sin mandar
                if retryable(exc):
                    raise
                log.info("Trakt: no pude revisar si %s ya estaba (%s); la mando", item["imdb"], exc)
                found = False
            if found:
                log.info("Trakt: %s ya estaba en tu historial; no la mando otra vez", item["imdb"])
                return
        t.add_history(item["video"], at)

    def waiting(self, items: list[dict]) -> bool:
        """¿Algo de esto (mismo lugar y mismo título) ya espera en la cola? Entonces lo nuevo va a la cola detrás de lo viejo
        (lo reemplaza) en vez de mandarse directo: si saliera ya y después lo viejo, Trakt se quedaría con lo viejo."""
        keys = {(i.get("target"), i.get("imdb")) for i in items}
        return any((p.get("target"), p.get("imdb")) in keys for p in self.pending)

    def kick(self, t: trakt_api.Trakt | None) -> bool:
        """Vacía la cola en segundo plano, sin hacer esperar a nadie: un solo hilo a la vez (si ya hay uno, da una vuelta
        más al terminar). Se llama tras cada acción y cuando Trakt vuelve a contestar. True si arrancó un hilo."""
        if t is None or not getattr(t, "linked", False):
            return False
        with self._lock:
            if self._worker is not None:
                self._again = True
                return False
            if not [i for i in self._load() or [] if isinstance(i, dict)]:
                return False
            self._again = False
            self._worker = threading.Thread(target=self._run, args=(t,), name="trakt-outbox", daemon=True)
            worker = self._worker
        worker.start()
        return True

    def _run(self, t: trakt_api.Trakt) -> None:
        while True:
            try:
                self.flush(t)
            except Exception:  # noqa: BLE001 - el hilo de la cola nunca se cae
                log.exception("Trakt: no pude vaciar la cola")
            with self._lock:
                if not self._again:
                    self._worker = None
                    return
                self._again = False

    def idle(self, timeout: float = 10.0) -> bool:
        """Espera a que el hilo de la cola termine (pruebas y apagado). True si ya no hay ninguno."""
        with self._lock:
            worker = self._worker
        if worker is not None:
            worker.join(timeout)
        with self._lock:
            return self._worker is None

    def flush(self, t: trakt_api.Trakt | None) -> int:
        """Manda lo pendiente, en orden. Se detiene al primer error que se puede reintentar; lo que no se puede (lista
        borrada, título inválido) se descarta. Si otro vaciado está en curso, espera a que acabe y sigue con lo que quedó.
        Nadie que espera una respuesta lo llama: las acciones usan `kick` (en segundo plano)."""
        if t is None or not getattr(t, "linked", False):
            return 0
        with self._flush_lock:
            return self._flush(t)

    def _flush(self, t: trakt_api.Trakt) -> int:
        self._expire()
        sent = 0
        targets: set[str] = set()
        failed: set[str] = set()  # lo que Trakt rechazó: lo que dependía de eso ya no se manda
        blocked: set[str] = set()  # títulos que esperan (falló uno de ellos): lo suyo que viene detrás, también
        queue = [i for i in self.pending if title_key(i) not in blocked]
        while queue:
            item = queue[0]
            run = [item]
            if item["target"] not in SINGLE:
                for nxt in queue[1:]:
                    if nxt["target"] != item["target"] or nxt.get("add") != item.get("add"):
                        break
                    run.append(nxt)
            queue = queue[len(run):]
            if item.get("after") in failed:  # la vieja de una fecha cambiada: la nueva no entró, así que se queda
                log.info("Trakt: la nueva no entró; dejo la vista vieja (%s)", item)
                self._drop(run)
                continue
            try:
                if item["target"] == HIDDEN:
                    t.set_hidden([item["imdb"]], bool(item.get("add")), tuple(item.get("sections") or trakt_api.HIDDEN_SECTIONS))
                elif item["target"] == HISTORY:  # ola 3: una vista que entra (con su fecha) o las que salen (por id)
                    if item.get("add"):
                        self._send_viewing(t, item)
                    else:
                        t.remove_viewings(item.get("ids") or [])
                elif item["target"] == NOTE:
                    t.set_note(item["kind"], item["imdb"], item.get("text") or "", item.get("note_id"))
                elif item["target"] == PROGRESS:
                    self._send_progress(t, item)
                else:
                    t.set_items(item["target"], [(i["kind"], i["imdb"]) for i in run], bool(item.get("add")))
                sent += len(run)
                targets.add(str(item["target"]))
            except Exception as exc:  # noqa: BLE001 - lo que no se puede reintentar se descarta; lo demás espera
                if retryable(exc):
                    if stops_everything(exc):
                        log.info("Trakt: la cola espera (%s)", exc)
                        break
                    # Solo este envío falló: espera él (y lo de su título), los demás siguen.
                    log.info("Trakt: %s espera (%s); sigo con lo demás", [i["imdb"] for i in run], exc)
                    blocked.update(title_key(i) for i in run)
                    queue = [i for i in queue if title_key(i) not in blocked]
                    continue
                # Un 4xx definitivo o un error de programación: sale de la fila (y a la bitácora) y lo demás sigue en
                # su orden; si se quedara, atoraría la cola para siempre.
                log.warning("Trakt: descarto %s de la cola: %s", item, exc,
                            exc_info=not isinstance(exc, trakt_api.TraktError))
                self._note_discard(run, "rechazado", str(exc) or type(exc).__name__)
                failed.update(i["imdb"] for i in run)
            self._drop(run)
        if sent and self.on_sent is not None:
            try:
                self.on_sent(targets)
            except Exception:  # noqa: BLE001
                log.exception("Trakt: no pude avisar lo que salió de la cola")
        return sent
