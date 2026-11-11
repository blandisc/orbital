"""Los paneles: pistas de audio y subtítulos, Más, versiones y episodios."""

from __future__ import annotations

from dataclasses import dataclass, field

from .. import flags
from . import canvas
from .canvas import FLAG_GAP, FLAG_H, LIVE, MARGIN, MUTED, NEXT, ON_LIGHT, RADIUS_CARD, SHADE, SOFT, TEXT, H, targets
from .draw import _shape, fit, glass, gradient, hints, hints_width, icon, rrect, text, text_width, wrap
from .hud import pills, pills_width
from .labels import clock, esc, track_label


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
    lines = [gradient(PANEL_TOP - 160, PANEL_TOP + 40, 255, 110, 10), rrect(0, PANEL_TOP + 40, canvas.W, H - PANEL_TOP - 40, 0, SHADE, "6E"),
             glass(MARGIN - PANEL_INSET, PANEL_TOP - 16, canvas.W - 2 * (MARGIN - PANEL_INSET), PANEL_BOTTOM - PANEL_TOP + 16, RADIUS_CARD,
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
    unit = min(520, (canvas.W - 2 * MARGIN - 64 * (n - 1)) / max(1.0, sum(weights)))
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
        if canvas.TOUCH:
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
            if canvas.TOUCH:
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
    note_room = canvas.W - 2 * MARGIN - 48 - (pills_width([*turn, ("Cerrar", "close")]) if canvas.TOUCH else hints_width(keys))
    while legend_below and legend_width(legend_below) > note_room:  # 4:3 con la letra más grande: lo de menos uso, fuera
        legend_below.pop()
    if panel.column.key == "source":  # la enfocada en palabras y qué quiere decir «Al instante», donde se elige
        note = "Al instante: Real-Debrid ya la tiene guardada y arranca en segundos. Las demás primero se descargan y pueden tardar."
        if panel.column.grid and panel.column.chosen:
            row, cell = panel.column.options[panel.column.index], panel.column.chosen
            said = " · ".join(p for p in (row["label"], cell["label"], cell["doubt"], cell["hint"], cell["size"],
                                          ADDON_MARKS.get(cell.get("addon") or "", ("",))[0],
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
    if canvas.TOUCH:
        lines.append(pills([*turn, ("Cerrar", "close")], 986, right=canvas.W - MARGIN, layer="panel"))
    else:
        lines.append(hints(keys, 1022, right=canvas.W - MARGIN))
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
    step = 30 * canvas._text_scale
    body = step * len(label) + (26 * canvas._text_scale if option.get("hint") else 0)
    return label, max(54.0, body + 22)


def _icon_rows(column: Column, c: int, x: float, col_w: float, active: bool) -> list[str]:
    """Reproducción (Y): cada acción con su ícono y su nombre completo, como los renglones de un menú de Orbital. La fila
    crece si el nombre necesita dos renglones; se ven las que caben entre ROWS_TOP y ROWS_BOTTOM y el resto se desplaza con
    el foco (sin brincar: solo cuando el foco sale de las que se ven)."""
    lines: list[str] = []
    if not column.options:
        return [text(x + 18, ROWS_TOP + 27, "Nada que elegir aquí", 24, MUTED, align=4)]
    size = ICON_SIZE * canvas._text_scale
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
        if canvas.TOUCH:
            targets["panel"].append((x, y, col_w, h, ("option", c, i)))
        ink = ON_LIGHT if focused else TEXT if option.get("current") else SOFT
        weight = "semi" if focused or option.get("current") else "regular"
        hint = option.get("hint") or ""
        step = 30 * canvas._text_scale
        top = y + (h - step * len(label) - (26 * canvas._text_scale if hint else 0)) / 2
        lines.append(icon(option.get("icon") or "restart", x + 18 + size / 2, y + h / 2, size, ink))
        for n, part in enumerate(label):
            lines.append(text(left, top + step * (n + .5), esc(part), 24, ink, weight=weight, align=4))
        if hint:
            lines.append(text(left, top + step * len(label) + 13 * canvas._text_scale, esc(fit(hint, 20, room)), 20,
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

ADDON_MARKS = {"torrentio": ("Torrentio", "addon-torrentio"), "comet": ("Comet", "addon-comet"), "other": ("Otro complemento", "addon")}


def cell_states(cell: dict) -> list[tuple[str, str, str]]:
    """Lo que dice una casilla (de `CELL_STATES`): primero qué tan rápido arranca y luego si su idioma es dudoso."""
    said = {cell.get("hint"), cell.get("doubt")}
    return [state for state in CELL_STATES if state[0] in said]


def legend_items(grid: list[dict]) -> list[tuple[str, str, str]]:
    """Los íconos de `CELL_STATES` que aparecen en la cuadrícula (la leyenda solo explica lo que se ve)."""
    present = {s[0] for row in grid for cell in row.get("cells", []) for s in cell_states(cell)}
    return [s for s in CELL_STATES if s[0] in present]


def legend_width(items: list[tuple[str, str, str]]) -> float:
    size = CELL_ICON * canvas._text_scale
    return sum(size + 8 + text_width(name, 20) for name, _, _ in items) + 24 * max(0, len(items) - 1)


def states_legend(items: list[tuple[str, str, str]], x: float, cy: float) -> list[str]:
    """«⚡ Al instante  ☁ Hay que bajarla  ? Idioma dudoso»: cada ícono con su nombre (nunca un ícono sin él)."""
    size, out = CELL_ICON * canvas._text_scale, []
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
    size = CELL_ICON * canvas._text_scale
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
            if canvas.TOUCH:
                targets["panel"].append((cx, y, width, 54, ("cell", c, i, j)))
            ink = ON_LIGHT if focused else TEXT
            # De qué complemento viene (Ⓣ, Ⓒ o la pieza): tenue, en el renglón de los íconos y a la derecha (junto a la
            # calidad, en una casilla angosta de 4:3, cortaba «4K HDR»).
            if mark := ADDON_MARKS.get(cell.get("addon") or ""):
                lines.append(icon(mark[1], cx + width - 12 - size / 2, y + 40, size, ON_LIGHT if focused else MUTED))
            room = width - 24
            label_size = 21  # «4K HDR» en una casilla angosta (16:10, letra grande): se achica antes de cortarse
            while label_size > 16 and text_width(cell["label"], label_size, "semi") > room:
                label_size -= 1
            lines.append(text(cx + 12, y + 17, esc(fit(cell["label"], label_size, room, "semi")), label_size, ink,
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
