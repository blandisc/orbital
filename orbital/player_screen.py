"""Pantalla y mando del reproductor de Orbital (ver player.py). El dibujo vive en player_ui.py.

Con el dedo (o el ratón): tocar enseña los botones (−10 s, Pausa, +10 s, Audio y subtítulos, Episodios,
Salir; en pausa, si hay, «⏭ Siguiente · E3», que hace lo mismo que RT); tocar la barra salta ahí; en un panel, tocar
una opción la elige; tocar el video los esconde.
Cualquier botón del mando vuelve a los glifos del mando.

El mando, viendo algo:
  A pausa/seguir · ◀ ▶ adelantar/regresar (mantén: más rápido) · LB/RB capítulo (o 1 min) ·
  RT siguiente episodio / LT anterior, con un toque (avisa y espera 2 s: B lo cancela; teclado ] y [) ·
  ▲ ▼ volumen · X Audio y subtítulos · Y Más (episodios por temporada con LB/RB, fuente, desde el principio) ·
  B pregunta «¿Salir de …?» (A sigue viendo, B sale).

En X, elegir audio o subtítulos no cierra el panel (B lo cierra) y, mientras está abierto, los subtítulos suben para
verse encima de él. X › Subtítulos › «Probar otros»: una franja arriba para pasar de un subtítulo a otro (player_subs.py).

La TV en vivo usa los mismos botones con otro sentido (no hay a dónde adelantar ni una película que pausar):
  ▲ ▼ o LT/RT cambian de canal · ◀ ▶ volumen · A sin sonido · Y guía de canales · X audio · B (mantener) salir.
"""

from __future__ import annotations

import logging
import math
import threading
import time

from . import player_ui
from .playback import CHAPTER_SEEK, EXTRA_LABEL, UPNEXT_COUNTDOWN, VOLUME_BOOST_MAX, extra_filter, seek_step, track_variant
from .player_subs import SubtitleTrial
from .text import clock

log = logging.getLogger(__name__)

SEEK_LINGER = 2.0  # s que se queda la vista de «adelantar» (en pausa vuelve a la de pausa)


