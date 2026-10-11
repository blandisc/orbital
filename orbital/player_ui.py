"""Lo que se ve encima del video: la interfaz del reproductor de Orbital, dibujada en mpv.

mpv pinta texto y figuras ASS encima del video (comando osd-overlay). Aquí solo se arma ese texto
(funciones puras, con pruebas); player.py decide cuándo mostrarlo.

  * Barra inferior: título, en qué vas, progreso, idioma de audio y subtítulos, y la leyenda de
    qué hace cada botón del mando. Aparece al tocar cualquier botón y en pausa; se va sola.
  * Menú de Audio / Subtítulos (X / Y): las pistas del video con su idioma; ↑/↓ y A para elegir.
  * Aviso breve arriba a la derecha (volumen, "Subtítulos: Español"…).
"""

from __future__ import annotations

from dataclasses import dataclass, field

W, H = 1920, 1080  # coordenadas del lienzo (mpv escala a la pantalla)
MARGIN = 96

# Colores ASS (&HBBGGRR&) con la paleta de Orbital.
TEXT = "&HF0F4F5&"
MUTED = "&HA9B0B3&"
ACCENT = "&H4D57F0&"  # #F0574D
TRACK = "&H5A5A5A&"
GLYPH = {"A": "&H5BC86B&", "B": "&H4F4FE8&", "X": "&HE6A33C&", "Y": "&H2BC7F2&"}  # verde, rojo, azul, amarillo
FONT = "Segoe UI Variable Display"

LANGUAGES = {
    "en": "Inglés", "eng": "Inglés", "es": "Español", "spa": "Español", "es-419": "Español latino",
    "fr": "Francés", "fre": "Francés", "fra": "Francés", "it": "Italiano", "ita": "Italiano", "de": "Alemán",
    "ger": "Alemán", "deu": "Alemán", "pt": "Portugués", "por": "Portugués", "ja": "Japonés", "jpn": "Japonés",
    "ko": "Coreano", "kor": "Coreano", "zh": "Chino", "chi": "Chino", "zho": "Chino", "ru": "Ruso", "rus": "Ruso",
    "cs": "Checo", "cze": "Checo", "ces": "Checo", "pl": "Polaco", "pol": "Polaco", "hu": "Húngaro", "hun": "Húngaro",
    "tr": "Turco", "tur": "Turco", "ar": "Árabe", "ara": "Árabe", "hi": "Hindi", "hin": "Hindi", "nl": "Neerlandés",
    "dut": "Neerlandés", "nld": "Neerlandés", "sv": "Sueco", "swe": "Sueco", "uk": "Ucraniano", "ukr": "Ucraniano",
}


def esc(text: str) -> str:
    """Texto seguro para ASS (las llaves abren etiquetas)."""
    return str(text).replace("\\", "⧵").replace("{", "(").replace("}", ")").replace("\n", " ")


def clock(seconds: float | None) -> str:
    if seconds is None or seconds < 0:
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


@dataclass
class Hud:
    title: str
    detail: str = ""  # "T2 E3 · Nombre del episodio"
    position: float | None = None
    duration: float | None = None
    paused: bool = False
    audio: str = ""
    subtitles: str = ""


@dataclass
class Menu:
    kind: str  # "audio" | "sub"
    options: list[dict] = field(default_factory=list)  # {"label", "action", "current"}
    index: int = 0


def _rect(x: float, y: float, w: float, h: float, color: str, alpha: str = "00") -> str:
    return (f"{{\\an7\\pos(0,0)\\bord0\\shad0\\1c{color}\\1a&H{alpha}&\\p1}}"
            f"m {x:.0f} {y:.0f} l {x + w:.0f} {y:.0f} l {x + w:.0f} {y + h:.0f} l {x:.0f} {y + h:.0f}{{\\p0}}")


def _text(x: float, y: float, text: str, size: int, color: str = TEXT, *, bold: bool = False, align: int = 7,
          alpha: str = "00") -> str:
    return (f"{{\\an{align}\\pos({x:.0f},{y:.0f})\\fn{FONT}\\fs{size}\\b{1 if bold else 0}\\bord0\\shad0"
            f"\\1c{color}\\1a&H{alpha}&}}{text}")


def glyph(letter: str) -> str:
    """Botón del mando en su color (A verde, B rojo, X azul, Y amarillo); el resto en blanco."""
    color = GLYPH.get(letter, TEXT)
    return f"{{\\1c{color}\\b1}}{esc(letter)}{{\\1c{TEXT}\\b0}}"


LEGEND = [("A", "Pausa"), ("◀ ▶", "10 s"), ("LB RB", "1 min"), ("▲ ▼", "Volumen"),
          ("X", "Audio"), ("Y", "Subtítulos"), ("B", "Salir")]


