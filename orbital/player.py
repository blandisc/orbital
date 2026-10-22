"""Reproductor de Orbital: mpv a pantalla completa, manejado por el mando.

Orbital elige la fuente (library/streams.py) y la abre en mpv con un canal de control
(--input-ipc-server). Los botones del mando no se traducen a teclas: Orbital manda comandos a mpv
(pausa, adelantar, volumen, audio, subtítulos), así que funciona igual en cualquier idioma de
teclado y sin depender de los atajos de mpv.

  A pausa · ←/→ adelantar (mantener: cada vez más rápido) · LB/RB capítulo (o ±1 min)
  LT/RT episodio anterior/siguiente · ↑/↓ volumen · X audio y subtítulos · Y fuentes y episodios · B oculta la barra (mantener: salir)
  y, con la barra oculta, sale (guarda dónde ibas)

Además, como un servicio de streaming de verdad:
  * Si una fuente no arranca (o se corta), prueba sola la siguiente y sigue donde ibas.
  * Al final de un episodio, tarjeta "Siguiente episodio" con cuenta atrás (B la cancela); el
    siguiente se carga en el mismo mpv, sin volver al menú. Tras 3 seguidos sin tocar el mando,
    pregunta "¿Sigues viendo?".
  * "Saltar intro" cuando el archivo marca la intro con capítulos (Intro, Opening, Recap…).
  * El avance se guarda cada minuto y al pausar, no solo al salir.
  * TV en vivo (tv.py): el mismo mpv y la misma pantalla, pero sin avance que guardar, sin episodios, con
    caché corta y reconexión; ▲▼ o LT/RT cambian de canal con `loadfile … replace` (ver `tune`) y un canal
    que no abre se marca y se pasa al siguiente.

Piezas: mpv.py (la tubería con mpv), playback.py (comando, idiomas, capítulos, datos de lo que se
ve), player_screen.py (barra, tarjetas, menús y botones), player_subs.py («Probar otros» subtítulos) y aquí el reproductor que lo junta: arrancar,
vigilar, guardar el avance, fuentes que fallan y el siguiente episodio.
"""

from __future__ import annotations

