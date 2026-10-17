"""«Para ti»: Trakt, TMDB, RAWG y tus juegos, con dobles de red (nunca sale a internet)."""

from __future__ import annotations

import json
import re
import time

import pytest
from fastapi.testclient import TestClient

from orbital import foryou as foryou_mod
from orbital.config import parse_config
from orbital.foryou import Cache, ForYou, game_item, hours_text, runtime_text, video_item
from orbital.library import charts, rawg, tmdb, trakt
from orbital.server import create_app


class FakeNet:
    """Responde por URL (expresión regular) y anota lo que se pidió."""

    def __init__(self) -> None:
        self.routes: list[tuple[str, str, object]] = []
        self.calls: list[tuple[str, str, dict | None]] = []

    def on(self, method: str, pattern: str, reply) -> FakeNet:
        self.routes.append((method, pattern, reply))
        return self

    def __call__(self, url, *, method="GET", headers=None, body=None, timeout=10):
        self.calls.append((method, url, body))
        for m, pattern, reply in self.routes:
            if m == method and re.search(pattern, url):
                return reply(url, body) if callable(reply) else reply
        return 404, None


def show(title, imdb, trakt_id=1, year=2022, episodes=None):
    return {"title": title, "year": year, "aired_episodes": episodes, "ids": {"imdb": imdb, "trakt": trakt_id}}


def movie(title, imdb, runtime=120, year=2020):
    return {"title": title, "year": year, "runtime": runtime, "ids": {"imdb": imdb, "trakt": 9}}


@pytest.fixture
def net(monkeypatch):
    fake = FakeNet()
    for module in (trakt, tmdb, rawg):
        monkeypatch.setattr(module, "http_json", fake)
    return fake


@pytest.fixture
def make_foryou(library):
    def make(trakt_keys=True, tmdb_key="", rawg_key="", linked=False):
        p = library.config.para_ti
        p.trakt_client_id, p.trakt_client_secret = ("cid", "secret") if trakt_keys else ("", "")
        p.tmdb_key, p.rawg_key = tmdb_key, rawg_key
        fy = ForYou(library.config, library)
        library.foryou = fy
        if linked:
            library.credentials.set(trakt.TOKENS_KEY, json.dumps({"access_token": "tok", "refresh_token": "ref",
                                                                  "expires_at": time.time() + 86400}))
        else:
            library.credentials.set(trakt.TOKENS_KEY, None)
        return fy
    return make


# ---------------------------------------------------------------- textos y piezas
def test_runtime_and_hours_read_like_a_console():
    assert runtime_text(164) == "2 h 44 min" and runtime_text(60) == "1 h" and runtime_text(45) == "45 min"
    assert runtime_text(None) is None
    assert hours_text(48 * 3600) == "48 h" and hours_text(5400) == "1 h 30 min" and hours_text(35 * 60) == "35 min"


def test_series_you_are_watching_continue_where_you_left():
    e = {**trakt.entry(show("Severance", "tt11280740"), "series"), "next": {"season": 2, "episode": 6}}
    item = video_item(e, "Sigues viéndola")
    assert item["action"] == "Ver la serie" and item["video_id"] == "tt11280740:2:6"
    assert item["detail"] == "Sigue T2 E6" and item["id"] == "cinemeta:series:tt11280740"
    fresh = video_item(trakt.entry(show("Andor", "tt9253284", episodes=24), "series"), "Recomendada")
    assert fresh["action"] == "Ver la serie" and fresh["video_id"] == "tt9253284:1:1" and fresh["detail"] == "24 episodios"
    film = video_item(trakt.entry(movie("Blade Runner 2049", "tt1856101", runtime=164), "movie"), "Recomendada")
    assert film["action"] == "Ver" and film["video_id"] == "tt1856101" and film["detail"] == "2 h 44 min"
    assert film["image"].endswith("/poster/medium/tt1856101/img")


def test_titles_without_imdb_are_skipped():
    assert trakt.entry({"title": "Sin IMDb", "ids": {"trakt": 3}}, "movie") is None
    assert trakt.entry({"title": "", "ids": {"imdb": "tt1"}}, "movie") is None
    mixed = trakt._typed([{"type": "movie", "movie": movie("A", "tt1")}, {"type": "show", "show": show("B", "tt2")},
                          {"type": "episode", "episode": {}}, {"type": "movie", "movie": movie("A", "tt1")}])
    assert [(m["kind"], m["imdb"]) for m in mixed] == [("movie", "tt1"), ("series", "tt2")]


def test_a_library_game_plays_from_here():
    item = game_item({"id": "steam:1145360", "title": "Hades", "playtime": 48 * 3600, "extra": {"logo": "/l.png"}}, "Tu más jugado")
    assert item["detail"] == "48 h jugadas" and item["action"] == "Jugar" and item["logo"] == "/l.png"
    assert game_item({"id": "x", "title": "Celeste", "playtime": 0}, "Sin estrenar")["detail"] == "Nunca lo has abierto"


# ---------------------------------------------------------------- caché
def test_cache_keeps_the_last_answer_when_the_network_fails():
    now = [0.0]
    cache = Cache(clock=lambda: now[0])
    assert cache.get("k", 10, lambda: [1]) == [1]
    now[0] = 100

    def broken():
        raise trakt.TraktError("sin red")

    assert cache.get("k", 10, broken) == [1]  # sin internet: lo de la última vez
    with pytest.raises(trakt.TraktError):
        cache.get("nuevo", 10, broken)