def legend_line(items=LEGEND) -> str:
    return "      ".join(f"{glyph(k)}  {{\\1c{MUTED}}}{esc(v)}{{\\1c{TEXT}}}" for k, v in items)


def hud_ass(hud: Hud) -> str:
    """Barra inferior con todo lo que necesitas saber, sin tapar la película más de lo necesario."""
    lines = [
        # Degradado a negro en la base para que el texto se lea sobre cualquier escena.
        _rect(0, 700, W, 80, "&H000000&", "E0"),
        _rect(0, 780, W, 80, "&H000000&", "B0"),
        _rect(0, 860, W, 220, "&H000000&", "70"),
    ]
    y = 800
    if hud.paused:
        lines.append(_text(MARGIN, y - 44, "EN PAUSA", 26, ACCENT, bold=True))
    lines.append(_text(MARGIN, y, esc(hud.title), 52, bold=True))
    info = [hud.detail, f"Audio: {hud.audio}" if hud.audio else "", f"Subtítulos: {hud.subtitles}" if hud.subtitles else ""]
    lines.append(_text(MARGIN, y + 66, esc("   ·   ".join(i for i in info if i)), 28, MUTED))
    # Progreso
    bar_y, bar_w = 932, W - 2 * MARGIN
    lines.append(_rect(MARGIN, bar_y, bar_w, 6, TRACK, "40"))
    if hud.duration and hud.position is not None:
        done = max(0.0, min(1.0, hud.position / hud.duration))
        lines.append(_rect(MARGIN, bar_y, max(6, bar_w * done), 6, ACCENT))
        lines.append(_rect(MARGIN + bar_w * done - 8, bar_y - 5, 16, 16, TEXT))
    lines.append(_text(MARGIN, bar_y + 22, clock(hud.position), 28))
    remaining = (hud.duration - hud.position) if hud.duration and hud.position is not None else None
    lines.append(_text(W - MARGIN, bar_y + 22, f"-{clock(remaining)}" if remaining is not None else clock(hud.duration),
                       28, MUTED, align=9))
    lines.append(_text(W / 2, 1036, legend_line(), 26, align=2))
    return "\n".join(lines)


def menu_ass(menu: Menu) -> str:
    """Panel a la derecha con las pistas; la elegida lleva ●, la enfocada se resalta."""
    title = "Audio" if menu.kind == "audio" else "Subtítulos"
    row_h, width = 72, 620
    x = W - MARGIN - width
    height = 150 + row_h * len(menu.options) + 70
    y0 = max(80, (H - height) / 2 - 60)
    lines = [_rect(x, y0, width, height, "&H141418&", "18"),
             _text(x + 40, y0 + 40, title.upper(), 26, ACCENT, bold=True)]
    y = y0 + 100
    for i, option in enumerate(menu.options):
        if i == menu.index:
            lines.append(_rect(x + 20, y - 8, width - 40, row_h - 8, TEXT, "10"))
            color = "&H18141A&"
        else:
            color = TEXT
        mark = "●  " if option.get("current") else "    "
        lines.append(_text(x + 44, y + 6, esc(mark + option["label"]), 32, color, bold=i == menu.index))
        y += row_h
    lines.append(_text(x + 40, y + 24, f"{glyph('▲ ▼')}  {{\\1c{MUTED}}}Mover      {glyph('A')}  {{\\1c{MUTED}}}Elegir"
                                       f"      {glyph('B')}  {{\\1c{MUTED}}}Cerrar", 26))
    return "\n".join(lines)


def toast_ass(text: str) -> str:
    """Aviso corto arriba a la derecha (volumen, pista elegida)."""
    width = 40 + 17 * len(text)
    x = W - MARGIN - width
    return "\n".join([_rect(x, 64, width, 64, "&H141418&", "30"), _text(x + 20, 76, esc(text), 30)])


def track_menu(kind: str, tracks: list[dict], extra: list[dict] | None = None) -> Menu:
    """Opciones del menú: las pistas del video (y "Sin subtítulos" / buscar en tu addon)."""
    options = []
    if kind == "sub":
        none_selected = not any(t.get("type") == "sub" and t.get("selected") for t in tracks)
        options.append({"label": "Sin subtítulos", "action": ("sid", "no"), "current": none_selected})
    for t in tracks:
        if t.get("type") == kind:
            options.append({"label": track_label(t), "action": ("aid" if kind == "audio" else "sid", t["id"]),
                            "current": bool(t.get("selected"))})
    options += extra or []
    index = next((i for i, o in enumerate(options) if o.get("current")), 0)
    return Menu(kind, options, index)
