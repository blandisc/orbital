"""La ventanita (Home durante un video), sus botones y el telón negro del arranque."""

from __future__ import annotations

import threading
import time

from .. import player_ui
from ..gamepad import (  # noqa: F401 - las pruebas los piden a player
    A_BUTTON,
    B_BUTTON,
    BACK,
    DPAD_DOWN,
    DPAD_LEFT,
    DPAD_RIGHT,
    DPAD_UP,
    GUIDE,
    LT,
    RT,
    START,
    X_BUTTON,
    Y_BUTTON,
)
from ..mpv import PIPE, Mpv  # noqa: F401 - se importan desde aquí
from ..playback import (  # noqa: F401 - el resto de Orbital y las pruebas las piden a player
    CHAPTER_SEEK,
    CREDITS,
    INTRO,
    LANGS,
    LB,
    LIVE_SETTLE,
    LIVE_STARTUP_TIMEOUT,
    LIVE_USER_AGENT,
    MOUSE_SCRIPT,
    MOUSE_SCRIPT_NAME,
    OSD_STYLE,
    RB,
    RECAP,
    SAVE_EVERY,
    SCROBBLE_SEEK,
    SKIP_VISIBLE,
    STARTUP_TIMEOUT,
    STILL_WATCHING_AFTER,
    TOUCH_BINDINGS,
    UPNEXT_AT,
    UPNEXT_COUNTDOWN,
    UPNEXT_LOOKAHEAD,
    Playback,
    PlayerRemote,
    Segment,
    base_language,
    build_command,
    build_lang_list,
    chapter_kind,
    dub_track,
    find_mpv,
    has_language,
    idle_expired,
    input_conf,
    seek_step,
    stream_url,
    subtitle_options,
    track_properties,
    wrong_audio,
)
from .base import CURTAIN_ID, PIP_CONTROLS_SECONDS, PIP_FRAME, PIP_GLIDE, PIP_MARGIN, PIP_WIDTH, glide_curve, log
from .watching import _Watching


