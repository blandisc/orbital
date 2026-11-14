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


def test_touched_piece_is_never_cut(browser, server):  # noqa: F811
    """«Un listón no recorta lo que crece» (iPhone, 13 nov 2026) en la TV con el dedo: el póster que asoma en la orilla de una
    fila, tocado, crece entero (la fila se corre); y lo que el dedo sube en Inicio y en Juegos no se queda invisible
    (docs/sistema-de-diseno.md § 5, «Lo que el dedo desplaza se ve entero»)."""
    context = browser.new_context(viewport={"width": 1280, "height": 800}, has_touch=True)
    page = context.new_page()
    with_videos(page)
    page.goto(server)
    ready(page)
    cdp = context.new_cdp_session(page)

    def touch(kind, x=0, y=0):
        cdp.send("Input.dispatchTouchEvent", {"type": kind, "touchPoints": [] if kind == "touchEnd" else [{"x": x, "y": y}]})

    def tap(x, y, wait=1500):
        touch("touchStart", x, y)
        page.wait_for_timeout(60)
        touch("touchEnd")
        page.wait_for_timeout(wait)

    def drag(y1, y2, x=380):
        touch("touchStart", x, y1)
        for i in range(1, 13):
            touch("touchMove", x, y1 + (y2 - y1) * i / 12)
            page.wait_for_timeout(16)
        touch("touchEnd")
        page.wait_for_timeout(1500)

    cuts = {}
    for name, x, y in [("Inicio · la orilla de A continuación", 1180, 520)]:
        tap(x, y)
        if found := page.evaluate(FOCUS_CLIP):
            cuts[name] = found
    drag(600, 300, x=640)  # el Inicio sube con el dedo: las consolas, enteras y sin su asomo desvanecido
    assert page.evaluate("() => !document.querySelector('.home').classList.contains('home--peek')")
    tap(784, 63, wait=2000)  # Películas y series
    tap(1240, 560)
    if found := page.evaluate(FOCUS_CLIP):
        cuts["Películas y series · la orilla de una fila"] = found
    page.keyboard.press("q")  # Juegos, en una tele chica (varias filas): bajar con el mando, regresar con el dedo
    page.set_viewport_size({"width": 760, "height": 560})
    page.wait_for_timeout(2000)
    for key in ("ArrowDown", "ArrowDown", "ArrowDown"):
        page.keyboard.press(key)
        page.wait_for_timeout(500)
    drag(250, 500)
    hidden = page.evaluate("() => [...document.querySelectorAll('.games__grid > .is-above')].length")
    assert not cuts, cuts
    assert not hidden, f"{hidden} portadas invisibles tras deslizar hacia abajo en Juegos"
    context.close()


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


def test_collection_is_not_a_ranking_and_porque_viste_shows_focus(browser, server):  # noqa: F811
    """R2-3 y R2-4 (11 nov): la Colección Criterion no es un ranking (sus pósters no traen puesto): ningún «null» grande ni
    «Puesto null». Y el escenario de «Porque viste» lleva la órbita cuando el foco está en él, como cualquier póster."""
    import urllib.request
    post = lambda path: urllib.request.urlopen(urllib.request.Request(f"{server}/api/foryou/trakt/{path}", method="POST"), timeout=10).read()  # noqa: E731
    post("link")  # «Porque viste» sale de tu historial de Trakt (la demostración trae uno)
    try:
        _collection_and_stage(open_at(browser, server, videos=False))
    finally:
        post("unlink")


def _collection_and_stage(page):
    page.keyboard.press("e")
    page.keyboard.press("e")  # Películas y series
    page.locator(".shelf__stage").wait_for(state="attached", timeout=30000)
    page.wait_for_timeout(800)
    stage = None
    for _ in range(8):
        stage = page.evaluate("() => { const s = document.querySelector('.shelf__stage'); return s && [s.classList.contains('is-focused'), !!s.querySelector(':scope > .orbit')]; }")
        if stage and stage[0]:
            break
        page.keyboard.press("ArrowDown")
        page.wait_for_timeout(500)
    assert stage == [True, True], stage
    page.locator("button.pill[aria-label=Colecciones]").click()
    page.locator(".showcase__item").first.wait_for(timeout=5000)
    page.wait_for_timeout(500)
    page.locator(".showcase__item[aria-label^='Colección Criterion']").click()
    page.keyboard.press("Enter")
    page.locator(".list-screen .card").first.wait_for(timeout=8000)
    page.wait_for_timeout(800)
    found = page.evaluate("""() => ({
      nulls: [...document.querySelectorAll('.list-screen *')].filter((e) => !e.childElementCount && /^\\s*null\\s*$/.test(e.textContent)).length,
      labels: [...document.querySelectorAll('.list-screen [aria-label]')].map((e) => e.getAttribute('aria-label')).filter((l) => /null|undefined/.test(l)) })""")
    assert found == {"nulls": 0, "labels": []}, found
    assert not page.errors, page.errors


