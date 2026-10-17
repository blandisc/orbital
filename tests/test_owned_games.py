"""Todos los juegos de tu cuenta: los de Steam sin instalar (con «Instalar») y, si se pueden jugar en la nube, como
juegos de GeForce NOW (la lista pública de NVIDIA)."""

from __future__ import annotations

import json

from orbital.library import geforcenow, steam


def test_los_juegos_de_tu_cuenta_de_steam_salen_del_arte_guardado_y_de_lo_que_has_abierto(tmp_path):
    cache = tmp_path / "appcache" / "librarycache"
    (cache / "620").mkdir(parents=True)
    (cache / "367520_library_600x900.jpg").write_bytes(b"x")
    (cache / "228980").mkdir()  # Steamworks Common Redistributables: no es juego
    config = tmp_path / "userdata" / "1" / "config"
    config.mkdir(parents=True)
    (config / "localconfig.vdf").write_text('"UserLocalConfigStore" { "Software" { "Valve" { "Steam" { "apps" {'
                                            ' "105600" { "LastPlayed" "1700000000" "Playtime" "90" } } } } } }')
    assert steam.owned_appids(tmp_path) == {"620", "367520", "105600"}
    item = steam.uninstalled_item("620", "Portal 2")
    assert item.uri == "steam://install/620" and item.extra["installed"] is False and item.subtitle == "Steam · Sin instalar"


def test_la_lista_publica_de_geforce_now_por_numero_de_steam(tmp_path, monkeypatch):
    games = [{"id": 1001, "title": "Portal 2", "steamUrl": "https://store.steampowered.com/app/620", "status": "AVAILABLE"},
             {"id": 1002, "title": "Fortnite", "steamUrl": "", "status": "AVAILABLE"},
             {"id": 1003, "title": "Viejo", "steamUrl": "https://store.steampowered.com/app/9", "status": "MAINTENANCE"}]
    monkeypatch.setattr(geforcenow, "fetch_public", lambda: games)
    path = tmp_path / "gfn.json"
    assert geforcenow.cloud_by_steam(path) == {"620": {"cms_id": "1001", "title": "Portal 2"}}
    monkeypatch.setattr(geforcenow, "fetch_public", lambda: None)  # sin red: la copia guardada
    assert geforcenow.cloud_by_steam(path, now=path.stat().st_mtime + geforcenow.PUBLIC_REFRESH + 1)["620"]["cms_id"] == "1001"
    assert json.loads(path.read_text(encoding="utf-8"))[0]["id"] == 1001


class Art:
    def appid(self, title):
        return None


def test_los_de_la_nube_entran_como_juegos_de_geforce_now_sin_repetir(tmp_path, monkeypatch):
    folder = tmp_path / "CEF"
    folder.mkdir()
    monkeypatch.setattr(geforcenow, "install_dir", lambda: folder)
    monkeypatch.setattr(geforcenow, "read_shortcuts", list)
    monkeypatch.setattr(geforcenow, "read_library_cache", lambda: [{"title": "Portal 2", "cms_id": "1001", "short_name": "p2",
                                                                    "store": "Steam", "banner": None, "hero": None}])
    cloud = [("620", {"cms_id": "1001", "title": "Portal 2"}), ("292030", {"cms_id": "2002", "title": "The Witcher 3: Wild Hunt"})]
    found = geforcenow.items(Art(), cloud)
    assert [i.title for i in found] == ["Portal 2", "The Witcher 3: Wild Hunt"]  # Portal 2 ya estaba: una sola vez
    witcher = found[1]
    assert witcher.id == "gfn:2002" and witcher.steam_appid == 292030 and "cmsId=2002" in witcher.argv[1]
    assert witcher.image and "292030" in witcher.image  # el arte de Steam por su número
