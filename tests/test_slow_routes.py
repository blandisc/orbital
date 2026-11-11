"""Las rutas lentas hacen fila aparte y los hilos de «Para ti» tienen tope (F6, punto 3).

Antes: 100 listas en una petición abrían ~30 hilos nuevos (un grupo por llamada) y, con 60 listas lentas a la vez,
`/api/status` tardaba ~9.5 s (esperaba detrás de ellas en los 40 hilos de FastAPI)."""

from __future__ import annotations

import threading
import time

import pytest
from fastapi.testclient import TestClient

from orbital.api import slow
from orbital.foryou import pools
from orbital.server import create_app


class SlowTmdb:
    def details(self, kind, tmdb_id):
        time.sleep(0.05)
        return {"imdb": f"tt{tmdb_id:07d}", "kind": kind, "title": f"T{tmdb_id}", "poster": "", "backdrop": "", "overview": ""}


def _client(library):
    return TestClient(create_app(library.config, library), base_url="http://127.0.0.1:8710", client=("127.0.0.1", 5000))


def test_hundred_lists_in_one_request_use_a_bounded_number_of_threads(library, monkeypatch):
    fy = library.foryou
    fy.tmdb = SlowTmdb()
    monkeypatch.setattr(fy, "list_items", lambda list_id, kind=None: fy._tmdb_items([{"id": i} for i in range(6)], "movie", "x"))
    with _client(library) as c:
        c.get("/api/status")  # que el servidor ya tenga sus hilos de siempre
        base, peak, done = threading.active_count(), [0], threading.Event()

        def sample():
            while not done.is_set():
                peak[0] = max(peak[0], threading.active_count())
                time.sleep(0.002)
        sampler = threading.Thread(target=sample, daemon=True)
        sampler.start()
        r = c.post("/api/foryou/lists", json={"lists": [{"id": f"x{i}"} for i in range(100)]})
        done.set()
        sampler.join()
    assert r.status_code == 200 and len(r.json()["lists"]) == 100
    assert all(len(x["items"]) == 6 for x in r.json()["lists"])
    grupos = pools.BATCH.workers + pools.DETAILS.workers
    assert peak[0] - base <= grupos + 3, f"{peak[0] - base} hilos nuevos (tope {grupos})"


def test_status_answers_while_a_hundred_slow_lists_are_in_flight(library, monkeypatch):
    fy = library.foryou
    gate, started = threading.Event(), threading.Semaphore(0)

    def stuck(list_id, kind=None):
        started.release()
        gate.wait(20)
        return {"items": []}
    monkeypatch.setattr(fy, "list_payload", stuck)
    with _client(library) as c:
        codes: list[int] = []
        clients = [threading.Thread(target=lambda: codes.append(c.get("/api/foryou/list", params={"id": "lenta"}).status_code))
                   for _ in range(100)]
        try:
            for t in clients:
                t.start()
            for _ in range(slow.SLOW_LIMIT):  # las primeras ya están adentro; las demás, en su fila
                assert started.acquire(timeout=10)
            t0 = time.monotonic()
            status = c.get("/api/status")
            waited = time.monotonic() - t0
        finally:
            gate.set()
            for t in clients:
                t.join(30)
    assert status.status_code == 200
    assert waited < 2, f"/api/status tardó {waited:.2f} s detrás de las listas"
    assert codes == [200] * 100


def test_pool_keeps_order_respects_at_most_and_raises_the_first_error():
    pool = pools.Pool("prueba", level=1, workers=8)
    busy, most, lock = [0], [0], threading.Lock()

    def one(x):
        with lock:
            busy[0] += 1
            most[0] = max(most[0], busy[0])
        time.sleep(0.01)
        with lock:
            busy[0] -= 1
        return x * 2
    assert pool.map(one, range(20), at_most=3) == [x * 2 for x in range(20)]
    assert most[0] <= 3

    def bad(x):
        if x in (4, 7):
            raise ValueError(x)
        return x
    with pytest.raises(ValueError, match="4"):
        pool.map(bad, range(10))


def test_nested_calls_never_wait_on_each_other():
    """Una tarea que pide su propio nivel (o uno más afuera) lo hace en su hilo: con un grupo de 1 no se bloquea."""
    inner = pools.Pool("dentro", level=1, workers=1)
    outer = pools.Pool("fuera", level=2, workers=1)
    out: list = []

    def leaf(x):
        return inner.map(lambda y: y + x, [1, 2]) + outer.map(lambda y: y, [x, x])

    t = threading.Thread(target=lambda: out.append(outer.map(lambda x: inner.map(leaf, [x, x]), [10, 20])))
    t.start()
    t.join(5)
    assert not t.is_alive(), "las tareas anidadas se bloquearon"
    assert out == [[[[11, 12, 10, 10]] * 2, [[21, 22, 20, 20]] * 2]]
