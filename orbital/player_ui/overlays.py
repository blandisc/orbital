"""Lo que aparece encima un momento: probar subtítulos, la barra de la TV en vivo, saltar la intro, el siguiente
episodio, avisos, salir manteniendo, el volumen, la ventanita y el telón."""

from __future__ import annotations

import math
import re
from dataclasses import dataclass

from .. import flags
from . import canvas
from .canvas import (
    FLAG_GAP,
    FLAG_H,
    GLYPH,
    LIVE,
    MARGIN,
    MUTED,
    ON_LIGHT,
    PALETTE,
    PANEL,
    RADIUS_CARD,
    SOFT,
    TEXT,
    H,
    ass_color,
    placed,
    targets,
)
from .draw import _shape, arc, circle, fade, fit, glass, glyph, gradient, hints, hints_width, ring, rrect, text, text_width
from .hud import pills
from .labels import esc
from .panels import Panel, _column, delay_label


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
    h = TRY_TOUCH_H if canvas.TOUCH else TRY_H
    top, info, keys = TRY_ROWS
    lines = [glass(0, 0, canvas.W, h, 0, "glass-strong", None), gradient(h, h + 48, 160, 255, 8)]
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
    status_w = min(text_width(trial.status, 22, "semi"), (canvas.W - 2 * MARGIN) * .36) if trial.status else 0
    room = canvas.W - MARGIN - x - status_w - 48
    lines.append(text(x, top, esc(fit(title, 28, room, "bold")), 28, weight="bold", align=4))
    x += min(text_width(title, 28, "bold"), room) + 28
    if trial.badge and trial.number > 0:  # por qué está ahí, en su píldora (el turquesa de «al aire»: es lo bueno)
        bw, bh = text_width(trial.badge, 19, "semi") + 32, 34
        if x + bw < canvas.W - MARGIN - status_w - 48:
            lines += [rrect(x, top - bh / 2, bw, bh, bh / 2, LIVE, "C8", outline=LIVE, width=1.5),
                      text(x + bw / 2, top, esc(trial.badge), 19, LIVE, weight="semi", align=5)]
    if trial.status:
        lines.append(text(canvas.W - MARGIN, top, esc(fit(trial.status, 22, status_w + 1, "semi")), 22, SOFT, weight="semi", align=6))
    # Segundo renglón: de dónde viene, la copia para la que se hizo y sus descargas; la sincronía va a la derecha (es lo
    # que mueves con ↑ ↓, y así el nombre largo de la copia no la empuja fuera).
    origin = "Del video" if trial.origin == "video" else ""
    parts = [p for p in (origin, trial.release, _downloads(trial.downloads)) if p] if trial.number > 0 else []
    sync = f"Sincronía: {delay_label(trial.delay)}"
    lines.append(text(canvas.W - MARGIN, info, esc(sync), 21, SOFT if abs(trial.delay) >= .05 else MUTED, weight="semi", align=6))
    if parts:
        room = canvas.W - 2 * MARGIN - text_width(sync, 21, "semi") - 48
        lines.append(text(MARGIN, info, esc(fit(" · ".join(parts), 21, room, "semi")), 21, MUTED, weight="semi", align=4))
    if canvas.TOUCH:
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
        lines.append(text(canvas.W - MARGIN, 56, esc(hud.now), 34, weight="semi", align=9))
    number = str(hud.number) if hud.number else "—"
    block = max(112, text_width(number, 56, "bold") + 52)
    top = 786
    x = MARGIN + block + 28
    room = canvas.W - x - MARGIN
    label, color = LIVE_STATUS.get(hud.status, LIVE_STATUS["live"])
    lines += [rrect(MARGIN, top, block, 100, 22, TEXT), text(MARGIN + block / 2, top + 50, esc(number), 56, ON_LIGHT, weight="bold", align=5),
              text(x, top - 2, esc(fit(hud.name, 52, min(room, 1300), "bold")), 52, weight="bold"),
              circle(x + 9, top + 78, 7, color), text(x + 28, top + 78, esc(label), 24, color, weight="semi", align=4)]
    info = live_info_line(hud)
    if info:
        lines.append(text(x + 28 + text_width(label, 24, "semi") + 22, top + 78, esc(fit(info, 24, max(200, room - 280), "semi")), 24, MUTED,
                          weight="semi", align=4))
    items = [("↑ ↓", "Canal"), ("Y", "Canales"), ("X", "Audio"), ("◀ ▶", "Volumen"), ("A", "Silencio"), ("B", "Mantén: salir")]
    while len(items) > 3 and hints_width(items) > canvas.W - 2 * MARGIN:
        items.pop(-2)  # si no caben (4:3): primero A, luego ◀▶
    if canvas.TOUCH:  # con el dedo: botones que se tocan (la acción, la de la tecla)
        lines.append(pills([("Canal −", "down"), ("Canal +", "up"), ("Canales", "y"), ("Audio", "x"),
                            ("Silencio", "a"), ("Salir", "quit")], 940, center=canvas.W / 2, h=66))
    else:
        lines.append(hints(items, 1022, right=canvas.W - MARGIN))
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
    if canvas.TOUCH:
        w = text_width(label, 24, "bold") + 56
        x, y = canvas.W - MARGIN - w, 780 + lift
        targets["card"].append((x, y, w, 76, "a"))
        return _entering("\n".join([rrect(x, y, w, 76, 14, TEXT),
                                    text(x + w / 2, y + 38, esc(label), 24, ON_LIGHT, weight="bold", align=5)]), appear)
    gw = glyph(0, 0, "A", 30)[1]  # con teclado, «Espacio»: el botón crece con su glifo
    w = 16 + gw + 12 + text_width(label, 24, "bold") + 28
    x, y = canvas.W - MARGIN - w, 790 + lift
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
    w, h = (880 if still else 660), (206 if canvas.TOUCH else 176) - short
    x, y = canvas.W - MARGIN - w, 870 - h + (1 - ease_out(appear)) * CARD_RISE
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
    if canvas.TOUCH:  # botones que se tocan: «Seguir viendo», «Salir»… (la acción: la tecla que harían)
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
    room = canvas.W - 2 * MARGIN - 44
    title = fit(title, 24, room, "semi")
    if not detail:
        w = text_width(title, 24, "semi") + 44
        x = canvas.W - MARGIN - w
        return "\n".join([glass(x, top, w, 54, 27, "glass-strong"), text(x + 22, top + 27, esc(title), 24, weight="semi", align=4)])
    detail = fit(detail, 20, room)
    w = max(text_width(title, 24, "semi"), text_width(detail, 20)) + 44
    x = canvas.W - MARGIN - w
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
    cx, cy, r = canvas.W - MARGIN - 30, H - 220, 30
    shape, gw = glyph(cx - (20 if len(key) == 1 else 26), cy, key, 40)
    return "\n".join([circle(cx, cy, r + 6, PANEL, "70", blur=6),
                      ring(cx, cy, r, 3, 1.0, TEXT, "C8"), ring(cx, cy, r, 3, progress, TEXT), shape,
                      text(cx - r - 16, cy, esc(label), 24, SOFT, weight="semi", align=6)])


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
    x, y = canvas.W - MARGIN + 20 - w, BUFFER_Y + 80  # debajo de «Cargando…» y del anillo de «Salir»
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
    cx, cy = canvas.W / 2, H / 2
    corner = PIP_BUTTON + 64
    veil = rrect(0, 0, canvas.W, H, 0, PANEL, "B0")  # un velo tenue: el video se sigue viendo
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
    qx, qy = canvas.W - corner, corner
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
    return f"{{\\an7\\pos(0,0)\\bord0\\shad0\\1c&H000000&\\1a&H{alpha:02X}&\\p1}}m 0 0 l {canvas.W} 0 {canvas.W} {H} 0 {H}{{\\p0}}"


def seek_label(seconds: int) -> str:
    """"+10 s", "−30 s", "+1 min": lo que avanza cada toque (crece si mantienes)."""
    sign = "+" if seconds >= 0 else "−"
    s = abs(int(seconds))
    return f"{sign}{s // 60} min" if s >= 60 and s % 60 == 0 else f"{sign}{s} s"
