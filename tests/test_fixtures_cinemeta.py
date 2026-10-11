"""Respuestas reales de Cinemeta grabadas (scripts/record_fixtures.py): si Stremio cambia su formato,
estas pruebas lo dicen sin tener que ir a internet."""

import json
from pathlib import Path

import pytest

from orbital.library import cinemeta

FIXTURES = Path(__file__).parent / "fixtures" / "cinemeta"


def load(name):
    return json.loads((FIXTURES / name).read_text(encoding="utf-8"))


def test_real_series_has_ordered_seasons_and_next_episode():
    meta = load("meta_series_tt0386676.json")
    found = cinemeta.seasons(meta)
    regular = [s for s in found if s["season"] != 0]
    assert regular and regular[0]["season"] == 1
    first = regular[0]["episodes"]
    assert [e["episode"] for e in first] == sorted(e["episode"] for e in first)
    assert all(e["title"] for e in first)
    assert cinemeta.next_episode(meta, first[0]["id"]) == first[1]["id"]


def test_real_movie_description():
    info = cinemeta.describe_meta(load("meta_movie_tt0816692.json"))
    assert info  # año, géneros, duración… lo que traiga
    assert all(value not in (None, "") for value in info.values())


@pytest.mark.parametrize("query", ["dune", "Dune"])
def test_real_search_mixes_movies_and_series(query):
    results = cinemeta.search_results(query, load("search_movie_dune.json"), load("search_series_dune.json"))
    kinds = [r["kind"] for r in results]
    assert "movie" in kinds and "series" in kinds
    assert len({r["meta_id"] for r in results}) == len(results)  # sin repetidos
    assert all(r["title"] for r in results)
