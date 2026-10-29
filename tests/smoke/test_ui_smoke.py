"""Pruebas de humo de la interfaz en un navegador de verdad (Playwright), contra scripts/demo_server.py.

Corren en CI (que instala Playwright y Chromium). En la Legion Go se saltan si Playwright no está
instalado: no hace falta para usar Orbital.

    pip install playwright && python -m playwright install chromium
    python -m pytest tests/smoke          (ORBITAL_SMOKE_BROWSER=msedge: con el Edge instalado)
"""

from __future__ import annotations

import base64
import json
import os
import re
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


def test_focused_piece_is_marked_with_aria_current(page):
    """El sistema de diseño promete `aria-current` en lo enfocado, en cualquier pieza (core/focus-mark.js)."""
    ready(page)
    page.keyboard.press("e")  # Juegos: portada enfocada, filtro y consola del riel
    page.locator('button.card[aria-label="Hollow Knight"]').first.wait_for(timeout=5000)
    page.wait_for_timeout(400)
    assert page.locator(".card--focused[aria-current=true]:visible").count() == 1  # las vistas ocultas conservan su último foco
    page.keyboard.press("m")  # el menú: una opción enfocada (.sheet__item--focused) sin que la hoja lo ponga a mano
    page.locator(".sheet__item--focused").first.wait_for(timeout=3000)
    first = page.locator(".sheet__item[aria-current=true]:visible")
    assert first.count() == 1
    before = first.inner_text()
    page.keyboard.press("ArrowDown")
    page.wait_for_timeout(300)
    after = page.locator(".sheet__item[aria-current=true]:visible")
    assert after.count() == 1 and after.inner_text() != before  # el foco se movió: la marca se fue con él
    page.keyboard.press("Escape")
    page.wait_for_timeout(500)


def test_screensaver_fills_the_screen_edges(page):
    """Protector de pantalla: el margen de la TV se llena con una columna de más en cada orilla (solo asoma un pedazo)."""
    ready(page)
    page.keyboard.press("q")  # Para ti
    page.locator(".foryou-mosaic__tile").first.wait_for(timeout=8000)
    page.evaluate("document.body.dataset.screensaver = 'true'")  # lo que hace main.js · saver al pasar el rato sin usarla
    page.wait_for_function("document.querySelectorAll('.foryou-mosaic__col:not([hidden])').length === 8", timeout=8000)
    width = page.evaluate("innerWidth")
    left, right = [page.evaluate(f"(() => {{ const r = document.querySelectorAll('.foryou-mosaic__col')[{i}].getBoundingClientRect(); return [r.left, r.right]; }})()") for i in (6, 7)]
    assert left[0] < 0 < left[1] < width / 4 and 3 * width / 4 < right[0] < width < right[1]  # asoman por los dos lados
    assert all(page.locator(".foryou-mosaic__col").nth(i).locator(".foryou-mosaic__tile").count() > 0 for i in (6, 7))
    # Sin protector también se quedan: desde ff4561a1 las orillas llenan el margen de la TV siempre (antes solo con el
    # protector; esta prueba esperaba que se retiraran y fallaba desde entonces).
    page.evaluate("delete document.body.dataset.screensaver")
    page.wait_for_timeout(600)
    assert page.evaluate("document.querySelectorAll('.foryou-mosaic__col:not([hidden])').length") == 8


PIXEL = base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg==")


def _open_with_art(page, server, art) -> None:
    """Abre lo enfocado con el arte de Steam servido (`art`: "ok") o caído ("fail"), sin depender de internet."""
    page.route("**/steam/apps/**", lambda route: route.fulfill(body=PIXEL, content_type="image/png") if art == "ok" else route.abort())
    page.reload()  # que nada venga de la memoria del navegador
    ready(page)
    page.keyboard.press("e")  # Juegos: una portada con su fondo
    page.locator('button.card[aria-label="Hollow Knight"]').first.wait_for(timeout=8000)
    page.wait_for_timeout(400)
    page.keyboard.press("Enter")
    page.locator(".launch").wait_for(timeout=5000)


def _stop(server) -> None:
    """Cierra lo que abrió la prueba (cuando ya se registró): la siguiente abre de cero, no «Volver al juego»."""
    deadline = time.monotonic() + 10
    while not status(server)["running"] and time.monotonic() < deadline:
        time.sleep(.2)
    urllib.request.urlopen(urllib.request.Request(f"{server}/api/stop", method="POST"), timeout=5)
    while status(server)["running"] and time.monotonic() < deadline:
        time.sleep(.2)


def test_loading_screen_paints_each_image_once_it_is_decoded(page, server):
    """La pantalla de carga: el fondo ambiental (el arte difuminado en un lienzo diminuto) y la portada entran ya
    decodificados (antes se pintaban a medias o nunca)."""
    _open_with_art(page, server, "ok")
    page.locator(".launch.launch--ambient").wait_for(timeout=5000)
    page.locator(".launch__cover--ready .launch__poster img").wait_for(timeout=5000)
    assert page.evaluate("document.querySelector('.launch__poster img').naturalWidth") > 0
    assert page.evaluate("getComputedStyle(document.querySelector('.launch__art')).filter") == "none"  # sin filtros caros
    _stop(server)