class _Pip(_Watching):
    """La ventanita y el telón."""

    # --- el video en pequeño (PiP) ------------------------------------------------------------------------------------
    def enter_pip(self) -> bool:
        """Home durante un video: se desliza y se encoge, con calma, a la esquina de abajo a la derecha, y sigue sonando
        encima de Orbital. False si no hay video abierto."""
        current = self.current
        if current is None or current.process is None or current.process.poll() is not None:
            return False
        self.pip = True
        self.menu = None
        self._card = None
        self._lift_subs(False)
        self._try_end()
        for overlay in (1, 2, 4):  # la barra, el panel y la tarjeta no caben en la esquina
            self._overlay(overlay, None)
        threading.Thread(target=self._to_corner, args=(current,), daemon=True, name="pip").start()
        log.info("Video en pequeño: %s", current.title)
        return True

    def _window(self, current):
        from .. import windows

        return windows, windows.main_window(windows.process_tree(current.process.pid))

    def _pip_rect(self, windows) -> tuple[int, int, int, int]:
        screen_w, screen_h = windows.screen_size()
        width = int(screen_w * PIP_WIDTH)
        height = int(width * 9 / 16)
        margin = int(screen_w * PIP_MARGIN)
        return screen_w - width - margin, screen_h - height - margin, width, height

    def _glide(self, windows, hwnd, start: tuple, end: tuple, still) -> None:
        """La ventana de un lugar a otro en PIP_GLIDE segundos, con una curva que frena al llegar. Por tiempo (no por pasos)
        y sin esperar a que mpv redibuje cada uno (glide_window): antes cada paso cambiaba el tamaño y esperaba, y al
        encogerse se trababa. Mientras se mueve, el video se detiene un instante (sin decodificar mientras se redimensiona)."""
        was_paused = bool(self._value("pause"))
        if not was_paused:
            self.mpv.command("set_property", "pause", True)
            self._ask("pause", True)
        started = time.monotonic()
        try:
            while still():
                t = min(1.0, (time.monotonic() - started) / PIP_GLIDE)
                k = glide_curve(t)
                x, y, w, h = (round(a + (b - a) * k) for a, b in zip(start, end, strict=True))
                windows.glide_window(hwnd, x, y, w, h)
                if t >= 1:
                    break
                wait = getattr(windows, "wait_frame", None)  # a la par del refresco de la pantalla
                wait() if wait else time.sleep(PIP_FRAME)
        finally:
            if not was_paused:
                self.mpv.command("set_property", "pause", False)
                # Lo que se acaba de pedir: mpv lo confirma un instante después y los botones de la esquina (que se
                # dibujan justo al llegar) salían con ▶ y sin irse solos, con el video ya corriendo.
                self._ask("pause", False)

    def _to_corner(self, current) -> None:
        windows, hwnd = self._window(current)
        screen_w, screen_h = windows.screen_size()
        full = (0, 0, screen_w, screen_h)
        # Primero su tamaño de ventana = la pantalla entera: al salir de pantalla completa ya no salta al centro con
        # el tamaño de siempre (antes se veía ir al centro y luego encogerse de golpe).
        self.mpv.command("set_property", "geometry", f"{screen_w}x{screen_h}+0+0")
        for prop, value in (("border", False), ("ontop", True), ("keepaspect-window", False), ("fullscreen", False)):
            self.mpv.command("set_property", prop, value)
        windows.place_window(hwnd, *full)
        still = lambda: self.pip and self.current is current  # noqa: E731
        self._glide(windows, hwnd, full, self._pip_rect(windows), still)
        if still():
            self._show_pip_controls()

    def exit_pip(self) -> None:
        """De vuelta a pantalla completa (Volver al video): el mismo camino, de la esquina a toda la pantalla."""
        if not self.pip:
            return
        self.pip = False
        self._cancel_pip_timer()
        self._overlay(1, None)
        current = self.current
        if current is not None and current.process is not None and current.process.poll() is None:
            windows, hwnd = self._window(current)
            screen_w, screen_h = windows.screen_size()
            here = windows.window_rect(hwnd)
            start = (here[0], here[1], here[2] - here[0], here[3] - here[1]) if here else self._pip_rect(windows)
            self._glide(windows, hwnd, start, (0, 0, screen_w, screen_h), lambda: not self.pip)
        for prop, value in (("fullscreen", True), ("ontop", False), ("border", True)):
            self.mpv.command("set_property", prop, value)
        log.info("Video a pantalla completa otra vez")

    # --- los tres botones del video en pequeño (como el PiP del iPhone) -------------------------------------------
    def _cancel_pip_timer(self) -> None:
        timer = getattr(self, "_pip_timer", None)
        if timer:
            timer.cancel()
        self._pip_timer = None

    def _show_pip_controls(self) -> None:
        """Los tres botones unos segundos (en pausa se quedan): luego solo el video."""
        if not self.pip:
            return
        paused = bool(self._value("pause"))
        self._overlay(1, player_ui.pip_ass(paused))
        self._cancel_pip_timer()
        if not paused:
            self._pip_timer = threading.Timer(PIP_CONTROLS_SECONDS, self._hide_pip_controls)
            self._pip_timer.daemon = True
            self._pip_timer.start()

    def _hide_pip_controls(self) -> None:
        if self.pip and not self._value("pause"):
            self._overlay(1, None)
            player_ui.targets["hud"] = []

    def _pip_tap(self, x: float, y: float) -> None:
        """Un toque en el video en pequeño: un botón, o enseñar los botones."""
        action = player_ui.hit("hud", x, y)
        if action == "pip:expand":
            current = self.current
            self.exit_pip()
            if current is not None and current.process is not None:
                windows, hwnd = self._window(current)
                windows.focus(hwnd)
        elif action == "pip:close":
            self._user_quit = True
            self._quit()
        elif action == "pip:play":
            paused = not bool(self._value("pause"))
            self.mpv.command("set_property", "pause", paused)
            self._ask("pause", paused)
            self._show_pip_controls()
        else:
            self._show_pip_controls()

    def _curtain(self, opacity: float) -> None:
        """El negro del fundido de entrada (debajo de la barra, los avisos y los paneles)."""
        try:
            self.mpv.command_named(name="osd-overlay", id=CURTAIN_ID, format="ass-events" if opacity > 0 else "none",
                                   data=player_ui.curtain_ass(opacity) if opacity > 0 else "",
                                   res_x=player_ui.W, res_y=player_ui.H, z=0)
        except Exception:  # noqa: BLE001 - el fundido nunca tumba la reproducción
            log.debug("No pude dibujar el fundido", exc_info=True)
