"""Jugadores como en una consola: el control con el que abres es el Jugador 1 y los demás en el orden en que llegaron."""

from types import SimpleNamespace

from orbital.players import Players, name_of

LEGION, GAMESIR, XBOX = (0x17EF, 0x61EB), (0x3537, 0x1040), (0x045E, 0x0B12)


def watcher(devices, arrived, last_used=None):
    return SimpleNamespace(devices=devices, connected_at=arrived, last_used=last_used, versions={})


def test_order_is_who_arrived_first_not_the_windows_slot():
    # El GameSir llegó primero aunque Windows le dio el lugar 1; la Legion llegó después en el lugar 0.
    w = watcher({0: LEGION, 1: GAMESIR}, {1: 10.0, 0: 20.0})
    p = Players(w)
    assert p.sync() == [1, 0]
    w.devices[2], w.connected_at[2] = XBOX, 30.0  # a media partida llega un Xbox: se suma al final
    assert p.joined(2) == 3 and p.devices() == [GAMESIR, LEGION, XBOX]
    del w.devices[1], w.connected_at[1]  # se fue el GameSir: los demás suben
    assert p.sync() == [0, 2]


def test_the_controller_that_opens_the_game_is_player_one():
    w = watcher({0: LEGION, 1: GAMESIR}, {0: 1.0, 1: 2.0}, last_used=1)
    p = Players(w)
    assert p.for_launch() == [1, 0]
    assert p.make_first(0) and p.order == [0, 1]
    assert not p.make_first(3)  # ese control ya no está


def test_snapshot_says_who_is_who_with_battery():
    w = watcher({0: LEGION, 2: (0x1234, 0x5678)}, {0: 1.0, 2: 2.0})
    snap = Players(w).snapshot(battery=lambda slot: {0: "wired", 2: "low"}[slot])
    assert snap == [{"player": 1, "slot": 0, "name": "Legion Go", "kind": "legion", "battery": "wired"},
                    {"player": 2, "slot": 2, "name": "Control", "kind": "other", "battery": "low"}]
    assert name_of(GAMESIR) == "GameSir" and name_of(None) == "Control"
