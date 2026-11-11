"""La caché de «Para ti» (V6): tope por prefijo, purga de lo vencido y una sola serialización por cambio."""

from __future__ import annotations

import json

from orbital import foryou as foryou_mod
from orbital.foryou import Cache


def test_each_prefix_keeps_only_its_newest(monkeypatch):
    monkeypatch.setattr(Cache, "PREFIX_LIMIT", 3)
    now = [0.0]
    cache = Cache(clock=lambda: now[0])
    for i in range(5):
        now[0] = i
        cache.get(f"poster:tt{i}", 999, lambda i=i: f"p{i}")
    cache.get("details:x", 999, lambda: "d")
    assert [cache.peek(f"poster:tt{i}") for i in range(5)] == [None, None, "p2", "p3", "p4"]
    assert cache.peek("details:x") == "d"  # otro prefijo, su propio tope


def test_renewing_an_entry_makes_it_new_again(monkeypatch):
    monkeypatch.setattr(Cache, "PREFIX_LIMIT", 2)
    now = [0.0]
    cache = Cache(clock=lambda: now[0])
    cache.get("poster:a", 1, lambda: "a1")
    now[0] = 1
    cache.get("poster:b", 1, lambda: "b")
    now[0] = 5
    cache.get("poster:a", 1, lambda: "a2")  # vencida: se renueva y pasa al final
    now[0] = 6
    cache.get("poster:c", 1, lambda: "c")
    assert cache.peek("poster:a") == "a2" and cache.peek("poster:b") is None


def test_what_is_too_old_is_purged_on_load_and_save(tmp_path):
    path = tmp_path / "foryou-cache.json"
    now = 1_000_000_000.0
    path.write_text(json.dumps({"poster:old": [now - Cache.MAX_AGE - 1, "viejo"], "poster:ok": [now - 10, "bien"],
                                "roto": "no es [fecha, valor]"}), encoding="utf-8")
    cache = Cache(clock=lambda: now, path=path)
    assert cache.peek("poster:old") is None and cache.peek("poster:ok") == "bien"
    cache._save()
    assert json.loads(path.read_text(encoding="utf-8")) == {"poster:ok": [now - 10, "bien"]}


def test_a_change_serializes_only_that_entry(tmp_path, monkeypatch):
    path = tmp_path / "foryou-cache.json"
    cache = Cache(path=path)
    for i in range(3):
        cache.get(f"details:{i}", 999, lambda i=i: {"n": i})
    cache.get("raro", 999, lambda: {1, 2})  # no se puede guardar: se salta
    cache._save()
    calls = []
    real = foryou_mod.json.dumps
    monkeypatch.setattr(foryou_mod.json, "dumps", lambda obj, **kw: calls.append(obj) or real(obj, **kw))
    cache.get("details:9", 999, lambda: {"n": 9})
    cache._save()
    values = [c for c in calls if isinstance(c, list) and c[1] != {1, 2}]  # el raro se vuelve a intentar (y falla)
    assert values == [[cache._data["details:9"][0], {"n": 9}]]  # lo demás ya estaba en texto
    saved = json.loads(path.read_text(encoding="utf-8"))
    assert {k: v[1] for k, v in saved.items()} == {"details:0": {"n": 0}, "details:1": {"n": 1}, "details:2": {"n": 2},
                                                  "details:9": {"n": 9}}
    cache.clear("details:1")
    assert "details:1" not in json.loads(path.read_text(encoding="utf-8"))


def test_clear_and_the_save_timer_never_bring_back_what_was_cleared(tmp_path):
    """`clear()` guarda al instante y el temporizador puede estar guardando a la vez: lo borrado no regresa del disco."""
    import json as _json
    import threading as _threading

    path = tmp_path / "foryou-cache.json"
    for _ in range(20):
        cache = Cache(path=path)
        for i in range(200):
            cache.get(f"poster:{i}", 60, lambda i=i: {"url": "x" * 200, "i": i})
        saver = _threading.Thread(target=cache._save)
        saver.start()
        cache.clear("poster:")
        saver.join()
        on_disk = _json.loads(path.read_text(encoding="utf-8"))
        assert not [k for k in on_disk if k.startswith("poster:")]


def test_per_key_locks_leave_with_their_keys(monkeypatch):
    """Revisión del 11 nov 2026: un candado por cada clave pedida alguna vez, para siempre (miles de pósters en un día)."""
    from orbital.net import NetError

    monkeypatch.setattr(Cache, "PREFIX_LIMIT", 10)
    cache = Cache(clock=lambda: 0.0)
    for i in range(500):
        cache.get(f"poster:tt{i}", 999, lambda i=i: f"p{i}")
    assert len(cache._locks) <= 10  # las que salieron por el tope se llevaron su candado

    def offline():
        raise NetError("sin internet")

    for i in range(200):  # lo que nunca llegó tampoco deja el suyo
        try:
            cache.get(f"details:tt{i}", 999, offline)
        except NetError:
            pass
    assert len(cache._locks) <= 10
    cache.clear("poster")
    assert cache._locks == {}
    assert cache.get("poster:tt1", 999, lambda: "otra vez") == "otra vez"  # y la clave sigue funcionando


def test_a_stale_refresh_still_runs_once_and_keeps_working_after_the_lock_is_gone():
    import threading
    import time

    now = [0.0]
    cache = Cache(clock=lambda: now[0])
    cache.get("top:x", 10, lambda: "viejo")
    now[0] = 20
    started, go = threading.Event(), threading.Event()
    calls = []

    def slow():
        calls.append(1)
        started.set()
        go.wait(5)
        return "nuevo"

    assert cache.get("top:x", 10, slow, stale=True) == "viejo"
    assert started.wait(5)
    assert cache.get("top:x", 10, slow, stale=True) == "viejo" and len(calls) == 1  # una sola renovación a la vez
    go.set()
    deadline = time.monotonic() + 5
    while cache.peek("top:x") != "nuevo" and time.monotonic() < deadline:
        time.sleep(0.01)
    assert cache.peek("top:x") == "nuevo"
