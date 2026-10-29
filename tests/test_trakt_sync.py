"""Trakt como la fuente de lo tuyo en la consola (desacoplar Stremio, corte E): Seguir viendo, Mi lista y las reglas de
escritura (respaldo cada 5 min, tope de 79.9 %, mínimo de 1 %). Con un Trakt falso: nunca sale a internet."""

from __future__ import annotations

import json
import re
import time

from orbital.library import trakt
from orbital.library.models import LibraryItem
from orbital.scrobble import TraktScrobbler, plan
from orbital.trakt_sync import TraktLibrary, merge

NOW = 1_800_000_000.0


def stremio(meta_id, kind="movie", category="continue", when=NOW - 1000, video_id=None, in_library=False, progress=.4):
    return LibraryItem(id=f"stremio:{meta_id}", title=meta_id, category=category, source="stremio", progress=progress,
                       last_watched=when, extra={"kind": kind, "meta_id": meta_id, "video_id": video_id or meta_id,
                                                 "in_library": in_library, "description": "De Stremio"})


def paused(meta_id, when, percent=40.0, kind="movie", video_id=None, runtime=7200.0, row_id=1):
    return {"id": row_id, "kind": kind, "meta_id": meta_id, "video_id": video_id or meta_id, "title": f"T {meta_id}",
            "year": 2020, "percent": percent, "paused_at": when, "runtime": runtime}


# ---------------------------------------------------------------- unir Stremio y Trakt
def test_what_you_paused_on_the_iphone_shows_up_in_continue_watching():
    out = merge([], [paused("tt1", NOW)], {}, {}, None)
    assert [(i.id, i.category, i.progress, i.last_watched, i.source) for i in out] == [
        ("stremio:tt1", "continue", .4, NOW, "stremio")]
    assert out[0].subtitle == "Película · quedan 1 h 12 min"
    assert out[0].image.endswith("/tt1/img")


def test_the_most_recent_wins_per_title():
    items = [stremio("tt1", when=NOW), stremio("tt2", when=NOW - 500)]
    out = merge(items, [paused("tt1", NOW - 10, percent=70), paused("tt2", NOW, percent=55)], {}, {}, None)
    by = {i.extra["meta_id"]: i for i in out}
    assert by["tt1"].progress == .4  # Stremio es más nuevo (lo viste en la consola después)
    assert by["tt2"].progress == .55 and by["tt2"].extra["description"] == "De Stremio"  # conserva sus datos
    assert items[1].progress == .4  # la biblioteca de Stremio no se toca


def test_a_show_you_finished_an_episode_of_points_to_the_next_one():
    items = [stremio("tt9", kind="series", when=NOW - 5000, video_id="tt9:2:5")]
    shows = {"tt9": {"imdb": "tt9", "title": "Serie", "next": (2, 6), "last_watched": NOW, "watched": {(2, 5)}}}
    out = merge(items, [], shows, {}, None)
    assert out[0].extra["video_id"] == "tt9:2:6" and out[0].subtitle == "Sigue: T2 E6" and out[0].progress is None


def test_a_paused_episode_beats_an_older_finished_one():
    shows = {"tt9": {"imdb": "tt9", "title": "Serie", "next": (2, 6), "last_watched": NOW - 100, "watched": set()}}
    out = merge([], [paused("tt9", NOW, kind="series", video_id="tt9:2:6", percent=30, runtime=2400)], shows, {}, None)
    assert out[0].extra["video_id"] == "tt9:2:6" and out[0].progress == .3


def test_what_you_finished_elsewhere_leaves_continue_watching():
    items = [stremio("tt1", when=NOW - 100), stremio("tt9", kind="series", when=NOW - 100, video_id="tt9:1:1")]
    shows = {"tt9": {"imdb": "tt9", "title": "Serie", "next": None, "last_watched": NOW, "watched": set()}}
    out = merge(items, [], shows, {"tt1": NOW}, None)
    assert [i.category for i in out] == ["stremio", "stremio"]


