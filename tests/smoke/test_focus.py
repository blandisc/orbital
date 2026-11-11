"""«El foco nunca se pierde» (R3-5, 11 nov 2026): 300 teclas al azar, con semilla fija, desde cada pantalla (Inicio, Explorar,
Decide y su mazo «Una por una», Juegos, Películas y series, TV en vivo, Buscar, el menú, la ficha de una película y de una serie, Elegir versión).
Después de cada una tiene que haber exactamente una pieza enfocada que se vea: dentro de la pantalla, sin nada encima que la
tape. Los tres modelos de foco (docs/sistema-de-diseno.md § 5, «Los modelos de foco») pasan por aquí.

Nada sale de la casa: todo POST a la API contesta 409 (A no abre un juego ni cambia un ajuste; si acaso sale un aviso), y la
misma semilla da siempre la misma caminata. Si falla, el mensaje dice dónde, qué teclas llevaron ahí y qué estaba enfocado."""

from __future__ import annotations

import random

from test_ui_flows import browser, with_videos  # noqa: F401  (browser es un fixture)
from test_ui_smoke import ready, server  # noqa: F401  (server es un fixture)

SEED = 20261111
PRESSES = 300

# Lo enfocado que se ve: `.is-focused` con tamaño, sin un ancestro invisible, dentro de la pantalla y arriba de todo en su
# centro (un menú o una ficha encima lo tapan; el aviso, el pie y el anillo de la órbita no cuentan como tapar).
PROBE = """() => {
  const vw = innerWidth, vh = innerHeight;
  const look = (el) => {
    const r = el.getBoundingClientRect();
    if (r.width < 2 || r.height < 2) return null;
    for (let n = el; n && n !== document.documentElement; n = n.parentElement) {
      const s = getComputedStyle(n);
      if (s.visibility === 'hidden' || s.display === 'none' || +s.opacity < 0.05) return null;
    }
    const on = r.right > 0 && r.bottom > 0 && r.left < vw && r.top < vh;
    const x = Math.min(vw - 1, Math.max(0, r.left + r.width / 2)), y = Math.min(vh - 1, Math.max(0, r.top + r.height / 2));
    const top = document.elementsFromPoint(x, y).find((e) => !e.closest('.toast, .orbit, .hints'));
    const covered = !(top && (el.contains(top) || top.contains(el)));
    const name = String(el.className.baseVal ?? el.className).split(' ')[0] + ' «' + (el.getAttribute('aria-label') || el.textContent.trim()).slice(0, 30) + '»';
    return { name, seen: on && !covered };
  };
  const all = [...document.querySelectorAll('.is-focused')].map(look).filter(Boolean);
  return { where: document.body.dataset.view + (document.body.dataset.overlay === 'true' ? ' + algo encima' : ''),
    seen: all.filter((f) => f.seen).map((f) => f.name), behind: all.filter((f) => !f.seen).map((f) => f.name) };
}"""

# De dónde arranca cada tramo: una dirección y, si hace falta, las teclas que llevan a la pantalla.
STARTS = [("/", []), ("/?seccion=foryou", []), ("/?seccion=foryou", ["x"]), ("/?seccion=foryou", ["x", "ArrowUp", "ArrowRight", "Enter"]), ("/?seccion=games", []), ("/?seccion=media", []),
          ("/?seccion=tv", []), ("/", ["s"]), ("/", ["m"]), ("/?pelicula=tt15239678", []), ("/?serie=tt0386676", []),
          ("/?pelicula=tt15239678", ["y"])]
# Las flechas pesan más (es lo que más se aprieta); A, X, Y, B, LB/RB, LT/RT (PageUp/PageDown), ☰ y buscar también.
KEYS = ["ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight"] * 4 + ["e", "q", "PageDown", "PageUp", "Escape", "Enter", "Enter", "x", "y", "m", "s"]


def nothing_leaves(route):
    if route.request.method == "GET":
        return route.fallback()
    return route.fulfill(status=409, content_type="application/json", body='{"detail": "prueba"}')


def test_focus_is_never_lost(browser, server):  # noqa: F811
    rng = random.Random(SEED)
    page = browser.new_page(viewport={"width": 1920, "height": 1080}, reduced_motion="reduce")
    errors: list[str] = []
    page.on("pageerror", lambda exc: errors.append(str(exc)))
    with_videos(page)
    page.route("**/api/**", nothing_leaves)
    lost: list[str] = []
    per = -(-PRESSES // len(STARTS))
    done = 0
    for url, first in STARTS:
        page.goto(server + url)
        ready(page)
        page.wait_for_timeout(1000)
        trail = list(first)
        for key in first:
            page.keyboard.press(key)
            page.wait_for_timeout(900)
        for _ in range(min(per, PRESSES - done)):
            key = rng.choice(KEYS)
            trail.append(key)
            page.keyboard.press(key)
            page.wait_for_timeout(250)
            seen = page.evaluate(PROBE)
            if len(seen["seen"]) != 1:  # una animación a medias: se le da su tiempo antes de contarlo
                page.wait_for_timeout(900)
                seen = page.evaluate(PROBE)
            if len(seen["seen"]) != 1:
                lost.append(f"{url} → {' '.join(trail[-8:])}: {seen['where']}, se ven {seen['seen'] or 'ninguna'}"
                            f" (detrás o fuera: {seen['behind'][:3]})")
            done += 1
    page.close()
    assert done == PRESSES
    assert not errors, errors
    assert not lost, f"{len(lost)} de {PRESSES} teclas dejaron el foco perdido o doble:\n" + "\n".join(lost[:12])
