"""«Cambiar el arte» de una película o serie: elegir otro póster o fondo de TMDB, y que se vea en todos lados."""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from orbital.library import tmdb as tmdb_api
from orbital.library.models import LibraryItem
from orbital.server import create_app

POSTER = "https://image.tmdb.org/t/p/w500/otro.jpg"
WIDE = "https://image.tmdb.org/t/p/w1280/fondo.jpg"


def test_tmdb_da_primero_las_imagenes_en_espanol(monkeypatch):
    t = tmdb_api.Tmdb("clave")
    monkeypatch.setattr(t, "_get", lambda path, **p: {
        "posters": [{"file_path": "/en.jpg", "iso_639_1": "en", "vote_average": 9}, {"file_path": "/es.jpg", "iso_639_1": "es", "vote_average": 1}],
        "backdrops": [{"file_path": "/con-titulo.jpg", "iso_639_1": "es", "vote_average": 9}, {"file_path": "/b.jpg", "iso_639_1": None}]})
    found = t.images("series", 1)
    assert found["posters"] == ["https://image.tmdb.org/t/p/w500/es.jpg", "https://image.tmdb.org/t/p/w500/en.jpg"]
    # Los fondos sin texto van primero: encima ya va el logo.
    assert found["backgrounds"] == ["https://image.tmdb.org/t/p/w1280/b.jpg", "https://image.tmdb.org/t/p/w1280/con-titulo.jpg"]


def test_las_filas_de_tmdb_usan_el_fondo_sin_texto_en_la_misma_consulta(monkeypatch):
    t = tmdb_api.Tmdb("clave")
    asked = []

    def get(path, **p):
        asked.append(p)
        return {"id": 1, "title": "Dune", "imdb_id": "tt1160419", "backdrop_path": "/con-titulo.jpg", "images": {"backdrops": [
            {"file_path": "/sin-texto-b.jpg", "iso_639_1": None, "vote_average": 5.1},
            {"file_path": "/sin-texto-a.jpg", "iso_639_1": None, "vote_average": 5.6}]}}

    monkeypatch.setattr(t, "_get", get)
    assert t.details("movie", 1)["backdrop"] == "https://image.tmdb.org/t/p/w1280/sin-texto-a.jpg"
    assert len(asked) == 1 and "images" in asked[0]["append_to_response"] and asked[0]["include_image_language"] == "null"
    # Sin fondos sin texto, el de siempre.
    monkeypatch.setattr(t, "_get", lambda path, **p: {"id": 1, "title": "Dune", "backdrop_path": "/con-titulo.jpg", "images": {"backdrops": []}})
    assert t.details("movie", 1)["backdrop"] == "https://image.tmdb.org/t/p/w1280/con-titulo.jpg"


def test_elegir_arte_se_recuerda_y_se_ve_en_la_biblioteca_y_para_ti(library):
    show = LibraryItem(id="stremio:tt1", title="Futurama", category="continue", source="stremio", image="metahub.jpg",
                       hero="metahub-bg.jpg", extra={"meta_id": "tt1", "kind": "series"})
    library.store.replace([show])
    with pytest.raises(ValueError):
        library.watch.set_art("tt1", "poster", "https://evil.example.com/x.jpg")  # solo de TMDB
    library.watch.set_art("tt1", "poster", POSTER)
    library.watch.set_art("tt1", "background", WIDE)
    library.apply_art("tt1")
    item = library.get("stremio:tt1")
    assert item.image == POSTER and item.hero == WIDE
    assert library.foryou._with_art({"meta_id": "tt1", "image": "a", "hero": "b"}) == {"meta_id": "tt1", "image": POSTER, "hero": WIDE}
    library.watch.set_art("tt1", "poster", None)  # «El de siempre»
    assert library.watch.art_for("tt1") == {"background": WIDE}


def test_la_api_de_cambiar_el_arte(library, monkeypatch):
    monkeypatch.setattr(library.watch.localizer.tmdb, "key", "clave")
    monkeypatch.setattr(library.watch.localizer.tmdb, "find_id", lambda imdb, kind: 7)
    monkeypatch.setattr(library.watch.localizer.tmdb, "images", lambda kind, tmdb_id: {"posters": [POSTER], "backgrounds": [WIDE]})
    with TestClient(create_app(library.config, library), base_url="http://127.0.0.1:8710", client=("127.0.0.1", 5000)) as c:
        got = c.get("/api/stremio/art", params={"kind": "series", "id": "tt1"}).json()
        assert got["posters"] == [POSTER] and got["current"] == {}
        assert c.post("/api/stremio/art", json={"meta_id": "tt1", "which": "poster", "url": POSTER}).json()["art"] == {"poster": POSTER}
        assert c.post("/api/stremio/art", json={"meta_id": "tt1", "which": "logo", "url": POSTER}).status_code == 400
        assert c.get("/api/stremio/art", params={"kind": "juego", "id": "tt1"}).status_code == 400
