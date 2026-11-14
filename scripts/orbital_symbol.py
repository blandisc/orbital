#!/usr/bin/env python3
"""Arma el símbolo propio de Orbital (planeta, anillo y luna) como plantilla de SF Symbols completa.

Es la marca pulida del 1 nov 2026, la misma de `OrbitalMark` y del ícono de la app: el planeta de contorno con el hueco
donde le cruza el anillo, el anillo como pincelada que engorda al frente y termina en punta, y la luna sobre su órbita. El
trazo lo arma `scripts/orbital_mark_path.swift` con CoreGraphics (por eso corre en la Mac). Antes del 13 nov este símbolo
seguía con la marca vieja (anillo de grosor parejo), y el Centro de control y la Live Activity no se veían como el ícono.

El Centro de control solo pinta símbolos que traen todos los grosores y tamaños: la plantilla trae las 27 variantes (9
grosores × S, M y L, con los mismos puntos en todas). La de antes traía solo Regular-M y el control salía en blanco.

Uso: python3 scripts/orbital_symbol.py  (escribe el .svg en los dos catálogos: la extensión y la app)
"""
from __future__ import annotations

import json
import math
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TARGETS = [ROOT / "ios/App/Widgets/Symbols.xcassets/orbital.mark.symbolset/orbital.mark.svg",
           ROOT / "ios/App/Resources/Assets.xcassets/orbital.mark.symbolset/orbital.mark.svg"]

# Grosores (planeta, lo que baja la curva de afuera y la de adentro del anillo, el hueco y el radio de la luna), en la caja
# de 32. Regular es exactamente DS.Brand (Tokens.swift); del delgado al grueso cambia el trazo, no el dibujo.
WEIGHT_NAMES = ["Ultralight", "Thin", "Light", "Regular", "Medium", "Semibold", "Bold", "Heavy", "Black"]
THIN, REGULAR, BLACK = (1.2, 4.96, 3.78, 1.5, 1.6), (2.8, 4.96, 2.34, 1.8, 1.98), (3.9, 4.96, 1.30, 2.0, 2.4)
PLANET = (16.0, 16.0, 7.2)
CAP = 10   # lo usa la dona (donut_symbol.py)
# Con qué medidas de DS.Brand se dibujó (DesignRulesTests compara esta firma con Tokens.swift: si la marca cambia, hay
# que volver a correr este script).
SIGNATURE = "marca: planeta 7.2 x 2.8, anillo 14.51 4.96/2.34 a -18.8, hueco 1.8"


def weight(i: int) -> tuple[float, ...]:
    """Del delgado al normal (0…3) y del normal al grueso (3…8), en línea recta."""
    a, b, t = (THIN, REGULAR, i / 3) if i <= 3 else (REGULAR, BLACK, (i - 3) / 5)
    return tuple(x + (y - x) * t for x, y in zip(a, b, strict=True))


WEIGHTS = {f"{name}-{scale}": weight(i) for i, name in enumerate(WEIGHT_NAMES) for scale in "SML"}
# Dónde va cada variante: la columna por grosor y el renglón por tamaño (con su línea base); S más chico, L más grande.
COLUMN = {f"{name}-{scale}": 413.0 + 300.0 * i for i, name in enumerate(WEIGHT_NAMES) for scale in "SML"}
ROW = {"S": (696.0, 625.541, 0.84), "M": (1126.0, 1055.54, 1.0), "L": (1556.0, 1485.54, 1.21)}
UNITS = 156.0   # antes 92 y 122: la marca es ancha y baja; en el botón redondo del Centro de control se veía chica


def to_sheet(x: float, y: float, column: float, row: str = "M") -> tuple[float, float]:
    base, cap, factor = ROW[row]
    s = UNITS * factor / 32
    return column + (x - 16) * s, (base + cap) / 2 + (y - 16) * s


def circle(cx: float, cy: float, r: float, clockwise: bool) -> list[tuple[float, float]]:
    n = 64
    pts = [(cx + r * math.cos(2 * math.pi * i / n), cy + r * math.sin(2 * math.pi * i / n)) for i in range(n)]
    return pts if clockwise else pts[::-1]


def area(points: list[tuple[float, float]]) -> float:
    return sum(points[i][0] * points[(i + 1) % len(points)][1] - points[(i + 1) % len(points)][0] * points[i][1] for i in range(len(points))) / 2


def oriented(points: list[tuple[float, float]], positive: bool) -> list[tuple[float, float]]:
    return points if (area(points) > 0) == positive else points[::-1]


def path(points: list[tuple[float, float]], column: float, row: str) -> str:
    sheet = [to_sheet(x, y, column, row) for x, y in points]
    return "M " + " L ".join(f"{x:.2f},{y:.2f}" for x, y in sheet) + " Z"


def mark_commands(planet_w: float, outer: float, inner: float, gap: float, moon_r: float) -> list[list]:
    script = ROOT / "scripts" / "orbital_mark_path.swift"
    args = [f"{v:.4f}" for v in (planet_w, outer, inner, gap, moon_r)]
    return json.loads(subprocess.run(["swift", str(script), *args], check=True, capture_output=True, text=True).stdout)


def glyph(name: str) -> tuple[str, float, float]:
    column, row = COLUMN[name], name.split("-")[1]
    parts, xs = [], []
    for op, *nums in mark_commands(*WEIGHTS[name]):
        pts = [to_sheet(nums[i], nums[i + 1], column, row) for i in range(0, len(nums), 2)]
        xs += [x for x, _ in pts]
        parts.append(op + " " + " ".join(f"{x:.2f},{y:.2f}" for x, y in pts) if pts else op)
    return " ".join(parts), min(xs), max(xs)


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
<!-- La marca de Orbital (planeta, anillo y luna). Generado por scripts/orbital_symbol.py: no se edita a mano. {SIGNATURE} -->
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
