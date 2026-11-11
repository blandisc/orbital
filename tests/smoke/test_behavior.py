"""Pruebas de comportamiento en un navegador de verdad (R3-3, 11 nov 2026): lo que antes se cuidaba buscando expresiones en el
código fuente (`tests/web/tint.test.mjs`, `search.test.mjs`, `menu-paths.test.mjs`, `rendimiento.test.mjs`) se comprueba aquí
haciendo lo que haría alguien en el sillón: mover el foco, escribir, abrir y volver. Mismo servidor de demostración."""

from __future__ import annotations

from test_ui_flows import browser, open_at  # noqa: F401  (browser es un fixture)
from test_ui_smoke import server  # noqa: F401  (server es un fixture)

FOCUSED = "(sel) => { const f = document.querySelector(sel + ' .is-focused'); return f ? (f.getAttribute('aria-label') || f.textContent).trim() : null; }"


def press(page, *keys, wait=350):
    for key in keys:
        page.keyboard.press(key)
        page.wait_for_timeout(wait)


def to_media(page):
    """Inicio → Juegos → Películas y series."""
    press(page, "e", "e", wait=500)
    page.wait_for_timeout(1300)


# --- El color del arte solo en las piezas que lo usan (antes: tint.test.mjs comparaba dos listas en el código) ------------

TINT_SNAPSHOT = """async () => {
  const { TINTED } = await import('/js/components/backdrop.js');
  const all = [document.documentElement, ...document.querySelectorAll('body *')];
  const tinted = TINTED.join(', ');
  return { values: all.map((el) => getComputedStyle(el).getPropertyValue('--art-accent').trim()), tinted,
    inside: all.map((el) => !!el.closest(tinted)),
    // Cada pieza teñida saca su --color-accent de su propio --art-accent (si el tema no la nombrara, heredaría el de <html>).
    stale: [...document.querySelectorAll(tinted)].filter((el) => { const s = getComputedStyle(el);
      return s.getPropertyValue('--color-accent').trim() !== s.getPropertyValue('--art-accent').trim(); }).map((el) => el.className),
    root: document.documentElement.style.cssText };
}"""

TINT_CHANGED = """([before, tinted, inside]) => {
  const all = [document.documentElement, ...document.querySelectorAll('body *')];
  const changed = all.filter((el, i) => getComputedStyle(el).getPropertyValue('--art-accent').trim() !== before[i]);
  return { changed: changed.length, outside: changed.filter((el) => !el.closest(tinted) && !inside[all.indexOf(el)]).map((el) => el.tagName + '.' + el.className).slice(0, 10),
    rootChanged: changed.includes(document.documentElement),
    orbit: (() => { const f = document.querySelector('.is-focused.card'); if (!f) return null; const s = getComputedStyle(f);
      return [s.getPropertyValue('--orbit-color'), s.getPropertyValue('--art-accent').trim()]; })() };
}"""


def test_art_tint_only_reaches_the_pieces_that_use_it(browser, server):  # noqa: F811
    """V1: al mover el foco a un título de otro color, el color del arte cambia solo en las piezas que lo usan (el fondo, las
    pantallas, los paneles, la tarjeta enfocada; la que deja el foco sale de ese grupo y eso no cuenta), nunca en <html> (que obligaba a recalcular toda la página), y cada pieza
    teñida lo lleva de verdad (su --color-accent es su --art-accent, no el de antes). Lo enfocado recibe el color en su órbita."""
    page = open_at(browser, server)
    to_media(page)
    press(page, "ArrowDown", wait=1200)
    before = page.evaluate(TINT_SNAPSHOT)
    assert not before["stale"], before["stale"]
    result = None
    for _ in range(8):  # hasta dar con un título de otro color
        press(page, "ArrowRight", wait=900)
        result = page.evaluate(TINT_CHANGED, [before["values"], before["tinted"], before["inside"]])
        if result["changed"]:
            break
    assert result and result["changed"], "ningún título de otro color en la fila"
    assert not result["outside"], result["outside"]
    assert not result["rootChanged"], "el color del arte se escribió en <html>"
    after = page.evaluate(TINT_SNAPSHOT)
    assert not after["stale"], after["stale"]
    assert "--art" not in after["root"], after["root"]
    orbit, accent = result["orbit"]
    assert accent and accent in orbit, result["orbit"]  # la órbita de lo enfocado sale del color de su arte
    assert not page.errors, page.errors


