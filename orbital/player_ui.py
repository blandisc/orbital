"""Lo que se ve encima del video: la interfaz del reproductor de Orbital, dibujada en mpv.

mpv pinta texto y figuras ASS encima del video (comando osd-overlay). Aquí solo se arma ese texto
(funciones puras, con pruebas); player_screen.py decide cuándo mostrarlo. El diseño es el de los
tableros «Reproductor» del lienzo (docs/sistema-de-diseno.md § 8):

  * Reproduciendo (al tocar un botón): título, una barra gruesa partida por capítulos con su punto,
    el tiempo («termina a las 23:40»), idioma y fuente, y solo tres pistas: A, X, Y.
  * En pausa: el video se oscurece; título grande, datos, sinopsis y los botones.
  * Adelantando: solo la barra y, sobre el punto, la hora a la que vas y el capítulo.
  * Panel de columnas abajo (el video sigue): X = Audio · Subtítulos · Tamaño; Y = Más (Episodios ·
    Fuente · Reproducción). ◀ ▶ cambian de columna, ↑ ↓ y A eligen.
  * Tarjetas: «Saltar intro» (un botón claro), «Siguiente episodio» (con cuenta atrás en anillo) y
    «¿Sigues viendo?». Avisos breves arriba a la derecha (el volumen, con su barra).

Piezas reutilizables (todas aquí): rrect, circle, ring, gradient, glyph, hints, pills, text, wrap.

Con el dedo (la pantalla de la Legion Go): `TOUCH` cambia los glifos del mando por botones que se
tocan (sin «A», «X», «Y») y cada botón anota dónde quedó en `targets` (por capa: «hud», «panel»,
«card»), para que player_screen sepa qué tocaste.
"""

from __future__ import annotations

import json
import math
import re
from collections.abc import Sequence
from dataclasses import dataclass, field
from pathlib import Path

from . import flags

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
PALETTE = json.loads((Path(__file__).parent / "web" / "styles" / "palette.json").read_text(encoding="utf-8"))


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

LANGUAGES = {
    "en": "Inglés", "eng": "Inglés", "es": "Español", "spa": "Español", "es-419": "Español latino", "es-mx": "Español latino", "es-es": "Castellano",
    "fr": "Francés", "fre": "Francés", "fra": "Francés", "it": "Italiano", "ita": "Italiano", "de": "Alemán",
    "ger": "Alemán", "deu": "Alemán", "pt": "Portugués", "por": "Portugués", "ja": "Japonés", "jpn": "Japonés",
    "ko": "Coreano", "kor": "Coreano", "zh": "Chino", "chi": "Chino", "zho": "Chino", "ru": "Ruso", "rus": "Ruso",
    "cs": "Checo", "cze": "Checo", "ces": "Checo", "pl": "Polaco", "pol": "Polaco", "hu": "Húngaro", "hun": "Húngaro",
    "tr": "Turco", "tur": "Turco", "ar": "Árabe", "ara": "Árabe", "hi": "Hindi", "hin": "Hindi", "nl": "Neerlandés",
    "dut": "Neerlandés", "nld": "Neerlandés", "sv": "Sueco", "swe": "Sueco", "uk": "Ucraniano", "ukr": "Ucraniano",
}


def esc(value: str) -> str:
    """Texto seguro para ASS (las llaves abren etiquetas)."""
    return str(value).replace("\\", "⧵").replace("{", "(").replace("}", ")").replace("\n", " ")


def clock(seconds: float | None) -> str:
    if not isinstance(seconds, (int, float)) or not math.isfinite(seconds) or seconds < 0:
        return "--:--"
    s = int(seconds)
    h, m, s = s // 3600, s % 3600 // 60, s % 60
    return f"{h}:{m:02d}:{s:02d}" if h else f"{m}:{s:02d}"


def language(code: str | None) -> str:
    if not code:
        return ""
    return LANGUAGES.get(code.lower(), code.upper() if len(code) <= 3 else code)


def sub_kind(track: dict) -> str:
    """«forced» (solo los letreros), «sdh» (para sordos: con [música], [risas]…) o «normal»."""
    title = str(track.get("title") or "").strip().lower()
    if track.get("forced") or "forced" in title or "forzad" in title:
        return "forced"
    if track.get("hearing-impaired") or "sdh" in title or title == "cc" or "sordos" in title or "hearing" in title:
        return "sdh"
    return "normal"


# La variante de un idioma va pegada a él («Español latino», no «Español · Latino»): un separador menos y el nombre del audio
# cabe en su columna (RE-1, 2 nov 2026: se cortaba en «Español · Latino · Estér…»).
VARIANTS = {"latino", "latinoamérica", "latinoamericano", "castellano", "españa", "méxico", "brasil", "portugal", "francia", "canadá"}


def track_label(track: dict) -> str:
    """'Inglés · 5.1 · E-AC3' / 'Español latino · Estéreo' / 'Español · Forzados' / 'Pista 3'."""
    parts = [language(track.get("lang"))]
    title = (track.get("title") or "").strip()
    lowered = title.lower()
    kind = sub_kind(track)
    if kind == "forced":
        parts.append("Forzados")
    elif kind == "sdh":
        parts.append("Para sordos")
    elif title and lowered in VARIANTS and parts[0]:
        parts[0] = f"{parts[0]} {lowered}"
    elif title and language(track.get("lang")).lower() not in lowered and len(title) <= 28:
        parts.append(title)
    if track.get("type") == "audio":
        channels = track.get("demux-channel-count") or track.get("audio-channels")
        if isinstance(channels, int):
            parts.append({1: "Mono", 2: "Estéreo", 6: "5.1", 8: "7.1"}.get(channels, f"{channels} canales"))
        if track.get("codec"):
            parts.append(str(track["codec"]).upper().replace("EAC3", "E-AC3"))
    if track.get("external"):
        parts.append("de tu addon")
    label = " · ".join(p for p in parts if p)
    return label or f"Pista {track.get('id', '')}".strip()


def current_label(tracks: list[dict], kind: str) -> str:
    chosen = next((t for t in tracks if t.get("type") == kind and t.get("selected")), None)
    if chosen is None:
        return "No" if kind == "sub" else "—"
    return language(chosen.get("lang")) or track_label(chosen)


