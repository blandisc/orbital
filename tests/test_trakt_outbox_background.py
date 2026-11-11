"""La cola de Trakt no frena lo que haces (revisión del 11 nov 2026): se vacía en segundo plano, con un solo hilo, y lo que
nunca va a funcionar sale de la fila sin atorarla.

Un Trakt falso lento (cada envío tarda) y una cola larga, como tras un rato sin internet."""

from __future__ import annotations

import logging
import threading
import time
from types import SimpleNamespace

import pytest

from orbital import net
from orbital.gestor import Gestor
from orbital.library import trakt
from orbital.trakt_outbox import HISTORY, NOTE, WATCHLIST, TraktOutbox, retryable


class SlowTrakt:
    """Trakt que tarda `delay` s por envío y recuerda en qué orden llegó cada cosa (y cuántos hilos a la vez)."""

    linked = True

    def __init__(self, delay: float = 0.0) -> None:
        self.delay = delay
        self.sent: list[tuple] = []
        self.down = False
        self.busy = 0
        self.most_at_once = 0
        self._lock = threading.Lock()
        self.watchlist: set[str] = set()

    def _work(self, what: tuple) -> None:
        with self._lock:
            self.busy += 1
            self.most_at_once = max(self.most_at_once, self.busy)
        try:
            time.sleep(self.delay)
            if self.down:
                raise trakt.TraktError("No pude conectar con Trakt: sin red")
            self.sent.append(what)
        finally:
            with self._lock:
                self.busy -= 1

    def set_items(self, target, items, add):
        self._work(("items", target, tuple(items), add))
        if target == WATCHLIST:
            for _, imdb in items:
                (self.watchlist.add if add else self.watchlist.discard)(imdb)

    def set_hidden(self, imdbs, hidden, sections):
        self._work(("hidden", tuple(imdbs), hidden))

    def set_note(self, kind, imdb, text, note_id):
        if imdb == "tt404":
            raise trakt.TraktError("Trakt respondió HTTP 404", 404)  # definitivo
        self._work(("note", imdb, text))

    def add_history(self, target, at):
        self._work(("history", at))

    def viewed_near(self, target, at):
        return False


class FakeCache:
    def clear(self, key=None):
        pass


def make_gestor(t):
    settings: dict = {}
    state = SimpleNamespace(settings=lambda: settings, set_setting=lambda k, v: settings.__setitem__(k, v))
    events: list = []
    foryou = SimpleNamespace(trakt=t, catalog=SimpleNamespace(state=state), cache=FakeCache(), publish=events.append,
                             unfollowed=lambda: set())
    g = Gestor(foryou)  # type: ignore[arg-type]
    return g, events


def fill(outbox: TraktOutbox, n: int) -> None:
    for i in range(n):
        outbox.enqueue({"target": "12", "imdb": f"tt{100 + i}", "kind": "movie", "add": True})
        outbox.enqueue({"target": NOTE, "imdb": f"tt{500 + i}", "kind": "movie", "text": "x", "add": True})


@pytest.mark.reloj  # mide segundos de reloj: fuera de la pasada antes de actualizar, sí en la CI
def test_an_action_answers_at_once_even_with_a_long_queue_and_a_slow_trakt():
    t = SlowTrakt(delay=0.2)
    g, events = make_gestor(t)
    fill(g.outbox, 10)  # 20 envíos de 0,2 s: 4 s si la acción esperara a la cola
    started = time.monotonic()
    t.delay = 0.0
    assert g.set_watchlist([("movie", "tt0816692")], True) == "sent"
    t.delay = 0.2
    assert time.monotonic() - started < 1.0  # la acción no esperó a la cola
    assert ("items", WATCHLIST, (("movie", "tt0816692"),), True) in t.sent
    assert g.outbox.idle(timeout=15)
    assert g.outbox.pending == [] and len(t.sent) == 21
    assert any(e == {"type": "foryou-changed"} for e in events)  # la interfaz se entera de lo que salió solo


def test_the_same_title_in_the_queue_goes_after_it_so_the_last_choice_wins():
    t = SlowTrakt()
    g, _ = make_gestor(t)
    t.down = True
    assert g.set_watchlist([("movie", "tt1")], True) == "queued"  # sin red: «agregar» espera
    g.outbox.idle()
    t.down = False
    assert g.set_watchlist([("movie", "tt1")], False) == "queued"  # «quitar» va detrás y reemplaza al «agregar»
    assert g.outbox.idle()
    assert t.watchlist == set() and g.outbox.pending == []
    assert [s for s in t.sent if s[0] == "items"] == [("items", WATCHLIST, (("movie", "tt1"),), False)]


