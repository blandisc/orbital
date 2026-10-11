"""Ventanas y foco: la pantalla de carga encima del emulador y pasar el juego al frente.

Todo lo que habla con las ventanas de Windows al abrir algo: fijar Orbital encima mientras el
emulador abre, reconocer cuándo el juego ya está listo y fundir Orbital sobre él.
"""

from __future__ import annotations

import logging
import sys
import threading
import time

from .launcher import Launcher
from .text import normalize

log = logging.getLogger(__name__)


def bring_app_to_front(exe: str, timeout: float = 10.0, fullscreen: bool = False) -> bool:
    """Espera la ventana de `exe` y la trae al frente (Windows). Con `fullscreen`, además la pone
    en pantalla completa (F11) si aún no lo está: F11 alterna, por eso primero se mide."""
    if sys.platform != "win32":
        return False
    from . import windows

    deadline = time.time() + timeout
    time.sleep(.8)  # que alcance a navegar al enlace antes de mostrarse
    while time.time() < deadline:
        hwnd = windows.main_window(windows.pids_by_exe(exe))
        if hwnd and windows.focus(hwnd):
            if fullscreen:
                time.sleep(1.5)  # que el reproductor termine de abrir
                if windows.foreground() == hwnd and not windows.is_fullscreen(hwnd):
                    from .gamepad import VK_F11, send_key
                    send_key(VK_F11)
            return True
        time.sleep(.4)
    return False


ORBITAL_BROWSERS = {"msedge.exe", "chrome.exe", "chromium.exe"}


READY_TIMEOUT = 25.0  # s máximos con la pantalla de carga de Orbital encima
READY_SETTLE = .6  # s tras detectar el juego: que pinte sus primeros cuadros
FADE_TO_BLACK = .75  # s de la salida de la pantalla de carga (el "salto" al juego) antes del fundido


def _words(text: str) -> set[str]:
    return {w for w in normalize(text).split() if len(w) >= 3}


def game_ready(windows: list[tuple[str, bool]], title: str, runner: str | None = None) -> bool:
    """¿Ya está el juego (no la lista del emulador ni su ventana de carga)? Lo está si alguna ventana
    ocupa toda la pantalla o su título nombra al juego ("Eden | Mario Party Superstars")."""
    wanted = _words(title) - _words(runner or "")
    # Xenia se pone en pantalla completa antes de cargar el juego: ahí solo cuenta que su título ya lo
    # nombre ("Xenia… | COD: Black Ops II <415608C3>").
    fullscreen_counts = "xenia" not in normalize(runner or "")
    for win_title, fullscreen in windows:
        if fullscreen and fullscreen_counts:
            return True
        found = _words(win_title)
        if wanted and len(wanted & found) >= max(1, round(len(wanted) * .6)):
            return True
    return False


def is_orbital_window(win, hwnd: int) -> bool:
    return bool(hwnd) and "Orbital" in win.title(hwnd) and win.exe_name(win.pid_of(hwnd)) in ORBITAL_BROWSERS


def pin_orbital(win=None) -> int:
    """Orbital "siempre encima" ANTES de lanzar el emulador (antes se fijaba un instante después y
    la ventana del emulador alcanzaba a asomarse). Solo si Orbital está al frente. Devuelve su ventana."""
    if win is None:
        if sys.platform != "win32":
            return 0
        from . import windows as win
    fg = win.foreground()
    return fg if is_orbital_window(win, fg) and win.set_topmost(fg, True) else 0


FULLSCREEN_GRACE = 4.0  # s: el juego ya cargó (su nombre en la ventana) pero aún no ocupa la pantalla
REVEAL_FADE = (210, 160, 110, 60, 20, 0)  # opacidad de Orbital al fundirse sobre el juego


