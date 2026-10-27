"""Avisos encima del juego (con un juego al frente, la ventana de Orbital no se ve), hechos con el sistema de diseño de
Orbital (tokens.css, themes/orbital.css, toast.css):

- Notificación («GameSir conectado · Jugador 2», «Se desconectó el GameSir»): arriba a la derecha, donde salen los avisos
  de Orbital, con su forma (radio xl), su fondo, su borde fino y su sombra. El ícono en un círculo: el número del
  jugador en el azul de los controles de Orbital o, si es advertencia, «!» en ámbar tenue. Entra como los avisos (desliza 1,5 rem y aparece en 220 ms, ease-out) y el número hace un «pop».
- Acción (mantener el atajo de cerrar): la misma notificación, en el mismo lugar, con el ícono de apagar; el anillo coral
  alrededor se llena mientras mantienes el atajo y, al cerrar, el círculo se llena entero («Volviendo a Orbital»).

Todo se mide en `rem`, la unidad de la interfaz (min(1,25 vw, 2 vh)): se ve igual de grande que Orbital en 4K, en 1080p
para jugar o en la pantalla de la Legion. Se dibuja con Pillow (suavizado, con transparencia de verdad) y Windows lo pone
encima con UpdateLayeredWindow: una ventana que no toma el foco (el juego sigue recibiendo el mando) y que los clics
atraviesan. Tkinter solo pone el reloj y la cola de órdenes, en su propio hilo.
"""

from __future__ import annotations

import ctypes
import logging
import queue
import sys
import threading
import time
from ctypes import wintypes

log = logging.getLogger(__name__)

# --- el sistema de diseño (tokens.css y themes/orbital.css) --------------------------------------------------------------
SURFACE = (30, 30, 35)  # --color-surface-raised (--palette-ink-800)
TEXT = (245, 244, 240)  # --color-text (--palette-paper)
MUTED = (163, 163, 171)  # --color-text-muted (--palette-ink-300)
HAIRLINE = (255, 255, 255, 23)  # --color-hairline (blanco al 9 %)
TRACK = (42, 42, 48)  # --palette-ink-700
CORAL = (240, 87, 77)  # --palette-red-400 (la barra de cerrar)
WARN = (244, 194, 77)  # --color-warning (--palette-amber-300)
PAD_BLUE = (74, 138, 232)  # --palette-pad-blue: el azul de los controles en Orbital (el círculo del jugador)

# En rem (la unidad de la interfaz). Los de la notificación son los de toast.css.
RADIUS = 1.1  # --radius-xl (dos renglones)
ICON = 2.2  # .toast__icon
PAD_LEFT, PAD_RIGHT, GAP = .5, 1.5, .75  # --space-2 · --space-6 · --space-3
TOAST_MIN_W, TOAST_MAX_W, TOAST_H = 18, 34, 4.1
TITLE_SIZE, DETAIL_SIZE = 1.07, .98  # --text-md · --text-sm
SHADOW_Y, SHADOW_BLUR, SHADOW_ALPHA = 1.5, 4.0, .55  # --shadow-overlay: 0 1.5rem 4rem rgba(0,0,0,.55)
RING = .16  # rem: el grueso del anillo que se llena al mantener el atajo de cerrar
SAFE_AREA = 4  # --safe-area: margen de la tele (Ajustes › Márgenes de la TV)

# El movimiento (tokens.css): --duration-base / --ease-out y --duration-exit / --ease-in, como toast-in / toast-out.
ENTER_MS, EXIT_MS = 220, 160
EASE_OUT = (.16, 1, .3, 1)
EASE_IN = (.5, 0, .75, 0)
SLIDE_IN, SLIDE_OUT = 1.5, 1.0  # rem: toast-in viene de 1,5 rem a la derecha; toast-out se va 1 rem
POP_MS, POP_DELAY_MS, POP_FRAMES = 380, 90, 12