def test_only_one_worker_empties_the_queue_however_many_times_it_is_kicked():
    t = SlowTrakt(delay=0.02)
    box: dict = {}
    outbox = TraktOutbox(lambda: box.get("v"), lambda v: box.__setitem__("v", v))
    fill(outbox, 10)
    started = [outbox.kick(t) for _ in range(20)]
    assert started.count(True) == 1
    assert outbox.idle(timeout=10)
    assert t.most_at_once == 1 and outbox.pending == [] and len(t.sent) == 20
    assert len([s for s in t.sent if s[0] == "items"]) == 10 and len({s[1] for s in t.sent if s[0] == "note"}) == 10


def test_a_bug_or_a_definitive_4xx_leaves_the_queue_and_the_rest_keeps_its_order(caplog):
    class Buggy(SlowTrakt):
        def set_hidden(self, imdbs, hidden, sections):
            raise AttributeError("un error de programación")

    t = Buggy()
    box: dict = {}
    outbox = TraktOutbox(lambda: box.get("v"), lambda v: box.__setitem__("v", v))
    outbox.enqueue({"target": NOTE, "imdb": "tt1", "kind": "movie", "text": "a", "add": True})
    outbox.enqueue({"target": "hidden", "imdb": "tt2", "kind": "series", "add": True})  # el error de programación
    outbox.enqueue({"target": NOTE, "imdb": "tt404", "kind": "movie", "text": "b", "add": True})  # Trakt: 404
    outbox.enqueue({"target": HISTORY, "imdb": "tt3@1", "kind": "movie", "add": True, "video": {}, "at": 1.0})
    outbox.enqueue({"target": NOTE, "imdb": "tt4", "kind": "movie", "text": "c", "add": True})
    with caplog.at_level(logging.WARNING, logger="orbital.trakt_outbox"):
        assert outbox.flush(t) == 3
    assert outbox.pending == []  # nada atorado
    assert t.sent == [("note", "tt1", "a"), ("history", 1.0), ("note", "tt4", "c")]  # en su orden
    assert sum("descarto" in r.getMessage() for r in caplog.records) == 2  # los dos, a la bitácora


def test_only_the_network_and_trakt_being_busy_are_worth_waiting_for():
    assert retryable(net.NetError("sin red")) and retryable(TimeoutError())
    assert not retryable(AttributeError("bug")) and not retryable(KeyError("video"))
    assert not retryable(trakt.TraktError("Trakt respondió HTTP 422", 422))
    assert retryable(trakt.TraktError("No pude renovar tu sesión de Trakt (HTTP 503)", 503))


def test_when_trakt_answers_again_the_queue_leaves_by_itself(monkeypatch):
    t = SlowTrakt()
    g, _ = make_gestor(t)
    t.down = True
    g.set_watchlist([("movie", "tt7")], True)
    g.outbox.idle()
    assert len(g.outbox.pending) == 1
    t.down = False
    net.breaker.failure(trakt.HOST)  # fallaba…
    try:
        net.breaker.success(trakt.HOST)  # …y vuelve a contestar (cualquier lectura de Trakt)
        assert g.outbox.idle()
        assert g.outbox.pending == [] and t.watchlist == {"tt7"}
    finally:
        net.reset()


def test_a_flush_waits_for_the_one_in_course_instead_of_skipping():
    t = SlowTrakt(delay=0.05)
    box: dict = {}
    outbox = TraktOutbox(lambda: box.get("v"), lambda v: box.__setitem__("v", v))
    fill(outbox, 3)
    outbox.kick(t)
    outbox.flush(t)  # no regresa 0 a media vuelta: espera y sigue con lo que quedó
    assert outbox.pending == []


# --- reglas como el iPhone: no se atora, vence a los 30 días y deja bitácora --------------------------------------------
class Picky(SlowTrakt):
    """Trakt que contesta 503 a los envíos de los títulos en `busy` (solo esos: el resto entra)."""

    def __init__(self) -> None:
        super().__init__()
        self.refuse: set[str] = set()

    def set_items(self, target, items, add):
        if any(imdb in self.refuse for _, imdb in items):
            raise trakt.TraktError("Trakt respondió HTTP 503", 503)
        super().set_items(target, items, add)

    def set_hidden(self, imdbs, hidden, sections):
        if any(imdb in self.refuse for imdb in imdbs):
            raise trakt.TraktError("Trakt respondió HTTP 503", 503)
        super().set_hidden(imdbs, hidden, sections)


def outbox_with_clock(now):
    box: dict = {}
    outbox = TraktOutbox(lambda: box.get("v"), lambda v: box.__setitem__("v", v))
    outbox.clock = lambda: now[0]
    return outbox