def long_watchlist(page, n=300) -> None:
    """Tu Mi lista con `n` títulos (cada uno con su tt propio), para la lista larga (V4)."""
    def lists(route):
        res = route.fetch()
        data = res.json()
        for entry in data.get("lists", []):
            if entry.get("id") == "watchlist" and entry.get("items"):
                base = entry["items"][0]
                entry["items"] = [{**base, "key": f"video:tt9{i:06d}", "id": f"cinemeta:movie:tt9{i:06d}", "meta_id": f"tt9{i:06d}",
                                   "title": f"Película {i}"} for i in range(n)]
        route.fulfill(response=res, json=data)
    page.route("**/api/foryou/lists", lists)


def linked_settings(page) -> None:
    """Los ajustes dicen «Trakt conectado» (el servidor de pruebas no tiene la llave de la app, así que dice que no)."""
    def settings(route):
        res = route.fetch()
        data = res.json()
        data["trakt"] = {**(data.get("trakt") or {}), "configured": True, "linked": True}
        route.fulfill(response=res, json=data)
    page.route("**/api/settings", settings)


LIST_STATE = """() => {
  const s = document.querySelector('.list-screen'); const grid = s.querySelector('.card-grid');
  const f = s.querySelector('.card-grid .is-focused'); const r = f && f.getBoundingClientRect();
  const view = grid.parentElement.getBoundingClientRect();
  const inView = [...grid.children].filter((c) => { const b = c.getBoundingClientRect(); return b.bottom > view.top && b.top < view.bottom; });
  return { cards: grid.children.length, slots: grid.querySelectorAll('.card--slot').length, focus: f && f.dataset.focusId,
    armed: !!f && !f.classList.contains('card--slot'), whole: !!r && r.top >= 0 && r.bottom <= innerHeight,
    emptyInView: inView.filter((c) => c.classList.contains('card--slot')).length,
    toast: document.querySelector('.toast')?.textContent || '' };
}"""


def test_long_list_and_editing_your_list(browser, server):  # noqa: F811
    """V4 en una lista (revisión 2, 17d, 11 nov): Mi lista con 300 títulos arma solo lo cercano y la enfocada siempre está
    armada. Y editarla (lo que salió de main.js a app/list-editing.js): Y › «Quitar de esta lista» la quita al instante,
    «Deshacer» la regresa a su lugar; «Guardar en…» abre la hoja con tus listas de Trakt."""
    import json
    import urllib.request
    post = lambda path: urllib.request.urlopen(urllib.request.Request(f"{server}/api/foryou/trakt/{path}", method="POST"), timeout=10).read()  # noqa: E731
    post("link")
    # La demo «escribe el código en el celular» a los ~6 s (demo_foryou.poll_device): antes de abrir la página, Trakt ya está
    # conectado. Si no, Para ti cargaba sin Mi lista y su tarjeta no llegaba nunca (fallaba a ratos en Windows, 11 nov).
    linked = lambda: json.load(urllib.request.urlopen(f"{server}/api/foryou", timeout=10))["status"]["trakt"]["linked"]  # noqa: E731
    deadline = time.monotonic() + 60
    while not linked():
        assert time.monotonic() < deadline, "La demo no conectó Trakt en 60 s"
        time.sleep(.25)
    try:
        page = browser.new_page(viewport={"width": 1920, "height": 1080})
        page.errors = []
        page.on("pageerror", lambda exc: page.errors.append(str(exc)))
        long_watchlist(page)
        linked_settings(page)
        page.goto(server)
        ready(page)
        page.keyboard.press("e")
        page.keyboard.press("e")  # Películas y series
        mine = page.locator("button.card--list[aria-label='Mi lista']").first
        mine.wait_for(state="attached", timeout=60000)
        mine.click()
        page.wait_for_function("() => document.activeElement?.matches?.(\"button.card--list[aria-label='Mi lista']\")"
                               " || document.querySelector(\"button.card--list[aria-label='Mi lista'].is-focused\")", timeout=30000)
        page.keyboard.press("Enter")
        # Sin esperas a reloj (11 nov): cada paso espera su condición, con tope amplio para el runner de Windows.
        state = lambda: page.evaluate(LIST_STATE)  # noqa: E731
        page.wait_for_function("() => document.querySelectorAll('.list-screen .card-grid > *').length === 300", timeout=30000)
        page.wait_for_function("() => !!document.querySelector('.list-screen .card-grid .is-focused')", timeout=30000)
        first = state()
        assert first["cards"] == 300 and first["slots"] > 200, first
        for _ in range(15):
            before = page.evaluate("() => document.querySelector('.list-screen .card-grid .is-focused')?.dataset.focusId")
            page.keyboard.press("ArrowDown")
            page.wait_for_function("(id) => { const f = document.querySelector('.list-screen .card-grid .is-focused');"
                                   " return !!f && f.dataset.focusId !== id; }", arg=before, timeout=30000)
        # Que la cuadrícula termine de deslizarse y de armar lo cercano: la enfocada armada y entera, ninguna vacía a la vista.
        page.wait_for_function(f"() => {{ const s = ({LIST_STATE})(); return s.armed && s.whole && s.emptyInView === 0; }}",
                               timeout=30000)
        deep = state()
        assert deep["focus"] not in (None, first["focus"]) and deep["armed"] and deep["whole"] and deep["emptyInView"] == 0, deep
        # Quitar la enfocada: sale ya, con «Deshacer».
        page.keyboard.press("y")
        page.locator(".sheet").get_by_text("Quitar de esta lista").click()
        page.wait_for_function("() => document.querySelectorAll('.list-screen .card-grid > *').length === 299"
                               " && (document.querySelector('.toast')?.textContent || '').includes('Deshacer')", timeout=30000)
        gone = state()
        assert gone["cards"] == 299 and "Quitada de «Mi lista»" in gone["toast"], gone
        page.locator(".toast").get_by_text("Deshacer").click()
        page.wait_for_function("() => document.querySelectorAll('.list-screen .card-grid > *').length === 300", timeout=30000)
        assert state()["cards"] == 300
        # «Guardar en…» de un póster: la hoja con Mi lista, Favoritos y tus listas de Trakt.
        page.keyboard.press("y")
        page.locator(".sheet").get_by_text("Guardar en…").first.click()
        page.locator(".sheet").get_by_text("Tus listas de Trakt").wait_for(timeout=30000)
        page.locator(".sheet").get_by_text("Favoritos").first.wait_for(timeout=30000)  # la hoja se arma por partes
        assert not page.errors, page.errors
        page.close()
    finally:
        post("unlink")


