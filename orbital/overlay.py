"""Avisos encima del juego (con un juego al frente, la ventana de Orbital no se ve), en el mismo lenguaje que los de
Orbital:

- Notificación («GameSir conectado · Jugador 2», «Se desconectó el GameSir»): arriba a la derecha, donde salen los avisos
  de Orbital (toast.css), con su ícono en un círculo (el número del jugador; ámbar si es una advertencia) y tan ancha como
  su texto. Entra deslizándose desde la derecha y se va sola.
- Acción (mantener el atajo de cerrar: Start + Select + Home; GameSir: LB + RB + Select): abajo al centro, como los
  avisos de las consolas, con el juego en grande, qué mantener y una barra que se llena. Entra subiendo.

Una ventana pequeña, siempre visible y que NO toma el foco: el juego sigue recibiendo el mando. Se dibuja con Tkinter
(viene con Python) en su propio hilo; las órdenes llegan por una cola que el hilo atiende ~60 veces por segundo. Se
acomoda cada vez en la pantalla de ese momento (4K, 1080p para jugar, la de la Legion Go). Los círculos se dibujan con
Pillow, suavizados (los de Tk salen dentados en Windows); las esquinas de la ventana las redondea Windows 11.
"""

from __future__ import annotations

import ctypes
import logging
import queue
import sys
import threading
import time

log = logging.getLogger(__name__)

# Paleta del tema Orbital (styles/themes/orbital.css)
BG = "#1e1e23"  # --color-surface-raised (--palette-ink-800)
TEXT = "#f5f4f0"  # --color-text
MUTED = "#a3a3ab"  # --color-text-muted
TRACK = "#2c2c32"
FILL = "#f0574d"  # el acento de la marca: la barra y el número del jugador
WARN = "#f4c24d"  # --color-warning (--palette-amber-300)
HAIRLINE = "#2f2f34"  # --color-hairline (blanco al 9 %) sobre el fondo

# Acción (cerrar): px lógicos (se escalan con el DPI), abajo al centro.
WIDTH, HEIGHT = 560, 128
PAD = 28
BAR = 6
FROM_TOP = .78  # dónde va su centro, en fracción del alto de la pantalla
# Notificación: arriba a la derecha, como toast.css (debajo de la barra de estado, al margen de la página).
TOAST_HEIGHT = 84
TOAST_MIN, TOAST_MAX = 340, 720  # px lógicos: tan ancha como su texto, entre estos dos
TOAST_TOP = .07  # fracción del alto de la pantalla
TOAST_RIGHT = .035  # fracción del ancho: el margen de la página
ICON = 48  # px lógicos del círculo del ícono
SLIDE = 28  # px lógicos que se desliza al entrar (y al irse); con «Reducir movimiento», solo el fundido
# Por tiempo, con las curvas de la interfaz de Orbital: entra rápido y se asienta suave; se va acelerando hacia afuera.
ENTER_MS, EXIT_MS = 320, 200
POP_MS, POP_DELAY_MS = 420, 70  # el número del jugador crece un poco de más y se acomoda, ya con la tarjeta en su lugar
POP_FRAMES = 12
OPAQUE = 0.97


def ease_out(p: float) -> float:
    """Arranca rápido y se asienta (quíntica): la entrada."""
    return 1 - (1 - p) ** 5


def ease_in(p: float) -> float:
    """Arranca despacio y se va acelerando (cúbica): la salida."""
    return p ** 3


def ease_back(p: float) -> float:
    """Pasa un poco de su tamaño y regresa: el «pop» del número."""
    c1 = 1.70158
    return 1 + (c1 + 1) * (p - 1) ** 3 + c1 * (p - 1) ** 2


def screen_rect() -> tuple[int, int, int, int]:
    """(x, y, ancho, alto) de la pantalla principal AHORA, en las mismas unidades que la ventana. GetSystemMetrics se
    quedaba con el tamaño de cuando arrancó Orbital: con la tele bajada a 1080p para jugar (display.py) el aviso se
    calculaba para 4K y quedaba fuera de la pantalla (y = 1556 en una de 1080, visto el 2026-10-26)."""

    class _Rect(ctypes.Structure):
        _fields_ = [("left", ctypes.c_long), ("top", ctypes.c_long), ("right", ctypes.c_long), ("bottom", ctypes.c_long)]

    class _Info(ctypes.Structure):
        _fields_ = [("cbSize", ctypes.c_ulong), ("rcMonitor", _Rect), ("rcWork", _Rect), ("dwFlags", ctypes.c_ulong)]

    user32 = ctypes.windll.user32
    user32.MonitorFromPoint.restype = ctypes.c_void_p
    monitor = user32.MonitorFromPoint(ctypes.c_longlong(0), 1)  # MONITOR_DEFAULTTOPRIMARY
    info = _Info()
    info.cbSize = ctypes.sizeof(info)
    if monitor and user32.GetMonitorInfoW(ctypes.c_void_p(monitor), ctypes.byref(info)):
        r = info.rcMonitor
        return r.left, r.top, r.right - r.left, r.bottom - r.top
    return 0, 0, user32.GetSystemMetrics(0), user32.GetSystemMetrics(1)


