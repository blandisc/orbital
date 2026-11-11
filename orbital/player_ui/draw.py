"""Las piezas con que se dibuja: figuras, vidrio, íconos, degradados, texto que cabe y los glifos del mando."""

from __future__ import annotations

import math
import re

from . import canvas
from .canvas import (
    EDGE_TOKENS,
    FONT,
    FONT_SEMI,
    FS,
    GLASS_TOKENS,
    GLYPH,
    GLYPH_SOLID,
    KEY_NAMES,
    MARGIN,
    SHADE,
    SOFT,
    TEXT,
    H,
    ass_color,
)
from .labels import esc


# --- piezas de dibujo (reutilizables) ------------------------------------------------------------
def _shape(path: str, color: str, alpha: str = "00", *, outline: str | None = None, width: float = 0,
           fill_alpha: str | None = None, blur: float = 0, outline_alpha: str = "00") -> str:
    """Una figura ASS (coordenadas absolutas del lienzo). `outline`: además, un borde de ese color (`outline_alpha`: su
    transparencia; el filo del vidrio es un blanco casi transparente)."""
    fill = f"\\1c{color}\\1a&H{fill_alpha or alpha}&"
    border = f"\\3c{outline}\\3a&H{outline_alpha}&\\bord{width:g}" if outline else "\\bord0"
    soft = f"\\blur{blur:g}" if blur else ""
    return f"{{\\an7\\pos(0,0){border}\\shad0{soft}{fill}\\p1}}{path}{{\\p0}}"


def rrect_path(x: float, y: float, w: float, h: float, r: float) -> str:
    """Rectángulo de esquinas redondeadas (curvas de Bézier, como el CSS border-radius)."""
    r = max(0.0, min(r, w / 2, h / 2))
    x2, y2 = x + w, y + h
    if r == 0:
        return f"m {x:.1f} {y:.1f} l {x2:.1f} {y:.1f} l {x2:.1f} {y2:.1f} l {x:.1f} {y2:.1f}"
    k = r * .4477  # 1 − 0,5523: el punto de control de un cuarto de círculo
    return (f"m {x + r:.1f} {y:.1f} l {x2 - r:.1f} {y:.1f} b {x2 - k:.1f} {y:.1f} {x2:.1f} {y + k:.1f} {x2:.1f} {y + r:.1f} "
            f"l {x2:.1f} {y2 - r:.1f} b {x2:.1f} {y2 - k:.1f} {x2 - k:.1f} {y2:.1f} {x2 - r:.1f} {y2:.1f} "
            f"l {x + r:.1f} {y2:.1f} b {x + k:.1f} {y2:.1f} {x:.1f} {y2 - k:.1f} {x:.1f} {y2 - r:.1f} "
            f"l {x:.1f} {y + r:.1f} b {x:.1f} {y + k:.1f} {x + k:.1f} {y:.1f} {x + r:.1f} {y:.1f}")


def rrect(x: float, y: float, w: float, h: float, r: float, color: str, alpha: str = "00", **kw) -> str:
    return _shape(rrect_path(x, y, w, h, r), color, alpha, **kw)


def circle(cx: float, cy: float, r: float, color: str, alpha: str = "00", **kw) -> str:
    return rrect(cx - r, cy - r, 2 * r, 2 * r, r, color, alpha, **kw)


def ring(cx: float, cy: float, r: float, thickness: float, fraction: float, color: str, alpha: str = "00") -> str:
    """Anillo que se llena en el sentido del reloj desde arriba (cuenta atrás)."""
    fraction = max(0.0, min(1.0, fraction))
    if fraction <= 0:
        return ""
    steps = max(2, int(64 * fraction))
    outer, inner = r, r - thickness

    def point(radius: float, t: float) -> str:
        a = -math.pi / 2 + 2 * math.pi * fraction * t
        return f"{cx + radius * math.cos(a):.1f} {cy + radius * math.sin(a):.1f}"

    outside = [point(outer, i / steps) for i in range(steps + 1)]
    inside = [point(inner, i / steps) for i in range(steps, -1, -1)]
    return _shape("m " + outside[0] + " l " + " ".join(outside[1:] + inside), color, alpha)


