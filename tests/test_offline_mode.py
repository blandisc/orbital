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
    """La ficha como el iPhone: frase, clasificación (la de tu país; si no, EE. UU.) y «Dirección · Guion» o «Creada por»."""
    from orbital.library import tmdb

    client = tmdb.Tmdb("clave")
    movie = {"tagline": "Larga vida a la lucha.", "release_dates": {"results": [
        {"iso_3166_1": "US", "release_dates": [{"certification": "PG-13"}]}]},
        "credits": {"crew": [{"job": "Director", "name": "Denis Villeneuve"}, {"job": "Screenplay", "name": "Jon Spaihts"}],
                    "cast": [{"name": "Timothée Chalamet"}, {"name": "Zendaya"}, {"name": "Rebecca Ferguson"}, {"name": "Otro"}]}}
    monkeypatch.setattr(client, "_get", lambda path, **params: movie)
    x = client.extras("movie", 693134, "MX")
    assert x == {"tagline": "Larga vida a la lucha.", "certification": "PG-13", "directors": ["Denis Villeneuve"],
                 "writers": ["Jon Spaihts"], "cast": ["Timothée Chalamet", "Zendaya", "Rebecca Ferguson"]}
    show = {"tagline": "", "created_by": [{"name": "Dan Erickson"}], "content_ratings": {"results": [{"iso_3166_1": "MX", "rating": "B15"}]},
            "credits": {"crew": [], "cast": [{"name": "Adam Scott"}]}}
    monkeypatch.setattr(client, "_get", lambda path, **params: show)
    assert client.extras("series", 95396, "MX") == {"tagline": None, "certification": "B15", "directors": ["Dan Erickson"],
                                                    "writers": [], "cast": ["Adam Scott"]}