# ---------------------------------------------------------------- Trakt: conectar
def test_link_with_a_code_and_save_the_session(make_foryou, net, monkeypatch):
    fy = make_foryou()
    replies = iter([(400, None), (429, None), (200, {"access_token": "tok", "refresh_token": "ref", "expires_in": 86400, "created_at": time.time()})])
    net.on("POST", r"/oauth/device/code$", (200, {"device_code": "dev", "user_code": "4F7K2Q", "verification_url": "https://trakt.tv/activate", "interval": 5, "expires_in": 600}))
    net.on("POST", r"/oauth/device/token$", lambda url, body: next(replies))
    net.on("GET", r"/users/settings$", (200, {"user": {"username": "fer", "name": "Fernando"}}))
    events = []
    fy.catalog.events.subscribe(events.append)
    monkeypatch.setattr(foryou_mod.threading, "Thread", lambda **kw: type("T", (), {"start": lambda self: None})())
    code = fy.start_link()
    assert code["code"] == "4F7K2Q" and code["url"] == "trakt.tv/activate"
    waits = []
    assert fy._wait_link(fy._link, sleep=waits.append) == "linked"
    assert waits == [5, 5, 10]  # «más despacio» (429) espera más
    assert fy.trakt.linked and {"type": "trakt-linked", "name": "Fernando"} in events
    assert {"type": "foryou-changed"} in events


def test_an_expired_or_cancelled_code_stops_waiting(make_foryou, net):
    fy = make_foryou()
    code = trakt.DeviceCode("dev", "ABC", "https://trakt.tv/activate", 1, time.time() + 60)
    net.on("POST", r"/oauth/device/token$", (410, None))
    events = []
    fy.catalog.events.subscribe(events.append)
    fy._link = code
    assert fy._wait_link(code, sleep=lambda s: None) == "expired"
    assert events[-1]["type"] == "trakt-link-failed" and not fy.trakt.linked
    fy._link = None  # cancelado (B): deja de preguntar sin avisar de nada
    assert fy._wait_link(code, sleep=lambda s: None) == "cancelled"


def test_linking_without_the_app_keys_says_what_is_missing(make_foryou):
    fy = make_foryou(trakt_keys=False)
    with pytest.raises(ValueError, match="Ajustes › Cuentas"):
        fy.start_link()


def test_an_old_session_is_renewed_and_a_rejected_one_is_forgotten(make_foryou, net):
    fy = make_foryou(linked=True)
    fy.catalog.credentials.set(trakt.TOKENS_KEY, json.dumps({"access_token": "old", "refresh_token": "ref", "expires_at": time.time() + 60}))
    net.on("POST", r"/oauth/token$", (200, {"access_token": "new", "refresh_token": "ref2", "expires_in": 86400, "created_at": time.time()}))
    net.on("GET", r"/sync/watchlist", (200, []))
    assert fy.trakt.watchlist() == []
    assert any(c[1].endswith("/oauth/token") for c in net.calls)
    assert json.loads(fy.catalog.credentials.get(trakt.TOKENS_KEY))["access_token"] == "new"
    net.routes.insert(0, ("GET", r"/sync/watchlist", (401, None)))
    with pytest.raises(trakt.TraktAuthError):
        fy.trakt.watchlist()
    assert not fy.trakt.linked  # Trakt cerró la sesión: hay que volver a conectar


def test_your_series_bring_the_next_episode_and_skip_finished_ones(make_foryou, net):
    fy = make_foryou(linked=True)
    net.on("GET", r"/sync/history/episodes", (200, [
        {"show": show("Severance", "tt11280740", trakt_id=11)}, {"show": show("Severance", "tt11280740", trakt_id=11)},
        {"show": show("Breaking Bad", "tt0903747", trakt_id=22)}]))
    net.on("GET", r"/shows/11/progress/watched", (200, {"next_episode": {"season": 2, "number": 6}}))
    net.on("GET", r"/shows/22/progress/watched", (200, {"next_episode": None, "completed": 62}))
    items = fy.list_items("mine")
    assert [(i["title"], i["action"]) for i in items] == [("Severance", "Ver la serie")]


# ---------------------------------------------------------------- listas y servicios
CHART_LIST_IDS = ["chart:netflix", "jw:disney", "jw:hbo", "jw:prime", "jw:appletv", "jw:paramount"]


def test_only_the_services_you_have_show_up(make_foryou, net):
    # Netflix (Top 10 oficial) y JustWatch no piden clave: siempre están, aunque vengan vacíos sin red.
    assert [row["id"] for row in make_foryou(trakt_keys=False).lists()] == [*CHART_LIST_IDS, "mygames"]
    ids = [row["id"] for row in make_foryou().lists()]
    assert ids == ["trend", "popular", *CHART_LIST_IDS, "mygames"]  # Trakt sin cuenta: tendencias y popular sí
    net.on("GET", r"/users/me/lists$", (200, [{"name": "Ciencia ficción", "ids": {"trakt": 77}}]))
    linked = [row["id"] for row in make_foryou(linked=True, rawg_key="r").lists()]
    assert linked[:5] == ["recs", "mine", "watchlist", "estrenos", "list:77"]
    assert linked[-4:] == ["mygames", "rawg:new", "rawg:popular", "rawg:best"]