def _circle_image(text: str, size: int, tone: str, grow: float = 1.0):
    """El ícono de la notificación: el número del jugador en un círculo del acento, o «!» en uno ámbar tenue (como el
    ícono de los avisos de advertencia de Orbital). Dibujado al cuádruple con Pillow y reducido: suave. `grow`: su tamaño
    dentro del lugar del ícono (el «pop» de la entrada). None sin Pillow."""
    try:
        from PIL import Image, ImageDraw, ImageFont, ImageTk
    except ImportError:
        return None
    big = size * 4
    image = Image.new("RGBA", (big, big), BG)
    draw = ImageDraw.Draw(image)
    r = big / 2 * max(.05, min(1.12, grow)) / 1.12  # a 1.12 llena el lugar: el pop no se sale
    box = (big / 2 - r, big / 2 - r, big / 2 + r - 1, big / 2 + r - 1)
    if tone == "warn":
        draw.ellipse(box, fill=_mix(WARN, BG, .18))
        ink = WARN
    else:
        draw.ellipse(box, fill=FILL)
        ink = TEXT
    try:
        font = ImageFont.truetype("segoeuib.ttf", max(1, int(r * .96)))
    except OSError:
        font = ImageFont.load_default()
    draw.text((big / 2, big / 2), text, fill=ink, font=font, anchor="mm")
    return ImageTk.PhotoImage(image.resize((size, size), Image.LANCZOS))


def _mix(color: str, base: str, amount: float) -> str:
    """`amount` de `color` sobre `base` (como color-mix de CSS)."""
    a = [int(color[i:i + 2], 16) for i in (1, 3, 5)]
    b = [int(base[i:i + 2], 16) for i in (1, 3, 5)]
    return "#" + "".join(f"{round(x * amount + y * (1 - amount)):02x}" for x, y in zip(a, b, strict=True))