def _alpha(opacity: float) -> str:
    """Opacidad (0 a 1) -> transparencia ASS («00» tapa, «FF» no se ve)."""
    return f"{max(0, min(255, round(255 * (1 - opacity)))):02X}"


def glass_fill(kind: str = "glass") -> tuple[str, str]:
    """El color y la transparencia ASS de un vidrio de `GLASS_TOKENS`: sus capas compuestas en una sola (el fondo abajo y,
    encima, la luz blanca, en su promedio de arriba a abajo). Una figura en vez de tres: más barato para libass."""
    layers = list(GLASS_TOKENS[kind])
    light = [layer for layer in layers if layer[:3] == (255, 255, 255)]
    base = [layer for layer in layers if layer[:3] != (255, 255, 255)]
    sheen = (255, 255, 255, sum(layer[3] for layer in light) / len(light))
    rgb, opacity = (0.0, 0.0, 0.0), 0.0
    for *c, a in [*base, sheen]:
        out = a + opacity * (1 - a)
        rgb = tuple((ci * a + pi * opacity * (1 - a)) / out for ci, pi in zip(c, rgb, strict=True)) if out else rgb
        opacity = out
    hex_color = "#" + "".join(f"{round(ci):02X}" for ci in rgb)
    return ass_color(hex_color), _alpha(opacity)


def glass(x: float, y: float, w: float, h: float, r: float, kind: str = "glass", edge: str | None = "glass") -> str:
    """Una pieza de vidrio (receta «Vidrio»): «glass» para lo que se toca o se enfoca (botones, píldoras, casillas),
    «glass-strong» para lo que flota encima de todo (paneles, tarjetas, avisos), «glass-selected» para lo elegido. Su filo
    (`edge`): «glass» si flota sobre el video, «glass-hairline» dentro de un panel, None sin filo (una franja de orilla a orilla)."""
    color, alpha = glass_fill(kind)
    if not edge:
        return rrect(x, y, w, h, r, color, alpha)
    top, ring_opacity = EDGE_TOKENS[edge]
    inset = max(r * .8, 2)  # la luz de arriba, entre las dos esquinas
    return "\n".join([rrect(x, y, w, h, r, color, alpha, outline=TEXT, width=1.2, outline_alpha=_alpha(ring_opacity)),
                      rrect(x + inset, y, max(0.0, w - 2 * inset), 1.5, .75, TEXT, _alpha(top))])


