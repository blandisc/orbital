"""Pruebas de humo de la cuarta tanda (P4, 10 nov 2026): lo que se ve (tarjetas con nombre, foco entero) y los flujos con el
mando que no tenían prueba (F11). Mismo servidor de demostración y mismo navegador que test_ui_smoke.py."""

from __future__ import annotations

import time

import pytest
from test_ui_smoke import playwright, ready, server  # noqa: F401  (server es un fixture)


def _video(meta_id, title, kind, subtitle, progress, hero, when):
    return {"id": f"stremio:{meta_id}", "title": title, "category": "continue", "source": "stremio", "subtitle": subtitle,
            "image": "/img/placeholders/cover-generic-1.jpg", "hero": f"/img/placeholders/{hero}", "progress": progress,
            "last_watched": when, "last_played": when, "meta_id": meta_id,
            "extra": {"kind": kind, "meta_id": meta_id, "video_id": f"{meta_id}:2:3", "from_trakt": True}}


def with_videos(page) -> None:
    """Como en la casa: The Office e Interstellar a medias (de Trakt) mezclados con los juegos, y sin logo para The Office
    (sin internet, o TMDB que no lo tiene): así se ve una tarjeta sin arte propio."""
    now = time.time()
    office = _video("tt0386676", "The Office", "series", "T2 E3 · quedan 12 min", .42, "hero-generic-3.jpg", now - 60)
    inter = _video("tt0816692", "Interstellar", "movie", "quedan 1 h 10 min", .3, "hero-xbox-2.jpg", now - 7200)
    sev = _video("tt11280740", "Severance", "series", "T1 E2 · quedan 30 min", .5, "hero-switch-2.jpg", now - 86400 * 5)

    def library(route):
        res = route.fetch()
        data = res.json()
        jump = next((r for r in data["rows"] if r["id"] == "jump"), None)
        if jump is not None:
            jump["items"] = [office, *jump["items"][:2], inter, *jump["items"][2:]]
        data["rows"].append({"id": "continue", "title": "Seguir viendo", "items": [office, inter, sev]})
        route.fulfill(response=res, json=data)

    page.route("**/api/library*", library)
    page.route("**/api/foryou/logo/tt0386676*", lambda route: route.fulfill(status=404, body=""))


@pytest.fixture
def browser():
    with playwright.sync_playwright() as p:
        b = p.chromium.launch(channel=__import__("os").environ.get("ORBITAL_SMOKE_BROWSER") or None)
        yield b
        b.close()


def open_at(browser, server, width=1920, height=1080, videos=True):  # noqa: F811
    page = browser.new_page(viewport={"width": width, "height": height})
    errors: list[str] = []
    page.on("pageerror", lambda exc: errors.append(str(exc)))
    page.errors = errors
    if videos:
        with_videos(page)
    page.goto(server)
    ready(page)
    return page


# Una tarjeta dice qué es: su logo ya visible, su nombre encima, su nombre debajo o un póster propio (que trae su título).
NAMELESS = """
() => {
  const shown = (el) => { const r = el.getBoundingClientRect(); return r.width > 0 && r.height > 0 && r.right > 0 && r.left < innerWidth && r.bottom > 0 && r.top < innerHeight && getComputedStyle(el).visibility !== 'hidden'; };
  const says = (card) => {
    if (card.classList.contains('card--logo-ready')) return true;
    const meta = card.querySelector('.card__meta');
    if (meta && getComputedStyle(meta).display !== 'none' && meta.textContent.trim()) return true;
    const label = card.querySelector('.card__label');
    if (label && label.textContent.trim()) return true;
    if (card.classList.contains('card--has-art') && !card.classList.contains('card--wide')) {
      const img = card.querySelector('img.card__image');
      return !!img && !/img\\/placeholders\\//.test(img.getAttribute('src') || '');
    }
    return card.classList.contains('card--stand-in') || !!card.querySelector('.card__placeholder--app');
  };
  return [...document.querySelectorAll('.card')].filter((c) => shown(c) && !says(c)).map((c) => c.getAttribute('aria-label'));
}
"""


