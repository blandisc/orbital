"""Los íconos de Orbital desde un solo dibujo (la marca «pulida» del 1 nov 2026): el planeta de contorno, el anillo como
pincelada que engorda al pasar por delante y termina en punta (la mitad de enfrente de una elipse), el hueco limpio donde
cruza y la luna turquesa (teal-300, --color-brand-moon) sobre una órbita concéntrica al anillo. Cada edición se cuenta en
lunas sobre esa órbita: Orbital una, Plus dos, Ultra tres.

Escribe:
  - orbital/web/icons: PNG de 16 a 512 y orbital.ico (la app de la TV: una luna, la marca sola).
  - ios/App/Resources/Assets.xcassets: AppIcon (clásico, oscuro y teñido), AppIconNight (Cielo nocturno) y sus vistas
    previas de Ajustes, en la edición de `IPHONE` (la app de iPhone de hoy es la de Fernando: Ultra).
  - design/marca: los SVG de las tres ediciones, clásico y noche, y su PNG de 1024 (para cuando Plus y Orbital tengan
    su propia app).

Uso: python scripts/make_icon.py. Necesita Pillow y un Chromium que pinte los SVG: Edge en Windows, el de Playwright en la
Mac, o el que diga ORBITAL_CHROME."""
import glob
import math
import os
import pathlib
import shutil
import subprocess
import tempfile

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
WEB = ROOT / "orbital" / "web" / "icons"
ASSETS = ROOT / "ios" / "App" / "Resources" / "Assets.xcassets"
MARCA = ROOT / "design" / "marca"
IPHONE = "ultra"   # la edición de la app de iPhone de hoy (mx.iracheta.orbital); Plus y Orbital, cuando tengan su destino
LUNAS = {"orbital": 1, "plus": 2, "ultra": 3}

# La geometría, en el cuadro de 1024 (el mismo centro, tamaño e inclinación de la marca de antes).
CX, CY = 495, 520          # el centro del planeta y del anillo
PLANET_R, PLANET_W = 160, 62
TILT = -18.8               # la inclinación del anillo (grados)
RING_R, RING_OUT, RING_IN = 322, 110, 52   # semieje del anillo y las dos elipses que lo hacen grueso al frente y en punta
GAP = 20                   # el hueco entre el anillo y el planeta
ORBIT = (570, 223)         # la órbita de las lunas (concéntrica, misma inclinación)
MOONS = [(-49, 44), (-29, 24), (-66, 17)]   # (dónde en la órbita, radio): la principal y las de Plus y Ultra

PAPER, MOON = "#f5f4f0", "#5fd6c6"
NIGHT_INK = "#efe6d4"


def ring_path(r=RING_R, outer=RING_OUT, inner=RING_IN):
    # Dos curvas que se juntan en punta en las orillas (con arcos de elipse, la punta quedaba roma) y se separan al frente:
    # `outer` e `inner` son lo que baja cada una a la mitad.
    c = 0.55 * r
    return (f"M{-r},0 C{-c},{outer / 0.75:.1f} {c},{outer / 0.75:.1f} {r},0 "
            f"C{c},{inner / 0.75:.1f} {-c},{inner / 0.75:.1f} {-r},0Z")


def on_orbit(deg):
    t, a = math.radians(deg), math.radians(TILT)
    x, y = ORBIT[0] * math.cos(t), ORBIT[1] * math.sin(t)
    return CX + x * math.cos(a) - y * math.sin(a), CY + x * math.sin(a) + y * math.cos(a)


def mark(ink, moons, moon_fill, *, scale=1.0, planet_w=PLANET_W, ring=(RING_OUT, RING_IN), moon_scale=1.0, glow=None, tag=""):
    """El planeta, el anillo y las lunas. `scale` agranda todo desde el centro del cuadro (los tamaños chicos)."""
    g = f'transform="translate({CX} {CY}) rotate({TILT})"'
    d = ring_path(outer=ring[0], inner=ring[1])
    out = [f'<mask id="gap{tag}" maskUnits="userSpaceOnUse" x="-512" y="-512" width="2048" height="2048">'
           f'<rect x="-512" y="-512" width="2048" height="2048" fill="#fff"/>'
           f'<path {g} d="{d}" stroke="#000" stroke-width="{2 * GAP}" stroke-linejoin="round"/></mask>',
           f'<g transform="translate(512 512) scale({scale}) translate(-512 -512)">',
           f'<circle cx="{CX}" cy="{CY}" r="{PLANET_R}" fill="none" stroke="{ink}" stroke-width="{planet_w}" mask="url(#gap{tag})"/>',
           f'<path {g} d="{d}" fill="{ink}"/>']
    for i, (deg, r) in enumerate(MOONS[:moons]):
        x, y = on_orbit(deg)
        r *= moon_scale
        if glow:
            # El brillo, menor en las lunas chicas para que no se junten.
            out.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{r * (2.6 if i == 0 else 1.9):.1f}" fill="url(#glow{tag})"/>')
        out.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{r:.1f}" fill="{moon_fill}"{"" if i == 0 else " fill-opacity=\".85\""}/>')
    out.append("</g>")
    return "".join(out)


def svg(body, defs=""):
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024"><defs>{defs}</defs>{body}</svg>'


GRAPHITE = '<radialGradient id="bg" cx="40%" cy="30%" r="80%"><stop offset="0" stop-color="#1e1e23"/><stop offset="1" stop-color="#0c0c0e"/></radialGradient>'


def classic(moons):
    return svg('<rect width="1024" height="1024" fill="url(#bg)"/>' + mark(PAPER, moons, MOON), GRAPHITE)