# Íconos del reproductor, dibujados en una cuadrícula de 24 (como los SF Symbols del iPhone y los `ICONS` de la interfaz).
# Cada uno es una lista de (figura, trazo): con trazo, solo el contorno (un ícono de línea); sin él, relleno.
ICON_PATHS: dict[str, list[tuple[str, float]]] = {
    # Al instante (Real-Debrid ya la tiene): el rayo, como «bolt.fill» del iPhone.
    "bolt": [("m 13 2 l 4 13.5 l 11 13.5 l 10 22 l 20 10 l 13 10", 0)],
    # Hay que bajarla: la nube con flecha, la de todo lo de Real-Debrid (PT5).
    "cloud-down": [("m 7 19 b 4.2 19 2 16.8 2 14 b 2 11.4 4 9.3 6.5 9.1 b 7.4 6.1 10 4 13 4 b 16.6 4 19.5 6.8 19.8 10.3 "
                    "b 21.7 10.9 23 12.7 23 14.8 b 23 17.1 21.1 19 18.8 19", 1.8),
                   ("m 11.2 8.5 l 12.8 8.5 l 12.8 13.5 l 11.2 13.5", 0), ("m 8.8 12.6 l 15.2 12.6 l 12 16.4", 0)],
    # Idioma dudoso: un círculo con «?» (el «?» lo pone `icon`, en texto).
    "doubt": [("m 12 3 b 17 3 21 7 21 12 b 21 17 17 21 12 21 b 7 21 3 17 3 12 b 3 7 7 3 12 3", 1.8)],
    # De qué complemento viene una versión (AddonMark de la interfaz y del iPhone): Ⓣ Torrentio, Ⓒ Comet (la «C» la pone
    # `icon`, con un arco) y la pieza para los demás.
    "addon-torrentio": [("m 12 3 b 17 3 21 7 21 12 b 21 17 17 21 12 21 b 7 21 3 17 3 12 b 3 7 7 3 12 3", 1.8),
                        ("m 8.5 7.1 l 15.5 7.1 l 15.5 8.9 l 8.5 8.9", 0), ("m 11.1 7.1 l 12.9 7.1 l 12.9 16.5 l 11.1 16.5", 0)],
    "addon-comet": [("m 12 3 b 17 3 21 7 21 12 b 21 17 17 21 12 21 b 7 21 3 17 3 12 b 3 7 7 3 12 3", 1.8)],
    "addon": [("m 5.4 7.6 l 8.65 7.6 b 8.65 6.36 9.66 5.35 10.9 5.35 b 12.14 5.35 13.15 6.36 13.15 7.6 l 16.4 7.6 "
               "l 16.4 10.85 b 17.64 10.85 18.65 11.86 18.65 13.1 b 18.65 14.34 17.64 15.35 16.4 15.35 l 16.4 18.6 l 5.4 18.6", 1.8)],
    # Desde el principio: |◀.
    "restart": [("m 4 5 l 6.6 5 l 6.6 19 l 4 19", 0), ("m 20 5 l 20 19 l 8.4 12", 0)],
    # Volver a donde ibas: la flecha que regresa (↺; el arco lo pone `icon`).
    "resume": [],
    # Seguir en el iPhone · Enviar al iPhone · Descargar en el iPhone: el teléfono con lo que pasa adentro.
    "phone-play": [("m 9.4 2.5 l 14.6 2.5 b 16 2.5 17 3.5 17 4.9 l 17 19.1 b 17 20.5 16 21.5 14.6 21.5 l 9.4 21.5 "
                    "b 8 21.5 7 20.5 7 19.1 l 7 4.9 b 7 3.5 8 2.5 9.4 2.5", 1.7), ("m 10.6 8.6 l 15 12 l 10.6 15.4", 0)],
    "phone-send": [("m 9.4 2.5 l 14.6 2.5 b 16 2.5 17 3.5 17 4.9 l 17 19.1 b 17 20.5 16 21.5 14.6 21.5 l 9.4 21.5 "
                    "b 8 21.5 7 20.5 7 19.1 l 7 4.9 b 7 3.5 8 2.5 9.4 2.5", 1.7),
                   ("m 11.2 10 l 12.8 10 l 12.8 16 l 11.2 16", 0), ("m 8.9 10.8 l 15.1 10.8 l 12 7.2", 0)],
    "phone-down": [("m 9.4 2.5 l 14.6 2.5 b 16 2.5 17 3.5 17 4.9 l 17 19.1 b 17 20.5 16 21.5 14.6 21.5 l 9.4 21.5 "
                    "b 8 21.5 7 20.5 7 19.1 l 7 4.9 b 7 3.5 8 2.5 9.4 2.5", 1.7),
                   ("m 11.2 7 l 12.8 7 l 12.8 13 l 11.2 13", 0), ("m 8.9 12.2 l 15.1 12.2 l 12 15.8", 0)],
    # Seguir solo este capítulo (salir del canal): un episodio, el ▶ en su cuadro.
    "episode": [("m 5.5 5 l 18.5 5 b 20 5 21 6 21 7.5 l 21 16.5 b 21 18 20 19 18.5 19 l 5.5 19 b 4 19 3 18 3 16.5 l 3 7.5 "
                 "b 3 6 4 5 5.5 5", 1.8), ("m 10 8.8 l 15.4 12 l 10 15.2", 0)],
}

_NUMBER = re.compile(r"-?\d+(?:\.\d+)?")


