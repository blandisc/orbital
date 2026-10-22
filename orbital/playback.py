"""Piezas del reproductor que no hablan con mpv: armar el comando, idiomas, capítulos, botones
del mando y los datos de lo que se está viendo (Playback, Segment)."""

from __future__ import annotations

import functools
import logging
import os
import re
import subprocess
import time
from dataclasses import dataclass, field
from pathlib import Path

from .gamepad import (
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
    STICK_DOWN,
    STICK_LEFT,
    STICK_RIGHT,
    STICK_UP,
    X_BUTTON,
    Y_BUTTON,
)
from .library.iptv_health import DEFAULT_USER_AGENT as LIVE_USER_AGENT  # el mismo con el que se verifica cada canal
from .mpv import PIPE

NO_WINDOW = getattr(subprocess, "CREATE_NO_WINDOW", 0)  # sin consola negra al preguntarle a mpv

log = logging.getLogger(__name__)

CHAPTER_SEEK = 60  # LB/RB sin capítulos: ±1 min

LB, RB = 0x0100, 0x0200
STREMIO_SERVER = "http://127.0.0.1:11470"

STARTUP_TIMEOUT = 45.0  # s sin imagen: esa fuente no sirve, se prueba otra
LIVE_STARTUP_TIMEOUT = 12.0  # s sin imagen en un canal de TV: sin señal, se pasa al siguiente (medido: abre en ~1,7 s)
LIVE_SETTLE = 0.5  # s tras sintonizar en que las propiedades de mpv aún pueden ser las del canal anterior
# TV en vivo: nada de 400 MiB de caché (un video grabado se adelanta; la tele en vivo no). Pocos segundos por
# delante y, si la conexión se corta, mpv la reabre solo; sin respuesta en 10 s el canal se da por caído.
LIVE_ARGS = [
    "--cache=yes", "--cache-secs=8", "--demuxer-readahead-secs=8", "--demuxer-max-bytes=48MiB",
    "--demuxer-max-back-bytes=8MiB", "--network-timeout=10", "--tls-verify=no",
    "--stream-lavf-o=reconnect=1,reconnect_streamed=1,reconnect_at_eof=1,reconnect_delay_max=4",
]
SAVE_EVERY = 60.0  # s entre guardados del avance en Stremio
SCROBBLE_SEEK = 60.0  # s de salto en la posición (adelante o atrás) para volver a avisarle a Trakt del avance
UPNEXT_LOOKAHEAD = 180.0  # s antes del final: se busca ya el siguiente episodio (y su fuente)
UPNEXT_AT = 30.0  # s antes del final (o al empezar los créditos): tarjeta "Siguiente episodio"
UPNEXT_COUNTDOWN = 8.0
STILL_WATCHING_AFTER = 3  # episodios seguidos sin tocar el mando -> "¿Sigues viendo?"
SKIP_VISIBLE = 10.0  # s que se ofrece "Saltar intro"

INTRO = re.compile(r"\b(intro|opening|op|recap|previously|resumen|anteriormente|apertura)\b", re.I)
RECAP = re.compile(r"\b(recap|previously|resumen|anteriormente)\b", re.I)
CREDITS = re.compile(r"\b(credits?|ending|ed|outro|créditos|creditos)\b", re.I)

# Apariencia de los mensajes de mpv con la tipografía y la paleta de Orbital.
OSD_STYLE = [
    "--osd-font=Segoe UI Variable Display Semibold", "--osd-font-size=38", "--osd-color=#F5F4F0",
    "--osd-border-size=0", "--osd-shadow-offset=2", "--osd-shadow-color=#99000000",
    "--osd-bar-align-y=0.88", "--osd-bar-h=1.6", "--osd-bar-w=72", "--osd-margin-x=60", "--osd-margin-y=48",
    "--sub-font=Segoe UI Variable Text Semibold", "--sub-font-size=44", "--sub-border-size=2.5",
    "--sub-color=#F5F4F0", "--sub-border-color=#CC000000", "--sub-margin-y=56",
]