def test_streaming_platforms_come_from_tmdb_with_their_logo(make_foryou, net):
    fy = make_foryou(trakt_keys=False, tmdb_key="k")
    net.on("GET", r"/watch/providers/movie", (200, {"results": [
        {"provider_id": 8, "provider_name": "Netflix", "logo_path": "/n.png"},
        {"provider_id": 337, "provider_name": "Disney Plus", "logo_path": "/d.png"},
        {"provider_id": 1796, "provider_name": "Netflix basic with Ads", "logo_path": "/x.png"}]}))
    net.on("GET", r"/watch/providers/tv", (200, {"results": [{"provider_id": 1899, "provider_name": "HBO Max", "logo_path": "/h.png"}]}))
    net.on("GET", r"/discover/tv\?.*with_watch_providers=8", (200, {"results": [{"id": 1}, {"id": 2}]}))
    net.on("GET", r"/tv/1\?", (200, {"id": 1, "name": "Merlina", "first_air_date": "2022-11-23", "overview": "Merlina investiga…",
                                     "number_of_seasons": 2, "number_of_episodes": 16, "poster_path": "/p.jpg",
                                     "external_ids": {"imdb_id": "tt13443470"}}))
    net.on("GET", r"/tv/2\?", (200, {"id": 2, "name": "Sin IMDb", "external_ids": {}}))
    rows = {row["id"]: row for row in fy.lists()}
    assert list(rows) == [*CHART_LIST_IDS, "netflix", "disney", "hbo", "mygames"]
    assert rows["netflix"]["logo"] == "https://image.tmdb.org/t/p/w154/n.png" and rows["netflix"]["split"]
    items = fy.list_items("netflix", "series")
    assert [(i["title"], i["detail"], i["why"]) for i in items] == [("Merlina", "2 temporadas", "En Netflix")]
    assert items[0]["image"] == "https://image.tmdb.org/t/p/w500/p.jpg" and items[0]["overview"].startswith("Merlina")
    assert "watch_region=MX" in next(c[1] for c in net.calls if "/discover/" in c[1])


def test_netflix_top10_and_justwatch_lists_bring_rank_and_why(make_foryou, monkeypatch):
    fy = make_foryou(trakt_keys=False)
    monkeypatch.setattr(charts, "netflix_entries", lambda region, kind, **kw:
                        [{"imdb": "tt6933238", "title": "UNABOMBER", "rank": 1, "weeks": 2}] if kind == "movie" else [])
    monkeypatch.setattr(charts, "fetch_justwatch_chart", lambda brand, region, kind:
                        [{"imdb": "tt29355505", "title": "Toy Story 5", "year": 2026, "rank": 1}]
                        if brand == "disney" and kind == "movie" else [])
    items = fy.list_items("chart:netflix", "movie")
    assert [(i["title"], i["why"], i["rank"]) for i in items] == [("UNABOMBER", "N.º 1 en Netflix", 1)]
    jw_items = fy.list_items("jw:disney", "movie")
    assert [(i["title"], i["why"], i["rank"]) for i in jw_items] == [("Toy Story 5", "N.º 1 en Disney+", 1)]
    assert fy.list_items("jw:disney", "series") == []  # esa plataforma no trajo series: queda vacía, no tumba nada


def test_tmdb_platform_backup_always_comes_with_what_its_ranked_list_covers(make_foryou, net, monkeypatch):
    """El respaldo de TMDB va siempre (si JustWatch trae películas pero no series, con «Series» no quedaba nada de la
    plataforma), con `fallback_for` y `covered`: lo que su lista con puesto ya trae, sin salir a internet."""
    fy = make_foryou(trakt_keys=False, tmdb_key="k")
    net.on("GET", r"/watch/providers/movie", (200, {"results": [{"provider_id": 8, "provider_name": "Netflix", "logo_path": "/n.png"}]}))
    net.on("GET", r"/watch/providers/tv", (200, {"results": []}))
    calls = []
    monkeypatch.setattr(charts, "netflix_entries", lambda region, kind, **kw: calls.append(kind) or (
        [{"imdb": "tt1", "title": "X", "rank": 1, "weeks": 1}] if kind == "movie" else []))
    rows = {row["id"]: row for row in fy.lists()}
    assert rows["netflix"]["fallback_for"] == "chart:netflix" and rows["netflix"]["covered"] == []
    assert calls == []  # el riel no espera al Top 10 de Netflix
    fy.list_items("chart:netflix", "movie")
    fy.list_items("chart:netflix", "series")
    rows = {row["id"]: row for row in fy.lists()}
    assert rows["netflix"]["covered"] == ["movie"]  # trae películas, no series: el respaldo sigue sirviendo


def test_cache_can_answer_stale_and_refresh_in_the_background():
    """Lo vencido se devuelve al instante y se renueva aparte (el iPhone no espera 30 s y se rinde)."""
    import threading

    from orbital.foryou import Cache

    now = [0.0]
    cache = Cache(clock=lambda: now[0])
    assert cache.get("k", 10, lambda: "viejo", stale=True) == "viejo"  # la primera vez sí espera
    now[0] = 100
    done = threading.Event()
    assert cache.get("k", 10, lambda: (done.set(), "nuevo")[1], stale=True) == "viejo"
    assert done.wait(2)
    for _ in range(50):
        if cache.peek("k") == "nuevo":
            break
        threading.Event().wait(.02)
    assert cache.peek("k") == "nuevo"


