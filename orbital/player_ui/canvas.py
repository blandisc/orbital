"""El lienzo del reproductor: su tamaño, con qué se maneja (mando, teclado o dedo), dónde quedó lo tocable, la paleta y el tamaño del texto.

Dueño del estado que cambia mientras corre: W (set_canvas), TOUCH y KEYBOARD (set_input) y _text_scale (set_text_size).
Las demás piezas los leen como `canvas.W`; ninguna los asigna. `targets` y `placed` son de quien dibuja cada capa."""

from __future__ import annotations

import json
import math
from pathlib import Path

FLAG_H, FLAG_GAP = 22, 12  # la banderita junto al idioma (audio, subtítulos, versión)

W, H = 1920, 1080  # coordenadas del lienzo: 1080 de alto y lo ancho que dé la pantalla (ver set_canvas)

MARGIN = 96

RADIUS_CARD = 22  # --radius-2xl (1 rem a 1080p): la esquina de las tarjetas, los paneles y los menús (el «Ritmo»)

TOUCH = False  # con el dedo: botones que se tocan en vez de glifos del mando

KEYBOARD = False  # con teclado: los glifos dicen la tecla, no el botón del mando

# El botón del mando -> su tecla (las pistas son las mismas; solo cambia lo que dice cada glifo).
KEY_NAMES = {"A": "Espacio", "B": "Esc", "◀ ▶": "← →", "LT RT": "[ ]", "LT": "[", "RT": "]", "LB RB": "RePág AvPág",
             "Home": "Ctrl Inicio"}

# Dónde quedó cada cosa tocable, por capa: (x, y, ancho, alto, acción). Se rehace al dibujar la capa.
targets: dict[str, list[tuple[float, float, float, float, object]]] = {"hud": [], "panel": [], "card": [], "try": [], "volume": []}

# Dónde va lo que no es ASS (el logo del título en pausa: una imagen que mpv pone encima): (x, y, ancho, alto) en el lienzo.
placed: dict[str, tuple[float, float, float, float]] = {}

LOGO_BOX = (860, 190)  # lo más que mide el logo en pausa, en el lienzo


def set_input(mode: str) -> bool:
    """«gamepad», «keyboard» o «touch»: qué enseñan los botones. True si cambió (hay que volver a dibujar)."""
    global TOUCH, KEYBOARD
    before = (TOUCH, KEYBOARD)
    TOUCH, KEYBOARD = mode == "touch", mode == "keyboard"
    return (TOUCH, KEYBOARD) != before


def set_touch(on: bool) -> bool:
    """Con el dedo o con el mando. True si cambió (hay que volver a dibujar)."""
    return set_input("touch" if on else "gamepad")


def hit(layer: str, x: float, y: float, pad: float = 14):
    """La acción de lo tocado en `layer` (con un margen: el dedo no es preciso), o None."""
    for tx, ty, tw, th, action in reversed(targets.get(layer, [])):
        if tx - pad <= x <= tx + tw + pad and ty - pad <= y <= ty + th + pad:
            return action
    return None


def set_canvas(width: float, height: float) -> bool:
    """El lienzo con la forma de la pantalla: en la Legion Go (16:10) mide 1728 x 1080 y en la TV
    1920 x 1080. Con un ancho fijo, mpv estiraba todo en una pantalla 16:10. True si cambió."""
    global W
    try:
        aspect = float(width) / float(height)
    except (TypeError, ValueError, ZeroDivisionError):
        return False
    if not math.isfinite(aspect) or aspect <= 0:
        return False
    new = int(round(H * max(4 / 3, min(aspect, 21 / 9))))
    changed, W = new != W, new
    return changed

# Colores: la misma paleta que la interfaz (web/styles/palette.json), en formato ASS (&HBBGGRR&).
PALETTE = json.loads((Path(__file__).parent.parent / "web" / "styles" / "palette.json").read_text(encoding="utf-8"))


