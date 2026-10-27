"""Modo juego: con algo pesado al frente (Switch, Wii U…) la ventana de Orbital se cierra para dejarle su memoria al
juego (Edge son ~560–800 MB, medido el 2026-10-26) y Home o terminar el juego la vuelven a abrir, sin perder avisos."""

import sys
from types import SimpleNamespace

from orbital import kiosk, sessions


class FakeProc:
    pid = 123

    def poll(self):
        return None


def test_parking_minimizes_and_frees_ram_without_closing(monkeypatch, tmp_path):
    """Cerrarla y reabrirla con Home dejaba ~2 s de pantalla negra (probado en la TV): ahora se minimiza y Windows saca
    su memoria de la RAM; Home la trae al instante, la misma página (sin la entrada de la marca)."""
    from orbital import windows

    monkeypatch.setattr(sys, "platform", "win32")
    k = kiosk.KioskWindow("http://127.0.0.1:8710", profile_dir=tmp_path)
    k._process = FakeProc()
    calls = []
    monkeypatch.setattr(k, "window", lambda: 77)
    monkeypatch.setattr(k, "pids", lambda: {1, 2, 3})
    monkeypatch.setattr(windows, "minimize", lambda hwnd: calls.append(("min", hwnd)))
    monkeypatch.setattr(windows, "trim_working_set", lambda pids: calls.append(("trim", sorted(pids))) or len(pids))
    monkeypatch.setattr(kiosk.system, "focus_window", lambda hwnd: calls.append(("front", hwnd)) or True)
    assert k.park() and k.parked and k.is_open and not k.exited_by_user
    assert calls == [("min", 77), ("trim", [1, 2, 3])]
    assert k.open() and not k.parked and calls[-1] == ("front", 77)  # Home: la misma ventana al frente
    k.exited_by_user = True
    assert not k.park()  # saliste al escritorio: nada que minimizar


def fake_sessions(system="switch", setting="heavy", kiosk_obj=None):
    s = sessions.Sessions.__new__(sessions.Sessions)
    s.kiosk = kiosk_obj if kiosk_obj is not None else SimpleNamespace(park=lambda: None)
    s.store = SimpleNamespace(get=lambda item_id: SimpleNamespace(system=system))
    s.state = SimpleNamespace(settings=lambda: {"game_mode": setting})
    s.returned_at = 0.0
    return s


def test_only_heavy_systems_and_only_if_not_turned_off():
    assert fake_sessions("switch").game_mode("switch:jamboree")
    assert not fake_sessions("gba").game_mode("gba:pokemon")  # mGBA no pesa: la ventana se queda
    assert not fake_sessions("switch", setting="off").game_mode("switch:jamboree")
    s = fake_sessions("switch")
    s.kiosk = None  # sin la ventana de Orbital (otra pantalla, pruebas): nada que cerrar
    assert not s.game_mode("switch:jamboree")


def test_parks_only_if_you_are_still_in_that_game(monkeypatch):
    parked = []
    timers = []

    class Timer:
        def __init__(self, delay, fn):
            self.fn, self.daemon = fn, False
            timers.append(self)

        def start(self):
            pass

    monkeypatch.setattr(sessions.threading, "Timer", Timer)
    s = fake_sessions(kiosk_obj=SimpleNamespace(park=lambda: parked.append(1)))
    s.launcher = SimpleNamespace(status=lambda: {"id": "switch:jamboree"})
    s.park_soon("switch:jamboree")
    timers[-1].fn()
    assert parked == [1]
    s.park_soon("switch:jamboree")
    s.returned_at = float("inf")  # apretaste Home mientras tanto
    timers[-1].fn()
    s.returned_at = 0.0
    s.launcher = SimpleNamespace(status=lambda: None)  # el juego ya se cerró
    s.park_soon("switch:jamboree")
    timers[-1].fn()
    assert parked == [1]