def icon(name: str, cx: float, cy: float, size: float, color: str = TEXT, alpha: str = "00") -> str:
    """Un ícono de `ICON_PATHS` centrado en (cx, cy), de `size` de lado en el lienzo, del color de su texto."""
    k = size / 24
    ox, oy = cx - 12 * k, cy - 12 * k

    def place(path: str) -> str:
        n = iter(range(10 ** 6))
        return _NUMBER.sub(lambda m: f"{(ox if next(n) % 2 == 0 else oy) + float(m.group()) * k:.1f}", path)

    out = [_shape(place(path), color, "FF", outline=color, width=stroke * k / 2, outline_alpha=alpha) if stroke
           else _shape(place(path), color, alpha) for path, stroke in ICON_PATHS[name]]
    if name == "doubt":
        out.append(f"{{\\an5\\pos({cx:.0f},{cy + .5 * k:.0f})\\fn{FONT}\\fs{size * .8:.0f}\\b1\\bord0\\shad0\\1c{color}\\1a&H{alpha}&}}?")
    elif name == "addon-comet":  # la «C»: abierta a la derecha
        out.append(arc(cx, cy, 4.2 * k, 1.8 * k, 42.0, 318.0, color, alpha))
    elif name == "resume":  # el arco abierto arriba a la izquierda y la punta que regresa (a la izquierda)
        r, start, end = 7.6 * k, 262.0, 560.0
        out.append(arc(cx, cy + k, r, 2 * k, start, end, color, alpha))
        a = math.radians(start)
        px, py = cx + r * math.cos(a), cy + k + r * math.sin(a)
        dx, dy = math.sin(a), -math.cos(a)  # hacia donde regresa el arco (contra el reloj)
        nx, ny = -dy, dx
        tip, half = 3.6 * k, 3.4 * k
        out.append(_shape(f"m {px + dx * tip:.1f} {py + dy * tip:.1f} l {px + nx * half:.1f} {py + ny * half:.1f} "
                          f"l {px - nx * half:.1f} {py - ny * half:.1f}", color, alpha))
    return "\n".join(out)


# Cuánto pueden cubrir, sumadas, las figuras de una capa (en pantallas completas): a 4K libass deja de pintar la capa
# entera pasando de ~12 (medido en la Lenovo con mpv: 12.3 sí, 16.5 no). Cada paso de un velo es una figura que llega
# hasta su orilla oscura, así que un velo de muchos pasos cuesta varias pantallas.
SHADE_BUDGET = 11.0


def gradient(y0: float, y1: float, top_alpha: int, bottom_alpha: int, steps: int = 32) -> str:
    """Velo negro que va de `top_alpha` a `bottom_alpha` (255 = transparente) sin franjas visibles.

    Las capas se apilan (cada una llega hasta el borde del lado oscuro): así ningún pixel tiene dos
    bordes encima (con franjas contiguas se veían líneas finas). La opacidad de cada capa se calcula
    para que el total siga una curva suave."""
    down = bottom_alpha < top_alpha  # lo oscuro abajo
    light, dark = (top_alpha, bottom_alpha) if down else (bottom_alpha, top_alpha)

    def clear(t: float) -> float:  # transparencia total en t (0 = lado claro, 1 = lado oscuro)
        eased = t * t * (3 - 2 * t)
        return (light - (light - dark) * eased) / 255

    out, h, before = [], (y1 - y0) / steps, clear(0)
    for i in range(steps):
        now = clear((i + 1) / steps)
        layer = 1 - now / before if before > 0 else 1  # opacidad que aporta esta capa
        before = now
        a = max(0, min(255, round(255 * (1 - layer))))
        if a >= 255:
            continue
        if down:
            top = y0 + i * h
            out.append(_shape(rrect_path(0, top, canvas.W, y1 - top, 0), SHADE, f"{a:02X}", blur=3))
        else:
            out.append(_shape(rrect_path(0, y0, canvas.W, y1 - i * h - y0, 0), SHADE, f"{a:02X}", blur=3))
    return "\n".join(out)


def side_gradient(x1: float, left_alpha: int, steps: int = 28) -> str:
    """Velo negro desde la orilla izquierda (`left_alpha`, 255 = transparente) que se desvanece hasta `x1`: lo oscuro
    «sangra» sobre el video, sin borde. Las capas se apilan desde la orilla, como `gradient`."""
    def clear(t: float) -> float:  # transparencia total en t (0 = la orilla, 1 = x1)
        eased = t * t * (3 - 2 * t)
        return (left_alpha + (255 - left_alpha) * eased) / 255

    out, step, before = [], x1 / steps, clear(1)
    for i in range(steps, 0, -1):  # de lo claro (x1) a lo oscuro (la orilla)
        now = clear((i - 1) / steps)
        layer = 1 - now / before if before > 0 else 1
        before = now
        a = max(0, min(255, round(255 * (1 - layer))))
        if a < 255:
            out.append(_shape(rrect_path(0, 0, i * step, H, 0), SHADE, f"{a:02X}", blur=3))
    return "\n".join(out)


