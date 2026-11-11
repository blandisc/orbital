"""F4 (TV): un scrobble que falla por la red o con Trakt caído pasa por la cola de Trakt y se reintenta, como el iPhone."""

from __future__ import annotations

from test_scrobble import EPISODE, MOVIE, setup

from orbital import trakt_outbox
from orbital.library import trakt
from orbital.trakt_outbox import HISTORY, PROGRESS, TraktOutbox


def wired(monkeypatch, reply):
    net, t, s = setup(monkeypatch, reply=reply)
    box: dict = {}
    s.outbox = TraktOutbox(lambda: box.get("v"), lambda v: box.__setitem__("v", v))
    s.outbox.sleep = lambda seconds: None
    return net, t, s


def test_a_finished_movie_without_internet_waits_as_a_viewing(monkeypatch):
    net, t, s = wired(monkeypatch, trakt.TraktError("No pude conectar con Trakt: sin red"))
    s.event("stop", MOVIE, 7000, 7200)
    s.wait()
    [item] = s.outbox.pending
    assert item["target"] == HISTORY and item["add"] and item["at"] == 1000.0  # con la hora en que terminaste
    assert item["video"] == {"movie": {"ids": {"imdb": "tt1375666"}}}


def test_a_half_watched_episode_keeps_only_its_latest_progress(monkeypatch):
    net, t, s = wired(monkeypatch, (503, None))
    s.event("pause", EPISODE, 300, 1200)
    s.event("pause", EPISODE, 600, 1200)
    s.event("start", EPISODE, 600, 1200)  # un start no se guarda
    s.wait()
    [item] = s.outbox.pending
    assert item["target"] == PROGRESS and item["imdb"] == "tt0386676:2:5" and item["progress"] == 50.0


def test_errors_that_retrying_cannot_fix_are_not_queued(monkeypatch):
    net, t, s = wired(monkeypatch, (422, None))
    s.event("stop", MOVIE, 7000, 7200)
    s.wait()
    assert s.outbox.pending == []


def test_when_trakt_answers_again_the_queue_goes_out(monkeypatch):
    replies = [(503, None), (201, {}), (201, {}), (201, {})]
    net, t, s = wired(monkeypatch, lambda url, body: replies.pop(0) if replies else (201, {}))
    net.on("/sync/playback", (200, []))
    s.event("pause", EPISODE, 600, 1200)  # falla: a la cola
    s.wait()
    assert len(s.outbox.pending) == 1
    s.event("pause", EPISODE, 700, 1200)  # Trakt ya contesta: este llega y manda lo que esperaba
    s.wait()
    assert s.outbox.pending == []
    sent = [step for step, _ in net.scrobbles()]
    assert sent[-2:] == ["start", "pause"]  # el avance pendiente: start y, 2 s después, pause


def test_an_older_progress_does_not_beat_a_newer_one_from_another_device(monkeypatch):
    net, t, s = wired(monkeypatch, (201, {}))
    net.on("/sync/playback", (200, [{"type": "episode", "progress": 80.0, "paused_at": "2030-01-01T00:00:00.000Z",
                                     "show": {"ids": {"imdb": "tt0386676"}}, "episode": {"season": 2, "number": 5}}]))
    s.outbox.enqueue({"target": PROGRESS, "imdb": "tt0386676:2:5", "kind": "series", "add": True,
                      "video": trakt.scrobble_target("series", "tt0386676", "tt0386676:2:5"), "progress": 10.0, "at": 1000.0})
    assert s.outbox.flush(t) == 1 and s.outbox.pending == []
    assert net.scrobbles() == []  # Trakt ya tenía uno más nuevo: no se manda el viejo


def test_scrobble_errors_carry_their_status():
    assert trakt_outbox.retryable(trakt.TraktError("Trakt respondió HTTP 503", 503))
    assert not trakt_outbox.retryable(trakt.TraktError("Trakt respondió HTTP 422", 422))