@pytest.mark.parametrize(("width", "height"), [(1920, 1080), (1280, 800)])
def test_choose_version_is_whole_and_the_notice_does_not_cover(browser, server, width, height):  # noqa: F811
    """R3-1 (revisión 2, punto 11): en «Elegir versión» la etiqueta de arriba es la turquesa del sistema; al bajar, «Ver los
    demás» enfocada se ve entera y sin velo; al subir, la fila de arriba tampoco queda bajo el fundido; y el aviso «Esa versión
    ya no está» no tapa ninguna tarjeta. La demo sirve la ficha de Dune y sus versiones sin internet."""
    page = browser.new_page(viewport={"width": width, "height": height})
    errors: list[str] = []
    page.on("pageerror", lambda exc: errors.append(str(exc)))
    page.route("**/api/stremio/play", lambda r: r.fulfill(
        status=409, json={"detail": "Esa versión ya no está disponible; vuelve a abrir la lista"}))
    page.goto(f"{server}/?pelicula=tt15239678")
    ready(page)
    page.locator("section.title:not([hidden])").wait_for(timeout=8000)
    page.wait_for_timeout(1200)
    page.keyboard.press("y")
    page.locator(".sources .version").first.wait_for(timeout=8000)
    page.wait_for_timeout(800)
    if page.locator(".sheet__title", has_text="Así funciona").is_visible():
        page.keyboard.press("Enter")
        page.wait_for_timeout(600)
    colors = page.evaluate("""() => {
      const probe = document.createElement('span'); probe.style.color = 'var(--color-reason)'; document.body.append(probe);
      const want = getComputedStyle(probe).color; probe.remove();
      return [getComputedStyle(document.querySelector('.sources__heading')).color, want]; }""")
    assert colors[0] == colors[1], colors
    whole = """() => {
      const list = document.querySelector('.sources__list'), el = list.querySelector('.is-focused');
      const a = list.getBoundingClientRect(), b = el.getBoundingClientRect(), fade = 3 * parseFloat(getComputedStyle(document.documentElement).fontSize);
      const up = list.classList.contains('sources__list--up'), down = list.classList.contains('sources__list--down');
      return { text: el.textContent.trim().slice(0, 20), up, down,
               top: b.top - a.top - (up ? fade : 0), bottom: a.bottom - b.bottom - (down ? fade : 0) }; }"""
    for _ in range(12):
        page.keyboard.press("ArrowDown")
        page.wait_for_timeout(150)
    page.wait_for_timeout(700)
    end = page.evaluate(whole)
    assert end["text"].startswith("Ver los demás"), end
    assert not end["down"] and end["top"] >= -1 and end["bottom"] >= -1, end
    for _ in range(12):
        page.keyboard.press("ArrowUp")
        page.wait_for_timeout(150)
    page.wait_for_timeout(700)
    start = page.evaluate(whole)
    assert not start["up"] and start["top"] >= -1 and start["bottom"] >= -1, start
    page.keyboard.press("Enter")
    page.locator(".toast:not([hidden])").wait_for(timeout=5000)
    page.wait_for_timeout(700)
    toast = page.evaluate("""() => {
      const t = document.querySelector('.toast').getBoundingClientRect();
      const hit = [...document.querySelectorAll('.sources .version')].filter((v) => {
        const r = v.getBoundingClientRect();
        return r.height && r.left < t.right && r.right > t.left && r.top < t.bottom && r.bottom > t.top; });
      return { text: document.querySelector('.toast').innerText, hit: hit.map((v) => v.textContent.trim().slice(0, 20)) }; }""")
    assert "Esa versión ya no está" in toast["text"] and "Elige otra de la lista" in toast["text"], toast
    assert not toast["hit"], toast
    assert not errors, errors
    page.close()


