"""Capítulos, saltar la intro o los créditos y el siguiente episodio."""

from __future__ import annotations

import threading
import time

from ..gamepad import (  # noqa: F401 - las pruebas los piden a player
    A_BUTTON,
    B_BUTTON,
    BACK,
    DPAD_DOWN,
    DPAD_LEFT,
    DPAD_RIGHT,
    DPAD_UP,
    GUIDE,
    LT,
    RT,
    START,
    X_BUTTON,
    Y_BUTTON,
)
from ..mpv import PIPE, Mpv  # noqa: F401 - se importan desde aquí
from ..playback import (  # noqa: F401 - el resto de Orbital y las pruebas las piden a player
    CHAPTER_SEEK,
    CREDITS,
    INTRO,
    LANGS,
    LB,
    LIVE_SETTLE,
    LIVE_STARTUP_TIMEOUT,
    LIVE_USER_AGENT,
    MOUSE_SCRIPT,
    MOUSE_SCRIPT_NAME,
    OSD_STYLE,
    RB,
    RECAP,
    SAVE_EVERY,
    SCROBBLE_SEEK,
    SKIP_VISIBLE,
    STARTUP_TIMEOUT,
    STILL_WATCHING_AFTER,
    TOUCH_BINDINGS,
    UPNEXT_AT,
    UPNEXT_COUNTDOWN,
    UPNEXT_LOOKAHEAD,
    Playback,
    PlayerRemote,
    Segment,
    base_language,
    build_command,
    build_lang_list,
    chapter_kind,
    dub_track,
    find_mpv,
    has_language,
    idle_expired,
    input_conf,
    seek_step,
    stream_url,
    subtitle_options,
    track_properties,
    wrong_audio,
)
from .base import log
from .lifecycle import _Lifecycle