def test_rawg_games_you_own_are_marked_and_play(make_foryou, net):
    fy = make_foryou(trakt_keys=False, rawg_key="r")
    net.on("GET", r"/api/games\?", (200, {"results": [
        {"id": 1, "name": "Hades", "released": "2020-09-17", "metacritic": 93, "background_image": "https://r/h.jpg"},
        {"id": 2, "name": "Hollow Knight", "released": "2017-02-24", "metacritic": 87},
        {"id": 3, "name": "Clair Obscur: Expedition 33", "released": "2025-04-24", "metacritic": 92, "background_image": "https://r/c.jpg"}]}))
    net.on("GET", r"/api/games/1/stores", (200, {"results": [{"store_id": 1, "url": "https://store.steampowered.com/app/1145360/Hades/"}]}))
    net.on("GET", r"/api/games/2/stores", (200, {"results": []}))
    net.on("GET", r"/api/games/3/stores", (200, {"results": [{"store_id": 1, "url": "https://store.steampowered.com/app/1903340/x/"}]}))
    items = {i["title"]: i for i in fy.list_items("rawg:best")}
    assert items["Hades"]["owned"] and items["Hades"]["id"] == "steam:1145360" and items["Hades"]["action"] == "Jugar"
    assert items["Hollow Knight"]["owned"]  # sin id de Steam en RAWG: por el nombre
    clair = items["Clair Obscur: Expedition 33"]
    assert not clair["owned"] and clair["action"] is None and clair["detail"] == "Metacritic 92"
    assert clair["image"].endswith("/1903340/library_600x900.jpg") and clair["image_fallback"] == "https://r/c.jpg"
    assert "ordering=-metacritic" in next(c[1] for c in net.calls if "/api/games?" in c[1])


def test_your_games_favorites_most_played_unopened_and_one_at_random(library, make_foryou):
    hades, hollow = library.get("steam:1145360"), library.get("steam:367520")
    library.set_prefs(hollow.id, favorite=True)
    library.state.record_launch(hades.id)
    library.state.record_session(hades.id, 3 * 3600)
    picks = make_foryou(trakt_keys=False).local_games(seed=1)
    by = {p["title"]: p["why"] for p in picks}
    assert by["Hollow Knight"] == "Tu favorito" and by["Hades"] == "Tu más jugado"
    assert "Sin estrenar" in by.values()  # las ROMs que nunca abriste
    assert all(p["kind"] == "game" and p["item"]["id"] == p["id"] for p in picks)


def test_not_interested_is_remembered(library, make_foryou):
    fy = make_foryou(trakt_keys=False)
    key = fy.local_games(seed=1)[0]["key"]
    fy.dismiss(key)
    assert key not in [p["key"] for p in fy.local_games(seed=1)]
    with pytest.raises(ValueError):
        fy.dismiss("cualquier cosa")


def test_the_mosaic_mixes_videos_and_games_and_survives_a_broken_service(make_foryou, net):
    fy = make_foryou()
    net.on("GET", r"/shows/trending", (200, [{"show": show(f"Serie {i}", f"tt{100 + i}")} for i in range(6)]))
    net.on("GET", r"/movies/trending", (500, None))  # Trakt falla en películas: el mosaico sigue
    mosaic = fy.mosaic()
    kinds = [m["kind"] for m in mosaic]
    assert kinds[:5] == ["series", "series", "series", "game", "game"]
    assert len({m["key"] for m in mosaic}) == len(mosaic)
    assert {m["why"] for m in mosaic if m["kind"] == "series"} == {"En tendencia"}


# ---------------------------------------------------------------- ficha
def test_details_bring_the_spanish_overview(make_foryou, net):
    fy = make_foryou(trakt_keys=False, tmdb_key="k")
    net.on("GET", r"/find/tt9253284", (200, {"tv_results": [{"id": 83867}]}))
    net.on("GET", r"/tv/83867\?", (200, {"id": 83867, "name": "Andor", "overview": "La historia de Cassian Andor.",
                                         "number_of_seasons": 2, "number_of_episodes": 24, "external_ids": {"imdb_id": "tt9253284"}}))
    info = fy.details("video:tt9253284", "series")
    assert info["overview"] == "La historia de Cassian Andor." and info["facts"] == [["Temporadas", "2"], ["Episodios", "24"]]


def test_rawg_details_prefer_the_spanish_steam_text(make_foryou, net, monkeypatch):
    fy = make_foryou(trakt_keys=False, rawg_key="r")
    net.on("GET", r"/api/games/3/stores", (200, {"results": [{"store_id": 1, "url": "https://store.steampowered.com/app/1903340/x/"}]}))
    monkeypatch.setattr(rawg, "steam_description", lambda appid: "Un juego de rol por turnos." if appid == 1903340 else "")
    assert fy.details("rawg:3") == {"overview": "Un juego de rol por turnos."}
    assert rawg.plain("<p>Hola&nbsp;<b>mundo</b></p>") == "Hola mundo"