@functools.lru_cache(maxsize=4)
def background_args(mpv: str, mtime: float = 0) -> tuple[str, ...]:
    """El fondo gris de Orbital en mpv. mpv 0.41 cambió la opción: `--background` ahora es
    none|color|tiles y el color va en `--background-color`; con la forma vieja, el mpv nuevo se
    cierra al instante («Fatal error») y ninguna película abría. Se pregunta a mpv cuál entiende
    (una vez por versión: `mtime` cambia si se actualiza)."""
    try:
        out = subprocess.run([mpv, "--list-options"], capture_output=True, text=True, encoding="utf-8",
                             errors="replace", timeout=10, creationflags=NO_WINDOW).stdout
    except (OSError, subprocess.SubprocessError):
        return ()
    if "--background-color" in out:
        return ("--background-color=#08080A",)
    return ("--background=#08080A",) if "--background" in out else ()


def mpv_background(mpv: str) -> tuple[str, ...]:
    try:
        mtime = Path(mpv).stat().st_mtime
    except OSError:
        mtime = 0
    return background_args(mpv, mtime)


def find_mpv() -> str | None:
    """mpv de Orbital: el que viene dentro de Orbital.exe (carpeta mpv junto al programa), el de
    %LOCALAPPDATA%/orbital/mpv o el del sistema."""
    import sys

    candidates = [Path(sys.executable).parent / "mpv" / "mpv.exe"] if getattr(sys, "frozen", False) else []
    candidates.append(Path(os.environ.get("LOCALAPPDATA", "")) / "orbital" / "mpv" / "mpv.exe")
    for local in candidates:
        if local.exists():
            return str(local)
    from shutil import which

    return which("mpv")


def stream_url(stream: dict) -> str | None:
    """URL que mpv puede abrir: directa (Real-Debrid, http) o un torrent vía el servidor de Stremio."""
    url = stream.get("url")
    if isinstance(url, str) and url.strip():
        # Solo http(s) o magnet: un complemento no puede mandar a mpv a abrir un archivo local ni una opción.
        return url if re.match(r"^(https?://|magnet:)", url, re.I) else None
    info, idx = stream.get("infoHash"), stream.get("fileIdx")
    if isinstance(info, str) and re.fullmatch(r"[0-9a-fA-F]{40}|[A-Za-z2-7]{32}", info):
        idx = idx if isinstance(idx, int) and not isinstance(idx, bool) and idx >= -1 else -1
        return f"{STREMIO_SERVER}/{info}/{idx}"
    return None


LANGS = {"en": ["en", "eng", "English"], "es": ["es", "spa", "Spanish", "es-419"],
         "fr": ["fr", "fre", "fra", "French"], "pt": ["pt", "por", "pt-BR", "Portuguese"],
         "it": ["it", "ita", "Italian"], "de": ["de", "ger", "deu", "German"], "ja": ["ja", "jpn", "Japanese"],
         "ko": ["ko", "kor", "Korean"]}


def build_lang_list(lang: str) -> list[str]:
    return LANGS.get(lang, [lang])


def base_language(code: str | None) -> str:
    """El idioma de una pista sin importar cómo venga escrito: «spa», «es-419», «Spanish» → «es» (el iPhone y mpv
    no los etiquetan igual). "" si no se sabe."""
    code = str(code or "").strip().lower()
    if not code:
        return ""
    for lang, names in LANGS.items():
        if code in {n.lower() for n in names}:
            return lang
    return code.replace("_", "-").split("-")[0]


# Pantalla táctil (y ratón): mpv le dice a Orbital dónde tocaste y Orbital decide (enseñar los botones,
# pausar, adelantar, elegir en un panel…); el doble toque ya no saca de pantalla completa por accidente.
TOUCH_BINDINGS = ("MBTN_LEFT script-message orbital-tap ${mouse-pos/x} ${mouse-pos/y} ${osd-dimensions/w} ${osd-dimensions/h}\n"
                  "MBTN_LEFT_DBL ignore\nMBTN_RIGHT ignore\n")

