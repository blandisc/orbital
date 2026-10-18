"""La ventana de Orbital siempre a la vista (kiosk.KioskWindow.ensure_shown): al despertar tras cambiar de pantalla,
Edge seguía vivo pero sin ventana visible y Orbital «no abría»."""

import sys

import pytest

from orbital import kiosk, windows


class FakeProc:
    pid = 123

    def poll(self):
        return None


@pytest.fixture
def window(monkeypatch, tmp_path):
    monkeypatch.setattr(sys, "platform", "win32")
    k = kiosk.KioskWindow("http://127.0.0.1:8710", profile_dir=tmp_path)
    k._process = FakeProc()
    calls = {"placed": [], "front": 0, "restart": 0}
    monkeypatch.setattr(windows, "screen_size", lambda: (2560, 1600))
    monkeypatch.setattr(windows, "is_minimized", lambda h: False)
    monkeypatch.setattr(windows, "place_window", lambda h, x, y, w, ht, topmost=True: calls["placed"].append((h, x, y, w, ht)))
    monkeypatch.setattr(kiosk.system, "bring_to_front", lambda: calls.__setitem__("front", calls["front"] + 1))
    monkeypatch.setattr(k, "restart", lambda: calls.__setitem__("restart", calls["restart"] + 1))
    return k, calls


def test_a_window_left_on_a_screen_that_is_gone_comes_back_to_the_main_one(window, monkeypatch):
    k, calls = window
    monkeypatch.setattr(k, "window", lambda: 77)
    monkeypatch.setattr(windows, "on_a_monitor", lambda h: False)
    assert k.ensure_shown() == "moved" and calls["placed"] == [(77, 0, 0, 2560, 1600)] and calls["front"] == 0
    monkeypatch.setattr(windows, "on_a_monitor", lambda h: True)
    assert k.ensure_shown(front=True) == "ok" and calls["front"] == 1  # al despertar sin juego: al frente


def test_edge_alive_without_a_window_is_reopened_after_two_checks(window, monkeypatch):
    k, calls = window
    monkeypatch.setattr(k, "window", lambda: 0)
    assert k.ensure_shown() == "waiting" and calls["restart"] == 0  # puede estar arrancando
    assert k.ensure_shown() == "reopened" and calls["restart"] == 1
    k.exited_by_user = True
    assert k.ensure_shown() == "skip"  # saliste al escritorio: no se reabre
