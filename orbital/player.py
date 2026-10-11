"""Reproductor de Orbital: mpv a pantalla completa, manejado por el mando.

Orbital elige la fuente (library/streams.py) y la abre en mpv con un canal de control
(--input-ipc-server). Los botones del mando no se traducen a teclas: Orbital manda comandos a mpv
(pausa, adelantar, volumen, audio, subtítulos), así que funciona igual en cualquier idioma de
teclado y sin depender de los atajos de mpv.

  A pausa · ←/→ adelantar (mantener: cada vez más rápido) · LB/RB capítulo (o ±1 min)
  LT/RT episodio anterior/siguiente · ↑/↓ volumen · X audio · Y subtítulos · B oculta la barra
  y, con la barra oculta, sale (guarda dónde ibas)

Además, como un servicio de streaming de verdad:
  * Si una fuente no arranca (o se corta), prueba sola la siguiente y sigue donde ibas.
  * Al final de un episodio, tarjeta "Siguiente episodio" con cuenta atrás (B la cancela); el
    siguiente se carga en el mismo mpv, sin volver al menú. Tras 3 seguidos sin tocar el mando,
    pregunta "¿Sigues viendo?".
  * "Saltar intro" cuando el archivo marca la intro con capítulos (Intro, Opening, Recap…).
  * El avance se guarda cada minuto y al pausar, no solo al salir.

Piezas: mpv.py (la tubería con mpv), playback.py (comando, idiomas, capítulos, datos de lo que se
ve), player_screen.py (barra, tarjetas, menús y botones) y aquí el reproductor que lo junta: arrancar,
vigilar, guardar el avance, fuentes que fallan y el siguiente episodio.
"""

from __future__ import annotations

import logging
import math
import subprocess
import threading
import time

