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
