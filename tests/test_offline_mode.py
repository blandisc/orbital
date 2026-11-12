"""Modo sin internet: lo que Orbital ya trajo se sigue viendo (las fichas, Para ti) aunque no haya conexión."""

import json
import time
import urllib.error

from orbital.library import cinemeta

REAL_GET = cinemeta.Cinemeta._get  # antes de que las pruebas lo cambien por uno sin red


def test_a_title_you_already_opened_still_shows_without_internet(tmp_path, monkeypatch):
    saved = tmp_path / "cinemeta-fichas.json"
    url = "https://v3-cinemeta.strem.io/meta/series/tt5753856.json"
    saved.write_text(json.dumps({url: [time.time() - 10 * 86400, {"meta": {"name": "Dark"}}]}), encoding="utf-8")
    client = cinemeta.Cinemeta()
    client.keep_on_disk(saved)

    def offline(*args, **kwargs):
        raise urllib.error.URLError("sin internet")

    monkeypatch.setattr(cinemeta.urllib.request, "urlopen", offline)
    assert REAL_GET(client, "/meta/series/tt5753856.json") == {"meta": {"name": "Dark"}}  # vencida, pero la misma ficha
    try:
        REAL_GET(client, "/meta/series/tt0000001.json")  # nunca abierta: se dice que no hay red
        raise AssertionError("debió fallar")
    except cinemeta.CinemetaError:
        pass


def test_the_tv_title_page_gets_tagline_rating_and_credits_like_the_iphone(monkeypatch):
    """La ficha como el iPhone: frase, clasificación (la de México y la de EE. UU., crudas) y «Dirección · Guion» o «Creada por»."""
    from orbital.library import tmdb

    client = tmdb.Tmdb("clave")
    movie = {"tagline": "Larga vida a la lucha.", "release_dates": {"results": [
        {"iso_3166_1": "US", "release_dates": [{"certification": "PG-13"}]}]},
        "credits": {"crew": [{"job": "Director", "name": "Denis Villeneuve"}, {"job": "Screenplay", "name": "Jon Spaihts"}],
                    "cast": [{"name": "Timothée Chalamet"}, {"name": "Zendaya"}, {"name": "Rebecca Ferguson"}, {"name": "Otro"}]}}
    monkeypatch.setattr(client, "_get", lambda path, **params: movie)
    x = client.extras("movie", 693134, "MX")
    assert x == {"tagline": "Larga vida a la lucha.", "ratings": {"MX": None, "US": "PG-13"}, "directors": ["Denis Villeneuve"],
                 "writers": ["Jon Spaihts"], "cast": ["Timothée Chalamet", "Zendaya", "Rebecca Ferguson"], "people": [],  # sin id, sin cara
                 "release": None, "languages": [], "studios": [], "collection": None}
    show = {"tagline": "", "created_by": [{"name": "Dan Erickson"}], "content_ratings": {"results": [{"iso_3166_1": "MX", "rating": "B15"}]},
            "credits": {"crew": [], "cast": [{"name": "Adam Scott"}]}}
    monkeypatch.setattr(client, "_get", lambda path, **params: show)
    assert client.extras("series", 95396, "MX") == {"tagline": None, "ratings": {"MX": "B15", "US": None}, "directors": ["Dan Erickson"],
                                                    "writers": [], "cast": ["Adam Scott"], "people": [],
                                                    "release": None, "languages": [], "studios": [], "collection": None}


def test_the_title_page_details_and_saga_like_the_iphone(monkeypatch):
    """«Los datos de la ficha» (estreno, idiomas, estudio o cadena) y la saga de una película, como el iPhone."""
    from orbital.library import tmdb

    client = tmdb.Tmdb("clave")
    movie = {"release_date": "2024-02-27", "spoken_languages": [{"iso_639_1": "en"}, {"iso_639_1": "es"}],
             "production_companies": [{"name": "Legendary"}, {"name": "Warner Bros."}],
             "belongs_to_collection": {"id": 726871, "name": "Dune: colección"}}
    monkeypatch.setattr(client, "_get", lambda path, **params: movie)
    x = client.extras("movie", 693134, "MX")
    assert (x["release"], x["languages"], x["studios"]) == ("2024-02-27", ["en", "es"], ["Legendary", "Warner Bros."])
    assert x["collection"] == {"id": 726871, "name": "Dune: colección"}
    show = {"first_air_date": "2022-02-18", "languages": ["en"], "networks": [{"name": "Apple TV+"}]}
    monkeypatch.setattr(client, "_get", lambda path, **params: show)
    y = client.extras("series", 95396, "MX")
    assert (y["release"], y["languages"], y["studios"], y["collection"]) == ("2022-02-18", ["en"], ["Apple TV+"], None)
    saga = {"parts": [{"id": 2, "release_date": "2024-02-27"}, {"id": 3}, {"id": 1, "release_date": "2021-09-15"}]}
    monkeypatch.setattr(client, "_get", lambda path, **params: saga)
    assert [p["id"] for p in client.collection_parts(726871)] == [1, 2, 3]


def test_seasons_say_how_long_until_they_start_like_the_iphone():
    """«Próximas temporadas»: cuánto falta, con las mismas palabras que la línea de tiempo del iPhone."""
    from datetime import date

    from orbital.library import tmdb

    assert [tmdb.season_when(d) for d in (0, 1, 24, 44, 50, 120)] == [
        "Ya es temporada", "Mañana", "En 24 días", "En 44 días", "En 2 meses", "En 4 meses"]
    navidad = tmdb.SEASON_BY_SLUG["navidad"]
    assert tmdb.season_days(navidad, date(2026, 11, 1)) == 24
    assert tmdb.season_days(navidad, date(2026, 12, 31)) == 0  # cruza el año
