"""Una vista nunca queda doble en Trakt ni se pierde (revisión del 11 nov 2026).

Un Trakt falso con historial de verdad: aplica lo que le llega y, a propósito, a veces pierde la respuesta (la vista SÍ
entró, pero Orbital no se entera), responde tarde (la hora de la vista es unos minutos después) o no recibe nada.
"""

from __future__ import annotations

import random
from datetime import datetime
from urllib.parse import parse_qs, urlsplit

import pytest
from test_scrobble import EPISODE, MOVIE, Creds

from orbital import net as net_lib
from orbital.library import trakt
from orbital.scrobble import TraktScrobbler
from orbital.trakt_outbox import HISTORY, TraktOutbox


def _iso(when: float) -> str:
    return trakt._iso(when)


class FakeTrakt:
    """Trakt con historial. `down`: no llega nada. `lose`: cuántas escrituras más se aplican pero su respuesta se pierde.
    `delay`: cuántos segundos después de la hora pedida queda la vista (Trakt anota cuando recibe el `stop`)."""

    def __init__(self, now: float = 1000.0) -> None:
        self.now = now
        self.history: list[dict] = []
        self.down = False
        self.lose = 0
        self.delay = 0.0
        self.writes: list[str] = []

    def _add(self, row: dict) -> None:
        row["id"] = len(self.history) + 1
        self.history.append(row)

    def __call__(self, url, *, method="GET", headers=None, body=None, timeout=10, **_):
        if self.down:
            raise net_lib.NetError("sin red (pruebas)")
        parts = urlsplit(url)
        path, query = parts.path, {k: v[0] for k, v in parse_qs(parts.query).items()}
        if method == "GET" and path.startswith("/sync/history/"):
            kind = path.rsplit("/", 1)[1]
            lo = datetime.fromisoformat(query["start_at"].replace("Z", "+00:00")).timestamp()
            hi = datetime.fromisoformat(query["end_at"].replace("Z", "+00:00")).timestamp()
            rows = [r for r in self.history if r["type"] == kind[:-1] and lo <= r["at"] <= hi]
            return 200, [{**r, "watched_at": _iso(r["at"])} for r in rows]
        if method == "GET" and path == "/sync/playback":
            return 200, []
        if method != "POST":
            return 404, None
        self.writes.append(path)
        if path == "/scrobble/stop" and (body or {}).get("progress", 0) >= 80:
            self._viewing(body, self.now + self.delay)
        elif path.startswith("/scrobble/"):
            pass
        elif path == "/sync/history":
            for m in body.get("movies") or []:
                self._add({"type": "movie", "movie": {"ids": m["ids"]}, "at": _ts(m["watched_at"])})
            for s in body.get("shows") or []:
                for season in s["seasons"]:
                    for e in season["episodes"]:
                        self._add({"type": "episode", "show": {"ids": s["ids"]},
                                   "episode": {"season": season["number"], "number": e["number"]}, "at": _ts(e["watched_at"])})
        else:
            return 404, None
        if self.lose:
            self.lose -= 1
            raise net_lib.NetError("se perdió la respuesta (pruebas)")
        return 201, {}

    def _viewing(self, body: dict, at: float) -> None:
        if "episode" in body:
            self._add({"type": "episode", "show": body["show"], "episode": body["episode"], "at": at})
        else:
            self._add({"type": "movie", "movie": body["movie"], "at": at})


def _ts(value: str) -> float:
    return datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp()


@pytest.fixture
def tv(monkeypatch):
    fake = FakeTrakt()
    monkeypatch.setattr(trakt, "http_json", fake)
    t = trakt.Trakt("cid", "", Creds())
    s = TraktScrobbler(lambda: t, clock=lambda: 1000.0, sleep=lambda _: None)
    box: dict = {}
    s.outbox = TraktOutbox(lambda: box.get("v"), lambda v: box.__setitem__("v", v))
    s.outbox.sleep = lambda _: None
    return fake, t, s