# Con teclado: cada tecla se la pasa a Orbital con el nombre del botón del mando que hace lo mismo (y la barra
# enseña las teclas). Esc pregunta antes de salir; q también (antes cerraba sin guardar cómo terminó).
KEY_BINDINGS = "".join(f"{key} {'repeatable ' if repeat else ''}script-message orbital-key {name}\n" for key, name, repeat in (
    ("SPACE", "a", False), ("ENTER", "a", False), ("KP_ENTER", "a", False),
    ("LEFT", "left", True), ("RIGHT", "right", True), ("UP", "up", True), ("DOWN", "down", True),
    ("ESC", "esc", False), ("BS", "esc", False), ("q", "esc", False),
    ("x", "x", False), ("y", "y", False), ("PGUP", "lb", False), ("PGDWN", "rb", False),
    ("[", "lt", False), ("]", "rt", False)))


# El ratón (o el dedo) mantenido: input.conf solo sabe «bajó», así que un script mínimo de mpv avisa también por dónde
# va mientras lo arrastras y dónde lo soltaste. Así se arrastra la bolita de la barra para moverte en el video.
# Reemplaza al MBTN_LEFT de TOUCH_BINDINGS (que queda por si mpv no trae Lua).
MOUSE_SCRIPT = """-- Orbital: el botón del ratón con bajar, arrastrar y soltar (lo escribe Orbital; se reescribe cada vez).
local held = false
local function pos()
  local m = mp.get_property_native("mouse-pos") or {}
  local d = mp.get_property_native("osd-dimensions") or {}
  return tostring(m.x or 0), tostring(m.y or 0), tostring(d.w or 0), tostring(d.h or 0)
end
mp.add_forced_key_binding("MBTN_LEFT", "orbital-mouse", function(e)
  local x, y, w, h = pos()
  if e.event == "down" then
    held = true
    mp.commandv("script-message", "orbital-tap", x, y, w, h)
  elseif e.event == "up" and held then
    held = false
    mp.commandv("script-message", "orbital-drop", x, y, w, h)
  end
end, {complex = true})
mp.observe_property("mouse-pos", "native", function()
  if held then
    local x, y, w, h = pos()
    mp.commandv("script-message", "orbital-drag", x, y, w, h)
  end
end)
"""
MOUSE_SCRIPT_NAME = "orbital-mouse.lua"


def input_conf() -> str | None:
    """Archivo de atajos de mpv de Orbital (se reescribe cada vez; vive junto a los datos de Orbital), con el script del
    ratón al lado (MOUSE_SCRIPT; build_command lo carga si está)."""
    path = Path(os.environ.get("LOCALAPPDATA", "")) / "orbital" / "mpv-input.conf"
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(TOUCH_BINDINGS + KEY_BINDINGS, encoding="utf-8")
        path.with_name(MOUSE_SCRIPT_NAME).write_text(MOUSE_SCRIPT, encoding="utf-8")
        return str(path)
    except OSError:
        return None


def subtitle_options(subtitles: str, audio: str) -> list[str]:
    """Qué subtítulos elige mpv solo. "forced": solo los forzados en tu idioma (los carteles y
    diálogos en otro idioma de una película doblada), nunca los completos."""
    if subtitles == "forced":
        return [f"--slang={','.join(build_lang_list(audio))}", "--subs-with-matching-audio=forced",
                "--subs-fallback=no", "--subs-fallback-forced=always"]
    if not subtitles:
        return ["--sid=no"]
    return [f"--slang={','.join(build_lang_list(subtitles))}"]