class GameOverlay:
    def __init__(self, reduce_motion=lambda: False) -> None:
        self.reduce_motion = reduce_motion  # Ajustes › Pantalla › Reducir movimiento: sin el deslizamiento
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
        `tone`: «ok» (el acento) o «warn» (ámbar)."""
        self._commands.put(("notice", title, detail, int(seconds * 1000), badge, tone))

    def closing(self, title: str, detail: str = "") -> None:
        self._commands.put(("closing", title, detail))

    def hide(self, delay_ms: int = 0) -> None:
        self._commands.put(("hide", delay_ms))

    # ------------------------------------------------------------- hilo de Tk
    def _run(self) -> None:
        try:
            ctypes.windll.shcore.SetProcessDpiAwareness(2)  # nítido en la pantalla de la Legion Go
        except (AttributeError, OSError):
            pass
        import tkinter as tk
        import tkinter.font as tkfont

        root = tk.Tk()
        root.withdraw()
        root.overrideredirect(True)
        root.configure(bg=BG)
        root.attributes("-topmost", True)
        root.attributes("-alpha", 0.0)
        scale = root.winfo_fpixels("1i") / 96
        px = lambda value: int(value * scale)  # noqa: E731 - px lógicos → de pantalla
        pad, slide, icon = px(PAD), px(SLIDE), px(ICON)

        canvas = tk.Canvas(root, width=px(WIDTH), height=px(HEIGHT), bg=BG, highlightthickness=0, bd=0)
        canvas.pack()
        border = canvas.create_rectangle(0, 0, 1, 1, outline=HAIRLINE, width=1)  # borde fino, como las hojas de Orbital
        title_font = tkfont.Font(root, family="Segoe UI Variable Display Semibold", size=17)
        detail_font = tkfont.Font(root, family="Segoe UI Variable Text", size=11)
        toast_title = tkfont.Font(root, family="Segoe UI Variable Text Semibold", size=14)
        toast_detail = tkfont.Font(root, family="Segoe UI Variable Text", size=11)
        title = canvas.create_text(0, 0, anchor="nw", fill=TEXT, text="")
        detail = canvas.create_text(0, 0, anchor="nw", fill=MUTED, text="")
        badge = canvas.create_image(0, 0, anchor="w")
        art: dict = {}  # las imágenes de Tk se pierden si nadie las guarda (el ícono y los cuadros del pop)
        bar_h = max(3, px(BAR))
        track = canvas.create_rectangle(0, 0, 0, 0, fill=TRACK, width=0)
        fill = canvas.create_rectangle(0, 0, 0, 0, fill=FILL, width=0)
        hwnd = _hwnd(root)
        _style_window(hwnd)
        # Para Tk queda "mostrada" (así no la vuelve a activar), pero Windows la esconde de verdad mientras no se usa
        # (_hide): una ventana por capas encima de un juego a pantalla completa obliga a DWM a componer cada cuadro (más
        # memoria de DWM y más batería). Mostrarla es SW_SHOWNOACTIVATE: nunca le quita el foco al juego.
        root.deiconify()
        _hide(hwnd)
        state = {"start": 0.0, "duration": 1.0, "filling": False, "alpha": 0.0, "hide_at": None, "offset": 0.0,
                 "base": (0, 0), "size": (px(WIDTH), px(HEIGHT)), "kind": "action", "anim": None, "pop": None}

        def fit(text: str, font, room: int) -> str:
            """Un renglón: un texto largo se corta con «…» en vez de salirse."""
            if font.measure(text) <= room:
                return text
            while text and font.measure(text + "…") > room:
                text = text[:-1]
            return text.rstrip() + "…"

        def resize(w: int, h: int) -> None:
            state["size"] = (w, h)
            canvas.config(width=w, height=h)
            canvas.coords(border, 0, 0, w - 1, h - 1)

        def place(offset: float = 0.0) -> None:
            """En la pantalla de AHORA (ver screen_rect): la notificación arriba a la derecha, la acción abajo al centro.
            `offset`: cuánto le falta por deslizarse (hacia la derecha la notificación, hacia abajo la acción)."""
            sx, sy, sw, sh = screen_rect()
            w, h = state["size"]
            if state["kind"] == "toast":
                state["base"] = (sx + sw - w - int(sw * TOAST_RIGHT), sy + int(sh * TOAST_TOP))
            else:
                state["base"] = (sx + (sw - w) // 2, sy + int(sh * FROM_TOP) - h // 2)
            move(offset)

        def move(offset: float) -> None:
            state["offset"] = offset
            bx, by = state["base"]
            w, h = state["size"]
            dx, dy = (int(offset), 0) if state["kind"] == "toast" else (0, int(offset))
            root.geometry(f"{w}x{h}+{bx + dx}+{by + dy}")

        def animate(to_offset: float, to_alpha: float, ms: int, curve) -> None:
            """De donde esté ahora a (to_offset, to_alpha) en `ms`, con esa curva."""
            state["anim"] = (time.monotonic(), ms / 1000, state["offset"], to_offset, state["alpha"], to_alpha, curve)

        def enter() -> None:
            """Aparece: se desliza a su lugar mientras se funde (desde donde esté, si ya se veía)."""
            still = self.reduce_motion()
            place(0 if still or state["alpha"] > 0 else slide)
            _raise_no_activate(hwnd)
            animate(0, OPAQUE, ENTER_MS, ease_out)

        def leave() -> None:
            animate(0 if self.reduce_motion() else slide * .6, 0.0, EXIT_MS, ease_in)

        def set_progress(fraction: float) -> None:
            w, h = state["size"]
            bar_y = h - pad - bar_h
            canvas.coords(track, pad, bar_y, w - pad, bar_y + bar_h)
            canvas.coords(fill, pad, bar_y, pad + (w - 2 * pad) * min(1.0, max(0.0, fraction)), bar_y + bar_h)

        def as_action(text: str, sub: str) -> None:
            state["kind"] = "action"
            resize(px(WIDTH), px(HEIGHT))
            canvas.itemconfigure(badge, state="hidden")
            for item in (track, fill):
                canvas.itemconfigure(item, state="normal")
            canvas.itemconfigure(title, font=title_font, text=fit(text, title_font, px(WIDTH) - 2 * pad))
            canvas.itemconfigure(detail, font=detail_font, text=fit(sub, detail_font, px(WIDTH) - 2 * pad))
            canvas.coords(title, pad, pad - px(4))
            canvas.coords(detail, pad, pad + px(32))

        def as_toast(text: str, sub: str, mark: str, tone: str) -> None:
            state["kind"] = "toast"
            for item in (track, fill):
                canvas.itemconfigure(item, state="hidden")
            image = _circle_image(mark, icon, tone) if mark else None
            # El «pop» del número: sus cuadros se dibujan una vez aquí (en la animación solo se cambian).
            frames = [] if image is None or self.reduce_motion() else \
                [_circle_image(mark, icon, tone, ease_back(i / (POP_FRAMES - 1)) * 1.12) for i in range(POP_FRAMES)]
            art["frames"] = frames
            state["pop"] = time.monotonic() + POP_DELAY_MS / 1000 if frames else None
            inner = px(18)
            left = inner + (icon + px(16) if image is not None else px(8))
            words = max(toast_title.measure(text), toast_detail.measure(sub))
            w = max(px(TOAST_MIN), min(px(TOAST_MAX), left + words + px(28)))
            h = px(TOAST_HEIGHT)
            resize(w, h)
            room = w - left - px(28)
            if image is not None:
                art["icon"] = image
                canvas.itemconfigure(badge, image=frames[0] if frames else image, state="normal")
                canvas.coords(badge, inner, h // 2)
            else:
                canvas.itemconfigure(badge, state="hidden")
            canvas.itemconfigure(title, font=toast_title, text=fit(text, toast_title, room))
            canvas.itemconfigure(detail, font=toast_detail, text=fit(sub, toast_detail, room))
            two = bool(sub)
            canvas.coords(title, left, h // 2 - (px(24) if two else px(12)))
            canvas.coords(detail, left, h // 2 + px(2))

        def handle(cmd) -> None:
            kind = cmd[0]
            if kind == "notice":
                _, text, sub, duration, mark, tone = cmd
                as_toast(text, sub, mark, tone)
                state.update(filling=False, hide_at=time.monotonic() + duration / 1000)
                enter()
            elif kind == "show":
                _, text, sub, duration = cmd
                as_action(text, sub)
                state.update(start=time.monotonic(), duration=max(duration, 1) / 1000, filling=True, hide_at=None)
                set_progress(0)
                enter()
            elif kind == "closing":
                as_action(cmd[1], cmd[2])
                state["filling"] = False
                set_progress(1)
                place(state["offset"])
            elif kind == "hide":
                state["hide_at"] = time.monotonic() + cmd[1] / 1000
                state["filling"] = False

        def tick() -> None:
            while True:
                try:
                    handle(self._commands.get_nowait())
                except queue.Empty:
                    break
            now = time.monotonic()
            if state["hide_at"] is not None and now >= state["hide_at"]:
                state["hide_at"] = None
                leave()
            anim = state["anim"]
            if anim is not None:  # deslizar y fundir a la vez, por tiempo y con su curva
                t0, length, off0, off1, a0, a1, curve = anim
                p = min(1.0, (now - t0) / length)
                e = curve(p)
                move(off0 + (off1 - off0) * e)
                state["alpha"] = a0 + (a1 - a0) * e
                root.attributes("-alpha", state["alpha"])
                if p >= 1:
                    state["anim"] = None
                    if a1 == 0:
                        _hide(hwnd)  # terminó de irse: fuera de la pantalla hasta la próxima
            pop = state["pop"]
            if pop is not None and now >= pop and art.get("frames"):
                frames = art["frames"]
                i = min(len(frames) - 1, int((now - pop) / (POP_MS / 1000) * len(frames)))
                canvas.itemconfigure(badge, image=frames[i])
                if i == len(frames) - 1:
                    state["pop"] = None
            if state["filling"]:
                set_progress((now - state["start"]) / state["duration"])
            # 60 vueltas por segundo solo mientras se ve; escondida, 10: una orden nueva tarda a lo mucho 100 ms en
            # notarse (el aviso de cerrar sale a los 250 ms de mantener el atajo) y no gasta CPU sin parar.
            busy = state["alpha"] > 0 or state["anim"] is not None or state["filling"]
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
    try:  # Windows 11: esquinas redondeadas nativas (suavizadas)
        corner = ctypes.c_int(2)  # DWMWCP_ROUND
        ctypes.windll.dwmapi.DwmSetWindowAttribute(hwnd, 33, ctypes.byref(corner), ctypes.sizeof(corner))
    except (AttributeError, OSError):
        pass


def _raise_no_activate(hwnd: int) -> None:
    """Visible y encima de todo (también del juego en pantalla completa sin bordes), sin activarla."""
    ctypes.windll.user32.ShowWindow(hwnd, SW_SHOWNOACTIVATE)
    ctypes.windll.user32.SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOSIZE | SWP_NOMOVE | SWP_NOACTIVATE)


def _hide(hwnd: int) -> None:
    """La quita de la pantalla (ya con opacidad 0) para que no estorbe a DWM ni al juego."""
    ctypes.windll.user32.ShowWindow(hwnd, SW_HIDE)