def ass_color(hex_color: str) -> str:
    """#RRGGBB -> &HBBGGRR& (mpv/libass escribe los colores al revés)."""
    r, g, b = hex_color[1:3], hex_color[3:5], hex_color[5:7]
    return f"&H{b}{g}{r}&".upper()


TEXT = ass_color(PALETTE["paper"])

SOFT = ass_color(PALETTE["ink-200"])  # texto secundario claro (sinopsis, datos)

MUTED = ass_color(PALETTE["ink-300"])

PANEL = ass_color(PALETTE["ink-950"])  # tarjetas y paneles sobre el video

ON_LIGHT = ass_color(PALETTE["ink-1000"])  # texto sobre lo enfocado (fondo claro)

GLYPH_SOLID = ass_color(PALETTE["ink-850"])  # --glyph-bg-solid: el disco del glifo sobre lo blanco

NEXT = ass_color(PALETTE["amber-300"])  # «Siguiente» en Y › Episodios (--color-warning: el que sigue, no un error)

LIVE = ass_color(PALETTE["teal-300"])  # «En vivo» del mismo color en toda la app (--color-live; antes verde aquí y rojo en TV)

# Vidrio, como en Orbital (receta «Vidrio» de docs/sistema-de-diseno.md § 0): los mismos números que los tokens de
# themes/orbital.css, capa por capa (la luz blanca que baja y el fondo apenas oscuro), y su filo (arriba más brillante que
# alrededor). `tests/test_player.py · test_player_glass_is_the_glass_of_the_interface` los compara con el CSS. mpv no desenfoca lo
# de atrás (no hay backdrop-filter en ASS): el vidrio del reproductor es solo translúcido, y no cuesta nada en reposo.
GLASS_TOKENS = {
    "glass": ((255, 255, 255, .14), (255, 255, 255, .05), (28, 28, 32, .3)),  # --color-glass: lo que se toca o se enfoca
    "glass-strong": ((255, 255, 255, .08), (255, 255, 255, .02), (30, 30, 36, .74)),  # --color-glass-strong: lo que flota
    "glass-selected": ((255, 255, 255, .32), (255, 255, 255, .16)),  # --color-glass-selected: lo elegido en un grupo
    "glyph-bg": ((255, 255, 255, .2), (255, 255, 255, .06), (24, 24, 28, .42)),  # --glyph-bg: los glifos del mando
}

# El filo: (la luz de arriba, el contorno), como --edge-glass, --edge-glass-hairline y --edge-glass-selected.
EDGE_TOKENS = {"glass": (.3, .1), "glass-hairline": (.22, .08), "glass-selected": (.45, .14)}

SHADE = "&H000000&"  # degradados y velos sobre el video (negro de verdad, a propósito)

# Botones del mando en su color, los mismos que en la interfaz: A verde, B rojo, X azul, Y amarillo.
GLYPH = {"A": ass_color(PALETTE["pad-green"]), "B": ass_color(PALETTE["pad-red"]),
         "X": ass_color(PALETTE["pad-blue"]), "Y": ass_color(PALETTE["pad-yellow"])}

# libass no encuentra «Segoe UI Variable»: la familia clásica, con su corte seminegrita.
FONT = "Segoe UI"

FONT_SEMI = "Segoe UI Semibold"

# \fs en ASS es la altura de la línea, no la del cuerpo como en CSS: con el mismo número la letra sale
# ~25 % más chica. Los tamaños de este archivo son «como en CSS» y se convierten al dibujar.
FS = 1.32

# Ajustes › Tamaño del texto, también en el reproductor (antes solo en la interfaz): la letra crece un poco, y los anchos
# que se miden (fit, wrap) crecen igual, así lo que no cabe se recorta bien.
TEXT_SCALES = {"normal": 1.0, "large": 1.08, "xlarge": 1.16}

_text_scale = 1.0


def set_text_size(name: str | None) -> bool:
    """El tamaño del texto de Ajustes (normal | large | xlarge). True si cambió (hay que redibujar)."""
    global _text_scale
    scale = TEXT_SCALES.get(str(name or "normal"), 1.0)
    changed = scale != _text_scale
    _text_scale = scale
    return changed
