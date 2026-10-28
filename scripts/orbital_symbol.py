#!/usr/bin/env python3
"""Arma el símbolo propio de Orbital (planeta, anillo y luna) como plantilla de SF Symbols completa.

El Centro de control solo pinta símbolos que traen todos los grosores y tamaños: la plantilla trae las 27 variantes (9
grosores × S, M y L, con los mismos puntos en todas). La de antes traía solo Regular-M y el control salía en blanco.

Uso: python3 scripts/orbital_symbol.py  (escribe el .svg en los dos catálogos: la extensión y la app)
"""
from __future__ import annotations

import math
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TARGETS = [ROOT / "ios/App/Widgets/Symbols.xcassets/orbital.mark.symbolset/orbital.mark.svg",
           ROOT / "ios/App/Resources/Assets.xcassets/orbital.mark.symbolset/orbital.mark.svg"]

# La marca en su caja de 32 (la misma de la TV y de OrbitalMark): planeta, anillo «M3.2 20.4 c3.8 3.1 21.2-2.4 26-8.8» y
# la luna arriba a la derecha, como en el ícono de la app.
PLANET = (16.0, 16.0, 7.2)
RING = ((3.2, 20.4), (7.0, 23.5), (24.4, 18.0), (29.2, 11.6))
MOON = (27.6, 6.0)
# Grosores (planeta, anillo, radio de la luna) del más delgado al más grueso, en unidades de la caja.
WEIGHT_NAMES = ["Ultralight", "Thin", "Light", "Regular", "Medium", "Semibold", "Bold", "Heavy", "Black"]
THIN, REGULAR, BLACK = (0.9, 0.8, 1.6), (2.4, 2.0, 2.5), (3.6, 3.0, 3.0)   # junto a los símbolos de Apple, la de 1.9 se veía débil


def weight(i: int) -> tuple[float, float, float]:
    """Del delgado al normal (0…3) y del normal al grueso (3…8), en línea recta."""
    a, b, t = (THIN, REGULAR, i / 3) if i <= 3 else (REGULAR, BLACK, (i - 3) / 5)
    return tuple(x + (y - x) * t for x, y in zip(a, b, strict=True))


WEIGHTS = {f"{name}-{scale}": weight(i) for i, name in enumerate(WEIGHT_NAMES) for scale in "SML"}
# Dónde va cada variante: la columna por grosor y el renglón por tamaño (con su línea base); S más chico, L más grande.
COLUMN = {f"{name}-{scale}": 413.0 + 300.0 * i for i, name in enumerate(WEIGHT_NAMES) for scale in "SML"}
ROW = {"S": (696.0, 625.541, 0.84), "M": (1126.0, 1055.54, 1.0), "L": (1556.0, 1485.54, 1.21)}
UNITS = 156.0   # antes 92 y 122: la marca es ancha y baja; en el botón redondo del Centro de control se veía chica
SAMPLES = 48
CAP = 10


def to_sheet(x: float, y: float, column: float, row: str = "M") -> tuple[float, float]:
    base, cap, factor = ROW[row]
    s = UNITS * factor / 32
    return column + (x - 16) * s, (base + cap) / 2 + (y - 16) * s


def circle(cx: float, cy: float, r: float, clockwise: bool) -> list[tuple[float, float]]:
    n = 64
    pts = [(cx + r * math.cos(2 * math.pi * i / n), cy + r * math.sin(2 * math.pi * i / n)) for i in range(n)]
    return pts if clockwise else pts[::-1]


def bezier(t: float) -> tuple[float, float]:
    (x0, y0), (x1, y1), (x2, y2), (x3, y3) = RING
    u = 1 - t
    return (u**3 * x0 + 3 * u * u * t * x1 + 3 * u * t * t * x2 + t**3 * x3,
            u**3 * y0 + 3 * u * u * t * y1 + 3 * u * t * t * y2 + t**3 * y3)


