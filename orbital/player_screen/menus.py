"""Los paneles (pistas de audio y subtítulos, Más), qué hace cada opción y los mensajes de mpv."""

from __future__ import annotations

import threading
import time

from .. import player_ui
from ..playback import UPNEXT_COUNTDOWN, track_variant
from .base import log
from .hud import _Hud


class _Menus(_Hud):
    """Los paneles y los mensajes de mpv."""

    # Cada aviso en su capa (antes compartían la 3 y se borraban entre sí: el volumen se comía «Salir», y el
    # fin del «Cargando…» borraba un aviso útil al que aún le quedaban segundos).
    TOAST, VOLUME, HOLD, BUFFER, MUTE = 3, 5, 6, 7, 8

    def _show_notice(self, ass: str, seconds: float, layer: int = 3) -> None:
        self._overlay(layer, ass)
        timers = self.__dict__.setdefault("_notice_timers", {})
        if timers.get(layer):
            timers[layer].cancel()
        timer = threading.Timer(seconds, lambda: self._overlay(layer, None))
        timer.daemon = True
        timer.start()
        timers[layer] = timer
        if layer == self.TOAST:
            self._toast_timer = timer

    def open_more(self, still_wanted=lambda: True) -> None:
        meta = getattr(self.current, "meta", None) or {}
        if meta.get("clip"):
            return  # un tráiler no tiene episodios ni versiones
        episodes = self._safe(self.episodes_provider, meta) if self.episodes_provider and meta.get("kind") == "series" else None
        sources = self._safe(self.sources_provider, meta) if self.sources_provider and self.current else None
        if still_wanted() and self.current is not None:  # mientras buscaba pulsaste otra cosa: no aparece de golpe
            # «Enviar al iPhone» solo con iPhone conectado y con una película o serie (no con la TV en vivo).
            iphone = bool(self.on_send_iphone and self.iphone_provider and meta.get("meta_id") and not meta.get("live")
                          and self._safe(self.iphone_provider))
            channel = bool(meta.get("synthetic"))
            self._open_panel(player_ui.more_panel(episodes=None if channel else episodes or None,
                                                  sources=None if channel else sources or None,
                                                  back_to=getattr(self, "_restart_from", None), iphone=iphone, channel=channel))

    def _open_more_soon(self) -> None:
        """Y: las fuentes se buscan por internet (hasta segundos). Se buscan aparte: el mando (el mismo
        hilo que atiende Home y Select+Start) nunca se queda esperando. Si tarda, se avisa."""
        done, token = threading.Event(), object()
        self._more_token = token

        def run() -> None:
            try:
                self.open_more(still_wanted=lambda: self._more_token is token)
            finally:
                done.set()

        threading.Thread(target=run, daemon=True, name="player-more").start()
        if not done.wait(.35):
            self.toast("Buscando versiones…", 3)

    def _open_panel(self, panel: player_ui.Panel) -> None:
        self.menu = panel
        if self._hud_timer:
            self._hud_timer.cancel()
        self._hud_visible = False
        self._overlay(1, None)
        self._overlay(4, None)  # la tarjeta vuelve al cerrar el panel
        self._overlay(self.MUTE, None)  # el panel dice «sin sonido» (la píldora se encimaba sobre su etiqueta)
        self._lift_subs(panel.kind == "tracks")  # X: los subtítulos suben, para ver cómo quedan los que eliges
        self._draw_panel()

    def _draw_panel(self) -> None:
        if self.menu is not None:
            self._overlay(2, player_ui.panel_ass(self.menu, playing=not self._value("pause"), muted=self._live_muted()))

    def _live_muted(self) -> bool:
        return self._is_live() and self._muted()

    def close_menu(self) -> None:
        self.menu = None
        self._overlay(2, None)
        self._lift_subs(False)
        if self._live_muted():
            self._overlay(self.MUTE, player_ui.muted_ass())  # vuelve la píldora «Sin sonido»
        card = self._card
        if card and card.get("kind") == "next" and card["segment"].upnext_deadline is not None:
            card["segment"].upnext_deadline = time.monotonic() + UPNEXT_COUNTDOWN  # no arranca de golpe
        self._draw_card()
        if self._value("pause"):
            self.show_hud()  # en pausa, sin barra no se sabe que está en pausa

    def _choose(self, option: dict) -> None:
        prop, value = option["action"]
        if prop == "category":  # la guía de canales: otra categoría, y se pasa a su lista de canales
            self._show_category(value)
            return
        if prop == "subdelay":  # Sincronía: se queda en el panel (se ajusta paso a paso); vuelve a cero con cada video
            self._set_sub_delay(0.0 if not value else self.sub_delay + value)
            column = self.menu.find("sync") if self.menu else None
            if column:
                column.options = player_ui.sync_options(self.sub_delay)
                column.index = 0 if value < 0 else 2 if value > 0 else 1
            self.toast("Subtítulos a tiempo" if not self.sub_delay else
                       f"Subtítulos {abs(self.sub_delay):.1f} s {'antes' if self.sub_delay < 0 else 'después'}".replace(".", ","), 2)
            self._draw_panel()
            return
        if prop == "subscale":  # se queda en el panel: ves el cambio y sigues ajustando
            self.sub_scale = value
            self.mpv.command("set_property", "sub-scale", value)
            if self.on_sub_scale:
                self._safe(self.on_sub_scale, value)
            for o in self.menu.column.options if self.menu else []:
                o["current"] = o is option
            self._draw_panel()
            return
        if prop in ("aid", "sid") and self.menu is not None and self.menu.kind == "tracks":
            # Audio o subtítulos: el panel se queda (B lo cierra) para probar otro sin volver a abrirlo.
            column = self.menu.find("audio" if prop == "aid" else "sub")
            for o in column.options if column else []:
                o["current"] = o.get("action") == option["action"]
            self._pick_track(option)
            self._draw_panel()
            return
        self.close_menu()
        meta = getattr(self.current, "meta", None) or {}
        if prop == "try":
            self.try_subtitles()
        elif prop == "fetch":
            self.toast("Buscando subtítulos…", 3)
            threading.Thread(target=self._fetch_subs, args=(value,), daemon=True).start()
        elif prop == "channel":
            if option.get("current") or not self.on_play_channel:
                return
            self.toast(f"Sintonizando {option['label'].split(' · ', 1)[-1]}…", 4)
            self._in_background(self.on_play_channel, meta, value, self._panel_category, failed="No pude cambiar de canal")
        elif prop == "restart":
            position = self.mpv.get("time-pos")
            if isinstance(position, (int, float)) and position > 30:
                self._restart_from = float(position)  # Y › «Volver a 32:10», por si fue sin querer
                self.toast(f"Desde el principio · Y › Volver a {player_ui.clock(position)}", 4)
            self.mpv.command("seek", 0, "absolute")
            self.show_hud()
        elif prop == "iphone":
            if self.on_send_iphone and meta.get("meta_id"):
                self._in_background(self._send_iphone, meta, value, failed="No pude mandarlo al iPhone")
        elif prop == "detach":
            self.detach_channel()
        elif prop == "resume-at":
            self._restart_from = None
            self.mpv.command("seek", float(value), "absolute")
            self.show_hud(position=float(value))
        elif prop == "episode":
            if option.get("current") or not self.on_play_episode:
                return
            self.toast(f"Cargando {option['label']}…", 4)
            self._in_background(self.on_play_episode, meta, value, failed="No pude cargar ese episodio")
        elif prop == "source":
            if option.get("current") or self.current is None:
                return
            position = self.mpv.get("time-pos")
            self.toast("Cambiando de versión…", 4)
            if self.on_switch_source:
                self._in_background(self.on_switch_source, meta, value, float(position or 0), failed="No pude cambiar de versión")
        else:  # aid / sid
            self._pick_track(option)

    def _pick_track(self, option: dict) -> None:
        """Una pista de audio o de subtítulos (del panel X o del iPhone): se pone, se dice y la serie la recuerda."""
        prop, value = option["action"]
        meta = getattr(self.current, "meta", None) or {}
        self.mpv.command("set_property", prop, value)
        kind = "Audio" if prop == "aid" else "Subtítulos"
        self.toast(f"{kind}: {option['label'].split(' · ')[0]}")
        if self.on_language and self.current is not None:  # que la serie lo recuerde
            lang = "" if value == "no" else option.get("lang")
            if prop == "aid" and lang is not None:  # «spa · Latino»: que la serie recuerde el doblaje, no solo «español»
                lang = track_variant(lang, option.get("label") or "") or lang
            if lang is not None:
                self._safe(self.on_language, meta, "audio" if prop == "aid" else "subtitles", lang)

    def _send_iphone(self, meta: dict, action: str) -> None:
        position = self.mpv.get("time-pos")
        try:
            said = self.on_send_iphone(meta, action, position if isinstance(position, (int, float)) else None)
        except ValueError as exc:  # sin iPhone o sin internet: en palabras, nunca un error crudo
            self.toast(str(exc), 4)
            return
        self.toast(said or "Listo", 5)
        if action == "continue":  # sigue allá: la TV regresa a Orbital (lo visto se guarda al cerrar)
            time.sleep(1.5)
            self.stop()

    def detach_channel(self) -> None:
        """Y › «Seguir solo este capítulo»: el episodio del canal se vuelve un episodio normal ahí mismo, sin recargar
        (pausa, adelantar, «Seguir viendo» y el siguiente de verdad, con la misma fuente y doblaje)."""
        segment, current = self.segment, self.current
        if segment is None or current is None or not segment.meta.get("synthetic"):
            return
        meta = {k: v for k, v in segment.meta.items() if k not in ("synthetic", "channel_id", "cycle", "place", "skips")}
        tried = meta.get("tried") or []
        label = next((part for part in str(meta.get("detail") or "").split(" · ") if part.startswith("T") and " E" in part), "")
        title = " · ".join(p for p in (meta.get("series") or current.title, label) if p)  # «Los Simpson · T7 E17»
        meta.update(kind="series", title=title, source=tried[-1] if tried else None)
        with self._swap:
            segment.meta = meta
            current.meta, current.title = meta, title
        self.mpv.command("set_property", "force-media-title", title)
        running = getattr(self, "on_detached", None)
        if running:
            self._safe(running, meta)
        self.menu = None
        self._overlay(2, None)
        self._lift_subs(False)
        self.toast(f"Sigues en {meta.get('detail') or title} · fuera del canal", 4)
        self.show_hud()

    def _fetch_subs(self, lang: str) -> None:
        try:
            urls = self._fallback_subs() if self._fallback_subs else []
        except Exception:  # noqa: BLE001
            log.exception("No pude buscar subtítulos")
            urls = []
        if urls:
            self.add_sub(urls[0], "Subtítulos", lang, done=f"Subtítulos: {player_ui.language(lang)}")
        else:
            self.toast("No encontré subtítulos en tu addon", 2.5)

    def _menu_press(self, button: str) -> None:
        panel = self.menu
        if panel is None:
            return
        column = panel.column
        if button in ("up", "down"):
            if column.options:
                column.index = max(0, min(len(column.options) - 1, column.index + (-1 if button == "up" else 1)))
                self._draw_panel()
        elif button in ("lb", "rb") and column.pages:  # Episodios: otra temporada
            if column.turn(-1 if button == "lb" else 1):
                self._draw_panel()
        elif button in ("lt", "rt"):  # una página de opciones (una lista de 170 canales no se recorre de a una)
            if column.options:
                jump = player_ui.PANEL_ROWS * (-1 if button == "lt" else 1)
                column.index = max(0, min(len(column.options) - 1, column.index + jump))
                self._draw_panel()
        elif button in ("left", "right"):
            step = -1 if button == "left" else 1
            cells = len(column.options[column.index]["cells"]) if column.grid else 0
            if column.grid and 0 <= min(column.cell, cells - 1) + step < cells:  # Versión: de calidad en calidad
                column.cell = min(column.cell, cells - 1) + step
                self._draw_panel()
            elif 0 <= panel.col + step < len(panel.columns):  # del borde de la cuadrícula, a la columna de al lado
                panel.col += step
                self._draw_panel()
        elif button == "a" and column.chosen:
            self._choose(column.chosen)
        elif button == "b":
            self.close_menu()
        elif button in ("x", "y"):
            self.close_menu()  # X y Y cierran el panel (como B); no saltan de uno a otro

    # --- el dedo ----------------------------------------------------------------------------------
    def _on_mpv_message(self, args: list[str]) -> None:
        """«orbital-tap x y ancho alto» (px de la ventana): al lienzo de player_ui y a tap(). «orbital-key
        botón»: una tecla, como el botón del mando que hace lo mismo (key())."""
        if len(args) >= 2 and args[0] == "orbital-key":
            self.key(args[1])
            return
        if not args or args[0] not in ("orbital-tap", "orbital-drag", "orbital-drop") or len(args) < 5:
            return
        try:
            x, y, w, h = (float(a) for a in args[1:5])
        except ValueError:
            return
        if w > 0 and h > 0:
            x, y = x / w * player_ui.W, y / h * player_ui.H
            if args[0] == "orbital-tap":
                self._scrub = None
                self.tap(x, y)
            else:
                self._drag(x, final=args[0] == "orbital-drop")
