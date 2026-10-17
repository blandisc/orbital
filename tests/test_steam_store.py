"""La ficha de la tienda de Steam (en español) para los juegos de Steam y GeForce NOW, que no traían nada."""

from __future__ import annotations

from orbital.library import steam_store
from orbital.library.models import LibraryItem

BODY = {"short_description": "&iexcl;Forja tu propio camino en <b>Hollow Knight</b> ya!", "release_date": {"date": "24 FEB 2017"},
        "genres": [{"description": "Acción"}, {"description": "Aventura"}, {"description": "Indie"}, {"description": "RPG"}],
        "developers": ["Team Cherry"]}


def test_la_ficha_trae_lo_mismo_que_los_juegos_de_consola():
    info = steam_store.parse(BODY)
    assert info == {"description": "¡Forja tu propio camino en Hollow Knight ya!", "year": "2017",
                    "genres": ["Acción", "Aventura", "Indie"], "developer": "Team Cherry"}
    assert steam_store.parse({}) == {}


def test_se_guarda_y_no_se_vuelve_a_pedir_hasta_el_mes(tmp_path):
    asked = []
    now = [1000.0]
    store = steam_store.SteamStore(tmp_path / "s.json", fetch_fn=lambda a: asked.append(a) or ({} if a == 2 else {"year": "2017"}),
                                   clock=lambda: now[0], sleep=lambda s: None)
    assert store.warm([1, 2, 1]) == 2 and asked == [1, 2]  # cada juego una vez
    assert store.cached(1) == {"year": "2017"} and store.cached(2) == {}
    again = steam_store.SteamStore(tmp_path / "s.json", fetch_fn=lambda a: asked.append(a) or {}, clock=lambda: now[0])
    assert again.warm([1, 2]) == 0 and again.cached(1) == {"year": "2017"}  # en disco: nada que pedir
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
