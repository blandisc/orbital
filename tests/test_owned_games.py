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


def test_los_juegos_que_no_estan_en_steam_traen_su_ficha_de_wikidata(tmp_path, monkeypatch):
    """Hearthstone, Diablo Immortal… (GeForce NOW, no Steam): descripción, año, desarrollador y géneros de Wikidata y
    Wikipedia en español; una expansión («World of Warcraft: Midnight») busca el juego de antes de los dos puntos."""
    from orbital.library import wiki_games

    answers = {
        "wbsearchentities&search=World%20of%20Warcraft%3A%20Midnight": {"search": [{"id": "Q9", "description": "expansión"}]},
        "wbsearchentities&search=World%20of%20Warcraft": {"search": [{"id": "Q1", "description": "videojuego de rol"}]},
        "ids=Q1&props=claims": {"entities": {"Q1": {"claims": {
            "P577": [{"mainsnak": {"datavalue": {"value": {"time": "+2004-11-23T00:00:00Z"}}}}],
            "P178": [{"mainsnak": {"datavalue": {"value": {"id": "Q50"}}}}],
            "P136": [{"mainsnak": {"datavalue": {"value": {"id": "Q60"}}}}]},
            "sitelinks": {"eswiki": {"title": "World of Warcraft"}}}}},
        "ids=Q50|Q60&props=labels": {"entities": {"Q50": {"labels": {"es": {"value": "Blizzard Entertainment"}}},
                                                  "Q60": {"labels": {"es": {"value": "videojuego de rol multijugador masivo en línea"}}}}},
        "page/summary/World_of_Warcraft": {"extract": "World of Warcraft es un videojuego de rol multijugador masivo en línea."},
    }

    def fake(url, headers=None, timeout=10):
        return 200, next((v for k, v in answers.items() if k in url), {})

    monkeypatch.setattr(wiki_games, "http_json", fake)
    info = wiki_games.find("World of Warcraft: Midnight")
    assert info == {"description": "World of Warcraft es un videojuego de rol multijugador masivo en línea.", "year": "2004",
                    "developer": "Blizzard Entertainment", "genres": ["Rol multijugador masivo en línea"]}
    store = wiki_games.WikiGames(tmp_path / "w.json", lookup_fn=lambda t: info, sleep=lambda s: None)
    assert store.warm(["World of Warcraft: Midnight"]) == 1 and store.cached("world of warcraft: midnight")["year"] == "2004"
    assert wiki_games.WikiGames(tmp_path / "w.json").cached("World of Warcraft: Midnight")["developer"] == "Blizzard Entertainment"


def test_un_juego_de_geforce_now_abre_con_la_pantalla_de_carga(library, monkeypatch):
    """Como los demás juegos: Orbital encima con su pantalla de carga hasta que el juego en la nube está a pantalla
    completa (antes se veían las ventanas de conexión de GeForce NOW). La app de GeForce NOW sigue abriendo directo."""
    import sys

    from orbital import sessions as sessions_mod
    from orbital.library.models import LibraryItem

    ran, asked = [], {}
    monkeypatch.setattr(library.launcher, "run", lambda argv, cwd=None: ran.append(argv))
    monkeypatch.setattr(library.launcher, "track_exe", lambda *a, **k: None)
    monkeypatch.setattr(library.sessions, "to_front", lambda item_id, title, runner=None, pinned=None, ready=None, timeout=0:
                        asked.update(item=item_id, runner=runner, ready=ready, timeout=timeout) or True)
    game = LibraryItem(id="gfn:1", title="Hogwarts Legacy", category="geforcenow", source="geforcenow",
                       argv=["GeForceNOWStreamer.exe", "--url-route=#?cmsId=1"])
    library.store.replace([game])
    library.sessions.launch("gfn:1")
    assert ran and asked["item"] == "gfn:1" and asked["runner"] == "GeForce NOW" and asked["timeout"] == sessions_mod.GFN_READY_TIMEOUT
    assert library.sessions.revealing is True and callable(asked["ready"])
    if sys.platform != "win32":
        return
    from orbital import windows
    monkeypatch.setattr(windows, "pids_by_exe", lambda exe: {5})
    monkeypatch.setattr(windows, "main_window", lambda pids: 77)
    monkeypatch.setattr(windows, "is_fullscreen", lambda hwnd: hwnd == 77)
    assert asked["ready"]() is True  # su ventana a pantalla completa: listo
