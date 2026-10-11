"""Pruebas de humo de la interfaz en un navegador de verdad (Playwright), contra scripts/demo_server.py.

Corren en CI (que instala Playwright y Chromium). En la Legion Go se saltan si Playwright no está
instalado: no hace falta para usar Orbital.

    pip install playwright && python -m playwright install chromium
    python -m pytest tests/smoke
"""

from __future__ import annotations

import socket
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

import pytest

playwright = pytest.importorskip("playwright.sync_api")
ROOT = Path(__file__).resolve().parents[2]


def free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


@pytest.fixture(scope="module")
def server():
    port = free_port()
    process = subprocess.Popen([sys.executable, str(ROOT / "scripts" / "demo_server.py"), "--port", str(port)])
    url = f"http://127.0.0.1:{port}"
    deadline = time.monotonic() + 30
    while time.monotonic() < deadline:
        try:
            urllib.request.urlopen(f"{url}/api/health", timeout=1)
            break
        except OSError:
            time.sleep(.2)
    else:
        process.kill()
        pytest.fail("El servidor de prueba no arrancó")
    yield url
    process.kill()
    process.wait(5)


@pytest.fixture
def page(server):
    with playwright.sync_playwright() as p:
        browser = p.chromium.launch()
        page = browser.new_page(viewport={"width": 1280, "height": 800})
        errors: list[str] = []
        page.on("pageerror", lambda exc: errors.append(str(exc)))
        page.goto(server)
        yield page
        assert not errors, f"Errores de JavaScript: {errors}"
        browser.close()


def test_boots_and_shows_the_library(page):
    page.wait_for_selector("#boot", state="detached", timeout=15_000)  # la animación de arranque termina
    page.keyboard.press("Escape")  # "Tu consola" sale la primera vez
    assert page.get_by_text("Hollow Knight").first.is_visible() or page.get_by_text("Hades").first.is_visible()


def test_opening_a_game_and_coming_back(page, server):
    page.wait_for_selector("#boot", state="detached", timeout=15_000)
    page.keyboard.press("Escape")
    page.keyboard.press("Enter")  # abre lo enfocado (el lanzador de prueba no abre nada de verdad)
    page.wait_for_function("fetch('/api/status').then(r => r.json()).then(s => !!s.running)", timeout=10_000)
    urllib.request.urlopen(urllib.request.Request(f"{server}/api/stop", method="POST"), timeout=5)
    page.get_by_text("De vuelta de").first.wait_for(timeout=10_000)  # llegó el aviso por SSE


def test_diagnostics_screen(page):
    page.wait_for_selector("#boot", state="detached", timeout=15_000)
    page.keyboard.press("Escape")
    page.locator(".status-bar__brand").click()  # el logo abre el menú
    page.get_by_text("Ajustes", exact=True).first.click()
    page.get_by_text("Diagnóstico", exact=True).first.click()
    page.get_by_text("Memoria libre").wait_for(timeout=15_000)
