"""Cuando arranca, falla o se cierra un tramo: el doblaje, los canales de Orbital, Trakt y el avance guardado."""

from __future__ import annotations

import math
import threading
import time

from .. import player_ui
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
from ..scrobble import not_the_video
from ..trakt_sync import CHANNEL_DONE
from .base import SYNTHETIC_RESYNC_AFTER, _num, log
from .pip import _Pip


class _Lifecycle(_Pip):
    """Arranque, fallas, Trakt y el avance."""

    def _started(self, segment: Segment) -> None:
        """Primera imagen de este archivo: avisos, subtítulos, capítulos y la barra."""
        if not segment.live:
            self._lift_curtain(segment)
            self._end_loading(target=segment)  # «Cargando…» se desvanece mientras el episodio aparece
        if self._filler(segment):
            return self._fail(segment, filler=True)
        tracks = self.mpv.get("track-list")
        tracks = tracks if isinstance(tracks, list) else []  # una respuesta rara de mpv nunca tumba al vigilante
        chapters = self.mpv.get("chapter-list")
        chapters = chapters if isinstance(chapters, list) else []
        segment.chapters = [c for c in chapters if isinstance(c, dict) and isinstance(c.get("time"), (int, float))]
        if segment.meta.get("synthetic"):
            if segment.duration and segment.start > 5 and segment.position >= segment.duration - 10:
                return self._at_end(segment)  # lo que iba al aire ya acabó (duraba menos de lo estimado): el siguiente
            return self._synthetic_started(segment, tracks)
        if segment.duration and segment.start > 5 and segment.position >= segment.duration - 30:
            # Donde ibas queda más allá del final de este archivo (otra fuente, otra edición): desde el
            # principio, en vez de saltar al final y dar la película por vista.
            self.mpv.command("seek", 0, "absolute")
            segment.position, segment.start = 0.0, 0.0
            self.toast("Esta versión es más corta · empieza desde el principio", 4)
            self._ensure_subtitles(self._subs_lang, self._fallback_subs)
            self.show_hud()
            return
        note = self._safe(self.on_tracks, segment.meta, tracks) if self.on_tracks else None
        if isinstance(note, str) and note:
            self.toast(note, 7)  # «Esta versión no trae latino: sus pistas son inglés y castellano · X › Audio…»
        elif wrong_audio(tracks, self._audio_lang):
            # El archivo dice ser de otro idioma (un doblaje mal etiquetado): avisa en vez de callar.
            self.toast("Esta versión no trae audio en tu idioma · Y para elegir otra", 6)
        elif segment.start > 5:
            self.toast("Sigues donde te quedaste · ◀ regresa", 3.5)
        self._pick_dub(segment, tracks)
        if not self._apply_sub_pick(tracks):
            self._ensure_subtitles(self._subs_lang, self._fallback_subs)
        self.show_hud()  # al empezar: qué estás viendo y qué hace cada botón

    def _pick_dub(self, segment: Segment, tracks: list) -> None:
        """Un archivo con dos pistas en español (latino y castellano, las dos «spa»): la del doblaje que quieres. mpv elige
        por idioma y no sabe cuál es cuál; el título de la pista sí lo dice. «Continuar» (el audio con que lo dejaste) va
        después y manda."""
        if self._audio_lang != "es" or self.spanish_provider is None:
            return
        variant = self._safe(self.spanish_provider, segment.meta)
        if variant not in ("es-419", "es-ES"):
            return
        pick = dub_track(tracks, "latino" if variant == "es-419" else "castellano")
        selected = next((t.get("id") for t in tracks if t.get("type") == "audio" and t.get("selected")), None)
        if isinstance(pick, int) and not isinstance(pick, bool) and pick != selected:
            self.mpv.command("set_property", "aid", pick)

    def _synthetic_tick(self, segment: Segment, now: float, paused: bool) -> None:
        """Un canal de Orbital va al aire aunque no lo veas: tras una pausa de más de un minuto, al seguir, regresa a lo
        que va a esta hora (como la tele en vivo). Y la programación aprende cuánto dura de verdad cada episodio."""
        if segment.duration and not segment.duration_told and self.on_synthetic_duration:
            segment.duration_told = True
            self._safe(self.on_synthetic_duration, segment.meta, segment.duration)
        if paused:
            segment.paused_at = segment.paused_at or now
            return
        away, segment.paused_at = (now - segment.paused_at if segment.paused_at else 0), None
        if away > SYNTHETIC_RESYNC_AFTER and self.on_synthetic_resync and not segment.next_loading:
            segment.next_loading = time.monotonic()
            self.toast(f"De vuelta al aire · {segment.title}", 4)
            self._in_background(self._synthetic_resync, segment, failed="No pude volver a lo que va al aire")

    def _synthetic_resync(self, segment: Segment) -> bool:
        """Si no se pudo volver al aire, sigue lo que ya veías y su final vuelve a pedir lo que sigue (antes quedaba
        marcado como «cargando» y, al acabar el episodio, el canal se quedaba en el último cuadro)."""
        ok = False
        try:
            ok = bool(self.on_synthetic_resync and self.on_synthetic_resync(segment.meta))
        finally:
            if not ok:
                segment.next_loading = 0.0
        return ok

    def _synthetic_started(self, segment: Segment, tracks: list) -> None:
        """Un canal de Orbital: la pista del doblaje del canal (si el archivo no la trae, otra fuente) y qué va."""
        pick = dub_track(tracks, segment.meta.get("dub") or "latino")
        if pick is False:
            log.info("%s no trae audio %s: otra fuente", segment.meta.get("detail"), segment.meta.get("dub"))
            return self._fail(segment)
        if pick is not None:
            self.mpv.command("set_property", "aid", pick)
        self.mpv.command("set_property", "sid", "no")
        self.toast(f"Al aire · {segment.meta.get('detail') or segment.title}", 4)
        self.show_hud()

    def _fail_channel(self, segment: Segment) -> None:
        """Un canal no abrió o se cortó: se marca y, si hay otro, se pasa a él (tv.py decide cuál)."""
        was_playing = segment.playing
        log.info("El canal %s %s", segment.title, "se cortó" if was_playing else "no abrió")
        retrying = bool(self.on_channel_failed and self._safe(self.on_channel_failed, segment.meta, was_playing))
        if not retrying and self.segment is segment:
            self.toast("Sin señal en este canal · ▲▼ para cambiar", 5)
            self.show_hud()  # «Sin señal», a la vista hasta que hagas algo

    def _filler(self, segment: Segment) -> bool:
        """Lo que da imagen dura tan poco que no puede ser el título: el video de aviso de la fuente (Real-Debrid manda uno de
        ~30 s cuando aún no lo tiene). Antes se veía entero, «terminaba» y saltaba al siguiente episodio."""
        return (not segment.live and not segment.failed and not segment.meta.get("clip")
                and not_the_video(segment.meta, segment.duration))

    def _fail(self, segment: Segment, filler: bool = False) -> None:
        if segment.failed or segment.closed:
            return
        segment.failed = True
        if filler:  # la otra versión, desde donde ibas (no desde el segundo del relleno)
            log.info("%s: la fuente mandó un relleno de %d s, no el video", segment.title, segment.duration)
            segment.position = segment.start
        if segment.live:
            return self._fail_channel(segment)
        if segment.meta.get("synthetic"):
            return self._fail_synthetic(segment)
        if segment.meta.get("clip"):  # un tráiler no tiene otra versión que probar
            log.info("El tráiler de %s %s", segment.title, "se cortó" if segment.playing else "no arrancó")
            self.toast("No pude reproducir el tráiler", 4)
            timer = threading.Timer(4, lambda: self.segment is segment and self._quit())
            timer.daemon = True
            timer.start()
            return None
        log.info("La fuente de %s %s", segment.title, "se cortó" if segment.playing else "no arrancó")
        retrying = False
        if self.on_failed:
            self.toast("Esa versión no abrió · regreso a la de antes…" if segment.meta.get("back_to") is not None
                       else "Esa versión todavía no está en la nube · probando otra…" if filler
                       else "Esa versión falló · probando otra…", 6)
            retrying = bool(self._safe(self.on_failed, segment.meta, segment.position, True))
        if not retrying:
            self._end_loading(target=segment)
            if not self.on_failed:  # con on_failed, Orbital ya dijo por qué y qué hacer (watch.give_up_words)
                self.toast("No pude reproducir esto con ninguna versión", 4)
            timer = threading.Timer(4, lambda: self.segment is segment and self._quit())
            timer.daemon = True
            timer.start()

    def _fail_synthetic(self, segment: Segment) -> None:
        """Un episodio de un canal de Orbital no abrió: el canal prueba otra fuente u otro episodio (en su hilo)."""
        log.info("%s: la fuente de %s %s", segment.title, segment.meta.get("detail"), "se cortó" if segment.playing else "no arrancó")
        handler = self.on_synthetic_failed

        def retry() -> None:
            if not (handler and self._safe(handler, segment.meta)) and self.segment is segment:
                self.toast(f"No pude seguir con {segment.title}", 4)
                timer = threading.Timer(4, lambda: self.segment is segment and self._quit())
                timer.daemon = True
                timer.start()

        threading.Thread(target=retry, daemon=True, name="synthetic-retry").start()

    def _scrobble(self, action: str, segment: Segment) -> None:
        """Avisa a Trakt (en su propio hilo: la red no toca el video). Nunca un canal en vivo."""
        if segment.live or segment.meta.get("synthetic") or segment.meta.get("clip") or not self.on_scrobble or not segment.duration:
            return  # un canal de Orbital tampoco (es la tele de fondo), ni un tráiler
        if action == "start":
            segment.scrobbling = True
            segment.last_checkpoint = time.monotonic()
        elif not segment.scrobbling:
            return  # pausar o parar algo que Trakt nunca supo que empezó
        elif action == "stop":
            segment.scrobbling = False
        meta = {**segment.meta, "finished": True} if segment.finished else segment.meta  # créditos o «Ver ahora»: visto
        self._safe(self.on_scrobble, action, meta, segment.position, segment.duration)

    def _channel_progress(self, segment: Segment, closing: bool) -> None:
        """V2: un episodio de un canal de Orbital no guarda en Stremio ni avisa a Trakt mientras lo ves (es la tele de fondo),
        pero lo que dejas a medias se puede retomar y lo terminado queda visto, sin mover tu orden (trakt_sync.ChannelDetours)."""
        if not self.on_channel or not segment.duration or not segment.meta.get("video_id"):
            return
        done = segment.finished or segment.position >= segment.duration * CHANNEL_DONE
        if not closing and done:
            return  # el final se dice una sola vez, al cerrar
        threading.Thread(target=self._safe, args=(self.on_channel, segment.meta, segment.position, segment.duration,
                                                   segment.watched, closing and done), daemon=True).start()

    def _save_progress(self, segment: Segment) -> None:
        segment.last_save = time.monotonic()
        if segment.meta.get("synthetic") and not segment.live:
            return self._channel_progress(segment, closing=False)
        delta = segment.watched - segment.saved_watched
        if segment.live or segment.meta.get("synthetic") or segment.meta.get("clip") or not self.on_progress \
                or not segment.duration or delta <= 0:
            return
        segment.saved_watched = segment.watched
        threading.Thread(target=self._safe, args=(self.on_progress, segment.meta, segment.position,
                                                   segment.duration, delta), daemon=True).start()

    def _close_segment(self, segment: Segment) -> None:
        """Lo que se vio de este archivo, a Stremio (al salir o al pasar al siguiente)."""
        with self._closing:  # el vigilante y play() a la vez: lo visto se guarda una sola vez
            if segment.closed:
                return
            segment.closed = True
        if segment.playing and not segment.live:  # cómo se vio: para saber, si «se trabó», si fue la red o la imagen (#12)
            self._drops_tick(segment, paused=True)  # lo último que haya (si mpv aún contesta), sin contarlo como tirón
            log.info("%s: %d min vistos, %d esperas de búfer (%.0f s), %d cuadros perdidos (%d al decodificar), %d tirones",
                     segment.title, int(segment.watched // 60), segment.waits, segment.waited, segment.drops,
                     segment.decoder_drops, segment.stutters)
        if segment.meta.get("synthetic") and not segment.live:
            return self._channel_progress(segment, closing=True)  # V2: lo de un canal, aparte
        if segment.live or segment.meta.get("clip"):
            return  # la tele en vivo y un tráiler no guardan dónde ibas ni entran en «Seguir viendo»
        self._scrobble("stop", segment)  # Trakt: lo que llevabas (≥ 80 % lo marca visto)
        if self.on_finished and segment.duration and not (segment.watched < 20 and segment.position >= segment.duration * .9):
            # (Casi nada visto y «al final»: un salto raro, no la película vista de principio a fin.)
            self._safe(self.on_finished, segment.meta, segment.duration if segment.finished else segment.position,
                       segment.duration, segment.watched - segment.saved_watched)

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
        if waiting and not self._buffering:
            self._wait_started = time.monotonic()  # una espera nueva: al terminar se anota cuánto duró (ver abajo)
        if waiting:
            percent = self.mpv.get("cache-buffering-state")
            self._buffering = True
            known = isinstance(percent, (int, float)) and math.isfinite(percent)
            self._show_notice(player_ui.toast_ass(f"Cargando… {int(percent)} %" if known else "Cargando…",
                                                  top=player_ui.BUFFER_Y), 2, layer=self.BUFFER)
        elif self._buffering:
            self._buffering = False
            self._overlay(self.BUFFER, None)  # solo el «Cargando…»: el aviso que estaba sigue
            self._log_wait()

    def _log_wait(self) -> None:
        """Cada «Cargando…» a media reproducción, en el registro: cuánto duró, cuánto quedaba por delante y a qué velocidad
        bajaba. Antes solo se veía en pantalla: cuando algo «se trababa», no había cómo saber por qué (#12)."""
        segment = self.segment
        lasted = time.monotonic() - getattr(self, "_wait_started", time.monotonic())
        if segment is not None:
            segment.waits += 1
            segment.waited += lasted
        speed = self.mpv.get("cache-speed")
        log.info("Esperó al búfer %.1f s en %s (min %s): por delante %s s, bajando a %s Mbps", lasted,
                 segment.title if segment else "?", int(segment.position // 60) if segment else "?",
                 _num(self.mpv.get("demuxer-cache-duration")), _num(speed * 8 / 1e6) if isinstance(speed, (int, float)) else "?")
