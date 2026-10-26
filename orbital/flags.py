"""Banderitas junto al idioma que eliges (audio, subtítulos, versión), las mismas en la interfaz y en el reproductor.

Cada bandera es un dibujo sencillo de 30 × 20 (rectángulos, polígonos y círculos): de aquí salen los SVG de la interfaz
(`web/img/flags/*.svg` y `web/js/core/flags.js`, que escribe `scripts/flags.py`) y el dibujo ASS del reproductor
(`ass`). Windows no dibuja los emoji de bandera (salen «MX»), por eso no se usan.

El idioma dice la bandera (lo decidió Fernando, igual en el iPhone): «es-419», «Latino» o un español que no dice cuál →
México; «es-ES» o «Castellano» → España; portugués → Brasil (salvo que diga Portugal); inglés → Estados Unidos (salvo
Reino Unido); los demás, el país principal del idioma. Un idioma sin un país que le quede (árabe…), sin bandera.
"""

from __future__ import annotations

import math

W, H = 30, 20
RADIUS = 2.5  # las esquinas, redondeadas


def _band(x1: float, y1: float, x2: float, y2: float, width: float) -> list[tuple[float, float]]:
    """Una franja de ese grueso de un punto a otro (las diagonales del Reino Unido)."""
    dx, dy = x2 - x1, y2 - y1
    n = width / 2 / math.hypot(dx, dy)
    ox, oy = -dy * n, dx * n
    return [(x1 + ox, y1 + oy), (x2 + ox, y2 + oy), (x2 - ox, y2 - oy), (x1 - ox, y1 - oy)]


def _star(cx: float, cy: float, r: float, turn: float = 0.0) -> list[tuple[float, float]]:
    points = []
    for i in range(10):
        a = -math.pi / 2 + turn + i * math.pi / 5
        rr = r if i % 2 == 0 else r * .382
        points.append((cx + rr * math.cos(a), cy + rr * math.sin(a)))
    return points


def _half_disc(cx: float, cy: float, r: float, start: float) -> list[tuple[float, float]]:
    return [(cx + r * math.cos(start + math.pi * i / 16), cy + r * math.sin(start + math.pi * i / 16)) for i in range(17)]


def _stripes(colors: list[str], *, vertical: bool, weights: list[float] | None = None) -> list[tuple]:
    weights = weights or [1.0] * len(colors)
    total, at, out = sum(weights), 0.0, []
    for color, weight in zip(colors, weights, strict=True):
        size = (W if vertical else H) * weight / total
        out.append(("rect", at, 0, size, H, color) if vertical else ("rect", 0, at, W, size, color))
        at += size
    return out


def _gb() -> list[tuple]:
    shapes: list[tuple] = [("rect", 0, 0, W, H, "#012169")]
    for x1, y1, x2, y2 in ((0, 0, W, H), (0, H, W, 0)):
        shapes.append(("poly", _band(x1, y1, x2, y2, 4), "#FFFFFF"))
    for x1, y1, x2, y2 in ((0, 0, W, H), (0, H, W, 0)):
        shapes.append(("poly", _band(x1, y1, x2, y2, 1.4), "#C8102E"))
    return shapes + [("rect", 12, 0, 6, H, "#FFFFFF"), ("rect", 0, 7, W, 6, "#FFFFFF"),
                     ("rect", 13.2, 0, 3.6, H, "#C8102E"), ("rect", 0, 8.2, W, 3.6, "#C8102E")]


def _us() -> list[tuple]:
    shapes = _stripes(["#B22234", "#FFFFFF"] * 3 + ["#B22234"], vertical=False)
    return shapes + [("rect", 0, 0, 13, H * 4 / 7, "#3C3B6E")]


def _kr() -> list[tuple]:
    shapes: list[tuple] = [("rect", 0, 0, W, H, "#FFFFFF"),
                           ("poly", _half_disc(15, 10, 5, math.pi + .6), "#CD2E3A"),
                           ("poly", _half_disc(15, 10, 5, .6), "#0047A0")]
    for x1, y1, x2, y2 in ((4.5, 3.5, 7.5, 6.5), (22.5, 13.5, 25.5, 16.5), (22.5, 6.5, 25.5, 3.5), (4.5, 16.5, 7.5, 13.5)):
        shapes.append(("poly", _band(x1, y1, x2, y2, 2.4), "#000000"))
    return shapes