def test_live_tv_with_hundreds_of_channels_arms_only_what_is_near(browser, server):  # noqa: F811
    """R3-2 (V4 en TV en vivo): con 400 canales la cuadrícula no los arma todos (lejos de la vista son huecos del alto de un
    canal), y el foco, la vista previa del enfocado, el salto de categoría, la rueda y el dedo siguen como siempre."""
    page = browser.new_page(viewport={"width": 1920, "height": 1080})
    errors: list[str] = []
    page.on("pageerror", lambda exc: errors.append(str(exc)))

    def many(route):
        res = route.fetch()
        data = res.json()
        extra = [{"id": f"demo:{n}", "name": f"Canal {n}", "categories": ["General"], "quality": "720p", "synthetic": False,
                  "tagline": "", "logo": None, "number": 100 + n, "verified": True, "now": None} for n in range(400 - len(data["channels"]))]
        data["channels"] = [*data["channels"], *extra]
        for cat in data["categories"]:
            if cat["id"] in ("todos", "general"):
                cat["count"] += len(extra)
        route.fulfill(response=res, json=data)

    page.route("**/api/tv", many)
    page.goto(server)
    ready(page)
    for _ in range(3):  # Inicio → Juegos → Películas y series → TV en vivo
        page.keyboard.press("e")
        page.wait_for_timeout(350)
    page.locator(".tv__tile.is-focused").wait_for(timeout=8000)
    page.wait_for_timeout(600)
    count = """() => ({ cells: document.querySelectorAll('.tv__grid [data-focus-id^="channel:"]').length,
      armed: document.querySelectorAll('.tv__grid .tv__tile.tile').length,
      focused: document.querySelectorAll('.tv__grid .tile.is-focused').length,
      name: document.querySelector('.tv__grid .tile.is-focused')?.getAttribute('aria-label') || '',
      now: document.querySelector('.tv__now-title')?.textContent || '',
      seen: (() => { const f = document.querySelector('.tv__grid .tile.is-focused'); if (!f) return false;
        const r = f.getBoundingClientRect(), v = document.querySelector('.tv__viewport').getBoundingClientRect();
        return r.top >= v.top - 1 && r.bottom <= v.bottom + 1; })() })"""
    start = page.evaluate(count)
    assert page.locator(".tv__cat--on").inner_text().startswith("Todos")
    assert start["cells"] == 400, start
    assert start["armed"] < 150, start  # antes: los 400 armados con su logo, su número y su nombre
    for _ in range(40):
        page.keyboard.press("ArrowDown")
        page.wait_for_timeout(60)
    page.wait_for_timeout(900)
    deep = page.evaluate(count)
    assert deep["focused"] == 1 and deep["seen"], deep
    assert deep["armed"] < 150, deep
    assert deep["now"] and deep["now"] in deep["name"], deep  # la vista previa es la del canal enfocado
    page.mouse.move(1200, 800)
    page.mouse.wheel(0, 120)
    page.wait_for_timeout(700)
    wheeled = page.evaluate(count)
    assert wheeled["focused"] == 1 and wheeled["seen"] and wheeled["name"] != deep["name"], wheeled
    page.keyboard.press("PageDown")  # la categoría siguiente
    page.wait_for_timeout(500)
    assert page.locator(".tv__cat--on").inner_text().startswith("Tus canales")
    assert page.evaluate(count)["cells"] == 5
    page.keyboard.press("PageUp")
    page.wait_for_timeout(500)
    back = page.evaluate(count)
    assert page.locator(".tv__cat--on").inner_text().startswith("Todos") and back["cells"] == 400 and back["focused"] == 1, back
    assert back["armed"] < 150, back
    assert not errors, errors
    page.close()