def test_one_title_that_fails_does_not_hold_the_others_and_its_own_keep_their_order():
    t = Picky()
    t.refuse = {"tt1"}
    outbox = outbox_with_clock([1000.0])
    outbox.enqueue({"target": "hidden", "imdb": "tt1", "kind": "series", "add": True})  # «la dejé» (Trakt: 503)
    outbox.enqueue({"target": WATCHLIST, "imdb": "tt2", "kind": "movie", "add": True})  # otro título
    outbox.enqueue({"target": "hidden", "imdb": "tt3", "kind": "series", "add": True})  # otro título
    outbox.enqueue({"target": WATCHLIST, "imdb": "tt1", "kind": "series", "add": False})  # lo mismo de tt1, después
    assert outbox.flush(t) == 2
    assert [s[:2] for s in t.sent] == [("items", WATCHLIST), ("hidden", ("tt3",))]  # los otros no esperaron
    assert [i["imdb"] for i in outbox.pending] == ["tt1", "tt1"]  # lo de tt1, en su orden
    t.refuse = set()
    assert outbox.flush(t) == 2
    assert [s[:2] for s in t.sent[2:]] == [("hidden", ("tt1",)), ("items", WATCHLIST)]  # la dejé y luego salió de la lista


def test_watched_then_unwatched_ends_unwatched_even_if_trakt_was_busy():
    class History(SlowTrakt):
        def __init__(self):
            super().__init__()
            self.refuse = True
            self.seen: set[str] = set()

        def add_history(self, target, at):
            if self.refuse:
                raise trakt.TraktError("Trakt respondió HTTP 502", 502)
            self.seen.add(target["movie"]["ids"]["imdb"])

        def remove_viewings(self, ids):
            self.seen.discard("tt1")

    t = History()
    outbox = outbox_with_clock([1000.0])
    movie = {"movie": {"ids": {"imdb": "tt1"}}}
    outbox.enqueue({"target": HISTORY, "imdb": "tt1@900", "kind": "movie", "add": True, "video": movie, "at": 900.0})
    outbox.enqueue({"target": HISTORY, "imdb": "remove:7", "kind": "movie", "add": False, "ids": [7], "after": "tt1@900"})
    outbox.enqueue({"target": NOTE, "imdb": "tt2", "kind": "movie", "text": "otra", "add": True})
    outbox.flush(t)
    assert len(outbox.pending) == 2 and ("note", "tt2", "otra") in t.sent  # la vista espera; lo demás salió
    t.refuse = False
    outbox.flush(t)
    assert t.seen == set() and outbox.pending == []  # entró y luego salió: termina en «no visto»


def test_without_network_it_stops_at_once_instead_of_trying_each_one():
    t = SlowTrakt()
    t.down = True
    outbox = outbox_with_clock([1000.0])
    fill(outbox, 5)
    calls = []
    original = t._work
    t._work = lambda what: (calls.append(what), original(what))  # type: ignore[method-assign]
    assert outbox.flush(t) == 0 and len(calls) == 1 and len(outbox.pending) == 10


def test_what_could_not_be_sent_in_30_days_expires_into_the_journal():
    now = [1000.0]
    t = SlowTrakt()
    t.down = True
    outbox = outbox_with_clock(now)
    outbox.enqueue({"target": WATCHLIST, "imdb": "tt1", "kind": "movie", "add": True})
    now[0] += 20 * 86400
    outbox.enqueue({"target": WATCHLIST, "imdb": "tt2", "kind": "movie", "add": True})
    now[0] += 11 * 86400  # tt1 lleva 31 días; tt2, 11
    outbox.flush(t)
    assert [i["imdb"] for i in outbox.pending] == ["tt2"]
    [row] = outbox.discarded()
    assert row["why"] == "vencido" and row["imdb"] == "tt1" and row["at"] == now[0]


def test_every_definitive_discard_is_in_the_journal_and_in_diagnostics():
    from orbital.api.diagnostics import trakt_queue

    t = SlowTrakt()
    g, _ = make_gestor(t)
    g.outbox.enqueue({"target": NOTE, "imdb": "tt404", "kind": "movie", "text": "b", "add": True})
    g.outbox.enqueue({"target": NOTE, "imdb": "tt5", "kind": "movie", "text": "c", "add": True})
    g.outbox.flush(t)
    [row] = g.outbox.discarded()
    assert row["why"] == "rechazado" and row["imdb"] == "tt404" and "404" in row["reason"]
    queue = trakt_queue(SimpleNamespace(foryou=SimpleNamespace(gestor=g)))
    assert queue == {"pending": 0, "discarded": [row]}
    assert g.foryou.catalog.state.settings()["trakt_outbox_log"] == [row]  # se guarda en el estado: sobrevive un reinicio
