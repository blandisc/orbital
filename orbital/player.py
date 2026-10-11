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
"""

from __future__ import annotations

import json
import logging
import os
import re
import subprocess
import threading
import time
from dataclasses import dataclass, field
from pathlib import Path

from . import player_ui
from .gamepad import (A_BUTTON, B_BUTTON, BACK, DPAD_DOWN, DPAD_LEFT, DPAD_RIGHT, DPAD_UP, GUIDE, LT, RT, START,
                      X_BUTTON, Y_BUTTON)

log = logging.getLogger(__name__)

CHAPTER_SEEK = 60  # LB/RB sin capítulos: ±1 min

PIPE = r"\\.\pipe\orbital-mpv"
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


class Mpv:
    """Habla con mpv por su tubería JSON (una línea por comando)."""

    def __init__(self, pipe: str = PIPE) -> None:
        self.pipe = pipe
        self._lock = threading.Lock()

    def _send(self, payload: dict, label) -> dict | None:
        with self._lock:
            try:
                with open(self.pipe, "r+b", buffering=0) as fh:
                    fh.write((json.dumps(payload) + "\n").encode())
                    for _ in range(20):  # salta eventos hasta la respuesta
                        line = fh.readline()
                        if not line:
                            return None
                        data = json.loads(line)
                        if "error" in data:
                            return data
            except (OSError, ValueError) as exc:
                log.debug("mpv no respondió a %s: %s", label, exc)
        return None

    def command(self, *args) -> dict | None:
        return self._send({"command": list(args)}, args)

    def command_named(self, **args) -> dict | None:
        """Comando con argumentos por nombre (osd-overlay los necesita)."""
        return self._send({"command": args}, args.get("name"))

    def get(self, prop: str):
        reply = self.command("get_property", prop)
        return reply.get("data") if reply and reply.get("error") == "success" else None

    def show(self, text: str, ms: int = 1800) -> None:
        self.command("show-text", text, ms)


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


class OrbitalPlayer:
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
        self.menu: player_ui.Menu | None = None
        self._hud_timer: threading.Timer | None = None
        self._toast_timer: threading.Timer | None = None
        self._hud_visible = False
        self._card: dict | None = None  # {"kind": "skip" | "next" | "still", ...}
        self._subs_lang = "en"
        self._audio_lang = "en"
        self._fallback_subs = None
        self._user_quit = False  # B, Orbital o la voz lo cerraron: no es un fallo
        self._quiet_episodes = 0  # episodios encadenados sin tocar el mando
        self._buffering = False
        self.sub_scale = 1.0
        self.on_finished = on_finished  # (meta, posición, duración, segundos vistos)
        self.on_progress = None  # igual que on_finished, cada minuto y al pausar
        self.on_failed = None  # (meta, posición, sigue_abierto) -> True si se intenta con otra fuente
        self.next_provider = None  # (meta) -> {"label", "title", "play"} | None
        self.sources_provider = None  # (meta) -> [{"id", "label", "current"}]
        self.on_switch_source = None  # (meta, id_fuente, posición)
        self.on_episode = None  # (meta, ±1): episodio anterior / siguiente
        self.on_sub_scale = None  # (escala): para recordarla
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
        self._quiet_episodes = 0
        self._subs_lang, self._fallback_subs = subtitles, fallback_subs
        self._audio_lang = options.get("audio", "en")
        playback = Playback(title, process, time.time(), meta)
        self.current = playback
        self.segment = Segment(meta, title, url, start=float(options.get("start") or 0))
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
                    self.mpv.command("quit")
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
            self.toast("Esta fuente no trae audio en tu idioma · X › Fuente para elegir otra", 6)
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
            timer = threading.Timer(4, lambda: self.segment is segment and self.mpv.command("quit"))
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
            self.toast(f"Cargando… {int(percent)} %" if isinstance(percent, (int, float)) else "Cargando…", 2)
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
        self.mpv.command("quit")

    def _play_next(self, segment: Segment, auto: bool) -> None:
        info = segment.upnext
        if not info or segment.closed:
            return
        self._hide_card()
        self._quiet_episodes = self._quiet_episodes + 1 if auto else 0
        segment.upnext_dismissed = True  # que no se dispare dos veces
        self.toast(f"Cargando {info.get('label') or 'el siguiente episodio'}…", 6)
        threading.Thread(target=self._safe, args=(info["play"],), daemon=True, name="next-episode").start()

    # --- tarjetas encima del video -------------------------------------------------------------
    def _show_card(self, card: dict, now: float | None = None) -> None:
        self._card = card
        self._draw_card(now)

    def _draw_card(self, now: float | None = None) -> None:
        card = self._card
        if card is None:
            self._overlay(4, None)
            return
        if card["kind"] == "skip":
            ass = player_ui.card_ass(card["label"], actions=[("A", card["label"]), ("B", "Seguir viendo")])
        else:
            segment = card["segment"]
            info = segment.upnext or {}
            label = " · ".join(p for p in (info.get("label"), info.get("title")) if p)
            if card["kind"] == "still":
                ass = player_ui.card_ass("¿Sigues viendo?", label, [("A", "Seguir viendo"), ("B", "Salir")])
            else:
                now = time.monotonic() if now is None else now
                left = max(0.0, (segment.upnext_deadline or now) - now)
                ass = player_ui.card_ass(f"Siguiente episodio en {int(left + .99)}", label,
                                         [("A", "Ver ahora"), ("B", "Quedarme")], progress=left / UPNEXT_COUNTDOWN)
        self._overlay(4, ass)

    def _hide_card(self) -> None:
        self._card = None
        self._overlay(4, None)

    def _card_accept(self) -> None:
        card = self._card
        if card["kind"] == "skip":
            self._hide_card()
            self.mpv.command("seek", card["to"], "absolute")
        else:
            self._play_next(card["segment"], auto=False)

    def _card_dismiss(self) -> None:
        card = self._card
        self._hide_card()
        if card["kind"] == "still":
            self._user_quit = True
            self.mpv.command("quit")
        elif card["kind"] == "next":
            card["segment"].upnext_dismissed = True  # se queda en los créditos; al final, sale

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

    # --- interfaz encima del video (player_ui) -------------------------------------------------
    def _overlay(self, overlay_id: int, ass: str | None) -> None:
        self.mpv.command_named(name="osd-overlay", id=overlay_id, format="ass-events" if ass else "none",
                               data=ass or "", res_x=player_ui.W, res_y=player_ui.H, z=overlay_id)

    def show_hud(self) -> None:
        """Barra inferior: se queda en pausa; reproduciendo, se va sola a los pocos segundos."""
        if self.current is None or self.menu is not None:
            return
        tracks = self.mpv.get("track-list") or []
        paused = bool(self.mpv.get("pause"))
        meta = self.current.meta
        segment = self.segment
        hud = player_ui.Hud(
            title=self.current.title, detail=meta.get("detail", ""),
            position=self.mpv.get("time-pos"), duration=self.mpv.get("duration"), paused=paused,
            audio=player_ui.current_label(tracks, "audio"), subtitles=player_ui.current_label(tracks, "sub"),
            source=meta.get("source_label", ""), series=meta.get("kind") == "series" and self.on_episode is not None,
            ends=player_ui.ends_at(self.mpv.get("time-pos"), self.mpv.get("duration")),
            chapters=[float(c["time"]) for c in (segment.chapters if segment else [])])
        self._overlay(1, player_ui.hud_ass(hud))
        self._hud_visible = True
        if self._hud_timer:
            self._hud_timer.cancel()
        if not paused:
            self._hud_timer = threading.Timer(self.HUD_SECONDS, self._hide_hud_if_playing)
            self._hud_timer.daemon = True
            self._hud_timer.start()

    def hide_hud(self) -> None:
        if self._hud_timer:
            self._hud_timer.cancel()
        self._hud_visible = False
        self._overlay(1, None)

    def _hide_hud_if_playing(self) -> None:
        if not self.mpv.get("pause"):
            self.hide_hud()

    def toast(self, text: str, seconds: float = 1.6) -> None:
        self._overlay(3, player_ui.toast_ass(text))
        if self._toast_timer:
            self._toast_timer.cancel()
        self._toast_timer = threading.Timer(seconds, lambda: self._overlay(3, None))
        self._toast_timer.daemon = True
        self._toast_timer.start()

    # --- menú con pestañas: Audio · Subtítulos · Fuente ------------------------------------------
    def _tabs(self) -> list[str]:
        return ["audio", "sub"] + (["source"] if self.sources_provider and self.current else [])

    def open_menu(self, kind: str) -> None:
        tabs = self._tabs()
        if kind == "source" and self.current is not None:
            sources = self._safe(self.sources_provider, self.current.meta) or []
            self.menu = player_ui.source_menu(sources, tabs)
        else:
            tracks = self.mpv.get("track-list") or []
            extra = []
            if kind == "sub":
                if self._fallback_subs and self._subs_lang:
                    extra.append({"label": f"Buscar subtítulos en {player_ui.language(self._subs_lang).lower()}…",
                                  "action": ("fetch", self._subs_lang), "current": False})
                extra.append({"label": f"Tamaño: {player_ui.sub_scale_label(self.sub_scale)}",
                              "action": ("subscale", None), "current": False})
            self.menu = player_ui.track_menu(kind, tracks, extra, tabs)
        if self._hud_timer:
            self._hud_timer.cancel()
        self._hud_visible = False
        self._overlay(1, None)
        self._overlay(4, None)  # la tarjeta vuelve al cerrar el menú
        self._overlay(2, player_ui.menu_ass(self.menu))

    def close_menu(self) -> None:
        self.menu = None
        self._overlay(2, None)
        self._draw_card()

    def _choose(self, option: dict) -> None:
        prop, value = option["action"]
        if prop == "subscale":  # se queda en el menú: ves el cambio y sigues ajustando
            self.sub_scale = player_ui.next_sub_scale(self.sub_scale)
            self.mpv.command("set_property", "sub-scale", self.sub_scale)
            if self.on_sub_scale:
                self._safe(self.on_sub_scale, self.sub_scale)
            option["label"] = f"Tamaño: {player_ui.sub_scale_label(self.sub_scale)}"
            self._overlay(2, player_ui.menu_ass(self.menu))
            return
        self.close_menu()
        if prop == "fetch":
            self.toast("Buscando subtítulos…", 3)
            threading.Thread(target=self._fetch_subs, args=(value,), daemon=True).start()
            return
        if prop == "source":
            if option.get("current") or self.current is None:
                return
            position = self.mpv.get("time-pos")
            self.toast("Cambiando de fuente…", 4)
            if self.on_switch_source:
                threading.Thread(target=self._safe, args=(self.on_switch_source, self.current.meta, value,
                                                          float(position or 0)), daemon=True).start()
            return
        self.mpv.command("set_property", prop, value)
        kind = "Audio" if prop == "aid" else "Subtítulos"
        self.toast(f"{kind}: {option['label'].split(' · ')[0]}")

    def _fetch_subs(self, lang: str) -> None:
        try:
            urls = self._fallback_subs() if self._fallback_subs else []
        except Exception:  # noqa: BLE001
            log.exception("No pude buscar subtítulos")
            urls = []
        if urls:
            self.mpv.command("sub-add", urls[0], "select", "Subtítulos", lang)
            self.toast(f"Subtítulos: {player_ui.language(lang)}")
        else:
            self.toast("No encontré subtítulos en tu addon", 2.5)

    def _menu_press(self, button: str) -> None:
        menu = self.menu
        if button in ("up", "down"):
            if menu.options:
                menu.index = max(0, min(len(menu.options) - 1, menu.index + (-1 if button == "up" else 1)))
                self._overlay(2, player_ui.menu_ass(menu))
        elif button == "a" and menu.options:
            self._choose(menu.options[menu.index])
        elif button == "b":
            self.close_menu()
        elif button in ("lb", "rb", "left", "right"):
            tabs = menu.tabs
            i = tabs.index(menu.kind) if menu.kind in tabs else 0
            self.open_menu(tabs[(i + (-1 if button in ("lb", "left") else 1)) % len(tabs)])
        elif button in ("x", "y"):
            kind = "audio" if button == "x" else "sub"
            if kind == menu.kind:
                self.close_menu()
            else:
                self.open_menu(kind)

    # --- el mando ---------------------------------------------------------------------------------
    def press(self, button: str) -> None:
        """Un botón del mando con el reproductor al frente."""
        self._quiet_episodes = 0  # alguien está ahí
        if self.menu is not None:
            self._menu_press(button)
            return
        if self._card is not None and button in ("a", "b"):
            if button == "a":
                self._card_accept()
            else:
                self._card_dismiss()
            return
        if button == "a":
            self.mpv.command("cycle", "pause")
            self.show_hud()
        elif button == "b":
            # Primero se va la barra; con la barra oculta, B sale.
            if self._hud_visible:
                self.hide_hud()
            else:
                self._user_quit = True
                self.mpv.command("quit")
        elif button in ("x", "y"):
            self.open_menu("audio" if button == "x" else "sub")
        elif button in ("left", "right"):
            step = seek_step(self.remote.held(button))
            self.mpv.command("seek", step if button == "right" else -step, "relative")
            self.show_hud()
        elif button in ("lb", "rb"):
            delta = -1 if button == "lb" else 1
            if self.segment is not None and len(self.segment.chapters) > 1:
                self.mpv.command("add", "chapter", delta)
            else:
                self.mpv.command("seek", delta * CHAPTER_SEEK, "relative")
            self.show_hud()
        elif button in ("lt", "rt"):
            meta = self.current.meta if self.current else {}
            if meta.get("kind") == "series" and self.on_episode:
                self.toast("Episodio siguiente…" if button == "rt" else "Episodio anterior…", 3)
                threading.Thread(target=self._safe, args=(self.on_episode, meta, -1 if button == "lt" else 1),
                                 daemon=True).start()
        elif button in ("up", "down"):
            self.mpv.command("add", "volume", 5 if button == "up" else -5)
            volume = self.mpv.get("volume")
            self.toast(f"Volumen {int(volume)} %" if isinstance(volume, (int, float)) else "Volumen")

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
            self.mpv.command("quit")
            try:
                self.current.process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                self.current.process.kill()

    @property
    def playing(self) -> bool:
        return self.current is not None and self.current.process.poll() is None
