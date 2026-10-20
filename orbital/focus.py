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
# La entrada de la pantalla de carga (la portada vuela, el anillo se dibuja) dura casi 2 s. xemu abre a pantalla completa
# desde el primer instante y contaba como listo en 1 s: la salida cortaba la entrada a medias y se veía trabada.
MIN_LOADING = 2.0
# xemu arranca la consola en negro varios segundos antes de la primera imagen del juego (2,5–5 s medidos): con su ventana ya
# a pantalla completa contaba como listo y se veía ese negro. Con estos, se espera a que su ventana tenga imagen (con tope).
PICTURE_RUNNERS = ("xemu",)
PICTURE_WAIT = 12.0  # s más, como mucho: un juego que de verdad arranca en negro se enseña igual


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
# Tras la transición, el juego se cuida unos segundos: si el emulador recrea su ventana (xemu, Eden al
# pasar a pantalla completa) o mpv cambia de modo, Windows le regresaba el foco a Orbital.
FOCUS_TRIES = 8  # x .25 s: dos segundos para que Windows dé el foco al juego o al video
GUARD_SECONDS = 15.0


def keep_game_in_front(launcher: Launcher, item_id: str, win, user_returned=lambda: False,
                       seconds: float = GUARD_SECONDS, sleep=time.sleep, clock=time.monotonic) -> int:
    """Durante `seconds` tras mostrar el juego, si Orbital vuelve al frente sin que lo pidieras
    (Home, Legion L), el juego regresa al frente. Devuelve cuántas veces lo regresó."""
    fixed = 0
    end = clock() + seconds
    while clock() < end:
        sleep(.3)
        status = launcher.status()
        if not status or status.get("id") != item_id or user_returned():
            break  # se cerró, se abrió otra cosa o tú volviste a Orbital: ya no es asunto del vigilante
        fg = win.foreground()
        seen = win.window_at_center() if hasattr(win, "window_at_center") else fg
        # Orbital tapa al juego si tiene el foco, o si se VE encima aunque el foco lo tenga el juego.
        orbital = fg if is_orbital_window(win, fg) else seen if is_orbital_window(win, seen) else 0
        if not orbital:
            continue
        pids = win.process_tree(status["pid"]) if status.get("pid") else set()
        game = win.main_window(pids) if pids else 0
        if not game:
            continue
        if orbital != fg and not getattr(win, "covers_center", lambda h: True)(game):
            continue  # el juego (o el video) en ventana: Orbital se ve alrededor, no encima
        if hasattr(win, "place_below"):
            win.place_below(orbital, game)
        if (fg == game or win.focus(game)) and not fixed:
            log.info("Orbital tapó a %s tras la transición: el juego vuelve al frente", status.get("title", item_id))
        fixed += 1
    return fixed


def bring_game_to_front(launcher: Launcher, item_id: str, title: str = "", runner: str | None = None,
                        notify=None, skip: threading.Event | None = None, timeout: float = READY_TIMEOUT,
                        win=None, sleep=time.sleep, pinned: int | None = None, ready_check=None,
                        user_returned=None, clock=time.time) -> bool:
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
    started = clock()
    grace = int(FULLSCREEN_GRACE / .3)
    wants_picture = any(r in normalize(runner or "") for r in PICTURE_RUNNERS) and hasattr(win, "has_picture")
    picture_until = None
    pictures = 0  # lecturas seguidas con imagen: al pasar a pantalla completa xemu suelta un cuadro suelto que no es el juego
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
                ready = next((h for h, i in zip(hwnds, info, strict=False) if game_ready([i], title, runner)), 0)
                if ready and orbital and not win.is_fullscreen(ready) and grace > 0:
                    grace -= 1  # cargó, pero quizá está por pasar a pantalla completa: un momento
                    target = ready
                    sleep(.3)
                    continue
                if ready and orbital and wants_picture:
                    pictures = pictures + 1 if win.has_picture(ready) is not False else 0
                    picture_until = picture_until or time.time() + PICTURE_WAIT
                    if pictures < 2 and time.time() < picture_until:
                        target = ready  # ya a pantalla completa, pero todavía en negro: la pantalla de carga sigue
                        sleep(.3)
                        continue
                    if pictures < 2:
                        log.info("%s sin imagen en %.0f s: se muestra igual", title, PICTURE_WAIT)
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
            early = MIN_LOADING - (clock() - started)
            if early > 0 and not (skip and skip.is_set()):
                sleep(early)  # que la entrada termine antes de la salida
            notify({"type": "launch-ready", "id": item_id})  # la pantalla de carga hace su salida
            sleep(FADE_TO_BLACK)
            if target and win.foreground() != target:
                win.focus(target)  # el juego al frente, aún debajo de Orbital (que sigue encima)
            # Del negro de la pantalla de carga al juego, sin fundir la ventana de Orbital encima: volverla
            # transparente (estilo de capa) sobre un juego a pantalla completa hacía crecer la memoria con la que
            # Windows dibuja las ventanas (DWM) cientos de MB en cada apertura y regreso, sin soltarla.
    finally:
        if orbital:
            win.set_topmost(orbital, False)
            if target and hasattr(win, "place_below"):
                # Sin "siempre encima", Windows deja a Orbital arriba de las ventanas normales: encima
                # del juego aunque el juego tenga el foco. Se manda detrás.
                win.place_below(orbital, target)
    if not target:
        return False
    fg = win.foreground()
    shown = fg == target
    # Windows a veces niega el foco a la primera: el video se veía al frente, pero el mando y el teclado
    # seguían hablándole a Orbital (detrás). Se reintenta unos segundos.
    for _ in range(FOCUS_TRIES):
        if shown or not is_orbital_window(win, win.foreground()):
            break
        shown = win.focus(target)
        if not shown:
            sleep(.25)
    if user_returned is not None:  # aunque no se pudiera a la primera: el vigilante lo sigue intentando
        keep_game_in_front(launcher, item_id, win, user_returned, sleep=sleep)
    return shown or win.foreground() == target


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