def bezier(p1x: float, p1y: float, p2x: float, p2y: float):
    """cubic-bezier() de CSS: devuelve la curva como función de 0 a 1."""
    def at(t: float, a: float, b: float) -> float:
        return 3 * a * t * (1 - t) ** 2 + 3 * b * t * t * (1 - t) + t ** 3

    def curve(x: float) -> float:
        lo, hi = 0.0, 1.0
        for _ in range(24):  # bisección: de sobra para 60 cuadros por segundo
            mid = (lo + hi) / 2
            if at(mid, p1x, p2x) < x:
                lo = mid
            else:
                hi = mid
        return at((lo + hi) / 2, p1y, p2y)
    return curve


def ease_back(p: float) -> float:
    """Pasa un poco de su tamaño y regresa: el «pop» del número."""
    c1 = 1.70158
    return 1 + (c1 + 1) * (p - 1) ** 3 + c1 * (p - 1) ** 2


def screen_rect() -> tuple[int, int, int, int]:
    """(x, y, ancho, alto) de la pantalla principal AHORA, en pixeles reales. GetSystemMetrics se quedaba con el tamaño de
    cuando arrancó Orbital: con la tele bajada a 1080p para jugar (display.py) el aviso se calculaba para 4K y quedaba
    fuera de la pantalla (y = 1556 en una de 1080, visto el 2026-10-26)."""

    class _Info(ctypes.Structure):
        _fields_ = [("cbSize", ctypes.c_ulong), ("rcMonitor", wintypes.RECT), ("rcWork", wintypes.RECT),
                    ("dwFlags", ctypes.c_ulong)]

    user32 = ctypes.windll.user32
    user32.MonitorFromPoint.restype = ctypes.c_void_p
    monitor = user32.MonitorFromPoint(ctypes.c_longlong(0), 1)  # MONITOR_DEFAULTTOPRIMARY
    info = _Info()
    info.cbSize = ctypes.sizeof(info)
    if monitor and user32.GetMonitorInfoW(ctypes.c_void_p(monitor), ctypes.byref(info)):
        r = info.rcMonitor
        return r.left, r.top, r.right - r.left, r.bottom - r.top
    return 0, 0, user32.GetSystemMetrics(0), user32.GetSystemMetrics(1)


def rem_for(width: int, height: int) -> float:
    """La unidad de la interfaz en pixeles reales: --root-size = clamp(12px, min(1.25vw, 2vh), 44px)."""
    return max(12.0, min(width * .0125, height * .02))


# --- dibujar (Pillow) -------------------------------------------------------------------------------------------------
def _font(size: float, weight: str):
    from PIL import ImageFont

    try:
        font = ImageFont.truetype("SegUIVar.ttf", max(1, round(size)))  # Segoe UI Variable, la de la interfaz
        names = [n.decode() if isinstance(n, bytes) else n for n in font.get_variation_names()]
        pick = next((n for n in names if "Text" in n and weight in n), None) or next((n for n in names if weight in n), None)
        if pick:
            font.set_variation_by_name(pick)
        return font
    except (OSError, AttributeError, ValueError):
        pass
    for name in ("seguisb.ttf" if weight == "Semibold" else "segoeui.ttf", "segoeui.ttf"):
        try:
            return ImageFont.truetype(name, max(1, round(size)))
        except OSError:
            continue
    return ImageFont.load_default()


def _fit(draw, text: str, font, room: float) -> str:
    if draw.textlength(text, font=font) <= room:
        return text
    while text and draw.textlength(text + "…", font=font) > room:
        text = text[:-1]
    return text.rstrip() + "…"