def bring_game_to_front(launcher: Launcher, item_id: str, title: str = "", runner: str | None = None,
                        notify=None, skip: threading.Event | None = None, timeout: float = READY_TIMEOUT,
                        win=None, sleep=time.sleep, pinned: int | None = None, ready_check=None) -> bool:
    """Pantalla de carga hasta que el juego esté listo, y luego un fundido de Orbital al juego.

    Mientras el emulador abre se ven sus ventanas feas (la lista de juegos de Eden, una consola…).
    Si Orbital está al frente, se queda ENCIMA (topmost) con su pantalla de carga hasta que el juego
    está listo Y en pantalla completa (si no, se veía el emulador brincar de ventana a pantalla
    completa). Entonces la pantalla de carga hace su salida (evento launch-ready), el juego pasa al
    frente DEBAJO de Orbital y Orbital se funde hasta desaparecer: del cohete al juego, sin cortes.
    Si ya estás en otra cosa, no se pelea por el foco. `skip`: B en la pantalla de carga.
    `pinned`: la ventana de Orbital ya fijada encima antes de lanzar (pin_orbital).
    `ready_check()`: otra señal de "listo" (el reproductor: hasta la primera imagen, no una ventana negra)."""
    if win is None:
        if sys.platform != "win32":
            return False
        from . import windows as win
    notify = notify or (lambda event: None)
    orbital = pin_orbital(win) if pinned is None else pinned
    target = 0
    started = time.time()
    grace = int(FULLSCREEN_GRACE / .3)
    try:
        deadline = time.time() + timeout
        while time.time() < deadline and not (skip and skip.is_set()):
            status = launcher.status()
            if not status or status.get("id") != item_id:
                return False  # se cerró (o truena) o se abrió otra cosa: Orbital se queda
            pids = win.process_tree(status["pid"]) if status.get("pid") else set()
            hwnds = win.windows_of(pids) if pids else []
            if ready_check is not None:
                if hwnds and ready_check():
                    target = hwnds[0]
                    log.info("%s listo tras %.1f s", title, time.time() - started)
                    break
                sleep(.3)
                continue
            if hwnds:
                target = hwnds[0]
                info = [(win.title(h), win.is_fullscreen(h)) for h in hwnds]
                ready = next((h for h, i in zip(hwnds, info) if game_ready([i], title, runner)), 0)
                if ready and orbital and not win.is_fullscreen(ready) and grace > 0:
                    grace -= 1  # cargó, pero quizá está por pasar a pantalla completa: un momento
                    target = ready
                    sleep(.3)
                    continue
                if ready or not orbital:
                    target = ready or target
                    if ready:
                        log.info("%s listo tras %.1f s: %s", title, time.time() - started, win.title(ready))
                    break
            sleep(.3)
        if orbital and not (skip and skip.is_set()) and time.time() >= deadline:
            log.info("%s sin señal de listo en %.0f s: se muestra igual", title, timeout)
        if not target:
            status = launcher.status()
            pids = win.process_tree(status["pid"]) if status and status.get("pid") else set()
            target = win.main_window(pids) if pids else 0
        if orbital:
            settle(win, target, sleep)
            notify({"type": "launch-ready", "id": item_id})  # la pantalla de carga hace su salida
            sleep(FADE_TO_BLACK)
            if target and win.foreground() != target:
                win.focus(target)  # el juego al frente, aún debajo de Orbital (que sigue encima)
            fade = getattr(win, "set_alpha", None)
            if fade and target:
                for alpha in REVEAL_FADE:  # Orbital se funde y aparece el juego
                    fade(orbital, alpha)
                    sleep(.04)
    finally:
        if orbital:
            win.set_topmost(orbital, False)
            fade = getattr(win, "set_alpha", None)
            if fade:
                fade(orbital, None)  # vuelve a ser opaca (ya detrás del juego)
    if not target:
        return False
    fg = win.foreground()
    if fg == target:
        return True
    return is_orbital_window(win, fg) and win.focus(target)


def settle(win, hwnd: int, sleep, tries: int = 8) -> None:
    """Espera a que la ventana del juego deje de cambiar de tamaño (dos lecturas iguales seguidas)."""
    rect_of = getattr(win, "window_rect", None)
    if not rect_of or not hwnd:
        sleep(READY_SETTLE)
        return
    last = rect_of(hwnd)
    for _ in range(tries):
        sleep(READY_SETTLE / 3)
        now = rect_of(hwnd)
        if now == last:
            return
        last = now