# ---------------------------------------------------------------- API y config
def test_api_lists_details_dismiss_and_trakt(library, make_foryou):
    make_foryou(trakt_keys=False)
    with TestClient(create_app(library.config, library), base_url="http://127.0.0.1:8710", client=("127.0.0.1", 5000)) as c:
        data = c.get("/api/foryou").json()
        assert data["status"]["trakt"] == {"configured": False, "linked": False, "scrobble": {"last": None, "error": None}}
        assert [row["id"] for row in data["lists"]] == [*CHART_LIST_IDS, "mygames"] and data["mosaic"]
        assert c.get("/api/foryou/list", params={"id": "mygames"}).json()["items"]
        assert c.get("/api/foryou/list", params={"id": "nada"}).status_code == 404
        assert c.post("/api/foryou/dismiss", json={"key": "lo que sea"}).status_code == 422
        assert c.post("/api/foryou/dismiss", json={"key": data["mosaic"][0]["key"]}).json() == {"ok": True}
        assert c.post("/api/foryou/trakt/link").status_code == 409  # sin la aplicación de Trakt en config.yaml
        assert c.get("/api/foryou/details", params={"key": "nada"}).status_code == 404


def test_para_ti_config_checks_the_country():
    assert parse_config({"para_ti": {"region": "mx", "tmdb_key": " k "}}).para_ti.region == "MX"
    assert parse_config({"para_ti": {"tmdb_key": " k "}}).para_ti.tmdb_key == "k"
    with pytest.raises(ValueError, match="dos letras"):
        parse_config({"para_ti": {"region": "Mexico"}})


def test_the_mosaic_leaves_out_games_without_their_own_art(make_foryou, net):
    fy = make_foryou(trakt_keys=False)
    games = fy.local_games(seed=1)
    assert any(g["placeholder"] for g in games) and any(not g["placeholder"] for g in games)  # en Listas, todos
    in_mosaic = [m for m in fy.mosaic() if m["kind"] == "game"]
    assert in_mosaic and not any(m["placeholder"] for m in in_mosaic)  # el mosaico es de imágenes


# ---------------------------------------------------------------- sin claves: lo de tu Stremio
def stremio_title(meta_id, title, kind="series", continue_=False, in_library=True, video_id=None, last=0, source="stremio"):
    from orbital.library.models import LibraryItem

    prefix = "stremio" if source == "stremio" else f"cinemeta:{kind}"
    return LibraryItem(id=f"{prefix}:{meta_id}", title=title, source=source,
                       category="continue" if continue_ else ("stremio" if source == "stremio" else "series" if kind == "series" else "movies"),
                       last_watched=last, extra={"kind": kind, "meta_id": meta_id, "video_id": video_id, "in_library": in_library,
                                                 "year": "2019–", "runtime": "148 min", "description": "Sinopsis"})


def test_without_any_key_para_ti_still_has_movies_and_series(library, make_foryou):
    fy = make_foryou(trakt_keys=False)
    library.store.replace_source("stremio", [
        stremio_title("tt0903747", "Breaking Bad", continue_=True, video_id="tt0903747:2:6", last=5),
        stremio_title("tt1375666", "Inception", kind="movie", last=9),
        stremio_title("bad-id", "Sin IMDb", continue_=True)])
    library.store.replace_source("cinemeta", [stremio_title(f"tt{900 + i}", f"Popular {i}", kind=("movie", "series")[i % 2],
                                                            source="cinemeta") for i in range(6)])
    lists = [row["id"] for row in fy.lists()]
    assert lists[:3] == ["continue", "mylist", "cinemeta"] and lists[-1] == "mygames"
    bb = fy.list_items("continue")[0]
    assert (bb["title"], bb["action"], bb["video_id"], bb["why"]) == ("Breaking Bad", "Ver la serie", "tt0903747:2:6", "Seguir viendo")
    assert fy.list_items("mylist")[0]["detail"] == "2 h 28 min"
    assert {i["kind"] for i in fy.list_items("cinemeta", "movie")} == {"movie"}
    mosaic = fy.mosaic()
    assert {"series", "movie", "game"} <= {m["kind"] for m in mosaic}
    assert "video:tt0903747" in [m["key"] for m in mosaic[:3]]


def test_keys_written_in_settings_are_checked_saved_and_removed(library, make_foryou, net):
    fy = make_foryou(trakt_keys=False)
    net.on("GET", r"api_key=mala", (401, None))
    net.on("GET", r"/watch/providers/", (200, {"results": [{"provider_id": 8, "provider_name": "Netflix", "logo_path": "/n.png"}]}))
    with pytest.raises(tmdb.TmdbKeyError):
        fy.set_keys("tmdb", ["mala"])
    assert not fy.tmdb.configured and library.credentials.get("para_ti.tmdb_key") is None
    fy.set_keys("tmdb", [" buena "])
    assert fy.tmdb.key == "buena" and fy.status()["saved"] == ["tmdb"]
    with pytest.raises(ValueError, match="Client ID"):
        fy.set_keys("trakt", ["", "solo-secreto"])
    with pytest.raises(ValueError):
        fy.set_keys("trakt", ["con espacio", "x"])
    fy.set_keys("trakt", ["cid", "secret"])
    assert fy.trakt.configured
    fy.set_keys("tmdb", [""])
    assert not fy.tmdb.configured and fy.status()["saved"] == ["trakt"]
    with TestClient(create_app(library.config, library), base_url="http://127.0.0.1:8710", client=("127.0.0.1", 5000)) as c:
        assert c.post("/api/foryou/keys", json={"service": "rawg", "values": []}).status_code == 422
        net.on("GET", r"rawg.io/api/games\?key=mala", (401, None))
        assert c.post("/api/foryou/keys", json={"service": "rawg", "values": ["mala"]}).status_code == 422
        assert c.get("/api/settings").json()["para_ti"]["saved"] == ["trakt"]


