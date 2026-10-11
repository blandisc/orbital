"""Piezas del reproductor que no hablan con mpv: armar el comando, idiomas, capítulos, botones
del mando y los datos de lo que se está viendo (Playback, Segment)."""

from __future__ import annotations

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
    X_BUTTON,
    Y_BUTTON,
)
from .mpv import PIPE

log = logging.getLogger(__name__)

CHAPTER_SEEK = 60  # LB/RB sin capítulos: ±1 min

LB, RB = 0x0100, 0x0200
STREMIO_SERVER = "http://127.0.0.1:11470"

STARTUP_TIMEOUT = 45.0  # s sin imagen: esa fuente no sirve, se prueba otra
SAVE_EVERY = 60.0  # s entre guardados del avance en Stremio
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


def find_mpv() -> str | None:
    """mpv de Orbital (%LOCALAPPDATA%\\orbital\\mpv) o el del sistema."""
    local = Path(os.environ.get("LOCALAPPDATA", "")) / "orbital" / "mpv" / "mpv.exe"
    if local.exists():
        return str(local)
    from shutil import which

    return which("mpv")


def stream_url(stream: dict) -> str | None:
    """URL que mpv puede abrir: directa (Real-Debrid, http) o un torrent vía el servidor de Stremio."""
    if stream.get("url"):
        return stream["url"]
    if stream.get("infoHash"):
        idx = stream.get("fileIdx")
        return f"{STREMIO_SERVER}/{stream['infoHash']}/{idx if idx is not None else -1}"
    return None


LANGS = {"en": ["en", "eng", "English"], "es": ["es", "spa", "Spanish", "es-419"]}


def build_lang_list(lang: str) -> list[str]:
    return LANGS.get(lang, [lang])


# Pantalla táctil: tocar el video pausa/reanuda (y Orbital muestra su barra); el doble toque ya no
# saca de pantalla completa por accidente.
TOUCH_BINDINGS = "MBTN_LEFT cycle pause\nMBTN_LEFT_DBL ignore\nMBTN_RIGHT ignore\n"


def input_conf() -> str | None:
    """Archivo de atajos de mpv de Orbital (se reescribe cada vez; vive junto a los datos de Orbital)."""
    path = Path(os.environ.get("LOCALAPPDATA", "")) / "orbital" / "mpv-input.conf"
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(TOUCH_BINDINGS, encoding="utf-8")
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


def build_command(mpv: str, url: str, title: str, *, start: float = 0, audio: str = "en",
                  subtitles: str = "en", sub_files: list[str] | None = None, bindings: str | None = None,
                  sub_scale: float = 1.0) -> list[str]:
    cmd = [
        mpv, url, f"--input-ipc-server={PIPE}", "--fullscreen", "--force-window=immediate",
        # keep-open: al terminar se queda en el último cuadro (Orbital decide: siguiente episodio o
        # salir). idle: si una fuente falla, mpv no se cierra; Orbital carga otra en la misma ventana.
        "--keep-open=yes", "--idle=yes", "--osc=no", "--input-default-bindings=yes",
        *([f"--input-conf={bindings}"] if bindings else []),
        f"--title={title}", f"--force-media-title={title}",
        f"--alang={','.join(build_lang_list(audio))}", *subtitle_options(subtitles, audio),
        "--sub-auto=fuzzy", "--cache=yes", "--demuxer-max-bytes=400MiB", "--hwdec=auto-safe",
        "--save-position-on-quit=no", "--msg-level=all=warn", "--background=#08080A", *OSD_STYLE,
    ]
    if abs(sub_scale - 1.0) > .01:
        cmd.append(f"--sub-scale={sub_scale:g}")
    if start > 5:
        cmd.append(f"--start={int(start)}")
    for sub in sub_files or []:
        cmd.append(f"--sub-file={sub}")
    return cmd


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
    failed: bool = False
    closed: bool = False
    last_save: float = field(default_factory=time.monotonic)
    last_tick: float = field(default_factory=time.monotonic)
    chapters: list[dict] = field(default_factory=list)  # [{"title", "time"}]
    skip_offered: set[int] = field(default_factory=set)
    upnext: dict | bool | None = None  # {"label", "title", "play"}; False = no hay
    upnext_requested: bool = False
    upnext_dismissed: bool = False
    upnext_deadline: float | None = None


class PlayerRemote:
    """Botones del mando -> nombres de botón ("a", "left"…), con autorrepetición al mantener la
    cruceta y LB/RB. Qué hace cada uno lo decide el reproductor (depende de si hay un menú abierto)."""

    BUTTONS = {A_BUTTON: "a", B_BUTTON: "b", X_BUTTON: "x", Y_BUTTON: "y", DPAD_LEFT: "left", DPAD_RIGHT: "right",
               DPAD_UP: "up", DPAD_DOWN: "down", LB: "lb", RB: "rb", LT: "lt", RT: "rt"}
    REPEAT = {DPAD_LEFT, DPAD_RIGHT, DPAD_UP, DPAD_DOWN, LB, RB}

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
                self._next.pop(bit, None)
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


def wrong_audio(tracks: list[dict], lang: str) -> bool:
    """Las pistas de audio tienen idioma y ninguna es el tuyo (sin etiquetas no se sabe: no avisa)."""
    tagged = [str(t.get("lang")).lower() for t in tracks or []
              if t.get("type") == "audio" and t.get("lang") and str(t.get("lang")).lower() not in ("und", "mul")]
    codes = {c.lower() for c in build_lang_list(lang)}
    return bool(tagged) and not any(code in codes for code in tagged)
