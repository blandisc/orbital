"""«¿Qué vemos?», «Tu año», una persona de TMDB y el historial de Trakt (como el iPhone)."""

from __future__ import annotations

import random
from datetime import UTC, datetime

from orbital import decide
from orbital.library import tmdb, trakt


def item(imdb, kind="movie", runtime=None, genres=None, episode=None):
    return {"meta_id": imdb, "kind": kind, "title": imdb, "runtime": runtime, "genres": genres or [], "episode": episode}


def test_the_time_comes_from_the_hour_like_the_iphone():
    assert decide.context_time(datetime(2026, 10, 14, 23, 30)) == "short"  # miércoles, muy noche
    assert decide.context_time(datetime(2026, 10, 14, 20, 0)) == "hour"
    assert decide.context_time(datetime(2026, 10, 16, 19, 0)) == "long"  # viernes en la noche
    assert decide.context_time(datetime(2026, 10, 18, 12, 0)) == "long"  # domingo


def test_three_that_fit_your_time_and_mood_and_never_what_you_watched():
    pool = [item("tt1", runtime=170, genres=["Drama"]), item("tt2", runtime=95, genres=["Comedy"]),
            item("tt3", runtime=30, genres=["Comedy"]), item("tt4", runtime=25, genres=["Horror"]),
            item("tt5", "series", runtime=22, genres=["Comedy"]), item("tt6", runtime=28, genres=["Comedy"])]
    picks = decide.choose(pool, time="short", mood="light", exclude={"tt6"}, rng=random.Random(1))
    assert {p["meta_id"] for p in picks} == {"tt3", "tt5", "tt2"}  # tt2 dura más: la más cercana, al final
    assert picks[-1]["meta_id"] == "tt2"
    only_series = decide.choose(pool, time="long", kind="series")
    assert [p["meta_id"] for p in only_series] == ["tt5"]


def test_what_you_follow_goes_first_and_details_fill_missing_genres():
    pool = [item("tt1"), item("tt2", "series", episode="T2 E3")]
    assert decide.choose(pool, time="long", rng=random.Random(3))[0]["meta_id"] == "tt2"
    sci = decide.choose([item("tt9")], time="long", genres={"Science Fiction"}, details={"tt9": {"genres": ["Sci-Fi"]}})
    assert [p["meta_id"] for p in sci] == ["tt9"]


def test_runtime_text():
    assert decide.runtime_minutes("2h 49min") == 169
    assert decide.runtime_minutes("169 min") == 169
    assert decide.runtime_minutes("45") == 45
    assert decide.runtime_minutes("") is None


def test_your_year_hours_streak_genre_map_and_top():
    utc = UTC
    at = lambda m, d, h=20: datetime(2026, m, d, h, tzinfo=utc).timestamp()  # noqa: E731
    plays = [
        {"at": at(1, 3), "kind": "movie", "imdb": "tt1", "title": "Dune", "minutes": 166, "genres": ["science-fiction"]},
        {"at": at(1, 4), "kind": "series", "imdb": "tt2", "title": "Severance", "minutes": 50, "genres": ["drama"], "season": 1, "episode": 1},
        {"at": at(1, 4, 22), "kind": "movie", "imdb": "tt3", "title": "Up", "minutes": 96, "genres": ["animation"]},
        {"at": at(1, 5), "kind": "series", "imdb": "tt2", "title": "Severance", "minutes": 54, "genres": ["drama"], "season": 1, "episode": 2},
        {"at": at(3, 1), "kind": "series", "imdb": "tt2", "title": "Severance", "minutes": 50, "genres": ["drama"], "season": 1, "episode": 3},
        {"at": datetime(2025, 12, 31, 20, tzinfo=utc).timestamp(), "kind": "movie", "imdb": "tt9", "title": "Viejo", "minutes": 100, "genres": []},
    ]
    r = decide.year_review(plays, 2026, utc)
    assert (r["hours"], r["movies"], r["episodes"], r["longest_streak"]) == (7, 2, 3, 3)
    assert r["top_genre"] == "drama"
    assert r["days"] == {"2026-01-03": "movies", "2026-01-04": "both", "2026-01-05": "series", "2026-03-01": "series"}
    assert [t["title"] for t in r["top"]][:1] == ["Severance"] and r["top"][0]["plays"] == 3
    assert [p["title"] for p in r["plays"]["2026-01-04"]] == ["Severance", "Up"]