def _card(width: float, height: float, rem: float):
    """La tarjeta con su sombra: (imagen RGBA, margen de la sombra). La sombra es la de --shadow-overlay."""
    from PIL import Image, ImageDraw, ImageFilter

    margin = round(SHADOW_BLUR * rem * .75)
    w, h = round(width), round(height)
    image = Image.new("RGBA", (w + 2 * margin, h + 2 * margin), (0, 0, 0, 0))
    radius = round(RADIUS * rem)
    shadow = Image.new("L", image.size, 0)
    dy = round(SHADOW_Y * rem * .5)
    ImageDraw.Draw(shadow).rounded_rectangle((margin, margin + dy, margin + w, margin + h + dy), radius,
                                             fill=round(255 * SHADOW_ALPHA))
    shadow = shadow.filter(ImageFilter.GaussianBlur(SHADOW_BLUR * rem / 4))
    image.putalpha(shadow)
    # La tarjeta, suavizada: se dibuja al doble y se reduce.
    big = Image.new("RGBA", (w * 2, h * 2), (0, 0, 0, 0))
    draw = ImageDraw.Draw(big)
    draw.rounded_rectangle((0, 0, w * 2 - 1, h * 2 - 1), radius * 2, fill=SURFACE + (255,))
    draw.rounded_rectangle((1, 1, w * 2 - 2, h * 2 - 2), radius * 2, outline=HAIRLINE, width=2)
    image.alpha_composite(big.resize((w, h), Image.LANCZOS), (margin, margin))
    return image, margin


def _circle(text: str, size: int, tone: str, grow: float = 1.12):
    """El ícono: el número del jugador en el azul de los controles, o «!» en ámbar tenue (advertencia). `grow`: su tamaño
    (el «pop» de la entrada; a 1.12 llena su lugar)."""
    from PIL import Image, ImageDraw

    big = size * 4
    image = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    r = big / 2 * max(.05, min(1.12, grow)) / 1.12
    box = (big / 2 - r, big / 2 - r, big / 2 + r, big / 2 + r)
    if tone == "warn":
        draw.ellipse(box, fill=WARN + (46,))  # color-mix(… 18 %, transparent), como .toast__icon
        ink = WARN + (255,)
    else:
        draw.ellipse(box, fill=PAD_BLUE + (255,))
        ink = TEXT + (255,)
    # Centrado de verdad: con la caja que ocupa la figura (anchor «mm» centra la línea de texto y los números de Segoe
    # quedaban un poco altos).
    font = _font(r * .95, "Semibold")
    left, top, right, bottom = draw.textbbox((0, 0), text, font=font)
    draw.text((big / 2 - (left + right) / 2, big / 2 - (top + bottom) / 2), text, fill=ink, font=font)
    return image.resize((size, size), Image.LANCZOS)


def draw_toast(title: str, detail: str, mark: str, tone: str, rem: float, grow: float = 1.12):
    """La notificación completa: (imagen, margen de la sombra)."""
    from PIL import Image, ImageDraw

    probe = ImageDraw.Draw(Image.new("RGBA", (1, 1)))
    title_font, detail_font = _font(TITLE_SIZE * rem, "Semibold"), _font(DETAIL_SIZE * rem, "Regular")
    icon = round(ICON * rem) if mark else 0
    inset = (TOAST_H * rem - icon) / 2 if detail else (3 * rem - icon) / 2  # el círculo, centrado en su alto
    left = (inset + icon + GAP * rem) if mark else 1.25 * rem
    words = max(probe.textlength(title, font=title_font), probe.textlength(detail, font=detail_font) if detail else 0)
    width = min(TOAST_MAX_W * rem, max(TOAST_MIN_W * rem, left + words + PAD_RIGHT * rem))
    height = TOAST_H * rem if detail else 3 * rem
    image, margin = _card(width, height, rem)
    draw = ImageDraw.Draw(image)
    room = width - left - PAD_RIGHT * rem
    x, mid = margin + left, margin + height / 2
    if mark and grow > 0:
        circle = _circle(mark, icon, tone, grow)
        image.alpha_composite(circle, (round(margin + inset), round(mid - icon / 2)))
    if detail:
        draw.text((x, mid - .1 * rem), _fit(draw, title, title_font, room), fill=TEXT + (255,), font=title_font, anchor="ls")
        draw.text((x, mid + .3 * rem), _fit(draw, detail, detail_font, room), fill=MUTED + (255,), font=detail_font,
                  anchor="lt")
    else:
        draw.text((x, mid), _fit(draw, title, title_font, room), fill=TEXT + (255,), font=title_font, anchor="lm")
    return image, margin


