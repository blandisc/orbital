"""Stremio como respaldo («La TV sin Stremio», corte S5; SS-8): traer lo tuyo una vez y, desde ahí, Seguir viendo y Mi
lista salen de Trakt; Stremio solo recibe copia si la dejas. Sin Trakt, Stremio sigue siendo tu lista (P-4)."""

import pytest

from orbital.library import addons

TORRENTIO = "https://torrentio.strem.fun/sort=seeders|language=latino|realdebrid=KEY/manifest.json"


class Account:
    """Tu cuenta de Stremio, de mentira."""

    def __init__(self):
        self.saved, self.reads = [], 0

    def library(self, auth_key):
        self.reads += 1
        return [
            {"_id": "tt1", "type": "movie", "name": "Dune", "removed": False, "temp": False, "state": {}},
            {"_id": "tt2", "type": "series", "name": "Severance", "removed": False, "temp": False, "state": {}},
            {"_id": "tt3", "type": "movie", "name": "Vista y quitada", "removed": True, "temp": False, "state": {}},
        ]

    def library_item(self, auth_key, item_id):
        return {"_id": item_id, "type": "movie", "name": item_id, "removed": False, "temp": False, "state": {}}

    def save_library_item(self, auth_key, item):
        self.saved.append(item["_id"])

    def request(self, method, params):
        return {"addons": [{"transportUrl": TORRENTIO, "manifest": {"id": "t", "name": "Torrentio RD"}}]}


class Trakt:
    linked = True

    def __init__(self):
        self.added = []

    def watchlist(self):
        return [{"imdb": "tt2", "kind": "series", "title": "Severance"}]

    def set_watchlist(self, kind, imdb, add):
        self.added.append((kind, imdb, add))


@pytest.fixture
def watch(tmp_path, monkeypatch):
    from orbital.catalog import Catalog
    from orbital.config import parse_config
    from orbital.credentials import Credentials
    from tests.conftest import FakeLauncher

    monkeypatch.setattr(addons, "fetch_json", lambda url, timeout=0: {"name": "x", "resources": ["stream"], "types": ["movie"]})
    cfg = parse_config({"steam": {"enabled": False}, "esde": {"enabled": False}, "detect": {"enabled": False},
                        "stremio": {"executable": "stremio-test"}})
    w = Catalog(cfg, FakeLauncher(), credentials=Credentials(tmp_path / "secrets.json"), stremio_client=Account()).watch
    w.credentials.set("stremio_auth_key", "clave")
    monkeypatch.setattr(w, "refresh_trakt", lambda background=False, force=False: True)
    return w


def test_without_trakt_stremio_stays_your_list(watch):
    with pytest.raises(ValueError, match="Primero conecta Trakt"):
        watch.bring_from_stremio()
    assert watch.setting("stremio_role", "both") == "both"


def test_bring_once_then_stremio_is_only_a_backup(watch, monkeypatch):
    trakt = Trakt()
    monkeypatch.setattr(watch.trakt_library, "client", lambda: trakt)
    monkeypatch.setattr(type(watch.trakt_library), "active", property(lambda self: True))
    done = watch.bring_from_stremio()
    # Dune pasa a Mi lista de Trakt; Severance ya estaba; lo que quitaste de Stremio no viaja.
    assert done == {"addons": 0, "my_list": 1, "already": 1} and trakt.added == [("movie", "tt1", True)]
    assert watch.addon_list.imported_at and watch.setting("stremio_role") == "backup" and watch.stremio_backup
    reads = watch.stremio_client.reads
    assert watch.refresh_stremio() is False and watch.stremio_client.reads == reads  # ya no se lee
    watch._save_stremio("clave", {"_id": "tt9"})
    assert watch.stremio_client.saved == ["tt9"]  # la copia sigue, si la dejas
    watch.state.set_setting("stremio_copy", False)
    watch._save_stremio("clave", {"_id": "tt10"})
    assert watch.stremio_client.saved == ["tt9"]  # sin copia: nada le llega a Stremio
    watch.state.set_setting("stremio_role", "both")
    assert not watch.stremio_backup  # «Volver a leer tu Stremio»
