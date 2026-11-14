"""El reproductor de Orbital: mpv a pantalla completa, manejado con el mando, que avisa cuánto se vio.

Es un paquete: base (la bitácora, las medidas y las funciones sueltas: subtítulos de internet, memoria de mpv, la curva
de la ventanita) y una pieza por tema de `OrbitalPlayer` (launch: abrir y cambiar lo que se ve; watching: el vigilante
que sigue la posición; pip: la ventanita y el telón; lifecycle: cuando arranca, falla o se guarda el avance; upnext:
capítulos, saltar la intro y el siguiente episodio; tracks: audio, subtítulos, pausa y buscar). `OrbitalPlayer`, aquí,
es la fachada, con la misma API de siempre; hereda de PlayerScreen (player_screen/) lo que se ve encima del video.

Lo que las pruebas cambian en `player.…` vive aquí para que el cambio llegue: in_background, fetch_subtitle y
process_memory_mb los usa __init__ (aquí), y NEXT_LOAD_WAIT y CURTAIN_STEP se definen aquí junto con los tres métodos
que los leen (_lift_curtain, _at_end, _synthetic_next). find_mpv se reexporta: quien lo usa lo pide a `player`.
"""

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
from .base import CURTAIN_ID as CURTAIN_ID
from .base import CURTAIN_REVEAL_WAIT as CURTAIN_REVEAL_WAIT
from .base import CURTAIN_STEPS as CURTAIN_STEPS
from .base import CUT_MARGIN as CUT_MARGIN
from .base import LOAD_GRACE as LOAD_GRACE
from .base import PIP_CONTROLS_SECONDS as PIP_CONTROLS_SECONDS
from .base import PIP_FRAME as PIP_FRAME
from .base import PIP_GLIDE as PIP_GLIDE
from .base import PIP_MARGIN as PIP_MARGIN
from .base import PIP_WIDTH as PIP_WIDTH
from .base import SUB_MAX_BYTES as SUB_MAX_BYTES
from .base import SUB_TIMEOUT as SUB_TIMEOUT
from .base import SYNTHETIC_NEXT_TRIES as SYNTHETIC_NEXT_TRIES
from .base import SYNTHETIC_RESYNC_AFTER as SYNTHETIC_RESYNC_AFTER
from .base import _num as _num
from .base import fetch_subtitle as fetch_subtitle
from .base import glide_curve as glide_curve
from .base import in_background as in_background
from .base import log as log
from .base import process_memory_mb as process_memory_mb
from .base import subtitle_cache as subtitle_cache
from .tracks import _Tracks

CURTAIN_STEP = .07

NEXT_LOAD_WAIT = 25  # s que el final espera al siguiente episodio que se está cargando


class OrbitalPlayer(_Tracks):
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
        self._card: dict | None = None  # {"kind": "skip" | "next" | "still" | "quit" | "loading", ...}
        self._card_paint = threading.RLock()  # la capa de la tarjeta, de un hilo a la vez (ver PlayerScreen._overlay)
        self._next_lock = threading.Lock()  # el siguiente episodio se pide una sola vez (el anillo y el vigilante a la vez)
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
        self.on_channel = None  # (meta, posición, duración, segundos vistos, terminado): un episodio de un canal de Orbital (V2)
        self.on_failed = None  # (meta, posición, sigue_abierto) -> True si se intenta con otra fuente
        self.next_provider = None  # (meta) -> {"label", "title", "play"} | None
        self.sources_provider = None  # (meta) -> [{"id", "label", "current"}]
        self.logo_provider = None  # (meta) -> PNG del logo del título (en pausa, el título estilizado) | None
        self.still_provider = None  # (url, ancho en px) -> la imagen del cuadro del episodio («Siguiente episodio») | None
        self.on_tracks = None  # (meta, track-list) -> aviso si no trae tu idioma (y lo recuerda: «Comprobado»)
        self.versions_provider = None  # (meta) -> [{"id", "label", "hint"}]: tu idioma en otra versión (X › Audio)
        self.on_switch_source = None  # (meta, id_fuente, posición)
        self.on_episode = None  # (meta, ±1): episodio anterior / siguiente
        self._held = False  # abrió en pausa hasta que se vaya la pantalla de carga (release_start): un tráiler
        self.before_open = None  # () antes de abrir mpv: esperar si DWM acaba de reiniciarse (server.py, dwm_release)
        self.episodes_provider = None  # (meta) -> [{"id", "label", "current", "progress"?}] de la temporada
        self.on_play_episode = None  # (meta, id_del_episodio): ver ese episodio
        self.on_sub_scale = None  # (escala): para recordarla
        self.iphone_provider = None  # () -> bool: ¿hay iPhone conectado? (Y › «Enviar al iPhone»)
        self.on_send_iphone = None  # (meta, "open" | "download") -> aviso en palabras (o lanza ValueError con el motivo)
        self.system_volume = None  # (leer, escribir) del volumen de Windows: un solo volumen (ver player_screen._muted)
        self.boost = 100  # el volumen del reproductor: 100, o más si pasaste el 100 de Windows; el siguiente video arranca igual
        self.on_language = None  # (meta, "audio" | "subtitles", código): el idioma que elegiste
        self.on_sub_kept = None  # (meta): «Probar otros» › «Este va bien»: recordar ya esos subtítulos (y su sincronía)
        self.spanish_provider = None  # (meta) -> "es-419" | "es-ES" | "": el doblaje que va con ese título
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

    def _at_end(self, segment: Segment) -> None:
        """Llegó al final (mpv se queda en el último cuadro)."""
        if segment.closed:
            return
        segment.finished = True
        if segment.meta.get("synthetic") and self.on_synthetic_end:
            if not segment.next_loading:  # el siguiente episodio del canal, una vez (si no se pudo, otra al rato)
                segment.next_loading = time.monotonic()
                self._in_background(self._synthetic_next, segment, failed="No pude seguir con el canal")
            return
        if segment.upnext and not segment.upnext_dismissed and segment.upnext.get("ready") is not False:
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
        """Lo que sigue en el canal. Si no se pudo, el final lo vuelve a pedir en NEXT_LOAD_WAIT: la tele no se apaga (ni
        se queda en el último cuadro) por un tropiezo de Internet. Tras SYNTHETIC_NEXT_TRIES, se cierra."""
        handler = self.on_synthetic_end
        try:
            ok = bool(handler and handler(segment.meta))
        except Exception:  # noqa: BLE001 - un error de red no deja el canal congelado en el último cuadro
            log.exception("%s: no pude poner lo que sigue", segment.title)
            ok = False
        if ok or self.segment is not segment:
            return
        segment.next_tries += 1
        if segment.next_tries < SYNTHETIC_NEXT_TRIES:
            log.info("%s: no pude poner lo que sigue (intento %d); otra vez en %d s", segment.title, segment.next_tries,
                     NEXT_LOAD_WAIT)
            self.toast(f"Buscando lo que sigue en {segment.title}…", 6)
            timer = threading.Timer(NEXT_LOAD_WAIT, lambda: setattr(segment, "next_loading", 0.0))
            timer.daemon = True
            timer.start()
            return
        self.toast(f"No pude seguir con {segment.title}", 4)
        self._user_quit = True
        self._quit()