def _power(size: int, progress: float, done: bool):
    """El ícono de cerrar: el símbolo de apagar en un círculo tenue, con el anillo coral que se llena con `progress`
    (de las 12 en punto, en el sentido del reloj). `done`: el círculo coral entero (ya se está cerrando)."""
    from PIL import Image, ImageDraw

    big = size * 4
    image = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    ring = max(4, round(big * RING / ICON))
    if done:
        draw.ellipse((0, 0, big - 1, big - 1), fill=CORAL + (255,))
    else:
        draw.ellipse((0, 0, big - 1, big - 1), fill=CORAL + (46,))  # tenue, como el «!» de advertencia
        if progress > 0:
            draw.arc((ring / 2, ring / 2, big - 1 - ring / 2, big - 1 - ring / 2), -90, -90 + 360 * min(1.0, progress),
                     fill=CORAL + (255,), width=ring)
    ink = (TEXT if done else CORAL) + (255,)
    r, stroke = big * .22, max(3, round(big * .075))
    c = big / 2
    draw.arc((c - r, c - r + big * .03, c + r, c + r + big * .03), -50, 230, fill=ink, width=stroke)
    draw.line((c, c - r - big * .02, c, c + big * .02), fill=ink, width=stroke)
    for x, y in ((c, c - r - big * .02), (c, c + big * .02)):  # puntas redondas
        draw.ellipse((x - stroke / 2, y - stroke / 2, x + stroke / 2, y + stroke / 2), fill=ink)
    return image.resize((size, size), Image.LANCZOS)


def draw_action(title: str, detail: str, progress: float, rem: float, base=None, done: bool = False):
    """La acción de cerrar, con la forma de la notificación: (imagen, margen, base sin el ícono, para reusarla en cada
    cuadro)."""
    if base is None:
        image, margin = draw_toast(title, detail, " ", "ok", rem, grow=0)
        base = (image, margin)
    image, margin = base[0].copy(), base[1]
    icon = round(ICON * rem)
    inset = (TOAST_H * rem - icon) / 2
    image.alpha_composite(_power(icon, progress, done), (round(margin + inset), round(margin + TOAST_H * rem / 2 - icon / 2)))
    return image, margin, base


# --- la ventana (UpdateLayeredWindow) ---------------------------------------------------------------------------------
class _Blend(ctypes.Structure):
    _fields_ = [("BlendOp", ctypes.c_ubyte), ("BlendFlags", ctypes.c_ubyte), ("SourceConstantAlpha", ctypes.c_ubyte),
                ("AlphaFormat", ctypes.c_ubyte)]


class _BitmapInfoHeader(ctypes.Structure):
    _fields_ = [("biSize", wintypes.DWORD), ("biWidth", ctypes.c_long), ("biHeight", ctypes.c_long),
                ("biPlanes", wintypes.WORD), ("biBitCount", wintypes.WORD), ("biCompression", wintypes.DWORD),
                ("biSizeImage", wintypes.DWORD), ("biXPelsPerMeter", ctypes.c_long), ("biYPelsPerMeter", ctypes.c_long),
                ("biClrUsed", wintypes.DWORD), ("biClrImportant", wintypes.DWORD)]