def track_properties(audio: str, subtitles: str) -> list[tuple[str, str]]:
    """Lo mismo que subtitle_options y --alang, para el mpv ya abierto (otro episodio u otra fuente).
    aid/sid vuelven a «auto»: una pista elegida a mano en el panel (aid=2) se quedaba puesta y el
    siguiente episodio salía con la pista 2, fuera del idioma que recuerda la serie."""
    props = [("aid", "auto"), ("alang", ",".join(build_lang_list(audio)))]
    if subtitles == "forced":
        return props + [("sid", "auto"), ("slang", ",".join(build_lang_list(audio))), ("subs-with-matching-audio", "forced"),
                        ("subs-fallback", "no"), ("subs-fallback-forced", "always")]
    if not subtitles:
        return props + [("sid", "no")]
    return props + [("sid", "auto"), ("slang", ",".join(build_lang_list(subtitles))), ("subs-with-matching-audio", "yes"),
                    ("subs-fallback", "default"), ("subs-fallback-forced", "yes")]


def build_command(mpv: str, url: str, title: str, *, start: float = 0, audio: str = "en",
                  subtitles: str = "en", sub_files: list[str] | None = None, bindings: str | None = None,
                  sub_scale: float = 1.0, live: bool = False, user_agent: str | None = None,
                  referrer: str | None = None) -> list[str]:
    """`live`: un canal de TV (caché corta, reconexión, sin posición que recordar). `user_agent` y `referrer`
    son los del canal; los canales siguientes los llevan en su propio `loadfile` (ver OrbitalPlayer.tune)."""
    # Por delante 200 MiB y hacia atrás 25 MiB, escrito aquí para que una versión nueva de mpv no cambie el valor de
    # fábrica sin que se note. Antes 400 + 50: con Los Simpson al aire mpv llegaba a 1 GB en una consola de 12 GB que
    # también corre los juegos. 200 MiB siguen siendo ~3 min de un 1080p y ~30 s de un 4K remux por delante.
    cache = LIVE_ARGS if live else ["--cache=yes", "--demuxer-max-bytes=200MiB", "--demuxer-max-back-bytes=25MiB"]
    cmd = [
        mpv, f"--input-ipc-server={PIPE}", "--fullscreen", "--force-window=immediate",
        # keep-open: al terminar se queda en el último cuadro (Orbital decide: siguiente episodio o
        # salir). idle: si una fuente falla, mpv no se cierra; Orbital carga otra en la misma ventana.
        "--keep-open=yes", "--idle=yes", "--osc=no", "--input-default-bindings=yes",
        *([f"--input-conf={bindings}"] if bindings else []),
        *([f"--script={script}"] if bindings and (script := Path(bindings).with_name(MOUSE_SCRIPT_NAME)).is_file() else []),
        f"--title={title}", f"--force-media-title={title}",
        f"--alang={','.join(build_lang_list(audio))}", *subtitle_options(subtitles, audio),
        "--sub-auto=fuzzy", *cache, "--hwdec=auto-safe",
        # Sin el modo «flip» de Direct3D: con él, cada ventana de mpv dejaba ~140 MB en la memoria de dibujo de Windows
        # (DWM) y cada cambio de video ~100 MB más, sin devolverlos nunca (controlador AMD, tele 4K: llegó a 14 GB y
        # Windows se quedaba sin RAM). Medido en la tele: con flip, +578 MB en 4 ventanas; sin flip, 0 MB.
        "--d3d11-flip=no",
        "--save-position-on-quit=no", "--volume=100", "--msg-level=all=warn", *mpv_background(mpv), *OSD_STYLE,  # el volumen es el de Windows
    ]
    if live:
        cmd.append(f"--user-agent={user_agent or LIVE_USER_AGENT}")
        if referrer:
            cmd.append(f"--referrer={referrer}")
    if abs(sub_scale - 1.0) > .01:
        cmd.append(f"--sub-scale={sub_scale:g}")
    if start > 5 and not live:
        cmd.append(f"--start={int(start)}")
    for sub in sub_files or []:
        cmd.append(f"--sub-file={sub}")
    # La URL va al final, después de «--»: aunque empiece con «-», mpv nunca la lee como una opción.
    return [*cmd, "--", url]