def test_a_stop_that_arrived_but_lost_its_answer_is_not_sent_again(tv):
    fake, t, s = tv
    fake.lose, fake.delay = 1, 240  # Trakt anotó la vista 4 min después y la respuesta nunca llegó
    s.event("stop", MOVIE, 7100, 7200)
    s.wait()
    [item] = s.outbox.pending
    assert item["target"] == HISTORY  # Orbital no sabe que llegó: la guarda
    s.outbox.flush(t)
    assert s.outbox.pending == []
    assert len(fake.history) == 1  # una sola vista
    assert "/sync/history" not in fake.writes  # ni se intentó mandarla otra vez


def test_a_stop_that_never_arrived_is_sent_from_the_queue(tv):
    fake, t, s = tv
    fake.down = True
    s.event("stop", EPISODE, 1190, 1200)
    s.wait()
    assert s.outbox.flush(t) == 0 and len(s.outbox.pending) == 1  # sigue sin red: espera, no se pierde
    fake.down = False
    s.outbox.flush(t)
    assert s.outbox.pending == [] and len(fake.history) == 1
    assert fake.history[0]["episode"] == {"season": 2, "number": 5}


def test_a_queued_viewing_whose_answer_is_lost_is_not_sent_twice(tv):
    fake, t, s = tv
    fake.down = True
    s.event("stop", MOVIE, 7100, 7200)
    s.wait()
    fake.down, fake.lose = False, 1
    s.outbox.flush(t)  # llega, pero se pierde la respuesta: sigue en la cola
    assert len(s.outbox.pending) == 1 and len(fake.history) == 1
    s.outbox.flush(t)  # la siguiente vez Trakt ya la tiene: sale de la cola sin mandarla
    assert s.outbox.pending == [] and len(fake.history) == 1


def test_an_older_viewing_of_the_same_title_does_not_hide_a_new_one(tv):
    fake, t, s = tv
    fake._add({"type": "movie", "movie": {"ids": {"imdb": "tt1375666"}}, "at": 1000.0 - 3 * 3600})  # la viste hace 3 h
    fake._add({"type": "episode", "show": {"ids": {"imdb": "tt0386676"}}, "episode": {"season": 2, "number": 4},
               "at": 1000.0})  # otro capítulo, a la misma hora
    fake.down = True
    s.event("stop", MOVIE, 7100, 7200)
    s.event("stop", EPISODE, 1190, 1200)
    s.wait()
    fake.down = False
    s.outbox.flush(t)
    assert s.outbox.pending == [] and len(fake.history) == 4


def test_never_doubled_and_never_lost_whatever_the_network_does(monkeypatch):
    rng = random.Random(11)
    for _ in range(200):
        fake = FakeTrakt()
        monkeypatch.setattr(trakt, "http_json", fake)
        t = trakt.Trakt("cid", "", Creds())
        s = TraktScrobbler(lambda t=t: t, clock=lambda: 1000.0, sleep=lambda _: None)
        box: dict = {}
        s.outbox = TraktOutbox(lambda box=box: box.get("v"), lambda v, box=box: box.__setitem__("v", v))
        fake.down, fake.lose, fake.delay = rng.random() < 0.4, rng.randint(0, 2), rng.uniform(0, 500)
        s.event("stop", rng.choice([MOVIE, EPISODE]), 7190, 7200)
        s.wait()
        for _ in range(rng.randint(0, 4)):  # unas idas y vueltas de la red
            fake.down, fake.lose = rng.random() < 0.5, rng.randint(0, 1)
            s.outbox.flush(t)
        fake.down, fake.lose = False, 0
        s.outbox.flush(t)
        assert s.outbox.pending == [] and len(fake.history) == 1


def test_viewed_near_only_counts_that_title_or_episode(tv):
    fake, t, _ = tv
    fake._add({"type": "episode", "show": {"ids": {"imdb": "tt0386676"}}, "episode": {"season": 2, "number": 5}, "at": 1500.0})
    ep = trakt.scrobble_target("series", "tt0386676", "tt0386676:2:5")
    other = trakt.scrobble_target("series", "tt0386676", "tt0386676:2:6")
    assert t.viewed_near(ep, 1000.0) and not t.viewed_near(other, 1000.0)
    assert not t.viewed_near(ep, 1000.0 - 3600)  # fuera de los 10 min