class Surface:
    """Una imagen RGBA con transparencia de verdad encima de todo, en (x, y) y con opacidad; moverla o cambiarle la
    opacidad no la vuelve a dibujar."""

    def __init__(self, hwnd: int) -> None:
        self.hwnd = hwnd
        self.size = (0, 0)
        gdi = ctypes.windll.gdi32
        gdi.CreateCompatibleDC.restype = ctypes.c_void_p
        gdi.CreateDIBSection.restype = ctypes.c_void_p
        gdi.SelectObject.restype = ctypes.c_void_p
        self.dc = gdi.CreateCompatibleDC(None)
        self.bitmap: int | None = None

    def set_image(self, image) -> None:
        from PIL import Image, ImageChops

        w, h = image.size
        r, g, b, a = image.split()
        # Windows pide los colores premultiplicados por la transparencia, en orden BGRA y de abajo hacia arriba.
        premult = Image.merge("RGBA", (ImageChops.multiply(b, a), ImageChops.multiply(g, a), ImageChops.multiply(r, a), a))
        data = premult.tobytes("raw", "RGBA", 0, -1)
        header = _BitmapInfoHeader(ctypes.sizeof(_BitmapInfoHeader), w, h, 1, 32, 0, 0, 0, 0, 0, 0)
        bits = ctypes.c_void_p()
        gdi = ctypes.windll.gdi32
        bitmap = gdi.CreateDIBSection(ctypes.c_void_p(self.dc), ctypes.byref(header), 0, ctypes.byref(bits), None, 0)
        if not bitmap or not bits.value:
            return
        ctypes.memmove(bits, data, len(data))
        gdi.SelectObject(ctypes.c_void_p(self.dc), ctypes.c_void_p(bitmap))
        if self.bitmap:
            gdi.DeleteObject(ctypes.c_void_p(self.bitmap))
        self.bitmap = bitmap
        self.size = (w, h)

    def show(self, x: float, y: float, alpha: float) -> None:
        w, h = self.size
        blend = _Blend(0, 0, max(0, min(255, round(alpha * 255))), 1)  # AC_SRC_OVER, AC_SRC_ALPHA
        pos, size, src = wintypes.POINT(round(x), round(y)), wintypes.SIZE(w, h), wintypes.POINT(0, 0)
        ctypes.windll.user32.UpdateLayeredWindow(ctypes.c_void_p(self.hwnd), None, ctypes.byref(pos), ctypes.byref(size),
                                                 ctypes.c_void_p(self.dc), ctypes.byref(src), 0, ctypes.byref(blend), 2)