def test_steam_games_carry_their_store_capsule_for_the_mosaic():
    item = game_item({"id": "steam:1313140", "title": "Cult of the Lamb", "playtime": 0, "extra": {}}, "Sin estrenar")
    assert item["steam_appid"] == 1313140 and item["wide"].endswith("/1313140/capsule_616x353.jpg")
    gba = game_item({"id": "emu:gba:1", "title": "Kirby", "playtime": 0, "extra": {"hero_lowres": True}}, "Al azar")
    assert gba["wide"] is None and gba["hero_weak"]


def test_renewing_tries_the_https_redirect_and_then_the_old_one(make_foryou, net):
    fy = make_foryou(linked=True)
    fy.catalog.credentials.set(trakt.TOKENS_KEY, json.dumps({"access_token": "old", "refresh_token": "ref", "expires_at": time.time() + 60}))
    sent = []

    def token(url, body):
        sent.append(body["redirect_uri"])
        ok = body["redirect_uri"] == "urn:ietf:wg:oauth:2.0:oob"  # una aplicación vieja
        return (200, {"access_token": "new", "refresh_token": "r", "expires_in": 86400, "created_at": time.time()}) if ok else (401, None)

    net.on("POST", r"/oauth/token$", token)
    net.on("GET", r"/sync/watchlist", (200, []))
    assert fy.trakt.watchlist() == []
    assert sent == ["https://localhost/", "https://localhost", "urn:ietf:wg:oauth:2.0:oob"]


def test_a_new_trakt_app_without_secret_links_and_renews(make_foryou, net):
    """developer.trakt.tv ya no da Client Secret (PKCE): con el Client ID basta y no se manda secreto."""
    fy = make_foryou(trakt_keys=False)
    fy.set_keys("trakt", ["cid-nuevo", ""])
    assert fy.trakt.configured and fy.status()["saved"] == ["trakt"]
    bodies = []
    net.on("POST", r"/oauth/device/token$", lambda url, body: bodies.append(body) or (200, {
        "access_token": "tok", "refresh_token": "ref", "expires_in": 60, "created_at": time.time()}))
    net.on("POST", r"/oauth/token$", lambda url, body: bodies.append(body) or (200, {
        "access_token": "new", "refresh_token": "r2", "expires_in": 86400, "created_at": time.time()}))
    net.on("GET", r"/sync/watchlist", (200, []))
    assert fy.trakt.poll_device(trakt.DeviceCode("dev", "ABC", "https://trakt.tv/activate", 1, time.time() + 60)) == "linked"
    assert fy.trakt.watchlist() == []  # la sesión dura 60 s: se renueva antes de pedir
    assert [b.get("client_id") for b in bodies] == ["cid-nuevo", "cid-nuevo"]
    assert not any("client_secret" in b for b in bodies)


# ---------------------------------------------------------------- tus complementos de Stremio
class FakeAddons:
    """addonCollectionGet de mentiras (como el de una cuenta real) y los catálogos que sirven."""

    def __init__(self):
        self.calls = []

    def request(self, method, params):
        self.calls.append(method)
        cat = lambda t, i, n, extra=None: {"type": t, "id": i, "name": n, "extra": extra or []}  # noqa: E731
        return {"addons": [
            {"transportUrl": "https://v3-cinemeta.strem.io/manifest.json", "manifest": {"name": "Cinemeta", "catalogs": [cat("movie", "top", "Popular")]}},
            {"transportUrl": "https://torrent-catalogs.strem.fun/manifest.json", "manifest": {"name": "Torrent Catalogs", "catalogs": [cat("movie", "top-movies", "Top seeded")]}},
            {"transportUrl": "https://www.strem.io/trakt/tok/manifest.json", "manifest": {"name": "Trakt Integration", "catalogs": [
                cat("movie", "watchlist", "Trakt Watchlist"), cat("series", "watchlist", "Trakt Watchlist"), cat("series", "recommendations", "Trakt Recommendations")]}},
            {"transportUrl": "https://x.baby-beamup.club/manifest.json", "manifest": {"name": "Streaming Catalogs", "catalogs": [
                cat("movie", "nfx", "Netflix"), cat("movie", "amp", "Prime Video"), cat("series", "amp", "Prime Video")]}},
            {"transportUrl": "https://tmdb.baby-beamup.club/manifest.json", "manifest": {"name": "The Movie Database Addon", "catalogs": [
                cat("movie", "tmdb.top", "Popular"), cat("movie", "tmdb.search", "Search", [{"name": "search", "isRequired": True}])]}},
        ]}