class _UpNext(_Lifecycle):
    """Capítulos, saltar la intro y el siguiente episodio."""

    # --- capítulos: saltar intro, créditos ---------------------------------------------------
    def _chapter_now(self, segment: Segment) -> tuple[int, dict | None]:
        index = self.mpv.get("chapter")
        if not isinstance(index, int) or not (0 <= index < len(segment.chapters)):
            return -1, None
        return index, segment.chapters[index]

    def _chapters_tick(self, segment: Segment, now: float) -> None:
        if self._card and self._card["kind"] == "skip" and now >= self._card["until"]:
            self._hide_card()
        if not segment.chapters or self.menu is not None or self._card:
            return
        index, chapter = self._chapter_now(segment)
        if chapter is None or index in segment.skip_offered:
            return
        title = chapter.get("title", "")
        if chapter_kind(title) == "intro" and index + 1 < len(segment.chapters):
            target = float(segment.chapters[index + 1]["time"])
            if target - segment.position > 8:
                segment.skip_offered.add(index)
                label = "Saltar resumen" if RECAP.search(title) else "Saltar intro"
                self._show_card({"kind": "skip", "to": target, "until": now + SKIP_VISIBLE, "label": label})

    def skip_intro(self) -> str | None:
        """«Salta la intro» por voz: la tarjeta si está a la vista, o la intro en la que vas. None si el
        video no marca la intro (sin capítulos no se adivina)."""
        card = self._card
        if card and card["kind"] == "skip":
            self._hide_card()
            self.mpv.command("seek", card["to"], "absolute")
            return card["label"]
        segment = self.segment
        if segment is None or not segment.chapters:
            return None
        index, chapter = self._chapter_now(segment)
        if chapter is None or chapter_kind(chapter.get("title", "")) != "intro" or index + 1 >= len(segment.chapters):
            return None
        segment.skip_offered.add(index)
        self.mpv.command("seek", float(segment.chapters[index + 1]["time"]), "absolute")
        return "Saltar resumen" if RECAP.search(chapter.get("title", "")) else "Saltar intro"

    def _in_credits(self, segment: Segment) -> bool:
        _, chapter = self._chapter_now(segment)
        return bool(chapter and chapter_kind(chapter.get("title", "")) == "credits")

    # --- siguiente episodio --------------------------------------------------------------------
    def _upnext_tick(self, segment: Segment, now: float) -> None:
        if segment.meta.get("kind") != "series" or not self.next_provider or not segment.duration:
            return
        remaining = segment.duration - segment.position
        credits = self._in_credits(segment)
        if not segment.upnext_requested and (remaining <= UPNEXT_LOOKAHEAD or credits):
            segment.upnext_requested = True
            provider = self.next_provider

            def ask() -> None:
                try:
                    segment.upnext = provider(segment.meta) or False
                    if isinstance(segment.upnext, dict) and segment.upnext.get("still"):
                        self._still_for(segment.upnext["still"])  # el cuadro del episodio, listo antes de la tarjeta
                except Exception:  # noqa: BLE001 - Cinemeta no respondió: se pregunta otra vez (3 intentos)
                    log.exception("No pude saber el siguiente episodio")
                    segment.upnext_tries += 1
                    if segment.upnext_tries < 3:
                        segment.upnext_requested = False
                    else:
                        segment.upnext = False

            threading.Thread(target=ask, daemon=True, name="upnext").start()
        if not segment.upnext or segment.upnext_dismissed or self.menu is not None:
            return
        card = self._card
        if card is None and (remaining <= UPNEXT_AT or credits):
            if segment.upnext.get("ready") is False:  # Real-Debrid aún no lo tiene: lo dice y ofrece pedirlo (RD-4)
                segment.upnext_deadline = None
                self._show_card({"kind": "debrid", "segment": segment}, now)
                return
            still = self._quiet_episodes >= STILL_WATCHING_AFTER - 1
            segment.upnext_deadline = None if still else now + UPNEXT_COUNTDOWN
            self._show_card({"kind": "still" if still else "next", "segment": segment}, now)
        elif card is not None and card.get("segment") is segment and card["kind"] == "next":
            if segment.upnext_deadline is not None and now >= segment.upnext_deadline:
                self._play_next(segment, auto=True)
            elif not self.CARD_FRAME:  # sin animación (pruebas), la cuenta atrás va con este vistazo
                self._draw_card(now)

    def _request_next(self, segment: Segment) -> None:
        """A en «Real-Debrid todavía no lo tiene»: se le pide el siguiente episodio y te quedas en los créditos (RD-4)."""
        info = segment.upnext
        self._hide_card()
        segment.upnext_dismissed = True
        if not isinstance(info, dict) or not callable(info.get("request")):
            return

        if info.get("requested"):  # ya se lo pidió solo: el aviso «Ya está…» llega al terminar
            self.toast(f"Te aviso cuando {info.get('label') or 'el siguiente episodio'} esté listo", 4)
            return

        def run() -> None:
            try:
                info["request"]()
            except LookupError as exc:
                self.toast(str(exc), 6)
                return
            self.toast(f"Pedido a Real-Debrid · {info.get('label') or 'el siguiente episodio'} · Te aviso cuando esté", 5)

        threading.Thread(target=run, daemon=True, name="rd-request").start()

    def _play_next(self, segment: Segment, auto: bool) -> None:
        info = segment.upnext
        with self._next_lock:  # el anillo (su hilo) y el vigilante pueden llegar a la vez al final de la cuenta atrás
            if not isinstance(info, dict) or segment.closed or segment.next_loading:
                return
            segment.next_loading = time.monotonic()
        self._quiet_episodes = self._quiet_episodes + 1 if auto else 0
        segment.upnext_dismissed = True  # que no se dispare dos veces
        segment.finished = True  # «Ver ahora» en los créditos: este episodio ya se vio
        # La misma tarjeta pasa a «Cargando…» (no se va ni entra otra vez); el arco que le quedaba a la cuenta atrás se
        # vuelve el que gira. Antes se iba y salía otro aviso arriba a la derecha.
        card = self._card if self._card is not None and self._card.get("segment") is segment else None
        left = 0.0
        if card is not None and card["kind"] == "next" and segment.upnext_deadline is not None:
            left = max(0.0, min(1.0, (segment.upnext_deadline - time.monotonic()) / UPNEXT_COUNTDOWN))
        loading = {"kind": "loading", "segment": segment, "label": info.get("label") or "", "name": info.get("title") or "",
                   "still": info.get("still"), "since": time.monotonic(), "from": left}
        if card is not None and "shown" in card:
            loading["shown"] = card["shown"]
        self._show_card(loading)
        self._in_background(self._load_with_card, loading, info["play"], failed="No pude cargar el siguiente episodio")
        if not auto:  # tras «Ver ahora», un segundo A no pausa lo que está cargando
            self._loading_until = time.monotonic() + 3
