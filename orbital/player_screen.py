"""Pantalla y mando del reproductor de Orbital (ver player.py). El dibujo vive en player_ui.py.

El mando, viendo algo:
  A pausa/seguir · ◀ ▶ adelantar/regresar (mantén: más rápido) · LB/RB capítulo (o 1 min) ·
  LT/RT episodio · ▲ ▼ volumen · X Audio y subtítulos · Y Más (episodios, fuente, desde el principio) ·
  B oculta la barra; con la barra oculta, sale.
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
        else:
            self._play_next(card["segment"], auto=False)

    def _card_dismiss(self) -> None:
        card = self._card
        if card is None:
            return
        self._hide_card()
        if card["kind"] == "still":
            self._user_quit = True
            self._quit()
        elif card["kind"] == "next":
            card["segment"].upnext_dismissed = True  # se queda en los créditos; al final, sale

    # --- interfaz encima del video (player_ui) -------------------------------------------------
    def _overlay(self, overlay_id: int, ass: str | None) -> None:
        self.mpv.command_named(name="osd-overlay", id=overlay_id, format="ass-events" if ass else "none",
                               data=ass or "", res_x=player_ui.W, res_y=player_ui.H, z=overlay_id)

    def _hud(self, seeking: str = "") -> player_ui.Hud:
        tracks = self.mpv.get("track-list") or []
        meta = self.current.meta
        segment = self.segment
        chapters = segment.chapters if segment else []
        position, duration = self.mpv.get("time-pos"), self.mpv.get("duration")
        return player_ui.Hud(
            title=self.current.title, detail=meta.get("detail") or ("Película" if meta.get("kind") == "movie" else ""),
            position=position, duration=duration, paused=bool(self.mpv.get("pause")),
            audio=player_ui.current_label(tracks, "audio"), subtitles=player_ui.current_label(tracks, "sub"),
            source=meta.get("source_label", ""), series=meta.get("kind") == "series" and self.on_episode is not None,
            ends=player_ui.ends_at(position, duration), now=time.strftime("%H:%M"),
            chapters=[float(c["time"]) for c in chapters], chapter_titles=[str(c.get("title") or "") for c in chapters],
            facts=meta.get("facts", ""), description=meta.get("description", ""), seeking=seeking)

    def show_hud(self, seeking: str = "") -> None:
        """Barra inferior: se queda en pausa; reproduciendo, se va sola a los pocos segundos.
        `seeking` («+30 s»): mientras adelantas, solo la barra y a dónde vas."""
        if self.current is None or self.menu is not None:
            return
        hud = self._hud(seeking)
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
        if self.mpv.get("pause") and self._hud_visible and self.menu is None:
            self.show_hud()

    def hide_hud(self) -> None:
        if self._hud_timer:
            self._hud_timer.cancel()
        self._hud_visible = False
        self._overlay(1, None)

    def _hide_hud_if_playing(self) -> None:
        if not self.mpv.get("pause"):
            self.hide_hud()

    def toast(self, text: str, seconds: float = 1.6) -> None:
        self._show_notice(player_ui.toast_ass(text), seconds)

    def _show_notice(self, ass: str, seconds: float) -> None:
        self._overlay(3, ass)
        if self._toast_timer:
            self._toast_timer.cancel()
        self._toast_timer = threading.Timer(seconds, lambda: self._overlay(3, None))
        self._toast_timer.daemon = True
        self._toast_timer.start()

    # --- paneles de columnas: X (Audio · Subtítulos · Tamaño) y Y (Más) ---------------------------
    def open_tracks(self, focus: str = "audio") -> None:
        tracks = self.mpv.get("track-list") or []
        extra = []
        if self._fallback_subs and self._subs_lang:
            extra.append({"label": f"Buscar en {player_ui.language(self._subs_lang).lower()}…",
                          "action": ("fetch", self._subs_lang), "current": False})
        self._open_panel(player_ui.tracks_panel(tracks, self.sub_scale, extra, focus))

    def open_more(self) -> None:
        meta = self.current.meta if self.current else {}
        episodes = self._safe(self.episodes_provider, meta) if self.episodes_provider and meta.get("kind") == "series" else None
        sources = self._safe(self.sources_provider, meta) if self.sources_provider and self.current else None
        self._open_panel(player_ui.more_panel(episodes=episodes or None, sources=sources or None))

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
            self._overlay(2, player_ui.panel_ass(self.menu, playing=not self.mpv.get("pause")))

    def close_menu(self) -> None:
        self.menu = None
        self._overlay(2, None)
        self._draw_card()

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
        meta = self.current.meta if self.current else {}
        if prop == "fetch":
            self.toast("Buscando subtítulos…", 3)
            threading.Thread(target=self._fetch_subs, args=(value,), daemon=True).start()
        elif prop == "restart":
            self.mpv.command("seek", 0, "absolute")
            self.show_hud()
        elif prop == "episode":
            if option.get("current") or not self.on_play_episode:
                return
            self.toast(f"Cargando {option['label']}…", 4)
            threading.Thread(target=self._safe, args=(self.on_play_episode, meta, value), daemon=True).start()
        elif prop == "source":
            if option.get("current") or self.current is None:
                return
            position = self.mpv.get("time-pos")
            self.toast("Cambiando de fuente…", 4)
            if self.on_switch_source:
                threading.Thread(target=self._safe, args=(self.on_switch_source, meta, value, float(position or 0)),
                                 daemon=True).start()
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
        elif button in ("left", "right", "lb", "rb"):
            step = -1 if button in ("left", "lb") else 1
            if 0 <= panel.col + step < len(panel.columns):
                panel.col += step
                self._draw_panel()
        elif button == "a" and column.options:
            self._choose(column.options[column.index])
        elif button == "b":
            self.close_menu()
        elif button == "x":
            if panel.kind == "tracks":
                self.close_menu()
            else:
                self.open_tracks()
        elif button == "y":
            if panel.kind == "more":
                self.close_menu()
            else:
                self.open_more()

    # --- el mando ---------------------------------------------------------------------------------
    def press(self, button: str) -> None:
        """Un botón del mando con el reproductor al frente."""
        self._quiet_episodes = 0  # alguien está ahí
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
            self.mpv.command("cycle", "pause")
            self.show_hud()
        elif button == "b":
            # Primero se va la barra; con la barra oculta, B sale.
            if self._hud_visible:
                self.hide_hud()
            else:
                self._user_quit = True
                self._quit()
        elif button == "x":
            self.open_tracks()
        elif button == "y":
            self.open_more()
        elif button in ("left", "right"):
            step = seek_step(self.remote.held(button)) * (1 if button == "right" else -1)
            self.mpv.command("seek", step, "relative")
            self.show_hud(seeking=player_ui.seek_label(step))
        elif button in ("lb", "rb"):
            delta = -1 if button == "lb" else 1
            if self.segment is not None and len(self.segment.chapters) > 1:
                self.mpv.command("add", "chapter", delta)
                self.show_hud()
            else:
                self.mpv.command("seek", delta * CHAPTER_SEEK, "relative")
                self.show_hud(seeking=player_ui.seek_label(delta * CHAPTER_SEEK))
        elif button in ("lt", "rt"):
            meta = self.current.meta if self.current else {}
            if meta.get("kind") == "series" and self.on_episode:
                self.toast("Episodio siguiente…" if button == "rt" else "Episodio anterior…", 3)
                threading.Thread(target=self._safe, args=(self.on_episode, meta, -1 if button == "lt" else 1),
                                 daemon=True).start()
        elif button in ("up", "down"):
            self.mpv.command("add", "volume", 5 if button == "up" else -5)
            volume = self.mpv.get("volume")
            if isinstance(volume, (int, float)):
                self._show_notice(player_ui.volume_ass(volume), 1.6)
            else:
                self.toast("Volumen")

    def _quit(self) -> None:
        """Cierra mpv anotando ANTES cómo terminó (el catálogo lo lee al volver a Orbital: "Terminaste…"
        en vez de "Guardé dónde ibas"). Antes de cerrar, no después: el lanzador puede ver el proceso
        terminado antes que este vigilante."""
        segment = self.segment
        if segment is not None and self.current is not None:
            finished = bool(segment.duration) and segment.position >= segment.duration * .9
            self.last_end = {"title": self.current.title, "finished": finished, "kind": segment.meta.get("kind")}
        self.mpv.command("quit")
