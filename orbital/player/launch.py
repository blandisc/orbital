"""Abrir y cambiar lo que se ve: un video, otro archivo en el mismo mpv o un canal."""

from __future__ import annotations

import subprocess
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
from .base import CURTAIN_REVEAL_WAIT, LOAD_GRACE, _State, log


class _Launch(_State):
    """Abrir y cambiar lo que se ve."""

    # --- arrancar / cambiar de archivo -------------------------------------------------------
    def play(self, run, mpv_exe: str, url: str, title: str, meta: dict, *, subtitles: str = "en",
             fallback_subs=None, started=None, sub_pick: dict | None = None, **options) -> subprocess.Popen:
        """`run(argv)` lanza el proceso; `fallback_subs()` da URLs de subtítulos si el video no trae.
        `started(proceso)`: lo que hay que hacer con él en el mismo paso (vigilarlo).
        Uno a la vez: dos «pon…» seguidos (voz y mando) ya no dejan un mpv huérfano a pantalla completa."""
        with self._starting:
            process = self._play(run, mpv_exe, url, title, meta, subtitles=subtitles, fallback_subs=fallback_subs,
                                 sub_pick=sub_pick, **options)
            if started is not None:
                started(process)
            return process

    def _play(self, run, mpv_exe: str, url: str, title: str, meta: dict, *, subtitles: str = "en",
              fallback_subs=None, sub_pick: dict | None = None, **options) -> subprocess.Popen:
        self.stop()
        if self.segment is not None and self.segment.playing:
            self._close_segment(self.segment)  # lo visto del video anterior se guarda antes de soltarlo
        if self.before_open is not None:  # con la pantalla de carga a la vista: DWM ya dibuja bien (dwm_release)
            self._safe(self.before_open)
        self._held = bool(options.get("paused"))
        process = run(build_command(mpv_exe, url, title, subtitles=subtitles, bindings=input_conf(),
                                    sub_scale=self.sub_scale, volume=getattr(self, "boost", 100), **options))
        self.menu = None
        self._card = None
        self._user_quit = False
        self.last_end = None
        self._quiet_episodes = 0
        self._subs_lang, self._fallback_subs = subtitles, fallback_subs
        self._sub_pick, self._last_sub = sub_pick, None  # «Continuar»: los subtítulos que tenías (ver _apply_sub_pick)
        self._try_end()  # «Probar otros» era del video anterior
        self._subs_lifted, self._keep_delay = None, False  # un mpv nuevo: los subtítulos en su lugar de siempre
        self.sub_delay = 0.0  # …y a tiempo (la sincronía era del video anterior)
        self._audio_lang = options.get("audio", "en")
        self._want.clear()
        self._restart_from = None
        self._zap_view, self._away = None, False
        if self._zap_timer:
            self._zap_timer.cancel()
        playback = Playback(title, process, time.time(), meta)
        with self._swap:  # el vigilante del video anterior ve los dos cambios juntos, nunca uno solo
            self.current = playback
            self.segment = Segment(meta, title, url, start=float(options.get("start") or 0), live=bool(options.get("live")))
        self._reveal_wait = CURTAIN_REVEAL_WAIT  # el primero de esta ventana: Orbital todavía tapa la pantalla
        self.pip = False
        if not options.get("live"):
            self._curtain(1)
        if hasattr(self.mpv, "start_observing"):
            self.mpv.start_observing()  # mpv avisa de pausa, posición… en vez de preguntarle cada segundo
        threading.Thread(target=self._watch, args=(playback,), daemon=True, name="mpv").start()
        log.info("Reproduciendo en mpv: %s", title)
        return process

    def starting(self, video_id: str | None, source_key: str | None = None) -> bool:
        """Ese mismo video ya se está abriendo (todavía sin imagen). Otro «ver» no lo empieza de cero: con un stream
        lento (20–40 s) cada A, cada «pon…» del iPhone o de Alexa cerraba mpv y volvía a cargar desde el principio.
        Otra fuente elegida a propósito (`source_key` distinto) sí se abre."""
        playback, segment = self.current, self.segment
        return bool(video_id and playback is not None and playback.process.poll() is None and segment is not None
                    and not segment.playing and not segment.failed and not segment.live
                    and segment.meta.get("video_id") == video_id
                    and (source_key is None or segment.meta.get("source_key") == source_key)
                    and time.monotonic() - segment.loaded < STARTUP_TIMEOUT)

    def showing(self, video_id: str | None, source_key: str | None = None) -> bool:
        """Ese mismo video ya se está viendo (con imagen). Otro «ver» lo trae al frente en vez de abrirlo otra vez: antes
        lo cerraba y lo volvía a cargar desde lo último guardado (hasta un minuto atrás), y la película «se trababa»."""
        playback, segment = self.current, self.segment
        return bool(video_id and playback is not None and playback.process.poll() is None and segment is not None
                    and segment.playing and not segment.failed and not segment.live and not segment.closed
                    and segment.meta.get("video_id") == video_id
                    and (source_key is None or segment.meta.get("source_key") == source_key))

    def load(self, url: str, title: str, meta: dict, *, start: float = 0, fallback_subs=None,
             subtitles: str | None = None, audio: str | None = None, message: str | None = None) -> bool:
        """Otro archivo en la misma ventana: el siguiente episodio, u otra fuente del mismo título.
        Lo que se vio del anterior se guarda. False si mpv ya no está abierto."""
        playback = self.current
        if playback is None or playback.process.poll() is not None:
            return False
        segment = Segment(meta, title, url, start=start, grace_until=time.monotonic() + LOAD_GRACE)
        with self._swap:  # mientras se buscaba la fuente pudo abrirse otro video: entonces este archivo ya no va
            if self.current is not playback:
                return False
            previous = self.segment
            same = previous is not None and previous.meta.get("video_id") == meta.get("video_id")
            if same:  # la misma película en otra fuente: lo visto sigue contando como una sola vez
                previous.closed = True
                segment.watched, segment.saved_watched = previous.watched, previous.saved_watched
                segment.duration, segment.position = previous.duration, previous.position
            self.segment = segment
            playback.title, playback.meta = title, meta
        if previous is not None and not same:
            self._close_segment(previous)  # otro episodio: lo visto del anterior se guarda ya
        if self.menu is not None:  # el panel era del episodio anterior
            self.menu = None
            self._overlay(2, None)
        self._lift_subs(False)
        self._try_end()  # «Probar otros» era del archivo anterior
        self._keep_delay = False
        loading = self._card if self._card is not None and self._card.get("kind") == "loading" else None
        if loading is not None:
            loading["target"] = segment  # la tarjeta «Cargando…» se queda hasta que este archivo dé imagen (o falle)
        else:
            self._hide_card()
        # Siempre los del archivo nuevo (None = «sin subtítulos» o «solo forzados»): antes se quedaban
        # los del episodio anterior y al siguiente le ponían los subtítulos de otro.
        self._fallback_subs = fallback_subs
        if subtitles is not None:
            self._subs_lang = subtitles
        if audio is not None:
            self._audio_lang = audio
        self.mpv.command("set_property", "force-media-title", title)
        self.mpv.command("set_property", "start", f"{int(start)}" if start > 5 else "0")
        self._want.clear()  # lo pedido era del archivo anterior (p. ej. «en pausa»)
        self._restart_from = None  # «Volver a…» era del archivo anterior
        self.mpv.command("set_property", "pause", False)
        for prop, value in track_properties(self._audio_lang, self._subs_lang):
            self.mpv.command("set_property", prop, value)  # el idioma de este título, no la pista del anterior
        self.sub_delay = 0.0  # la sincronía era del archivo anterior
        self.mpv.command("set_property", "sub-delay", 0)
        self._reveal_wait = 0.0  # otro episodio u otra fuente en la misma ventana: se destapa en cuanto haya imagen
        self._curtain(1)
        self.mpv.command("loadfile", url, "replace")
        # Otra vez, ya con el archivo nuevo: al terminar el anterior, keep-open lo deja en pausa en su último cuadro y
        # mpv lo vuelve a pausar mientras siga ahí, así que la pausa de arriba no alcanzaba. El siguiente episodio (de un
        # canal 24/7 o de una serie) arrancaba en pausa en el segundo 0: parecía que «no ponía el siguiente».
        self.mpv.command("set_property", "pause", False)
        if loading is None:  # con la tarjeta «Cargando…» a la vista, ella lo dice (no un segundo aviso)
            self.toast(message or f"Cargando {title}…", 4)
        log.info("Cargando en el mismo mpv: %s", title)
        return True

    def tune(self, url: str, title: str, meta: dict, *, user_agent: str | None = None, referrer: str | None = None,
             message: str | None = None) -> bool:
        """Otro canal en la misma ventana (`loadfile … replace`: sin cerrar mpv, ~1,7 s). Un canal en vivo no
        guarda ni avance ni «Seguir viendo». Cada canal lleva su Referer y User-Agent (o los de siempre).
        False si mpv ya no está abierto."""
        playback = self.current
        if playback is None or playback.process.poll() is not None:
            return False
        segment = Segment(meta, title, url, live=True)
        with self._swap:  # mientras se buscaba el canal pudo abrirse otra cosa: entonces este ya no va
            if self.current is not playback:
                return False
            previous = self.segment
            self.segment = segment
            playback.title, playback.meta = title, meta
        if previous is not None:
            previous.closed = True  # nada que guardar de un canal
        if self.menu is not None:  # la guía era de la lista anterior
            self.menu = None
            self._overlay(2, None)
        self._lift_subs(False)
        self._try_end()
        self._hide_card()
        self._zap_view = None
        self._want.clear()
        self._away = False
        self.mpv.command("set_property", "force-media-title", title)
        self.mpv.command("set_property", "pause", False)
        self.set_muted(False)
        self._overlay(self.MUTE, None)  # un canal nuevo suena (y la píldora de «Sin sonido» se va)
        # Siempre las dos opciones, aunque vayan vacías: el Referer del canal anterior no se hereda.
        self.mpv.command("loadfile", url, "replace", -1, {"user-agent": user_agent or LIVE_USER_AGENT, "referrer": referrer or ""})
        self.show_hud()  # la barra del canal nuevo, «Sintonizando…» hasta que haya imagen
        if message:
            self.toast(message, 3)
        log.info("Sintonizando en el mismo mpv: %s", title)
        return True
