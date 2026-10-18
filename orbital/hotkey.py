"""El Home del teclado: Ctrl + Inicio, un atajo global de Windows (funciona aunque el juego o el video tengan el foco), igual
que Home en el mando o un toque de Legion L: del juego a Orbital y de Orbital de vuelta al juego. Sin esto, con teclado
no había cómo volver a Orbital desde un juego."""

from __future__ import annotations

import logging
import sys
import threading

log = logging.getLogger(__name__)

MOD_CONTROL, MOD_NOREPEAT = 0x0002, 0x4000
VK_HOME = 0x24
WM_HOTKEY, WM_QUIT = 0x0312, 0x0012
HOTKEY_ID = 0x4F52  # «OR»
LABEL = "Ctrl + Inicio"  # cómo se dice en la tele (la leyenda del teclado)


class KeyboardHome:
    """Escucha Ctrl + Inicio en su propio hilo (RegisterHotKey pide que el hilo que lo registra reciba el mensaje)."""

    def __init__(self, on_home) -> None:
        self.on_home = on_home
        self._thread: threading.Thread | None = None
        self._thread_id = 0

    def start(self) -> bool:
        if sys.platform != "win32" or self._thread is not None:
            return False
        ready = threading.Event()
        self._thread = threading.Thread(target=self._run, args=(ready,), daemon=True, name="teclado-home")
        self._thread.start()
        ready.wait(2)
        return True

    def _run(self, ready: threading.Event) -> None:
        import ctypes
        from ctypes import wintypes

        user32, kernel32 = ctypes.windll.user32, ctypes.windll.kernel32  # type: ignore[attr-defined]
        self._thread_id = kernel32.GetCurrentThreadId()
        ok = user32.RegisterHotKey(None, HOTKEY_ID, MOD_CONTROL | MOD_NOREPEAT, VK_HOME)
        ready.set()
        if not ok:
            log.warning("No pude registrar %s como Home del teclado (¿otro programa ya lo usa?)", LABEL)
            return
        log.info("Home del teclado: %s", LABEL)
        msg = wintypes.MSG()
        try:
            while user32.GetMessageW(ctypes.byref(msg), None, 0, 0) > 0:
                if msg.message == WM_HOTKEY and msg.wParam == HOTKEY_ID:
                    try:
                        self.on_home()
                    except Exception:  # noqa: BLE001 - un fallo aquí no debe matar el atajo
                        log.exception("Error atendiendo %s", LABEL)
        finally:
            user32.UnregisterHotKey(None, HOTKEY_ID)

    def stop(self) -> None:
        if self._thread_id and sys.platform == "win32":
            import ctypes

            ctypes.windll.user32.PostThreadMessageW(self._thread_id, WM_QUIT, 0, 0)  # type: ignore[attr-defined]