def seek_step(repeats: int) -> int:
    """Mantener ◀/▶ acelera: 10 s, luego 30 s y luego 1 min por paso (como en las TV)."""
    if repeats < 4:
        return 10
    if repeats < 10:
        return 30
    return 60


def chapter_kind(title: str) -> str | None:
    """"intro" (se puede saltar), "credits" (aparece el siguiente episodio) o None."""
    if not title:
        return None
    if CREDITS.search(title):
        return "credits"
    if INTRO.search(title):
        return "intro"
    return None


@dataclass
class Playback:
    title: str
    process: subprocess.Popen
    started: float
    meta: dict  # kind, meta_id, video_id: para guardar el progreso en Stremio
    memory_handled: bool = False  # el vigilante de memoria ya actuó con este mpv (una vez basta)


@dataclass
class Segment:
    """Un archivo dentro de la misma ventana de mpv (un episodio, o la misma película en otra fuente)."""

    meta: dict
    title: str
    url: str
    start: float = 0.0
    loaded: float = field(default_factory=time.monotonic)
    position: float = 0.0
    duration: float = 0.0
    watched: float = 0.0
    saved_watched: float = 0.0
    playing: bool = False  # ya hubo imagen (mpv sabe la duración)
    scrobbling: bool = False  # ya se le avisó a Trakt que empezó (y aún no que paró)
    live: bool = False  # un canal de TV: sin duración, sin progreso que guardar, sin episodios
    failed: bool = False
    closed: bool = False
    last_save: float = field(default_factory=time.monotonic)
    last_tick: float = field(default_factory=time.monotonic)
    chapters: list[dict] = field(default_factory=list)  # [{"title", "time"}]
    skip_offered: set[int] = field(default_factory=set)
    upnext: dict | bool | None = None  # {"label", "title", "play"}; False = no hay
    upnext_requested: bool = False
    upnext_tries: int = 0  # Cinemeta falló al preguntar por el siguiente: se reintenta
    next_loading: float = 0.0  # cuándo se pidió el siguiente episodio (mientras carga, el final no cierra)
    upnext_dismissed: bool = False
    upnext_deadline: float | None = None
    paused_at: float | None = None  # canal de Orbital: desde cuándo está en pausa (al seguir, regresa al aire)
    duration_told: bool = False  # canal de Orbital: ya se le dijo cuánto dura de verdad este episodio
    grace_until: float = 0.0  # otro archivo en la misma ventana: hasta entonces no se lee su posición (player.tick)


class PlayerRemote:
    """Botones del mando -> nombres de botón ("a", "left"…), con autorrepetición al mantener la
    cruceta y LB/RB. Qué hace cada uno lo decide el reproductor (depende de si hay un menú abierto)."""

    BUTTONS = {A_BUTTON: "a", B_BUTTON: "b", X_BUTTON: "x", Y_BUTTON: "y", DPAD_LEFT: "left", DPAD_RIGHT: "right",
               DPAD_UP: "up", DPAD_DOWN: "down", LB: "lb", RB: "rb", LT: "lt", RT: "rt",
               STICK_UP: "stick-up", STICK_DOWN: "stick-down", STICK_LEFT: "stick-left", STICK_RIGHT: "stick-right"}
    REPEAT = {DPAD_LEFT, DPAD_RIGHT, DPAD_UP, DPAD_DOWN, LB, RB, STICK_UP, STICK_DOWN, STICK_LEFT, STICK_RIGHT,
              B_BUTTON, LT, RT}  # B, LT y RT mantenidos: el anillo de «Salir» / «Episodio» se va llenando
    RELEASE = {B_BUTTON, LT, RT}  # al soltar llega "b-up" / "lt-up" / "rt-up" (el anillo se va si soltaste antes)

    def __init__(self, on_press, delay: float = .35, rate: float = .15) -> None:
        self.on_press = on_press
        self.delay = delay
        self.rate = rate
        self._next: dict[int, float] = {}
        self._repeats: dict[str, int] = {}

    def held(self, name: str) -> int:
        """Cuántas veces se ha repetido ese botón sin soltarlo (0 = pulsación nueva)."""
        return self._repeats.get(name, 0)

    def actions(self, buttons: int, now: float) -> list[str]:
        """Qué botones cuentan como pulsados en este momento (separado para poder probarlo)."""
        if buttons & (GUIDE | BACK | START):
            self._next.clear()  # Home y Select+Start son de Orbital
            self._repeats.clear()
            return []
        out = []
        for bit, name in self.BUTTONS.items():
            if not buttons & bit:
                if self._next.pop(bit, None) is not None and bit in self.RELEASE:
                    out.append(f"{name}-up")
                self._repeats.pop(name, None)
                continue
            if bit not in self._next:
                self._next[bit] = now + self.delay
                self._repeats[name] = 0
            elif bit in self.REPEAT and now >= self._next[bit]:
                self._next[bit] = now + self.rate
                self._repeats[name] = self._repeats.get(name, 0) + 1
            else:
                continue
            out.append(name)
        return out

    def update(self, buttons: int, now: float) -> None:
        for name in self.actions(buttons, now):
            self.on_press(name)


