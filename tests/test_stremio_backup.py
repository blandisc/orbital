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


class TraktLists:
    """Tu Trakt con listas personales, de mentira: guarda lo que se agrega y lo devuelve al leer la lista."""
    linked = True

    def __init__(self, drop=()):
        self.lists, self.items, self.drop = {}, {}, set(drop)

    def named_list(self, name, create=False):
        if name not in self.lists and create:
            self.lists[name] = str(100 + len(self.lists))
        return self.lists.get(name)

    def add_list_items(self, list_id, items):
        self.items.setdefault(list_id, []).extend((k, i) for k, i in items if i not in self.drop)

    def list_items(self, list_id):
        return [{"imdb": i, "kind": k} for k, i in self.items.get(list_id, [])]


def test_mi_lista_de_stremio_pasa_a_su_lista_de_trakt_y_luego_se_desconecta(watch, monkeypatch):
    """Fernando, 4 nov 2026: «Crear una nueva lista en Trakt que se llame Mi lista Stremio. Pásalo todo y luego quítala.»"""
    trakt = TraktLists()
    monkeypatch.setattr(watch.trakt_library, "client", lambda: trakt)
    done = watch.move_stremio_to_trakt_list()
    # Dune y Severance (lo quitado de Stremio no viaja) van a la lista personal, no a la watchlist.
    assert trakt.lists == {"Mi lista Stremio": "100"} and trakt.items["100"] == [("movie", "tt1"), ("series", "tt2")]
    assert done == {"stremio": 2, "in_list": 2, "missing": [], "unlinked": True, "list_id": "100"}
    assert not watch.stremio_linked  # llegó todo: la cuenta se quitó de la TV (en Stremio no se borró nada)
    assert watch.stremio_client.saved == []


def test_si_algo_no_llega_no_se_desconecta(watch, monkeypatch):
    trakt = TraktLists(drop={"tt2"})
    monkeypatch.setattr(watch.trakt_library, "client", lambda: trakt)
    done = watch.move_stremio_to_trakt_list()
    assert done["missing"] == ["tt2"] and done["in_list"] == 1 and not done["unlinked"]
    assert watch.stremio_linked  # faltó uno: la cuenta se queda para no perderlo
    monkeypatch.setattr(watch.trakt_library, "client", lambda: None)
    with pytest.raises(ValueError, match="Primero conecta Trakt"):
        watch.move_stremio_to_trakt_list()


def test_trakt_agrega_de_cien_en_cien(monkeypatch):
    from orbital.library import trakt as trakt_api

    client = trakt_api.Trakt("id", "secreto", credentials=None)
    sent = []
    monkeypatch.setattr(client, "_send", lambda method, path, body=None, errors=None: sent.append((method, path, body)))
    items = [("movie", f"tt{i}") for i in range(150)] + [("series", "tt999"), ("movie", "kitsu:1")]
    client.add_list_items("100", items)
    assert [len(b.get("movies", [])) + len(b.get("shows", [])) for _, _, b in sent] == [100, 51]  # sin lo que no es de IMDb
    assert sent[0][:2] == ("POST", "/users/me/lists/100/items") and sent[1][2]["shows"] == [{"ids": {"imdb": "tt999"}}]
    with pytest.raises(trakt_api.TraktError):
        client.add_list_items("../x", items)


def test_trakt_lee_todas_las_paginas_de_una_lista(monkeypatch):
    """4 nov 2026: «Mi lista Stremio» tenía 210 y se leían 100 (Trakt da las listas de cien en cien)."""
    from orbital.library import trakt as trakt_api

    client = trakt_api.Trakt("id", "secreto", credentials=None)
    rows = [{"type": "movie", "movie": {"title": f"P{i}", "year": 2000, "ids": {"imdb": f"tt{i:07d}"}}} for i in range(210)]
    pages = []

    def get(path, auth=True, **params):
        pages.append(params["page"])
        start = (params["page"] - 1) * params["limit"]
        return rows[start:start + params["limit"]]

    monkeypatch.setattr(client, "_get", get)
    assert len(client.list_items("38004492")) == 210 and pages == [1, 2, 3]


def test_mi_lista_de_trakt_se_lee_completa(monkeypatch):
    """4 nov 2026: la watchlist de Fernando tiene 318 y Mi lista enseñaba 100 (Trakt da cien por página)."""
    from orbital.library import trakt as trakt_api

    client = trakt_api.Trakt("id", "secreto", credentials=None)
    rows = [{"type": "movie", "listed_at": f"2026-01-01T00:{i // 60:02d}:{i % 60:02d}Z",
             "movie": {"title": f"P{i}", "year": 2000, "ids": {"imdb": f"tt{i:07d}"}}} for i in range(318)]

    def get(path, auth=True, **params):
        start = (params["page"] - 1) * params["limit"]
        return rows[start:start + params["limit"]]

    monkeypatch.setattr(client, "_get", get)
    assert len(client.watchlist()) == 318 and len(client.watchlist_rows()) == 318
