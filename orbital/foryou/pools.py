"""Los hilos de «Para ti», compartidos y con tope.

Antes cada llamada abría su propio grupo de hilos (`ThreadPoolExecutor(max_workers=…)`): 100 listas a la vez eran
cientos de hilos. Ahora hay pocos grupos fijos, uno por nivel, y cada llamada pide «a lo más n» de ellos (el mismo n
de antes), así que una sola llamada va igual de rápido y muchas juntas esperan su turno en vez de abrir más hilos.

Los niveles van de afuera hacia adentro: BATCH (varias listas en una petición) → SOURCES (las fuentes del mosaico) →
DETAILS (lo de cada título: TMDB, Cinemeta, Trakt). WARM es lo que se calienta en segundo plano. Una tarea que ya corre
en un nivel y pide otro igual o más afuera lo hace en su propio hilo, sin encolar: así ningún hilo se queda esperando
a otro que espera por él (el bloqueo de tareas anidadas).

Quién es dueño de qué: cada `Pool` es dueño de su `_lock` (abrir y cerrar el grupo, y contar `_active`); cada llamada a `map` es dueña
de su `lock` local (repartir los elementos entre sus hilos). Nada más se comparte.
"""

from __future__ import annotations

import threading
from collections.abc import Callable, Iterable
from concurrent.futures import ThreadPoolExecutor, wait
from typing import Any, TypeVar

T = TypeVar("T")
R = TypeVar("R")

_here = threading.local()  # el nivel del grupo en el que corre este hilo (None fuera de los grupos)


class Pool:
    """Un grupo de hilos fijo y compartido. `map` es como `ThreadPoolExecutor.map` pero devuelve la lista (en orden) y
    usa a lo más `at_most` hilos del grupo."""

    def __init__(self, name: str, level: int, workers: int) -> None:
        self.name, self.level, self.workers = name, level, workers
        self._lock = threading.Lock()
        self._pool: ThreadPoolExecutor | None = None
        self._active = 0  # cuántas llamadas a `map` lo usan ahora

    def _enter(self) -> ThreadPoolExecutor:
        with self._lock:
            self._active += 1
            if self._pool is None:
                self._pool = ThreadPoolExecutor(max_workers=self.workers, thread_name_prefix=f"parati-{self.name}")
            return self._pool

    def _leave(self) -> None:
        """Cuando ya nadie lo usa, el grupo suelta sus hilos (no se quedan dormidos ocupando memoria; el siguiente pedido
        abre los suyos, que es barato)."""
        with self._lock:
            self._active -= 1
            if self._active == 0 and self._pool is not None:
                self._pool.shutdown(wait=False)
                self._pool = None

    def map(self, fn: Callable[[T], R], items: Iterable[T], at_most: int | None = None) -> list[R]:
        todo = list(items)
        level = getattr(_here, "level", None)
        if len(todo) <= 1 or (level is not None and level <= self.level):
            return [fn(x) for x in todo]  # uno solo, o ya estamos dentro de este nivel (o uno más afuera): aquí mismo
        results: list[Any] = [None] * len(todo)
        errors: list[tuple[int, BaseException]] = []
        lock, cursor = threading.Lock(), iter(range(len(todo)))

        def drain() -> None:
            before = getattr(_here, "level", None)
            _here.level = self.level
            try:
                while True:
                    with lock:
                        i = next(cursor, None)
                    if i is None:
                        return
                    try:
                        results[i] = fn(todo[i])
                    except BaseException as exc:  # noqa: BLE001 - se vuelve a lanzar abajo, como pool.map
                        with lock:
                            errors.append((i, exc))
            finally:
                _here.level = before

        n = min(at_most or self.workers, self.workers, len(todo))
        pool = self._enter()
        try:
            wait([pool.submit(drain) for _ in range(n)])
        finally:
            self._leave()
        if errors:
            raise min(errors, key=lambda e: e[0])[1]  # el primero en orden, como lo lanzaba pool.map
        return results

    def run(self, jobs: Iterable[Callable[[], R]], at_most: int | None = None) -> list[R]:
        """Varias tareas distintas a la vez (lo que antes era `pool.submit` de cada una); los resultados, en orden."""
        return self.map(lambda job: job(), jobs, at_most)


BATCH = Pool("listas", level=3, workers=4)  # POST /api/foryou/lists: «como las 4 colas que tenía la interfaz»
SOURCES = Pool("fuentes", level=2, workers=4)  # las fuentes del mosaico
DETAILS = Pool("detalles", level=1, workers=16)  # lo de cada título (TMDB, Cinemeta, Trakt, Letterboxd, RAWG)
WARM = Pool("calentar", level=0, workers=2)  # pósters y logos en segundo plano