def current_flag(tracks: list[dict]) -> str | None:
    """La bandera del audio que suena (None si no hay pista o su idioma no tiene país)."""
    chosen = next((t for t in tracks if t.get("type") == "audio" and t.get("selected")), None)
    return flags.flag_for(chosen.get("lang"), str(chosen.get("title") or "")) if chosen else None


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
            out.append(_shape(rrect_path(0, top, W, y1 - top, 0), SHADE, f"{a:02X}", blur=3))
        else:
            out.append(_shape(rrect_path(0, y0, W, y1 - i * h - y0, 0), SHADE, f"{a:02X}", blur=3))
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
    return (f"{{\\an{align}\\pos({x:.0f},{y:.0f})\\fn{font}\\fs{round(size * FS * _text_scale)}\\b{bold}\\bord0\\shad0\\q2"
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
    return w * size * _text_scale * (1.05 if weight != "regular" else 1)


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
    if KEYBOARD:  # una tecla: rectángulo redondeado (como las del teclado) y la letra más grande que en el círculo
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
    if not items or TOUCH:  # con el dedo no hay botones del mando que enseñar
        return ""
    gap, inner = 36, 12
    if KEYBOARD:  # con teclado no se mantiene nada: Esc pregunta y sale
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


# --- estado de lo que se muestra --------------------------------------------------------------------
@dataclass
class Hud:
    title: str
    detail: str = ""  # "T2 E3 · Nombre del episodio" o "Película"
    position: float | None = None
    duration: float | None = None
    paused: bool = False
    audio: str = ""
    subtitles: str = ""
    source: str = ""  # "1080p · Torrentio"
    chapters: list[float] = field(default_factory=list)  # inicio de cada capítulo (s)
    chapter_titles: list[str] = field(default_factory=list)
    series: bool = False  # LT/RT cambian de episodio
    next: str = ""  # «E3» o «T6 E1»: el episodio que sigue (la píldora «Siguiente» y la pista RT); "" si no hay
    clip: bool = False  # un tráiler: no tiene versiones ni episodios (sin la «Y»)
    now: str = ""  # la hora, arriba a la derecha
    facts: str = ""  # "2024 · ★ 8.5 · Ciencia ficción" (en pausa)
    description: str = ""  # sinopsis (en pausa)
    seeking: str = ""  # "+10 s" / "−1 min" mientras adelantas: solo la barra y la burbuja
    pip: bool = False  # Home lo pone en pequeño (Ajustes): se dice arriba, que si no nadie lo descubre
    logo: tuple[float, float] | None = None  # en pausa, el logo del título (ancho, alto en el lienzo) en vez de su nombre
    audio_flag: str | None = None  # la bandera del audio que suena: va en lugar de su nombre (M2/N2, como la ficha y el iPhone)


def info_line(hud: Hud) -> str:
    """«Inglés · Subtítulos en español · 1080p · Torrentio»; con bandera, sin el nombre del audio: «· Subtítulos…» (la
    bandera la dibuja `info_ass` antes del texto, como «🇲🇽 · 1080p» en la ficha)."""
    if hud.subtitles and hud.subtitles not in ("No", "—"):
        subs = f"Subtítulos en {hud.subtitles[:1].lower()}{hud.subtitles[1:]}"
    else:
        subs = "Sin subtítulos"
    audio = "" if hud.audio_flag or hud.audio == "—" else hud.audio
    line = "  ·  ".join(p for p in (audio, subs, hud.source) if p)
    return f"·  {line}" if hud.audio_flag else line


def info_ass(hud: Hud, room: float) -> list[str]:
    """La línea de abajo del reproductor: la bandera del audio (si la hay) y lo demás en palabras, en `room` de ancho."""
    out, x = [], float(MARGIN)
    if hud.audio_flag:
        out += flags.ass(hud.audio_flag, x, 1022 - FLAG_H / 2, FLAG_H)
        x += FLAG_H * flags.W / flags.H + FLAG_GAP
    out.append(text(x, 1022, esc(fit(info_line(hud), 22, min(1200, room) - (x - MARGIN), "semi")), 22, MUTED, weight="semi", align=4))
    return out


BAR_Y = 930


def progress_bar(hud: Hud, y: float = BAR_Y) -> tuple[str, float | None]:
    """Barra partida por capítulos (huecos, como YouTube) y el punto que se mueve. Devuelve (ass, x del punto)."""
    x0, w, h = MARGIN, W - 2 * MARGIN, 8
    done = None
    if hud.duration and hud.position is not None:
        done = max(0.0, min(1.0, hud.position / hud.duration))
    marks = [c / hud.duration for c in hud.chapters[1:] if hud.duration and 0 < c < hud.duration]
    stops = [0.0, *marks, 1.0]
    out = []
    for a, b in zip(stops, stops[1:], strict=False):
        gap = 6 if b < 1 else 0
        left, width = x0 + w * a, w * (b - a) - gap
        if width <= 1:
            continue
        out.append(rrect(left, y, width, h, h / 2, TEXT, "C8"))  # pista: blanco tenue
        if done is not None and done > a:
            out.append(rrect(left, y, min(width, w * (done - a)), h, h / 2, TEXT))
    knob = None
    if done is not None:
        knob = x0 + w * done
        out.append(circle(knob, y + h / 2, 22, TEXT, "D0"))  # halo
        out.append(circle(knob, y + h / 2, 13, TEXT))
    if TOUCH:  # tocar la barra salta a ese punto (una franja alta: el dedo no atina a 8 px)
        targets["hud"].append((x0, y - 28, w, h + 56, ("seek", x0, w)))
    return "\n".join(out), knob


def _times(hud: Hud, y: float) -> str:
    remaining = (hud.duration - hud.position) if hud.duration and hud.position is not None else None
    right = f"−{clock(remaining)}" if remaining is not None else clock(hud.duration)  # solo lo que falta, sin «termina a las…»
    return "\n".join([text(MARGIN, y, clock(hud.position), 26, weight="semi"),
                      text(W - MARGIN, y, esc(right), 26, MUTED, align=9)])


def chapter_at(hud: Hud) -> str:
    """«Capítulo 3 · El agua de la vida» (o solo «Capítulo 3» si el nombre es genérico)."""
    if not hud.chapter_titles or hud.position is None:
        return ""
    index = max((i for i, start in enumerate(hud.chapters) if start <= hud.position), default=-1)
    if not 0 <= index < len(hud.chapter_titles):
        return ""
    name = (hud.chapter_titles[index] or "").strip()
    generic = not name or name.lower().startswith(("chapter", "capítulo", "capitulo")) or name.isdigit()
    return f"Capítulo {index + 1}" + ("" if generic else f" · {name}")


def hud_ass(hud: Hud) -> str:
    """Lo que se ve al tocar un botón (reproduciendo), en pausa o adelantando."""
    targets["hud"] = []
    if hud.paused and not hud.seeking:
        return paused_ass(hud)
    lines = [gradient(700, H, 255, 34, 20)]  # 20 pasos: dentro de SHADE_BUDGET a 4K; sin título, el velo empieza más abajo
    bar, knob = progress_bar(hud)
    if hud.seeking:  # adelantando: solo la barra y, sobre el punto, a dónde vas
        center = max(MARGIN + 220, min(W - MARGIN - 220, knob if knob is not None else W / 2))
        when = clock(hud.position)
        when_w = text_width(when, 44, "bold")
        chip_w = text_width(hud.seeking, 22, "semi") + 28
        left = center - (when_w + 14 + chip_w) / 2
        lines += [text(left, BAR_Y - 84, when, 44, weight="bold", align=4),
                  glass(left + when_w + 14, BAR_Y - 103, chip_w, 38, 19),
                  text(left + when_w + 28, BAR_Y - 84, esc(hud.seeking), 22, weight="semi", align=4)]
        chapter = chapter_at(hud)
        if chapter:
            lines.append(text(center, BAR_Y - 30, esc(fit(chapter, 22, 600, "semi")), 22, SOFT, weight="semi", align=2))
        lines += [bar, _times(hud, BAR_Y + 28),
                  hints([("◀ ▶", "Mantén: más rápido"), ("A", "Pausa")], 1022, right=W - MARGIN)]
        return "\n".join(lines)
    lines.append(gradient(0, 200, 100, 255, 14))
    if hud.now:
        lines.append(text(W - MARGIN, 56, esc(hud.now), 34, weight="semi", align=9))
    if hud.pip:
        lines.append(hints([("Home", "Ver en pequeño")], 56, left=MARGIN))
    # Reproduciendo, sin título ni «Película»: eso (y la sinopsis) es de la pausa. Solo la barra; abajo a la izquierda
    # el idioma, los subtítulos y la versión (en el mismo lugar que en pausa) y a la derecha los botones (también ◀▶ y
    # RT, que antes solo se descubrían en pausa). Si no caben (4:3), se quitan primero los de menos uso.
    # A primero, como en todo Orbital; luego lo que se descubre (◀▶, LT/RT) y B al final.
    items = [("A", "Pausa"), ("X", "Audio y subtítulos"), *([] if hud.clip else [("Y", "Episodios y versión" if hud.series else "Versión")]),
             ("◀ ▶", "Adelantar"), *([("RT", "Siguiente episodio")] if hud.next else []), ("B", "Mantén: salir")]
    while len(items) > 4 and hints_width(items) > W - 2 * MARGIN:
        items.pop(-2)  # si no caben (4:3): primero RT, luego ◀▶
    bottom = _touch_bar(hud, 1000, paused=False) if TOUCH else hints(items, 1022, right=W - MARGIN)
    lines += [bar, _times(hud, BAR_Y + 28)]
    room = W - 2 * MARGIN - (pills_width(_touch_items(hud, paused=False)) if TOUCH else hints_width(items)) - 48
    if room >= 260:  # si no cabe la línea de audio, se quita (está en X)
        lines += info_ass(hud, room)
    lines.append(bottom)
    return "\n".join(lines)


def paused_ass(hud: Hud) -> str:
    """En pausa: el video se oscurece y a la izquierda, lo esencial y los botones."""
    targets["hud"] = []
    placed.pop("logo", None)
    # Más oscuro que antes (88) y con la sombra que entra desde la izquierda, donde va el título: el video se ve, pero
    # el logo y el texto descansan sobre negro, como el arte de la ficha.
    # Pocas capas (SHADE_BUDGET): cada una es una figura casi del tamaño de la pantalla y, a 4K, libass no alcanzaba a
    # pintar las ~75 de antes: no salía nada de la pausa, solo la imagen del logo encima (lo que vio Fernando en la TV).
    lines = [rrect(0, 0, W, H, 0, SHADE, "70"), side_gradient(W * .62, 90, steps=8), gradient(420, H, 255, 60, 12),
             gradient(0, 200, 140, 255, 8)]
    if hud.now:
        lines.append(text(W - MARGIN, 56, esc(hud.now), 34, weight="semi", align=9))
    if hud.pip:
        lines.append(hints([("Home", "Ver en pequeño")], 56, left=MARGIN))
    # El bloque va abajo, apoyado sobre la barra (como en las TV), no a media pantalla: se mide primero
    # y se coloca para que los botones queden justo encima de la barra de progreso.
    width = min(1180, W - 2 * MARGIN)
    # Con logo, el título va estilizado (la imagen la pone mpv encima, en `placed`); sin él, su nombre en texto.
    title_lines = [] if hud.logo else wrap(hud.title, 64, width, 2)
    title_h = hud.logo[1] + 28 if hud.logo else 92 * len(title_lines)
    # En una serie, lo que ves es el episodio: va en su propio renglón, en blanco y más grande, bajo el logo; la línea de datos
    # queda con lo de la serie (PA-2, 2 nov 2026: «T13 E22 · Papá tiene una placa nueva» iba perdido en la línea gris).
    episode = hud.detail if hud.series and hud.detail else ""
    meta = hud.facts if episode else " · ".join(p for p in (hud.detail, hud.facts) if p)
    about = wrap_sentences(hud.description, 26, min(1000, width), 3)
    # Bajo «En pausa», aire: con logo, una línea más (pegados, el ícono de pausa y el logo se leían como una sola pieza).
    after_pause = 78 if hud.logo else 54
    height = after_pause + title_h + (60 if episode else 0) + (52 if meta else 0) + 40 * len(about) + 30 + 62
    y = max(110, BAR_Y - 56 - height)
    # «‖ En pausa»: el ícono dibujado (dos barras) y la palabra, sin mayúsculas.
    lines += [rrect(MARGIN, y + 5, 6, 22, 2, TEXT), rrect(MARGIN + 12, y + 5, 6, 22, 2, TEXT),
              text(MARGIN + 30, y, "En pausa", 26, weight="semi")]
    y += after_pause
    if hud.logo:
        placed["logo"] = (MARGIN, y - 10, *hud.logo)
        y += title_h
    for line in title_lines:
        lines.append(text(MARGIN, y, esc(line), 64, weight="bold"))
        y += 92
    if episode:
        lines.append(text(MARGIN, y, esc(fit(episode, 36, width, "semi")), 36, weight="semi"))
        y += 60
    if meta:
        lines.append(text(MARGIN, y + 4, esc(fit(meta, 26, min(1300, width))), 26, SOFT))
        y += 52
    for line in about:
        lines.append(text(MARGIN, y + 4, esc(line), 26, SOFT))
        y += 40
    y += 30
    lines.append(buttons([("A", "Continuar"), ("X", "Audio y subtítulos"),
                          *([] if hud.clip else [("Y", "Episodios y versión" if hud.series else "Versión")])], MARGIN, y))
    bar, _ = progress_bar(hud)
    # «Probar subtítulos» a la vista (regla de las cuatro superficies): mantener X con el mando, S con el teclado y, con el
    # dedo o el mouse, su botón abajo.
    subs = ("S", "Probar subtítulos") if KEYBOARD else ("X", "Mantén: probar subtítulos")
    # Un toque de RT pasa al siguiente (con aviso: B lo cancela); solo se dice si hay siguiente.
    more = [("◀ ▶", "Adelantar"), ("↑ ↓", "Volumen"), subs, *([("RT", "Siguiente episodio")] if hud.next else []),
            ("B", "Mantén: salir")]
    room = max(260, W - 2 * MARGIN - hints_width(more) - 48)
    if TOUCH:
        room = max(260, W - 2 * MARGIN - pills_width(_touch_items(hud, paused=True)) - 48)
    bottom = _touch_bar(hud, 1000, paused=True) if TOUCH else hints(more, 1022, right=W - MARGIN)
    lines += [bar, _times(hud, BAR_Y + 28)]
    if room >= 260:  # si no cabe la línea de audio, se quita (está en X)
        lines += info_ass(hud, room)
    lines.append(bottom)
    return "\n".join(lines)


def buttons(items: list[tuple[str, str]], x: float, y: float, *, layer: str = "hud") -> str:
    """Botones como los de Orbital: cápsulas; el primero en blanco (lo que hace A), los demás de vidrio. Con el dedo, sin
    el glifo del mando y más altos; cada uno anota su lugar (su acción: la tecla, «a», «x», «y»)."""
    out = []
    for i, (key, label) in enumerate(items):
        primary = i == 0
        h = 76 if TOUCH else 62
        # El glifo se mide de verdad: con teclado «Espacio» es mucho más ancho que el círculo del mando y se
        # encimaba sobre «Continuar».
        shape, gw = ("", 0.0) if TOUCH else glyph(x + 16, y + 31, key, 30, solid=primary)
        lead = 26 if TOUCH else 16 + gw + 12
        w = lead + text_width(label, 24, "semi") + 26
        out.append(rrect(x, y, w, h, h / 2, TEXT) if primary
                   else glass(x, y, w, h, h / 2))
        if shape:
            out.append(shape)
        out.append(text(x + lead, y + h / 2, esc(label), 24, ON_LIGHT if primary else TEXT, weight="semi", align=4))
        if TOUCH:
            targets[layer].append((x, y, w, h, key.lower()))
        x += w + 16
    return "\n".join(out)


def pills(items: Sequence[tuple[str, object]], y: float, *, right: float | None = None, left: float | None = None,
          center: float | None = None, layer: str = "hud", h: float = 72) -> str:
    """Con el dedo: una fila de botones tocables («−10 s», «+10 s», «Salir»…), anotados en `layer`."""
    if not items:
        return ""
    gap, size = 16, 24
    widths = [text_width(label, size, "semi") + 56 for label, _ in items]
    total = sum(widths) + gap * (len(items) - 1)
    x = (right - total) if right is not None else (center - total / 2) if center is not None else (left if left is not None else MARGIN)
    out = []
    for (label, action), w in zip(items, widths, strict=True):
        out.append(glass(x, y, w, h, h / 2))
        out.append(text(x + w / 2, y + h / 2, esc(label), size, weight="semi", align=5))
        targets[layer].append((x, y, w, h, action))
        x += w + gap
    return "\n".join(out)


def _touch_items(hud: Hud, *, paused: bool) -> list[tuple[str, object]]:
    """En pausa, Continuar, Audio y Episodios ya son botones grandes del bloque: abajo regresar, adelantar, el
    siguiente episodio (si hay; lo mismo que RT) y salir."""
    if paused:
        return [("−10 s", "left"), ("+10 s", "right"), *([(f"⏭ Siguiente · {hud.next}", "next")] if hud.next else []),
                ("Probar subtítulos", "subs"), ("Salir", "quit")]
    return [("−10 s", "left"), ("Pausa", "a"), ("+10 s", "right"), ("Volumen", "volume"), ("Audio y subtítulos", "x"),
            *([] if hud.clip else [("Episodios y versión" if hud.series else "Versión", "y")]), ("Salir", "quit")]


def pills_width(items: Sequence[tuple[str, object]], gap: float = 16, size: int = 24) -> float:
    return sum(text_width(label, size, "semi") + 56 for label, _ in items) + gap * max(0, len(items) - 1)


def _touch_bar(hud: Hud, y: float, *, paused: bool) -> str:
    """Abajo, con el dedo: regresar, pausa, adelantar, audio y subtítulos, más, y salir (sin mantener B). Va a la derecha,
    junto a la línea de audio y subtítulos (al centro se encimaba sobre ella)."""
    return pills(_touch_items(hud, paused=paused), y, right=W - MARGIN, h=66)


# --- panel de columnas (X: Audio · Subtítulos · Tamaño; Y: Episodios · Versión) ------------------------------------
@dataclass
class Column:
    key: str  # "audio" | "sub" | "size" | "episodes" | "source" | "playback"
    options: list[dict] = field(default_factory=list)  # {"label", "action", "current", "hint"?, "progress"?}
    index: int = 0
    top: int = 0  # primera fila a la vista: la lista solo se desplaza cuando el foco llega al borde
    cell: int = 0  # en una cuadrícula (Versión: un renglón por idioma), la casilla enfocada del renglón
    pages: list[dict] = field(default_factory=list)  # Episodios: una por temporada, {"label": "T5", "options": […]}
    page: int = 0  # la temporada a la vista (LB/RB)

    def turn(self, step: int) -> bool:
        """Episodios: LB/RB, otra temporada (en la que estás viendo, el foco va al que ves). False si no hay más."""
        if not 0 <= self.page + step < len(self.pages):
            return False
        self.page += step
        self.options = self.pages[self.page]["options"]
        self.index = next((i for i, o in enumerate(self.options) if o.get("current")), 0)
        self.top = 0
        return True

    @property
    def grid(self) -> bool:
        """Cada opción es un renglón con casillas (Versión: idioma × calidad); ◀ ▶ recorre las casillas."""
        return bool(self.options) and "cells" in self.options[0]

    @property
    def chosen(self) -> dict | None:
        """Lo que elige A: la opción enfocada o, en una cuadrícula, su casilla enfocada."""
        if not self.options:
            return None
        option = self.options[self.index]
        if not self.grid:
            return option
        cells = option["cells"]
        return cells[min(self.cell, len(cells) - 1)] if cells else None


@dataclass
class Panel:
    kind: str  # "tracks" (X) | "more" (Y)
    columns: list[Column] = field(default_factory=list)
    col: int = 0  # columna enfocada

    @property
    def column(self) -> Column:
        return self.columns[self.col]

    @property
    def options(self) -> list[dict]:  # la columna enfocada (para quien solo mira una lista)
        return self.column.options

    @property
    def index(self) -> int:
        return self.column.index

    def find(self, key: str) -> Column | None:
        return next((c for c in self.columns if c.key == key), None)


TAB_NAMES = {"audio": "Audio", "sub": "Subtítulos", "size": "Tamaño de los subtítulos", "sync": "Sincronía", "episodes": "Episodios",
             "source": "Versión", "playback": "Reproducción", "category": "Categoría", "channels": "Canales",
             "seek": "Adelantar", "volume": "Volumen", "episode": "Episodio"}
PANEL_ROWS = 6  # filas visibles por columna; el resto se desplaza con el foco
# Dónde empieza el panel (X, Y): 40 más arriba que antes, que la sexta fila terminaba en 998 y la fila de abajo (botones,
# la nota de Versión, «Cerrar» con el dedo desde 986) empezaba ahí mismo: se encimaban (visto en la TV el 2026-10-29).
PANEL_TOP = 520
PANEL_INSET = 36  # el vidrio del panel sale esto de sus columnas (y queda separado de las orillas: «Menú flotante»)
PANEL_BOTTOM = 976  # donde acaba el vidrio: las filas terminan en 958 y abajo van las pistas (1022) o «Cerrar» (986)
ROWS_TOP = PANEL_TOP + 84  # la primera fila de cada columna
ROWS_BOTTOM = ROWS_TOP + PANEL_ROWS * 60 - 6  # lo más abajo que llega una fila (958)


def panel_ass(panel: Panel, *, playing: bool = True, muted: bool = False) -> str:
    """Panel abajo, de vidrio fuerte (receta «Menú flotante»): el video sigue arriba. La opción enfocada, clara; la puesta,
    con ✓."""
    # Un velo corto que oscurece lo de abajo (para que las pistas del pie se lean sobre cualquier escena) y, encima, el panel
    # de vidrio separado de las orillas. Pocas figuras grandes: SHADE_BUDGET.
    targets["panel"] = []
    lines = [gradient(PANEL_TOP - 160, PANEL_TOP + 40, 255, 110, 10), rrect(0, PANEL_TOP + 40, W, H - PANEL_TOP - 40, 0, SHADE, "6E"),
             glass(MARGIN - PANEL_INSET, PANEL_TOP - 16, W - 2 * (MARGIN - PANEL_INSET), PANEL_BOTTOM - PANEL_TOP + 16, RADIUS_CARD,
                   "glass-strong")]
    if playing or muted:
        label = " · ".join(p for p in ("Sigue reproduciendo" if playing else "", "sin sonido" if muted else "") if p)
        label = label[:1].upper() + label[1:]
        lines += [glass(MARGIN, 64, text_width(label, 22, "semi") + 70, 46, 23),
                  _shape(f"m {MARGIN + 24} 77 l {MARGIN + 38} 87 l {MARGIN + 24} 97", TEXT),
                  text(MARGIN + 50, 87, label, 22, weight="semi", align=4)]
    n = len(panel.columns)
    # Fuentes y Episodios más anchas (el detalle de cada fuente, el nombre de cada episodio); Reproducción, la de siempre. La
    # cuadrícula de versiones, la que más: hasta cuatro calidades por idioma.
    weights = [2.0 if column.grid else {"source": 1.4, "episodes": 1.35, "playback": 1.0, "channels": 1.5, "category": .7}.get(column.key, 1.0)
               for column in panel.columns]
    unit = min(520, (W - 2 * MARGIN - 64 * (n - 1)) / max(1.0, sum(weights)))
    x, legend_below = MARGIN, []
    for c, column in enumerate(panel.columns):
        col_w = unit * weights[c]
        if c:
            x += unit * weights[c - 1] + 64
        active = c == panel.col
        name = TAB_NAMES.get(column.key, column.key)
        if column.pages:  # «Episodios · T5»: la temporada a la vista
            name += f" · {column.pages[column.page]['label']}"
        lines.append(text(x + 18, PANEL_TOP + 40, esc(name), 22, TEXT if active else MUTED, weight="semi"))
        if TOUCH:
            targets["panel"].append((x, PANEL_TOP + 20, col_w, 44, ("column", c)))
        if column.key in ICON_COLUMNS:  # Reproducción: cada renglón con su ícono y su texto entero (dos renglones si hace falta)
            lines += _icon_rows(column, c, x, col_w, active)
            continue
        # Antes la lista se recentraba en cada paso de la cruceta (todo brincaba); ahora solo se
        # desplaza cuando el foco sale de las filas a la vista.
        if column.index < column.top:
            column.top = column.index
        elif column.index >= column.top + PANEL_ROWS:
            column.top = column.index - PANEL_ROWS + 1
        column.top = first = max(0, min(column.top, len(column.options) - PANEL_ROWS))
        y = PANEL_TOP + 84  # filas de 54 cada 60: la sexta termina (958) bien antes de la fila de botones
        if not column.options:
            lines.append(text(x + 18, y + 27, "Nada que elegir aquí", 24, MUTED, align=4))
        if column.grid:
            lines += _grid_rows(column, c, x, y, col_w, active)
            name_w = text_width(name, 22, "semi") + 48
            counter = text_width("99 de 99", 20) + 24 if len(column.options) > PANEL_ROWS else 0
            legend = legend_items(column.options)
            if legend_width(legend) <= col_w - 36 - name_w - counter:  # en el encabezado si cabe entera; si no, abajo
                lines += states_legend(legend, x + 18 + name_w, PANEL_TOP + 40 + 15)
            else:
                legend_below = legend
        for i, option in enumerate([] if column.grid else column.options[first:first + PANEL_ROWS], start=first):
            focused = active and i == column.index
            current = bool(option.get("current"))
            if focused:
                lines.append(rrect(x, y, col_w, 54, 12, TEXT))
            if TOUCH:
                targets["panel"].append((x, y, col_w, 54, ("option", c, i)))
            color = ON_LIGHT if focused else (TEXT if current else SOFT)
            if current:
                lines.append(text(x + 18, y + 27, "✓", 24, color, weight="bold", align=4))
            hint = option.get("hint") or ""
            room = col_w - 70 - (text_width(hint, 20) + 20 if hint else 0)
            if hint and room < (col_w - 70) * .45:  # en 4:3 / 16:10 «720p» desaparecía bajo «MediaFusion · 900 MB…»
                room = (col_w - 70) * .45
                hint = fit(hint, 20, col_w - 70 - room - 20)
            weight = "semi" if focused or current else "regular"
            left = x + 52
            if option.get("flag"):  # la banderita del idioma, antes de su nombre (como en la interfaz)
                lines += flags.ass(option["flag"], left, y + 27 - FLAG_H / 2, FLAG_H)
                left += FLAG_H * flags.W / flags.H + FLAG_GAP
                room -= left - x - 52
            need = text_width(option["label"], 24, weight)
            if hint and need > room:  # el nombre primero: la pista suelta sus datos del final («En otra · 4K» → «En otra»)
                spare = col_w - 70 - (left - x - 52) - need - 20
                shorter = fit(hint, 20, spare) if spare > 0 else ""
                if shorter and not shorter.endswith("…"):
                    hint, room = shorter, col_w - 70 - (left - x - 52) - text_width(shorter, 20) - 20
            lines.append(text(left, y + 27, esc(fit(option["label"], 24, room, weight)), 24, color, weight=weight, align=4))
            if hint:
                tint = ON_LIGHT if focused else NEXT if option.get("accent") else MUTED
                lines.append(text(x + col_w - 18, y + 27, esc(hint), 20, tint, align=6))
            if option.get("progress"):
                bar_w = col_w - 70
                tint = ON_LIGHT if focused else TEXT
                lines += [rrect(x + 52, y + 47, bar_w, 4, 2, tint, "A0"),
                          rrect(x + 52, y + 47, max(4, bar_w * min(1, option["progress"])), 4, 2, tint)]
            y += 60
        if len(column.options) > PANEL_ROWS:  # en el encabezado, a la derecha: abajo se encimaba con la nota de Fuentes
            lines.append(text(x + col_w - 18, PANEL_TOP + 42, f"{column.index + 1} de {len(column.options)}", 20, MUTED, align=9))
    seasons = len(panel.column.pages) > 1  # Episodios con más de una temporada: LB/RB (o sus botones) la cambian
    turn = [("‹ Temporada", "lb"), ("Temporada ›", "rb")] if seasons else []
    keys = [("◀ ▶", "Columna"), ("A", "Elegir"), *([("LB RB", "Temporada")] if seasons else []), ("B", "Cerrar")]
    # Lo que queda a la izquierda de los botones de abajo (con el dedo, «‹ Temporada · Temporada › · Cerrar» miden más).
    note_room = W - 2 * MARGIN - 48 - (pills_width([*turn, ("Cerrar", "close")]) if TOUCH else hints_width(keys))
    while legend_below and legend_width(legend_below) > note_room:  # 4:3 con la letra más grande: lo de menos uso, fuera
        legend_below.pop()
    if panel.column.key == "source":  # la enfocada en palabras y qué quiere decir «Al instante», donde se elige
        note = "Al instante: Real-Debrid ya la tiene guardada y arranca en segundos. Las demás primero se descargan y pueden tardar."
        if panel.column.grid and panel.column.chosen:
            row, cell = panel.column.options[panel.column.index], panel.column.chosen
            said = " · ".join(p for p in (row["label"], cell["label"], cell["doubt"], cell["hint"], cell["size"],
                                          "la que ves" if cell.get("current") else "") if p)
            note = said if legend_below else f"{said}      Al instante: Real-Debrid ya la tiene y arranca en segundos"
        room = note_room - (legend_width(legend_below) + 40 if legend_below else 0)
        note = fit(note, 20, room) if room >= 160 else ""  # sin lugar (4:3, letra grande), la dice solo la casilla enfocada
        if note:
            lines.append(text(MARGIN, 1022, esc(note), 20, MUTED, align=4))
        if legend_below:
            lines += states_legend(legend_below, MARGIN + (text_width(note, 20) + 40 if note else 0), 1022)
    elif legend_below:
        lines += states_legend(legend_below, MARGIN, 1022)
    if TOUCH:
        lines.append(pills([*turn, ("Cerrar", "close")], 986, right=W - MARGIN, layer="panel"))
    else:
        lines.append(hints(keys, 1022, right=W - MARGIN))
    return "\n".join(lines)


ICON_COLUMNS = {"playback"}  # columnas de acciones: un ícono por renglón y el texto entero, en dos renglones si no cabe
ICON_SIZE = 30  # el ícono de un renglón (crece con el tamaño del texto)


def _icon_row_lines(option: dict, room: float) -> tuple[list[str], float]:
    """Los renglones del nombre de una acción (hasta tres, partidos entre palabras: nunca «…» a media palabra) y lo que mide
    su fila. La pista («Mismo minuto») va debajo, en chico: a la derecha le quitaba lugar al nombre."""
    words = str(option["label"]).split()
    label = wrap(option["label"], 24, room, 3)
    if " ".join(label) != " ".join(words):  # ni en tres renglones (no pasa con estos textos): una palabra por renglón
        label = [fit(w, 24, room, "semi") for w in words]
    step = 30 * _text_scale
    body = step * len(label) + (26 * _text_scale if option.get("hint") else 0)
    return label, max(54.0, body + 22)


def _icon_rows(column: Column, c: int, x: float, col_w: float, active: bool) -> list[str]:
    """Reproducción (Y): cada acción con su ícono y su nombre completo, como los renglones de un menú de Orbital. La fila
    crece si el nombre necesita dos renglones; se ven las que caben entre ROWS_TOP y ROWS_BOTTOM y el resto se desplaza con
    el foco (sin brincar: solo cuando el foco sale de las que se ven)."""
    lines: list[str] = []
    if not column.options:
        return [text(x + 18, ROWS_TOP + 27, "Nada que elegir aquí", 24, MUTED, align=4)]
    size = ICON_SIZE * _text_scale
    left = x + 18 + size + 14
    room = x + col_w - 18 - left
    rows = [_icon_row_lines(option, room) for option in column.options]
    budget = ROWS_BOTTOM - ROWS_TOP

    def fits(first: int, last: int) -> bool:  # ¿caben de `first` a `last` (incluidas)?
        return sum(h for _, h in rows[first:last + 1]) + 6 * (last - first) <= budget

    column.top = max(0, min(column.top, column.index))
    while column.top < column.index and not fits(column.top, column.index):
        column.top += 1
    y, shown = ROWS_TOP, 0
    for i in range(column.top, len(column.options)):
        option, (label, h) = column.options[i], rows[i]
        if i > column.top and y + h > ROWS_BOTTOM:
            break
        focused = active and i == column.index
        if focused:
            lines.append(rrect(x, y, col_w, h, 12, TEXT))
        if TOUCH:
            targets["panel"].append((x, y, col_w, h, ("option", c, i)))
        ink = ON_LIGHT if focused else TEXT if option.get("current") else SOFT
        weight = "semi" if focused or option.get("current") else "regular"
        hint = option.get("hint") or ""
        step = 30 * _text_scale
        top = y + (h - step * len(label) - (26 * _text_scale if hint else 0)) / 2
        lines.append(icon(option.get("icon") or "restart", x + 18 + size / 2, y + h / 2, size, ink))
        for n, part in enumerate(label):
            lines.append(text(left, top + step * (n + .5), esc(part), 24, ink, weight=weight, align=4))
        if hint:
            lines.append(text(left, top + step * len(label) + 13 * _text_scale, esc(fit(hint, 20, room)), 20,
                              ON_LIGHT if focused else MUTED, align=4))
        y += h + 6
        shown += 1
    if shown < len(column.options):  # no caben todas: cuál es la enfocada, en el encabezado (como las demás columnas)
        lines.append(text(x + col_w - 18, PANEL_TOP + 42, f"{column.index + 1} de {len(column.options)}", 20, MUTED, align=9))
    return lines


GRID_NAME = 215  # la banderita y el nombre del idioma («Castellano» entero), a la izquierda de sus casillas


# Lo que dice cada casilla de Versión, en íconos (como el iPhone, D10: íconos, no cápsulas de texto; Fernando, 6 nov: «solo se lee
# completo "Al instante"»). En palabras va abajo, en la nota de la enfocada, y el encabezado de la columna dice qué es cada uno.
CELL_STATES = (("Al instante", "bolt", LIVE), ("Hay que bajarla", "cloud-down", MUTED), ("Idioma dudoso", "doubt", NEXT))
CELL_ICON = 22  # los íconos de una casilla (crecen con el tamaño del texto)


def cell_states(cell: dict) -> list[tuple[str, str, str]]:
    """Lo que dice una casilla (de `CELL_STATES`): primero qué tan rápido arranca y luego si su idioma es dudoso."""
    said = {cell.get("hint"), cell.get("doubt")}
    return [state for state in CELL_STATES if state[0] in said]


def legend_items(grid: list[dict]) -> list[tuple[str, str, str]]:
    """Los íconos de `CELL_STATES` que aparecen en la cuadrícula (la leyenda solo explica lo que se ve)."""
    present = {s[0] for row in grid for cell in row.get("cells", []) for s in cell_states(cell)}
    return [s for s in CELL_STATES if s[0] in present]


def legend_width(items: list[tuple[str, str, str]]) -> float:
    size = CELL_ICON * _text_scale
    return sum(size + 8 + text_width(name, 20) for name, _, _ in items) + 24 * max(0, len(items) - 1)


def states_legend(items: list[tuple[str, str, str]], x: float, cy: float) -> list[str]:
    """«⚡ Al instante  ☁ Hay que bajarla  ? Idioma dudoso»: cada ícono con su nombre (nunca un ícono sin él)."""
    size, out = CELL_ICON * _text_scale, []
    for name, shape, color in items:
        out.append(icon(shape, x + size / 2, cy, size, color))
        out.append(text(x + size + 8, cy, esc(name), 20, MUTED, align=4))
        x += size + 8 + text_width(name, 20) + 24
    return out


def _grid_rows(column: Column, c: int, x: float, y: float, col_w: float, active: bool) -> list[str]:
    """La cuadrícula de Versión (como «Versión» de la ficha): un renglón por idioma, su nombre a la izquierda y
    sus calidades en casillas de vidrio («1080p» y debajo sus íconos: ⚡ al instante, la nube si hay que bajarla, «?» si el
    idioma es dudoso); la enfocada, clara; la que ves, con contorno."""
    lines = []
    # Hasta cuatro calidades (4K, 1080p, 720p, SD), pero solo el lugar de las que hay: con dos, cada casilla mide el doble. En
    # una columna angosta (4:3), el nombre del idioma cede un poco antes que las casillas.
    slots = max(1, min(4, max((len(row["cells"]) for row in column.options), default=1)))
    name_w = min(GRID_NAME, col_w * .34)
    width = min((col_w - name_w - 10 * (slots - 1)) / slots, (col_w - GRID_NAME - 30) / 2)
    size = CELL_ICON * _text_scale
    for i, row in enumerate(column.options[column.top:column.top + PANEL_ROWS], start=column.top):
        here = active and i == column.index
        left = x + 18
        if row.get("flag"):
            lines += flags.ass(row["flag"], left, y + 27 - FLAG_H / 2, FLAG_H)
            left += FLAG_H * flags.W / flags.H + FLAG_GAP
        weight, name_size, room = "semi" if here else "regular", 24, name_w - 8 - (left - x)
        while name_size > 19 and text_width(row["label"], name_size, weight) > room:  # se achica antes de cortarse
            name_size -= 1
        lines.append(text(left, y + 27, esc(fit(row["label"], name_size, room, weight)), name_size,
                          TEXT if here or any(cell.get("current") for cell in row["cells"]) else SOFT, weight=weight, align=4))
        cx = x + name_w
        for j, cell in enumerate(row["cells"][:4]):
            focused = here and j == min(column.cell, len(row["cells"]) - 1)
            if focused:
                lines.append(rrect(cx, y, width, 54, 12, TEXT))
            else:
                lines.append(glass(cx, y, width, 54, 12, edge="glass-hairline"))  # la casilla: un control de vidrio
            if cell.get("current"):
                lines.append(rrect(cx, y, width, 54, 12, TEXT, "FF", outline=TEXT if not focused else ON_LIGHT, width=2))
            if TOUCH:
                targets["panel"].append((cx, y, width, 54, ("cell", c, i, j)))
            ink = ON_LIGHT if focused else TEXT
            label_size = 21  # «4K HDR» en una casilla angosta (16:10, letra grande): se achica antes de cortarse
            while label_size > 16 and text_width(cell["label"], label_size, "semi") > width - 24:
                label_size -= 1
            lines.append(text(cx + 12, y + 17, esc(fit(cell["label"], label_size, width - 24, "semi")), label_size, ink,
                              weight="semi", align=4))
            ix = cx + 12
            for _name, shape, color in cell_states(cell):
                lines.append(icon(shape, ix + size / 2, y + 40, size, ON_LIGHT if focused else color))
                ix += size + 6
            cx += width + 10
        y += 60
    return lines


SUB_SCALES = [(.85, "Pequeño"), (1.0, "Normal"), (1.25, "Grande"), (1.5, "Muy grande")]


def sub_scale_label(scale: float) -> str:
    return next((name for value, name in SUB_SCALES if abs(value - scale) < .01), "Normal")


def track_options(kind: str, tracks: list[dict], extra: list[dict] | None = None) -> list[dict]:
    """Opciones de una columna de pistas (y "Sin subtítulos" / buscar en tu addon)."""
    options = [o for o in extra or [] if o.get("first")]  # «Probar otros · mantén X»: arriba, donde se ve
    extra = [o for o in extra or [] if not o.get("first")]
    if kind == "sub":
        none_selected = not any(t.get("type") == "sub" and t.get("selected") for t in tracks)
        options.append({"label": "Sin subtítulos", "action": ("sid", "no"), "current": none_selected})
    for t in tracks:
        if t.get("type") == kind:
            options.append({"label": track_label(t), "action": ("aid" if kind == "audio" else "sid", t["id"]),
                            "current": bool(t.get("selected")), "lang": t.get("lang"),
                            "flag": flags.flag_for(t.get("lang"), str(t.get("title") or ""))})
    return options + (extra or [])


def _column(key: str, options: list[dict]) -> Column:
    return Column(key, options, next((i for i, o in enumerate(options) if o.get("current")), 0))


SUB_STEP = .5  # s por paso de «Sincronía»


def delay_label(delay: float) -> str:
    """«A tiempo», «0,5 s antes», «1,0 s después» (negativo: los subtítulos salen antes)."""
    if abs(delay) < .05:
        return "A tiempo"
    return f"{abs(delay):.1f} s {'antes' if delay < 0 else 'después'}".replace(".", ",")


def sync_options(delay: float) -> list[dict]:
    """Sincronía de los subtítulos (como el iPhone): Antes · A tiempo (o «+1.0 s») · Después, de medio segundo en medio
    segundo. La de en medio vuelve a cero."""
    middle = "A tiempo" if abs(delay) < .05 else f"{delay:+.1f} s".replace(".", ",")
    return [{"label": "Antes", "hint": "−0,5 s", "action": ("subdelay", -SUB_STEP), "current": False},
            {"label": middle, "hint": "" if abs(delay) < .05 else "Volver a cero", "action": ("subdelay", 0.0), "current": True},
            {"label": "Después", "hint": "+0,5 s", "action": ("subdelay", SUB_STEP), "current": False}]


def tracks_panel(tracks: list[dict], sub_scale: float, extra_subs: list[dict] | None = None, focus: str = "audio",
                 sub_delay: float = 0.0, versions: list[dict] | None = None) -> Panel:
    """X: Audio · Subtítulos · Tamaño · Sincronía de los subtítulos, en columnas (el video sigue). En Audio, después de
    las pistas de esta versión, tu idioma en otra («Latino · en otra versión  4K · al instante»): cambia de fuente
    y sigue donde ibas."""
    sizes = [{"label": name, "action": ("subscale", value), "current": abs(value - sub_scale) < .01}
             for value, name in SUB_SCALES]
    other = [{"label": v["label"], "hint": v.get("hint", ""), "action": ("source", v["id"]), "current": False,
              "flag": v.get("flag")} for v in versions or []]
    columns = [_column("audio", track_options("audio", tracks, other)), _column("sub", track_options("sub", tracks, extra_subs)),
               _column("size", sizes), _column("sync", sync_options(sub_delay))]
    return Panel("tracks", columns, next((i for i, c in enumerate(columns) if c.key == focus), 0))


def more_panel(*, episodes: list[dict] | None = None, sources: list[dict] | None = None,
               back_to: float | None = None, iphone: bool = False, channel: bool = False) -> Panel:
    """Y: Episodios (series) · Versión · Reproducción (Desde el principio / Volver a… y, con un iPhone conectado, mandarlo o
    descargarlo allá). El iPhone va dentro de Reproducción: como cuarta columna todo se cortaba («2…», «Desde el prin…»)."""
    columns = []
    # Episodios primero (en una serie es lo que más se busca), luego Versión y Reproducción.
    if episodes:
        columns.append(episodes_column(episodes))
    if sources and "cells" in sources[0]:  # idioma × calidad: empieza en la que ves (o en la primera, la recomendada)
        rows = [{"label": r["label"], "flag": r.get("flag"), "cells": [{**cell, "action": ("source", cell["id"])} for cell in r["cells"]]}
                for r in sources if r.get("cells")]
        at = next(((i, j) for i, r in enumerate(rows) for j, cell in enumerate(r["cells"]) if cell.get("current")), (0, 0))
        if rows:
            columns.append(Column("source", rows, at[0], cell=at[1]))
    elif sources:
        columns.append(_column("source", [{"label": s["label"], "hint": s.get("hint", ""), "action": ("source", s["id"]),
                                           "current": bool(s.get("current"))} for s in sources]))
    if channel:  # un canal de Orbital: salirte del canal y quedarte en este episodio, o seguirlo en el iPhone
        playback = [{"label": "Seguir solo este capítulo", "hint": "Sale del canal", "action": ("detach", None), "current": False,
                     "icon": "episode"}]
        if iphone:
            playback.append({"label": "Seguir en el iPhone", "hint": "Mismo minuto", "action": ("iphone", "continue"), "current": False,
                             "icon": "phone-play"})
        columns.append(Column("playback", playback))
        return Panel("more", columns, 0)
    playback = [{"label": "Desde el principio", "action": ("restart", None), "current": False, "icon": "restart"}]
    if back_to:  # empezaste desde el principio sin querer: volver a donde ibas
        playback.insert(0, {"label": f"Volver a {clock(back_to)}", "action": ("resume-at", back_to), "current": False, "icon": "resume"})
    if iphone:  # lo que ves: seguir en el iPhone en el mismo minuto, mandarlo (desde donde ibas) o descargarlo allá
        playback += [{"label": "Seguir en el iPhone", "hint": "Mismo minuto", "action": ("iphone", "continue"), "current": False,
                      "icon": "phone-play"},
                     {"label": "Enviar al iPhone", "action": ("iphone", "open"), "current": False, "icon": "phone-send"},
                     {"label": "Descargar en el iPhone", "action": ("iphone", "download"), "current": False, "icon": "phone-down"}]
    columns.append(Column("playback", playback))
    return Panel("more", columns, 0)


def episodes_column(episodes: list[dict]) -> Column:
    """Y › Episodios: una página por temporada (`season` de cada episodio; LB/RB las cambia), empezando en la que ves.
    El que ves dice «Viendo»; el que sigue, «Siguiente» (en ámbar)."""
    pages: list[dict] = []
    for e in episodes:
        season = e.get("season")
        label = "" if season is None else "Especiales" if season == 0 else f"T{season}"
        if not pages or pages[-1]["label"] != label:
            pages.append({"label": label, "options": []})
        hint = "Viendo" if e.get("current") else "Siguiente" if e.get("next") else e.get("hint", "")
        pages[-1]["options"].append({"label": e["label"], "action": ("episode", e["id"]), "current": bool(e.get("current")),
                                     "hint": hint, "accent": bool(e.get("next")) and not e.get("current"),
                                     "progress": e.get("progress")})
    page = next((i for i, p in enumerate(pages) if any(o["current"] for o in p["options"])), 0)
    column = _column("episodes", pages[page]["options"])
    if len(pages) > 1 or pages[0]["label"]:
        column.pages, column.page = pages, page
    return column


# --- «Probar otros» subtítulos: una franja arriba (los subtítulos y el video se siguen viendo abajo) ---------------
@dataclass
class SubTrial:
    language: str  # «Español»
    number: int  # el que está puesto (1…total); 0 = ahora sin subtítulos
    total: int
    origin: str = "video"  # «video» | «addon» (de internet)
    delay: float = 0.0  # la sincronía (s)
    status: str = ""  # «Bajando el subtítulo…», «De vuelta al primero», «Sin internet…»
    flag: str | None = None  # la banderita del idioma (flags.py)
    badge: str = ""  # «Hecho para tu copia» · «Misma versión» (library/subtitles.badge)
    release: str = ""  # la copia para la que se hizo («The.Office.S02E05.720p.WEB-DL-NTb»)
    downloads: int | None = None
    languages: int = 1  # cuántos idiomas hay (con más de uno, LB/RB los cambia)
    edition: bool = False  # parece de otra edición del video: Y ajusta la velocidad
    edition_on: bool = False


TRY_H = 166  # alto de la franja con el mando (con el dedo, TRY_TOUCH_H: sus botones se tocan)
TRY_TOUCH_H = 190
TRY_ROWS = (46, 92, 132)  # los tres renglones (título, la copia, los botones): con aire entre ellos, no encimados


def try_items(trial: SubTrial) -> list[tuple[str, str]]:
    """Las pistas del mando (o del teclado: hints() pone la tecla) de la franja."""
    return [("◀ ▶", "Otro"), *([("LB RB", "Idioma")] if trial.languages > 1 else []), ("↑ ↓", "Sincronía"),
            *([("Y", "Velocidad como venía" if trial.edition_on else "Ajustar velocidad")] if trial.edition else []),
            ("A", "Este va bien"), ("B", "Listo")]


def try_pills(trial: SubTrial) -> list[tuple[str, str]]:
    """Con el dedo o el mouse: los mismos, como botones (la rueda del mouse también cambia de subtítulo)."""
    return [("‹ Anterior", "left"), ("Siguiente ›", "right"), *([("Otro idioma", "rb")] if trial.languages > 1 else []),
            ("Antes", "up"), ("Después", "down"),
            *([("Velocidad", "y")] if trial.edition else []), ("Este va bien", "a"), ("Listo", "done")]


def _downloads(n: int | None) -> str:
    """«12 400 descargas» (con espacio de miles, como se escribe en México en la TV)."""
    if not isinstance(n, int) or n <= 0:
        return ""
    return f"{n:,} descarga{'s' if n != 1 else ''}".replace(",", " ")


def sub_trial_ass(trial: SubTrial) -> str:
    """La franja de «Probar otros», arriba (así se lee la frase de abajo con cada subtítulo): la bandera y «Español ·
    Subtítulo 2 de 5», por qué está ahí («Hecho para tu copia»), la copia, las descargas y la sincronía; abajo, los botones
    del mando o, con el dedo y el mouse, botones tocables."""
    targets["try"] = []
    h = TRY_TOUCH_H if TOUCH else TRY_H
    top, info, keys = TRY_ROWS
    lines = [glass(0, 0, W, h, 0, "glass-strong", None), gradient(h, h + 48, 160, 255, 8)]
    if trial.total <= 0:
        title = f"{trial.language} · No hay subtítulos para probar"
    elif trial.number <= 0:
        title = f"{trial.language} · Ahora sin subtítulos · {trial.total} para probar"
    else:
        title = f"{trial.language} · Subtítulo {trial.number} de {trial.total}"
    x = MARGIN
    if trial.flag:
        lines += flags.ass(trial.flag, x, top - FLAG_H / 2, FLAG_H)
        x += FLAG_H * flags.W / flags.H + FLAG_GAP
    status_w = min(text_width(trial.status, 22, "semi"), (W - 2 * MARGIN) * .36) if trial.status else 0
    room = W - MARGIN - x - status_w - 48
    lines.append(text(x, top, esc(fit(title, 28, room, "bold")), 28, weight="bold", align=4))
    x += min(text_width(title, 28, "bold"), room) + 28
    if trial.badge and trial.number > 0:  # por qué está ahí, en su píldora (el turquesa de «al aire»: es lo bueno)
        bw, bh = text_width(trial.badge, 19, "semi") + 32, 34
        if x + bw < W - MARGIN - status_w - 48:
            lines += [rrect(x, top - bh / 2, bw, bh, bh / 2, LIVE, "C8", outline=LIVE, width=1.5),
                      text(x + bw / 2, top, esc(trial.badge), 19, LIVE, weight="semi", align=5)]
    if trial.status:
        lines.append(text(W - MARGIN, top, esc(fit(trial.status, 22, status_w + 1, "semi")), 22, SOFT, weight="semi", align=6))
    # Segundo renglón: de dónde viene, la copia para la que se hizo y sus descargas; la sincronía va a la derecha (es lo
    # que mueves con ↑ ↓, y así el nombre largo de la copia no la empuja fuera).
    origin = "Del video" if trial.origin == "video" else ""
    parts = [p for p in (origin, trial.release, _downloads(trial.downloads)) if p] if trial.number > 0 else []
    sync = f"Sincronía: {delay_label(trial.delay)}"
    lines.append(text(W - MARGIN, info, esc(sync), 21, SOFT if abs(trial.delay) >= .05 else MUTED, weight="semi", align=6))
    if parts:
        room = W - 2 * MARGIN - text_width(sync, 21, "semi") - 48
        lines.append(text(MARGIN, info, esc(fit(" · ".join(parts), 21, room, "semi")), 21, MUTED, weight="semi", align=4))
    if TOUCH:
        lines.append(pills(try_pills(trial), keys - 10, left=MARGIN, layer="try", h=48))
    else:
        lines.append(hints(try_items(trial), keys, left=MARGIN, size=20))
    return "\n".join(lines)


# --- TV en vivo: la barra del canal y la guía de canales (Y) --------------------------------------------
@dataclass
class LiveHud:
    name: str
    number: int | None = None  # el «12» del canal (no cambia aunque otro canal se oculte)
    category: str = ""
    quality: str = ""  # «1080p»
    status: str = "live"  # live | tuning | nosignal
    muted: bool = False
    now: str = ""


# Qué dice y de qué color es cada estado del canal.
LIVE_STATUS = {"live": ("En vivo", LIVE), "tuning": ("Sintonizando…", MUTED), "nosignal": ("Sin señal", GLYPH["B"])}


def live_info_line(hud: LiveHud) -> str:
    """«Noticias · 1080p» (el silencio no va aquí: lo dice la píldora fija de muted_ass)."""
    return "  ·  ".join(p for p in (hud.category, hud.quality) if p)


def live_hud_ass(hud: LiveHud) -> str:
    """La barra del canal, abajo a la izquierda: su número en un bloque claro, el nombre y, debajo, el estado,
    la categoría y la calidad. Sin barra de avance (en vivo no hay a dónde adelantar) y con los botones de la TV."""
    targets["hud"] = []
    lines = [gradient(560, H, 255, 34, 20), gradient(0, 200, 100, 255, 14)]
    if hud.now:
        lines.append(text(W - MARGIN, 56, esc(hud.now), 34, weight="semi", align=9))
    number = str(hud.number) if hud.number else "—"
    block = max(112, text_width(number, 56, "bold") + 52)
    top = 786
    x = MARGIN + block + 28
    room = W - x - MARGIN
    label, color = LIVE_STATUS.get(hud.status, LIVE_STATUS["live"])
    lines += [rrect(MARGIN, top, block, 100, 22, TEXT), text(MARGIN + block / 2, top + 50, esc(number), 56, ON_LIGHT, weight="bold", align=5),
              text(x, top - 2, esc(fit(hud.name, 52, min(room, 1300), "bold")), 52, weight="bold"),
              circle(x + 9, top + 78, 7, color), text(x + 28, top + 78, esc(label), 24, color, weight="semi", align=4)]
    info = live_info_line(hud)
    if info:
        lines.append(text(x + 28 + text_width(label, 24, "semi") + 22, top + 78, esc(fit(info, 24, max(200, room - 280), "semi")), 24, MUTED,
                          weight="semi", align=4))
    items = [("↑ ↓", "Canal"), ("Y", "Canales"), ("X", "Audio"), ("◀ ▶", "Volumen"), ("A", "Silencio"), ("B", "Mantén: salir")]
    while len(items) > 3 and hints_width(items) > W - 2 * MARGIN:
        items.pop(-2)  # si no caben (4:3): primero A, luego ◀▶
    if TOUCH:  # con el dedo: botones que se tocan (la acción, la de la tecla)
        lines.append(pills([("Canal −", "down"), ("Canal +", "up"), ("Canales", "y"), ("Audio", "x"),
                            ("Silencio", "a"), ("Salir", "quit")], 940, center=W / 2, h=66))
    else:
        lines.append(hints(items, 1022, right=W - MARGIN))
    return "\n".join(lines)


def muted_ass() -> str:
    """«Sin sonido»: una píldora arriba a la izquierda que se queda mientras el canal está en silencio. La barra del canal
    se va sola a los pocos segundos y, sin esto, nadie se acuerda de que silenció."""
    label = "Sin sonido"
    x, y = MARGIN, 52
    w = text_width(label, 24, "semi") + 98
    speaker = _shape(f"m {x + 24} {y + 20} l {x + 32} {y + 20} l {x + 42} {y + 11} l {x + 42} {y + 43} "
                     f"l {x + 32} {y + 34} l {x + 24} {y + 34}", TEXT)
    slash = _shape(f"m {x + 20} {y + 40} l {x + 23} {y + 43} l {x + 49} {y + 14} l {x + 46} {y + 11}", TEXT)
    return "\n".join([glass(x, y, w, 54, 27, "glass-strong"), speaker, slash, text(x + 62, y + 27, esc(label), 24, weight="semi", align=4)])


def channels_panel(categories: list[dict], channels: list[dict], *, focus: str = "channels") -> Panel:
    """Y en la TV: Categoría | Canales. `categories`: {"id", "label", "current"}; `channels`: {"id", "name", "number",
    "category", "current"}. El canal que ves, marcado; elegir una categoría cambia la lista de al lado."""
    rows = [{"label": c["label"], "hint": c.get("hint", ""), "action": ("category", c["id"]), "current": bool(c.get("current"))}
            for c in categories]
    # Un canal que ya falló una vez lo dice donde se elige (en vez de su categoría): así no sorprende que no abra.
    picks = [{"label": " · ".join(str(p) for p in (c.get("number"), c["name"]) if p),
              "hint": "Sin señal reciente" if c.get("shaky") else c.get("category", ""),
              "action": ("channel", c["id"]), "current": bool(c.get("current"))} for c in channels]
    columns = [_column("category", rows), _column("channels", picks)]
    return Panel("channels", columns, next((i for i, c in enumerate(columns) if c.key == focus), 1))


# --- tarjetas y avisos -------------------------------------------------------------------------------
CARD_RISE = 32  # lo que sube una tarjeta al entrar (aparece a la vez: PlayerScreen.CARD_IN)
STILL_BOX = (242, 136)  # el cuadro del episodio en «Siguiente episodio» (16:9), en el lienzo; la imagen la pone mpv encima


def ease_out(t: float) -> float:
    """Arranca rápido y se asienta despacio (la entrada de las tarjetas y el anillo que se vuelve «cargando»)."""
    t = max(0.0, min(1.0, t)) if math.isfinite(t) else 1.0
    return 1 - (1 - t) ** 3


def _entering(ass: str, appear: float) -> str:
    return ass if appear >= 1 else fade(ass, ease_out(appear))


def skip_ass(label: str, *, appear: float = 1.0) -> str:
    """«Saltar intro»: un botón claro abajo a la derecha (A); se va solo. `appear` (0 a 1): entra subiendo."""
    targets["card"] = []
    placed.pop("still", None)
    lift = (1 - ease_out(appear)) * CARD_RISE
    if TOUCH:
        w = text_width(label, 24, "bold") + 56
        x, y = W - MARGIN - w, 780 + lift
        targets["card"].append((x, y, w, 76, "a"))
        return _entering("\n".join([rrect(x, y, w, 76, 14, TEXT),
                                    text(x + w / 2, y + 38, esc(label), 24, ON_LIGHT, weight="bold", align=5)]), appear)
    gw = glyph(0, 0, "A", 30)[1]  # con teclado, «Espacio»: el botón crece con su glifo
    w = 16 + gw + 12 + text_width(label, 24, "bold") + 28
    x, y = W - MARGIN - w, 790 + lift
    shape, gw = glyph(x + 16, y + 32, "A", 30, solid=True)
    return _entering("\n".join([rrect(x, y, w, 64, 14, TEXT), shape,
                                text(x + 16 + gw + 12, y + 32, esc(label), 24, ON_LIGHT, weight="bold", align=4)]), appear)


def upnext_ass(title: str, eyebrow: str = "", *, seconds: int | None = None, progress: float | None = None,
               actions: list[tuple[str, str]] | None = None, spinner: tuple[float, float] | None = None,
               still: bool = False, appear: float = 1.0) -> str:
    """Tarjeta abajo a la derecha: «Siguiente episodio» con la cuenta atrás en un anillo, «¿Sigues viendo?» o, ya
    elegido, la misma tarjeta «Cargando…» con el anillo girando (`spinner`: (giro, largo del arco), en vueltas).

    `still`: a la izquierda, el lugar del cuadro del episodio (mpv pone la imagen encima, en `placed["still"]`); el anillo
    pasa a la derecha. `appear` (0 a 1): entra subiendo y apareciendo (PlayerScreen la mueve a 30 cuadros por segundo)."""
    targets["card"] = []
    circled = seconds is not None or spinner is not None
    # Sin renglón de arriba («¿Sigues viendo?» sin nombre del episodio), la tarjeta es más baja: antes quedaba un hueco.
    short = 0 if eyebrow or circled else 32
    still = still and not short
    w, h = (880 if still else 660), (206 if TOUCH else 176) - short
    x, y = W - MARGIN - w, 870 - h + (1 - ease_out(appear)) * CARD_RISE
    lines = [glass(x, y, w, h, RADIUS_CARD, "glass-strong")]
    tx, right = x + 32, x + w - 32
    if still:
        sw, sh = STILL_BOX
        sx, sy = x + 20, y + (h - sh) / 2
        lines.append(glass(sx, sy, sw, sh, 12, edge="glass-hairline"))  # el lugar del cuadro mientras llega (y si no llega)
        placed["still"] = (sx, sy, sw, sh)
        tx = sx + sw + 28
    else:
        placed.pop("still", None)
    if circled:
        r, thick = (44, 7) if still else (50, 8)
        cx, cy = (right - r, y + h / 2) if still else (x + 32 + r, y + h / 2)
        lines.append(ring(cx, cy, r, thick, 1.0, TEXT, "C8"))  # el riel del anillo (sin disco: se ve el vidrio)
        if spinner is not None:
            turn, length = spinner
            if length > .005:
                start = -90 + 360 * turn
                lines.append(arc(cx, cy, r - thick / 2, thick, start, start + 360 * min(1.0, length), TEXT))
        else:
            lines += [ring(cx, cy, r, thick, 1 if progress is None else progress, TEXT),
                      text(cx, cy, str(seconds), 30 if still else 34, weight="bold", align=5)]
        if still:
            right = cx - r - 24
        else:
            tx = x + 32 + 2 * r + 28
    room = right - tx
    if eyebrow:
        lines.append(text(tx, y + 30, esc(fit(eyebrow, 22, room, "semi")), 22, MUTED, weight="semi"))
    lines.append(text(tx, y + 62 - short, esc(fit(title, 30, room, "bold")), 30, weight="bold"))
    if TOUCH:  # botones que se tocan: «Seguir viendo», «Salir»… (la acción: la tecla que harían)
        touch = [(label.removeprefix("Mantén: ").capitalize(), key.lower()) for key, label in actions or []]
        lines.append(pills(touch, y + h - 84, left=tx, layer="card", h=64))
    else:
        lines.append(hints(actions or [], y + h - 40, left=tx))
    return _entering("\n".join(lines), appear)


# Los avisos van debajo de la hora (antes, a la misma altura, la tapaban: se leía «21:0» a través).
NOTICE_Y = 124  # avisos, volumen y «Salir»
BUFFER_Y = 196  # «Cargando… 40 %»: su propia altura, no borra el aviso que estaba


def lines_of(message: str) -> tuple[str, str]:
    """Título y detalle de un aviso, con la misma regla de la interfaz (toast.js · linesOf): sin punto final; se parte por el
    primer « · », si no por la primera frase y, si es largo, por «Algo: lo demás»."""
    def tidy(t: str) -> str:
        t = " ".join(str(t or "").split())
        return t[:-1] if t.endswith(".") and not t.endswith("..") else t
    text_ = tidy(message)
    if " · " in text_ and len(text_) > 48:
        title, rest = text_.split(" · ", 1)
        return title, tidy(rest)
    m = re.match(r"^(.{4,64}?(?:[.?!]|…))\s+(\S.*)$", text_)
    if m:
        rest = tidy(m.group(2))
        return tidy(m.group(1)), rest[:1].upper() + rest[1:]
    colon = text_.find(": ")
    if len(text_) > 48 and 0 < colon <= 48:
        rest = text_[colon + 2:]
        return text_[:colon], rest[:1].upper() + rest[1:]
    return text_, ""


def toast_ass(message: str, top: float = NOTICE_Y) -> str:
    """Aviso arriba a la derecha («Subtítulos: Español», «Cargando… 40 %»): una píldora; con detalle, dos renglones."""
    title, detail = lines_of(message)
    room = W - 2 * MARGIN - 44
    title = fit(title, 24, room, "semi")
    if not detail:
        w = text_width(title, 24, "semi") + 44
        x = W - MARGIN - w
        return "\n".join([glass(x, top, w, 54, 27, "glass-strong"), text(x + 22, top + 27, esc(title), 24, weight="semi", align=4)])
    detail = fit(detail, 20, room)
    w = max(text_width(title, 24, "semi"), text_width(detail, 20)) + 44
    x = W - MARGIN - w
    return "\n".join([glass(x, top, w, 84, 24, "glass-strong"), text(x + 22, top + 28, esc(title), 24, weight="semi", align=4),
                      text(x + 22, top + 58, esc(detail), 20, SOFT, align=4)])


def toast_seconds(message: str, seconds: float) -> float:
    """Lo que dura un aviso: lo pedido, pero nunca menos de lo que tarda en leerse (≈ 3,5 palabras por segundo, tope 6 s)."""
    return max(seconds, min(6.0, 1.2 + len(str(message).split()) / 3.5))


def quit_hold_ass(progress: float, key: str = "B", label: str = "Salir") -> str:
    """Un botón mantenido (B: salir; LT/RT: otro episodio): el botón arriba a la derecha con un anillo fino que se
    llena (y lo que hace al lado). Sin caja: discreto sobre el video."""
    progress = max(0.0, min(1.0, progress)) if math.isfinite(progress) else 0.0
    # Abajo a la derecha, cerca de donde la barra dice «B Mantén: salir» (antes arriba, lejos de su pista): justo encima de
    # la línea de tiempo, que ahí está vacío en pausa y reproduciendo (sobre la leyenda la tapaba).
    cx, cy, r = W - MARGIN - 30, H - 220, 30
    shape, gw = glyph(cx - (20 if len(key) == 1 else 26), cy, key, 40)
    return "\n".join([circle(cx, cy, r + 6, PANEL, "70", blur=6),
                      ring(cx, cy, r, 3, 1.0, TEXT, "C8"), ring(cx, cy, r, 3, progress, TEXT), shape,
                      text(cx - r - 16, cy, esc(label), 24, SOFT, weight="semi", align=6)])


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


def speaker(cx: float, cy: float, level: float, muted: bool = False, color: str = TEXT) -> str:
    """La bocina del volumen: el cuerpo y el cono, y de una a tres ondas según el nivel (con una ✕ si está en silencio)."""
    x = cx - 22
    body = _shape(f"m {x:.1f} {cy - 7:.1f} l {x + 8:.1f} {cy - 7:.1f} l {x + 19:.1f} {cy - 16:.1f} l {x + 19:.1f} {cy + 16:.1f} "
                  f"l {x + 8:.1f} {cy + 7:.1f} l {x:.1f} {cy + 7:.1f}", color)
    if muted:
        mx, my, d, t = x + 32, cy, 7, 1.7  # la ✕: dos trazos cruzados
        cross = (f"m {mx - d:.1f} {my - d + t:.1f} l {mx - d + t:.1f} {my - d:.1f} l {mx:.1f} {my - t:.1f} l {mx + d - t:.1f} {my - d:.1f} "
                 f"l {mx + d:.1f} {my - d + t:.1f} l {mx + t:.1f} {my:.1f} l {mx + d:.1f} {my + d - t:.1f} l {mx + d - t:.1f} {my + d:.1f} "
                 f"l {mx:.1f} {my + t:.1f} l {mx - d + t:.1f} {my + d:.1f} l {mx - d:.1f} {my + d - t:.1f} l {mx - t:.1f} {my:.1f}")
        return "\n".join([body, _shape(cross, color)])
    waves = 0 if level <= 0 else 1 if level < 34 else 2 if level < 67 else 3
    return "\n".join([body, *(arc(x + 19, cy, 9 + 7 * i, 3, -48, 48, color) for i in range(waves))])


EXTRA = ass_color(PALETTE["amber-300"])  # la zona «Extra» del volumen (--color-warning: más de lo normal, no un error)
VOLUME_TOP = 200  # playback.VOLUME_BOOST_MAX: el tope del Extra
VOLUME_NORMAL = 2 / 3  # dónde queda el 100 en el riel: lo de arriba es el Extra


def volume_ass(volume: float, muted: bool = False, touch: bool = False) -> str:
    """El volumen: una cápsula vertical en el borde derecho, a media altura (como en las TV): el nivel arriba, la barra
    que se llena de abajo arriba y la bocina abajo, con sus ondas según el nivel (o una ✕ en silencio: la barra se apaga).
    El 100 (el de Windows) queda a dos tercios con una rayita; arriba, el «Extra» hasta 200 en ámbar y la palabra EXTRA
    bajo el número (V1-C). Con el dedo, a su izquierda, + y − para tocarlos (V2-A).
    Arriba a la derecha van los avisos y antes se encimaban; abajo, la barra del video y los paneles."""
    targets["volume"] = []
    try:
        level = max(0.0, min(float(VOLUME_TOP), float(volume)))  # pasado 100, el Extra (playback.extra_filter)
    except (TypeError, ValueError):
        level = 0.0
    if not math.isfinite(level):
        level = 0.0
    w, h = 84, 330
    x, y = W - MARGIN + 20 - w, BUFFER_Y + 80  # debajo de «Cargando…» y del anillo de «Salir»
    track_w, track_top, track_h = 14, y + 70, 170
    track_x = x + (w - track_w) / 2
    normal_h = track_h * VOLUME_NORMAL
    fill = 0 if muted else max(track_w, normal_h * min(level, 100) / 100)
    extra = 0 if muted or level <= 100 else (track_h - normal_h) * (level - 100) / (VOLUME_TOP - 100)
    number = "—" if muted else f"{int(level)}"
    parts = [glass(x, y, w, h, w / 2, "glass-strong"),  # la cápsula, de vidrio como los paneles
             text(x + w / 2, y + 34, number, 30, TEXT, weight="semi", align=5, alpha="70" if muted else "00"),
             rrect(track_x, track_top, track_w, track_h, track_w / 2, TEXT, "D0")]  # el riel
    if extra:
        parts.append(text(x + w / 2, y + 58, "EXTRA", 14, EXTRA, weight="semi", align=5))
    if fill:
        parts.append(rrect(track_x, track_top + track_h - fill, track_w, fill, track_w / 2, TEXT))
    if extra:  # el Extra, en ámbar, encima de lo normal
        parts.append(rrect(track_x, track_top + track_h - normal_h - extra, track_w, extra + track_w / 2, track_w / 2, EXTRA))
    mark_y = track_top + track_h - normal_h  # la rayita del 100: hasta aquí es lo normal
    parts.append(rrect(track_x - 7, mark_y - 1.5, track_w + 14, 3, 1.5, EXTRA, "40"))
    if touch:  # V2-A: + arriba y − abajo, a la izquierda de la cápsula
        for label, action, by in (("+", "up", y + 40), ("−", "down", y + h - 110)):
            bx, size = x - 92, 72
            parts.append(glass(bx, by, size, size, size / 2))
            parts.append(text(bx + size / 2, by + size / 2, label, 40, TEXT, weight="semi", align=5))
            targets["volume"].append((bx, by, size, size, action))
    parts.append(speaker(x + w / 2 + 4, y + h - 46, level, muted))
    return "\n".join(parts)


def _line_path(x1: float, y1: float, x2: float, y2: float, t: float) -> str:
    """Una línea gruesa (un rectángulo girado) de (x1, y1) a (x2, y2)."""
    dx, dy = x2 - x1, y2 - y1
    length = math.hypot(dx, dy) or 1.0
    nx, ny = -dy / length * t / 2, dx / length * t / 2
    return (f"m {x1 + nx:.1f} {y1 + ny:.1f} l {x2 + nx:.1f} {y2 + ny:.1f} l {x2 - nx:.1f} {y2 - ny:.1f} "
            f"l {x1 - nx:.1f} {y1 - ny:.1f}")


PIP_BUTTON = 92  # radio de los botones de la esquina, en el lienzo (la ventana chica lo reduce a ~22 px)
PIP_PLAY = 132  # radio del botón del centro


def pip_ass(paused: bool) -> str:
    """El video en pequeño, como el PiP del iPhone: solo tres botones sobre un velo tenue. Arriba a la izquierda,
    volver a pantalla completa; arriba a la derecha, cerrar; al centro, pausa o reproducir. Nada de la barra completa
    del reproductor (en chiquito no se leía y no tenía sentido)."""
    targets["hud"] = []
    cx, cy = W / 2, H / 2
    corner = PIP_BUTTON + 64
    veil = rrect(0, 0, W, H, 0, PANEL, "B0")  # un velo tenue: el video se sigue viendo
    parts = [veil]
    # Volver a pantalla completa: las cuatro esquinas de un marco (el ícono de siempre).
    ex, ey, s, t = corner, corner, 34, 14
    parts.append(glass(ex - PIP_BUTTON, ey - PIP_BUTTON, 2 * PIP_BUTTON, 2 * PIP_BUTTON, PIP_BUTTON))
    for sx, sy in ((-1, -1), (1, -1), (-1, 1), (1, 1)):
        x0, y0 = ex + sx * s, ey + sy * s
        parts.append(_shape(_line_path(x0, y0, x0 - sx * 26, y0, t), TEXT))
        parts.append(_shape(_line_path(x0, y0, x0, y0 - sy * 26, t), TEXT))
    targets["hud"].append((ex - PIP_BUTTON, ey - PIP_BUTTON, 2 * PIP_BUTTON, 2 * PIP_BUTTON, "pip:expand"))
    # Cerrar: una ✕.
    qx, qy = W - corner, corner
    parts.append(glass(qx - PIP_BUTTON, qy - PIP_BUTTON, 2 * PIP_BUTTON, 2 * PIP_BUTTON, PIP_BUTTON))
    parts.append(_shape(_line_path(qx - 34, qy - 34, qx + 34, qy + 34, 14), TEXT))
    parts.append(_shape(_line_path(qx + 34, qy - 34, qx - 34, qy + 34, 14), TEXT))
    targets["hud"].append((qx - PIP_BUTTON, qy - PIP_BUTTON, 2 * PIP_BUTTON, 2 * PIP_BUTTON, "pip:close"))
    # Pausa / reproducir, al centro y más grande.
    parts.append(glass(cx - PIP_PLAY, cy - PIP_PLAY, 2 * PIP_PLAY, 2 * PIP_PLAY, PIP_PLAY))
    if paused:
        parts.append(_shape(f"m {cx - 38:.1f} {cy - 62:.1f} l {cx + 66:.1f} {cy:.1f} l {cx - 38:.1f} {cy + 62:.1f}", TEXT))
    else:
        parts.append(rrect(cx - 52, cy - 60, 34, 120, 8, TEXT))
        parts.append(rrect(cx + 18, cy - 60, 34, 120, 8, TEXT))
    targets["hud"].append((cx - PIP_PLAY, cy - PIP_PLAY, 2 * PIP_PLAY, 2 * PIP_PLAY, "pip:play"))
    return "\n".join(parts)


def curtain_ass(opacity: float) -> str:
    """Un negro de pantalla completa con esa opacidad (1 = tapa todo, 0 = transparente): el fundido de entrada del video."""
    alpha = max(0, min(255, round((1 - opacity) * 255)))
    return f"{{\\an7\\pos(0,0)\\bord0\\shad0\\1c&H000000&\\1a&H{alpha:02X}&\\p1}}m 0 0 l {W} 0 {W} {H} 0 {H}{{\\p0}}"


def seek_label(seconds: int) -> str:
    """"+10 s", "−30 s", "+1 min": lo que avanza cada toque (crece si mantienes)."""
    sign = "+" if seconds >= 0 else "−"
    s = abs(int(seconds))
    return f"{sign}{s // 60} min" if s >= 60 and s % 60 == 0 else f"{sign}{s} s"
