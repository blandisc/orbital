"""Modo juego: con algo pesado al frente (Switch, Wii U…) la ventana de Orbital se cierra para dejarle su memoria al
juego (Edge son ~560–800 MB, medido el 2026-10-26) y Home o terminar el juego la vuelven a abrir, sin perder avisos."""

import asyncio
import sys
from types import SimpleNamespace

from orbital import kiosk, sessions
from orbital.api.live import SseHub


class FakeProc:
    pid = 123

    def __init__(self):
        self.alive = True

    def poll(self):
        return None if self.alive else 0


def window(monkeypatch, tmp_path):
    monkeypatch.setattr(sys, "platform", "linux")  # sin Edge de verdad ni barra de tareas
    k = kiosk.KioskWindow("http://127.0.0.1:8710", profile_dir=tmp_path)
    k._process = FakeProc()
    killed = []
    monkeypatch.setattr(k, "_kill", lambda proc: killed.append(proc))
    return k, killed


def test_parking_closes_the_window_without_counting_as_leaving_to_the_desktop(monkeypatch, tmp_path):
    k, killed = window(monkeypatch, tmp_path)
    calls = []
    k.on_park, k.on_unpark = (lambda: calls.append("park")), (lambda: calls.append("unpark"))
    proc = k._process
    assert k.park() and killed == [proc] and k.parked and not k.exited_by_user and not k.is_open
    assert not k.park()  # ya cerrada: nada que hacer
    monkeypatch.setattr(kiosk, "find_browser", lambda configured=None: None)  # Home: open() la reabre (aquí sin Edge)
    k.open()
    assert not k.parked and calls == ["park", "unpark"]


def test_never_parks_after_you_left_to_the_desktop(monkeypatch, tmp_path):
    k, killed = window(monkeypatch, tmp_path)
    k.exited_by_user = True
    assert not k.park() and killed == []


def test_notices_while_the_window_is_closed_reach_it_when_it_reopens():
    async def run():
        hub = SseHub()
        hub.hold()
        hub.publish({"type": "status", "running": None})  # el estado no se guarda: llega al día al conectar
        hub.publish({"type": "closed", "title": "Mario Kart 8"})
        hub.release()
        hub.publish({"type": "health", "message": "memoria"})  # justo al reabrir, antes de que la página se conecte
        first = hub.subscribe()
        got = [first.get_nowait()["type"] for _ in range(first.qsize())]
        second = hub.subscribe()
        hub.publish({"type": "toast", "message": "ya conectada"})  # de aquí en adelante, normal: sin guardar
        return got, second.qsize() - 1 + len(hub._backlog)

    got, second = asyncio.run(run())
    assert got == ["closed", "health"] and second == 0  # solo una vez: al primero que se conecta


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