def stroked_ring(width: float) -> list[tuple[float, float]]:
    """El anillo como contorno cerrado (trazo con puntas redondas), siempre con los mismos puntos."""
    half = width / 2
    centers = [bezier(i / (SAMPLES - 1)) for i in range(SAMPLES)]
    normals = []
    for i in range(SAMPLES):
        a, b = centers[max(i - 1, 0)], centers[min(i + 1, SAMPLES - 1)]
        dx, dy = b[0] - a[0], b[1] - a[1]
        length = math.hypot(dx, dy) or 1
        normals.append((-dy / length, dx / length))
    left = [(c[0] + n[0] * half, c[1] + n[1] * half) for c, n in zip(centers, normals, strict=True)]
    right = [(c[0] - n[0] * half, c[1] - n[1] * half) for c, n in zip(centers, normals, strict=True)]

    def cap(center, normal, flip):
        base = math.atan2(normal[1], normal[0])
        return [(center[0] + half * math.cos(base + flip * math.pi * k / CAP), center[1] + half * math.sin(base + flip * math.pi * k / CAP))
                for k in range(1, CAP)]
    end_cap = cap(centers[-1], normals[-1], -1)
    start_cap = cap(centers[0], (-normals[0][0], -normals[0][1]), -1)
    return left + end_cap + right[::-1] + start_cap


def area(points: list[tuple[float, float]]) -> float:
    return sum(points[i][0] * points[(i + 1) % len(points)][1] - points[(i + 1) % len(points)][0] * points[i][1] for i in range(len(points))) / 2


def oriented(points: list[tuple[float, float]], positive: bool) -> list[tuple[float, float]]:
    return points if (area(points) > 0) == positive else points[::-1]


def path(points: list[tuple[float, float]], column: float, row: str) -> str:
    sheet = [to_sheet(x, y, column, row) for x, y in points]
    return "M " + " L ".join(f"{x:.2f},{y:.2f}" for x, y in sheet) + " Z"


def glyph(name: str) -> tuple[str, float, float]:
    planet_w, ring_w, moon_r = WEIGHTS[name]
    column, row = COLUMN[name], name.split("-")[1]
    cx, cy, r = PLANET
    outer = oriented(circle(cx, cy, r + planet_w / 2, True), True)
    inner = oriented(circle(cx, cy, r - planet_w / 2, True), False)   # al revés: el hueco del planeta
    ring = oriented(stroked_ring(ring_w), True)
    moon = oriented(circle(MOON[0], MOON[1], moon_r, True), True)
    d = " ".join(path(p, column, row) for p in (outer, inner, ring, moon))
    xs = [to_sheet(x, y, column, row)[0] for x, y in outer + ring + moon]
    return d, min(xs), max(xs)


def template() -> str:
    guides, symbols = [], []
    for name in WEIGHTS:
        d, left, right = glyph(name)
        base = ROW[name.split("-")[1]][0]
        y1, y2 = base - 120, base + 40
        guides.append(f'  <line id="left-margin-{name}" style="fill:none;stroke:#00AEEF;stroke-width:0.5;opacity:1.0;" x1="{left:.2f}" x2="{left:.2f}" y1="{y1}" y2="{y2}"/>')
        guides.append(f'  <line id="right-margin-{name}" style="fill:none;stroke:#00AEEF;stroke-width:0.5;opacity:1.0;" x1="{right:.2f}" x2="{right:.2f}" y1="{y1}" y2="{y2}"/>')
        symbols.append(f'  <g id="{name}">\n   <path d="{d}"/>\n  </g>')
    lines = "\n".join([
        '  <line id="Baseline-S" style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.5;" x1="263" x2="3036" y1="696" y2="696"/>',
        '  <line id="Capline-S" style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.5;" x1="263" x2="3036" y1="625.541" y2="625.541"/>',
        '  <line id="Baseline-M" style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.5;" x1="263" x2="3036" y1="1126" y2="1126"/>',
        '  <line id="Capline-M" style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.5;" x1="263" x2="3036" y1="1055.54" y2="1055.54"/>',
        '  <line id="Baseline-L" style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.5;" x1="263" x2="3036" y1="1556" y2="1556"/>',
        '  <line id="Capline-L" style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.5;" x1="263" x2="3036" y1="1485.54" y2="1485.54"/>',
        *guides])
    return f'''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">
<!-- La marca de Orbital (planeta, anillo y luna). Generado por scripts/orbital_symbol.py: no se edita a mano. -->
<svg version="1.1" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="3300" height="2200">
 <g id="Notes">
  <rect height="2200" id="artboard" style="fill:white;opacity:1" width="3300" x="0" y="0"/>
  <text style="stroke:none;fill:black;font-family:sans-serif;font-size:13;" transform="matrix(1 0 0 1 263 322)">Weight/Scale Variations</text>
 </g>
 <g id="Guides">
{lines}
 </g>
 <g id="Symbols">
{chr(10).join(symbols)}
 </g>
</svg>
'''


if __name__ == "__main__":
    text = template()
    for target in TARGETS:
        target.write_text(text)
        print("Escrito", target.relative_to(ROOT))
