"""Aviso encima del juego mientras se mantiene el atajo de cerrar (Start + Select + Home; GameSir: LB + RB + Select):
el juego en grande, qué mantener y una barra que se llena. También avisos breves sin barra («Control GameSir conectado ·
Jugador 2»): con un juego al frente, la ventana de Orbital no se ve.

Una ventana pequeña, centrada, siempre visible y que NO toma el foco: el juego sigue
recibiendo el mando. Se dibuja con Tkinter (viene con Python) en su propio hilo.
Las órdenes llegan por una cola; el hilo de Tk las atiende ~60 veces por segundo.

Una barra recta en lugar de un anillo: Tk en Windows no suaviza círculos y se verían dentados.
"""

from __future__ import annotations

import ctypes
import logging
import queue
import sys
import threading
import time

log = logging.getLogger(__name__)

# Paleta del tema Orbital (styles/tokens.css)
BG = "#18181c"
TEXT = "#f5f4f0"
MUTED = "#a3a3ab"
TRACK = "#2c2c32"
FILL = "#f0574d"
HAIRLINE = "#34343b"

# px lógicos (se escalan con el DPI). Ancho para títulos largos; abajo al centro (como los avisos de las consolas),
# no en medio del juego.
WIDTH, HEIGHT = 560, 128
PAD = 28
BAR = 6
FROM_TOP = .78  # dónde va su centro, en fracción del alto de la pantalla
FADE_MS = 140
RISE = 22  # px lógicos que sube el aviso breve al entrar (y baja al irse); con «Reducir movimiento», solo el fundido
BADGE = 56  # px lógicos del círculo con el número del jugador


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