def dark(moons):
    # Sin fondo: iOS pone el suyo.
    return svg(mark(PAPER, moons, MOON))


def tinted(moons):
    # Grises sobre negro: iOS la tiñe.
    return svg('<rect width="1024" height="1024" fill="#000"/>' + mark("#fff", moons, "#fff"))


def night(moons):
    # Cielo nocturno: azul de medianoche que baja a negro, unas estrellas quietas y lunas color crema que brillan.
    defs = ('<linearGradient id="sky" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#0d1a33"/>'
            '<stop offset=".6" stop-color="#0e1424"/><stop offset="1" stop-color="#101012"/></linearGradient>'
            '<radialGradient id="glow"><stop offset=".38" stop-color="#fff6e0" stop-opacity=".5"/>'
            '<stop offset="1" stop-color="#fff6e0" stop-opacity="0"/></radialGradient>')
    stars = "".join(f'<circle cx="{x}" cy="{y}" r="{r}" fill="#fff" fill-opacity="{o}"/>' for x, y, r, o in [
        (128, 254, 3, .35), (414, 196, 2.5, .3), (578, 112, 2.5, .3), (972, 352, 2.5, .25), (884, 522, 3, .3),
        (168, 432, 2, .25), (700, 690, 3, .2), (474, 822, 2.5, .2), (84, 838, 2.5, .2), (922, 904, 2.5, .2), (300, 66, 2, .25)])
    return svg('<rect width="1024" height="1024" fill="url(#sky)"/>' + stars + mark(NIGHT_INK, moons, "#fff3dc", glow=True), defs)


def windows(small):
    """La de la TV (una luna) en su cuadro redondeado con las esquinas transparentes. Chica (16-48 px): la marca más grande
    y más gruesa, para que no se vea delgada ni borrosa en la barra de tareas."""
    frame = '<rect x="32" y="32" width="960" height="960" rx="216" fill="url(#bg)"/>' if not small else \
            '<rect x="16" y="16" width="992" height="992" rx="224" fill="url(#bg)"/>'
    art = mark(PAPER, 1, MOON, scale=0.94) if not small else \
        mark(PAPER, 1, MOON, scale=1.12, planet_w=84, ring=(126, 40), moon_scale=1.45)
    return svg(frame + art, GRAPHITE)


def chrome():
    if os.environ.get("ORBITAL_CHROME"):
        return os.environ["ORBITAL_CHROME"]
    for pattern in ["~/Library/Caches/ms-playwright/chromium_headless_shell-*/chrome-headless-shell-*/chrome-headless-shell",
                    "~/AppData/Local/ms-playwright/chromium_headless_shell-*/chrome-headless-shell-*/chrome-headless-shell.exe",
                    r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe", r"C:\Program Files\Microsoft\Edge\Application\msedge.exe"]:
        found = sorted(glob.glob(os.path.expanduser(pattern)))
        if found:
            return found[-1]
    raise SystemExit("No encontré un Chromium: define ORBITAL_CHROME")


def render(art, path, size=1024):
    """Pinta el SVG a `size` px con fondo transparente."""
    with tempfile.TemporaryDirectory() as tmp:
        page = pathlib.Path(tmp) / "icon.html"
        page.write_text(f"<html><body style='margin:0;background:transparent'>{art.replace('width=\"1024\" height=\"1024\"', f'width=\"{size}\" height=\"{size}\"')}</body></html>")
        shot = pathlib.Path(tmp) / "icon.png"
        subprocess.run([chrome(), "--headless", "--hide-scrollbars", "--default-background-color=00000000",
                        f"--window-size={size},{size}", f"--screenshot={shot}", page.as_uri()], check=True, capture_output=True)
        Image.open(shot).convert("RGBA").crop((0, 0, size, size)).save(path)


def opaque(path):
    # El App Store no acepta transparencia en el ícono principal.
    Image.open(path).convert("RGB").save(path)


MARCA.mkdir(parents=True, exist_ok=True)
for edition, moons in LUNAS.items():
    for look, make in (("clasico", classic), ("noche", night)):
        art = make(moons)
        (MARCA / f"{edition}-{look}.svg").write_text(art)
        render(art, MARCA / f"{edition}-{look}.png")
        opaque(MARCA / f"{edition}-{look}.png")

moons = LUNAS[IPHONE]
icon = ASSETS / "AppIcon.appiconset"
shutil.copy(MARCA / f"{IPHONE}-clasico.png", icon / "AppIcon.png")
render(dark(moons), icon / "AppIcon-Dark.png")
render(tinted(moons), icon / "AppIcon-Tinted.png")
opaque(icon / "AppIcon-Tinted.png")
shutil.copy(MARCA / f"{IPHONE}-noche.png", ASSETS / "AppIconNight.appiconset" / "AppIconNight.png")
for look, name in (("clasico", "day"), ("noche", "night")):
    Image.open(MARCA / f"{IPHONE}-{look}.png").resize((240, 240), Image.LANCZOS).save(ASSETS / "AppIconPreview" / f"{name}.imageset" / f"{name}.png")

sizes = (16, 24, 32, 48, 64, 128, 256, 512)
for s in sizes:
    render(windows(small=s <= 48), WEB / f"orbital-{s}.png", s)
imgs = [Image.open(WEB / f"orbital-{s}.png").convert("RGBA") for s in sorted(sizes[:-1], reverse=True)]
imgs[0].save(WEB / "orbital.ico", sizes=[i.size for i in imgs], append_images=imgs[1:])
print("Íconos listos")
