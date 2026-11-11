"""Lo que usan todas las piezas del reproductor: la bitácora, las medidas (ventanita, telón, final) y las funciones
sueltas (subtítulos de internet, memoria de mpv, la curva de la ventanita)."""

from __future__ import annotations

import hashlib
import logging
import os
import threading
import urllib.request
from pathlib import Path
from typing import TYPE_CHECKING, Any
from urllib.parse import urlsplit

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
from ..library import opensubtitles
from ..mpv import PIPE, Mpv  # noqa: F401 - se importan desde aquí
from ..net import read_body
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
from ..player_screen import PlayerScreen

log = logging.getLogger("orbital.player")  # el nombre de siempre: la bitácora no cambia

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

CURTAIN_REVEAL_WAIT = 1.1  # s tras la primera imagen al abrir desde Orbital: lo que tarda su salida (focus.FADE_TO_BLACK)

CUT_MARGIN = 90  # s: un «final» antes de esto es la conexión que se cortó, no el final de verdad

SYNTHETIC_NEXT_TRIES = 3  # veces que un canal de Orbital pide lo que sigue (cada NEXT_LOAD_WAIT) antes de cerrarse


def process_memory_mb(pid: int) -> int:
    """Memoria comprometida de un proceso (MB), como la mide el aviso de memoria. 0 si no se puede (o fuera de Windows)."""
    if not pid:
        return 0
    try:
        from ..memory import _private_mb

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
        # Uno de la API de OpenSubtitles se pide ahora (gasta cuota); ya bajado, el archivo se reusa sin gastar otra.
        real = opensubtitles.resolve(url)
        req = urllib.request.Request(real, headers={"User-Agent": "Orbital/0.1"})
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


def _num(value) -> str:
    """Un número del registro, corto («12.4»), o «?» si mpv no lo dio."""
    return f"{value:.1f}" if isinstance(value, (int, float)) else "?"


class _State(PlayerScreen):
    """El estado que OrbitalPlayer.__init__ arma y los métodos que las piezas se piden entre sí: aquí solo se
    declaran, con su tipo, para que cada pieza los vea (nada de esto existe en ejecución)."""

    _audio_lang: Any
    _away: Any
    _buffering: Any
    _card: dict | None
    _card_paint: Any
    _closing: Any
    _episode_steps: Any
    _episode_timer: Any
    _fallback_subs: Any
    _held: Any
    _hud_timer: threading.Timer | None
    _hud_visible: Any
    _last_audio: Any
    _last_sub: Any
    _loading_until: Any
    _more_token: Any
    _next_lock: Any
    _panel_category: Any
    _pip_timer: Any
    _quiet_episodes: Any
    _restart_from: Any
    _restore_sound: Any
    _reveal_wait: Any
    _starting: Any
    _sub_pick: Any
    _sub_urls: dict[str, str]
    _subs_lang: Any
    _swap: Any
    _toast_timer: threading.Timer | None
    _user_quit: Any
    _wait_started: Any
    _want: dict[str, tuple[object, float]]
    _zap_timer: Any
    _zap_view: Any
    background: Any
    before_open: Any
    boost: Any
    channels_provider: Any
    current: Playback | None
    episodes_provider: Any
    fetch_subtitle: Any
    idle_seconds: Any
    iphone_provider: Any
    last_end: dict | None
    logo_provider: Any
    memory_of: Any
    menu: player_ui.Panel | None
    mpv: Mpv
    next_provider: Any
    on_channel_failed: Any
    on_channel_ok: Any
    on_detached: Any
    on_episode: Any
    on_failed: Any
    on_finished: Any
    on_idle: Any
    on_language: Any
    on_memory_full: Any
    on_play_channel: Any
    on_play_episode: Any
    on_progress: Any
    on_scrobble: Any
    on_send_iphone: Any
    on_sub_kept: Any
    on_sub_scale: Any
    on_switch_source: Any
    on_synthetic_duration: Any
    on_synthetic_end: Any
    on_synthetic_failed: Any
    on_synthetic_resync: Any
    on_tracks: Any
    pip: Any
    remote: Any
    segment: Segment | None
    sources_provider: Any
    spanish_provider: Any
    still_provider: Any
    sub_delay: Any
    sub_scale: Any
    system_volume: Any
    versions_provider: Any
    MEMORY_EVERY: float
    MEMORY_LIMIT_MB: int
    POLL: float

    if TYPE_CHECKING:  # viven en una pieza de más adelante o en la fachada: aquí solo para los tipos
        def _apply_sub_pick(self, tracks: list) -> bool: ...
        def _at_end(self, segment: Segment) -> None: ...
        def _buffering_state(self, paused: bool) -> None: ...
        def _chapters_tick(self, segment: Segment, now: float) -> None: ...
        def _close_segment(self, segment: Segment) -> None: ...
        def _curtain(self, opacity: float) -> None: ...
        def _ensure_subtitles(self, lang: str, fallback_subs) -> None: ...
        def _fail(self, segment: Segment, filler: bool=False) -> None: ...
        def _filler(self, segment: Segment) -> bool: ...
        def _lift_curtain(self, segment: Segment) -> None: ...
        @staticmethod
        def _safe(fn, *args): ...
        def _save_progress(self, segment: Segment) -> None: ...
        def _scrobble(self, action: str, segment: Segment) -> None: ...
        def _started(self, segment: Segment) -> None: ...
        def _synthetic_tick(self, segment: Segment, now: float, paused: bool) -> None: ...
        def _upnext_tick(self, segment: Segment, now: float) -> None: ...
        def _watch(self, playback: Playback) -> None: ...
        def stop(self) -> None: ...