def test_stremio_addon_catalogs_join_para_ti(library, make_foryou, monkeypatch):
    import io

    fy = make_foryou(trakt_keys=False)
    library.credentials.set("stremio_auth_key", "auth")
    library.watch.stremio_client = FakeAddons()
    served = []

    def urlopen(req, timeout=10):
        served.append(req.full_url)
        metas = [{"id": "tt0903747", "type": "series", "name": "Breaking Bad", "releaseInfo": "2008–2013", "background": "https://b/bb.jpg"},
                 {"id": "kitsu:1", "name": "Sin IMDb"}]
        return io.BytesIO(json.dumps({"metas": metas}).encode())

    monkeypatch.setattr(foryou_mod.urllib.request, "urlopen", urlopen)
    titles = {a["title"]: a for a in fy.addon_catalogs()}
    # Lo genérico, los torrents y Cinemeta no; Netflix sí (sin TMDB no hay otra lista de Netflix).
    assert set(titles) == {"Watchlist", "Recommendations", "Netflix", "Prime Video"}
    assert titles["Prime Video"]["kinds"] == ["movie", "series"] and titles["Watchlist"]["addon"] == "Trakt Integration"
    rail = [row for row in fy.lists() if row["id"].startswith("addon:")]
    assert {row["title"] for row in rail} == set(titles) and next(r for r in rail if r["title"] == "Prime Video")["split"]
    items = fy.list_items(titles["Prime Video"]["id"], "series")
    assert [i["title"] for i in items] == ["Breaking Bad"] and items[0]["year"] == 2008 and items[0]["why"] == "En Prime Video"
    assert served[-1] == "https://x.baby-beamup.club/catalog/series/amp.json"
    # Sin Trakt conectado, el mosaico toma la watchlist y las recomendaciones del complemento.
    assert any(m["why"] in ("En tu watchlist", "Recomendada") for m in fy.mosaic())
    # Con Trakt conectado, las de «Trakt Integration» ya llegan de Trakt: no se repiten.
    fy2 = make_foryou(linked=True)
    assert {a["title"] for a in fy2.addon_catalogs()} == {"Netflix", "Prime Video"}