def test_dismissed_titles_do_not_come_back_with_older_trakt_data():
    out = merge([], [paused("tt1", NOW - 10)], {}, {}, None, dismissed=lambda imdb: NOW)
    assert out == []
    out = merge([], [paused("tt1", NOW + 10)], {}, {}, None, dismissed=lambda imdb: NOW)
    assert len(out) == 1  # lo pausaste otra vez después: sí vuelve


def test_my_list_is_the_trakt_watchlist():
    items = [stremio("tt1", category="stremio", in_library=True), stremio("tt2", category="stremio")]
    watchlist = [{"kind": "movie", "imdb": "tt2", "title": "Dos", "listed_at": NOW},
                 {"kind": "series", "imdb": "tt3", "title": "Tres", "listed_at": NOW - 5}]
    out = merge(items, [], {}, {}, watchlist)
    assert {i.extra["meta_id"]: i.extra["in_library"] for i in out} == {"tt1": False, "tt2": True, "tt3": True}
    assert merge(items, [], {}, {}, None)[0].extra["in_library"] is True  # sin leer la watchlist, se queda como estaba


# ---------------------------------------------------------------- leer solo lo que cambió
class FakeTrakt:
    linked = True

    def __init__(self):
        self.stamps = {"paused": "a", "watched": "a", "watchlist": "a"}
        self.calls = []

    def last_activities(self):
        self.calls.append("activities")
        return dict(self.stamps)

    def playback_rows(self):
        self.calls.append("playback")
        return [paused("tt1", NOW)]

    def watchlist_rows(self):
        self.calls.append("watchlist")
        return []

    def watched_movies(self):
        self.calls.append("movies")
        return {}

    def recent_shows(self, limit):
        self.calls.append("shows")
        return [{"imdb": "tt9", "title": "Serie", "kind": "series"}]

    def show_progress(self, imdb):
        self.calls.append(f"progress:{imdb}")
        return {"next": (1, 2), "last_watched": NOW, "watched": {(1, 1)}}


def test_only_what_changed_is_downloaded_again():
    fake = FakeTrakt()
    lib = TraktLibrary(lambda: fake, clock=lambda: NOW)
    assert lib.refresh() is True
    assert fake.calls == ["activities", "playback", "movies", "shows", "progress:tt9", "watchlist"]
    fake.calls.clear()
    assert lib.refresh() is False and fake.calls == ["activities"]
    fake.stamps["paused"] = "b"
    fake.calls.clear()
    assert lib.refresh() is True and fake.calls == ["activities", "playback"]
    assert lib.watched_episodes("tt9") == ({"tt9:1:1"}, ("tt9:1:2", NOW))
    assert lib.in_watchlist("tt1") is False


def test_without_trakt_nothing_changes():
    lib = TraktLibrary(lambda: None)
    items = [stremio("tt1")]
    assert lib.merged(items) is items and lib.refresh() is False


# ---------------------------------------------------------------- piezas de la API
def test_parsers_for_playback_progress_and_activities():
    row = {"id": 7, "type": "episode", "progress": 45.098, "paused_at": "2026-10-29T10:00:00.000Z",
           "episode": {"season": 2, "number": 5, "runtime": 40}, "show": {"title": "The Office", "year": 2005,
                                                                          "ids": {"imdb": "tt0386676"}}}
    found = trakt.playback_row(row)
    assert found["id"] == 7 and found["video_id"] == "tt0386676:2:5" and found["runtime"] == 2400
    progress = trakt.show_progress({"last_watched_at": "2026-10-29T10:00:00.000Z", "next_episode": {"season": 2, "number": 6},
                                    "seasons": [{"number": 2, "episodes": [{"number": 5, "completed": True},
                                                                           {"number": 6, "completed": False}]}]})
    assert progress["next"] == (2, 6) and progress["watched"] == {(2, 5)}
    stamps = trakt.activity_stamps({"movies": {"paused_at": "x", "watched_at": "y"}, "episodes": {"paused_at": "z"},
                                    "watchlist": {"updated_at": "w"}})
    assert stamps["paused"] == "x|z" and stamps["watched"] == "y|" and stamps["watchlist"].startswith("w")
    assert trakt.history_body({"show": {"ids": {"imdb": "tt1"}}, "episode": {"season": 1, "number": 2}}) == {
        "shows": [{"ids": {"imdb": "tt1"}, "seasons": [{"number": 1, "episodes": [{"number": 2}]}]}]}


