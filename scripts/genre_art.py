"""Arte fijo de los géneros de Buscar › Explora (iPhone): una imagen por género, original y sin red.

Proyección («el arte es la luz»): cada género es una luz de sala sobre tinta oscura —su color y su forma lo evocan— en
lugar de un fondo de película pedido a internet (tardaba en cargar y dos géneros podían salir con la misma imagen).

    python3 scripts/genre_art.py        # escribe ios/App/Resources/Assets.xcassets/Genres/*.imageset

Solo usa Pillow. Determinista (semilla fija): volver a correrlo da las mismas imágenes.
"""

from __future__ import annotations

import json
import math
import random
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "ios/App/Resources/Assets.xcassets/Genres"
W, H = 1050, 576  # 3× de una tarjeta de ~350×192 pt (cubre la de 2 columnas en cualquier iPhone, con margen)
INK = (13, 13, 16)  # ink-950, el fondo de la app en oscuro


def canvas() -> Image.Image:
    return Image.new("RGB", (W, H), INK)


def glow(img: Image.Image, center: tuple[float, float], radius: float, color: tuple[int, int, int], strength: float = 1.0) -> Image.Image:
    """Una luz suave (círculo muy desenfocado) sumada a la imagen."""
    layer = Image.new("RGB", (W, H), (0, 0, 0))
    d = ImageDraw.Draw(layer)
    x, y = center
    c = tuple(int(v * strength) for v in color)
    d.ellipse([x - radius, y - radius, x + radius, y + radius], fill=c)
    layer = layer.filter(ImageFilter.GaussianBlur(radius * 0.55))
    return ImageChops.add(img, layer)


def beam(img: Image.Image, origin: tuple[float, float], angle: float, spread: float, length: float, color: tuple[int, int, int], blur: float = 40) -> Image.Image:
    """Un haz de proyector: un triángulo de luz desenfocado que sale de `origin`."""
    layer = Image.new("RGB", (W, H), (0, 0, 0))
    d = ImageDraw.Draw(layer)
    ox, oy = origin
    a1, a2 = angle - spread / 2, angle + spread / 2
    pts = [(ox, oy), (ox + length * math.cos(a1), oy + length * math.sin(a1)), (ox + length * math.cos(a2), oy + length * math.sin(a2))]
    d.polygon(pts, fill=color)
    layer = layer.filter(ImageFilter.GaussianBlur(blur))
    return ImageChops.add(img, layer)


def streaks(img: Image.Image, rng: random.Random, n: int, color: tuple[int, int, int], angle: float, length: tuple[int, int], width: tuple[int, int], blur: float) -> Image.Image:
    layer = Image.new("RGB", (W, H), (0, 0, 0))
    d = ImageDraw.Draw(layer)
    for _ in range(n):
        x, y = rng.uniform(-W * 0.2, W * 1.1), rng.uniform(-H * 0.2, H * 1.1)
        L = rng.uniform(*length)
        k = rng.uniform(0.35, 1.0)
        c = tuple(int(v * k) for v in color)
        d.line([(x, y), (x + L * math.cos(angle), y + L * math.sin(angle))], fill=c, width=int(rng.uniform(*width)))
    layer = layer.filter(ImageFilter.GaussianBlur(blur))
    return ImageChops.add(img, layer)


def bokeh(img: Image.Image, rng: random.Random, n: int, palette: list[tuple[int, int, int]], size: tuple[int, int], blur: float, strength: tuple[float, float] = (0.25, 0.7)) -> Image.Image:
    layer = Image.new("RGB", (W, H), (0, 0, 0))
    d = ImageDraw.Draw(layer)
    for _ in range(n):
        r = rng.uniform(*size)
        x, y = rng.uniform(0, W), rng.uniform(0, H)
        k = rng.uniform(*strength)
        c = tuple(int(v * k) for v in rng.choice(palette))
        d.ellipse([x - r, y - r, x + r, y + r], fill=c)
    layer = layer.filter(ImageFilter.GaussianBlur(blur))
    return ImageChops.add(img, layer)


