"""Pantalla y mando del reproductor de Orbital (ver player.py). El dibujo vive en player_ui.py.

El mando, viendo algo:
  A pausa/seguir · ◀ ▶ adelantar/regresar (mantén: más rápido) · LB/RB capítulo (o 1 min) ·
  LT/RT episodio · ▲ ▼ volumen · X Audio y subtítulos · Y Más (episodios, fuente, desde el principio) ·
  B pregunta «¿Salir de …?» (A sigue viendo, B sale).
"""

from __future__ import annotations

import logging
import threading
import time

from . import player_ui
from .playback import CHAPTER_SEEK, UPNEXT_COUNTDOWN, seek_step

log = logging.getLogger(__name__)

SEEK_LINGER = 2.0  # s que se queda la vista de «adelantar» (en pausa vuelve a la de pausa)


class PlayerScreen:
    """Lo que se ve encima del video (barra, pausa, adelantar, paneles, tarjetas, avisos) y qué
    hace cada botón del mando. Se mezcla en OrbitalPlayer: usa su estado (mpv, segment…)."""

    # --- tarjetas encima del video -------------------------------------------------------------
    def _show_card(self, card: dict, now: float | None = None) -> None:
        self._card = card
        self._draw_card(now)

    def _draw_card(self, now: float | None = None) -> None:
        card = self._card
        if card is None:
            self._overlay(4, None)
            return
        if card["kind"] == "skip":
            ass = player_ui.skip_ass(card["label"])
        elif card["kind"] == "quit":
            ass = player_ui.upnext_ass(f"¿Salir de {card['title']}?", "Tu avance se guarda",
                                       actions=[("A", "Seguir viendo"), ("B", "Salir")])
        else:
            segment = card["segment"]
            info = segment.upnext or {}
            title = " · ".join(p for p in (info.get("label"), info.get("title")) if p)
            if card["kind"] == "still":
                ass = player_ui.upnext_ass("¿Sigues viendo?", title, actions=[("A", "Seguir viendo"), ("B", "Salir")])
            else:
                now = time.monotonic() if now is None else now
                left = max(0.0, (segment.upnext_deadline or now) - now)
                ass = player_ui.upnext_ass(title or "Siguiente episodio", "Siguiente episodio", seconds=int(left + .99),
                                           progress=left / UPNEXT_COUNTDOWN, actions=[("A", "Ver ahora"), ("B", "Ver créditos")])
        self._overlay(4, ass)

    def _hide_card(self) -> None:
        self._card = None
        self._overlay(4, None)

    def _card_accept(self) -> None:
        card = self._card
        if card is None:
            return
        if card["kind"] == "skip":
            self._hide_card()
            self.mpv.command("seek", card["to"], "absolute")
        elif card["kind"] == "quit":
            self._hide_card()  # A: seguir viendo
            if self._value("pause"):
                self.show_hud()
        else:
            self._play_next(card["segment"], auto=False)

    def _card_dismiss(self) -> None:
        card = self._card
        if card is None:
            return
        self._hide_card()
        if card["kind"] in ("still", "quit"):
            self._user_quit = True
            self._quit()
        elif card["kind"] == "next":
            card["segment"].upnext_dismissed = True  # se queda en los créditos; al final, sale

    def _fit_canvas(self) -> None:
        """El lienzo del ancho de la pantalla (TV 16:9 o la Legion Go 16:10); si cambió (conectaste o
        desconectaste la TV) y la barra se ve, se vuelve a dibujar."""
        w, h = self.mpv.get("osd-width"), self.mpv.get("osd-height")
        if not (isinstance(w, (int, float)) and isinstance(h, (int, float)) and w > 0 and h > 0):
            return
        if not player_ui.set_canvas(w, h):
            return
        if self.menu is not None:  # lo que se ve, otra vez con el ancho nuevo
            self._draw_panel()
        elif self._hud_visible:
            self.show_hud()
        if self._card is not None and self.menu is None:
            self._draw_card()

    # --- lo pedido vs. lo confirmado ---------------------------------------------------------------
    WANT_SECONDS = 1.0

    def _value(self, prop: str):
        """El valor de `prop` contando lo que se acaba de pedir: mpv lo confirma un instante después y,
        con pulsaciones seguidas, la barra repetía el valor viejo (85, 85, 85 en vez de 85, 90, 95)."""
        want = self._want.get(prop)
        if want is not None and time.monotonic() < want[1]:
            return want[0]
        return self.mpv.get(prop)

    def _ask(self, prop: str, value) -> None:
        self._want[prop] = (value, time.monotonic() + self.WANT_SECONDS)

    # --- interfaz encima del video (player_ui) -------------------------------------------------
    def _overlay(self, overlay_id: int, ass: str | None) -> None:
        self.mpv.command_named(name="osd-overlay", id=overlay_id, format="ass-events" if ass else "none",
                               data=ass or "", res_x=player_ui.W, res_y=player_ui.H, z=overlay_id)

    def _hud(self, current, seeking: str = "", *, position: float | None = None, paused: bool | None = None) -> player_ui.Hud:
        tracks = self.mpv.get("track-list") or []
        meta = current.meta
        segment = self.segment
        chapters = segment.chapters if segment else []
        duration = self.mpv.get("duration")
        if position is None:
            position = self._value("time-pos")
        return player_ui.Hud(
            title=current.title, detail=meta.get("detail") or ("Película" if meta.get("kind") == "movie" else ""),
            position=position, duration=duration, paused=bool(self._value("pause")) if paused is None else paused,
            audio=player_ui.current_label(tracks, "audio"), subtitles=player_ui.current_label(tracks, "sub"),
            source=meta.get("source_label", ""), series=meta.get("kind") == "series" and self.on_episode is not None,
            ends=player_ui.ends_at(position, duration), now=time.strftime("%H:%M"),
            chapters=[float(c["time"]) for c in chapters], chapter_titles=[str(c.get("title") or "") for c in chapters],
            facts=meta.get("facts", ""), description=meta.get("description", ""), seeking=seeking)

    def show_hud(self, seeking: str = "", *, position: float | None = None, paused: bool | None = None) -> None:
        """Barra inferior: se queda en pausa; reproduciendo, se va sola a los pocos segundos.
        `seeking` («+30 s»): mientras adelantas, solo la barra y a dónde vas. `position`/`paused`: lo que
        el botón acaba de pedir (mpv tarda un instante en confirmarlo y la barra saldría atrasada)."""
        current = self.current
        if current is None or self.menu is not None:
            return
        hud = self._hud(current, seeking, position=position, paused=paused)
        self._overlay(1, player_ui.hud_ass(hud))
        self._hud_visible = True
        if self._hud_timer:
            self._hud_timer.cancel()
        if hud.paused and seeking:  # en pausa, después de adelantar vuelve la vista de pausa
            self._hud_timer = threading.Timer(SEEK_LINGER, self._refresh_paused)
        elif not hud.paused:
            self._hud_timer = threading.Timer(self.HUD_SECONDS, self._hide_hud_if_playing)
        else:
            self._hud_timer = None
            return
        self._hud_timer.daemon = True
        self._hud_timer.start()

    def _refresh_paused(self) -> None:
        if self._value("pause") and self._hud_visible and self.menu is None:
            self.show_hud()

    def hide_hud(self) -> None:
        if self._hud_timer:
            self._hud_timer.cancel()
        self._hud_visible = False
        self._overlay(1, None)

    def _hide_hud_if_playing(self) -> None:
        if not self._value("pause"):
            self.hide_hud()

    def toast(self, text: str, seconds: float = 1.6) -> None:
        self._show_notice(player_ui.toast_ass(text), seconds)

    # Cada aviso en su capa (antes compartían la 3 y se borraban entre sí: el volumen se comía «Salir», y el
    # fin del «Cargando…» borraba un aviso útil al que aún le quedaban segundos).
    TOAST, VOLUME, HOLD, BUFFER = 3, 5, 6, 7

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

    # --- paneles de columnas: X (Audio · Subtítulos · Tamaño) y Y (Más) ---------------------------
    def open_tracks(self, focus: str = "audio") -> None:
        tracks = self.mpv.get("track-list") or []
        extra = []
        if self._fallback_subs and self._subs_lang:
            extra.append({"label": f"Buscar en {player_ui.language(self._subs_lang).lower()}…",
                          "action": ("fetch", self._subs_lang), "current": False})
        self._open_panel(player_ui.tracks_panel(tracks, self.sub_scale, extra, focus))

    def open_more(self, still_wanted=lambda: True) -> None:
        meta = getattr(self.current, "meta", None) or {}
        episodes = self._safe(self.episodes_provider, meta) if self.episodes_provider and meta.get("kind") == "series" else None
        sources = self._safe(self.sources_provider, meta) if self.sources_provider and self.current else None
        if still_wanted() and self.current is not None:  # mientras buscaba pulsaste otra cosa: no aparece de golpe
            self._open_panel(player_ui.more_panel(episodes=episodes or None, sources=sources or None,
                                                  back_to=getattr(self, "_restart_from", None)))

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
            self.toast("Buscando fuentes…", 3)

    def _open_panel(self, panel: player_ui.Panel) -> None:
        self.menu = panel
        if self._hud_timer:
            self._hud_timer.cancel()
        self._hud_visible = False
        self._overlay(1, None)
        self._overlay(4, None)  # la tarjeta vuelve al cerrar el panel
        self._draw_panel()

    def _draw_panel(self) -> None:
        if self.menu is not None:
            self._overlay(2, player_ui.panel_ass(self.menu, playing=not self._value("pause")))

    def close_menu(self) -> None:
        self.menu = None
        self._overlay(2, None)
        card = self._card
        if card and card.get("kind") == "next" and card["segment"].upnext_deadline is not None:
            card["segment"].upnext_deadline = time.monotonic() + UPNEXT_COUNTDOWN  # no arranca de golpe
        self._draw_card()
        if self._value("pause"):
            self.show_hud()  # en pausa, sin barra no se sabe que está en pausa

    def _choose(self, option: dict) -> None:
        prop, value = option["action"]
        if prop == "subscale":  # se queda en el panel: ves el cambio y sigues ajustando
            self.sub_scale = value
            self.mpv.command("set_property", "sub-scale", value)
            if self.on_sub_scale:
                self._safe(self.on_sub_scale, value)
            for o in self.menu.column.options if self.menu else []:
                o["current"] = o is option
            self._draw_panel()
            return
        self.close_menu()
        meta = getattr(self.current, "meta", None) or {}
        if prop == "fetch":
            self.toast("Buscando subtítulos…", 3)
            threading.Thread(target=self._fetch_subs, args=(value,), daemon=True).start()
        elif prop == "restart":
            position = self.mpv.get("time-pos")
            if isinstance(position, (int, float)) and position > 30:
                self._restart_from = float(position)  # Y › «Volver a 32:10», por si fue sin querer
                self.toast(f"Desde el principio · Y › Volver a {player_ui.clock(position)}", 4)
            self.mpv.command("seek", 0, "absolute")
            self.show_hud()
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
            self.toast("Cambiando de fuente…", 4)
            if self.on_switch_source:
                self._in_background(self.on_switch_source, meta, value, float(position or 0), failed="No pude cambiar de fuente")
        else:  # aid / sid
            self.mpv.command("set_property", prop, value)
            kind = "Audio" if prop == "aid" else "Subtítulos"
            self.toast(f"{kind}: {option['label'].split(' · ')[0]}")
            if self.on_language and self.current is not None:  # que la serie lo recuerde
                lang = "" if value == "no" else option.get("lang")
                if lang is not None:
                    self._safe(self.on_language, meta, "audio" if prop == "aid" else "subtitles", lang)

    def _fetch_subs(self, lang: str) -> None:
        try:
            urls = self._fallback_subs() if self._fallback_subs else []
        except Exception:  # noqa: BLE001
            log.exception("No pude buscar subtítulos")
            urls = []
        if urls:
            self.mpv.command("sub-add", urls[0], "select", "Subtítulos", lang)
            self.toast(f"Subtítulos: {player_ui.language(lang)}")
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
        elif button in ("left", "right"):
            step = -1 if button == "left" else 1
            if 0 <= panel.col + step < len(panel.columns):
                panel.col += step
                self._draw_panel()
        elif button == "a" and column.options:
            self._choose(column.options[column.index])
        elif button == "b":
            self.close_menu()
        elif button in ("x", "y"):
            self.close_menu()  # X y Y cierran el panel (como B); no saltan de uno a otro

    # --- el mando ---------------------------------------------------------------------------------
    def press(self, button: str) -> None:
        """Un botón del mando con el reproductor al frente."""
        self._quiet_episodes = 0  # alguien está ahí
        current = self.current
        if current is None:
            return
        self._fit_canvas()  # por si la pantalla cambió en este segundo (TV ↔ Legion Go)
        if button == "b-up":
            if getattr(self, "_quit_hold", None) is not None:
                self._quit_hold = None
                self._overlay(self.HOLD, None)  # soltaste antes de llenarse: no pasa nada
            return
        if button == "b" and self.remote.held("b"):
            self._hold_to_quit()
            return
        if button.startswith("stick-"):
            # Un stick: en un panel mueve el foco como la cruceta; si no, solo enciende los controles
            # (no adelanta ni sube el volumen: un empujón sin querer no cambia nada).
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
        if self._card is not None and button in ("a", "b"):
            if button == "a":
                self._card_accept()
            else:
                self._card_dismiss()
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
            self._overlay(self.HOLD, player_ui.quit_hold_ass(0))
        elif button == "x":
            self.open_tracks()
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
            meta = getattr(self.current, "meta", None) or {}
            if meta.get("kind") == "series" and self.on_episode:
                self._queue_episode(meta, -1 if button == "lt" else 1)
        elif button in ("up", "down"):
            before = self._value("volume")
            if isinstance(before, (int, float)) and not isinstance(before, bool):
                top = self.mpv.get("volume-max")  # mpv deja pasar de 100 (130 de fábrica)
                top = top if isinstance(top, (int, float)) and not isinstance(top, bool) and top > 0 else 100
                volume = max(0, min(top, before + (5 if button == "up" else -5)))
                self.mpv.command("set_property", "volume", volume)
                self._ask("volume", volume)
                self._show_notice(player_ui.volume_ass(volume), 1.6, layer=self.VOLUME)
            else:
                self.mpv.command("add", "volume", 5 if button == "up" else -5)
                self.toast("Volumen")

    QUIT_HOLD = 1.5  # s con B mantenido para salir

    def _hold_to_quit(self) -> None:
        """B sigue mantenido: la barra avanza y, llena, sale. Solo si la pulsación empezó aquí (no la
        que cerró un panel o una tarjeta)."""
        started = getattr(self, "_quit_hold", None)
        if started is None:
            return
        progress = (time.monotonic() - started) / self.QUIT_HOLD
        if progress >= 1:
            self._quit_hold = None
            self._overlay(self.HOLD, None)
            self._quit()
        else:
            self._overlay(self.HOLD, player_ui.quit_hold_ass(progress))

    EPISODE_WAIT = .7  # s: RT, RT seguidos suman (dos episodios adelante) antes de cargar

    def _queue_episode(self, meta: dict, step: int) -> None:
        """LT/RT: se cuentan las pulsaciones y, cuando paras, se carga ese episodio (antes dos RT
        rápidos cargaban el mismo «siguiente» dos veces)."""
        self._episode_steps += step
        n = self._episode_steps
        if n == 0:
            self.toast("Sigues en este episodio", 2)
        elif abs(n) == 1:
            self.toast("Episodio siguiente…" if n > 0 else "Episodio anterior…", 3)
        else:
            self.toast(f"{abs(n)} episodios {'adelante' if n > 0 else 'atrás'}…", 3)
        if self._episode_timer:
            self._episode_timer.cancel()
        self._episode_timer = threading.Timer(self.EPISODE_WAIT, self._step_episodes, args=(meta,))
        self._episode_timer.daemon = True
        self._episode_timer.start()

    def _step_episodes(self, meta: dict) -> None:
        delta, self._episode_steps = self._episode_steps, 0
        if delta and self.current is not None:
            self._in_background(self.on_episode, meta, delta, failed="No pude cambiar de episodio")

    def _expected_position(self, step: float) -> float | None:
        """Adónde va el seek que se acaba de pedir (mpv lo confirma un instante después)."""
        pos, dur = self._value("time-pos"), self.mpv.get("duration")
        if not isinstance(pos, (int, float)) or isinstance(pos, bool):
            return None
        end = dur if isinstance(dur, (int, float)) and dur > 0 else pos + abs(step)
        target = max(0.0, min(float(end), pos + step))
        self._ask("time-pos", target)
        return target

    def _quit(self) -> None:
        """Cierra mpv anotando ANTES cómo terminó (el catálogo lo lee al volver a Orbital: "Terminaste…"
        en vez de "Guardé dónde ibas"). Antes de cerrar, no después: el lanzador puede ver el proceso
        terminado antes que este vigilante."""
        segment, current = self.segment, self.current
        if segment is not None and current is not None:
            finished = bool(segment.duration) and segment.position >= segment.duration * .9
            self.last_end = {"title": current.title, "finished": finished, "kind": segment.meta.get("kind")}
        self.mpv.command("quit")
