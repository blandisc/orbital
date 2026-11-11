"""El vigilante: sigue la posición, la memoria de mpv, el búfer y la TV en vivo; decide cuándo terminó."""

from __future__ import annotations

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
from ..scrobble import CHECKPOINT_SECONDS
from .base import CUT_MARGIN, log
from .launch import _Launch


class _Watching(_Launch):
    """El vigilante de la posición y de mpv."""

    # --- vigilancia ---------------------------------------------------------------------------
    def _watch(self, playback: Playback) -> None:
        was_paused = False
        paused_since: float | None = None
        memory_at = time.monotonic()
        while playback.process.poll() is None:
            time.sleep(self.POLL)
            segment = self.segment
            if segment is None or self.current is not playback:
                continue
            try:
                now = time.monotonic()
                if now - memory_at >= self.MEMORY_EVERY:
                    memory_at = now
                    self._check_memory(playback, segment)
                self._fit_canvas()
                paused = bool(self.mpv.get("pause"))
                if self._held:  # esperando a que se vaya la pantalla de carga: esa pausa no es tuya (sin barra ni aviso)
                    if segment.playing and now - segment.loaded > self.HOLD_MAX:
                        self.release_start()  # la pantalla de carga nunca avisó: que no se quede detenido
                    paused = False
                if paused != was_paused and segment.playing:
                    self.show_hud()  # pausado con un toque en la pantalla (o por otro lado): que se vea la barra
                    if paused:
                        self._save_progress(segment)  # pausar = buen momento para guardar
                    self._scrobble("pause" if paused else "start", segment)
                was_paused = paused
                paused = paused or (segment.live and self._away)  # un canal que dejaste con Home es un video olvidado
                paused_since = (paused_since or now) if paused else None
                if paused_since is not None and idle_expired(paused_since, now, self.idle_seconds):
                    log.info("%s llevaba %d min en pausa: se cierra (el avance queda guardado)",
                             playback.title, self.idle_seconds // 60)
                    self._user_quit = True
                    self._quit()
                    if self.on_idle:
                        minutes = int(self.idle_seconds // 60)
                        if segment.live:
                            self.on_idle(playback.title, minutes, live=True)
                        else:
                            self.on_idle(playback.title, minutes)
                    paused_since = None
                    continue
                self.tick(segment, now, paused)
            except Exception:  # noqa: BLE001 - el vigilante no se puede morir a media película
                log.exception("Error vigilando mpv")
        self.finish(playback)

    def _check_memory(self, playback: Playback, segment: Segment) -> None:
        """mpv ocupa demasiado: un canal se vuelve a abrir en un mpv nuevo (un parpadeo de 2 s, nada se pierde); un video
        avisa una vez (cortarlo a media película sería peor que lo lento)."""
        if playback.memory_handled or not segment.playing:
            return
        mb = self.memory_of(getattr(playback.process, "pid", 0) or 0)
        if mb < self.MEMORY_LIMIT_MB:
            return
        playback.memory_handled = True
        log.warning("mpv ocupa %d MB viendo %s", mb, playback.title)
        if segment.live and self.on_memory_full:
            threading.Thread(target=self._safe, args=(self.on_memory_full, dict(segment.meta)), daemon=True,
                             name="mpv-memory").start()
        elif not segment.live:
            self.toast(f"El reproductor ocupa mucha memoria ({mb / 1024:.1f} GB) · Si se pone lento, sal y vuelve: sigues donde ibas", 8)

    def finish(self, playback: Playback) -> None:
        """mpv se cerró: guarda lo visto o, si no llegó a verse nada y nadie lo cerró, avisa."""
        with self._swap:
            if self.current is not playback:
                return  # ya se abrió otro video: su segmento, su tarjeta y su «salí yo» no son de este
            segment = self.segment
            self.current = None
        self._card = None
        if segment is None or segment.closed:
            return
        if segment.playing:
            self._close_segment(segment)
            return
        if segment.live:
            return  # mpv se cerró: no hay otro canal que probar ni nada que guardar
        if segment.duration:  # solo lo tiene si heredó lo del archivo anterior
            self._close_segment(segment)  # cambió de fuente y salió antes de que cargara: lo visto se guarda
        if not self._user_quit and not segment.failed and self.on_failed:
            segment.failed = True  # mpv se cayó antes de mostrar nada: avisar, no quedarse callado
            self._safe(self.on_failed, segment.meta, 0.0, False)

    def tick(self, segment: Segment, now: float, paused: bool) -> None:
        """Un vistazo por segundo: arrancó, se cortó, capítulos, siguiente episodio, final."""
        pos, dur = self.mpv.get("time-pos"), self.mpv.get("duration")
        idle = bool(self.mpv.get("idle-active"))
        if segment.live:
            return self._live_tick(segment, now, paused, pos, idle)
        known = isinstance(dur, (int, float)) and dur > 0
        if now < segment.grace_until and not segment.playing:
            # Recién cargado otro archivo en la misma ventana: mpv tarda un instante en soltar lo del anterior (su posición
            # al final y «llegó al final»). Sin esta espera el episodio nuevo se daba por terminado y se cargaba otro.
            return
        if not segment.playing:
            # Arrancó: hay posición y, o se sabe cuánto dura, o la posición ya avanza (un torrent que aún
            # descarga no dice su duración; antes se daba por fallido a los 45 s aunque se estuviera viendo).
            moving = isinstance(pos, (int, float)) and pos > segment.start + 2
            if isinstance(pos, (int, float)) and not idle and (known or moving):
                segment.playing = True
                segment.position, segment.duration = float(pos), float(dur) if known else 0.0
                segment.last_tick = segment.last_save = now
                self._started(segment)
            elif (idle and now - segment.loaded > 2.5) or now - segment.loaded > STARTUP_TIMEOUT:
                self._fail(segment)
            return
        if idle:  # el archivo se cortó a media reproducción (stream caído): otra fuente, mismo punto
            self._fail(segment)
            return
        jumped = isinstance(pos, (int, float)) and abs(pos - segment.position) >= SCROBBLE_SEEK
        if isinstance(pos, (int, float)):
            if not paused:
                segment.watched += min(now - segment.last_tick, abs(pos - segment.position) + 1)
            segment.position = float(pos)
            if known:
                segment.duration = float(dur)
        if self._filler(segment):  # la duración llegó tarde: era el relleno de la fuente, no el episodio
            return self._fail(segment, filler=True)
        if not segment.scrobbling:
            if segment.duration and not paused:  # primera imagen real (o ya se supo la duración): «viendo ahora»
                self._scrobble("start", segment)
        elif jumped:  # saltaste: Trakt recibe el avance nuevo (en pausa, queda guardado como pausa)
            self._scrobble("pause" if paused else "start", segment)
        segment.last_tick = now
        self._drops_tick(segment, paused)
        self._buffering_state(paused)
        if now - segment.last_save >= SAVE_EVERY and not paused:
            self._save_progress(segment)
        if segment.scrobbling and not paused and now - segment.last_checkpoint >= CHECKPOINT_SECONDS:
            segment.last_checkpoint = now
            self._scrobble("checkpoint", segment)  # que otro aparato sepa dónde vas aunque la consola se apague
        self._chapters_tick(segment, now)
        self._upnext_tick(segment, now)
        if segment.meta.get("synthetic"):
            self._synthetic_tick(segment, now, paused)
        if self.mpv.get("eof-reached"):
            if segment.duration and segment.position < segment.duration - CUT_MARGIN:
                # Llegó al «final» a media película: la conexión se cortó (con keep-open, mpv se queda en
                # el último cuadro sin quedar inactivo). Antes se cerraba como si hubiera terminado.
                self._fail(segment)
                return
            self._at_end(segment)

    STUTTER_FRAMES = 3  # cuadros perdidos en un segundo que ya se notan (a 24 cuadros por segundo, un octavo de segundo)

    HOLD_MAX = 20.0  # s: si la pantalla de carga nunca avisa que se fue, el clip empieza igual

    def release_start(self) -> None:
        """Se fue la pantalla de carga: el clip, que abrió en pausa con su primer cuadro listo, empieza ahora. Antes empezaba
        en cuanto había imagen, uno o dos segundos antes de verse (visto en la TV con un tráiler el 2026-10-29)."""
        if not self._held:
            return
        self._held = False
        self.mpv.command("set_property", "pause", False)
        self._ask("pause", False)
        if getattr(self, "_hud_visible", False):
            # La barra que se dibujó durante la espera decía «En pausa · 0:00» y se quedaba encima del tráiler ya corriendo
            # (visto en la TV el 2026-10-30): se redibuja como reproduciendo y se va sola.
            self.show_hud(paused=False)

    def _drops_tick(self, segment: Segment, paused: bool) -> None:
        """Cada segundo, los cuadros que mpv tiró. Un tirón (varios de golpe) va al registro con su hora y su minuto, si fue
        al mostrar (la pantalla o Windows no alcanzaron) o al decodificar (el video pide más de lo que da la gráfica), y
        cómo estaban el equipo y el búfer: así se sabe qué lo causa sin tener que estar mirando (#tirones)."""
        dropped, decoder = self.mpv.get("frame-drop-count"), self.mpv.get("decoder-frame-drop-count")
        dropped = dropped if isinstance(dropped, int) and not isinstance(dropped, bool) else segment.drops
        decoder = decoder if isinstance(decoder, int) and not isinstance(decoder, bool) else segment.decoder_drops
        new, new_decoder = dropped - segment.drops, decoder - segment.decoder_drops
        segment.drops, segment.decoder_drops = dropped, decoder
        if paused or new + new_decoder < self.STUTTER_FRAMES or new < 0 or new_decoder < 0:
            return
        segment.stutters += 1
        from .. import health

        cache = self.mpv.get("demuxer-cache-duration")
        log.warning("Tirón en %s, minuto %s: %d cuadros perdidos al mostrar y %d al decodificar · %s, %s · búfer %s s · "
                    "RAM libre %s MB", segment.title, player_ui.clock(segment.position), new, new_decoder,
                    self.mpv.get("hwdec-current") or "sin aceleración", self.mpv.get("video-codec") or "?",
                    f"{cache:.0f}" if isinstance(cache, (int, float)) else "?", health.free_ram_mb())

    def _live_tick(self, segment: Segment, now: float, paused: bool, pos, idle: bool) -> None:
        """Un vistazo por segundo a un canal: ¿ya hay imagen?, ¿se cortó? Sin duración, capítulos ni final."""
        if not segment.playing:
            # Hay imagen cuando mpv ya reporta la posición DE ESTE canal: justo tras sintonizar, las propiedades
            # aún pueden ser las del anterior (sin esto, un canal caído se daba por bueno y se marcaba como sano).
            settled = now - segment.loaded >= LIVE_SETTLE and self.mpv.get("path") == segment.url
            if settled and isinstance(pos, (int, float)) and not idle:
                segment.playing = True
                segment.position = float(pos)
                segment.last_tick = segment.last_save = now
                self.show_hud()  # «En vivo»
                if self.on_channel_ok:
                    self._safe(self.on_channel_ok, segment.meta)
            elif (idle and now - segment.loaded > 1.0) or now - segment.loaded > LIVE_STARTUP_TIMEOUT:
                self._fail(segment)
            return
        if idle or self.mpv.get("eof-reached"):  # la señal se cortó y mpv no pudo reconectar
            self._fail(segment)
            return
        segment.last_tick = now
        self._buffering_state(paused)
