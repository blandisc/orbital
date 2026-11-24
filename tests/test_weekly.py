"""«Esta semana» en la TV (orbital/foryou/weekly.py): la misma tabla y la misma rueda que el iPhone (ExploreListsTests)."""

from __future__ import annotations

from datetime import date, timedelta

from orbital.foryou import weekly


def test_la_tabla_del_repositorio_se_lee():
    table = weekly.local_table()
    assert table.get("rotate", 0) > 0
    ids = [e["id"] for e in table["lists"]]
    assert len(ids) == len(set(ids))


def test_las_de_temporada_salen_en_su_temporada_y_primero():
    table = weekly.local_table()
    october = [e["id"] for e in weekly.this_week(table, date(2026, 10, 15))]
    assert october[0] == "simpsons-halloween"
    assert "simpsons-navidad" not in october
    assert "simpsons-navidad" in [e["id"] for e in weekly.this_week(table, date(2027, 1, 3))]  # cruza el año
    assert not any(weekly.dated(e) for e in weekly.this_week(table, date(2026, 11, 23)))


def test_las_demas_rotan_el_lunes_y_pasan_todas():
    table = {"rotate": 4, "lists": [{"id": f"l{n}"} for n in range(6)]}
    monday = date(2026, 11, 23)
    week = [e["id"] for e in weekly.this_week(table, monday)]
    assert len(week) == 4
    assert [e["id"] for e in weekly.this_week(table, monday + timedelta(days=6))] == week
    following = [e["id"] for e in weekly.this_week(table, monday + timedelta(days=7))]
    assert following != week
    assert set(week + following) == {f"l{n}" for n in range(6)}


def test_igual_que_el_iphone_el_lunes_23_nov():
    # ExploreTable.thisWeek (OrbitalCore): semana 2968 desde el lunes 5 ene 1970 → empieza en (2968 * 4) % 6 = 4.
    table = {"rotate": 4, "lists": [{"id": f"l{n}"} for n in range(6)]}
    assert [e["id"] for e in weekly.this_week(table, date(2026, 11, 23))] == ["l4", "l5", "l0", "l1"]


def test_los_capitulos_salen_y_abren_su_serie_en_ese_capitulo():
    entry = {"items": [{"id": "tt0096697:7:11", "kind": "episode", "title": "El bebé de mamá", "year": 1995},
                       {"id": "tt0099785", "kind": "movie", "title": "Mi pobre angelito", "year": 1990}]}
    items = weekly.written(entry)
    assert [(e["imdb"], e["kind"]) for e in items] == [("tt0096697:7:11", "episode"), ("tt0099785", "movie")]
    assert weekly.episode("tt0096697:7:11") == ("tt0096697", 7, 11)
    assert weekly.episode("tt0099785") is None


def test_la_tabla_tiene_icono_en_cada_lista_y_la_afi_en_orden():
    table = weekly.local_table()
    assert all(e.get("art") for e in table["lists"])
    afi = next(e for e in table["lists"] if e["id"] == "afi-100")["items"]
    assert (afi[0]["title"], afi[-1]["title"], len(afi)) == ("Citizen Kane", "Ben-Hur", 100)