# --- Lo que salió del menú ☰ tiene camino con mando (antes: menu-paths.test.mjs buscaba expresiones en main.js) ------------

def test_entries_that_left_the_menu_have_a_path_with_the_pad(browser, server):  # noqa: F811
    """D5-A: Guardado, Colecciones y Filtro avanzado se abren desde los íconos junto a «Todo · Películas · Series» (↑, ▶ y A;
    B vuelve al mismo ícono; también con un clic), y «Decide por mí» con «Una por una» desde Explorar (X; ↑ y A abren el mazo
    encima de Decide; B regresa a Decide). Con Trakt conectado en la demo (Guardado vive en Trakt)."""
    import urllib.request
    post = lambda path: urllib.request.urlopen(urllib.request.Request(f"{server}/api/foryou/trakt/{path}", method="POST"), timeout=10).read()  # noqa: E731
    post("link")
    try:
        paths_from_the_menu(browser, server)
    finally:
        post("unlink")


def paths_from_the_menu(browser, server):  # noqa: F811
    page = open_at(browser, server)
    to_media(page)
    for _ in range(5):
        if page.locator(".hero__kinds .pill.is-focused").count():
            break
        press(page, "ArrowUp", wait=400)
    opened = {}
    for label, screen in (("Guardado", "section.list-screen"), ("Colecciones", "section.showcase"), ("Filtro avanzado", "section.filter")):
        for _ in range(8):
            if page.locator(".hero__kinds .pill.is-focused").get_attribute("aria-label") == label:
                break
            press(page, "ArrowRight", wait=250)
        assert page.locator(".hero__kinds .pill.is-focused").get_attribute("aria-label") == label
        press(page, "Enter", wait=1200)
        opened[label] = page.locator(f"{screen}:not([hidden])").count() == 1
        press(page, "Escape", wait=900)
        assert page.locator(".hero__kinds .pill.is-focused").get_attribute("aria-label") == label, f"B no volvió a {label}"
    assert all(opened.values()), opened
    # Con el mouse: un clic en el ícono abre lo mismo.
    page.locator('.hero__kinds .pill[aria-label="Colecciones"]').click()
    page.locator("section.showcase:not([hidden])").wait_for(timeout=5000)
    press(page, "Escape", wait=900)
    # Explorar: X abre Decide por mí; ↑ llega a las pestañas y A en «Una por una» abre el mazo; B vuelve a Decide.
    press(page, "q", "q", "q", wait=600)
    page.wait_for_timeout(1200)
    assert page.locator("section.foryou:not([hidden])").count() == 1
    press(page, "x", wait=1500)
    page.locator("section.decide:not([hidden])").wait_for(timeout=5000)
    for _ in range(4):
        if "Una por una" in (page.evaluate(FOCUSED, ".decide__modes") or ""):
            break
        press(page, "ArrowUp", "ArrowRight", wait=300)
    assert "Una por una" in (page.evaluate(FOCUSED, ".decide__modes") or "")
    press(page, "Enter", wait=1500)
    page.locator("section.match:not([hidden])").wait_for(timeout=5000)
    press(page, "Escape", wait=900)
    assert page.locator("section.match:not([hidden])").count() == 0
    assert page.locator("section.decide:not([hidden])").count() == 1, "B en el mazo no regresó a Decide"
    assert not page.errors, page.errors


# --- Buscar escribe, filtra y elige (antes: search.test.mjs buscaba expresiones en search.js y search.css) -----------------

SEARCH_LAYOUT = """() => {
  const kb = document.querySelector('.search .keyboard').getBoundingClientRect();
  const res = document.querySelector('.search__results').getBoundingClientRect();
  const first = document.querySelector('.search .keyboard .key, .search .keyboard button');
  const row = [...document.querySelectorAll('.search .keyboard button')].filter((b) => Math.abs(b.getBoundingClientRect().top - first.getBoundingClientRect().top) < 2);
  const bg = getComputedStyle(document.querySelector('section.search')).backgroundImage;
  return { left: kb.right <= res.left + 1, columns: row.length, firstKey: row[0]?.textContent.trim(),
    focusedKey: document.querySelector('.search .keyboard .is-focused')?.textContent.trim(), sky: /radial-gradient/.test(bg),
    heads: [...document.querySelectorAll('.search__results h2, .search__results h3, .search__results .section-head')].map((n) => n.textContent.trim()) };
}"""


