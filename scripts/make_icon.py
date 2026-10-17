"""Genera los íconos de Orbital (orbital/web/icons: PNG de 16 a 512 y orbital.ico) con la marca C: el planeta de contorno,
el anillo por delante y la luna como punto. Uso: python scripts/make_icon.py (escribe en ./out; cópialos a orbital/web/icons)."""
import pathlib

from PIL import Image
from playwright.sync_api import sync_playwright

SVG = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" width="{s}" height="{s}">
<defs><radialGradient id="g" cx="40%" cy="30%" r="80%"><stop offset="0" stop-color="#1e1e23"/><stop offset="1" stop-color="#0c0c0e"/></radialGradient></defs>
<rect x="8" y="8" width="240" height="240" rx="54" fill="url(#g)"/>
<g transform="translate(124 130) scale(5.2) translate(-16 -16)" fill="none" stroke="#f5f4f0" stroke-linecap="round">
<circle cx="16" cy="16" r="7.2" stroke-width="2.8"/>
<path d="M3.2 20.4c3.8 3.1 21.2-2.4 26-8.8" stroke="#141417" stroke-width="5"/>
<path d="M3.2 20.4c3.8 3.1 21.2-2.4 26-8.8" stroke-width="2.1"/>
</g>
<circle cx="196" cy="62" r="11" fill="#f5f4f0"/>
</svg>"""
out = pathlib.Path("out"); out.mkdir(exist_ok=True)
with sync_playwright() as p:
    b = p.chromium.launch(channel="msedge", headless=True)
    pg = b.new_page()
    for s in (16, 24, 32, 48, 64, 128, 256, 512):
        pg.set_viewport_size({"width": s, "height": s})
        pg.set_content(f"<html><body style='margin:0;background:transparent'>{SVG.format(s=s)}</body></html>")
        png = pg.screenshot(omit_background=True, clip={"x": 0, "y": 0, "width": s, "height": s})
        (out / f"orbital-{s}.png").write_bytes(png)
    b.close()
imgs = [Image.open(out / f"orbital-{s}.png").convert("RGBA") for s in (256, 128, 64, 48, 32, 24, 16)]
imgs[0].save(out / "orbital.ico", sizes=[(s, s) for s in (256, 128, 64, 48, 32, 24, 16)], append_images=imgs[1:])
print("ok")
