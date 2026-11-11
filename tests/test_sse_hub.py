"""SSE (F9): una pantalla que se atrasa no se queda desfasada en silencio; se le cierra para que se reconecte."""

from __future__ import annotations

import asyncio

from orbital.api.live import CLOSE, SseHub


def test_a_full_queue_is_closed_and_dropped():
    async def scenario():
        hub = SseHub()
        slow, quick = hub.subscribe(), hub.subscribe()
        for i in range(slow.maxsize):
            hub.publish({"type": "toast", "n": i})
        while not quick.empty():
            quick.get_nowait()  # esta pantalla sí lee
        hub.publish({"type": "status"})
        assert slow.qsize() == 1 and slow.get_nowait() is CLOSE  # lo viejo se tira; solo queda «reconéctate»
        assert quick.get_nowait() == {"type": "status"}
        hub.publish({"type": "toast"})
        assert slow.empty() and quick.qsize() == 1  # la atrasada ya no recibe nada: espera a reconectarse

    asyncio.run(scenario())


def test_the_events_stream_ends_on_close(make_client):
    from orbital.api import live

    deps = make_client().app.state.deps
    route = next(r for r in live.router(deps, lambda request: True).routes if getattr(r, "path", "") == "/api/events")
    hub = deps.hub

    class Request:
        async def is_disconnected(self):
            return False

    async def scenario():
        hub.loop = asyncio.get_running_loop()
        response = await route.endpoint(Request())
        body = response.body_iterator
        assert (await body.__anext__()).startswith(": conectado")
        assert '"status"' in await body.__anext__()  # al conectarse, el estado
        for _ in range(150):  # nadie lee: la cola se llena
            hub.publish({"type": "toast"})
        rest = [chunk async for chunk in body]  # y la respuesta termina (antes: abierta, con avisos perdidos)
        assert rest == [] and not hub._subscribers

    asyncio.run(scenario())