def has_language(tracks: list[dict], kind: str, codes: set[str]) -> bool:
    """¿El video ya trae una pista (audio/sub) en ese idioma?"""
    return any(t.get("type") == kind and str(t.get("lang") or "").lower() in codes for t in tracks or [])


def idle_expired(since: float, now: float, limit: float) -> bool:
    """¿Lleva más de `limit` segundos en pausa? (0 = nunca se cierra solo)."""
    return limit > 0 and now - since >= limit


SPANISH_TRACK = re.compile(r"^(es|spa|es-\w+)$", re.I)
LATINO_TRACK = re.compile(r"latin|\blat\b|419|latam|m[eé]xic|hispanoam", re.I)
CASTELLANO_TRACK = re.compile(r"castellano|castilian|espa[ñn]a|spain|\bes-es\b|europe|ib[eé]ric", re.I)


def dub_track(tracks: list[dict], dub: str = "latino") -> int | None | bool:
    """La pista de audio de ese doblaje del español (los canales de Orbital). La que lo dice primero; si ninguna lo dice,
    una en español que no diga ser del otro. None si el archivo no dice nada de idiomas (se queda la que trae);
    False si trae español pero solo del otro doblaje, o idiomas pero ningún español (no sirve: otra fuente)."""
    audio = [t for t in tracks or [] if t.get("type") == "audio" and isinstance(t.get("id"), int)]
    wanted, other = (LATINO_TRACK, CASTELLANO_TRACK) if dub == "latino" else (CASTELLANO_TRACK, LATINO_TRACK)

    def label(t: dict) -> str:
        return f"{t.get('lang') or ''} {t.get('title') or ''}".strip()

    spanish = [t for t in audio if SPANISH_TRACK.match(str(t.get("lang") or "")) or re.search(r"espa[ñn]ol|spanish", label(t), re.I)]
    for t in spanish:
        if wanted.search(label(t)):
            return t["id"]
    neutral = [t for t in spanish if not other.search(label(t))]
    if neutral:
        return neutral[0]["id"]
    if spanish or any(t.get("lang") and str(t.get("lang")).lower() not in ("und", "mul") for t in audio):
        return False
    return None


def wrong_audio(tracks: list[dict], lang: str) -> bool:
    """Las pistas de audio tienen idioma y ninguna es el tuyo (sin etiquetas no se sabe: no avisa)."""
    tagged = [str(t.get("lang")).lower() for t in tracks or []
              if t.get("type") == "audio" and t.get("lang") and str(t.get("lang")).lower() not in ("und", "mul")]
    codes = {c.lower() for c in build_lang_list(lang)}
    return bool(tagged) and not any(code in codes for code in tagged)
