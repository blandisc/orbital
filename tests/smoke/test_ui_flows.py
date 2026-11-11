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
    assert not page.errors, page.errors