_ALPHA = re.compile(r"\\([13]a|alpha)&H([0-9A-Fa-f]{2})&")


def fade(ass: str, appear: float) -> str:
    """La misma capa a medio aparecer (`appear` de 0 a 1): cada transparencia se acerca a «nada» en lo que falta. Con esto la
    pausa entra con un fundido en tres pasos en vez de aparecer de golpe (PlayerScreen.PAUSE_FADE)."""
    if appear >= 1:
        return ass
    rest = 1 - max(0.0, appear)

    def lighter(m: re.Match) -> str:
        a = int(m.group(2), 16)
        return f"\\{m.group(1)}&H{round(a + (255 - a) * rest):02X}&"
    return _ALPHA.sub(lighter, ass)


def text(x: float, y: float, value: str, size: int, color: str = TEXT, *, weight: str = "regular", align: int = 7,
         alpha: str = "00") -> str:
    """Texto ya escapado (o con etiquetas). weight: regular | semi | bold."""
    font = FONT_SEMI if weight == "semi" else FONT
    bold = 1 if weight == "bold" else 0
    return (f"{{\\an{align}\\pos({x:.0f},{y:.0f})\\fn{font}\\fs{round(size * FS * canvas._text_scale)}\\b{bold}\\bord0\\shad0\\q2"
            f"\\1c{color}\\1a&H{alpha}&}}{value}")


_NARROW = set("iljtf.,:;·'|!()[] ")


def text_width(value: str, size: int, weight: str = "regular") -> float:
    """Ancho aproximado en el lienzo (Segoe UI): para acomodar piezas una tras otra."""
    w = 0.0
    for ch in str(value):
        if ch in _NARROW:
            w += .29
        elif ch.isupper() or ch in "mwMW%":
            w += .68
        elif ch.isdigit():
            w += .55
        else:
            w += .52
    return w * size * canvas._text_scale * (1.05 if weight != "regular" else 1)


def wrap(value: str, size: int, width: float, lines: int) -> list[str]:
    """Parte un texto en renglones que caben en `width`; el último termina en «…» si sobra."""
    words, out, line = str(value or "").split(), [], ""
    for word in words:
        candidate = f"{line} {word}".strip()
        if text_width(candidate, size) <= width:
            line = candidate
            continue
        if line:
            out.append(line)
        line = word
        if len(out) == lines:
            break
    if line and len(out) < lines:
        out.append(line)
    out = [fit(x, size, width) for x in out]  # una palabra sola más ancha que el renglón (nombre de archivo)
    if out and " ".join(out) != " ".join(words):
        last = out[-1]
        while last and text_width(last + "…", size) > width:
            last = last[:-1]
        out[-1] = last.rstrip(" ,.;:") + "…"
    return out


def wrap_sentences(value: str, size: int, width: float, lines: int) -> list[str]:
    """Como `wrap`, pero si el texto no cabe termina en la última frase completa que sí cabe, con su punto, no a media frase
    con «…» (PA-1, 2 nov 2026: la sinopsis de la pausa acababa en «…en un lugar en el que…»). Si ni la primera frase cabe,
    se corta como siempre."""
    text_value = str(value or "").strip()
    full = wrap(text_value, size, width, lines)
    if " ".join(full) == " ".join(text_value.split()):
        return full
    sentences = [s for s in re.split(r"(?<=[.!?…])\s+", text_value) if s]
    for count in range(len(sentences) - 1, 0, -1):
        shorter = " ".join(sentences[:count])
        out = wrap(shorter, size, width, lines)
        if " ".join(out) == " ".join(shorter.split()):
            return out
    return full


def fit(value: str, size: int, width: float, weight: str = "regular") -> str:
    """Una sola línea que cabe en `width`. Si son datos con « · » («Español latino · Estéreo · AAC»), primero se quitan los del
    final, enteros; solo si ni el primero cabe se corta con «…» (RE-1: nada se corta a media palabra si hay de dónde quitar)."""
    value = str(value)
    if text_width(value, size, weight) <= width:
        return value
    pieces = value.split(" · ")
    while len(pieces) > 1:
        pieces.pop()
        shorter = " · ".join(pieces)
        if text_width(shorter, size, weight) <= width:
            return shorter
    value = pieces[0]
    while value and text_width(value + "…", size, weight) > width:
        value = value[:-1]
    return value.rstrip(" ,.;:·") + "…"