class PlayerScreen(SubtitleTrial):
    """Lo que se ve encima del video (barra, pausa, adelantar, paneles, tarjetas, avisos) y qué
    hace cada botón del mando. Se mezcla en OrbitalPlayer: usa su estado (mpv, segment…)."""

    # --- tarjetas encima del video -------------------------------------------------------------
    # Las tarjetas se mueven a 30 cuadros por segundo, en su hilo: entran subiendo y apareciendo, la cuenta atrás corre
    # seguida (antes saltaba una vez por segundo, con el vistazo del vigilante), cargando el anillo gira, y al irse se
    # desvanecen. Las pruebas lo apagan con CARD_FRAME = 0 (todo de golpe, como antes).
    CARD = 4  # la capa de las tarjetas
    CARD_FRAME = 1 / 30
    CARD_IN, CARD_OUT = .32, .2  # s: entrar, irse
    SPIN = .85  # vueltas por segundo del anillo de «Cargando…»
    SPIN_ARC = .28  # lo largo del arco que gira (en vueltas)
    MORPH = .45  # s: lo que tarda el anillo de la cuenta atrás en volverse el de «Cargando…»
    LOADING_MAX = 45.0  # s: si lo siguiente nunca da imagen, la tarjeta se va igual (el aviso de error ya dice qué pasó)

    def _show_card(self, card: dict, now: float | None = None) -> None:
        card.setdefault("shown", time.monotonic())
        self._card = card
        self._draw_card(now)
        self._animate_card()

    def _card_appear(self, card: dict) -> float:
        if not self.CARD_FRAME:
            return 1.0
        return min(1.0, (time.monotonic() - card.get("shown", 0.0)) / self.CARD_IN)

    def _card_moving(self, card: dict) -> bool:
        return card["kind"] in ("next", "loading") or self._card_appear(card) < 1

    def _animate_card(self) -> None:
        """El hilo que mueve la tarjeta mientras haga falta (uno por tarjeta: el de la anterior se detiene solo)."""
        if not self.CARD_FRAME:
            return
        token = object()
        self._card_anim = token

        def run() -> None:
            while getattr(self, "_card_anim", None) is token:
                card = self._card
                if card is None:
                    return
                now = time.monotonic()
                if card["kind"] == "next" and self.menu is None:
                    segment = card["segment"]
                    if segment.upnext_deadline is not None and now >= segment.upnext_deadline:
                        self._play_next(segment, auto=True)  # justo al vaciarse el anillo (no al siguiente vistazo)
                        return
                if card["kind"] == "loading" and now - card["since"] > self.LOADING_MAX:
                    self._end_loading()
                    return
                if self.menu is None:
                    self._safe(self._draw_card, now)
                if not self._card_moving(card):
                    return
                time.sleep(self.CARD_FRAME)

        threading.Thread(target=run, daemon=True, name="player-card").start()

    def _draw_card(self, now: float | None = None) -> None:
        card = self._card
        if card is None:
            self._overlay(self.CARD, None)
            return
        appear = self._card_appear(card)
        bitmap, room = None, False
        if card["kind"] == "skip":
            ass = player_ui.skip_ass(card["label"], appear=appear)
        elif card["kind"] == "quit":
            # Un canal en vivo no guarda avance (no entra en «Seguir viendo»): ahí sería mentira.
            ass = player_ui.upnext_ass(f"¿Salir de {card['title']}?", "TV en vivo" if self._is_live() else "Tu avance se guarda",
                                       actions=[("A", "Seguir viendo"), ("B", "Salir")], appear=appear)
        elif card["kind"] == "loading":
            # La misma tarjeta, ya elegido: dice «Cargando…» y su anillo gira hasta que el episodio da imagen (antes se iba
            # y salía otro aviso, «Cargando T1 E2…», arriba a la derecha).
            bitmap, room = self._still_state(card.get("still"))
            spent = time.monotonic() - card["since"]
            settle = player_ui.ease_out(spent / self.MORPH) if self.CARD_FRAME else 1.0
            length = self.SPIN_ARC + (card.get("from", 0.0) - self.SPIN_ARC) * (1 - settle)  # el arco que quedaba
            label, name = card.get("label") or "", card.get("name") or ""
            ass = player_ui.upnext_ass(name or label or "Siguiente episodio",
                                       f"Cargando {label}…" if label and name else "Cargando…",
                                       spinner=(spent * self.SPIN, length), actions=[("B", "Mantén: salir")],
                                       still=room, appear=appear)
        else:
            segment = card["segment"]
            info = segment.upnext or {}
            label, name = info.get("label") or "", info.get("title") or ""
            bitmap, room = self._still_state(info.get("still"))
            if card["kind"] == "debrid":  # RD-4: el siguiente no arranca al instante (RD-6: ya se le pidió solo)
                eyebrow = f"Siguiente episodio · {label}" if label else "Siguiente episodio"
                if info.get("requested"):
                    ass = player_ui.upnext_ass(f"Bajando en la nube · {int(info.get('percent') or 0)} %" if info.get("percent") is not None else "Bajando en la nube", eyebrow, actions=[("A", "Avisarme cuando esté"), ("B", "Ver créditos")],
                                               still=room, appear=appear)
                else:
                    ass = player_ui.upnext_ass("Todavía no está en la nube", eyebrow,
                                               actions=[("A", "Pedir a la nube"), ("B", "Ver créditos")], still=room, appear=appear)
            elif card["kind"] == "still":
                ass = player_ui.upnext_ass("¿Sigues viendo?", " · ".join(p for p in (label, name) if p),
                                           actions=[("A", "Seguir viendo"), ("B", "Mantén: salir")], still=room, appear=appear)
            else:
                now = time.monotonic() if now is None else now
                left = max(0.0, (segment.upnext_deadline or now) - now)
                # Arriba qué es («Siguiente episodio · T1 E2»), abajo su nombre en grande: con el cuadro, el nombre cabe.
                eyebrow = f"Siguiente episodio · {label}" if label and name else "Siguiente episodio"
                ass = player_ui.upnext_ass(name or label or "Siguiente episodio", eyebrow, seconds=math.ceil(left),
                                           progress=left / UPNEXT_COUNTDOWN, actions=[("A", "Ver ahora"), ("B", "Ver créditos")],
                                           still=room, appear=appear)
        where = player_ui.placed.get("still") if room else None
        with self._card_paint:
            if self._card is not card:
                return  # se fue mientras se dibujaba (otro hilo): no vuelve a aparecer
            self._overlay(self.CARD, ass)
            self._card_last = (ass, where, bitmap)
            self._show_still(where, bitmap, player_ui.ease_out(appear))

    def _hide_card(self) -> None:
        """Quita la tarjeta (ya no cuenta para A ni B) y, a la vista, se desvanece en CARD_OUT."""
        with self._card_paint:
            card, self._card = self._card, None
            last = getattr(self, "_card_last", None)
            if card is None or last is None or not self.CARD_FRAME or self.menu is not None:
                self._overlay(self.CARD, None)
                return
            token = object()
            self._card_ghost = token
        ass, where, bitmap = last
        started = time.monotonic()

        def run() -> None:
            while True:
                left = 1 - (time.monotonic() - started) / self.CARD_OUT
                with self._card_paint:
                    if getattr(self, "_card_ghost", None) is not token:
                        return  # otra tarjeta, un panel o el video en pequeño ya mandan en la capa
                    if left <= 0:
                        self._overlay(self.CARD, None)
                        return
                    self._overlay(self.CARD, player_ui.fade(ass, left), fading=True)
                    self._show_still(where, bitmap, left)
                time.sleep(self.CARD_FRAME)

        threading.Thread(target=run, daemon=True, name="player-card-out").start()

    def _end_loading(self, card: dict | None = None, target=None) -> None:
        """Se acabó «Cargando…» (el episodio ya da imagen, no se pudo o tardó demasiado): la tarjeta se va. Con `card`,
        solo si sigue siendo esa; con `target`, solo si es la del archivo que cargó."""
        current = self._card
        if current is None or current.get("kind") != "loading" or (card is not None and current is not card):
            return
        if target is not None and current.get("target") is not target:
            return
        self._hide_card()

    # --- el cuadro del episodio en la tarjeta: una imagen encima (mpv overlay-add), como el logo de la pausa ------------
    STILL_OVERLAY = 1
    STILL_STEPS = (.25, .5, .75, 1.0)  # la imagen entra y sale en estos pasos de transparencia (una copia de cada uno)

    def _still_state(self, url: str | None) -> tuple[tuple[list[str], int, int] | None, bool]:
        """(la imagen lista o None, si la tarjeta le guarda lugar). Mientras se prepara, el lugar ya está (no brinca al
        llegar); si no hay o no se pudo bajar, la tarjeta de siempre."""
        found = self._still_for(url) if url else None
        if isinstance(found, tuple):
            return found, True
        return None, found == self._LOGO_BUSY

    def _still_for(self, url: str):
        key = (url, self._px_per_unit())
        if not self.still_provider or not key[1]:
            return None
        cache = self.__dict__.setdefault("_stills", {})
        if key not in cache:
            cache[key] = self._LOGO_BUSY
            threading.Thread(target=self._prepare_still, args=key, daemon=True, name="player-still").start()
        return cache[key]

    def _prepare_still(self, url: str, scale: float) -> None:
        result = None
        box = (round(player_ui.STILL_BOX[0] * scale), round(player_ui.STILL_BOX[1] * scale))
        try:
            raw = self.still_provider(url, box[0])
            if raw:
                result = still_bgra(raw, url, box, round(12 * scale), self.STILL_STEPS)
        except Exception:  # noqa: BLE001 - sin cuadro, la tarjeta de siempre
            log.info("Sin cuadro del episodio: %s", url, exc_info=True)
        self.__dict__.setdefault("_stills", {})[(url, scale)] = result
        card = self._card
        if card is not None and self._card_still(card) == url and self.menu is None and not self._card_moving(card):
            self._draw_card()  # llegó con la tarjeta quieta a la vista: ya con el cuadro

    @staticmethod
    def _card_still(card: dict) -> str | None:
        """La dirección del cuadro del episodio de esa tarjeta (None si no lleva)."""
        if card["kind"] == "loading":
            return card.get("still")
        info = getattr(card.get("segment"), "upnext", None)
        return info.get("still") if isinstance(info, dict) else None

    def _show_still(self, where, bitmap, appear: float) -> None:
        """Pone el cuadro del episodio en su lugar (en el paso de transparencia de `appear`), o lo quita."""
        if where is None or bitmap is None or appear < .15:
            if getattr(self, "_still_at", None) is not None:
                self._still_at = None
                self.mpv.command("overlay-remove", self.STILL_OVERLAY)
            return
        paths, w, h = bitmap
        step = min(len(paths) - 1, max(0, math.ceil(appear * len(paths)) - 1))
        scale = self._px_per_unit() or 1.0
        at = (paths[step], round(where[0] * scale), round(where[1] * scale))
        if at == getattr(self, "_still_at", None):
            return  # quieta: no se vuelve a mandar a mpv en cada cuadro
        self._still_at = at
        self.mpv.command("overlay-add", self.STILL_OVERLAY, at[1], at[2], at[0], 0, "bgra", w, h, w * 4)

    def _card_accept(self) -> None:
        card = self._card
        if card is None or card["kind"] == "loading":
            return
        if card["kind"] == "skip":
            self._hide_card()
            self.mpv.command("seek", card["to"], "absolute")
        elif card["kind"] == "quit":
            self._hide_card()  # A: seguir viendo
            if self._value("pause"):
                self.show_hud()
        elif card["kind"] == "debrid":
            self._request_next(card["segment"])
        else:
            self._play_next(card["segment"], auto=False)

    def _card_dismiss(self) -> None:
        card = self._card
        if card is None:
            return
        self._hide_card()
        if card["kind"] in ("still", "quit", "loading"):  # «Cargando…» con el dedo: «Salir» (con el mando, mantener B)
            self._user_quit = True
            self._quit()
        elif card["kind"] in ("next", "debrid"):
            card["segment"].upnext_dismissed = True  # se queda en los créditos; al final, sale

    def _fit_canvas(self) -> None:
        """El lienzo del ancho de la pantalla (TV 16:9 o la Legion Go 16:10); si cambió (conectaste o
        desconectaste la TV) y la barra se ve, se vuelve a dibujar."""
        w, h = self.mpv.get("osd-width"), self.mpv.get("osd-height")
        if not (isinstance(w, (int, float)) and isinstance(h, (int, float)) and w > 0 and h > 0):
            return
        if not player_ui.set_canvas(w, h):
            return
        self._try_draw()
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

    # --- paneles de columnas: X (Audio · Subtítulos · Tamaño) y Y (Más) ---------------------------
    def open_tracks(self, focus: str = "audio") -> None:
        tracks = self.mpv.get("track-list") or []
        extra = []
        if not self._is_live() and (self._fallback_subs or any(t.get("type") == "sub" for t in tracks)):
            # Primera fila de Subtítulos, y dice el atajo (regla de las cuatro superficies): mantener X, la tecla S.
            how = "Tecla S" if player_ui.KEYBOARD else "Uno por uno" if player_ui.TOUCH else "Mantén X"
            extra.append({"label": "Probar otros", "hint": how, "action": ("try", None), "current": False, "first": True})
        if self._fallback_subs and self._subs_lang:
            extra.append({"label": f"Buscar en {player_ui.language(self._subs_lang).lower()}…",
                          "action": ("fetch", self._subs_lang), "current": False})
        meta = getattr(self.current, "meta", None) or {}
        # Tu idioma (y los que esta no trae) en otra versión: de la lista ya buscada, sin esperar a internet.
        versions = self._safe(self.versions_provider, meta) if self.versions_provider and self.current else None
        self._open_panel(player_ui.tracks_panel(tracks, self.sub_scale, extra, focus, sub_delay=self.sub_delay,
                                                versions=versions or None))
        if extra and extra[0].get("first") and not player_ui.TOUCH and not PlayerScreen.subs_taught:
            PlayerScreen.subs_taught = True  # la primera vez (en esta Orbital): cómo se llega directo
            key = "S" if player_ui.KEYBOARD else "X"
            self.toast(f"Para probar subtítulos sin abrir esto: {'oprime' if player_ui.KEYBOARD else 'mantén'} {key}", 4)

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

    # --- un solo volumen: el de Windows ------------------------------------------------------------------------------
    # Con `system_volume` = (leer, escribir) (quick.volume / quick.set_volume, lo conecta watch.py), ▲ ▼ y «Sin sonido»
    # mueven el volumen de la computadora, el mismo de Ajustes rápidos y de Alexa, y mpv se queda al 100 %: antes había
    # tres volúmenes (el de la tele, el de Windows y el del reproductor). Sin él (pruebas), el de mpv como antes.
    def _muted(self) -> bool:
        system = getattr(self, "system_volume", None)
        if system:
            return bool((system[0]() or {}).get("muted"))
        return bool(self._value("mute"))

    def set_muted(self, muted: bool) -> None:
        system = getattr(self, "system_volume", None)
        if system:
            system[1](muted=muted)
        else:
            self.mpv.command("set_property", "mute", muted)
            self._ask("mute", muted)

    def toggle_mute(self) -> bool:
        muted = not self._muted()
        self.set_muted(muted)
        return muted

    def _change_volume(self, direction: int, phone: bool = False) -> None:
        """▲ ▼ (y el + y − del iPhone, `phone`: V5-B, el mismo orden que el mando; la cápsula sale sin sus botones, V7-A)."""
        system = getattr(self, "system_volume", None)
        if system:
            now = system[0]() or {}
            current = int(now.get("level") or 0)
            boost = getattr(self, "boost", 100)
            # Pasado el 100 de Windows, sigue el del reproductor (hasta VOLUME_BOOST_MAX); al bajar, primero se quita eso.
            if (direction > 0 and current >= 100) or (direction < 0 and boost > 100):
                boost = max(100, min(VOLUME_BOOST_MAX, boost + 5 * direction))
                self.boost = boost
                self._apply_extra(boost)
                if direction > 0 and now.get("muted"):
                    system[1](level=current, muted=False)
                self._show_volume(boost, muted=False, touch=False if phone else None)
                return
            level = max(0, min(100, current + 5 * direction))
            after = system[1](level=level, muted=False if direction > 0 else None) or {"level": level}
            self._show_volume(after.get("level", level), muted=bool(after.get("muted")), touch=False if phone else None)
            return
        before = self._value("volume")
        if isinstance(before, (int, float)) and not isinstance(before, bool):
            top = self.mpv.get("volume-max")  # mpv deja pasar de 100 (130 de fábrica)
            top = top if isinstance(top, (int, float)) and not isinstance(top, bool) and top > 0 else 100
            volume = max(0, min(top, before + 5 * direction))
            self.mpv.command("set_property", "volume", volume)
            self._ask("volume", volume)
            self._show_volume(volume, muted=self._muted())
        else:
            self.mpv.command("add", "volume", 5 * direction)
            self.toast("Volumen")

    def _apply_extra(self, boost: float) -> None:
        """V1-C: el Extra no es el volumen de mpv (que solo multiplica y truena): mpv se queda en 100 y el filtro empareja
        y sube. Se cambia completo en cada paso de 5 (es un instante)."""
        self.mpv.command("set_property", "volume", 100)
        self.mpv.command("af", "remove", f"@{EXTRA_LABEL}")
        extra = extra_filter(boost)
        if extra:
            self.mpv.command("af", "add", extra)

    def _show_volume(self, level: float, muted: bool, touch: bool | None = None) -> None:
        """La cápsula del volumen; con el dedo, con sus botones − y + (V2-A) y un rato más a la vista para tocarlos.
        `touch=False`: desde el iPhone, sin los botones y el rato normal (V7-A)."""
        touch = player_ui.TOUCH if touch is None else touch
        self._show_notice(player_ui.volume_ass(level, muted=muted, touch=touch), 4.0 if touch else 1.6, layer=self.VOLUME)

    def volume_tap(self, x: float, y: float) -> bool:
        """Un toque en − o + de la cápsula (V2-A). True si tocó uno."""
        action = player_ui.hit("volume", x, y)
        if action not in ("up", "down"):
            return False
        self._change_volume(1 if action == "up" else -1)
        return True

    def show_volume_now(self) -> None:
        """El botón «Volumen» de abajo (mouse y dedo, V2-A): enseña la cápsula con − y +, sin cambiar nada."""
        system = getattr(self, "system_volume", None)
        if system:
            now = system[0]() or {}
            boost = getattr(self, "boost", 100)
            level = boost if boost > 100 else int(now.get("level") or 0)
            self._show_volume(level, muted=bool(now.get("muted")))
        else:
            value = self._value("volume")
            self._show_volume(value if isinstance(value, (int, float)) else 100, muted=self._muted())

    QUIT_HOLD = 1.5  # s con B mantenido para salir
    HOLD_SHOW_AFTER = .25  # s mantenido B antes de dibujar el anillo de salir
    HOLD_FPS = 30  # el anillo de «Salir» se llena con su propio reloj (antes, a saltos: solo con cada repetición de B)

    def _animate_hold(self, started: float) -> None:
        """Redibuja el anillo a 30 cuadros por segundo mientras B siga mantenido. Solo dibuja: salir lo sigue decidiendo
        `_hold_to_quit` con la repetición de B (soltar a tiempo nunca sale)."""
        def run() -> None:
            time.sleep(self.HOLD_SHOW_AFTER)  # un toque de B no enseña el anillo: parecía que B hacía dos cosas
            while getattr(self, "_quit_hold", None) == started:
                progress = (time.monotonic() - started) / self.QUIT_HOLD
                self._overlay(self.HOLD, player_ui.quit_hold_ass(min(1.0, progress)))
                if getattr(self, "_quit_hold", None) != started:  # soltaste mientras se dibujaba: que no se quede
                    self._overlay(self.HOLD, None)
                    return
                if progress >= 1:
                    return
                time.sleep(1 / self.HOLD_FPS)

        threading.Thread(target=run, daemon=True, name="hold-to-quit").start()

    subs_taught = False  # ya se enseñó «mantén X» al abrir el panel (una vez por Orbital)
    SUBS_HOLD = .6  # s con X mantenido para entrar a «Probar subtítulos» (un toque de X sigue abriendo el panel)

    def _hold_subs(self) -> None:
        """Mantener X: el anillo se llena y, lleno, entra a «Probar subtítulos». Soltar antes abre Audio y subtítulos
        (_release_x)."""
        started = time.monotonic()
        self._subs_hold = started

        def run() -> None:
            time.sleep(self.HOLD_SHOW_AFTER)  # un toque de X no enseña el anillo
            while getattr(self, "_subs_hold", None) == started:
                progress = (time.monotonic() - started) / self.SUBS_HOLD
                self._overlay(self.HOLD, player_ui.quit_hold_ass(min(1.0, progress), "X", "Probar subtítulos"))
                if progress >= 1:
                    self._subs_hold = None
                    self._overlay(self.HOLD, None)
                    self.try_subtitles()
                    return
                time.sleep(1 / self.HOLD_FPS)

        threading.Thread(target=run, daemon=True, name="hold-subs").start()

    def _release_x(self) -> None:
        """Soltaste X: si no se llenó el anillo, era un toque (Audio y subtítulos)."""
        if getattr(self, "_subs_hold", None) is None:
            return  # ya entró a probar, o la X cerró un panel
        self._subs_hold = None
        self._overlay(self.HOLD, None)
        if self.menu is None and self._try is None and self.current is not None:
            self.open_tracks()

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

    # s: RT, RT seguidos suman (dos episodios adelante) antes de cargar; y da tiempo de arrepentirse con B
    # (en la Legion Go en la mano, los gatillos se rozan sin querer).
    EPISODE_WAIT = 3.0
    EPISODE_CARD = 9  # capa de la cuenta atrás del cambio de episodio (como la tarjeta «Siguiente episodio»)

    def _queue_episode(self, meta: dict, step: int) -> None:
        """LT/RT: se cuentan las pulsaciones y, cuando paras, se carga ese episodio (antes dos RT rápidos cargaban el
        mismo «siguiente» dos veces). Mientras, la tarjeta de «Siguiente episodio» con la cuenta atrás en su anillo y
        «B Cancelar»: se ve cuándo va a cambiar y hasta cuándo se puede arrepentir (antes solo un aviso que se iba)."""
        self._episode_steps += step
        n = self._episode_steps
        if self._episode_timer:
            self._episode_timer.cancel()
        if n == 0:  # RT y luego LT: de vuelta en el mismo
            self._episode_timer = None
            self._stop_episode_card()
            self.toast("Sigues en este episodio", 2)
            return
        if abs(n) == 1:
            title = "Siguiente" + (f" · {meta['next']}" if n > 0 and meta.get("next") else "") if n > 0 else "Anterior"
        else:
            title = f"{abs(n)} episodios {'adelante' if n > 0 else 'atrás'}"
        self._episode_timer = threading.Timer(self.EPISODE_WAIT, self._step_episodes, args=(meta,))
        self._episode_timer.daemon = True
        self._episode_timer.start()
        self._episode_countdown(title)

    def _episode_countdown(self, title: str) -> None:
        """La tarjeta con el anillo que se vacía y los segundos que faltan, redibujada 30 veces por segundo (como la de
        «Siguiente episodio»; entra subiendo la primera vez, no con cada RT)."""
        started = time.monotonic()
        self._episode_anim = started
        self._episode_title = title
        since = getattr(self, "_episode_since", None)
        if since is None:
            self._episode_since = since = started

        def draw() -> bool:
            now = time.monotonic()
            left = self.EPISODE_WAIT - (now - started)
            if left <= 0 or getattr(self, "_episode_anim", None) != started:
                return False
            appear = min(1.0, (now - since) / self.CARD_IN) if self.CARD_FRAME else 1.0
            self._overlay(self.EPISODE_CARD, player_ui.upnext_ass(
                title, "Cambio de episodio", seconds=math.ceil(left), progress=left / self.EPISODE_WAIT,
                actions=[("B", "Cancelar")], appear=appear))
            return True

        draw()  # ya, sin esperar al hilo: la tarjeta sale en cuanto oprimes RT

        def run() -> None:
            while draw():
                time.sleep(self.CARD_FRAME or .1)

        threading.Thread(target=run, daemon=True, name="episode-countdown").start()

    def _stop_episode_card(self) -> None:
        self._episode_anim = self._episode_since = None
        self._overlay(self.EPISODE_CARD, None)

    def _cancel_episode(self) -> None:
        """B (o «Cancelar» con el dedo) durante la cuenta atrás: no cambia nada."""
        if self._episode_timer is not None:
            self._episode_timer.cancel()
        self._episode_timer, self._episode_steps = None, 0
        self._stop_episode_card()
        self.toast("Sigues en este episodio", 2)

    def _step_episodes(self, meta: dict) -> None:
        delta, self._episode_steps = self._episode_steps, 0
        if not delta or self.current is None:
            self._stop_episode_card()
            return
        # La tarjeta de la cuenta atrás se queda donde estaba y pasa a «Cargando…» (antes se iba y salía otro aviso).
        card = {"kind": "loading", "name": getattr(self, "_episode_title", ""), "since": time.monotonic(), "shown": 0.0}
        self._show_card(card)
        self._stop_episode_card()
        self._in_background(self._load_with_card, card, self.on_episode, meta, delta, failed="No pude cambiar de episodio")

    def _load_with_card(self, card: dict, load, *args):
        """Carga otro episodio con la tarjeta «Cargando…» a la vista: si no se pudo (o ya se avisó por qué), se va; si
        cargó, se va cuando el episodio da imagen (`_started`)."""
        ok = False
        try:
            ok = load(*args)
            return ok
        finally:
            if ok is not True:
                self._end_loading(card)

    def _expected_position(self, step: float) -> float | None:
        """Adónde va el seek que se acaba de pedir (mpv lo confirma un instante después)."""
        pos, dur = self._value("time-pos"), self.mpv.get("duration")
        if not isinstance(pos, (int, float)) or isinstance(pos, bool):
            return None
        end = dur if isinstance(dur, (int, float)) and dur > 0 else pos + abs(step)
        target = max(0.0, min(float(end), pos + step))
        self._ask("time-pos", target)
        return target

    def phone_legend(self) -> dict:
        """Lo que hace cada botón del control del iPhone con el reproductor al frente (las mismas acciones de
        /api/companion/input), para que el iPhone diga «Subtítulos» y no la leyenda de la interfaz."""
        if self._is_live():
            return {"up": "Canal siguiente", "down": "Canal anterior", "options": "Canales", "alt": "Audio",
                    "left": "Bajar volumen", "right": "Subir volumen", "select": "Silencio", "back": "Salir"}
        if self._try is not None:  # «Probar otros» subtítulos (la franja de arriba)
            return {"left": "Subtítulo anterior", "right": "Subtítulo siguiente", "up": "Adelantar subtítulos",
                    "down": "Atrasar subtítulos", "select": "Este va bien", "back": "Listo",
                    "prevsection": "Idioma anterior", "nextsection": "Idioma siguiente"}
        segment = self.segment
        meta = (segment.meta if segment is not None else None) or getattr(self.current, "meta", None) or {}
        series = meta.get("kind") == "series" and self.on_episode is not None
        legend = {"select": "Continuar" if self._value("pause") else "Pausa", "alt": "Audio y subtítulos",
                  "options": "Episodios" if series else "Versión", "left": "Atrasar", "right": "Adelantar",
                  "up": "Subir volumen", "down": "Bajar volumen", "back": "Salir"}
        if series:
            legend |= {"pageleft": "Episodio anterior", "pageright": "Episodio siguiente"}
        return legend

    def phone_tracks(self) -> dict:
        """Las pistas de audio y subtítulos para el iPhone: {audio: [{id, label, lang, selected}], subtitles: [...]}."""
        tracks = self.mpv.get("track-list") or []

        def of(kind: str) -> list[dict]:
            return [{"id": t["id"], "label": player_ui.track_label(t), "lang": t.get("lang") or None,
                     "selected": bool(t.get("selected"))} for t in tracks if t.get("type") == kind and "id" in t]
        return {"audio": of("audio"), "subtitles": of("sub")}

    def phone_track(self, kind: str, track: int | str | None = None) -> None:
        """Del iPhone: «subtitles» o «audio». Sin `track`, la siguiente pista (los subtítulos pasan por «Sin
        subtítulos»); con `track` (un id de phone_tracks, o "no" para quitar los subtítulos), esa."""
        listed = self.phone_tracks()["subtitles" if kind == "subtitles" else "audio"]
        prop = "sid" if kind == "subtitles" else "aid"
        choices = ([{"id": "no", "label": "Sin subtítulos"}] if kind == "subtitles" else []) + listed
        if track is None:
            if len(choices) < 2:
                raise ValueError("No hay otra pista" if kind == "audio" else "Este video no trae subtítulos")
            here = next((i for i, c in enumerate(choices) if c.get("selected")), 0)
            chosen = choices[(here + 1) % len(choices)]
        else:
            chosen = next((c for c in choices if str(c["id"]) == str(track)), None)
            if chosen is None:
                raise ValueError("Esa pista ya no está")
        self._choose({"action": (prop, chosen["id"]), "label": chosen["label"], "lang": chosen.get("lang") or ""})

    def phone_button(self, action: str) -> None:
        """Un botón del control del iPhone con el reproductor al frente: como el mando, salvo B, que sale sin mantener
        (en el teléfono no hay «mantener B»): con un panel o los controles a la vista, primero los quita."""
        if action == "back":
            if self._try is not None:
                self.press("b")  # «Listo»: se queda el último que probaste
            elif self.menu is not None:
                self.press("b")
                self.press("b-up")
            elif self._hud_visible and not self._value("pause"):
                self.hide_hud()
            else:
                self._quit()
            return
        meta = getattr(self.current, "meta", None) or {}
        if action in ("pageleft", "pageright") and self.menu is None and not self._is_live()                 and meta.get("kind") == "series" and self.on_episode:
            self._queue_episode(meta, -1 if action == "pageleft" else 1)  # en el teléfono no se mantiene: directo
            return
        button = {"select": "a", "alt": "x", "options": "y", "menu": "x", "pageleft": "lt", "pageright": "rt",
                  "prevsection": "lb", "nextsection": "rb"}.get(action, action)
        if button in ("up", "down", "left", "right", "a", "x", "y", "lt", "rt", "lb", "rb"):
            self.press(button)

    def _quit(self) -> None:
        """Cierra mpv anotando ANTES cómo terminó (el catálogo lo lee al volver a Orbital: "Terminaste…"
        en vez de "Guardé dónde ibas"). Antes de cerrar, no después: el lanzador puede ver el proceso
        terminado antes que este vigilante."""
        segment, current = self.segment, self.current
        if segment is not None and current is not None:
            finished = bool(segment.duration) and segment.position >= segment.duration * .9
            # Qué era (película o serie, su IMDb): al terminarla, la interfaz ofrece calificarla (como el iPhone). Un tráiler o
            # un canal no se califican.
            rateable = not segment.live and not segment.meta.get("clip") and not segment.meta.get("synthetic")
            self.last_end = {"title": current.title, "finished": finished, "kind": segment.meta.get("kind"),
                             **({"meta_id": segment.meta.get("meta_id")} if rateable and segment.meta.get("meta_id") else {}),
                             **({"live": True} if segment.live else {})}
        self.mpv.command("quit")

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


