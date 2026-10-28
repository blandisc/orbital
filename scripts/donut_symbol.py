#!/usr/bin/env python3
"""Arma el símbolo de la dona de Los Simpson («Un Simpson al azar» en el Centro de control) como plantilla de SF Symbols.

Como la marca de Orbital (scripts/orbital_symbol.py, de donde toma la hoja y las medidas): las 27 variantes (9 grosores ×
S, M y L) con los mismos puntos en todas, o el Centro de control la pinta en blanco. La dona: la orilla de afuera, el hoyo,
el glaseado ondulado y seis chispas encima.

Uso: python3 scripts/donut_symbol.py  (escribe el .svg en los dos catálogos: la extensión y la app)
"""
from __future__ import annotations

import math
from pathlib import Path

import orbital_symbol as base

ROOT = Path(__file__).resolve().parent.parent
TARGETS = [ROOT / "ios/App/Widgets/Symbols.xcassets/simpsons.donut.symbolset/simpsons.donut.svg",
           ROOT / "ios/App/Resources/Assets.xcassets/simpsons.donut.symbolset/simpsons.donut.svg"]

# En la caja de 32: la orilla, el hoyo, el glaseado (radio medio, cuánto ondula y cuántas ondas) y las chispas (radio, ángulo
# en grados y giro de cada una, y su largo).
CENTER = (16.0, 16.0)
OUTER, HOLE = 14.0, 4.4
ICING, WAVE, WAVES = 10.4, 1.0, 8
SPRINKLES = [(7.5, 35, 60), (7.6, 125, -30), (7.5, 215, 50), (7.6, 305, -40)]   # cuatro: con seis, en chico se empastaba
SPRINKLE_LENGTH = 2.6
POINTS = 96
# Grosores (orilla, hoyo, glaseado, chispa) del más delgado al más grueso.
THIN, REGULAR, BLACK = (0.9, 0.8, 0.8, 1.1), (2.3, 2.0, 1.8, 2.0), (3.2, 2.8, 2.6, 2.6)


def weight(i: int) -> tuple[float, ...]:
    a, b, t = (THIN, REGULAR, i / 3) if i <= 3 else (REGULAR, BLACK, (i - 3) / 5)
    return tuple(x + (y - x) * t for x, y in zip(a, b, strict=True))


WEIGHTS = {f"{name}-{scale}": weight(i) for i, name in enumerate(base.WEIGHT_NAMES) for scale in "SML"}


def ring(radius, width: float) -> list[list[tuple[float, float]]]:
    """Una línea cerrada alrededor del centro (radio fijo o una función del ángulo) como contorno: afuera y el hueco."""
    r = radius if callable(radius) else (lambda _a: radius)
    angles = [2 * math.pi * i / POINTS for i in range(POINTS)]
    outer = [(CENTER[0] + (r(a) + width / 2) * math.cos(a), CENTER[1] + (r(a) + width / 2) * math.sin(a)) for a in angles]
    inner = [(CENTER[0] + (r(a) - width / 2) * math.cos(a), CENTER[1] + (r(a) - width / 2) * math.sin(a)) for a in angles]
    return [base.oriented(outer, True), base.oriented(inner, False)]


def sprinkle(radius: float, angle: float, turn: float, width: float) -> list[tuple[float, float]]:
    """Una chispa: un trazo corto con puntas redondas."""
    a = math.radians(angle)
    cx, cy = CENTER[0] + radius * math.cos(a), CENTER[1] + radius * math.sin(a)
    t = math.radians(angle + 90 + turn)
    dx, dy = math.cos(t) * SPRINKLE_LENGTH / 2, math.sin(t) * SPRINKLE_LENGTH / 2
    half, nx, ny = width / 2, -math.sin(t), math.cos(t)
    points = []
    for (px, py), start in (((cx + dx, cy + dy), math.atan2(ny, nx)), ((cx - dx, cy - dy), math.atan2(-ny, -nx))):
        points += [(px + half * math.cos(start - math.pi * k / base.CAP), py + half * math.sin(start - math.pi * k / base.CAP))
                   for k in range(base.CAP + 1)]
    return base.oriented(points, True)


def glyph(name: str) -> tuple[str, float, float]:
    outer_w, hole_w, icing_w, sprinkle_w = WEIGHTS[name]
    column, row = base.COLUMN[name], name.split("-")[1]
    shapes = ring(OUTER, outer_w) + ring(HOLE, hole_w) + ring(lambda a: ICING + WAVE * math.sin(WAVES * a), icing_w)
    shapes += [sprinkle(r, a, t, sprinkle_w) for r, a, t in SPRINKLES]
    d = " ".join(base.path(p, column, row) for p in shapes)
    xs = [base.to_sheet(x, y, column, row)[0] for x, y in shapes[0]]
    return d, min(xs), max(xs)


if __name__ == "__main__":
    base.glyph = glyph   # la misma hoja (guías, renglones y columnas) con la dona en lugar de la marca
    base.UNITS = 124.0   # redonda: un poco más chica que la marca (ancha) para que las dos se vean del mismo tamaño
    base.WEIGHTS = WEIGHTS
    text = base.template().replace("La marca de Orbital (planeta, anillo y luna). Generado por scripts/orbital_symbol.py",
                                   "La dona de Los Simpson. Generado por scripts/donut_symbol.py")
    for target in TARGETS:
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text)
        (target.parent / "Contents.json").write_text((ROOT / "ios/App/Widgets/Symbols.xcassets/orbital.mark.symbolset/Contents.json")
                                                     .read_text().replace("orbital.mark.svg", "simpsons.donut.svg"))
        print("Escrito", target.relative_to(ROOT))