# ---------------------------------------------------------------- próximos estrenos
def test_upcoming_episodes_by_day_with_local_time(make_foryou, net):
    from datetime import datetime, timedelta

    fy = make_foryou(linked=True)
    now = datetime(2026, 10, 15, 12, 0).astimezone()
    at = lambda days, hour: (now.replace(hour=hour) + timedelta(days=days)).astimezone(tz=None).isoformat()  # noqa: E731
    utc = lambda local: datetime.fromisoformat(local).astimezone(tz=__import__("datetime").timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")  # noqa: E731
    row = lambda title, imdb, s, e, when, net_="NBC", ep_title="": {  # noqa: E731
        "first_aired": utc(when), "episode": {"season": s, "number": e, "title": ep_title},
        "show": {**show(title, imdb), "network": net_}}
    net.on("GET", r"/calendars/my/shows/", (200, [
        row("Ayer", "tt9", 1, 1, at(-1, 20)), row("SVU", "tt1", 28, 2, at(0, 19), ep_title="Midway"),
        row("Avatar", "tt2", 1, 4, at(1, 1), "Paramount+"), row("Avatar", "tt2", 1, 5, at(1, 1), "Paramount+"),
        row("Avatar", "tt2", 1, 6, at(1, 1), "Paramount+"), {"first_aired": "basura", "episode": {}, "show": None}, None,
        row("Lejos", "tt3", 1, 1, at(20, 20))]))
    items = fy.calendar(now=now)
    assert [(i["title"], i["day_label"], i["time"], i["episode_label"]) for i in items] == [
        ("SVU", "Hoy", "7:00 p. m.", "T28 E2"), ("Avatar", "Mañana", "Desde la madrugada", "T1 E4–E6")]
    assert items[0]["today"] and items[0]["why"] == "Sale hoy" and items[0]["action"] == "Ver la serie"
    assert ["Episodio", "T1 E4–E6"] in items[1]["facts"] and items[1]["overview"].startswith("T1 E4–E6 · 3 episodios")
    lists = {row["id"]: row for row in fy.lists()}
    assert lists["estrenos"]["views"][1]["label"] == "Semana"


def test_airing_today_is_empty_without_trakt_or_network(make_foryou, net):
    fy = make_foryou(trakt_keys=False)
    assert fy.airing_today() == {}
    fy = make_foryou(linked=True)
    net.on("GET", r"/calendars/my/shows/", (500, None))
    assert fy.airing_today() == {}


def test_chart_lists_say_what_they_measure_and_carry_movement(make_foryou, monkeypatch):
    """Netflix: «Top 10» con la semana; JustWatch: «Tendencias» (mide interés, no vistas). Cada título lleva rank,
    movement y new; el motivo es «N.º 3 en …»."""
    fy = make_foryou(trakt_keys=False)
    monkeypatch.setattr(charts, "netflix_entries", lambda region, kind, **kw: [
        {"imdb": "tt1", "title": "A", "rank": 1, "weeks": 3, "movement": 2, "new": False, "week": "2026-10-11"},
        {"imdb": "tt2", "title": "B", "rank": 2, "weeks": 1, "movement": None, "new": True, "week": "2026-10-11"}]
        if kind == "series" else [])
    monkeypatch.setattr(charts, "fetch_justwatch_chart", lambda brand, region, kind:
                        [{"imdb": "tt9", "title": "Z", "year": 2026, "rank": 1}] if brand == "disney" else [])
    items = fy.list_items("chart:netflix", "series")
    assert [(i["why"], i["rank"], i["movement"], i["new"]) for i in items] == [("N.º 1 en Netflix", 1, 2, False), ("N.º 2 en Netflix", 2, None, True)]
    rows = {r["id"]: r for r in fy.lists()}
    assert rows["chart:netflix"]["title"] == "Top 10 en Netflix"
    assert rows["chart:netflix"]["meta"].endswith("semana del 5 de oct")  # la semana termina el domingo 11
    assert rows["jw:disney"]["title"] == "Tendencias en Disney+" and rows["jw:disney"]["meta"].startswith("Tendencia en JustWatch")
    jw = fy.list_items("jw:disney", "movie")
    assert jw[0]["rank"] == 1 and jw[0]["movement"] is None and jw[0]["new"] is False  # primera foto: sin flechas


def test_my_list_is_stremio_and_watchlist_is_trakt():
    """Mismo glosario que el iPhone: «En Mi lista» (biblioteca de Stremio) y «En tu watchlist» (Trakt)."""
    import inspect

    from orbital import foryou
    src = inspect.getsource(foryou.ForYou._list)
    assert '"mylist": "En Mi lista"' in src and 'video_item(e, "En tu watchlist")' in src


def test_trakt_qr_opens_the_activation_page_and_setup_knows_about_para_ti(library):
    """Conectar Trakt: un QR con trakt.tv/activate (sin teclear la dirección). «Tu consola» también dice si falta Trakt."""
    with TestClient(create_app(library.config, library), base_url="http://127.0.0.1:8710", client=("127.0.0.1", 5000)) as c:
        res = c.get("/api/foryou/trakt/qr.svg")
        assert res.status_code == 200 and res.headers["content-type"].startswith("image/svg+xml") and "<svg" in res.text
        assert c.get("/api/setup").json()["trakt"] == library.foryou.status()["trakt"]


# ---------------------------------------------------------------- logos sin aire
def _logo_png(size=(80, 40), box=(10, 20, 70, 30)) -> bytes:
    import io

    from PIL import Image, ImageDraw

    image = Image.new("RGBA", size, (0, 0, 0, 0))
    if box[2] > box[0]:
        ImageDraw.Draw(image).rectangle((box[0], box[1], box[2] - 1, box[3] - 1), fill=(255, 255, 255, 255))
    out = io.BytesIO()
    image.save(out, "PNG")
    return out.getvalue()


def test_title_logos_lose_their_transparent_padding_and_are_kept(library, make_foryou, monkeypatch, tmp_path):
    """El logo de Midnight Mass trae casi la mitad de aire arriba: se recorta, así el hueco bajo la etiqueta es parejo."""
    import io

    from PIL import Image

    from orbital.library import iptv_logos

    asked: list[str] = []

    def download(url, timeout=8):
        asked.append(url)
        if "tt404" in url:
            raise OSError("404")
        return _logo_png()

    monkeypatch.setattr(iptv_logos, "download_logo", download)
    fy = make_foryou(trakt_keys=False)
    fy.logo_dir = tmp_path / "title-logos"
    png = fy.trimmed_logo("tt10574558")
    assert Image.open(io.BytesIO(png)).size == (60, 10)
    assert asked == ["https://images.metahub.space/logo/medium/tt10574558/img"]
    assert fy.trimmed_logo("tt10574558") == png and len(asked) == 1  # del disco
    assert (tmp_path / "title-logos" / "tt10574558.png").read_bytes() == png
    assert fy.trimmed_logo("tt404") is None and fy.trimmed_logo("tt404") is None and len(asked) == 2  # no insiste
    assert fy.trimmed_logo("../etc") is None and len(asked) == 2  # solo ids de IMDb
    with TestClient(create_app(library.config, library), base_url="http://127.0.0.1:8710", client=("127.0.0.1", 5000)) as c:
        library.foryou = fy
        ok = c.get("/api/foryou/logo/tt10574558")
        assert ok.status_code == 200 and ok.headers["content-type"] == "image/png" and ok.content == png
        assert c.get("/api/foryou/logo/tt404").status_code == 404


def test_trim_rejects_what_is_not_a_logo():
    from orbital.library import iptv_logos

    with pytest.raises(iptv_logos.LogoError):
        iptv_logos.trim(b"no soy una imagen")
    with pytest.raises(iptv_logos.LogoError):
        iptv_logos.trim(_logo_png(box=(0, 0, 0, 0)))


def test_the_first_mosaic_art_is_ready_before_it_is_seen(library, make_foryou, monkeypatch):
    from orbital import remote_art

    asked: list[tuple[str, int]] = []
    monkeypatch.setattr(remote_art, "sized", lambda url, width, *a, **k: asked.append((url, width)) or "ok")
    fy = make_foryou(trakt_keys=False)
    items = [{"image": "https://images.metahub.space/poster/medium/tt1/img"}, {"image": "img/placeholders/x.jpg"}]
    assert fy.prefetch_art(items) == 1
    assert asked == [("https://images.metahub.space/poster/medium/tt1/img", 360)]


def test_each_row_carries_genres_and_runtime_for_the_iphone():
    """«Decide por mí» del iPhone: cada fila trae sus géneros y lo que dura (en una serie, un episodio), si se saben."""
    from orbital import foryou
    from orbital.library import trakt

    e = trakt.entry({"title": "Severance", "year": 2022, "runtime": 55, "genres": ["drama", "science-fiction"],
                     "ids": {"imdb": "tt11280740", "trakt": 1}}, "series")
    item = foryou.video_item(e, "Porque sí")
    assert item["genres"] == ["Drama", "Science Fiction"] and item["runtime"] == 55
    bare = foryou.video_item({"imdb": "tt1", "kind": "movie", "title": "Sin datos"}, "x")
    assert "genres" not in bare and "runtime" not in bare  # sin el dato: se omite (el iPhone le pregunta a Cinemeta)
