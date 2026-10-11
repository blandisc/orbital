"""Pruebas de humo de la interfaz en un navegador de verdad (Playwright), contra scripts/demo_server.py.

Corren en CI (que instala Playwright y Chromium). En la Legion Go se saltan si Playwright no está
instalado: no hace falta para usar Orbital.

    pip install playwright && python -m playwright install chromium
    python -m pytest tests/smoke          (ORBITAL_SMOKE_BROWSER=msedge: con el Edge instalado)
"""

from __future__ import annotations

import json
import os
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
        browser = p.chromium.launch(channel=os.environ.get("ORBITAL_SMOKE_BROWSER") or None)
        page = browser.new_page(viewport={"width": 1280, "height": 800})
        errors: list[str] = []
        page.on("pageerror", lambda exc: errors.append(str(exc)))
        page.goto(server)
        yield page
        assert not errors, f"Errores de JavaScript: {errors}"
        browser.close()


def ready(page) -> None:
    """Pasó la animación de arranque y, si salió "Tu consola" (primera vez), se cerró."""
    page.wait_for_selector("#boot", state="detached", timeout=15_000)
    page.wait_for_timeout(1500)  # "Tu consola" aparece un momento después de aterrizar
    if page.locator(".sheet__title", has_text="Tu consola").is_visible():
        page.keyboard.press("Escape")
        page.wait_for_timeout(400)


def status(server) -> dict:
    with urllib.request.urlopen(f"{server}/api/status", timeout=5) as res:
        return json.load(res)


def test_boots_and_shows_the_library(page):
    ready(page)
    page.locator('button.card[aria-label="Hollow Knight"]').first.wait_for(state="attached", timeout=5000)
    assert page.locator("button.card").count() >= 6


def test_opening_a_game_and_coming_back(page, server):
    ready(page)
    page.keyboard.press("Enter")  # abre lo enfocado (el lanzador de prueba no abre nada de verdad)
    deadline = time.monotonic() + 10
    while not status(server)["running"] and time.monotonic() < deadline:
        time.sleep(.2)
    assert status(server)["running"]
    urllib.request.urlopen(urllib.request.Request(f"{server}/api/stop", method="POST"), timeout=5)
    page.locator(".toast", has_text="De vuelta de").wait_for(timeout=10_000)  # llegó el aviso por SSE


def test_diagnostics_screen(page):
    ready(page)
    page.locator(".status-bar__brand").click()  # el logo abre el menú
    page.get_by_text("Ajustes", exact=True).first.click()
    page.get_by_text("Diagnóstico", exact=True).first.click()
    page.get_by_text("Memoria libre").wait_for(timeout=15_000)
