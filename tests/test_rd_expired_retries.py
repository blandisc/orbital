"""Real-Debrid vencido: la TV no pasa de versión en versión (Fernando, 21 nov 2026: «lo único que hace es pasar de versión
en versión y nunca encuentra»). Al fallar la primera se le pregunta una vez a tu nube y, si la cuenta no sirve, se dice por
qué en vez de probar la siguiente (como `RealDebridRetryTests` del iPhone)."""

from types import SimpleNamespace

from orbital import watch
from orbital.library import streams


def _src(i):
    return streams.Source(index=i, addon="Torrentio", stream={"url": f"http://rd/{i}"}, transport_url="",
                          debrid=True, cached=True)


def _fake(problem, service="realdebrid", linked=True):
    loaded, toasts, published, asked = [], [], [], []

    def status(fresh=False):
        asked.append(fresh)
        return {"problem": problem}

    fake = SimpleNamespace(
        asked_language=lambda meta: (streams.Preferences(audio="es"), ""),
        stream_sources=lambda kind, video, prefs: [_src(i) for i in (1, 2, 3)],
        native_player=False,
        _load_in_player=lambda *a, **k: loaded.append(a[4].index) or True,
        rd=SimpleNamespace(client=lambda: object() if linked else None),
        debrid_status=status, debrid_service=service, debrid_name={"realdebrid": "Real-Debrid", "torbox": "TorBox"}[service],
        events=SimpleNamespace(publish=published.append),
        player=SimpleNamespace(toast=lambda text, seconds=0: toasts.append(text)))
    fake._account_stops_retries = lambda meta, first: watch.Watch._account_stops_retries(fake, meta, first)
    return fake, loaded, toasts, published, asked


META = {"kind": "movie", "meta_id": "tt1", "video_id": "tt1", "title": "Peli", "source": 1, "tried": [1]}


def test_an_expired_account_stops_at_the_first_failed_version():
    fake, loaded, toasts, published, asked = _fake("expired")
    assert watch.Watch._source_failed(fake, META, 0.0, True) is False
    assert loaded == []  # no probó la siguiente
    assert asked == [True]  # le preguntó a Real-Debrid una vez, en ese momento
    assert toasts == ["Tu Real-Debrid venció · Renovar en real-debrid.com, desde tu celular"]
    assert published[-1]["message"] == "Tu Real-Debrid venció"


def test_no_premium_and_a_bad_key_also_stop_and_say_the_name_of_your_cloud():
    for problem, words in (("no_premium", "Tu cuenta no tiene Premium"), ("bad_key", "Vuelve a conectar TorBox")):
        fake, loaded, toasts, _, _ = _fake(problem, service="torbox")
        assert watch.Watch._source_failed(fake, META, 0.0, True) is False
        assert loaded == [] and toasts[0].startswith(words)


def test_a_good_account_keeps_trying_and_only_asks_fresh_the_first_time():
    fake, loaded, toasts, _, asked = _fake(None)
    assert watch.Watch._source_failed(fake, META, 0.0, True) is True
    assert loaded == [2] and asked == [True]
    assert watch.Watch._source_failed(fake, {**META, "source": 2, "tried": [1, 2]}, 0.0, True) is True
    assert asked == [True, False]  # la segunda vez, lo guardado (sin volver a preguntar)


def test_offline_or_without_a_key_it_keeps_trying():
    fake, loaded, _, _, _ = _fake("offline")
    assert watch.Watch._source_failed(fake, META, 0.0, True) is True and loaded == [2]
    fake, loaded, _, _, asked = _fake("expired", linked=False)
    assert watch.Watch._source_failed(fake, META, 0.0, True) is True and loaded == [2] and asked == []