def still_bgra(raw: bytes, url: str, size: tuple[int, int], radius: int,
               steps: tuple[float, ...]) -> tuple[list[str], int, int]:
    """El cuadro del episodio -> archivos BGRA (alfa premultiplicado, para mpv overlay-add) del tamaño exacto de su lugar
    (recortado para llenarlo, sin estirarlo), con las esquinas redondeadas y una copia por cada paso de transparencia
    (`steps`): así entra y sale con la tarjeta. (rutas, ancho, alto)."""
    import hashlib
    import io
    import tempfile
    from pathlib import Path as _Path

    from PIL import Image, ImageDraw, ImageOps

    w, h = size
    image = ImageOps.fit(Image.open(io.BytesIO(raw)).convert("RGB"), (w, h), Image.Resampling.LANCZOS)
    big = Image.new("L", (w * 4, h * 4), 0)  # la esquina, dibujada en grande y reducida: sin dientes
    ImageDraw.Draw(big).rounded_rectangle((0, 0, w * 4 - 1, h * 4 - 1), radius * 4, fill=255)
    mask = big.resize((w, h), Image.Resampling.LANCZOS)
    folder = _Path(tempfile.gettempdir()) / "orbital-stills"
    folder.mkdir(exist_ok=True)
    key = hashlib.sha1(url.encode("utf-8", "surrogatepass")).hexdigest()[:16]
    paths = []
    for step in steps:
        rgba = image.convert("RGBA")
        rgba.putalpha(mask.point([round(v * step) for v in range(256)]))  # el filo con su suavizado, más transparente
        r, g, b, a = rgba.convert("RGBa").split()  # RGBa: alfa premultiplicado
        path = folder / f"{key}-{w}x{h}-{round(step * 100)}.bgra"
        path.write_bytes(Image.merge("RGBa", (b, g, r, a)).tobytes())
        paths.append(str(path))
    return paths, w, h


def logo_bgra(raw: bytes, key: str, box: tuple[float, float]) -> tuple[str, int, int] | None:
    """PNG del logo -> archivo BGRA con alfa premultiplicado (lo que pide mpv overlay-add), del tamaño que cabe en `box`
    (px). (ruta, ancho, alto) o None si no es una imagen."""
    import io
    import re as _re
    import tempfile
    from pathlib import Path as _Path

    from PIL import Image

    image = Image.open(io.BytesIO(raw)).convert("RGBA")
    ratio = min(box[0] / image.width, box[1] / image.height)
    size = (max(1, round(image.width * ratio)), max(1, round(image.height * ratio)))
    image = image.resize(size, Image.Resampling.LANCZOS)
    r, g, b, a = image.convert("RGBa").split()  # RGBa: alfa premultiplicado
    data = Image.merge("RGBa", (b, g, r, a)).tobytes()
    folder = _Path(tempfile.gettempdir()) / "orbital-logos"
    folder.mkdir(exist_ok=True)
    path = folder / f"{_re.sub(r'[^A-Za-z0-9_-]', '_', key)}-{size[0]}x{size[1]}.bgra"
    path.write_bytes(data)
    return str(path), size[0], size[1]