FLAGS: dict[str, list[tuple]] = {
    "mx": _stripes(["#006847", "#FFFFFF", "#CE1126"], vertical=True) + [("circle", 15, 10, 2.6, "#8C5A2B")],
    "es": _stripes(["#AA151B", "#F1BF00", "#AA151B"], vertical=False, weights=[1, 2, 1]),
    "us": _us(),
    "gb": _gb(),
    "br": [("rect", 0, 0, W, H, "#009C3B"), ("poly", [(3, 10), (15, 2.5), (27, 10), (15, 17.5)], "#FFDF00"),
           ("circle", 15, 10, 4.2, "#002776")],
    "pt": [("rect", 0, 0, 12, H, "#006600"), ("rect", 12, 0, 18, H, "#FF0000"), ("circle", 12, 10, 3.4, "#FFE000")],
    "fr": _stripes(["#0055A4", "#FFFFFF", "#EF4135"], vertical=True),
    "it": _stripes(["#009246", "#FFFFFF", "#CE2B37"], vertical=True),
    "de": _stripes(["#000000", "#DD0000", "#FFCE00"], vertical=False),
    "ru": _stripes(["#FFFFFF", "#0039A6", "#D52B1E"], vertical=False),
    "pl": _stripes(["#FFFFFF", "#DC143C"], vertical=False),
    "nl": _stripes(["#AE1C28", "#FFFFFF", "#21468B"], vertical=False),
    "ua": _stripes(["#0057B7", "#FFD700"], vertical=False),
    "in": _stripes(["#FF9933", "#FFFFFF", "#138808"], vertical=False) + [("circle", 15, 10, 2.4, "#000080")],
    "jp": [("rect", 0, 0, W, H, "#FFFFFF"), ("circle", 15, 10, 6, "#BC002D")],
    "kr": _kr(),
    "cn": [("rect", 0, 0, W, H, "#DE2910"), ("poly", _star(6, 6, 3.6), "#FFDE00")]
          + [("poly", _star(x, y, 1.2, .5), "#FFDE00") for x, y in ((11, 2.5), (13, 4.8), (13, 7.8), (11, 10))],
    "tr": [("rect", 0, 0, W, H, "#E30A17"), ("circle", 11.5, 10, 5, "#FFFFFF"), ("circle", 12.8, 10, 4, "#E30A17"),
           ("poly", _star(18.6, 10, 2.4, -math.pi / 2), "#FFFFFF")],
}

# El idioma (ISO 639-1 o 639-2, o con región) → la bandera. Español y portugués sin región: ver flag_for.
LANG_FLAGS = {
    "es-419": "mx", "es-mx": "mx", "es-la": "mx", "es-us": "mx", "es-es": "es",
    "en": "us", "eng": "us", "en-us": "us", "en-gb": "gb", "en-uk": "gb",
    "pt": "br", "por": "br", "pt-br": "br", "pob": "br", "pt-pt": "pt",
    "fr": "fr", "fre": "fr", "fra": "fr", "it": "it", "ita": "it", "de": "de", "ger": "de", "deu": "de",
    "ru": "ru", "rus": "ru", "pl": "pl", "pol": "pl", "nl": "nl", "dut": "nl", "nld": "nl", "uk": "ua", "ukr": "ua",
    "hi": "in", "hin": "in", "ja": "jp", "jpn": "jp", "ko": "kr", "kor": "kr", "zh": "cn", "chi": "cn", "zho": "cn",
    "tr": "tr", "tur": "tr",
}
LATINO = ("latino", "latin", "latam", "419", "méxico", "mexico", "hispanoam")
CASTELLANO = ("castellano", "castilian", "españa", "spain", "european", "europe")
PORTUGAL = ("portugal", "european", "europeu", "pt-pt")


def flag_for(code: str | None, hint: str = "") -> str | None:
    """La bandera de un idioma («es-419», «spa», «eng»…) y lo que dice la pista («Latino», «Castellano», «Portugal»);
    None si no hay un país que le quede (árabe…)."""
    code = (code or "").strip().lower().replace("_", "-")
    hint = (hint or "").lower()
    if code in ("es", "spa") or code.startswith("es-"):
        if code in LANG_FLAGS:
            return LANG_FLAGS[code]
        if any(w in hint for w in CASTELLANO) and not any(w in hint for w in LATINO):
            return "es"
        return "mx"  # latino, o un español que no dice cuál
    if code in ("pt", "por") and any(w in hint for w in PORTUGAL):
        return "pt"
    return LANG_FLAGS.get(code) or LANG_FLAGS.get(code.split("-")[0])


def _rrect_svg() -> str:
    return f'<rect width="{W}" height="{H}" rx="{RADIUS}"/>'