def stars(img: Image.Image, rng: random.Random, n: int) -> Image.Image:
    d = ImageDraw.Draw(img)
    for _ in range(n):
        x, y = rng.uniform(0, W), rng.uniform(0, H * 0.75)
        v = int(rng.uniform(90, 230))
        r = rng.choice([1, 1, 1, 2])
        d.ellipse([x - r, y - r, x + r, y + r], fill=(v, v, min(255, v + 15)))
    return img


def finish(img: Image.Image, rng: random.Random, vignette: float = 0.55, grain: float = 10) -> Image.Image:
    """Viñeta (la sala a oscuras) y grano de película, para que no se vea como un degradado de computadora."""
    mask = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(mask)
    d.ellipse([-W * 0.25, -H * 0.45, W * 1.25, H * 1.45], fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(H * 0.3))
    dark = Image.new("RGB", (W, H), INK)
    img = Image.composite(img, Image.blend(img, dark, vignette), mask)
    noise = Image.effect_noise((W, H), grain).convert("RGB")
    img = ImageChops.add(img, ImageChops.subtract(noise, Image.new("RGB", (W, H), (128, 128, 128))), scale=1.0)
    img = ImageChops.subtract(img, ImageChops.subtract(Image.new("RGB", (W, H), (128, 128, 128)), noise))
    return img


# --- un arte por género (los nombres de Cinemeta) ---

def action(rng):  # velocidad: haces cálidos en diagonal y chispas
    img = canvas()
    img = glow(img, (W * 0.78, H * 0.35), 260, (255, 96, 24), 0.9)
    img = streaks(img, rng, 70, (255, 140, 50), -0.35, (180, 520), (2, 7), 3)
    img = bokeh(img, rng, 40, [(255, 190, 90), (255, 120, 40)], (2, 6), 1.5, (0.5, 1.0))
    return finish(img, rng)


def comedy(rng):  # luz cálida de tarde y burbujas
    img = canvas()
    img = glow(img, (W * 0.3, H * 0.4), 320, (255, 186, 72), 0.85)
    img = glow(img, (W * 0.85, H * 0.75), 220, (255, 110, 120), 0.6)
    img = bokeh(img, rng, 26, [(255, 214, 120), (255, 150, 140), (255, 240, 200)], (18, 60), 10, (0.25, 0.6))
    return finish(img, rng, vignette=0.4)


def drama(rng):  # un solo seguidor de teatro desde arriba
    img = canvas()
    img = beam(img, (W * 0.5, -40), math.pi / 2, 0.5, H * 1.3, (150, 175, 245), 50)
    img = glow(img, (W * 0.5, H * 0.7), 230, (160, 185, 255), 0.6)
    return finish(img, rng, vignette=0.6)


