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
    # Inicio: lo último que jugaste a lo grande y tus consolas (con foto; sin arte, el respaldo).
    page.locator(".tile--feature").wait_for(timeout=5000)
    assert page.locator(".tile--console").count() >= 4
    assert page.locator(".tile--row").count() == 4  # «También tenías», en renglones
    page.keyboard.press("e")  # RB: a Juegos, con sus filas de portadas
    page.locator('button.card[aria-label="Hollow Knight"]').first.wait_for(timeout=5000)
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
    page.get_by_text("Mantenimiento", exact=True).first.click()  # lo técnico vive en Ajustes → Mantenimiento
    # «Diagnóstico» queda justo donde estaba «Mantenimiento»: un toque ahí antes de 400 ms la hoja lo toma como
    # doble toque y lo ignora a propósito (así un doble toque no confirma «¿Reiniciar?»). Una persona no es tan rápida.
    page.locator(".sheet__title", has_text="Mantenimiento").wait_for()
    page.wait_for_timeout(500)
    page.get_by_text("Diagnóstico", exact=True).first.click()
    page.get_by_text("Memoria libre").wait_for(timeout=15_000)


def test_live_tv_categories_and_tuning_a_channel(page, server):
    """TV en vivo: LB/RB pasan de categoría, A sintoniza y B vuelve (con canales de mentiras, sin mpv)."""
    ready(page)
    for _ in range(3):  # Inicio → Juegos → Películas y series → TV en vivo
        page.keyboard.press("e")
        page.wait_for_timeout(350)
    page.locator(".tv__tile").first.wait_for(timeout=5000)
    assert page.locator(".status-bar__tab--active").inner_text() == "TV en vivo"
    assert page.locator(".tv__tile").count() == 40 and page.locator(".tv__tile.tile--focused").count() == 1
    # Un canal que ya falló una vez sale al final, atenuado y con su aviso; los que nadie ha revisado, normales.
    assert page.locator(".tv__tile.tile--dimmed").count() == 1
    assert page.locator(".tv__tile").last.locator(".tv__flag", has_text="Sin señal reciente").count() == 1
    assert "1 sin señal reciente" in page.locator(".tv .browse__meta").inner_text()
    # Los logos los sirve Orbital (parejos) y cargan; el que no trae logo muestra las letras de su nombre.
    page.wait_for_function("document.querySelectorAll('.tv__logo').length > 5 && [...document.querySelectorAll('.tv__logo')].some((i) => i.complete && i.naturalWidth > 0)")
    assert page.locator(".tv__initials").count() >= 1
    # La sección cabe en la pantalla (antes las píldoras la ensanchaban y se cortaba la última columna).
    assert page.evaluate("document.querySelector('.tv').scrollWidth <= document.documentElement.clientWidth")
    page.keyboard.press("e")  # categoría siguiente: General
    page.wait_for_timeout(400)
    assert page.locator(".tv .browse__filter--on").inner_text() == "General"
    assert 1 < page.locator(".tv__tile").count() < 40
    page.keyboard.press("Enter")  # sintoniza el canal enfocado (el lanzador de prueba no abre nada de verdad)
    deadline = time.monotonic() + 10
    while not status(server)["running"] and time.monotonic() < deadline:
        time.sleep(.2)
    assert status(server)["running"]["id"] == "media:player"
    # Al aire: su casilla lo dice, A vuelve a él, y con uno al aire otro canal se sintoniza sin pantalla de carga.
    page.locator(".tv__flag", has_text="Al aire").wait_for(timeout=5000)
    assert status(server)["running"]["live"]
    assert "Volver al canal" in page.locator(".hints").inner_text()
    page.wait_for_timeout(2000)  # que se vaya la pantalla de carga del primer canal
    page.keyboard.press("ArrowRight")
    page.keyboard.press("Enter")
    page.wait_for_timeout(500)
    assert not page.locator(".launch").is_visible()
    assert page.locator(".tv__flag", has_text="Al aire").count() == 1
    urllib.request.urlopen(urllib.request.Request(f"{server}/api/stop", method="POST"), timeout=5)
    page.locator(".toast", has_text="De vuelta de la TV en vivo").wait_for(timeout=10_000)  # no «dónde ibas»: la tele no lo guarda
    page.keyboard.press("Escape")  # B: primero al primer canal; otra vez, a Inicio
    page.wait_for_timeout(300)
    page.keyboard.press("Escape")
    page.wait_for_timeout(500)
    assert page.locator(".status-bar__tab--active").inner_text() == "Inicio"


def test_search_with_results(page):
    """Escribir en Buscar con resultados a la vista: la leyenda ofrece saltar a ellos (antes, un
    ReferenceError en cada tecla dejaba la leyenda congelada)."""
    ready(page)
    page.keyboard.press("s")
    page.keyboard.type("hol")
    page.locator(".search button.card").first.wait_for(timeout=5000)
    page.locator(".hints", has_text="Resultados").wait_for(timeout=5000)