def svg(name: str) -> str:
    """El archivo SVG de la interfaz (esquinas redondeadas y un filo tenue para que el blanco no se pierda)."""
    parts = []
    for shape in FLAGS[name]:
        kind, color = shape[0], shape[-1]
        if kind == "rect":
            x, y, w, h = (round(v, 2) for v in shape[1:5])
            parts.append(f'<rect x="{x:g}" y="{y:g}" width="{w:g}" height="{h:g}" fill="{color}"/>')
        elif kind == "circle":
            cx, cy, r = shape[1:4]
            parts.append(f'<circle cx="{cx:g}" cy="{cy:g}" r="{r:g}" fill="{color}"/>')
        else:
            points = " ".join(f"{x:.2f},{y:.2f}" for x, y in shape[1])
            parts.append(f'<polygon points="{points}" fill="{color}"/>')
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}">'
            f'<clipPath id="c">{_rrect_svg()}</clipPath><g clip-path="url(#c)">{"".join(parts)}</g>'
            f'<rect x=".5" y=".5" width="{W - 1}" height="{H - 1}" rx="{RADIUS - .5}" fill="none" stroke="#000" stroke-opacity=".25"/></svg>\n')


def _bgr(color: str) -> str:
    """#RRGGBB → &HBBGGRR& (ASS)."""
    c = color.lstrip("#")
    return f"&H{c[4:6]}{c[2:4]}{c[0:2]}&".upper()


def ass(name: str, x: float, y: float, height: float) -> list[str]:
    """La bandera en el reproductor (renglones ASS en coordenadas del lienzo), con su esquina de arriba a la izquierda en
    x, y. Cada figura se recorta a la silueta redondeada, como en la interfaz."""
    s = height / H
    r, w = RADIUS * s, W * s
    k = r * .4477
    x2, y2 = x + w, y + height
    clip = (f"m {x + r:.1f} {y:.1f} l {x2 - r:.1f} {y:.1f} b {x2 - k:.1f} {y:.1f} {x2:.1f} {y + k:.1f} {x2:.1f} {y + r:.1f} "
            f"l {x2:.1f} {y2 - r:.1f} b {x2:.1f} {y2 - k:.1f} {x2 - k:.1f} {y2:.1f} {x2 - r:.1f} {y2:.1f} "
            f"l {x + r:.1f} {y2:.1f} b {x + k:.1f} {y2:.1f} {x:.1f} {y2 - k:.1f} {x:.1f} {y2 - r:.1f} "
            f"l {x:.1f} {y + r:.1f} b {x:.1f} {y + k:.1f} {x + k:.1f} {y:.1f} {x + r:.1f} {y:.1f}")
    out = []
    for shape in FLAGS[name]:
        kind, color = shape[0], shape[-1]
        if kind == "rect":
            px, py, pw, ph = shape[1:5]
            points = [(px, py), (px + pw, py), (px + pw, py + ph), (px, py + ph)]
        elif kind == "circle":
            cx, cy, rr = shape[1:4]
            points = [(cx + rr * math.cos(2 * math.pi * i / 24), cy + rr * math.sin(2 * math.pi * i / 24)) for i in range(24)]
        else:
            points = shape[1]
        path = "m " + " l ".join(f"{x + px * s:.1f} {y + py * s:.1f}" for px, py in points)
        out.append(f"{{\\an7\\pos(0,0)\\bord0\\shad0\\clip({clip})\\1c{_bgr(color)}\\1a&H00&\\p1}}{path}{{\\p0}}")
    return out


JS_RULES = """export function flagFor(code, hint = "") {
  const c = String(code || "").trim().toLowerCase().replace("_", "-");
  const said = String(hint || "").toLowerCase();
  if (c === "es" || c === "spa" || c.startsWith("es-")) {
    if (LANG_FLAGS[c]) return LANG_FLAGS[c];
    if (CASTELLANO.some((w) => said.includes(w)) && !LATINO.some((w) => said.includes(w))) return "es";
    return "mx"; // latino, o un español que no dice cuál
  }
  if ((c === "pt" || c === "por") && PORTUGAL.some((w) => said.includes(w))) return "pt";
  return LANG_FLAGS[c] || LANG_FLAGS[c.split("-")[0]] || null;
}
"""


def js() -> str:
    """`web/js/core/flags.js`: la misma tabla y las mismas reglas que flag_for, para la interfaz (sin colores)."""
    table = ", ".join(f'"{k}": "{v}"' for k, v in sorted(LANG_FLAGS.items()))

    def words(xs: tuple[str, ...]) -> str:
        return "[" + ", ".join(f'"{w}"' for w in xs) + "]"

    return ("// Generado por scripts/flags.py desde orbital/flags.py: no lo edites a mano.\n"
            "/** El idioma («es-419», «eng»…) y lo que dice la pista («Latino») → el archivo de su bandera, o null. */\n"
            f"const LANG_FLAGS = {{ {table} }};\n"
            f"const LATINO = {words(LATINO)};\nconst CASTELLANO = {words(CASTELLANO)};\nconst PORTUGAL = {words(PORTUGAL)};\n"
            + JS_RULES)