# ---------------------------------------------------------------- escribir como el iPhone
MOVIE = {"kind": "movie", "meta_id": "tt1375666", "video_id": "tt1375666", "title": "Origen"}


def test_trakt_never_sees_more_than_79_9_until_it_is_really_watched():
    assert plan("pause", MOVIE, 85 * 60, 100 * 60) == (["pause"], 79.9)  # 85 %: aún no es visto (90 %)
    assert plan("stop", MOVIE, 85 * 60, 100 * 60) == (["stop"], 79.9)
    assert plan("stop", MOVIE, 95 * 60, 100 * 60) == (["stop"], 95.0)  # visto: el avance real
    assert plan("stop", {**MOVIE, "finished": True}, 75 * 60, 100 * 60) == (["stop"], 80.0)  # créditos al 75 %
    assert plan("pause", MOVIE, 30, 100 * 60) is None  # menos del 1 %: Trakt contesta 422
    assert plan("start", MOVIE, 30, 100 * 60) == (["start"], 0.5)
    assert plan("checkpoint", MOVIE, 50 * 60, 100 * 60) == (["start", "pause"], 50.0)


class Creds:
    def __init__(self):
        self.data = {trakt.TOKENS_KEY: json.dumps({"access_token": "tok", "refresh_token": "ref",
                                                   "expires_at": time.time() + 86400})}

    def get(self, key):
        return self.data.get(key)

    def set(self, key, value):
        self.data[key] = value


def test_the_five_minute_backup_is_start_then_pause_and_the_next_pause_starts_again(monkeypatch):
    calls = []

    def net(url, *, method="GET", headers=None, body=None, timeout=10):
        calls.append((re.sub(r".*/scrobble/", "", url), body["progress"]))
        return 201, {}

    monkeypatch.setattr(trakt, "http_json", net)
    t = trakt.Trakt("cid", "", Creds())
    slept = []
    s = TraktScrobbler(lambda: t, sleep=slept.append)
    saved = []
    s.on_saved = lambda: saved.append(1)
    s.event("start", MOVIE, 600, 6000)
    s.event("checkpoint", MOVIE, 900, 6000)
    s.event("pause", MOVIE, 1200, 6000)
    s.wait()
    assert calls == [("start", 10.0), ("start", 15.0), ("pause", 15.0), ("start", 20.0), ("pause", 20.0)]
    assert slept == [2.0, 2.0] and len(saved) == 2


# ---------------------------------------------------------------- la consola completa (Inicio, Mi lista, ficha)
def test_the_console_rows_and_title_page_read_trakt(library, monkeypatch):
    from orbital.library import cinemeta

    meta = {"id": "tt9", "name": "Serie", "type": "series", "videos": [
        {"id": "tt9:1:1", "season": 1, "episode": 1, "title": "Uno"}, {"id": "tt9:1:2", "season": 1, "episode": 2, "title": "Dos"}]}
    monkeypatch.setattr(cinemeta.Cinemeta, "_get", lambda self, path, base=None: {"meta": dict(meta)})
    fake = FakeTrakt()
    saved = []
    fake.set_watchlist = lambda kind, imdb, add: saved.append((kind, imdb, add))
    library.watch.trakt_library.trakt = lambda: fake
    monkeypatch.setattr(library.watch, "refresh_stremio", lambda background=False: None)
    assert library.watch.refresh_trakt() is True
    rows = {r["id"]: r for r in library.grouped()}
    assert {i["id"] for i in rows["continue"]["items"]} == {"stremio:tt1", "stremio:tt9"}

    details = library.watch.title_details("series", "tt9")
    assert details["watched"] == ["tt9:1:1"] and details["resume"]["video_id"] == "tt9:1:2"
    assert details["in_library"] is False

    library.watch.set_in_library("series", "tt9", True)  # sin cuenta de Stremio: solo Trakt
    assert saved == [("series", "tt9", True)]
