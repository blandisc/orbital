"""La barra de abajo, la pausa (con el logo del título) y los avisos."""

from __future__ import annotations

import threading
import time

from .. import player_ui
from ..text import clock
from .base import SEEK_LINGER, log, logo_bgra
from .cards import _Cards


class _Hud(_Cards):
    """La barra, la pausa y los avisos."""

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
    def _overlay(self, overlay_id: int, ass: str | None, *, fading: bool = False) -> None:
        if overlay_id == self.CARD:
            with self._card_paint:  # la tarjeta la pintan varios hilos (el vigilante, su animación, su salida)
                if not fading:
                    self._card_ghost = None  # lo que se pinta ahora manda: la tarjeta que se iba desvaneciendo ya no
                self._paint(overlay_id, ass)
                if not ass:
                    self._card_last = None
                    self._show_still(None, None, 0)  # el cuadro del episodio se va con su tarjeta
            return
        if overlay_id == 1 and not fading:
            self._fade_token = None  # lo que se pinta ahora manda: un fundido de la pausa que iba a medias ya no lo tapa
        self._paint(overlay_id, ass)
        if overlay_id == 1 and not ass:  # se fue la barra (o la tapó un panel): el logo de la pausa, con ella
            self._show_logo(None)

    def _paint(self, overlay_id: int, ass: str | None) -> None:
        self.mpv.command_named(name="osd-overlay", id=overlay_id, format="ass-events" if ass else "none",
                               data=ass or "", res_x=player_ui.W, res_y=player_ui.H, z=overlay_id)

    # --- el logo del título en pausa: una imagen encima del video (mpv overlay-add), no texto plano -----------------
    LOGO_OVERLAY = 0  # el id de overlay-add (las imágenes van aparte de las capas ASS)
    _LOGO_BUSY = "busy"

    def _logo_for(self, meta: dict) -> tuple[str, int, int] | None:
        """El logo listo para mpv (archivo BGRA, ancho y alto en px de la pantalla); None si no hay o si aún se prepara
        (se pide por detrás y, si sigues en pausa, se vuelve a dibujar con él)."""
        key = meta.get("meta_id")
        scale = self._px_per_unit()
        if not key or not self.logo_provider or not scale:
            return None
        cache = self.__dict__.setdefault("_logos", {})
        found = cache.get((key, scale))
        if found is None and (key, scale) not in cache:
            cache[(key, scale)] = self._LOGO_BUSY
            threading.Thread(target=self._prepare_logo, args=(meta, key, scale), daemon=True, name="player-logo").start()
            return None
        return found if isinstance(found, tuple) else None

    def _px_per_unit(self) -> float | None:
        h = self.mpv.get("osd-height")
        return round(h / player_ui.H, 4) if isinstance(h, (int, float)) and h > 0 else None

    def _prepare_logo(self, meta: dict, key: str, scale: float) -> None:
        cache = self.__dict__.setdefault("_logos", {})
        result = None
        try:
            raw = self.logo_provider(meta)
            if raw:
                result = logo_bgra(raw, key, (player_ui.LOGO_BOX[0] * scale, player_ui.LOGO_BOX[1] * scale))
        except Exception:  # noqa: BLE001 - sin logo, el nombre en texto como siempre
            log.info("Sin logo para la pausa de %s", key, exc_info=True)
        cache[(key, scale)] = result
        current = self.current
        if result and current is not None and (current.meta or {}).get("meta_id") == key and self._hud_visible \
                and self.menu is None and self._value("pause"):
            self.show_hud()

    def _show_logo(self, where: tuple[float, float, float, float] | None, logo: tuple[str, int, int] | None = None) -> None:
        """Pone el logo en su lugar del lienzo (o lo quita con None)."""
        if where is None or logo is None:
            if getattr(self, "_logo_shown", False):
                self._logo_shown = False
                self.mpv.command("overlay-remove", self.LOGO_OVERLAY)
            return
        scale = self._px_per_unit() or 1.0
        path, w, h = logo
        x, y = round(where[0] * scale), round(where[1] * scale)
        self.mpv.command("overlay-add", self.LOGO_OVERLAY, x, y, path, 0, "bgra", w, h, w * 4)
        self._logo_shown = True

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
            audio_flag=player_ui.current_flag(tracks),
            source=meta.get("source_label", ""), series=meta.get("kind") == "series" and self.on_episode is not None,
            next=meta.get("next", "") if meta.get("kind") == "series" and self.on_episode is not None else "",
            clip=bool(meta.get("clip")),
            now=clock(),
            chapters=[float(c["time"]) for c in chapters], chapter_titles=[str(c.get("title") or "") for c in chapters],
            facts=meta.get("facts", ""), description=meta.get("description", ""), seeking=seeking,
            pip=bool(getattr(self, "pip_on_home", False)))

    # La pausa entra con un fundido (lo que se ve en cada paso, y cada cuánto) y, reproduciendo, la barra avanza mientras
    # se ve (antes se pintaba una vez y se quedaba quieta los 4 s). Las pruebas los apagan con () y 0.
    PAUSE_FADE: tuple[float, ...] = (.35, .7)
    PAUSE_FADE_STEP = .07
    HUD_TICK = .5

    def show_hud(self, seeking: str = "", *, position: float | None = None, paused: bool | None = None) -> None:
        """Barra inferior: se queda en pausa; reproduciendo, se va sola a los pocos segundos.
        `seeking` («+30 s»): mientras adelantas, solo la barra y a dónde vas. `position`/`paused`: lo que
        el botón acaba de pedir (mpv tarda un instante en confirmarlo y la barra saldría atrasada)."""
        current = self.current
        if current is None or self.menu is not None or self._try is not None:
            return
        if getattr(self, "pip", False):  # en pequeño: solo los tres botones, nunca la barra completa
            return self._show_pip_controls()
        if self._is_live():
            return self._show_live_hud()
        hud = self._hud(current, seeking, position=position, paused=paused)
        logo = self._logo_for(current.meta or {}) if hud.paused and not seeking else None
        scale = self._px_per_unit() or 1.0
        if logo:
            hud.logo = (logo[1] / scale, logo[2] / scale)
        ass = player_ui.hud_ass(hud)
        where = player_ui.placed.get("logo") if logo else None
        entering = hud.paused and not seeking and not self.__dict__.get("_pause_drawn") and bool(self.PAUSE_FADE)
        self._pause_drawn = bool(hud.paused)
        self._hud_seeking = seeking
        if entering:
            self._fade_in(ass, where, logo)
        else:
            self._overlay(1, ass)
            self._show_logo(where, logo)
        self._hud_visible = True
        if not hud.paused and not seeking and self.HUD_TICK:
            self._schedule_tick()
        if self.menu is None:
            # Reproduciendo, encima de la barra mientras se ve. En pausa se quedan en su lugar: el velo y el bloque de la
            # pausa los tapan de todos modos y verlos brincar arriba solo distraía (Fernando).
            self._lift_subs(not hud.paused or bool(seeking), self.SUBS_OVER_HUD)
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

    def _fade_in(self, ass: str, where, logo) -> None:
        """La pausa aparece en pasos (más transparente a más opaca); el logo, que es una imagen encima, entra al final."""
        token = self._fade_token = object()
        self._show_logo(None)
        self._overlay(1, player_ui.fade(ass, self.PAUSE_FADE[0]), fading=True)

        def step(appear: float) -> None:
            if self.__dict__.get("_fade_token") is not token or not self._hud_visible or self.menu is not None:
                return
            self._overlay(1, player_ui.fade(ass, appear), fading=True)
            if appear >= 1:
                self._show_logo(where, logo)
        for i, appear in enumerate((*self.PAUSE_FADE[1:], 1.0), 1):
            timer = threading.Timer(i * self.PAUSE_FADE_STEP, step, (appear,))
            timer.daemon = True
            timer.start()

    def _schedule_tick(self) -> None:
        old = self.__dict__.get("_tick_timer")
        if old:
            old.cancel()
        self._tick_timer = threading.Timer(self.HUD_TICK, self._tick)
        self._tick_timer.daemon = True
        self._tick_timer.start()

    def _tick(self) -> None:
        """Reproduciendo con la barra a la vista: se vuelve a pintar con el tiempo de ahora (la barra avanza pareja)."""
        current = self.current
        if (current is None or not self._hud_visible or self.menu is not None or self.__dict__.get("_hud_seeking")
                or self._value("pause") or getattr(self, "pip", False) or self._is_live()):
            return
        self._overlay(1, player_ui.hud_ass(self._hud(current)))
        self._schedule_tick()

    def _refresh_paused(self) -> None:
        if self._value("pause") and self._hud_visible and self.menu is None:
            self.show_hud()

    def hide_hud(self) -> None:
        if self._hud_timer:
            self._hud_timer.cancel()
        self._hud_visible = False
        self._pause_drawn = False
        self._fade_token = None
        self._overlay(1, None)
        if self.menu is None:
            self._lift_subs(False)  # la barra se fue: los subtítulos vuelven abajo

    def _hide_hud_if_playing(self) -> None:
        if not self._value("pause"):
            self.hide_hud()

    def toast(self, text: str, seconds: float = 1.6) -> None:
        self._show_notice(player_ui.toast_ass(text), player_ui.toast_seconds(text, seconds))
