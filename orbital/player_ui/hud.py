"""La barra de abajo mientras ves (tiempos, capítulos, botones) y la pantalla de pausa."""

from __future__ import annotations

from collections.abc import Sequence
from dataclasses import dataclass, field

from .. import flags
from . import canvas
from .canvas import FLAG_GAP, FLAG_H, MARGIN, MUTED, ON_LIGHT, SHADE, SOFT, TEXT, H, placed, targets
from .draw import (
    circle,
    fit,
    glass,
    glyph,
    gradient,
    hints,
    hints_width,
    rrect,
    side_gradient,
    text,
    text_width,
    wrap,
    wrap_sentences,
)
from .labels import clock, esc


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
    x0, w, h = MARGIN, canvas.W - 2 * MARGIN, 8
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
    if canvas.TOUCH:  # tocar la barra salta a ese punto (una franja alta: el dedo no atina a 8 px)
        targets["hud"].append((x0, y - 28, w, h + 56, ("seek", x0, w)))
    return "\n".join(out), knob


def _times(hud: Hud, y: float) -> str:
    remaining = (hud.duration - hud.position) if hud.duration and hud.position is not None else None
    right = f"−{clock(remaining)}" if remaining is not None else clock(hud.duration)  # solo lo que falta, sin «termina a las…»
    return "\n".join([text(MARGIN, y, clock(hud.position), 26, weight="semi"),
                      text(canvas.W - MARGIN, y, esc(right), 26, MUTED, align=9)])


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
        center = max(MARGIN + 220, min(canvas.W - MARGIN - 220, knob if knob is not None else canvas.W / 2))
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
                  hints([("◀ ▶", "Mantén: más rápido"), ("A", "Pausa")], 1022, right=canvas.W - MARGIN)]
        return "\n".join(lines)
    lines.append(gradient(0, 200, 100, 255, 14))
    if hud.now:
        lines.append(text(canvas.W - MARGIN, 56, esc(hud.now), 34, weight="semi", align=9))
    if hud.pip:
        lines.append(hints([("Home", "Ver en pequeño")], 56, left=MARGIN))
    # Reproduciendo, sin título ni «Película»: eso (y la sinopsis) es de la pausa. Solo la barra; abajo a la izquierda
    # el idioma, los subtítulos y la versión (en el mismo lugar que en pausa) y a la derecha los botones (también ◀▶ y
    # RT, que antes solo se descubrían en pausa). Si no caben (4:3), se quitan primero los de menos uso.
    # A primero, como en todo Orbital; luego lo que se descubre (◀▶, LT/RT) y B al final.
    items = [("A", "Pausa"), ("X", "Audio y subtítulos"), *([] if hud.clip else [("Y", "Episodios y versión" if hud.series else "Versión")]),
             ("◀ ▶", "Adelantar"), *([("RT", "Siguiente episodio")] if hud.next else []), ("B", "Mantén: salir")]
    while len(items) > 4 and hints_width(items) > canvas.W - 2 * MARGIN:
        items.pop(-2)  # si no caben (4:3): primero RT, luego ◀▶
    bottom = _touch_bar(hud, 1000, paused=False) if canvas.TOUCH else hints(items, 1022, right=canvas.W - MARGIN)
    lines += [bar, _times(hud, BAR_Y + 28)]
    room = canvas.W - 2 * MARGIN - (pills_width(_touch_items(hud, paused=False)) if canvas.TOUCH else hints_width(items)) - 48
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
    lines = [rrect(0, 0, canvas.W, H, 0, SHADE, "70"), side_gradient(canvas.W * .62, 90, steps=8), gradient(420, H, 255, 60, 12),
             gradient(0, 200, 140, 255, 8)]
    if hud.now:
        lines.append(text(canvas.W - MARGIN, 56, esc(hud.now), 34, weight="semi", align=9))
    if hud.pip:
        lines.append(hints([("Home", "Ver en pequeño")], 56, left=MARGIN))
    # El bloque va abajo, apoyado sobre la barra (como en las TV), no a media pantalla: se mide primero
    # y se coloca para que los botones queden justo encima de la barra de progreso.
    width = min(1180, canvas.W - 2 * MARGIN)
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
    subs = ("S", "Probar subtítulos") if canvas.KEYBOARD else ("X", "Mantén: probar subtítulos")
    # Un toque de RT pasa al siguiente (con aviso: B lo cancela); solo se dice si hay siguiente.
    more = [("◀ ▶", "Adelantar"), ("↑ ↓", "Volumen"), subs, *([("RT", "Siguiente episodio")] if hud.next else []),
            ("B", "Mantén: salir")]
    room = max(260, canvas.W - 2 * MARGIN - hints_width(more) - 48)
    if canvas.TOUCH:
        room = max(260, canvas.W - 2 * MARGIN - pills_width(_touch_items(hud, paused=True)) - 48)
    bottom = _touch_bar(hud, 1000, paused=True) if canvas.TOUCH else hints(more, 1022, right=canvas.W - MARGIN)
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
        h = 76 if canvas.TOUCH else 62
        # El glifo se mide de verdad: con teclado «Espacio» es mucho más ancho que el círculo del mando y se
        # encimaba sobre «Continuar».
        shape, gw = ("", 0.0) if canvas.TOUCH else glyph(x + 16, y + 31, key, 30, solid=primary)
        lead = 26 if canvas.TOUCH else 16 + gw + 12
        w = lead + text_width(label, 24, "semi") + 26
        out.append(rrect(x, y, w, h, h / 2, TEXT) if primary
                   else glass(x, y, w, h, h / 2))
        if shape:
            out.append(shape)
        out.append(text(x + lead, y + h / 2, esc(label), 24, ON_LIGHT if primary else TEXT, weight="semi", align=4))
        if canvas.TOUCH:
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
    return pills(_touch_items(hud, paused=paused), y, right=canvas.W - MARGIN, h=66)