@pytest.mark.parametrize(("width", "height"), [(1920, 1080), (1280, 800)])
def test_every_card_says_what_it_is(browser, server, width, height):  # noqa: F811
    """P4-1 (Fernando, 10 nov: The Office salía en blanco en «A continuación», solo con su barra): toda tarjeta sin arte
    propio ni logo lleva su nombre sobre el arte de respaldo, como «Mario Party Superstars»."""
    page = open_at(browser, server, width, height)
    page.wait_for_timeout(1500)
    found = {"Inicio": page.evaluate(NAMELESS)}
    page.keyboard.press("e")
    page.keyboard.press("e")  # Películas y series
    page.wait_for_timeout(1500)
    found["Películas y series"] = page.evaluate(NAMELESS)
    assert not any(found.values()), found
    # Lo que te falta de algo a medias se lee entero: «T2 E3 · quedan 12 min», no «T2 E3 · queda…» (pasada P4).
    cut = page.evaluate("""() => [...document.querySelectorAll('.card--named.card--has-progress .card__subtitle')]
      .filter((s) => s.getClientRects().length && s.scrollHeight > s.clientHeight + 1).map((s) => s.textContent)""")
    assert not cut, cut
    assert not page.errors, page.errors


FOCUS_CLIP = (__import__("pathlib").Path(__file__).parent / "focus_clip.js").read_text(encoding="utf-8")


@pytest.mark.parametrize(("width", "height"), [(1920, 1080), (1280, 800)])
def test_focused_piece_is_never_cut(browser, server, width, height):  # noqa: F811
    """P4 (Fernando, 10 nov: «la tarjeta enfocada de A continuación se ve cortada por arriba»): lo enfocado, ya crecido y
    con su órbita, se ve entero en cada fila y rejilla: ningún contenedor lo recorta y no se sale de la pantalla."""
    page = open_at(browser, server, width, height)
    cuts, seen = {}, {}

    def look(name):
        page.wait_for_timeout(900)
        seen[name] = page.evaluate("() => document.querySelectorAll('.is-focused:is(.card, .tile, .person-chip, .episode)').length")
        found = page.evaluate(FOCUS_CLIP)
        if found:
            cuts[name] = found

    def press(*keys, wait=350):
        for key in keys:
            page.keyboard.press(key)
            page.wait_for_timeout(wait)

    look("Inicio · A continuación")
    press("ArrowRight", "ArrowRight")
    look("Inicio · A continuación, a media fila")
    press("ArrowDown")
    look("Inicio · la fila de abajo")
    press("e", wait=900)
    look("Juegos")
    press("ArrowDown", "ArrowRight")
    look("Juegos · la rejilla")
    press("e", wait=1200)
    look("Películas y series")
    press("ArrowDown", "ArrowRight")
    look("Películas y series · otra fila")
    press("e", wait=1200)
    press("ArrowRight")
    look("TV en vivo")
    press("s", wait=600)
    page.keyboard.type("office")
    page.locator(".search button.card").first.wait_for(timeout=5000)
    press(*["ArrowRight"] * 10, wait=120)
    look("Buscar · resultados")
    press("Enter", wait=2500)
    page.locator("section.title:not([hidden])").wait_for(timeout=8000)
    press("ArrowDown", wait=700)
    look("La ficha · episodios")
    press("ArrowDown", wait=700)
    look("La ficha · abajo")
    assert all(seen.values()), f"sin foco que medir: {seen}"
    assert not cuts, cuts
    assert not page.errors, page.errors


@pytest.mark.parametrize(("width", "height"), [(1920, 1080), (1280, 800)])
def test_search_looks_like_the_rest(browser, server, width, height):  # noqa: F811
    """P4-3 (10 nov): Buscar con el teclado alfabético de 7 columnas, sugerencias con la caja vacía (lo que estás viendo y
    tus juegos) y los resultados en la cuadrícula de una lista: todas las portadas del mismo tamaño, sin nombres cortados."""
    page = open_at(browser, server, width, height)
    page.keyboard.press("s")
    page.locator(".search .keyboard__key").first.wait_for(timeout=5000)
    page.wait_for_timeout(600)
    first_row = page.evaluate("() => [...document.querySelectorAll('.search .keyboard__key')].slice(0, 7).map((k) => k.textContent)")
    assert first_row == list("ABCDEFG"), first_row
    groups = page.evaluate("() => [...document.querySelectorAll('.search__group')].map((g) => g.textContent)")
    assert groups[:2] == ["Seguir viendo", "Tus juegos"], groups
    page.keyboard.type("zelda")
    page.locator(".search .card-grid button.card").first.wait_for(timeout=5000)
    page.wait_for_timeout(1200)
    sizes = page.evaluate("() => [...document.querySelectorAll('.search .card-grid .card')].map((c) => [c.offsetWidth, c.offsetHeight])")
    assert sizes and len(set(map(tuple, sizes))) == 1, sizes  # una sola forma y un solo tamaño
    cut = page.evaluate("""() => [...document.querySelectorAll('.search .card-grid .card :is(.card__title, .card__label)')]
      .filter((t) => getComputedStyle(t.closest('.card__meta') || t).display !== 'none' && t.scrollHeight > t.clientHeight + 1)
      .map((t) => t.textContent)""")
    assert not cut, cut
    assert not page.errors, page.errors