def _badge_image(text: str, size: int, fill: str, ink: str):
    """El círculo con el número del jugador, suavizado (los óvalos de Tk salen dentados en Windows): se dibuja al
    cuádruple con Pillow y se reduce. None sin Pillow."""
    try:
        from PIL import Image, ImageDraw, ImageFont, ImageTk
    except ImportError:
        return None
    big = size * 4
    image = Image.new("RGBA", (big, big), BG)
    draw = ImageDraw.Draw(image)
    draw.ellipse((0, 0, big - 1, big - 1), fill=fill)
    try:
        font = ImageFont.truetype("segoeuib.ttf", int(big * .5))
    except OSError:
        font = ImageFont.load_default()
    draw.text((big / 2, big / 2), text, fill=ink, font=font, anchor="mm")
    return ImageTk.PhotoImage(image.resize((size, size), Image.LANCZOS))


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
        self._commands.put(("show", title, detail, duration_ms))

    def notice(self, title: str, detail: str = "", seconds: float = 3.5, badge: str = "") -> None:
        """Un aviso breve, sin barra, que se va solo; con `badge`, un círculo con ese número a la izquierda (el jugador)."""
        self._commands.put(("notice", title, detail, int(seconds * 1000), badge))

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
        w, h, pad = int(WIDTH * scale), int(HEIGHT * scale), int(PAD * scale)
        sx, sy, sw, sh = screen_rect()
        root.geometry(f"{w}x{h}+{sx + (sw - w) // 2}+{sy + int(sh * FROM_TOP) - h // 2}")
        rise = int(RISE * scale)
        badge_size = int(BADGE * scale)

        canvas = tk.Canvas(root, width=w, height=h, bg=BG, highlightthickness=0, bd=0)
        canvas.pack()
        canvas.create_rectangle(0, 0, w - 1, h - 1, outline=HAIRLINE, width=1)  # borde fino, como las hojas de Orbital
        title_font = tkfont.Font(root, family="Segoe UI Variable Display Semibold", size=17)
        detail_font = tkfont.Font(root, family="Segoe UI Variable Text", size=11)
        title = canvas.create_text(pad, pad - int(4 * scale), anchor="nw", fill=TEXT, font=title_font, text="")
        detail = canvas.create_text(pad, pad + int(32 * scale), anchor="nw", fill=MUTED, font=detail_font, text="")
        badge = canvas.create_image(pad, h // 2, anchor="w")
        badge_art: dict[str, object] = {}  # las imágenes de Tk se pierden si nadie las guarda
        bar_h = max(3, int(BAR * scale))
        bar_y = h - pad - bar_h
        track = canvas.create_rectangle(pad, bar_y, w - pad, bar_y + bar_h, fill=TRACK, width=0)
        fill = canvas.create_rectangle(pad, bar_y, pad, bar_y + bar_h, fill=FILL, width=0)

        def fit(text: str, font, room: int | None = None) -> str:
            """Un renglón: un título largo se corta con «…» en vez de salirse de la ventana."""
            room = room if room is not None else w - 2 * pad
            if font.measure(text) <= room:
                return text
            while text and font.measure(text + "…") > room:
                text = text[:-1]
            return text.rstrip() + "…"

        hwnd = _hwnd(root)
        _style_window(hwnd)
        # Para Tk queda "mostrada" (así no la vuelve a activar), pero Windows la esconde de verdad
        # mientras no se usa (_hide): antes se quedaba siempre visible con opacidad 0 encima del
        # juego, y una ventana por capas encima de un juego a pantalla completa obliga a DWM a
        # componer cada cuadro (más memoria de DWM y más batería) en vez de dejar pasar el juego
        # directo. Mostrarla es SW_SHOWNOACTIVATE: nunca le quita el foco al juego.
        root.deiconify()
        _hide(hwnd)
        state = {"start": 0.0, "duration": 1.0, "filling": False, "alpha": 0.0, "target": 0.0, "hide_at": None,
                 "offset": 0.0, "base": (0, 0)}

        def set_progress(fraction: float) -> None:
            canvas.coords(fill, pad, bar_y, pad + (w - 2 * pad) * min(1.0, max(0.0, fraction)), bar_y + bar_h)

        def place(offset: float = 0.0) -> None:
            """Centrado abajo en la pantalla de AHORA (ver screen_rect); `offset`: cuánto más abajo (la entrada sube)."""
            sx, sy, sw, sh = screen_rect()
            state["base"] = (sx + (sw - w) // 2, sy + int(sh * FROM_TOP) - h // 2)
            move(offset)

        def move(offset: float) -> None:
            state["offset"] = offset
            bx, by = state["base"]
            root.geometry(f"{w}x{h}+{bx}+{by + int(offset)}")

        def layout(with_badge: bool) -> int:
            """Con número de jugador, el texto va a la derecha del círculo y centrado en alto; sin él, como siempre."""
            left = pad + badge_size + int(18 * scale) if with_badge else pad
            canvas.coords(title, left, h // 2 - int(26 * scale) if with_badge else pad - int(4 * scale))
            canvas.coords(detail, left, h // 2 + int(6 * scale) if with_badge else pad + int(32 * scale))
            canvas.itemconfigure(badge, state="normal" if with_badge else "hidden")
            return w - left - pad

        def handle(cmd) -> None:
            kind = cmd[0]
            if kind in ("show", "notice", "closing"):
                place()  # en la pantalla de ahora (4K, 1080p para jugar, la de la Legion…)
                bar = "hidden" if kind == "notice" else "normal"
                canvas.itemconfigure(track, state=bar)
                canvas.itemconfigure(fill, state=bar)
            if kind == "notice":
                _, text, sub, duration, number = cmd
                if number:
                    art = _badge_image(number, badge_size, FILL, TEXT)
                    if art is not None:
                        badge_art["now"] = art
                        canvas.itemconfigure(badge, image=art)
                room = layout(bool(number) and "now" in badge_art)
                canvas.itemconfigure(title, text=fit(text, title_font, room))
                canvas.itemconfigure(detail, text=fit(sub, detail_font, room))
                still = self.reduce_motion()
                place(0 if still or state["alpha"] > 0 else rise)  # entra subiendo desde un poco más abajo
                state.update(filling=False, target=0.97, hide_at=time.monotonic() + duration / 1000, rising=not still)
                _raise_no_activate(hwnd)
                return
            if kind in ("show", "closing"):
                layout(False)  # el de cerrar: sin círculo, con su barra
            if kind == "show":
                _, text, sub, duration = cmd
                canvas.itemconfigure(title, text=fit(text, title_font))
                canvas.itemconfigure(detail, text=fit(sub, detail_font))
                # La misma entrada que el aviso de «Control conectado»: sube mientras aparece (una sola familia de avisos).
                still = self.reduce_motion()
                place(0 if still or state["alpha"] > 0 else rise)
                state.update(start=time.monotonic(), duration=max(duration, 1) / 1000, filling=True, target=0.97, hide_at=None,
                             rising=not still)
                set_progress(0)
                _raise_no_activate(hwnd)
            elif kind == "closing":
                canvas.itemconfigure(title, text=fit(cmd[1], title_font))
                canvas.itemconfigure(detail, text=fit(cmd[2], detail_font))
                state["filling"] = False
                set_progress(1)
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
                state["target"], state["hide_at"] = 0.0, None
            # El aviso breve sube al entrar y baja un poco al irse, al ritmo del fundido (curva de salida suave).
            if state.get("rising"):
                goal = 0.0 if state["target"] > 0 else rise * .5
                gap = goal - state["offset"]
                if abs(gap) > .5:
                    move(state["offset"] + gap * .22)
                elif state["target"] == 0 and state["alpha"] == 0:
                    state["rising"] = False
            if state["filling"]:
                set_progress((now - state["start"]) / state["duration"])
            # Fundido de entrada/salida
            step = 16 / FADE_MS
            alpha = state["alpha"]
            if alpha != state["target"]:
                alpha = min(state["target"], alpha + step) if state["target"] > alpha else max(state["target"], alpha - step)
                state["alpha"] = alpha
                root.attributes("-alpha", alpha)
                if alpha == 0.0:
                    _hide(hwnd)  # terminó de desvanecerse: fuera de la pantalla hasta la próxima
            # 60 vueltas por segundo solo mientras se ve (la barra se llena, el fundido); escondida, 10: una orden nueva
            # tarda a lo mucho 100 ms en notarse (el aviso sale a los 250 ms de mantener el atajo) y no gasta CPU sin parar.
            root.after(16 if state["alpha"] > 0 or state["target"] > 0 or state["filling"] else 100, tick)

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