def scifi(rng):  # el borde de un planeta con su luz y estrellas
    img = canvas()
    img = stars(img, rng, 160)
    layer = Image.new("RGB", (W, H), (0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.ellipse([-W * 0.4, H * 0.42, W * 1.4, H * 2.4], outline=(90, 220, 255), width=18)
    layer = layer.filter(ImageFilter.GaussianBlur(14))
    img = ImageChops.add(img, layer)
    img = glow(img, (W * 0.5, H * 0.6), 330, (110, 70, 255), 0.6)
    img = glow(img, (W * 0.5, H * 0.46), 160, (120, 230, 255), 0.55)
    return finish(img, rng, vignette=0.45)


def horror(rng):  # rojo apagado, niebla y una luz que casi no alcanza
    img = canvas()
    img = glow(img, (W * 0.5, H * 1.05), 360, (150, 10, 18), 0.95)
    img = bokeh(img, rng, 18, [(120, 20, 30), (70, 10, 20)], (80, 180), 60, (0.3, 0.6))
    img = glow(img, (W * 0.72, H * 0.28), 60, (255, 230, 210), 0.35)
    return finish(img, rng, vignette=0.75, grain=14)


def thriller(rng):  # luz de persiana que cae en diagonal sobre una pared oscura, verde azulado
    img = canvas()
    img = glow(img, (W * 0.7, H * 0.45), 300, (20, 120, 115), 0.55)
    layer = Image.new("RGB", (W, H), (0, 0, 0))
    d = ImageDraw.Draw(layer)
    for i in range(7):
        x = W * 0.38 + i * W * 0.085
        d.polygon([(x, -H * 0.1), (x + W * 0.035, -H * 0.1), (x + W * 0.035 + H * 0.55, H * 1.1), (x + H * 0.55, H * 1.1)], fill=(150, 240, 225))
    layer = layer.filter(ImageFilter.GaussianBlur(7))
    fade = Image.new("L", (W, H), 0)
    ImageDraw.Draw(fade).ellipse([W * 0.35, -H * 0.2, W * 1.25, H * 1.1], fill=170)
    fade = fade.filter(ImageFilter.GaussianBlur(H * 0.22))
    img = Image.composite(ImageChops.add(img, layer), img, fade)
    return finish(img, rng, vignette=0.6)


def animation(rng):  # formas redondas de colores de caramelo
    img = canvas()
    for (x, y, r, c) in [(0.2, 0.35, 230, (255, 120, 180)), (0.55, 0.7, 260, (110, 160, 255)), (0.85, 0.3, 200, (255, 210, 90)), (0.4, 0.1, 150, (120, 230, 170))]:
        img = glow(img, (W * x, H * y), r, c, 0.75)
    img = bokeh(img, rng, 22, [(255, 255, 255)], (6, 16), 3, (0.25, 0.55))
    return finish(img, rng, vignette=0.35)


def romance(rng):  # rosa, luces de ciudad desenfocadas
    img = canvas()
    img = glow(img, (W * 0.6, H * 0.5), 340, (255, 90, 140), 0.65)
    img = bokeh(img, rng, 45, [(255, 170, 190), (255, 210, 170), (255, 120, 160)], (20, 55), 7, (0.3, 0.75))
    return finish(img, rng, vignette=0.45)


def crime(rng):  # noir: el cono de una farola ámbar y lluvia
    img = canvas()
    img = beam(img, (W * 0.3, H * 0.05), math.pi / 2 - 0.15, 0.55, H * 1.2, (230, 150, 40), 45)
    img = glow(img, (W * 0.3, H * 0.06), 40, (255, 220, 150), 0.9)
    img = streaks(img, rng, 120, (190, 170, 140), math.pi / 2 + 0.25, (30, 80), (1, 2), 0.6)
    return finish(img, rng, vignette=0.6)


def documentary(rng):  # un horizonte al amanecer
    img = canvas()
    img = glow(img, (W * 0.5, H * 0.72), 360, (230, 140, 60), 0.75)
    img = glow(img, (W * 0.5, H * 0.7), 80, (255, 230, 180), 0.9)
    layer = Image.new("RGB", (W, H), (0, 0, 0))
    d = ImageDraw.Draw(layer)
    pts = [(0, H * 0.78)] + [(x, H * 0.74 + math.sin(x / 90) * 14 + math.sin(x / 37) * 6) for x in range(0, W + 30, 30)] + [(W, H), (0, H)]
    d.polygon(pts, fill=(1, 1, 1))
    img = Image.composite(Image.new("RGB", (W, H), INK), img, layer.convert("L").point(lambda v: 255 if v else 0))
    return finish(img, rng, vignette=0.5)


GENRES = {
    "Action": action, "Comedy": comedy, "Drama": drama, "Sci-Fi": scifi, "Horror": horror,
    "Thriller": thriller, "Animation": animation, "Romance": romance, "Crime": crime, "Documentary": documentary,
}


def asset_name(genre: str) -> str:
    """«Sci-Fi» → «genre-scifi» (el nombre que usa `ArtTile` en el catálogo)."""
    return "genre-" + "".join(ch for ch in genre.lower() if ch.isalnum())


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}, "properties": {"provides-namespace": False}}, indent=2) + "\n")
    for i, (genre, draw) in enumerate(GENRES.items()):
        name = asset_name(genre)
        folder = OUT / f"{name}.imageset"
        folder.mkdir(exist_ok=True)
        img = draw(random.Random(7 + i))
        img.save(folder / f"{name}.jpg", quality=82, optimize=True, progressive=True)
        contents = {"images": [{"filename": f"{name}.jpg", "idiom": "universal"}], "info": {"author": "xcode", "version": 1}}
        (folder / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")
        print(f"{name}: {(folder / f'{name}.jpg').stat().st_size // 1024} KB")


if __name__ == "__main__":
    main()