# F11 (P4): los flujos con el mando que no tenían prueba de DOM (no hay jsdom: se prueban en el navegador de verdad).
FOCUSED_IN = "(scope) => { const e = document.querySelector(`${scope} .is-focused`); return e && (e.getAttribute('aria-label') || e.textContent.trim()); }"


def test_menu_reaches_every_entry(browser, server):  # noqa: F811
    """☰ (M) abre el menú y ↓ llega a cada entrada, una por una, y da la vuelta al final."""
    page = open_at(browser, server)
    page.wait_for_timeout(1500)
    if page.locator(".sheet .sheet__item").first.is_visible():  # la guía de la primera vez, si salió: se cierra
        page.keyboard.press("Escape")
        page.wait_for_timeout(600)
    page.keyboard.press("m")
    page.locator(".sheet .sheet__item").first.wait_for(timeout=5000)
    page.wait_for_timeout(500)
    if page.locator(".sheet .sheet__item", has_text="Listo").count():  # con la consola recién puesta, ☰ abre su guía: «Listo»
        page.locator(".sheet .sheet__item", has_text="Listo").click()
        page.wait_for_timeout(800)
        page.keyboard.press("m")
        page.locator(".sheet .sheet__item", has_text="Ajustes").wait_for(timeout=5000)
        page.wait_for_timeout(500)
    count = page.locator(".sheet .sheet__item").count()
    seen = []
    for _ in range(count + 1):
        seen.append(page.evaluate(FOCUSED_IN, ".sheet"))
        page.keyboard.press("ArrowDown")
        page.wait_for_timeout(150)
    assert None not in seen, seen
    assert len(set(seen[:count])) == count, seen  # cada entrada, una vez
    assert seen[count] == seen[0], seen  # y vuelve a la primera
    assert any("Ajustes" in s for s in seen), seen
    assert not page.errors, page.errors


def test_home_to_title_and_back_keeps_focus(browser, server):  # noqa: F811
    """Inicio → la ficha (Y › Ver episodios) → B: de vuelta en Inicio, el foco sigue en la misma tarjeta."""
    page = open_at(browser, server)
    page.wait_for_timeout(800)
    before = page.evaluate(FOCUSED_IN, ".home")
    assert before == "The Office", before
    page.keyboard.press("y")
    page.locator(".sheet .sheet__item").first.wait_for(timeout=5000)
    page.wait_for_timeout(400)
    assert "Ver episodios" in page.evaluate(FOCUSED_IN, ".sheet")
    page.keyboard.press("Enter")
    page.locator("section.title:not([hidden])").wait_for(timeout=8000)
    page.wait_for_timeout(800)
    page.keyboard.press("Escape")
    page.locator("section.title").wait_for(state="hidden", timeout=5000)
    page.wait_for_timeout(600)
    assert page.evaluate(FOCUSED_IN, ".home") == before
    assert not page.errors, page.errors


def test_search_types_and_picks(browser, server):  # noqa: F811
    """Buscar (S): escribir «office», RT/AvPág salta a los resultados y A abre la ficha de lo elegido."""
    page = open_at(browser, server)
    page.keyboard.press("s")
    page.keyboard.type("office")
    page.locator(".search .card-grid button.card").first.wait_for(timeout=5000)
    page.wait_for_timeout(1200)
    page.keyboard.press("PageDown")
    page.wait_for_timeout(300)
    picked = page.evaluate(FOCUSED_IN, ".search__results")
    assert picked, "RT/AvPág no llevó el foco a los resultados"
    page.keyboard.press("Enter")
    page.locator("section.title:not([hidden])").wait_for(timeout=8000)
    assert picked in page.locator("section.title:not([hidden])").inner_text(), picked
    assert not page.errors, page.errors


def test_tabs_are_reached_with_up(browser, server):  # noqa: F811
    """Películas y series: ↑ desde el contenido llega a las pestañas (Todo · Películas · Series) y → cambia de pestaña."""
    page = open_at(browser, server)
    page.keyboard.press("e")
    page.keyboard.press("e")
    page.wait_for_timeout(1800)
    for _ in range(5):
        if page.locator(".pill--tab.is-focused").count():
            break
        page.keyboard.press("ArrowUp")
        page.wait_for_timeout(400)
    assert page.locator(".pill--tab.is-focused").inner_text().strip() == "Todo"
    page.keyboard.press("ArrowRight")
    page.wait_for_timeout(900)
    assert page.locator(".pill--tab.is-focused").inner_text().strip() == "Películas"
    assert not page.errors, page.errors


