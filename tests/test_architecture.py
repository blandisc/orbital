"""Piezas base de la arquitectura: eventos, almacén de elementos, escaneo único y estado por hilo."""

import threading
import time

from orbital.events import EventBus
from orbital.library.models import LibraryItem
from orbital.store import ItemStore


def item(i, source="steam"):
    return LibraryItem(id=f"{source}:{i}", title=f"Juego {i}", category="steam", source=source)


def test_a_broken_listener_does_not_stop_the_others():
    bus, got = EventBus(), []

    def broken(event):
        raise RuntimeError("boom")

    bus.subscribe(broken)
    unsubscribe = bus.subscribe(got.append)
    bus.publish({"type": "x"})
    assert got == [{"type": "x"}]
    unsubscribe()
    bus.publish({"type": "y"})
    assert got == [{"type": "x"}]


def test_store_replaces_one_source_without_touching_the_rest():
    store = ItemStore()
    store.replace([item(1), item(2, "stremio")])
    store.replace_source("stremio", [item(3, "stremio")])
    assert sorted(i.id for i in store.all()) == ["steam:1", "stremio:3"]
    store.update(lambda i: i.extra.update(hours=5), where=lambda i: i.source == "steam")
    assert store.get("steam:1").extra == {"hours": 5}


def test_two_refreshes_at_once_scan_only_once(library, monkeypatch):
    calls = []

    def slow():
        calls.append(1)
        time.sleep(.2)
        return 3

    monkeypatch.setattr(library, "_refresh", slow)
    results = []
    threads = [threading.Thread(target=lambda: results.append(library.refresh())) for _ in range(3)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    assert len(calls) == 1 and len(results) == 3  # el botón durante el arranque espera, no repite


def test_revealing_is_per_thread(library):
    library.revealing = True
    seen = []
    worker = threading.Thread(target=lambda: seen.append(library.revealing))
    worker.start()
    worker.join()
    assert library.revealing is True and seen == [False]  # la voz en segundo plano no pisa a la interfaz


def test_closed_event_refreshes_stremio(library, monkeypatch):
    refreshed = []
    monkeypatch.setattr(library.watch, "refresh_stremio", lambda background=False: refreshed.append(background))
    library.notify({"type": "closed", "id": "media:stremio", "title": "Stremio", "seconds": 60})
    assert refreshed == [True]
