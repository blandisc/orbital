"""Aviso encima del juego: "Mantén Select + Start para cerrar".

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

WIDTH, HEIGHT = 440, 116  # px lógicos (se escalan con el DPI)
PAD = 26
BAR = 4
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

    def closing(self, title: str) -> None:
        self._commands.put(("closing", title))

    def hide(self, delay_ms: int = 0) -> None:
        self._commands.put(("hide", delay_ms))

    # ------------------------------------------------------------- hilo de Tk
    def _run(self) -> None:
        try:
            ctypes.windll.shcore.SetProcessDpiAwareness(2)  # nítido en la pantalla de la Legion Go
        except (AttributeError, OSError):
            pass
        import tkinter as tk

        root = tk.Tk()
        root.withdraw()
        root.overrideredirect(True)
        root.configure(bg=BG)
        root.attributes("-topmost", True)
        root.attributes("-alpha", 0.0)
        scale = root.winfo_fpixels("1i") / 96
        w, h, pad = int(WIDTH * scale), int(HEIGHT * scale), int(PAD * scale)
        x = (root.winfo_screenwidth() - w) // 2
        y = (root.winfo_screenheight() - h) // 2
        root.geometry(f"{w}x{h}+{x}+{y}")

        canvas = tk.Canvas(root, width=w, height=h, bg=BG, highlightthickness=0, bd=0)
        canvas.pack()
        title_font = ("Segoe UI Variable Display Semibold", 15)
        detail_font = ("Segoe UI Variable Text", 11)
        title = canvas.create_text(pad, pad, anchor="nw", fill=TEXT, font=title_font, text="")
        detail = canvas.create_text(pad, pad + int(32 * scale), anchor="nw", fill=MUTED, font=detail_font, text="")
        bar_y = h - pad - int(BAR * scale)
        bar_h = max(2, int(BAR * scale))
        canvas.create_rectangle(pad, bar_y, w - pad, bar_y + bar_h, fill=TRACK, width=0)
        fill = canvas.create_rectangle(pad, bar_y, pad, bar_y + bar_h, fill=FILL, width=0)

        hwnd = _hwnd(root)
        _style_window(hwnd)
        # Siempre "visible" pero con opacidad 0 y sin recibir clics: mostrarla es solo subir la
        # opacidad, sin ShowWindow (que activaría la ventana y le quitaría el foco al juego).
        root.deiconify()
        state = {"start": 0.0, "duration": 1.0, "filling": False, "alpha": 0.0, "target": 0.0, "hide_at": None}

        def set_progress(fraction: float) -> None:
            canvas.coords(fill, pad, bar_y, pad + (w - 2 * pad) * min(1.0, max(0.0, fraction)), bar_y + bar_h)

        def handle(cmd) -> None:
            kind = cmd[0]
            if kind == "show":
                _, text, sub, duration = cmd
                canvas.itemconfigure(title, text=text)
                canvas.itemconfigure(detail, text=sub)
                state.update(start=time.monotonic(), duration=max(duration, 1) / 1000, filling=True, target=0.97, hide_at=None)
                set_progress(0)
                _raise_no_activate(hwnd)
            elif kind == "closing":
                canvas.itemconfigure(title, text=cmd[1])
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
            root.after(16, tick)

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
    """Encima de todo (también del juego en pantalla completa sin bordes), sin activarla."""
    ctypes.windll.user32.SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOSIZE | SWP_NOMOVE | SWP_NOACTIVATE)