def glyph(x: float, cy: float, label: str, size: int = 34, *, solid: bool = False) -> tuple[str, float]:
    """Botón del mando dibujado (círculo, o píldora si son dos) en su color. Devuelve (ass, ancho). Con teclado,
    la tecla que hace lo mismo («Espacio», «Esc»), en el mismo color. De cristal (--glyph-bg); sobre lo blanco (`solid`: el
    botón principal, «Saltar intro»), sólido (--glyph-bg-solid), que ahí el cristal no se vería."""
    color = GLYPH.get(label, TEXT)
    disc = (GLYPH_SOLID, "00") if solid else glass_fill("glyph-bg")
    if canvas.KEYBOARD:  # una tecla: rectángulo redondeado (como las del teclado) y la letra más grande que en el círculo
        label = KEY_NAMES.get(label, label)
        font = int(size * .56)
        w = max(size, text_width(label, font, "bold") + size * .6)
        parts = [rrect(x, cy - size / 2, w, size, size * .24, *disc, outline=color, width=2),
                 text(x + w / 2, cy, esc(label), font, color, weight="bold", align=5)]
        return "\n".join(parts), w
    w = size if len(label) == 1 else max(size, text_width(label, int(size * .44), "bold") + size * .6)
    parts = [rrect(x, cy - size / 2, w, size, size / 2, *disc, outline=color, width=2),
             text(x + w / 2, cy, esc(label), int(size * .44), color, weight="bold", align=5)]
    return "\n".join(parts), w


def hints_width(items: list[tuple[str, str]], size: int = 22) -> float:
    """Lo que mide una fila de pistas (para que el texto de al lado no se encime)."""
    return sum(glyph(0, 0, k)[1] + 12 + text_width(v, size, "semi") for k, v in items) + 36 * max(0, len(items) - 1)


def hints(items: list[tuple[str, str]], y: float, *, right: float | None = None, left: float | None = None,
          size: int = 22) -> str:
    """Pistas «A Pausa  X Audio y subtítulos…» en una fila, alineadas a la derecha o a la izquierda."""
    if not items or canvas.TOUCH:  # con el dedo no hay botones del mando que enseñar
        return ""
    gap, inner = 36, 12
    if canvas.KEYBOARD:  # con teclado no se mantiene nada: Esc pregunta y sale
        items = [(k, v.replace("Mantén: salir", "Salir")) for k, v in items]
    widths = [(glyph(0, 0, k)[1], text_width(v, size, "semi")) for k, v in items]
    total = sum(g + inner + t for g, t in widths) + gap * (len(items) - 1)
    x = (right - total) if right is not None else (left if left is not None else MARGIN)
    out = []
    for (key, label), (gw, tw) in zip(items, widths, strict=True):
        shape, _ = glyph(x, y, key)
        out.append(shape)
        out.append(text(x + gw + inner, y, esc(label), size, SOFT, weight="semi", align=4))
        x += gw + inner + tw + gap
    return "\n".join(out)


def arc(cx: float, cy: float, r: float, thickness: float, start: float, end: float, color: str, alpha: str = "00") -> str:
    """Un tramo de anillo entre dos ángulos (grados, 0 = a la derecha, en el sentido del reloj): las ondas de la bocina."""
    steps = max(6, int(abs(end - start) / 6))
    outer, inner = r + thickness / 2, r - thickness / 2

    def point(radius: float, deg: float) -> str:
        a = math.radians(deg)
        return f"{cx + radius * math.cos(a):.1f} {cy + radius * math.sin(a):.1f}"

    outside = [point(outer, start + (end - start) * i / steps) for i in range(steps + 1)]
    inside = [point(inner, start + (end - start) * i / steps) for i in range(steps, -1, -1)]
    return _shape("m " + outside[0] + " l " + " ".join(outside[1:] + inside), color, alpha)
