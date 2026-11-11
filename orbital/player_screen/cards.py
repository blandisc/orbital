"""Las tarjetas encima del video (siguiente episodio, cargando) y su imagen de fondo, y el lienzo con la forma de la pantalla."""

from __future__ import annotations

import math
import threading
import time

from .. import player_ui
from ..playback import UPNEXT_COUNTDOWN
from ..player_subs import SubtitleTrial
from .base import log, still_bgra


class _Cards(SubtitleTrial):
    """Las tarjetas encima del video y su imagen de fondo."""

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
