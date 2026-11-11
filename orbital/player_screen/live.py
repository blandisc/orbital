"""La TV en vivo en el reproductor: su barra, cambiar de canal y la lista de canales."""

from __future__ import annotations

import threading

from .. import player_ui
from ..text import clock
from .extras import _Extras


class _Live(_Extras):
    """La TV en vivo en el reproductor."""

    # --- TV en vivo ---------------------------------------------------------------------------------
    ZAP_WAIT = 0.45  # s sin tocar ▲▼ antes de sintonizar: pasar por 5 canales carga solo el último

    def _is_live(self) -> bool:
        segment = self.segment
        return segment is not None and segment.live

    def _live_hud(self, meta: dict | None = None, status: str | None = None) -> player_ui.LiveHud:
        segment = self.segment
        meta = meta or (segment.meta if segment is not None else {})
        if status is None:
            status = "tuning"
            if segment is not None and segment.failed:
                status = "nosignal"
            elif segment is not None and segment.playing:
                status = "live"
        return player_ui.LiveHud(name=meta.get("title") or "", number=meta.get("number"), category=meta.get("category") or "",
                                 quality=meta.get("quality") or "", status=status, muted=self._muted(),
                                 now=clock())

    def _show_live_hud(self, meta: dict | None = None, status: str | None = None) -> None:
        """La barra del canal; se va sola a los pocos segundos (salvo «Sin señal», que se queda hasta que hagas algo)."""
        hud = self._live_hud(meta, status)
        self._overlay(1, player_ui.live_hud_ass(hud))
        self._hud_visible = True
        if self._hud_timer:
            self._hud_timer.cancel()
        if hud.status == "nosignal":
            self._hud_timer = None
            return
        self._hud_timer = threading.Timer(self.HUD_SECONDS, self.hide_hud)
        self._hud_timer.daemon = True
        self._hud_timer.start()

    def _live_press(self, button: str) -> bool:
        """Los botones de la TV en vivo. False: ese botón hace lo de siempre (B salir, X audio)."""
        if button == "a":
            muted = self.toggle_mute()
            self._overlay(self.MUTE, player_ui.muted_ass() if muted else None)  # se queda a la vista mientras no haya sonido
            self.show_hud()
        elif button in ("left", "right"):
            self._change_volume(1 if button == "right" else -1)
        elif button in ("up", "rt"):
            self._queue_channel(1)
        elif button in ("down", "lt"):
            self._queue_channel(-1)
        elif button == "y":
            self.open_channels()
        elif button in ("lb", "rb"):
            self.show_hud()
        else:
            return False
        return True

    def _queue_channel(self, step: int) -> None:
        """▲▼ o LT/RT: la barra enseña el canal al que vas al instante y, cuando paras, se sintoniza (antes cada
        pulsación abría una conexión que la siguiente tiraba)."""
        segment = self.segment
        if segment is None or not self.channels_provider:
            return
        if self._zap_view is None:
            info = self._safe(self.channels_provider, segment.meta, None) or {}
            # Los que ya fallaron una vez no entran en la rueda de ▲▼ (siguen en la guía, atenuados): saltar de uno en
            # uno por canales caídos era esperar 12 s por cada uno.
            now = segment.meta.get("channel_id")
            channels = [c for c in info.get("channels") or [] if not c.get("shaky") or c["id"] == now]
            if len(channels) < 2:
                channels = info.get("channels") or []
            here = next((i for i, c in enumerate(channels) if c["id"] == now), -1)
            self._zap_view = {"channels": channels, "here": here, "meta": segment.meta, "steps": 0}
        view = self._zap_view
        channels = view["channels"]
        if len(channels) < 2:
            self.toast("No hay otro canal en esta lista", 2.5)
            self._zap_view = None
            return
        view["steps"] += step
        if view["here"] >= 0:
            target = channels[(view["here"] + view["steps"]) % len(channels)]
        else:  # el canal que ves ya no está en la lista (se ocultó): se empieza por un extremo
            target = channels[0 if view["steps"] > 0 else -1]
        if target["id"] == view["meta"].get("channel_id"):  # diste la vuelta completa: sigues en el mismo
            self._zap_view = None
            if self._zap_timer:
                self._zap_timer.cancel()
            return self.show_hud()
        self._show_live_hud({"title": target["name"], "number": target.get("number"), "category": target.get("category", ""),
                             "quality": target.get("quality") or ""}, "tuning")
        if self._zap_timer:
            self._zap_timer.cancel()
        self._zap_timer = threading.Timer(self.ZAP_WAIT, self._commit_zap, args=(target["id"],))
        self._zap_timer.daemon = True
        self._zap_timer.start()

    def _commit_zap(self, channel_id: str) -> None:
        view, self._zap_view, self._zap_timer = self._zap_view, None, None
        if view is None or self.segment is None or not self.on_play_channel:
            return
        self._in_background(self.on_play_channel, view["meta"], channel_id, None, failed="No pude cambiar de canal")

    def open_channels(self, category: str | None = None) -> None:
        """Y: la guía de canales (categoría | canales) sobre el video, que sigue."""
        segment = self.segment
        if segment is None or not self.channels_provider:
            return
        info = self._safe(self.channels_provider, segment.meta, category) or {}
        if not info.get("channels"):
            self.toast("No hay canales para elegir", 2.5)
            return
        self._panel_category = info.get("category")
        self._open_panel(player_ui.channels_panel(info.get("categories") or [], info["channels"]))

    def _show_category(self, category: str) -> None:
        """Elegiste una categoría en la guía: su lista de canales, y el foco pasa a ella."""
        segment, panel = self.segment, self.menu
        if segment is None or panel is None or panel.kind != "channels":
            return
        info = self._safe(self.channels_provider, segment.meta, category) or {}
        self._panel_category = info.get("category", category)
        fresh = player_ui.channels_panel(info.get("categories") or [], info.get("channels") or [])
        for column, new in zip(panel.columns, fresh.columns, strict=True):
            column.options, column.index, column.top = new.options, new.index, 0
        panel.col = 1
        self._draw_panel()
