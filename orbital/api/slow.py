"""Las rutas lentas (listas y fichas) hacen fila aparte.

FastAPI corre cada ruta normal (`def`, no `async def`) en un hilo del mismo grupo de 40. Si 60 listas de «Para ti»
tardaban, ocupaban los 40 y `/api/status` (lo que el mando y el iPhone preguntan a cada rato) esperaba detrás de ellas.
Con `@slow`, esas rutas usan su propio tope (`SLOW_LIMIT` a la vez): las demás siempre encuentran lugar.

Quién es dueño de qué: `_limiters` (un tope por bucle de eventos: el servidor tiene uno; las pruebas, uno por cliente) se
llena bajo `_lock`.
"""

from __future__ import annotations

import asyncio
import functools
import inspect
import threading
import typing
import weakref
from collections.abc import Callable
from typing import Any, TypeVar

import anyio
import anyio.to_thread

SLOW_LIMIT = 16  # listas y fichas a la vez; el resto espera su turno sin quitarle hilos a las demás rutas

F = TypeVar("F", bound=Callable[..., Any])

_lock = threading.Lock()
_limiters: weakref.WeakKeyDictionary[asyncio.AbstractEventLoop, anyio.CapacityLimiter] = weakref.WeakKeyDictionary()


def limiter() -> anyio.CapacityLimiter:
    """El tope de las rutas lentas del bucle que corre (se llama desde dentro de él)."""
    loop = asyncio.get_running_loop()
    with _lock:
        found = _limiters.get(loop)
        if found is None:
            found = _limiters[loop] = anyio.CapacityLimiter(SLOW_LIMIT)
        return found


def slow(fn: F) -> F:
    """Corre la ruta en un hilo, como siempre, pero con el tope de las rutas lentas. La firma (parámetros y respuesta)
    queda igual: FastAPI la lee de la función original, ya con los tipos resueltos."""
    hints = typing.get_type_hints(fn)
    sig = inspect.signature(fn)
    sig = sig.replace(parameters=[p.replace(annotation=hints.get(p.name, p.annotation)) for p in sig.parameters.values()],
                      return_annotation=hints.get("return", sig.return_annotation))

    @functools.wraps(fn)
    async def run(*args: Any, **kwargs: Any) -> Any:
        return await anyio.to_thread.run_sync(functools.partial(fn, *args, **kwargs), limiter=limiter())

    del run.__wrapped__  # FastAPI lee la firma de aquí abajo (con los tipos ya resueltos), no de la original
    run.__signature__ = sig  # type: ignore[attr-defined]
    run.__annotations__ = dict(hints)
    return typing.cast(F, run)
