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

Piezas reutilizables (todas aquí): rrect, circle, ring, gradient, glyph, hints, text, wrap.
"""

from __future__ import annotations

import json
import math
import time
from dataclasses import dataclass, field
from pathlib import Path

W, H = 1920, 1080  # coordenadas del lienzo: 1080 de alto y lo ancho que dé la pantalla (ver set_canvas)
MARGIN = 96


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

LANGUAGES = {
    "en": "Inglés", "eng": "Inglés", "es": "Español", "spa": "Español", "es-419": "Español latino",
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


def track_label(track: dict) -> str:
    """'Inglés · 5.1 · E-AC3' / 'Español · Forzados' / 'Pista 3'."""
    parts = [language(track.get("lang"))]
    title = (track.get("title") or "").strip()
    lowered = title.lower()
    if track.get("forced") or "forced" in lowered or "forzad" in lowered:
        parts.append("Forzados")
    elif "sdh" in lowered or "cc" == lowered:
        parts.append("Para sordos")
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


# --- piezas de dibujo (reutilizables) ------------------------------------------------------------
def _shape(path: str, color: str, alpha: str = "00", *, outline: str | None = None, width: float = 0,
           fill_alpha: str | None = None, blur: float = 0) -> str:
    """Una figura ASS (coordenadas absolutas del lienzo). `outline`: además, un borde de ese color."""
    fill = f"\\1c{color}\\1a&H{fill_alpha or alpha}&"
    border = f"\\3c{outline}\\3a&H00&\\bord{width:g}" if outline else "\\bord0"
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


def text(x: float, y: float, value: str, size: int, color: str = TEXT, *, weight: str = "regular", align: int = 7,
         alpha: str = "00") -> str:
    """Texto ya escapado (o con etiquetas). weight: regular | semi | bold."""
    font = FONT_SEMI if weight == "semi" else FONT
    bold = 1 if weight == "bold" else 0
    return (f"{{\\an{align}\\pos({x:.0f},{y:.0f})\\fn{font}\\fs{round(size * FS)}\\b{bold}\\bord0\\shad0\\q2"
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
    return w * size * (1.05 if weight != "regular" else 1)


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


def fit(value: str, size: int, width: float, weight: str = "regular") -> str:
    """Una sola línea que cabe en `width` (termina en «…»)."""
    value = str(value)
    if text_width(value, size, weight) <= width:
        return value
    while value and text_width(value + "…", size, weight) > width:
        value = value[:-1]
    return value.rstrip(" ,.;:·") + "…"


def glyph(x: float, cy: float, label: str, size: int = 34) -> tuple[str, float]:
    """Botón del mando dibujado (círculo, o píldora si son dos) en su color. Devuelve (ass, ancho)."""
    color = GLYPH.get(label, TEXT)
    w = size if len(label) == 1 else max(size, text_width(label, int(size * .44), "bold") + size * .6)
    parts = [rrect(x, cy - size / 2, w, size, size / 2, PANEL, "40", outline=color, width=2),
             text(x + w / 2, cy, esc(label), int(size * .44), color, weight="bold", align=5)]
    return "\n".join(parts), w


def hints_width(items: list[tuple[str, str]], size: int = 22) -> float:
    """Lo que mide una fila de pistas (para que el texto de al lado no se encime)."""
    return sum(glyph(0, 0, k)[1] + 12 + text_width(v, size, "semi") for k, v in items) + 36 * max(0, len(items) - 1)


def hints(items: list[tuple[str, str]], y: float, *, right: float | None = None, left: float | None = None,
          size: int = 22) -> str:
    """Pistas «A Pausa  X Audio y subtítulos…» en una fila, alineadas a la derecha o a la izquierda."""
    if not items:
        return ""
    gap, inner = 36, 12
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
    ends: str = ""  # "23:40": a qué hora termina (como en las TV)
    now: str = ""  # la hora, arriba a la derecha
    facts: str = ""  # "2024 · ★ 8.5 · Ciencia ficción" (en pausa)
    description: str = ""  # sinopsis (en pausa)
    seeking: str = ""  # "+10 s" / "−1 min" mientras adelantas: solo la barra y la burbuja


def info_line(hud: Hud) -> str:
    """«Inglés · Subtítulos en español · 1080p · Torrentio»."""
    if hud.subtitles and hud.subtitles not in ("No", "—"):
        subs = f"Subtítulos en {hud.subtitles.lower()}"
    else:
        subs = "Sin subtítulos"
    return "  ·  ".join(p for p in (hud.audio if hud.audio != "—" else "", subs, hud.source) if p)


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
    return "\n".join(out), knob


def _times(hud: Hud, y: float) -> str:
    remaining = (hud.duration - hud.position) if hud.duration and hud.position is not None else None
    right = f"−{clock(remaining)}" if remaining is not None else clock(hud.duration)
    if hud.ends and not hud.seeking:
        right += f"  ·  termina a las {hud.ends}"
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
    if hud.paused and not hud.seeking:
        return paused_ass(hud)
    lines = [gradient(470, H, 255, 34)]
    bar, knob = progress_bar(hud)
    if hud.seeking:  # adelantando: solo la barra y, sobre el punto, a dónde vas
        center = max(MARGIN + 220, min(W - MARGIN - 220, knob if knob is not None else W / 2))
        when = clock(hud.position)
        when_w = text_width(when, 44, "bold")
        chip_w = text_width(hud.seeking, 22, "semi") + 28
        left = center - (when_w + 14 + chip_w) / 2
        lines += [text(left, BAR_Y - 84, when, 44, weight="bold", align=4),
                  rrect(left + when_w + 14, BAR_Y - 103, chip_w, 38, 19, PANEL, "40"),
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
    if hud.detail:
        lines.append(text(MARGIN, 772, esc(fit(hud.detail, 24, min(1300, W - 2 * MARGIN), "semi")), 24, SOFT, weight="semi"))
    lines.append(text(MARGIN, 806, esc(fit(hud.title, 48, min(1500, W - 2 * MARGIN), "bold")), 48, weight="bold"))
    # Audio, subtítulos y fuente van bajo el título; abajo, todos los botones (también ◀▶ y LT/RT, que antes
    # solo se descubrían en pausa). Si no caben (4:3), se quitan primero los de menos uso.
    lines.append(text(MARGIN, 878, esc(fit(info_line(hud), 22, min(1300, W - 2 * MARGIN), "semi")), 22, MUTED, weight="semi"))
    # A primero, como en todo Orbital; luego lo que se descubre (◀▶, LT/RT) y B al final.
    items = [("A", "Pausa"), ("X", "Audio y subtítulos"), ("Y", "Episodios" if hud.series else "Fuentes"),
             ("◀ ▶", "Adelantar"), *([("LT RT", "Episodio")] if hud.series else []), ("B", "Mantén: salir")]
    while len(items) > 4 and hints_width(items) > W - 2 * MARGIN:
        items.pop(-2)  # si no caben (4:3): primero LT/RT, luego ◀▶
    lines += [bar, _times(hud, BAR_Y + 28), hints(items, 1022, right=W - MARGIN)]
    return "\n".join(lines)


def paused_ass(hud: Hud) -> str:
    """En pausa: el video se oscurece y a la izquierda, lo esencial y los botones."""
    lines = [rrect(0, 0, W, H, 0, SHADE, "88"), gradient(420, H, 255, 70), gradient(0, 200, 140, 255, 14)]
    if hud.now:
        lines.append(text(W - MARGIN, 56, esc(hud.now), 34, weight="semi", align=9))
    # El bloque va abajo, apoyado sobre la barra (como en las TV), no a media pantalla: se mide primero
    # y se coloca para que los botones queden justo encima de la barra de progreso.
    width = min(1180, W - 2 * MARGIN)
    title_lines = wrap(hud.title, 64, width, 2)
    meta = " · ".join(p for p in (hud.detail, hud.facts) if p)
    about = wrap(hud.description, 26, min(1000, width), 3)
    height = 54 + 92 * len(title_lines) + (52 if meta else 0) + 40 * len(about) + 30 + 62
    y = max(110, BAR_Y - 56 - height)
    # «‖ En pausa»: el ícono dibujado (dos barras) y la palabra, sin mayúsculas.
    lines += [rrect(MARGIN, y + 5, 6, 22, 2, TEXT), rrect(MARGIN + 12, y + 5, 6, 22, 2, TEXT),
              text(MARGIN + 30, y, "En pausa", 26, weight="semi")]
    y += 54
    for line in title_lines:
        lines.append(text(MARGIN, y, esc(line), 64, weight="bold"))
        y += 92
    if meta:
        lines.append(text(MARGIN, y + 4, esc(fit(meta, 26, min(1300, width))), 26, SOFT))
        y += 52
    for line in about:
        lines.append(text(MARGIN, y + 4, esc(line), 26, SOFT))
        y += 40
    y += 30
    lines.append(buttons([("A", "Continuar"), ("X", "Audio y subtítulos"), ("Y", "Episodios" if hud.series else "Fuentes")], MARGIN, y))
    bar, _ = progress_bar(hud)
    more = [("◀ ▶", "Adelantar"), ("↑ ↓", "Volumen"), *([("LT RT", "Episodio")] if hud.series else []),
            ("B", "Mantén: salir")]
    room = max(260, W - 2 * MARGIN - hints_width(more) - 48)
    lines += [bar, _times(hud, BAR_Y + 28),
              text(MARGIN, 1022, esc(fit(info_line(hud), 22, min(1200, room), "semi")), 22, MUTED, weight="semi", align=4),
              hints(more, 1022, right=W - MARGIN)]
    return "\n".join(lines)


def buttons(items: list[tuple[str, str]], x: float, y: float) -> str:
    """Botones como los de Orbital: el primero claro (lo que hace A), los demás tenues."""
    out = []
    for i, (key, label) in enumerate(items):
        primary = i == 0
        w = 16 + 30 + 12 + text_width(label, 24, "semi") + 26
        out.append(rrect(x, y, w, 62, 14, TEXT, "00" if primary else "D4"))
        shape, gw = glyph(x + 16, y + 31, key, 30)
        out.append(shape)
        out.append(text(x + 16 + gw + 12, y + 31, esc(label), 24, ON_LIGHT if primary else TEXT, weight="semi", align=4))
        x += w + 16
    return "\n".join(out)


# --- panel de columnas (X: Audio · Subtítulos · Tamaño; Y: Fuentes · Episodios) ------------------------------------
@dataclass
class Column:
    key: str  # "audio" | "sub" | "size" | "episodes" | "source" | "playback"
    options: list[dict] = field(default_factory=list)  # {"label", "action", "current", "hint"?, "progress"?}
    index: int = 0
    top: int = 0  # primera fila a la vista: la lista solo se desplaza cuando el foco llega al borde


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


TAB_NAMES = {"audio": "Audio", "sub": "Subtítulos", "size": "Tamaño de los subtítulos", "episodes": "Episodios",
             "source": "Fuentes", "playback": "Reproducción", "category": "Categoría", "channels": "Canales"}
PANEL_ROWS = 6  # filas visibles por columna; el resto se desplaza con el foco


def panel_ass(panel: Panel, *, playing: bool = True) -> str:
    """Panel abajo, sobre un velo: el video sigue arriba. La opción enfocada, clara; la puesta, con ✓."""
    # Una superficie sólida (como las hojas de Orbital) para leer sobre cualquier escena, con una
    # transición corta arriba; el video sigue visible encima.
    lines = [gradient(440, 560, 255, 40, 16), rrect(0, 560, W, H - 560, 0, PANEL, "28")]
    if playing:
        label = "Sigue reproduciendo"
        lines += [rrect(MARGIN, 64, text_width(label, 22, "semi") + 70, 46, 23, PANEL, "40"),
                  _shape(f"m {MARGIN + 24} 77 l {MARGIN + 38} 87 l {MARGIN + 24} 97", TEXT),
                  text(MARGIN + 50, 87, label, 22, weight="semi", align=4)]
    n = len(panel.columns)
    # Fuentes y Episodios más anchas (el detalle de cada fuente, el nombre de cada episodio); Reproducción, angosta.
    weights = [{"source": 1.4, "episodes": 1.35, "playback": .75, "channels": 1.5, "category": .7}.get(column.key, 1.0)
               for column in panel.columns]
    unit = min(520, (W - 2 * MARGIN - 64 * (n - 1)) / max(1.0, sum(weights)))
    x = MARGIN
    for c, column in enumerate(panel.columns):
        col_w = unit * weights[c]
        if c:
            x += unit * weights[c - 1] + 64
        active = c == panel.col
        lines.append(text(x + 18, 600, esc(TAB_NAMES.get(column.key, column.key)), 22, TEXT if active else MUTED,
                          weight="semi"))
        # Antes la lista se recentraba en cada paso de la cruceta (todo brincaba); ahora solo se
        # desplaza cuando el foco sale de las filas a la vista.
        if column.index < column.top:
            column.top = column.index
        elif column.index >= column.top + PANEL_ROWS:
            column.top = column.index - PANEL_ROWS + 1
        column.top = first = max(0, min(column.top, len(column.options) - PANEL_ROWS))
        y = 644  # filas de 54 cada 60: la sexta termina antes de la fila de botones (en 16:10 se encimaban)
        if not column.options:
            lines.append(text(x + 18, y + 27, "Nada que elegir aquí", 24, MUTED, align=4))
        for i, option in enumerate(column.options[first:first + PANEL_ROWS], start=first):
            focused = active and i == column.index
            current = bool(option.get("current"))
            if focused:
                lines.append(rrect(x, y, col_w, 54, 12, TEXT))
            color = ON_LIGHT if focused else (TEXT if current else SOFT)
            if current:
                lines.append(text(x + 18, y + 27, "✓", 24, color, weight="bold", align=4))
            hint = option.get("hint") or ""
            room = col_w - 70 - (text_width(hint, 20) + 20 if hint else 0)
            weight = "semi" if focused or current else "regular"
            lines.append(text(x + 52, y + 27, esc(fit(option["label"], 24, room, weight)), 24, color, weight=weight, align=4))
            if hint:
                lines.append(text(x + col_w - 18, y + 27, esc(hint), 20, ON_LIGHT if focused else MUTED, align=6))
            if option.get("progress"):
                bar_w = col_w - 70
                tint = ON_LIGHT if focused else TEXT
                lines += [rrect(x + 52, y + 47, bar_w, 4, 2, tint, "A0"),
                          rrect(x + 52, y + 47, max(4, bar_w * min(1, option["progress"])), 4, 2, tint)]
            y += 60
        if len(column.options) > PANEL_ROWS:
            lines.append(text(x + 18, y + 8, f"{column.index + 1} de {len(column.options)}", 20, MUTED))
    if panel.column.key == "source":  # qué quiere decir «Al instante», donde se elige
        lines.append(text(MARGIN, 1022, "Al instante: Real-Debrid ya la tiene guardada y arranca en segundos. "
                                        "Las demás primero se descargan y pueden tardar.", 20, MUTED, align=4))
    lines.append(hints([("◀ ▶", "Columna"), ("A", "Elegir"), ("B", "Cerrar")], 1022, right=W - MARGIN))
    return "\n".join(lines)


SUB_SCALES = [(.85, "Pequeño"), (1.0, "Normal"), (1.25, "Grande"), (1.5, "Muy grande")]


def sub_scale_label(scale: float) -> str:
    return next((name for value, name in SUB_SCALES if abs(value - scale) < .01), "Normal")


def track_options(kind: str, tracks: list[dict], extra: list[dict] | None = None) -> list[dict]:
    """Opciones de una columna de pistas (y "Sin subtítulos" / buscar en tu addon)."""
    options = []
    if kind == "sub":
        none_selected = not any(t.get("type") == "sub" and t.get("selected") for t in tracks)
        options.append({"label": "Sin subtítulos", "action": ("sid", "no"), "current": none_selected})
    for t in tracks:
        if t.get("type") == kind:
            options.append({"label": track_label(t), "action": ("aid" if kind == "audio" else "sid", t["id"]),
                            "current": bool(t.get("selected")), "lang": t.get("lang")})
    return options + (extra or [])


def _column(key: str, options: list[dict]) -> Column:
    return Column(key, options, next((i for i, o in enumerate(options) if o.get("current")), 0))


def tracks_panel(tracks: list[dict], sub_scale: float, extra_subs: list[dict] | None = None, focus: str = "audio") -> Panel:
    """X: Audio · Subtítulos · Tamaño de los subtítulos, en columnas (el video sigue)."""
    sizes = [{"label": name, "action": ("subscale", value), "current": abs(value - sub_scale) < .01}
             for value, name in SUB_SCALES]
    columns = [_column("audio", track_options("audio", tracks)), _column("sub", track_options("sub", tracks, extra_subs)),
               _column("size", sizes)]
    return Panel("tracks", columns, next((i for i, c in enumerate(columns) if c.key == focus), 0))


def more_panel(*, episodes: list[dict] | None = None, sources: list[dict] | None = None,
               back_to: float | None = None) -> Panel:
    """Y: Episodios (series) · Fuentes · Reproducción (Desde el principio / Volver a…)."""
    columns = []
    # Episodios primero (en una serie es lo que más se busca), luego Fuentes y Reproducción.
    if episodes:
        columns.append(_column("episodes", [
            {"label": e["label"], "action": ("episode", e["id"]), "current": bool(e.get("current")),
             "hint": "Viendo" if e.get("current") else e.get("hint", ""), "progress": e.get("progress")}
            for e in episodes]))
    if sources:
        columns.append(_column("source", [{"label": s["label"], "hint": s.get("hint", ""), "action": ("source", s["id"]),
                                           "current": bool(s.get("current"))} for s in sources]))
    playback = [{"label": "Desde el principio", "action": ("restart", None), "current": False}]
    if back_to:  # empezaste desde el principio sin querer: volver a donde ibas
        playback.insert(0, {"label": f"Volver a {clock(back_to)}", "action": ("resume-at", back_to), "current": False})
    columns.append(Column("playback", playback))
    return Panel("more", columns, 0)


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
LIVE_STATUS = {"live": ("En vivo", GLYPH["A"]), "tuning": ("Sintonizando…", MUTED), "nosignal": ("Sin señal", GLYPH["B"])}


def live_info_line(hud: LiveHud) -> str:
    """«Noticias · 1080p» (el silencio no va aquí: lo dice la píldora fija de muted_ass)."""
    return "  ·  ".join(p for p in (hud.category, hud.quality) if p)


def live_hud_ass(hud: LiveHud) -> str:
    """La barra del canal, abajo a la izquierda: su número en un bloque claro, el nombre y, debajo, el estado,
    la categoría y la calidad. Sin barra de avance (en vivo no hay a dónde adelantar) y con los botones de la TV."""
    lines = [gradient(560, H, 255, 34), gradient(0, 200, 100, 255, 14)]
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
    return "\n".join([rrect(x, y, w, 54, 27, PANEL, "30"), speaker, slash, text(x + 62, y + 27, esc(label), 24, weight="semi", align=4)])


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
def skip_ass(label: str) -> str:
    """«Saltar intro»: un botón claro abajo a la derecha (A); se va solo."""
    w = 16 + 30 + 12 + text_width(label, 24, "bold") + 28
    x, y = W - MARGIN - w, 790
    shape, gw = glyph(x + 16, y + 32, "A", 30)
    return "\n".join([rrect(x, y, w, 64, 14, TEXT), shape,
                      text(x + 16 + gw + 12, y + 32, esc(label), 24, ON_LIGHT, weight="bold", align=4)])


def upnext_ass(title: str, eyebrow: str = "", *, seconds: int | None = None, progress: float | None = None,
               actions: list[tuple[str, str]] | None = None) -> str:
    """Tarjeta abajo a la derecha: «Siguiente episodio» con la cuenta atrás en un anillo, o «¿Sigues viendo?»."""
    w, h = 660, 176
    x, y = W - MARGIN - w, 870 - h
    lines = [rrect(x, y, w, h, 20, PANEL, "18")]
    tx = x + 32
    if seconds is not None:
        cx, cy = x + 32 + 50, y + h / 2
        lines += [circle(cx, cy, 50, TEXT, "C8"), circle(cx, cy, 42, PANEL),
                  ring(cx, cy, 50, 8, 1 if progress is None else progress, TEXT),
                  text(cx, cy, str(seconds), 34, weight="bold", align=5)]
        tx = x + 32 + 100 + 28
    room = x + w - 32 - tx
    if eyebrow:
        lines.append(text(tx, y + 30, esc(fit(eyebrow, 22, room, "semi")), 22, MUTED, weight="semi"))
    lines.append(text(tx, y + 62, esc(fit(title, 30, room, "bold")), 30, weight="bold"))
    lines.append(hints(actions or [], y + h - 40, left=tx))
    return "\n".join(lines)


# Los avisos van debajo de la hora (antes, a la misma altura, la tapaban: se leía «21:0» a través).
NOTICE_Y = 124  # avisos, volumen y «Salir»
BUFFER_Y = 196  # «Cargando… 40 %»: su propia altura, no borra el aviso que estaba


def toast_ass(message: str, top: float = NOTICE_Y) -> str:
    """Aviso corto arriba a la derecha («Subtítulos: Español», «Cargando… 40 %»)."""
    message = fit(message, 24, W - 2 * MARGIN - 44, "semi")
    w = text_width(message, 24, "semi") + 44
    x = W - MARGIN - w
    return "\n".join([rrect(x, top, w, 54, 27, PANEL, "30"), text(x + 22, top + 27, esc(message), 24, weight="semi", align=4)])


def quit_hold_ass(progress: float) -> str:
    """B mantenido: el botón B arriba a la derecha con un anillo fino que se llena (y «Salir» al lado).
    Sin caja: discreto sobre el video."""
    progress = max(0.0, min(1.0, progress)) if math.isfinite(progress) else 0.0
    cx, cy, r = W - MARGIN - 30, BUFFER_Y + 28, 30  # debajo del aviso, no encima
    shape, gw = glyph(cx - 20, cy, "B", 40)
    return "\n".join([circle(cx, cy, r + 6, PANEL, "70", blur=6),
                      ring(cx, cy, r, 3, 1.0, TEXT, "C8"), ring(cx, cy, r, 3, progress, TEXT), shape,
                      text(cx - r - 16, cy, "Salir", 24, SOFT, weight="semi", align=6)])


def volume_ass(volume: float) -> str:
    """El volumen, con su barra (arriba a la derecha)."""
    try:
        level = max(0.0, min(100.0, float(volume)))
    except (TypeError, ValueError):
        level = 0.0
    if not math.isfinite(level):
        level = 0.0
    w = 360
    x = W - MARGIN - w
    bar_x, bar_w = x + 70, 210
    y = NOTICE_Y
    speaker = _shape(f"m {x + 24} {y + 20} l {x + 32} {y + 20} l {x + 42} {y + 11} l {x + 42} {y + 43} "
                     f"l {x + 32} {y + 34} l {x + 24} {y + 34}", TEXT)
    return "\n".join([rrect(x, y, w, 54, 27, PANEL, "30"), speaker,
                      rrect(bar_x, y + 23, bar_w, 8, 4, TEXT, "C0"), rrect(bar_x, y + 23, max(8, bar_w * level / 100), 8, 4, TEXT),
                      text(x + w - 22, y + 27, f"{int(level)}", 24, weight="semi", align=6)])


def ends_at(position: float | None, duration: float | None, now: float | None = None) -> str:
    """"23:40": la hora a la que termina si sigues viendo de corrido."""
    if not isinstance(duration, (int, float)) or not isinstance(position, (int, float)):
        return ""
    if not (math.isfinite(duration) and math.isfinite(position)):
        return ""
    if not duration or duration - position < 60 or duration - position > 86400 * 2:
        return ""
    return time.strftime("%H:%M", time.localtime((now if now is not None else time.time()) + duration - position))


def seek_label(seconds: int) -> str:
    """"+10 s", "−30 s", "+1 min": lo que avanza cada toque (crece si mantienes)."""
    sign = "+" if seconds >= 0 else "−"
    s = abs(int(seconds))
    return f"{sign}{s // 60} min" if s >= 60 and s % 60 == 0 else f"{sign}{s} s"
