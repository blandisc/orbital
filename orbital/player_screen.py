"""Pantalla y mando del reproductor de Orbital (ver player.py)."""

from __future__ import annotations

import logging
import threading
import time

from . import player_ui
from .playback import CHAPTER_SEEK, UPNEXT_COUNTDOWN, seek_step

log = logging.getLogger(__name__)


class PlayerScreen:
    """Lo que se ve encima del video (barra, tarjetas, avisos, menú de audio/subtítulos/fuente)
    y qué hace cada botón del mando. Se mezcla en OrbitalPlayer: usa su estado (mpv, segment…)."""

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
            ass = player_ui.card_ass(card["label"], actions=[("A", card["label"]), ("B", "Seguir viendo")])
        else:
            segment = card["segment"]
            info = segment.upnext or {}
            label = " · ".join(p for p in (info.get("label"), info.get("title")) if p)
            if card["kind"] == "still":
                ass = player_ui.card_ass("¿Sigues viendo?", label, [("A", "Seguir viendo"), ("B", "Salir")])
            else:
                now = time.monotonic() if now is None else now
                left = max(0.0, (segment.upnext_deadline or now) - now)
                ass = player_ui.card_ass(f"Siguiente episodio en {int(left + .99)}", label,
                                         [("A", "Ver ahora"), ("B", "Quedarme")], progress=left / UPNEXT_COUNTDOWN)
        self._overlay(4, ass)

    def _hide_card(self) -> None:
        self._card = None
        self._overlay(4, None)

    def _card_accept(self) -> None:
        card = self._card
        if card["kind"] == "skip":
            self._hide_card()
            self.mpv.command("seek", card["to"], "absolute")
        else:
            self._play_next(card["segment"], auto=False)

    def _card_dismiss(self) -> None:
        card = self._card
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

    def show_hud(self) -> None:
        """Barra inferior: se queda en pausa; reproduciendo, se va sola a los pocos segundos."""
        if self.current is None or self.menu is not None:
            return
        tracks = self.mpv.get("track-list") or []
        paused = bool(self.mpv.get("pause"))
        meta = self.current.meta
        segment = self.segment
        hud = player_ui.Hud(
            title=self.current.title, detail=meta.get("detail", ""),
            position=self.mpv.get("time-pos"), duration=self.mpv.get("duration"), paused=paused,
            audio=player_ui.current_label(tracks, "audio"), subtitles=player_ui.current_label(tracks, "sub"),
            source=meta.get("source_label", ""), series=meta.get("kind") == "series" and self.on_episode is not None,
            ends=player_ui.ends_at(self.mpv.get("time-pos"), self.mpv.get("duration")),
            chapters=[float(c["time"]) for c in (segment.chapters if segment else [])])
        self._overlay(1, player_ui.hud_ass(hud))
        self._hud_visible = True
        if self._hud_timer:
            self._hud_timer.cancel()
        if not paused:
            self._hud_timer = threading.Timer(self.HUD_SECONDS, self._hide_hud_if_playing)
            self._hud_timer.daemon = True
            self._hud_timer.start()

    def hide_hud(self) -> None:
        if self._hud_timer:
            self._hud_timer.cancel()
        self._hud_visible = False
        self._overlay(1, None)

    def _hide_hud_if_playing(self) -> None:
        if not self.mpv.get("pause"):
            self.hide_hud()

    def toast(self, text: str, seconds: float = 1.6) -> None:
        self._overlay(3, player_ui.toast_ass(text))
        if self._toast_timer:
            self._toast_timer.cancel()
        self._toast_timer = threading.Timer(seconds, lambda: self._overlay(3, None))
        self._toast_timer.daemon = True
        self._toast_timer.start()

    # --- menú con pestañas: Audio · Subtítulos · Fuente ------------------------------------------
    def _tabs(self) -> list[str]:
        return ["audio", "sub"] + (["source"] if self.sources_provider and self.current else [])

    def open_menu(self, kind: str) -> None:
        tabs = self._tabs()
        if kind == "source" and self.current is not None:
            sources = self._safe(self.sources_provider, self.current.meta) or []
            self.menu = player_ui.source_menu(sources, tabs)
        else:
            tracks = self.mpv.get("track-list") or []
            extra = []
            if kind == "sub":
                if self._fallback_subs and self._subs_lang:
                    extra.append({"label": f"Buscar subtítulos en {player_ui.language(self._subs_lang).lower()}…",
                                  "action": ("fetch", self._subs_lang), "current": False})
                extra.append({"label": f"Tamaño: {player_ui.sub_scale_label(self.sub_scale)}",
                              "action": ("subscale", None), "current": False})
            self.menu = player_ui.track_menu(kind, tracks, extra, tabs)
        if self._hud_timer:
            self._hud_timer.cancel()
        self._hud_visible = False
        self._overlay(1, None)
        self._overlay(4, None)  # la tarjeta vuelve al cerrar el menú
        self._overlay(2, player_ui.menu_ass(self.menu))

    def close_menu(self) -> None:
        self.menu = None
        self._overlay(2, None)
        self._draw_card()

    def _choose(self, option: dict) -> None:
        prop, value = option["action"]
        if prop == "subscale":  # se queda en el menú: ves el cambio y sigues ajustando
            self.sub_scale = player_ui.next_sub_scale(self.sub_scale)
            self.mpv.command("set_property", "sub-scale", self.sub_scale)
            if self.on_sub_scale:
                self._safe(self.on_sub_scale, self.sub_scale)
            option["label"] = f"Tamaño: {player_ui.sub_scale_label(self.sub_scale)}"
            self._overlay(2, player_ui.menu_ass(self.menu))
            return
        self.close_menu()
        if prop == "fetch":
            self.toast("Buscando subtítulos…", 3)
            threading.Thread(target=self._fetch_subs, args=(value,), daemon=True).start()
            return
        if prop == "source":
            if option.get("current") or self.current is None:
                return
            position = self.mpv.get("time-pos")
            self.toast("Cambiando de fuente…", 4)
            if self.on_switch_source:
                threading.Thread(target=self._safe, args=(self.on_switch_source, self.current.meta, value,
                                                          float(position or 0)), daemon=True).start()
            return
        self.mpv.command("set_property", prop, value)
        kind = "Audio" if prop == "aid" else "Subtítulos"
        self.toast(f"{kind}: {option['label'].split(' · ')[0]}")

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
        menu = self.menu
        if button in ("up", "down"):
            if menu.options:
                menu.index = max(0, min(len(menu.options) - 1, menu.index + (-1 if button == "up" else 1)))
                self._overlay(2, player_ui.menu_ass(menu))
        elif button == "a" and menu.options:
            self._choose(menu.options[menu.index])
        elif button == "b":
            self.close_menu()
        elif button in ("lb", "rb", "left", "right"):
            tabs = menu.tabs
            i = tabs.index(menu.kind) if menu.kind in tabs else 0
            self.open_menu(tabs[(i + (-1 if button in ("lb", "left") else 1)) % len(tabs)])
        elif button in ("x", "y"):
            kind = "audio" if button == "x" else "sub"
            if kind == menu.kind:
                self.close_menu()
            else:
                self.open_menu(kind)

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
        elif button in ("x", "y"):
            self.open_menu("audio" if button == "x" else "sub")
        elif button in ("left", "right"):
            step = seek_step(self.remote.held(button))
            self.mpv.command("seek", step if button == "right" else -step, "relative")
            self.show_hud()
        elif button in ("lb", "rb"):
            delta = -1 if button == "lb" else 1
            if self.segment is not None and len(self.segment.chapters) > 1:
                self.mpv.command("add", "chapter", delta)
            else:
                self.mpv.command("seek", delta * CHAPTER_SEEK, "relative")
            self.show_hud()
        elif button in ("lt", "rt"):
            meta = self.current.meta if self.current else {}
            if meta.get("kind") == "series" and self.on_episode:
                self.toast("Episodio siguiente…" if button == "rt" else "Episodio anterior…", 3)
                threading.Thread(target=self._safe, args=(self.on_episode, meta, -1 if button == "lt" else 1),
                                 daemon=True).start()
        elif button in ("up", "down"):
            self.mpv.command("add", "volume", 5 if button == "up" else -5)
            volume = self.mpv.get("volume")
            self.toast(f"Volumen {int(volume)} %" if isinstance(volume, (int, float)) else "Volumen")

    def _quit(self) -> None:
        """Cierra mpv anotando ANTES cómo terminó (el catálogo lo lee al volver a Orbital: "Terminaste…"
        en vez de "Guardé dónde ibas"). Antes de cerrar, no después: el lanzador puede ver el proceso
        terminado antes que este vigilante."""
        segment = self.segment
        if segment is not None and self.current is not None:
            finished = bool(segment.duration) and segment.position >= segment.duration * .9
            self.last_end = {"title": self.current.title, "finished": finished, "kind": segment.meta.get("kind")}
        self.mpv.command("quit")