def test_loading_screen_without_art_still_looks_intentional(page, server):
    """Sin internet (o con el arte caído): las estrellas de la marca y la inicial del título en la tarjeta, nunca un hueco."""
    _open_with_art(page, server, "fail")
    page.locator(".launch.launch--plain").wait_for(timeout=8000)
    page.locator(".launch__cover--missing").wait_for(timeout=8000)
    assert not page.locator(".launch.launch--art").count()
    _stop(server)


def test_opening_a_game_and_coming_back(page, server):
    ready(page)
    page.keyboard.press("Enter")  # abre lo enfocado (el lanzador de prueba no abre nada de verdad)
    deadline = time.monotonic() + 10
    while not status(server)["running"] and time.monotonic() < deadline:
        time.sleep(.2)
    assert status(server)["running"]
    urllib.request.urlopen(urllib.request.Request(f"{server}/api/stop", method="POST"), timeout=5)
    # Llegó el aviso por SSE (con portada: el título arriba y «Jugaste…» o «De vuelta en Orbital» abajo).
    page.locator(".toast", has_text=re.compile("Jugaste|De vuelta en Orbital")).wait_for(timeout=10_000)


def test_diagnostics_screen(page):
    ready(page)
    page.locator(".status-bar__brand").click()  # el logo abre el menú
    page.locator(".sheet__item", has_text="Ajustes").click()  # Ajustes a pantalla completa
    page.locator(".settings .rail__item", has_text="Sistema").click()  # lo técnico vive en Ajustes › Sistema
    page.locator(".settings__page-title", has_text="Sistema").wait_for()
    page.locator(".settings .sheet__item", has_text="Diagnóstico").click()
    page.get_by_text("Memoria libre").wait_for(timeout=15_000)


def test_live_tv_categories_and_tuning_a_channel(page, server):
    """TV en vivo: categorías a la izquierda (LT/RT o ↑↓ las cambian), canales en cuadrícula, A sintoniza y B vuelve
    (canales de mentiras, sin mpv; la miniatura en vivo de un canal de mentiras se queda en su logo)."""
    ready(page)
    for _ in range(3):  # Inicio → Juegos → Películas y series → TV en vivo
        page.keyboard.press("e")
        page.wait_for_timeout(350)
    page.locator(".tv__tile").first.wait_for(timeout=5000)
    assert page.locator(".status-bar__tab--active").inner_text() == "TV en vivo"
    assert page.locator(".tv__cat").count() > 1  # las categorías, siempre a la vista
    assert page.locator(".tv__cat--on").inner_text().startswith("Todos")
    assert page.locator(".tv__tile").count() == 42 and page.locator(".tv__tile.tile--focused").count() == 1
    # Los canales de Orbital (una serie al aire todo el día) van primero, con «24/7» en vez de número.
    assert "Los Simpson 24/7" in page.locator(".tv__tile").first.inner_text() and "24/7" in page.locator(".tv__number").first.inner_text()
    # Un canal que ya falló una vez sale atenuado y con su aviso; los que nadie ha revisado, normales.
    assert page.locator(".tv__tile.tile--dimmed").count() >= 1
    assert page.locator(".tv__flag", has_text="Sin señal reciente").count() >= 1
    # Los logos los sirve Orbital (parejos) y cargan; el que no trae logo muestra las letras de su nombre.
    page.wait_for_function("document.querySelectorAll('.tv__logo').length > 5 && [...document.querySelectorAll('.tv__logo')].some((i) => i.complete && i.naturalWidth > 0)")
    assert page.locator(".tv__initials").count() >= 1
    # La página no se ensancha.
    assert page.evaluate("document.documentElement.scrollWidth <= document.documentElement.clientWidth")
    page.keyboard.press("PageDown")  # la categoría siguiente (AvPág / RT); Q y E (LB RB) son las secciones
    page.wait_for_timeout(400)
    assert page.locator(".tv__cat--on").inner_text().startswith("Orbital 24/7")
    assert page.locator(".tv__tile").count() == 2
    page.keyboard.press("PageDown")
    page.wait_for_timeout(400)
    assert page.locator(".tv__cat--on").inner_text().startswith("General")
    assert 1 < page.locator(".tv__tile").count() < 40
    page.keyboard.press("Enter")  # sintoniza el canal enfocado (el lanzador de prueba no abre nada de verdad)
    deadline = time.monotonic() + 10
    while not status(server)["running"] and time.monotonic() < deadline:
        time.sleep(.2)
    assert status(server)["running"]["id"] == "media:player"
    # Al aire: su casilla lo dice y A vuelve a él.
    page.locator(".tv__flag", has_text="Al aire").wait_for(timeout=5000)
    assert status(server)["running"]["live"]
    assert "Volver al canal" in page.locator(".hints").inner_text()
    page.wait_for_timeout(2000)  # que se vaya la pantalla de carga del primer canal
    page.keyboard.press("ArrowRight")  # con uno al aire, otro canal se sintoniza sin pantalla de carga
    page.keyboard.press("Enter")
    page.wait_for_timeout(500)
    assert not page.locator(".launch").is_visible()
    assert page.locator(".tv__flag", has_text="Al aire").count() == 1
    urllib.request.urlopen(urllib.request.Request(f"{server}/api/stop", method="POST"), timeout=5)
    page.locator(".toast", has_text="De vuelta de la TV en vivo").wait_for(timeout=10_000)  # no «dónde ibas»: la tele no lo guarda
    page.keyboard.press("Escape")  # B: primero a las categorías; otra vez, a Inicio
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
    page.locator(".hints", has_text="Buscar").wait_for(timeout=5000)