import hashlib
import logging
import math
import os
import subprocess
import threading
import time
import urllib.request
from pathlib import Path
from urllib.parse import quote, urlsplit

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
from .net import read_body
from .playback import (  # noqa: F401 - el resto de Orbital y las pruebas las piden a player
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
    STREMIO_SERVER,
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
from .player_screen import PlayerScreen

log = logging.getLogger(__name__)

LOAD_GRACE = 1.5  # s tras cargar otro archivo antes de leer su posición (ver tick)
SYNTHETIC_RESYNC_AFTER = 60.0  # s en pausa tras los que un canal de Orbital regresa a lo que va al aire
# El fundido de entrada: el video arranca tapado de negro y se destapa ya con imagen (sin ventanas transparentes, que
# hacían crecer la memoria de dibujo de Windows). Al abrirlo desde Orbital espera a que Orbital termine su salida a negro.
PIP_WIDTH = .3  # del ancho de la pantalla: el video en pequeño (Home durante un video)
PIP_MARGIN = .03
PIP_GLIDE = .42  # s: lo que tarda en irse a la esquina (o volver), con una curva que frena al llegar
PIP_FRAME = .016  # un paso de la animación (~60 por segundo)
PIP_CONTROLS_SECONDS = 3.0  # los tres botones del video en pequeño, antes de irse solos
CURTAIN_ID = 9
CURTAIN_STEPS = (.86, .7, .52, .36, .22, .1, 0)  # opacidad, un paso cada CURTAIN_STEP s (~medio segundo)
CURTAIN_STEP = .07
CURTAIN_REVEAL_WAIT = 1.1  # s tras la primera imagen al abrir desde Orbital: lo que tarda su salida (focus.FADE_TO_BLACK)
CUT_MARGIN = 90  # s: un «final» antes de esto es la conexión que se cortó, no el final de verdad
NEXT_LOAD_WAIT = 25  # s que el final espera al siguiente episodio que se está cargando


def process_memory_mb(pid: int) -> int:
    """Memoria comprometida de un proceso (MB), como la mide el aviso de memoria. 0 si no se puede (o fuera de Windows)."""
    if not pid:
        return 0
    try:
        from .memory import _private_mb

        return _private_mb(pid)
    except Exception:  # noqa: BLE001 - sin el dato no se hace nada
        return 0


SUB_MAX_BYTES = 4 * 1024 * 1024  # un subtítulo nunca pesa tanto
SUB_TIMEOUT = 15.0


def subtitle_cache() -> Path:
    return Path(os.environ.get("LOCALAPPDATA") or Path.home()) / "orbital" / "cache" / "subs"


def fetch_subtitle(url: str) -> str:
    """Baja un subtítulo de internet a un archivo local y da su ruta. Con la URL, mpv lo bajaba él mismo y mientras
    tanto no contestaba nada (pausa, volumen, la interfaz: «mpv no contestó» y respuestas atrasadas)."""
    ext = os.path.splitext(urlsplit(url).path)[1].lower()
    path = subtitle_cache() / (hashlib.sha1(url.encode()).hexdigest()[:20] + (ext if ext in {".srt", ".vtt", ".ass", ".ssa", ".sub"} else ".srt"))
    if not path.exists():
        req = urllib.request.Request(url, headers={"User-Agent": "Orbital/0.1"})
        with urllib.request.urlopen(req, timeout=SUB_TIMEOUT) as res:
            data = read_body(res, timeout=SUB_TIMEOUT, limit=SUB_MAX_BYTES)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    return str(path)


def in_background(work) -> None:
    threading.Thread(target=work, daemon=True, name="subtítulos").start()


def glide_curve(t: float) -> float:
    """La curva del video en pequeño: cubic-bezier(.32, .72, 0, 1), la de los paneles de Apple. Arranca suave (sin el
    tirón del ease-out cúbico, que salía a toda velocidad) y se asienta largo."""
    x1, y1, x2, y2 = .32, .72, 0.0, 1.0
    if t <= 0 or t >= 1:
        return max(0.0, min(1.0, t))

    def bez(a: float, b: float, s: float) -> float:
        return 3 * a * (1 - s) ** 2 * s + 3 * b * (1 - s) * s ** 2 + s ** 3

    lo, hi = 0.0, 1.0
    for _ in range(30):  # el s de la curva cuya x es t (bisección: siempre converge)
        mid = (lo + hi) / 2
        if bez(x1, x2, mid) < t:
            lo = mid
        else:
            hi = mid
    return bez(y1, y2, (lo + hi) / 2)


class OrbitalPlayer(PlayerScreen):
    """Arranca mpv, lo vigila y avisa cuánto se vio (para Seguir viendo).

    El proceso lo lanza el Launcher de Orbital (así Home, la pausa, Select+Start y la vuelta a
    Orbital funcionan igual que con un juego); aquí se sigue la posición por la tubería y se
    decide qué pasa al final, si una fuente falla, etc. El catálogo pone los "proveedores":
    siguiente episodio, otras fuentes, cambiar de fuente.
    """

    POLL = 1.0
    # El vigilante de memoria: cada tanto se mira cuánto ocupa mpv. Con una versión de desarrollo llegó a 8 GB viendo la
    # tele (crece al dibujar, no el búfer). Un canal se vuelve a abrir en un mpv nuevo; un video solo avisa.
    MEMORY_EVERY = 30.0
    MEMORY_LIMIT_MB = 3000
    HUD_SECONDS = 4.0

    def __init__(self, on_finished=None, mpv: Mpv | None = None, idle_seconds: float = 0, on_idle=None) -> None:
        self.mpv = mpv or Mpv()
        self.mpv.on_message = self._on_mpv_message  # los toques en la pantalla (ver PlayerScreen.tap)
        self.remote = PlayerRemote(self.press)
        self.current: Playback | None = None
        self.segment: Segment | None = None
        self.menu: player_ui.Panel | None = None  # panel de columnas abierto (X o Y)
        self._hud_timer: threading.Timer | None = None
        self._toast_timer: threading.Timer | None = None
        self._hud_visible = False
        self._card: dict | None = None  # {"kind": "skip" | "next" | "still", ...}
        self._subs_lang = "en"
        self._sub_urls: dict[str, str] = {}  # archivo local → la URL de donde se bajó (lo que «Continuar» recuerda)
        self.fetch_subtitle = fetch_subtitle
        self.background = in_background
        self._audio_lang = "en"
        self._fallback_subs = None
        self._user_quit = False  # B, Orbital o la voz lo cerraron: no es un fallo
        self.last_end: dict | None = None  # cómo terminó lo último (para el aviso al volver)
        self._quiet_episodes = 0  # episodios encadenados sin tocar el mando
        self._buffering = False
        self._loading_until = 0.0  # tras «Ver ahora», A no pausa lo que está cargando
        self._want: dict[str, tuple[object, float]] = {}
        self._swap = threading.Lock()
        self._starting = threading.Lock()  # un play() a la vez
        self._closing = threading.Lock()
        self._more_token = None
        self._episode_steps, self._episode_timer = 0, None  # LT/RT seguidos (ver _queue_episode)  # el panel Y que se está buscando (ver _open_more_soon)  # current y segment cambian juntos (play) o se leen juntos (finish)  # lo último pedido a mpv (pausa, volumen, posición)
        self.sub_scale = 1.0
        self.sub_delay = 0.0  # Sincronía de los subtítulos (s); vuelve a cero con cada video
        self.on_finished = on_finished  # (meta, posición, duración, segundos vistos)
        self.on_progress = None  # igual que on_finished, cada minuto y al pausar
        self.on_scrobble = None  # (acción, meta, posición, duración): «start» | «pause» | «stop» para Trakt; nunca de TV en vivo
        self.on_failed = None  # (meta, posición, sigue_abierto) -> True si se intenta con otra fuente
        self.next_provider = None  # (meta) -> {"label", "title", "play"} | None
        self.sources_provider = None  # (meta) -> [{"id", "label", "current"}]
        self.on_switch_source = None  # (meta, id_fuente, posición)
        self.on_episode = None  # (meta, ±1): episodio anterior / siguiente
        self.episodes_provider = None  # (meta) -> [{"id", "label", "current", "progress"?}] de la temporada
        self.on_play_episode = None  # (meta, id_del_episodio): ver ese episodio
        self.on_sub_scale = None  # (escala): para recordarla
        self.iphone_provider = None  # () -> bool: ¿hay iPhone conectado? (Y › «Enviar al iPhone»)
        self.on_send_iphone = None  # (meta, "open" | "download") -> aviso en palabras (o lanza ValueError con el motivo)
        self.system_volume = None  # (leer, escribir) del volumen de Windows: un solo volumen (ver player_screen._muted)
        self.on_language = None  # (meta, "audio" | "subtitles", código): el idioma que elegiste
        self.on_sub_kept = None  # (meta): «Probar otros» › «Este va bien»: recordar ya esos subtítulos (y su sincronía)
        self.spanish_provider = None  # (meta) -> "es-419" | "es-ES" | "": el doblaje que va con ese título
        self.on_audio_tracks = None  # (meta, pistas): al abrir, el audio real de esa versión (se anota)
        # TV en vivo (ver tv.py): el reproductor solo pregunta y avisa, no sabe de listas ni de salud.
        self.channels_provider = None  # (meta, categoría | None) -> {"category", "categories", "channels"}
        self.on_play_channel = None  # (meta, id_del_canal, categoría | None): sintonizar ese canal
        self.on_channel_failed = None  # (meta, estaba_al_aire) -> True si se pasó a otro canal
        self.on_channel_ok = None  # (meta): el canal dio imagen
        self.on_memory_full = None  # (meta): un canal ocupa demasiada memoria; ábrelo de nuevo en un mpv nuevo
        self.memory_of = process_memory_mb  # (pid) -> MB (las pruebas lo cambian)
        # Canales de Orbital (ver synthetic.py): una serie al aire; al terminar o fallar, el canal decide qué sigue.
        self.on_synthetic_end = None  # (meta) -> True si cargó el siguiente episodio
        self.on_synthetic_failed = None  # (meta) -> True si se intenta con otra fuente u otro episodio
        self.on_synthetic_resync = None  # (meta) -> True si regresó a lo que va al aire (tras una pausa larga)
        self.on_synthetic_duration = None  # (meta, segundos): lo que dura de verdad (la programación lo aprende)
        self.pip = False  # el video en pequeño, en una esquina (Home durante un video)
        self.on_detached = None  # (meta): «Seguir solo este capítulo» (el canal ya no manda; la barra de arriba cambia)
        self._zap_view, self._zap_timer = None, None  # ▲▼ seguidos (ver _queue_channel)
        self._panel_category = None  # la categoría que enseña la guía de canales (Y)
        self._away = False  # Home: estás en Orbital y el canal sigue al aire sin sonido
        self._restore_sound = False  # …y al volver se le devuelve el sonido (salvo que ya lo hubieras silenciado tú)
        # Un video olvidado en pausa (saliste con Home y te fuiste) se cierra solo; el avance se guarda.
        self.idle_seconds = idle_seconds
        self.on_idle = on_idle  # (título, minutos[, live=True]): para avisar en Orbital

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
        process = run(build_command(mpv_exe, url, title, subtitles=subtitles, bindings=input_conf(),
                                    sub_scale=self.sub_scale, **options))
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
            self.toast(f"El reproductor ocupa mucha memoria ({mb / 1024:.1f} GB). Si se pone lento, sal y vuelve: sigues donde ibas.", 8)

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
        if not segment.scrobbling:
            if segment.duration and not paused:  # primera imagen real (o ya se supo la duración): «viendo ahora»
                self._scrobble("start", segment)
        elif jumped:  # saltaste: Trakt recibe el avance nuevo (en pausa, queda guardado como pausa)
            self._scrobble("pause" if paused else "start", segment)
        segment.last_tick = now
        self._buffering_state(paused)
        if now - segment.last_save >= SAVE_EVERY and not paused:
            self._save_progress(segment)
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

    # --- el video en pequeño (PiP) ------------------------------------------------------------------------------------
    def enter_pip(self) -> bool:
        """Home durante un video: se desliza y se encoge, con calma, a la esquina de abajo a la derecha, y sigue sonando
        encima de Orbital. False si no hay video abierto."""
        current = self.current
        if current is None or current.process is None or current.process.poll() is not None:
            return False
        self.pip = True
        self.menu = None
        self._card = None
        self._lift_subs(False)
        self._try_end()
        for overlay in (1, 2, 4):  # la barra, el panel y la tarjeta no caben en la esquina
            self._overlay(overlay, None)
        threading.Thread(target=self._to_corner, args=(current,), daemon=True, name="pip").start()
        log.info("Video en pequeño: %s", current.title)
        return True

    def _window(self, current):
        from . import windows

        return windows, windows.main_window(windows.process_tree(current.process.pid))

    def _pip_rect(self, windows) -> tuple[int, int, int, int]:
        screen_w, screen_h = windows.screen_size()
        width = int(screen_w * PIP_WIDTH)
        height = int(width * 9 / 16)
        margin = int(screen_w * PIP_MARGIN)
        return screen_w - width - margin, screen_h - height - margin, width, height

    def _glide(self, windows, hwnd, start: tuple, end: tuple, still) -> None:
        """La ventana de un lugar a otro en PIP_GLIDE segundos, con una curva que frena al llegar. Por tiempo (no por pasos)
        y sin esperar a que mpv redibuje cada uno (glide_window): antes cada paso cambiaba el tamaño y esperaba, y al
        encogerse se trababa. Mientras se mueve, el video se detiene un instante (sin decodificar mientras se redimensiona)."""
        was_paused = bool(self._value("pause"))
        if not was_paused:
            self.mpv.command("set_property", "pause", True)
        started = time.monotonic()
        try:
            while still():
                t = min(1.0, (time.monotonic() - started) / PIP_GLIDE)
                k = glide_curve(t)
                x, y, w, h = (round(a + (b - a) * k) for a, b in zip(start, end, strict=True))
                windows.glide_window(hwnd, x, y, w, h)
                if t >= 1:
                    break
                wait = getattr(windows, "wait_frame", None)  # a la par del refresco de la pantalla
                wait() if wait else time.sleep(PIP_FRAME)
        finally:
            if not was_paused:
                self.mpv.command("set_property", "pause", False)

    def _to_corner(self, current) -> None:
        windows, hwnd = self._window(current)
        screen_w, screen_h = windows.screen_size()
        full = (0, 0, screen_w, screen_h)
        # Primero su tamaño de ventana = la pantalla entera: al salir de pantalla completa ya no salta al centro con
        # el tamaño de siempre (antes se veía ir al centro y luego encogerse de golpe).
        self.mpv.command("set_property", "geometry", f"{screen_w}x{screen_h}+0+0")
        for prop, value in (("border", False), ("ontop", True), ("keepaspect-window", False), ("fullscreen", False)):
            self.mpv.command("set_property", prop, value)
        windows.place_window(hwnd, *full)
        still = lambda: self.pip and self.current is current  # noqa: E731
        self._glide(windows, hwnd, full, self._pip_rect(windows), still)
        if still():
            self._show_pip_controls()

    def exit_pip(self) -> None:
        """De vuelta a pantalla completa (Volver al video): el mismo camino, de la esquina a toda la pantalla."""
        if not self.pip:
            return
        self.pip = False
        self._cancel_pip_timer()
        self._overlay(1, None)
        current = self.current
        if current is not None and current.process is not None and current.process.poll() is None:
            windows, hwnd = self._window(current)
            screen_w, screen_h = windows.screen_size()
            here = windows.window_rect(hwnd)
            start = (here[0], here[1], here[2] - here[0], here[3] - here[1]) if here else self._pip_rect(windows)
            self._glide(windows, hwnd, start, (0, 0, screen_w, screen_h), lambda: not self.pip)
        for prop, value in (("fullscreen", True), ("ontop", False), ("border", True)):
            self.mpv.command("set_property", prop, value)
        log.info("Video a pantalla completa otra vez")

    # --- los tres botones del video en pequeño (como el PiP del iPhone) -------------------------------------------
    def _cancel_pip_timer(self) -> None:
        timer = getattr(self, "_pip_timer", None)
        if timer:
            timer.cancel()
        self._pip_timer = None

    def _show_pip_controls(self) -> None:
        """Los tres botones unos segundos (en pausa se quedan): luego solo el video."""
        if not self.pip:
            return
        paused = bool(self._value("pause"))
        self._overlay(1, player_ui.pip_ass(paused))
        self._cancel_pip_timer()
        if not paused:
            self._pip_timer = threading.Timer(PIP_CONTROLS_SECONDS, self._hide_pip_controls)
            self._pip_timer.daemon = True
            self._pip_timer.start()

    def _hide_pip_controls(self) -> None:
        if self.pip and not self._value("pause"):
            self._overlay(1, None)
            player_ui.targets["hud"] = []

    def _pip_tap(self, x: float, y: float) -> None:
        """Un toque en el video en pequeño: un botón, o enseñar los botones."""
        action = player_ui.hit("hud", x, y)
        if action == "pip:expand":
            current = self.current
            self.exit_pip()
            if current is not None and current.process is not None:
                windows, hwnd = self._window(current)
                windows.focus(hwnd)
        elif action == "pip:close":
            self._user_quit = True
            self._quit()
        elif action == "pip:play":
            paused = not bool(self._value("pause"))
            self.mpv.command("set_property", "pause", paused)
            self._ask("pause", paused)
            self._show_pip_controls()
        else:
            self._show_pip_controls()

    def _curtain(self, opacity: float) -> None:
        """El negro del fundido de entrada (debajo de la barra, los avisos y los paneles)."""
        try:
            self.mpv.command_named(name="osd-overlay", id=CURTAIN_ID, format="ass-events" if opacity > 0 else "none",
                                   data=player_ui.curtain_ass(opacity) if opacity > 0 else "",
                                   res_x=player_ui.W, res_y=player_ui.H, z=0)
        except Exception:  # noqa: BLE001 - el fundido nunca tumba la reproducción
            log.debug("No pude dibujar el fundido", exc_info=True)

    def _lift_curtain(self, segment: Segment) -> None:
        """Destapa el video en medio segundo, en su hilo (y si mientras tanto se cargó otro, ese ya trae su propio negro)."""
        wait, self._reveal_wait = getattr(self, "_reveal_wait", 0.0), 0.0

        def run() -> None:
            time.sleep(wait)
            for opacity in CURTAIN_STEPS:
                if self.segment is not segment:
                    return
                self._curtain(opacity)
                time.sleep(CURTAIN_STEP)

        threading.Thread(target=run, daemon=True, name="curtain").start()

    def _started(self, segment: Segment) -> None:
        """Primera imagen de este archivo: avisos, subtítulos, capítulos y la barra."""
        if not segment.live:
            self._lift_curtain(segment)
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
        if wrong_audio(tracks, self._audio_lang) and not segment.meta.get("synthetic"):
            # El archivo dice ser de otro idioma (un doblaje mal etiquetado): avisa en vez de callar.
            self.toast("Esta versión no trae audio en tu idioma · Y para elegir otra", 6)
        elif segment.start > 5:
            self.toast("Sigues donde te quedaste · ◀ regresa", 3.5)
        if self.on_audio_tracks and not segment.live:
            self._safe(self.on_audio_tracks, segment.meta, tracks)
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
            self._in_background(self.on_synthetic_resync, segment.meta, failed="No pude volver a lo que va al aire")

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

    def _fail(self, segment: Segment) -> None:
        if segment.failed or segment.closed:
            return
        segment.failed = True
        if segment.live:
            return self._fail_channel(segment)
        if segment.meta.get("synthetic"):
            return self._fail_synthetic(segment)
        log.info("La fuente de %s %s", segment.title, "se cortó" if segment.playing else "no arrancó")
        retrying = False
        if self.on_failed:
            self.toast("Esa versión falló · probando otra…", 6)
            retrying = bool(self._safe(self.on_failed, segment.meta, segment.position, True))
        if not retrying:
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
        if segment.live or segment.meta.get("synthetic") or not self.on_scrobble or not segment.duration:
            return  # un canal de Orbital tampoco: es la tele de fondo
        if action == "start":
            segment.scrobbling = True
        elif not segment.scrobbling:
            return  # pausar o parar algo que Trakt nunca supo que empezó
        elif action == "stop":
            segment.scrobbling = False
        self._safe(self.on_scrobble, action, segment.meta, segment.position, segment.duration)

    def _save_progress(self, segment: Segment) -> None:
        segment.last_save = time.monotonic()
        delta = segment.watched - segment.saved_watched
        if segment.live or segment.meta.get("synthetic") or not self.on_progress or not segment.duration or delta <= 0:
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
        if segment.live or segment.meta.get("synthetic"):
            return  # la tele (en vivo o un canal de Orbital) no guarda dónde ibas ni entra en «Seguir viendo»
        self._scrobble("stop", segment)  # Trakt: lo que llevabas (≥ 80 % lo marca visto)
        if self.on_finished and segment.duration and not (segment.watched < 20 and segment.position >= segment.duration * .9):
            # (Casi nada visto y «al final»: un salto raro, no la película vista de principio a fin.)
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
            self._show_notice(player_ui.toast_ass(f"Cargando… {int(percent)} %" if known else "Cargando…",
                                                  top=player_ui.BUFFER_Y), 2, layer=self.BUFFER)
        elif self._buffering:
            self._buffering = False
            self._overlay(self.BUFFER, None)  # solo el «Cargando…»: el aviso que estaba sigue

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
        if segment.meta.get("synthetic") and self.on_synthetic_end:
            if not segment.next_loading:  # el siguiente episodio del canal, una sola vez
                segment.next_loading = time.monotonic()
                self._in_background(self._synthetic_next, segment, failed="No pude seguir con el canal")
            return
        if segment.upnext and not segment.upnext_dismissed:
            if self._card is None or self._card.get("kind") != "still":
                self._play_next(segment, auto=True)
            return  # "¿Sigues viendo?": espera tu respuesta
        if segment.meta.get("kind") == "series" and segment.upnext is None and segment.upnext_requested:
            return  # aún buscando el siguiente: un segundo más
        if segment.next_loading and time.monotonic() - segment.next_loading < NEXT_LOAD_WAIT:
            return  # el siguiente episodio se está cargando: no cerrar mpv debajo de él
        self._user_quit = True
        self._quit()

    def _synthetic_next(self, segment: Segment) -> None:
        handler = self.on_synthetic_end
        if not (handler and handler(segment.meta)) and self.segment is segment:
            self._user_quit = True
            self._quit()

    def _play_next(self, segment: Segment, auto: bool) -> None:
        info = segment.upnext
        if not isinstance(info, dict) or segment.closed:
            return
        self._hide_card()
        self._quiet_episodes = self._quiet_episodes + 1 if auto else 0
        segment.upnext_dismissed = True  # que no se dispare dos veces
        segment.next_loading = time.monotonic()
        self.toast(f"Cargando {info.get('label') or 'el siguiente episodio'}…", 6)
        self._in_background(info["play"], failed="No pude cargar el siguiente episodio")
        if not auto:  # tras «Ver ahora», un segundo A no pausa lo que está cargando
            self._loading_until = time.monotonic() + 3

    # --- subtítulos ------------------------------------------------------------------------------
    def current_subtitle(self) -> dict | None:
        """Los subtítulos que tienes puestos ahora: {"off": True}, o idioma, nombre de la pista y, si son de un
        complemento, su dirección. Se recuerda lo último que se vio (al cerrar mpv ya no se puede preguntar)."""
        try:
            tracks = self.mpv.get("track-list")
        except Exception:  # noqa: BLE001 - mpv ya cerró
            tracks = None
        if isinstance(tracks, list) and tracks:
            chosen = next((t for t in tracks if isinstance(t, dict) and t.get("type") == "sub" and t.get("selected")), None)
            if chosen is None:
                self._last_sub = {"off": True}
            else:
                self._last_sub = {"off": False, "lang": str(chosen.get("lang") or ""), "title": str(chosen.get("title") or ""),
                                  "url": self._sub_url(chosen) if chosen.get("external") else ""}
                if self._keep_delay and abs(self.sub_delay) >= .05:  # «Este va bien» con su sincronía, para esta versión
                    segment = self.segment
                    self._last_sub |= {"delay": self.sub_delay,
                                       "delay_source": str((segment.meta if segment else {}).get("source_key") or "")}
        return getattr(self, "_last_sub", None)

    def current_audio(self) -> dict | None:
        """El audio que suena ahora: {"lang", "title"} (para «Continuar» y para pasarlo al iPhone), o None."""
        try:
            tracks = self.mpv.get("track-list")
        except Exception:  # noqa: BLE001 - mpv ya cerró
            tracks = None
        if isinstance(tracks, list) and tracks:
            chosen = next((t for t in tracks if isinstance(t, dict) and t.get("type") == "audio" and t.get("selected")), None)
            self._last_audio = {"lang": str(chosen.get("lang") or ""), "title": str(chosen.get("title") or "")} if chosen else None
        return getattr(self, "_last_audio", None)

    @staticmethod
    def _same_track(tracks: list, kind: str, saved: dict, exact_only: bool = False) -> dict | None:
        """La misma pista (idioma y nombre); si en este archivo se llama distinto (otra fuente, o viene del iPhone, que las
        etiqueta de otra forma), la del mismo idioma que no sea de forzados."""
        mine = [t for t in tracks if isinstance(t, dict) and t.get("type") == kind and "id" in t]
        lang, title = str(saved.get("lang") or ""), str(saved.get("title") or "")
        exact = next((t for t in mine if str(t.get("lang") or "") == lang and str(t.get("title") or "") == title), None)
        if exact is not None or exact_only or not base_language(lang):
            return exact
        return next((t for t in mine if base_language(t.get("lang")) == base_language(lang) and not t.get("forced")
                     and "forced" not in str(t.get("title") or "").lower()), None)

    def _apply_sub_pick(self, tracks: list) -> bool:
        """«Continuar» (o lo que venía viendo el iPhone): el mismo audio y los mismos subtítulos (la misma pista:
        Latinoamérica y no España, los forzados, o los que se buscaron en tu complemento). True si los subtítulos
        quedaron puestos; si no, lo de siempre."""
        pick, self._sub_pick = getattr(self, "_sub_pick", None), None
        if not isinstance(pick, dict):
            return False
        audio = self._same_track(tracks, "audio", pick["audio"]) if isinstance(pick.get("audio"), dict) else None
        if audio is not None and not audio.get("selected"):
            self.mpv.command("set_property", "aid", audio["id"])
        if "off" not in pick:
            return False  # solo el audio: los subtítulos, con la regla de siempre
        if pick.get("off"):
            self.mpv.command("set_property", "sid", "no")
            return True
        delay = pick.get("delay")
        segment = self.segment
        here = str((segment.meta if segment else {}).get("source_key") or "")
        if isinstance(delay, (int, float)) and not isinstance(delay, bool) and math.isfinite(delay) \
                and (not pick.get("delay_source") or pick["delay_source"] == here):
            self._set_sub_delay(float(delay))  # la sincronía que dejaste en «Probar otros», con esta misma versión
            self._keep_delay = True
        # La pista exacta; si no, los mismos de tu complemento (su dirección); si no, otros del mismo idioma.
        same = self._same_track(tracks, "sub", pick, exact_only=bool(pick.get("url")))
        if same is not None:
            self.mpv.command("set_property", "sid", same["id"])
            return True
        if pick.get("url"):
            self.add_sub(pick["url"], pick.get("title") or "Subtítulos", pick.get("lang") or "")
            return True
        return False

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
            self.add_sub(urls[0], "Subtítulos", lang)
            log.info("Subtítulos de un addon (%d disponibles)", len(urls))

    def _sub_url(self, track: dict) -> str:
        name = str(track.get("external-filename") or "")
        return self._sub_urls.get(name, name)

    def add_sub(self, url: str, title: str, lang: str, done: str | None = None) -> None:
        """Agrega y elige un subtítulo. Uno de internet se baja aparte (en segundo plano) y mpv recibe el archivo:
        así nunca se queda sin contestar mientras lo baja. `done`: el aviso cuando ya está puesto."""
        playback = self.current

        def work() -> None:
            path = url
            if url.startswith(("http://", "https://")):
                try:
                    path = self.fetch_subtitle(url)
                except (OSError, ValueError) as exc:
                    log.info("No pude bajar los subtítulos: %s", exc)
                    if done and self.current is playback:
                        self.toast("No pude bajar esos subtítulos", 2.5)
                    return
                self._sub_urls[path] = url
            if self.current is not playback:
                return  # mientras se bajaba se abrió otro video: ya no van
            self.mpv.command("sub-add", path, "select", title, lang)
            if done:
                self.toast(done)

        self.background(work)

    def pause(self) -> None:
        if self._is_live():
            # Home: un canal en vivo no se pausa (al volver estaría atrasado): se deja sin sonido y sigue al aire.
            self._away = True
            self._restore_sound = not bool(self._value("mute"))  # si ya lo habías silenciado tú, se queda como lo dejaste
            self.mpv.command("set_property", "mute", True)
            return
        self.mpv.command("set_property", "pause", True)

    def show_progress(self) -> None:
        if self._away:  # volviste al canal
            self._away = False
            if self._restore_sound:
                self.mpv.command("set_property", "mute", False)
                self._want.pop("mute", None)
            self._restore_sound = False
        self.show_hud()

    # --- para la voz -----------------------------------------------------------------------
    def set_pause(self, paused: bool) -> None:
        self.mpv.command("set_property", "pause", paused)
        self.show_hud()

    def seek_to(self, seconds: float) -> None:
        """A un punto exacto (voz: «desde el principio», «ve al minuto 20»)."""
        self.mpv.command("seek", max(0.0, seconds), "absolute")
        self.show_hud()

    def seek(self, seconds: float) -> None:
        self.mpv.command("seek", seconds, "relative")
        self.show_hud()

    def select_language(self, kind: str, lang: str, variant: str = "") -> bool:
        """Cambia a la pista de audio o subtítulos en ese idioma, si el video la trae. `variant` («es-419» / «es-ES»,
        «pon el audio en latino»): la pista de ese doblaje (con las dos «spa», no la primera); False si solo trae la
        del otro. Es solo para esta vez: si este video cambia de versión, la nueva sigue en ese doblaje."""
        tracks = self.mpv.get("track-list") or []
        if kind == "audio" and variant in ("es-419", "es-ES"):
            pick = dub_track(tracks, "latino" if variant == "es-419" else "castellano")
            if pick is False:
                return False
            if isinstance(pick, int) and not isinstance(pick, bool):
                self.mpv.command("set_property", "aid", pick)
                segment = self.segment
                if segment is not None:
                    asked = segment.meta.get("asked")
                    asked = asked if isinstance(asked, dict) else {}
                    segment.meta["asked"] = {**asked, "audio": "es", "spanish": variant}
                self.toast(f"Audio: {'Latino' if variant == 'es-419' else 'Castellano'}")
                return True
        codes = {c.lower() for c in build_lang_list(lang)}
        track = next((t for t in tracks if t.get("type") == kind and str(t.get("lang") or "").lower() in codes), None)
        if track is None:
            return False
        self.mpv.command("set_property", "aid" if kind == "audio" else "sid", track["id"])
        name = player_ui.language(track.get("lang")) or f"pista {track['id']}"
        self.toast(f"{'Audio' if kind == 'audio' else 'Subtítulos'}: {name}")
        return True

    def add_subtitles(self, url: str, lang: str) -> None:
        self.add_sub(url, "Subtítulos", lang, done=f"Subtítulos: {player_ui.language(lang)}")

    def subtitles_off(self) -> None:
        self.mpv.command("set_property", "sid", "no")
        self.toast("Sin subtítulos")

    def stop(self) -> None:
        current = self.current  # una sola lectura: el vigilante puede ponerlo en None a la mitad
        if current and current.process.poll() is None:
            self._user_quit = True
            self._quit()
            try:
                current.process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                current.process.kill()

    @property
    def playing(self) -> bool:
        current = self.current
        return current is not None and current.process.poll() is None

    # --- «Viendo en la TV» (el iPhone) ----------------------------------------------------------
    def now_playing(self) -> dict | None:
        """Lo que se está viendo ahora, para la tarjeta del iPhone. None si no hay nada abierto."""
        current, segment = self.current, self.segment
        if current is None or segment is None:
            return None
        meta = segment.meta
        logo = f"/api/tv/logo?id={quote(meta['channel_id'], safe='')}" if meta.get("channel_id") else None
        if meta.get("synthetic"):  # un canal de Orbital, para el iPhone, es tele: el canal y lo que va
            return {"kind": "tv", "live": True, "channel": current.title, "title": meta.get("detail") or current.title,
                    "number": None, "category": "Orbital 24/7", "paused": bool(self.mpv.get("pause")),
                    "muted": self._muted(), "logo": logo, "poster": meta.get("still") or meta.get("poster"),
                    "meta_id": meta.get("meta_id")}
        if segment.live:
            return {"kind": "tv", "live": True, "channel": meta.get("title") or current.title,
                    "title": meta.get("title") or current.title, "number": meta.get("number"),
                    "category": meta.get("category") or "", "paused": False,
                    "muted": self._muted(), "logo": logo}
        from .companion import episode_numbers  # aquí: companion no se carga con el reproductor
        label = (meta.get("detail") or "").split(" · ", 1)[0]
        parts = label.split()
        episode_label = f"{parts[0]} · {parts[1]}" if len(parts) == 2 else ""
        return {"kind": meta.get("kind") or "movie", "live": False, "meta_id": meta.get("meta_id"),
                "video_id": meta.get("video_id"), "title": meta.get("title") or current.title,
                "episode_label": episode_label, "poster": meta.get("poster"),
                **episode_numbers(meta.get("video_id") if meta.get("kind") == "series" else None),
                "position": segment.position, "duration": segment.duration,
                "paused": bool(self.mpv.get("pause"))}
