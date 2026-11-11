"""Toques, ratón, teclas y botones del mando: qué hace cada uno según lo que esté abierto."""

from __future__ import annotations

import time

from .. import player_ui
from ..playback import CHAPTER_SEEK, seek_step
from .menus import _Menus


class _Input(_Menus):
    """Toques, ratón, teclas y botones."""

    SCRUB_EVERY = .12  # s entre búsquedas mientras arrastras (la barra sí sigue al ratón en cada movimiento)

    def _drag(self, x: float, final: bool) -> None:
        """Arrastrar la bolita de la barra (tocaste la barra y no soltaste): la barra sigue al ratón y el video busca
        (a cuadros clave mientras arrastras, para que responda; exacto al soltar)."""
        scrub = getattr(self, "_scrub", None)
        duration = self.mpv.get("duration")
        if scrub is None or not isinstance(duration, (int, float)) or duration <= 0:
            return
        x0, width, last = scrub
        target = max(0.0, min(1.0, (x - x0) / width)) * duration
        now = time.monotonic()
        if final or now - last >= self.SCRUB_EVERY:
            self.mpv.command("seek", target, "absolute" if final else "absolute+keyframes")
            self._ask("time-pos", target)
            last = now
        self._scrub = None if final else (x0, width, last)
        self.show_hud(position=target)

    def tap(self, x: float, y: float) -> None:
        """Un toque en (x, y) del lienzo: lo que hay ahí (un botón, la barra, una opción del panel), o
        enseñar / esconder los botones. La primera vez cambia los glifos del mando por botones."""
        if self.current is None:
            return
        if getattr(self, "pip", False):
            return self._pip_tap(x, y)
        self._quiet_episodes = 0
        if player_ui.set_touch(True):
            self._redraw_for_input()
        if player_ui.targets.get("volume") and self.volume_tap(x, y):  # − o + de la cápsula del volumen (V2-A)
            return
        if self._try is not None:  # probando subtítulos: solo sus botones (tocar el video no hace nada)
            action = player_ui.hit("try", x, y)
            if isinstance(action, str):
                self._try_press(action)
            return
        if self._episode_steps and self._episode_timer is not None and player_ui.hit("card", x, y) == "b":
            self._cancel_episode()  # «Cancelar» en la cuenta atrás del cambio de episodio
            return
        if self._card is not None:
            action = player_ui.hit("card", x, y)
            if action == "a":
                self._card_accept()
            elif action == "b":
                self._card_dismiss()
            elif self.menu is None and self._card.get("kind") in ("skip", "next", "loading"):
                self._tap_video(x, y)  # «Saltar intro» no tapa el video: tocar fuera sigue siendo el video
            return
        if self.menu is not None:
            action = player_ui.hit("panel", x, y)
            if isinstance(action, tuple) and action[0] == "option":
                _, col, index = action
                self.menu.col = col
                self.menu.columns[col].index = index
                self._menu_press("a")
            elif isinstance(action, tuple) and action[0] == "cell":  # una casilla de Versión
                _, col, index, cell = action
                self.menu.col = col
                self.menu.columns[col].index, self.menu.columns[col].cell = index, cell
                self._menu_press("a")
            elif isinstance(action, tuple) and action[0] == "column":
                self.menu.col = action[1]
                self._draw_panel()
            elif action in ("lb", "rb"):  # «‹ Temporada» / «Temporada ›»
                self._menu_press(action)
            elif action == "close" or y < player_ui.PANEL_TOP:  # tocar el video, arriba del panel, también lo cierra
                self.close_menu()
            return
        self._tap_video(x, y)

    def _tap_video(self, x: float, y: float) -> None:
        action = player_ui.hit("hud", x, y) if self._hud_visible else None
        if isinstance(action, tuple) and action[0] == "seek":
            _, x0, width = action
            duration = self.mpv.get("duration")
            if isinstance(duration, (int, float)) and duration > 0:
                target = max(0.0, min(1.0, (x - x0) / width)) * duration
                self.mpv.command("seek", target, "absolute")
                self._ask("time-pos", target)
                self.show_hud(position=target)
                self._scrub = (x0, width, time.monotonic())  # si no sueltas, arrastras la bolita (_drag)
            return
        if action == "quit":
            self._user_quit = True
            self._quit()
        elif action == "subs":
            self.try_subtitles()
        elif action == "volume":  # V2-A: la cápsula con − y +
            self.show_volume_now()
            return
        elif action == "next":  # «⏭ Siguiente · E3»: lo mismo que RT
            action = "rt"
        if action in ("a", "x", "y", "left", "right", "up", "down", "rt"):
            self._touching = True
            try:
                self.press(action)
            finally:
                self._touching = False
        elif self._hud_visible and not self._value("pause"):
            self.hide_hud()  # tocar el video (no un botón) esconde los botones
        else:
            self.show_hud()

    def key(self, button: str) -> None:
        """Una tecla (ya con el nombre del botón del mando que hace lo mismo). La barra enseña las teclas. Esc:
        cierra lo abierto o pregunta «¿Salir de …?» (otro Esc sale; Espacio sigue viendo)."""
        if self.current is None:
            return
        if button.startswith("wheel-"):  # la rueda del mouse: otro subtítulo mientras pruebas; si no, el volumen (V2-A)
            if self._try is not None:
                self._try_press(button)
            elif self.menu is None:
                self._change_volume(1 if button == "wheel-up" else -1)
            return
        if player_ui.set_input("keyboard"):
            self._redraw_for_input()
        if button == "esc":
            if self._episode_steps and self._episode_timer is not None:
                button = "b"  # Esc en la cuenta atrás del cambio de episodio: cancelar (la tarjeta dice «Esc Cancelar»)
            elif self.menu is None and self._card is None and self._try is None:
                self._quiet_episodes = 0
                self._show_card({"kind": "quit", "title": self.current.title})
                return
            button = "b"  # con un panel o una tarjeta: B (cerrar, o salir en «¿Salir de …?»)
        self._keys = True
        try:
            self.press(button)
        finally:
            self._keys = False

    def _redraw_for_input(self) -> None:
        """Del dedo al mando (o al revés): lo que está a la vista, otra vez con sus botones o sus glifos."""
        if self.menu is not None:
            self._draw_panel()
        elif self._hud_visible:
            self.show_hud()
        if self._card is not None:
            self._draw_card()
        self._try_draw()

    # --- el mando ---------------------------------------------------------------------------------
    def press(self, button: str) -> None:
        """Un botón del mando con el reproductor al frente."""
        self._quiet_episodes = 0  # alguien está ahí
        if not getattr(self, "_touching", False) and not getattr(self, "_keys", False) and player_ui.set_input("gamepad"):
            self._redraw_for_input()  # volviste al mando: otra vez sus glifos
        current = self.current
        if current is None:
            return
        self._fit_canvas()  # por si la pantalla cambió en este segundo (TV ↔ Legion Go)
        if self._try is not None and self._try_press(button):
            return  # probando subtítulos: ◀▶ otro, ↑↓ sincronía, A este va bien, B el de antes
        if button == "b-up":
            if getattr(self, "_quit_hold", None) is not None:
                self._quit_hold = None
                self._overlay(self.HOLD, None)  # soltaste antes de llenarse: no pasa nada
            return
        if button == "b" and self.remote.held("b"):
            self._hold_to_quit()
            return
        if button in ("lt-up", "rt-up"):
            return  # el episodio ya se pidió al oprimir
        if button in ("lt", "rt") and self.remote.held(button):
            return  # mantenido cuenta una vez (no dispara dos episodios), igual en un panel o en la TV en vivo
        if button == "x-up":
            self._release_x()
            return
        if button == "x" and self.remote.held("x"):
            return  # mantenido: lo cuenta el anillo de «Probar subtítulos»
        if button.startswith("stick-"):
            # Un stick: en un panel mueve el foco como la cruceta; si no, solo enseña los controles. Ya no recorre los
            # botones de abajo (el usuario prefiere solo los atajos), ni adelanta ni sube el volumen: un empujón sin
            # querer (o un stick con deriva) no cambia nada.
            if self.menu is not None:
                self._menu_press(button.removeprefix("stick-"))
            elif self._card is None:
                self.show_hud()
            return
        if button != "y":
            self._more_token = None  # el panel Y que se estaba buscando ya no se abre
        if self.menu is not None:
            self._menu_press(button)
            return
        if button == "b" and self._episode_steps and self._episode_timer is not None:
            self._cancel_episode()  # LT/RT sin querer: B lo deshace antes de que cargue
            return
        # «¿Sigues viendo?» y «Cargando…»: salir es «Mantén B», como en todo el reproductor (un toque no saca del video).
        still = self._card is not None and self._card["kind"] in ("still", "loading")
        if button == "a" and self._card is not None and self._card["kind"] == "loading":
            return  # A mientras carga el otro episodio: nada (ni pausa lo que está cargando)
        if self._card is not None and button in ("a", "b") and not (button == "b" and still):
            if button == "a":
                self._card_accept()
            else:
                self._card_dismiss()
            return
        if self._is_live() and self._live_press(button):
            return
        if button == "a":
            if time.monotonic() < self._loading_until:
                return  # acaba de pedir otro episodio: A no pausa lo que está cargando
            paused = not self._value("pause")
            self.mpv.command("set_property", "pause", paused)  # el valor exacto: dos A seguidas no se cruzan
            self._ask("pause", paused)
            self.show_hud(paused=paused)
        elif button == "b":
            # B oculta los controles; para salir se MANTIENE B (la barra se llena): sin salidas sin querer.
            # En pausa no se oculta nada: sin el «En pausa», el cuadro congelado parecía un video colgado.
            if self._hud_visible and not self._value("pause"):
                self.hide_hud()
            self._quit_hold = time.monotonic()
            self._animate_hold(self._quit_hold)  # el anillo sale solo si lo mantienes (un toque solo oculta)
        elif button == "x":
            if self.remote.down("x") and not self._is_live():
                self._hold_subs()  # el mando: un toque abre Audio y subtítulos al soltar; mantenido, prueba subtítulos
            else:
                self.open_tracks()  # una tecla, el dedo o el iPhone no avisan al soltar: directo
        elif button == "subs":
            self.try_subtitles()  # S, o el botón «Probar subtítulos» (mouse y dedo)
        elif button == "y":
            self._open_more_soon()
        elif button in ("left", "right"):
            step = seek_step(self.remote.held(button)) * (1 if button == "right" else -1)
            self.mpv.command("seek", step, "relative")
            self.show_hud(seeking=player_ui.seek_label(step), position=self._expected_position(step))
        elif button in ("lb", "rb"):
            delta = -1 if button == "lb" else 1
            if self.segment is not None and len(self.segment.chapters) > 1:
                self.mpv.command("add", "chapter", delta)
                self.show_hud()
            else:
                self.mpv.command("seek", delta * CHAPTER_SEEK, "relative")
                self.show_hud(seeking=player_ui.seek_label(delta * CHAPTER_SEEK), position=self._expected_position(delta * CHAPTER_SEEK))
        elif button in ("lt", "rt"):
            # Un toque basta (antes había que mantenerlo 0,8 s): avisa «Episodio siguiente · B cancela» y espera 2 s.
            meta = getattr(self.current, "meta", None) or {}
            if meta.get("kind") == "series" and self.on_episode:
                self._queue_episode(meta, 1 if button == "rt" else -1)
        elif button in ("up", "down"):
            self._change_volume(1 if button == "up" else -1)
