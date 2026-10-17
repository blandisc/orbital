"""La ficha de la tienda de Steam (en español) para los juegos de Steam y GeForce NOW, que no traían nada."""

from __future__ import annotations

from orbital.library import steam_store
from orbital.library.models import LibraryItem

BODY = {"short_description": "&iexcl;Forja tu propio camino en <b>Hollow Knight</b> ya!", "release_date": {"date": "24 FEB 2017"},
        "genres": [{"description": "Acción"}, {"description": "Aventura"}, {"description": "Indie"}, {"description": "RPG"}],
        "developers": ["Team Cherry"]}


def test_la_ficha_trae_lo_mismo_que_los_juegos_de_consola():
    info = steam_store.parse(BODY)
    assert info == {"description": "¡Forja tu propio camino en Hollow Knight ya!", "year": "2017", "controller": "none",
                    "genres": ["Acción", "Aventura", "Indie"], "developer": "Team Cherry"}
    assert steam_store.parse({}) == {"controller": "none"}


def test_se_guarda_y_no_se_vuelve_a_pedir_hasta_el_mes(tmp_path):
    asked = []
    now = [1000.0]
    store = steam_store.SteamStore(tmp_path / "s.json", fetch_fn=lambda a: asked.append(a) or ({} if a == 2 else {"year": "2017", "controller": "full"}),
                                   clock=lambda: now[0], sleep=lambda s: None)
    assert store.warm([1, 2, 1]) == 2 and asked == [1, 2]  # cada juego una vez
    assert store.cached(1) == {"year": "2017", "controller": "full"} and store.cached(2) == {}
    again = steam_store.SteamStore(tmp_path / "s.json", fetch_fn=lambda a: asked.append(a) or {}, clock=lambda: now[0])
    assert again.warm([1, 2]) == 0 and again.cached(1)["year"] == "2017"  # en disco: nada que pedir
    now[0] += steam_store.RETRY_MISSING + 1
    assert again.warm([1, 2]) == 1  # el que no estaba en la tienda, a la semana; el que sí, al mes


def test_sin_red_se_detiene_y_sigue_otro_dia(tmp_path):
    store = steam_store.SteamStore(None, fetch_fn=lambda a: None, sleep=lambda s: None)
    assert store.warm([1, 2, 3]) == 0 and store.cached(1) == {}


def test_la_biblioteca_lo_pone_en_steam_y_geforce_now_sin_pisar_lo_que_ya_traen(library, monkeypatch):
    steam = LibraryItem(id="steam:367520", title="Hollow Knight", category="steam", source="steam", steam_appid=367520)
    gfn = LibraryItem(id="gfn:1", title="Hollow Knight", category="geforcenow", source="geforcenow", steam_appid=367520,
                      extra={"year": "2018"})
    library.store.replace([steam, gfn])
    monkeypatch.setattr(library.steam_store, "_fetch", lambda appid: steam_store.parse(BODY))
    monkeypatch.setattr(library.steam_store, "_sleep", lambda s: None)
    library.warm_store()
    assert library.get("steam:367520").extra["developer"] == "Team Cherry"
    assert library.get("gfn:1").extra["genres"] == ["Acción", "Aventura", "Indie"]
    assert library.get("gfn:1").extra["year"] == "2018"  # lo que ya traía se queda


def test_la_tienda_dice_si_se_juega_con_control_y_lo_viejo_se_vuelve_a_pedir(tmp_path):
    assert steam_store.parse({**BODY, "controller_support": "full"})["controller"] == "full"
    assert steam_store.parse(BODY)["controller"] == "none"  # sin el dato: teclado y ratón
    old = steam_store.SteamStore(tmp_path / "s.json", fetch_fn=lambda a: {"year": "2017", "controller": "partial"}, clock=lambda: 0, sleep=lambda s: None)
    old._data["1"] = {"info": {"year": "2017"}, "at": 0}  # guardada antes de saber del control
    assert old.warm([1]) == 1 and old.cached(1)["controller"] == "partial"