class GameOverlay:
    def __init__(self, reduce_motion=lambda: False, safe_area=lambda: SAFE_AREA) -> None:
        self.reduce_motion = reduce_motion  # Ajustes › Pantalla › Reducir movimiento: sin deslizar ni «pop»
        self.safe_area = safe_area  # Ajustes › Márgenes de la TV: el mismo margen que los avisos de Orbital
        self._commands: queue.Queue = queue.Queue()
        self._ready = threading.Event()
        self._thread: threading.Thread | None = None

    # ------------------------------------------------------------- API (cualquier hilo)
    def start(self) -> bool:
        if sys.platform != "win32":
            return False
        self._thread = threading.Thread(target=self._run, daemon=True, name="overlay")
        self._thread.start()
        return self._ready.wait(5)

    def show(self, title: str, detail: str, duration_ms: int) -> None:
        """Acción: mantener el atajo de cerrar (la barra se llena en `duration_ms`)."""
        self._commands.put(("show", title, detail, duration_ms))

    def notice(self, title: str, detail: str = "", seconds: float = 3.5, badge: str = "", tone: str = "ok") -> None:
        """Notificación arriba a la derecha que se va sola. `badge`: el texto de su círculo (el número del jugador, «!»);
        `tone`: «ok» o «warn» (ámbar)."""
        self._commands.put(("notice", title, detail, int(seconds * 1000), badge, tone))

    def closing(self, title: str, detail: str = "") -> None:
        self._commands.put(("closing", title, detail))

    def hide(self, delay_ms: int = 0) -> None:
        self._commands.put(("hide", delay_ms))

    # ------------------------------------------------------------- hilo de la ventana
    def _run(self) -> None:
        try:
            ctypes.windll.shcore.SetProcessDpiAwareness(2)  # pixeles reales: nítido en 4K y en la Legion
        except (AttributeError, OSError):
            pass
        import tkinter as tk

        root = tk.Tk()  # solo el reloj (after) y los mensajes de la ventana
        root.withdraw()
        root.overrideredirect(True)
        root.attributes("-topmost", True)
        hwnd = _hwnd(root)
        _style_window(hwnd)
        root.deiconify()
        _hide(hwnd)
        surface = Surface(hwnd)
        ease_out, ease_in = bezier(*EASE_OUT), bezier(*EASE_IN)
        state: dict = {"kind": None, "alpha": 0.0, "dx": 0.0, "dy": 0.0, "anim": None, "hide_at": None, "rem": 16.0,
                       "spot": (0.0, 0.0), "filling": None, "base": None, "pop": None, "content": None}

        def measure() -> float:
            _sx, _sy, sw, sh = screen_rect()
            state["rem"] = rem_for(sw, sh)
            return state["rem"]

        def put(image, margin: int, anchor: str) -> None:
            """La imagen nueva en su lugar, en la pantalla de ahora: arriba a la derecha (top y right de .toast)."""
            sx, sy, sw, sh = screen_rect()
            rem = state["rem"]
            surface.set_image(image)
            w, h = image.size
            safe = self.safe_area()
            top = (1.25 + 3 + .25) * rem + safe * .006 * sh  # calc(--space-5 + --safe-y + 3rem + --space-1)
            right = max(rem, safe * .01 * sw)  # --page-gutter: max(--space-4, --safe-x)
            state["spot"] = (sx + sw - right - (w - margin), sy + top - margin)
            draw_now()

        def draw_now() -> None:
            x, y = state["spot"]
            surface.show(x + state["dx"], y + state["dy"], state["alpha"])

        def animate(dx: float, dy: float, alpha: float, ms: int, curve) -> None:
            state["anim"] = (time.monotonic(), ms / 1000, state["dx"], dx, state["dy"], dy, state["alpha"], alpha, curve)

        def enter(axis: str) -> None:
            still = self.reduce_motion()
            if state["alpha"] == 0:
                state["dx"] = SLIDE_IN * state["rem"] if axis == "x" and not still else 0
                state["dy"] = SLIDE_IN * state["rem"] if axis == "y" and not still else 0
            _raise_no_activate(hwnd)
            draw_now()
            animate(0, 0, 1.0, ENTER_MS, ease_out)

        def leave() -> None:
            shift = 0 if self.reduce_motion() else SLIDE_OUT * state["rem"]
            animate(shift, 0, 0.0, EXIT_MS, ease_in)

        def toast(cmd) -> None:
            _, title, detail, duration, mark, tone = cmd
            rem = measure()
            state["kind"], state["filling"] = "toast", None
            pop = bool(mark) and not self.reduce_motion()
            state["content"] = (title, detail, mark, tone)
            image, margin = draw_toast(title, detail, mark, tone, rem, grow=.05 if pop else 1.12)
            put(image, margin, "toast")
            state["pop"] = time.monotonic() + POP_DELAY_MS / 1000 if pop else None
            state["hide_at"] = time.monotonic() + duration / 1000
            enter("x")

        def action(title: str, detail: str, progress: float, fresh: bool, done: bool = False) -> None:
            rem = measure() if fresh else state["rem"]
            if fresh or state["kind"] != "action":
                state["base"] = None
            image, margin, state["base"] = draw_action(title, detail, progress, rem, state["base"], done=done)
            state["kind"] = "action"
            put(image, margin, "action")

        def handle(cmd) -> None:
            kind = cmd[0]
            if kind == "notice":
                toast(cmd)
            elif kind == "show":
                _, title, detail, duration = cmd
                state["filling"] = (time.monotonic(), max(duration, 1) / 1000, title, detail)
                state["hide_at"], state["pop"] = None, None
                action(title, detail, 0.0, fresh=True)
                enter("x")
            elif kind == "closing":
                state["filling"] = None
                action(cmd[1], cmd[2], 1.0, fresh=True, done=True)
            elif kind == "hide":
                state["hide_at"] = time.monotonic() + cmd[1] / 1000
                state["filling"] = None

        def tick() -> None:
            try:
                while True:
                    try:
                        handle(self._commands.get_nowait())
                    except queue.Empty:
                        break
                now = time.monotonic()
                if state["hide_at"] is not None and now >= state["hide_at"]:
                    state["hide_at"] = None
                    leave()
                filling = state["filling"]
                if filling is not None:
                    t0, length, title, detail = filling
                    action(title, detail, (now - t0) / length, fresh=False)
                pop = state["pop"]
                if pop is not None and now >= pop and state["kind"] == "toast":
                    p = min(1.0, (now - pop) / (POP_MS / 1000))
                    step = round(p * (POP_FRAMES - 1)) / (POP_FRAMES - 1)
                    title, detail, mark, tone = state["content"]
                    image, _margin = draw_toast(title, detail, mark, tone, state["rem"], grow=ease_back(step) * 1.12)
                    surface.set_image(image)
                    draw_now()
                    if p >= 1:
                        state["pop"] = None
                anim = state["anim"]
                if anim is not None:
                    t0, length, dx0, dx1, dy0, dy1, a0, a1, curve = anim
                    p = min(1.0, (now - t0) / length)
                    e = curve(p)
                    state["dx"], state["dy"] = dx0 + (dx1 - dx0) * e, dy0 + (dy1 - dy0) * e
                    state["alpha"] = a0 + (a1 - a0) * e
                    draw_now()
                    if p >= 1:
                        state["anim"] = None
                        if a1 == 0:
                            state["kind"] = None
                            _hide(hwnd)  # se fue: fuera de la pantalla hasta la próxima
            except Exception:  # noqa: BLE001 - un aviso roto nunca tumba el hilo
                log.exception("Error dibujando el aviso encima del juego")
            # 60 vueltas por segundo solo mientras se ve; escondida, 10: una orden nueva tarda a lo mucho 100 ms en
            # notarse (el aviso de cerrar sale a los 250 ms de mantener el atajo) y no gasta CPU sin parar.
            busy = state["alpha"] > 0 or state["anim"] is not None or state["filling"] is not None or state["pop"] is not None
            root.after(16 if busy else 100, tick)

        self._ready.set()
        root.after(16, tick)
        root.mainloop()