def test_a_person_from_tmdb_most_known_first_with_posters_only(monkeypatch):
    raw = {"id": 7, "name": "Adam Scott", "profile_path": "/a.jpg", "biography": "", "birthday": "1973-04-03", "place_of_birth": "Santa Cruz",
           "combined_credits": {"cast": [
               {"id": 1, "media_type": "tv", "name": "Severance", "poster_path": "/s.jpg", "popularity": 90, "first_air_date": "2022-02-18", "character": "Mark"},
               {"id": 2, "media_type": "movie", "title": "Sin póster", "popularity": 99},
               {"id": 3, "media_type": "movie", "title": "Step Brothers", "poster_path": "/b.jpg", "popularity": 40, "release_date": "2008-07-25"},
           ], "crew": [{"id": 1, "media_type": "tv", "name": "Severance", "poster_path": "/s.jpg", "popularity": 90, "job": "Producer"}]}}
    calls = []

    def fake_get(self, path, **params):
        calls.append(params.get("language"))
        return raw if params.get("language") != "en-US" else {"biography": "An actor."}
    monkeypatch.setattr(tmdb.Tmdb, "_get", fake_get)
    p = tmdb.Tmdb("clave").person(7)
    assert p["born"] == "3 de abril de 1973" and p["place"] == "Santa Cruz"
    assert p["biography"] == "An actor."  # sin biografía en español, la de inglés
    assert [(c["title"], c["kind"], c["role"]) for c in p["credits"]] == [("Severance", "series", "Mark"), ("Step Brothers", "movie", None)]


def test_the_faces_of_a_title_directors_first_then_cast():
    raw = {"created_by": [], "credits": {"crew": [{"id": 9, "name": "Ben Stiller", "job": "Director", "profile_path": "/b.jpg"}],
                                         "cast": [{"id": 7, "name": "Adam Scott", "character": "Mark"}, {"id": 9, "name": "Ben Stiller", "character": "Él"}]}}
    people = tmdb.credit_people(raw)
    assert [(p["name"], p["role"]) for p in people] == [("Ben Stiller", "Dirección"), ("Adam Scott", "Mark")]
    assert people[1]["photo"] is None


def test_a_history_row_counts_episode_minutes():
    row = {"watched_at": "2026-01-04T20:00:00.000Z", "type": "episode",
           "show": {"title": "Severance", "ids": {"imdb": "tt2"}, "runtime": 55, "genres": ["drama"]},
           "episode": {"season": 1, "number": 2, "title": "Half Loop", "runtime": 50}}
    play = trakt.history_play(row)
    assert (play["kind"], play["minutes"], play["season"], play["episode"], play["episode_title"]) == ("series", 50, 1, 2, "Half Loop")
    assert trakt.history_play({"type": "movie", "movie": {"title": "X", "ids": {}}}) is None


def test_subtitle_sync_like_the_iphone():
    from orbital import player_ui

    assert [o["label"] for o in player_ui.sync_options(0)] == ["Antes", "A tiempo", "Después"]
    assert player_ui.sync_options(1.0)[1]["label"] == "+1,0 s" and player_ui.sync_options(-0.5)[1]["label"] == "-0,5 s"
    panel = player_ui.tracks_panel([], 1.0, sub_delay=0.5)
    assert panel.find("sync").options[1]["hint"] == "Volver a cero"


def test_a_dark_logo_comes_back_white_and_a_colored_one_untouched():
    import io

    from PIL import Image

    from orbital.foryou import whiten_if_dark

    def png(color):
        img = Image.new("RGBA", (20, 10), (0, 0, 0, 0))
        for x in range(4, 16):
            img.putpixel((x, 5), color)
        out = io.BytesIO()
        img.save(out, "PNG")
        return out.getvalue()
    dark = Image.open(io.BytesIO(whiten_if_dark(png((10, 10, 10, 255))))).convert("RGBA")
    assert dark.getpixel((8, 5)) == (255, 255, 255, 255) and dark.getpixel((0, 0))[3] == 0
    red = png((220, 30, 30, 255))
    assert whiten_if_dark(red) == red


def test_when_nothing_fits_the_shortest_come_first():
    """«Media hora» sin nada que quepa: antes salían al azar (películas de 107 y 113 min) y el texto decía que cabían."""
    pool = [{"meta_id": f"tt{n}", "kind": "movie", "runtime": minutes, "genres": ["Drama"]}
            for n, minutes in ((1, 113), (2, 44), (3, 107), (4, 61), (5, None))]
    picks = decide.choose(pool, time="short", rng=random.Random(7))
    assert [p["runtime"] for p in picks] == [44, 61, 107]
    assert not any(decide.fits(p["runtime"], "short") for p in picks)
