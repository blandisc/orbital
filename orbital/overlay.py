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


class GameOverlay:
    def __init__(self) -> None:
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

    def notice(self, title: str, detail: str = "", seconds: float = 3.5) -> None:
        """Un aviso breve, sin barra, que se va solo."""
        self._commands.put(("notice", title, detail, int(seconds * 1000)))

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
        x = (root.winfo_screenwidth() - w) // 2
        y = int(root.winfo_screenheight() * FROM_TOP) - h // 2
        root.geometry(f"{w}x{h}+{x}+{y}")

        canvas = tk.Canvas(root, width=w, height=h, bg=BG, highlightthickness=0, bd=0)
        canvas.pack()
        canvas.create_rectangle(0, 0, w - 1, h - 1, outline=HAIRLINE, width=1)  # borde fino, como las hojas de Orbital
        title_font = tkfont.Font(root, family="Segoe UI Variable Display Semibold", size=17)
        detail_font = tkfont.Font(root, family="Segoe UI Variable Text", size=11)
        title = canvas.create_text(pad, pad - int(4 * scale), anchor="nw", fill=TEXT, font=title_font, text="")
        detail = canvas.create_text(pad, pad + int(32 * scale), anchor="nw", fill=MUTED, font=detail_font, text="")
        bar_h = max(3, int(BAR * scale))
        bar_y = h - pad - bar_h
        track = canvas.create_rectangle(pad, bar_y, w - pad, bar_y + bar_h, fill=TRACK, width=0)
        fill = canvas.create_rectangle(pad, bar_y, pad, bar_y + bar_h, fill=FILL, width=0)

        def fit(text: str, font) -> str:
            """Un renglón: un título largo se corta con «…» en vez de salirse de la ventana."""
            room = w - 2 * pad
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
        state = {"start": 0.0, "duration": 1.0, "filling": False, "alpha": 0.0, "target": 0.0, "hide_at": None}

        def set_progress(fraction: float) -> None:
            canvas.coords(fill, pad, bar_y, pad + (w - 2 * pad) * min(1.0, max(0.0, fraction)), bar_y + bar_h)

        def handle(cmd) -> None:
            kind = cmd[0]
            bar = "hidden" if kind == "notice" else "normal"
            canvas.itemconfigure(track, state=bar)
            canvas.itemconfigure(fill, state=bar)
            if kind == "notice":
                _, text, sub, duration = cmd
                canvas.itemconfigure(title, text=fit(text, title_font))
                canvas.itemconfigure(detail, text=fit(sub, detail_font))
                state.update(filling=False, target=0.97, hide_at=time.monotonic() + duration / 1000)
                _raise_no_activate(hwnd)
            elif kind == "show":
                _, text, sub, duration = cmd
                canvas.itemconfigure(title, text=fit(text, title_font))
                canvas.itemconfigure(detail, text=fit(sub, detail_font))
                state.update(start=time.monotonic(), duration=max(duration, 1) / 1000, filling=True, target=0.97, hide_at=None)
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