from . import player_ui
from .gamepad import (  # noqa: F401 - las pruebas los piden a player
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
from .mpv import PIPE, Mpv  # noqa: F401 - se importan desde aquí
from .playback import (  # noqa: F401 - el resto de Orbital y las pruebas las piden a player
    CHAPTER_SEEK,
    CREDITS,
    INTRO,
    LANGS,
    LB,
    OSD_STYLE,
    RB,
    RECAP,
    SAVE_EVERY,
    SKIP_VISIBLE,
    STARTUP_TIMEOUT,
    STILL_WATCHING_AFTER,
    STREMIO_SERVER,
    TOUCH_BINDINGS,
    UPNEXT_AT,
    UPNEXT_COUNTDOWN,
    UPNEXT_LOOKAHEAD,
    Playback,
    PlayerRemote,
    Segment,
    build_command,
    build_lang_list,
    chapter_kind,
    find_mpv,
    has_language,
    idle_expired,
    input_conf,
    seek_step,
    stream_url,
    subtitle_options,
    wrong_audio,
)
from .player_screen import PlayerScreen

log = logging.getLogger(__name__)


class OrbitalPlayer(PlayerScreen):
    """Arranca mpv, lo vigila y avisa cuánto se vio (para Seguir viendo).

    El proceso lo lanza el Launcher de Orbital (así Home, la pausa, Select+Start y la vuelta a
    Orbital funcionan igual que con un juego); aquí se sigue la posición por la tubería y se
    decide qué pasa al final, si una fuente falla, etc. El catálogo pone los "proveedores":
    siguiente episodio, otras fuentes, cambiar de fuente.
    """

    POLL = 1.0
    HUD_SECONDS = 4.0

    def __init__(self, on_finished=None, mpv: Mpv | None = None, idle_seconds: float = 0, on_idle=None) -> None:
        self.mpv = mpv or Mpv()
        self.remote = PlayerRemote(self.press)
        self.current: Playback | None = None
        self.segment: Segment | None = None
        self.menu: player_ui.Panel | None = None  # panel de columnas abierto (X o Y)
        self._hud_timer: threading.Timer | None = None
        self._toast_timer: threading.Timer | None = None
        self._hud_visible = False
        self._card: dict | None = None  # {"kind": "skip" | "next" | "still", ...}
        self._subs_lang = "en"
        self._audio_lang = "en"
        self._fallback_subs = None
        self._user_quit = False  # B, Orbital o la voz lo cerraron: no es un fallo
        self.last_end: dict | None = None  # cómo terminó lo último (para el aviso al volver)
        self._quiet_episodes = 0  # episodios encadenados sin tocar el mando
        self._buffering = False
        self._loading_until = 0.0  # tras «Ver ahora», A no pausa lo que está cargando
        self.sub_scale = 1.0
        self.on_finished = on_finished  # (meta, posición, duración, segundos vistos)
        self.on_progress = None  # igual que on_finished, cada minuto y al pausar
        self.on_failed = None  # (meta, posición, sigue_abierto) -> True si se intenta con otra fuente
        self.next_provider = None  # (meta) -> {"label", "title", "play"} | None
        self.sources_provider = None  # (meta) -> [{"id", "label", "current"}]
        self.on_switch_source = None  # (meta, id_fuente, posición)
        self.on_episode = None  # (meta, ±1): episodio anterior / siguiente
        self.episodes_provider = None  # (meta) -> [{"id", "label", "current", "progress"?}] de la temporada
        self.on_play_episode = None  # (meta, id_del_episodio): ver ese episodio
        self.on_sub_scale = None  # (escala): para recordarla
        self.on_language = None  # (meta, "audio" | "subtitles", código): el idioma que elegiste
        # Un video olvidado en pausa (saliste con Home y te fuiste) se cierra solo; el avance se guarda.
        self.idle_seconds = idle_seconds
        self.on_idle = on_idle  # (título, minutos): para avisar en Orbital

    # --- arrancar / cambiar de archivo -------------------------------------------------------
    def play(self, run, mpv_exe: str, url: str, title: str, meta: dict, *, subtitles: str = "en",
             fallback_subs=None, **options) -> subprocess.Popen:
        """`run(argv)` lanza el proceso; `fallback_subs()` da URLs de subtítulos si el video no trae."""
        self.stop()
        process = run(build_command(mpv_exe, url, title, subtitles=subtitles, bindings=input_conf(),
                                    sub_scale=self.sub_scale, **options))
        self.menu = None
        self._card = None
        self._user_quit = False
        self.last_end = None
        self._quiet_episodes = 0
        self._subs_lang, self._fallback_subs = subtitles, fallback_subs
        self._audio_lang = options.get("audio", "en")
        playback = Playback(title, process, time.time(), meta)
        self.current = playback
        self.segment = Segment(meta, title, url, start=float(options.get("start") or 0))
        if hasattr(self.mpv, "start_observing"):
            self.mpv.start_observing()  # mpv avisa de pausa, posición… en vez de preguntarle cada segundo
        threading.Thread(target=self._watch, args=(playback,), daemon=True, name="mpv").start()
        log.info("Reproduciendo en mpv: %s", title)
        return process

    def load(self, url: str, title: str, meta: dict, *, start: float = 0, fallback_subs=None,
             subtitles: str | None = None, message: str | None = None) -> bool:
        """Otro archivo en la misma ventana: el siguiente episodio, u otra fuente del mismo título.
        Lo que se vio del anterior se guarda. False si mpv ya no está abierto."""
        if not self.playing:
            return False
        previous = self.segment
        same = previous is not None and previous.meta.get("video_id") == meta.get("video_id")
        segment = Segment(meta, title, url, start=start)
        if same:  # la misma película en otra fuente: lo visto sigue contando como una sola vez
            previous.closed = True
            segment.watched, segment.saved_watched = previous.watched, previous.saved_watched
            segment.duration = previous.duration
        elif previous is not None:
            self._close_segment(previous)  # otro episodio: lo visto del anterior se guarda ya
        if self.menu is not None:  # el panel era del episodio anterior
            self.menu = None
            self._overlay(2, None)
        self._hide_card()
        if fallback_subs is not None:
            self._fallback_subs = fallback_subs
        if subtitles is not None:
            self._subs_lang = subtitles
        self.segment = segment
        if self.current is not None:
            self.current.title, self.current.meta = title, meta
        self.mpv.command("set_property", "force-media-title", title)
        self.mpv.command("set_property", "start", f"{int(start)}" if start > 5 else "0")
        self.mpv.command("set_property", "pause", False)
        self.mpv.command("loadfile", url, "replace")
        self.toast(message or f"Cargando {title}…", 4)
        log.info("Cargando en el mismo mpv: %s", title)
        return True

    # --- vigilancia ---------------------------------------------------------------------------
    def _watch(self, playback: Playback) -> None:
        was_paused = False
        paused_since: float | None = None
        while playback.process.poll() is None:
            time.sleep(self.POLL)
            segment = self.segment
            if segment is None or self.current is not playback:
                continue
            try:
                now = time.monotonic()
                paused = bool(self.mpv.get("pause"))
                if paused != was_paused and segment.playing:
                    self.show_hud()  # pausado con un toque en la pantalla (o por otro lado): que se vea la barra
                    if paused:
                        self._save_progress(segment)  # pausar = buen momento para guardar
                was_paused = paused
                paused_since = (paused_since or now) if paused else None
                if paused_since is not None and idle_expired(paused_since, now, self.idle_seconds):
                    log.info("%s llevaba %d min en pausa: se cierra (el avance queda guardado)",
                             playback.title, self.idle_seconds // 60)
                    self._user_quit = True
                    self._quit()
                    if self.on_idle:
                        self.on_idle(playback.title, int(self.idle_seconds // 60))
                    paused_since = None
                    continue
                self.tick(segment, now, paused)
            except Exception:  # noqa: BLE001 - el vigilante no se puede morir a media película
                log.exception("Error vigilando mpv")
        self.finish(playback)

    def finish(self, playback: Playback) -> None:
        """mpv se cerró: guarda lo visto o, si no llegó a verse nada y nadie lo cerró, avisa."""
        segment = self.segment
        if self.current is playback:
            self.current = None
        self._card = None
        if segment is None or segment.closed:
            return
        if segment.playing:
            self._close_segment(segment)
        elif not self._user_quit and not segment.failed and self.on_failed:
            segment.failed = True  # mpv se cayó antes de mostrar nada: avisar, no quedarse callado
            self._safe(self.on_failed, segment.meta, 0.0, False)

    def tick(self, segment: Segment, now: float, paused: bool) -> None:
        """Un vistazo por segundo: arrancó, se cortó, capítulos, siguiente episodio, final."""
        pos, dur = self.mpv.get("time-pos"), self.mpv.get("duration")
        idle = bool(self.mpv.get("idle-active"))
        if not segment.playing:
            if isinstance(dur, (int, float)) and dur > 0 and isinstance(pos, (int, float)) and not idle:
                segment.playing = True
                segment.position, segment.duration = float(pos), float(dur)
                segment.last_tick = segment.last_save = now
                self._started(segment)
            elif (idle and now - segment.loaded > 2.5) or now - segment.loaded > STARTUP_TIMEOUT:
                self._fail(segment)
            return
        if idle:  # el archivo se cortó a media reproducción (stream caído): otra fuente, mismo punto
            self._fail(segment)
            return
        if isinstance(pos, (int, float)) and isinstance(dur, (int, float)) and dur > 0:
            if not paused:
                segment.watched += min(now - segment.last_tick, abs(pos - segment.position) + 1)
            segment.position, segment.duration = float(pos), float(dur)
        segment.last_tick = now
        self._buffering_state(paused)
        if now - segment.last_save >= SAVE_EVERY and not paused:
            self._save_progress(segment)
        self._chapters_tick(segment, now)
        self._upnext_tick(segment, now)
        if self.mpv.get("eof-reached"):
            self._at_end(segment)

    def _started(self, segment: Segment) -> None:
        """Primera imagen de este archivo: avisos, subtítulos, capítulos y la barra."""
        tracks = self.mpv.get("track-list") or []
        chapters = self.mpv.get("chapter-list") or []
        segment.chapters = [c for c in chapters if isinstance(c, dict) and isinstance(c.get("time"), (int, float))]
        if wrong_audio(tracks, self._audio_lang):
            # El archivo dice ser de otro idioma (un doblaje mal etiquetado): avisa en vez de callar.
            self.toast("Esta fuente no trae audio en tu idioma · Y › Fuente para elegir otra", 6)
        elif segment.start > 5:
            self.toast("Sigues donde te quedaste · ◀ regresa", 3.5)
        self._ensure_subtitles(self._subs_lang, self._fallback_subs)
        self.show_hud()  # al empezar: qué estás viendo y qué hace cada botón

    def _fail(self, segment: Segment) -> None:
        if segment.failed or segment.closed:
            return
        segment.failed = True
        log.info("La fuente de %s %s", segment.title, "se cortó" if segment.playing else "no arrancó")
        retrying = False
        if self.on_failed:
            self.toast("Esa fuente falló · probando otra…", 6)
            retrying = bool(self._safe(self.on_failed, segment.meta, segment.position, True))
        if not retrying:
            self.toast("No pude reproducir esto con ninguna fuente", 4)
            timer = threading.Timer(4, lambda: self.segment is segment and self._quit())
            timer.daemon = True
            timer.start()

    def _save_progress(self, segment: Segment) -> None:
        segment.last_save = time.monotonic()
        delta = segment.watched - segment.saved_watched
        if not self.on_progress or not segment.duration or delta <= 0:
            return
        segment.saved_watched = segment.watched
        threading.Thread(target=self._safe, args=(self.on_progress, segment.meta, segment.position,
                                                   segment.duration, delta), daemon=True).start()

    def _close_segment(self, segment: Segment) -> None:
        """Lo que se vio de este archivo, a Stremio (al salir o al pasar al siguiente)."""
        if segment.closed:
            return
        segment.closed = True
        if self.on_finished and segment.duration:
            self._safe(self.on_finished, segment.meta, segment.position, segment.duration,
                       segment.watched - segment.saved_watched)

    def _in_background(self, fn, *args, failed: str) -> None:
        """Algo que tarda (cargar otro episodio, otra fuente) en su hilo; si falla, se avisa en pantalla."""
        def run() -> None:
            try:
                ok = fn(*args)
            except Exception:  # noqa: BLE001
                log.exception("Error en %s", getattr(fn, "__name__", fn))
                ok = False
            if ok is False:
                self.toast(failed, 4)

        threading.Thread(target=run, daemon=True, name="player-task").start()

    @staticmethod
    def _safe(fn, *args):
        try:
            return fn(*args)
        except Exception:  # noqa: BLE001
            log.exception("Error en %s", getattr(fn, "__name__", fn))
            return None

    def _buffering_state(self, paused: bool) -> None:
        waiting = bool(self.mpv.get("paused-for-cache")) and not paused
        if waiting:
            percent = self.mpv.get("cache-buffering-state")
            self._buffering = True
            known = isinstance(percent, (int, float)) and math.isfinite(percent)
            self.toast(f"Cargando… {int(percent)} %" if known else "Cargando…", 2)
        elif self._buffering:
            self._buffering = False
            self._overlay(3, None)

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

            def ask() -> None:
                segment.upnext = self._safe(self.next_provider, segment.meta) or False

            threading.Thread(target=ask, daemon=True, name="upnext").start()
        if not segment.upnext or segment.upnext_dismissed or self.menu is not None:
            return
        card = self._card
        if card is None and (remaining <= UPNEXT_AT or credits):
            still = self._quiet_episodes >= STILL_WATCHING_AFTER - 1
            segment.upnext_deadline = None if still else now + UPNEXT_COUNTDOWN
            self._show_card({"kind": "still" if still else "next", "segment": segment}, now)
        elif card is not None and card.get("segment") is segment and card["kind"] == "next":
            if segment.upnext_deadline is not None and now >= segment.upnext_deadline:
                self._play_next(segment, auto=True)
            else:
                self._draw_card(now)

    def _at_end(self, segment: Segment) -> None:
        """Llegó al final (mpv se queda en el último cuadro)."""
        if segment.closed:
            return
        if segment.upnext and not segment.upnext_dismissed:
            if self._card is None or self._card.get("kind") != "still":
                self._play_next(segment, auto=True)
            return  # "¿Sigues viendo?": espera tu respuesta
        if segment.meta.get("kind") == "series" and segment.upnext is None and segment.upnext_requested:
            return  # aún buscando el siguiente: un segundo más
        self._user_quit = True
        self._quit()

    def _play_next(self, segment: Segment, auto: bool) -> None:
        info = segment.upnext
        if not isinstance(info, dict) or segment.closed:
            return
        self._hide_card()
        self._quiet_episodes = self._quiet_episodes + 1 if auto else 0
        segment.upnext_dismissed = True  # que no se dispare dos veces
        self.toast(f"Cargando {info.get('label') or 'el siguiente episodio'}…", 6)
        self._in_background(info["play"], failed="No pude cargar el siguiente episodio")
        self._loading_until = time.monotonic() + 3  # un segundo A no pausa lo que está cargando

    # --- subtítulos ------------------------------------------------------------------------------
    def _ensure_subtitles(self, lang: str, fallback_subs) -> None:
        if not lang or fallback_subs is None:
            return
        codes = {c.lower() for c in build_lang_list(lang)}
        if has_language(self.mpv.get("track-list") or [], "sub", codes):
            return  # el video ya trae subtítulos en tu idioma (mpv los eligió por --slang)
        try:
            urls = fallback_subs()
        except Exception:  # noqa: BLE001
            log.exception("No pude buscar subtítulos")
            return
        if urls:
            self.mpv.command("sub-add", urls[0], "select", "Subtítulos", lang)
            log.info("Subtítulos de un addon (%d disponibles)", len(urls))

    def pause(self) -> None:
        self.mpv.command("set_property", "pause", True)

    def show_progress(self) -> None:
        self.show_hud()

    # --- para la voz -----------------------------------------------------------------------
    def set_pause(self, paused: bool) -> None:
        self.mpv.command("set_property", "pause", paused)
        self.show_hud()

    def seek(self, seconds: float) -> None:
        self.mpv.command("seek", seconds, "relative")
        self.show_hud()

    def select_language(self, kind: str, lang: str) -> bool:
        """Cambia a la pista de audio o subtítulos en ese idioma, si el video la trae."""
        codes = {c.lower() for c in build_lang_list(lang)}
        track = next((t for t in self.mpv.get("track-list") or []
                      if t.get("type") == kind and str(t.get("lang") or "").lower() in codes), None)
        if track is None:
            return False
        self.mpv.command("set_property", "aid" if kind == "audio" else "sid", track["id"])
        name = player_ui.language(track.get("lang")) or f"pista {track['id']}"
        self.toast(f"{'Audio' if kind == 'audio' else 'Subtítulos'}: {name}")
        return True

    def add_subtitles(self, url: str, lang: str) -> None:
        self.mpv.command("sub-add", url, "select", "Subtítulos", lang)
        self.toast(f"Subtítulos: {player_ui.language(lang)}")

    def subtitles_off(self) -> None:
        self.mpv.command("set_property", "sid", "no")
        self.toast("Sin subtítulos")

    def stop(self) -> None:
        if self.current and self.current.process.poll() is None:
            self._user_quit = True
            self._quit()
            try:
                self.current.process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                self.current.process.kill()

    @property
    def playing(self) -> bool:
        return self.current is not None and self.current.process.poll() is None
