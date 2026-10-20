import threading
import time

from orbital import startup_profile


def busy_orbital_work(stop):  # un hilo «de Orbital» que trabaja (no espera)
    while not stop.is_set():
        sum(range(2000))


def test_counts_the_orbital_function_that_keeps_a_thread_busy(tmp_path):
    stop = threading.Event()
    worker = threading.Thread(target=busy_orbital_work, args=(stop,), name="escaneo")
    worker.start()
    try:
        lines = startup_profile.run(seconds=.4, interval=.02, path=tmp_path / "arranque.log")
    finally:
        stop.set()
        worker.join()
    text = (tmp_path / "arranque.log").read_text(encoding="utf-8")
    assert "[escaneo]" in text and "busy_orbital_work" in text and lines[0].startswith("")


def test_waiting_threads_do_not_count(tmp_path):
    sleeper = threading.Thread(target=time.sleep, args=(.6,), name="dormido")
    sleeper.start()
    startup_profile.run(seconds=.3, interval=.02, path=tmp_path / "arranque.log")
    sleeper.join()
    assert "[dormido]" not in (tmp_path / "arranque.log").read_text(encoding="utf-8")


def test_every_https_request_shares_one_tls_context():
    """Armar un contexto TLS carga los certificados de Windows (≈100 ms de CPU): uno para todo Orbital, no uno por pedido."""
    import urllib.request

    from orbital import net
    from orbital.library import iptv_health

    assert net.tls_context() is net.tls_context()
    assert iptv_health._context() is iptv_health._context()
    previous = urllib.request._opener  # type: ignore[attr-defined]
    try:
        net.share_tls()
        handlers = urllib.request._opener.handlers  # type: ignore[attr-defined]
        https = [h for h in handlers if isinstance(h, urllib.request.HTTPSHandler)]
        assert https and https[0]._context is net.tls_context()
    finally:
        urllib.request.install_opener(previous)