# ----------------------------------------------------------------- Win32
GWL_EXSTYLE = -20
WS_EX_TOPMOST = 0x00000008
WS_EX_TOOLWINDOW = 0x00000080  # sin botón en la barra de tareas
WS_EX_NOACTIVATE = 0x08000000  # nunca toma el foco
WS_EX_TRANSPARENT = 0x00000020  # los clics la atraviesan
WS_EX_LAYERED = 0x00080000
HWND_TOPMOST = -1
SWP_NOSIZE, SWP_NOMOVE, SWP_NOACTIVATE = 0x1, 0x2, 0x10
SW_HIDE, SW_SHOWNOACTIVATE = 0, 4


def _hwnd(root) -> int:
    root.update_idletasks()
    return int(root.wm_frame(), 16)


def _style_window(hwnd: int) -> None:
    user32 = ctypes.windll.user32
    style = user32.GetWindowLongW(hwnd, GWL_EXSTYLE)
    user32.SetWindowLongW(hwnd, GWL_EXSTYLE,
                          style | WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_TRANSPARENT | WS_EX_LAYERED)


def _raise_no_activate(hwnd: int) -> None:
    """Visible y encima de todo (también del juego en pantalla completa sin bordes), sin activarla."""
    ctypes.windll.user32.ShowWindow(hwnd, SW_SHOWNOACTIVATE)
    ctypes.windll.user32.SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOSIZE | SWP_NOMOVE | SWP_NOACTIVATE)


def _hide(hwnd: int) -> None:
    """La quita de la pantalla para que no estorbe a DWM ni al juego."""
    ctypes.windll.user32.ShowWindow(hwnd, SW_HIDE)
