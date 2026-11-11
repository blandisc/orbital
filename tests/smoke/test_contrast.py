"""Lo que se lee sobre el arte pasa AA con la medida estricta (R3-6, 11 nov 2026): el color del texto contra lo más claro de
lo que tiene debajo (el 5 % de píxeles más brillante, con el texto escondido), no contra el promedio. Antes de esta tanda daban
«Con control» 2,8, «PSP» 3,1, «Juegos» 4,1, LB/RB 4,7 y la cuenta «47» de TV en vivo 3,9; la sombra no cuenta aquí.
Juegos lleva el arte claro de Hades (la demostración), el peor caso a 1280 × 800."""

from __future__ import annotations

import io
import re

import pytest
from PIL import Image
from test_ui_flows import browser, with_videos  # noqa: F401  (browser es un fixture)
from test_ui_smoke import ready, server  # noqa: F401  (server es un fixture)

AA = 4.5

MARK = """([sel, i]) => { document.querySelectorAll('[data-measure]').forEach((e) => e.removeAttribute('data-measure'));
  const shown = [...document.querySelectorAll(sel)].filter((e) => { const r = e.getBoundingClientRect();
    return r.width > 2 && r.height > 2 && r.left >= 0 && r.right <= innerWidth && r.top >= 0 && r.bottom <= innerHeight && getComputedStyle(e).visibility !== 'hidden'; });
  const e = shown[i]; if (!e) return null; e.dataset.measure = '';
  const r = e.getBoundingClientRect();
  return { rect: [r.left, r.top, r.width, r.height], color: getComputedStyle(e).color, text: e.textContent.trim().slice(0, 24), count: shown.length }; }"""
HIDE = ("[data-measure], [data-measure] * { color: transparent !important; text-shadow: none !important; }"
        " [data-measure] :is(svg, img) { visibility: hidden !important; }")


def luminance(rgb):
    def channel(v):
        v /= 255
        return v / 12.92 if v <= .04045 else ((v + .055) / 1.055) ** 2.4
    return .2126 * channel(rgb[0]) + .7152 * channel(rgb[1]) + .0722 * channel(rgb[2])


def strict(page, sel, i):
    """Contraste del i-ésimo `sel` visible contra el 5 % más claro de su fondo (None si no hay tantos)."""
    info = page.evaluate(MARK, [sel, i])
    if not info:
        return None
    x, y, w, h = info["rect"]
    tag = page.add_style_tag(content=HIDE)
    page.wait_for_timeout(120)
    shot = Image.open(io.BytesIO(page.screenshot(clip={"x": x, "y": y, "width": w, "height": h}))).convert("RGB")
    page.evaluate("(t) => t.remove()", tag)
    pixels = sorted(shot.getdata(), key=luminance)
    bright = pixels[int(len(pixels) * .95)]
    nums = [float(v) for v in re.findall(r"[\d.]+", info["color"])]
    alpha = nums[3] if len(nums) > 3 else 1
    text = [nums[c] * alpha + bright[c] * (1 - alpha) for c in range(3)]
    hi, lo = sorted((luminance(text), luminance(bright)), reverse=True)
    return info["text"], (hi + .05) / (lo + .05), info["count"]


def all_of(page, sel, limit=8):
    out, i = [], 0
    while i < limit:
        got = strict(page, sel, i)
        if not got:
            break
        out.append(got[:2])
        i += 1
    return out


@pytest.mark.parametrize("width,height", [(1920, 1080), (1280, 800)])
def test_text_on_art_passes_strict_contrast(browser, server, width, height):  # noqa: F811
    page = browser.new_page(viewport={"width": width, "height": height}, reduced_motion="reduce")
    with_videos(page)
    page.goto(f"{server}/?seccion=games")
    ready(page)
    page.locator(".browse__filters .pill--tab").first.wait_for()
    page.wait_for_timeout(2000)  # el arte del destacado ya llegó
    measured = []
    measured += all_of(page, ".browse__filters .pill--tab")  # Recientes … Con control
    measured += all_of(page, ".glass-switch__item")  # Steam, Switch … PSP
    measured += all_of(page, ".status-bar__tab--active .status-bar__tab-label")  # «Juegos»
    measured += all_of(page, ".status-bar__tabs .glyph")  # LB, RB
    page.goto(f"{server}/?seccion=tv")
    ready(page)
    page.locator(".tv__cat--on .tv__cat-count").first.wait_for()
    page.wait_for_timeout(1500)
    measured += all_of(page, ".tv__cat-count")  # «47» en la elegida y los demás
    page.close()
    names = {name for name, _ in measured}
    assert {"Con control", "PSP", "Juegos", "LB", "RB"} <= names, names
    low = [(name, round(ratio, 1)) for name, ratio in measured if ratio < AA]
    assert not low, f"por debajo de {AA} contra lo más claro del fondo: {low}"