def test_search_writes_filters_and_picks(browser, server):  # noqa: F811
    """T7/P4: Buscar abre con el teclado alfabético de 7 columnas a la izquierda (empieza en la A) y los resultados a la derecha,
    sobre el cielo del sistema; con la caja vacía sugiere lo tuyo (sin «Populares»); con el mando A escribe y los resultados se
    filtran en vivo; → desde la orilla entra a los resultados y ← regresa al teclado. (A abre lo elegido: test_ui_flows ·
    test_search_types_and_picks.)"""
    page = open_at(browser, server)
    press(page, "s", wait=1200)
    layout = page.evaluate(SEARCH_LAYOUT)
    assert layout["left"] and layout["columns"] == 7 and layout["firstKey"] == "A" and layout["focusedKey"] == "A", layout
    assert layout["sky"], layout
    heads = " · ".join(layout["heads"])
    assert "Seguir viendo" in heads and "Tus juegos" in heads and "Populares" not in heads, heads
    # Con el mando: A escribe la letra enfocada («A»), ▶ ▶ y A escriben «C»… hasta «ha» de Hades (H es la primera de la fila 2).
    press(page, "ArrowDown", "Enter", wait=300)  # H
    press(page, "ArrowUp", "Enter", wait=300)  # A
    page.wait_for_timeout(1200)
    typed = page.locator(".search input, .search .search__field").first.input_value() if page.locator(".search input").count() \
        else page.locator(".search .search__field").first.inner_text()
    assert typed.lower().startswith("ha"), typed
    names = page.evaluate("() => [...document.querySelectorAll('.search__results .card')].map((c) => c.getAttribute('aria-label') || '')")
    assert names and all("ha" in n.lower() for n in names), names  # filtra: solo lo que dice «ha»
    assert any("Hades" in n for n in names), names
    # → desde la orilla del teclado entra a los resultados; ← desde la primera columna vuelve.
    for _ in range(8):
        if page.locator(".search__results .is-focused").count():
            break
        press(page, "ArrowRight", wait=150)
    assert page.locator(".search__results .is-focused").count() == 1
    press(page, "ArrowLeft", wait=300)
    assert page.locator(".search__results .is-focused").count() == 0 and page.locator(".search .keyboard .is-focused").count() == 1
    for _ in range(8):
        if page.locator(".search__results .is-focused").count():
            break
        press(page, "ArrowRight", wait=150)
    assert page.evaluate(FOCUSED, ".search__results")  # A abre lo elegido: test_ui_flows · test_search_types_and_picks
    assert not page.errors, page.errors


# --- Moverse en una fila solo repinta dos tarjetas (antes: rendimiento.test.mjs leía shelf.js) -----------------------------

def test_moving_in_a_row_repaints_only_two_cards(browser, server):  # noqa: F811
    """V2: en Películas y series, ▶ dentro de una fila cambia la clase de la tarjeta que deja el foco y la que lo recibe, nada
    más (antes recorría todas las filas en cada tecla)."""
    page = open_at(browser, server)
    to_media(page)
    press(page, "ArrowDown", wait=1200)
    page.evaluate("""() => { window.__touched = new Set();
      window.__watch = new MutationObserver((list) => { for (const m of list) if (m.target.classList?.contains('card')) window.__touched.add(m.target); });
      window.__watch.observe(document.querySelector('.shelf'), { subtree: true, attributes: true, attributeFilter: ['class'] }); }""")
    counts = []
    for _ in range(3):
        page.evaluate("() => window.__touched.clear()")
        press(page, "ArrowRight", wait=500)
        counts.append(page.evaluate("() => window.__touched.size"))
    assert max(counts) <= 2, counts
    assert not page.errors, page.errors