# V4 (P4): una consola con cientos de juegos arma solo lo que está cerca de la vista, y todo sigue igual: el foco llega a
# donde vas y siempre armado y entero, la consola recuerda el juego al volver, la rueda del ratón baja y el dedo trae portadas
# ya armadas (ningún hueco vacío a la vista).
def many_games(page, n=300) -> None:
    def library(route):
        res = route.fetch()
        data = res.json()
        now = time.time()
        for row in data["rows"]:
            if row["id"] == "steam":
                base = row["items"][0]
                row["items"] = [{**base, "id": f"steam:v4-{i}", "title": f"Juego {i}", "image": f"/img/placeholders/cover-generic-{1 + i % 3}.jpg",
                                 "last_played": now - i * 60, "extra": {**(base.get("extra") or {}), "logo": None}} for i in range(n)]
        route.fulfill(response=res, json=data)

    page.route("**/api/library*", library)


GRID_STATE = """() => {
  const grid = document.querySelector('.games .card-grid'); const view = grid.parentElement.getBoundingClientRect();
  const f = grid.querySelector('.is-focused'); const r = f && f.getBoundingClientRect();
  const inView = [...grid.children].filter((c) => { const b = c.getBoundingClientRect(); return b.bottom > view.top && b.top < view.bottom; });
  return { focus: f && f.dataset.focusId, armed: !!f && !f.classList.contains('card--slot') && !!f.querySelector('img'),
    whole: !!r && r.top >= 0 && r.bottom <= innerHeight, slots: grid.querySelectorAll('.card--slot').length,
    emptyInView: inView.filter((c) => c.classList.contains('card--slot')).length, cards: grid.children.length };
}"""


def test_long_grid_arms_only_what_is_near(browser, server):  # noqa: F811
    page = browser.new_page(viewport={"width": 1920, "height": 1080})
    errors: list[str] = []
    page.on("pageerror", lambda exc: errors.append(str(exc)))
    many_games(page)
    page.goto(server)
    ready(page)
    page.keyboard.press("e")
    page.wait_for_timeout(1500)
    page.keyboard.press("ArrowDown")
    state = page.evaluate(GRID_STATE)
    assert state["cards"] == 300 and state["slots"] > 200, state  # cada juego tiene su lugar; casi todos, hueco
    for _ in range(20):
        page.keyboard.press("ArrowDown")
        page.wait_for_timeout(120)
    page.wait_for_timeout(800)
    deep = page.evaluate(GRID_STATE)
    assert deep["focus"] not in (None, state["focus"]) and deep["armed"] and deep["whole"] and deep["emptyInView"] == 0, deep
    # La consola recuerda el juego: a otra y de regreso, el mismo.
    page.keyboard.press("PageDown")
    page.wait_for_timeout(900)
    page.keyboard.press("PageUp")
    page.wait_for_timeout(1200)
    back = page.evaluate(GRID_STATE)
    assert back["focus"] == deep["focus"] and back["armed"] and back["emptyInView"] == 0, back
    # La rueda del ratón baja como ↓.
    page.mouse.move(960, 700)
    for _ in range(6):
        page.mouse.wheel(0, 120)
        page.wait_for_timeout(250)
    page.wait_for_timeout(800)
    wheeled = page.evaluate(GRID_STATE)
    assert int(wheeled["focus"].split(":")[1]) > int(back["focus"].split(":")[1]) and wheeled["armed"] and wheeled["emptyInView"] == 0, wheeled
    # El dedo: arrastrar hacia arriba trae lo de abajo, ya armado.
    page.evaluate("""() => {
      const v = document.querySelector('.games__viewport'); const fire = (type, y) => v.dispatchEvent(new PointerEvent(type,
        { pointerType: 'touch', clientX: 900, clientY: y, bubbles: true, pointerId: 7 }));
      fire('pointerdown', 900); for (let y = 880; y >= 200; y -= 40) fire('pointermove', y); fire('pointerup', 200);
    }""")
    page.wait_for_timeout(1500)
    dragged = page.evaluate(GRID_STATE)
    assert dragged["emptyInView"] == 0, dragged
    assert not errors, errors
    page.close()
