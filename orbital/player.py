"""Reproductor de Orbital: mpv a pantalla completa, manejado por el mando.

Orbital elige la fuente (library/streams.py) y la abre en mpv con un canal de control
(--input-ipc-server). Los botones del mando no se traducen a teclas: Orbital manda comandos a mpv
(pausa, adelantar, volumen, audio, subtítulos), así que funciona igual en cualquier idioma de
teclado y sin depender de los atajos de mpv.

  A pausa · ←/→ ±10 s (mantener: continuo) · LB/RB ±1 min · ↑/↓ volumen
  X audio · Y subtítulos · B salir (guarda dónde ibas)
"""

from __future__ import annotations

import json
import logging
import os
import subprocess
import threading
import time
from dataclasses import dataclass
from pathlib import Path

from .gamepad import (A_BUTTON, B_BUTTON, BACK, DPAD_DOWN, DPAD_LEFT, DPAD_RIGHT, DPAD_UP, GUIDE, START,
                      X_BUTTON, Y_BUTTON)

log = logging.getLogger(__name__)

PIPE = r"\\.\pipe\orbital-mpv"
LB, RB = 0x0100, 0x0200
STREMIO_SERVER = "http://127.0.0.1:11470"

# Apariencia de los mensajes de mpv con la tipografía y la paleta de Orbital.
OSD_STYLE = [
    "--osd-font=Segoe UI Variable Display Semibold", "--osd-font-size=38", "--osd-color=#F5F4F0",
    "--osd-border-size=0", "--osd-shadow-offset=2", "--osd-shadow-color=#99000000",
    "--osd-bar-align-y=0.88", "--osd-bar-h=1.6", "--osd-bar-w=72", "--osd-margin-x=60", "--osd-margin-y=48",
    "--sub-font=Segoe UI Variable Text Semibold", "--sub-font-size=44", "--sub-border-size=2.5",
    "--sub-color=#F5F4F0", "--sub-border-color=#CC000000",
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


def build_command(mpv: str, url: str, title: str, *, start: float = 0, audio: str = "en",
                  subtitles: str = "en", sub_files: list[str] | None = None) -> list[str]:
    cmd = [
        mpv, url, f"--input-ipc-server={PIPE}", "--fullscreen", "--force-window=immediate",
        "--keep-open=no", "--idle=no", "--osc=no", "--input-default-bindings=yes",
        f"--title={title}", f"--force-media-title={title}",
        f"--alang={','.join(build_lang_list(audio))}", f"--slang={','.join(build_lang_list(subtitles))}",
        "--sub-auto=fuzzy", "--cache=yes", "--demuxer-max-bytes=400MiB", "--hwdec=auto-safe",
        "--save-position-on-quit=no", "--msg-level=all=warn", *OSD_STYLE,
    ]
    if start > 5:
        cmd.append(f"--start={int(start)}")
    for sub in sub_files or []:
        cmd.append(f"--sub-file={sub}")
    return cmd


@dataclass
class Playback:
    title: str
    process: subprocess.Popen
    started: float
    meta: dict  # kind, id, video_id: para guardar el progreso en Stremio


class Mpv:
    """Habla con mpv por su tubería JSON (una línea por comando)."""

    def __init__(self, pipe: str = PIPE) -> None:
        self.pipe = pipe
        self._lock = threading.Lock()

    def command(self, *args) -> dict | None:
        with self._lock:
            try:
                with open(self.pipe, "r+b", buffering=0) as fh:
                    fh.write((json.dumps({"command": list(args)}) + "\n").encode())
                    for _ in range(20):  # salta eventos hasta la respuesta
                        line = fh.readline()
                        if not line:
                            return None
                        data = json.loads(line)
                        if "error" in data:
                            return data
            except (OSError, ValueError) as exc:
                log.debug("mpv no respondió a %s: %s", args, exc)
        return None

    def get(self, prop: str):
        reply = self.command("get_property", prop)
        return reply.get("data") if reply and reply.get("error") == "success" else None

    def show(self, text: str, ms: int = 1800) -> None:
        self.command("show-text", text, ms)


class PlayerRemote:
    """Botones del mando -> comandos de mpv (con autorrepetición al mantener ←/→ y ↑/↓)."""

    SEEK = {DPAD_LEFT: -10, DPAD_RIGHT: 10, LB: -60, RB: 60}
    VOLUME = {DPAD_UP: 5, DPAD_DOWN: -5}

    def __init__(self, mpv: Mpv, delay: float = .35, rate: float = .15) -> None:
        self.mpv = mpv
        self.delay = delay
        self.rate = rate
        self._next: dict[int, float] = {}

    def actions(self, buttons: int, now: float) -> list[tuple]:
        """Qué comandos mandar en este momento (separado de mpv para poder probarlo)."""
        if buttons & (GUIDE | BACK | START):
            self._next.clear()  # Home y Select+Start son de Orbital
            return []
        out = []
        for bit in (A_BUTTON, B_BUTTON, X_BUTTON, Y_BUTTON, *self.SEEK, *self.VOLUME):
            if not buttons & bit:
                self._next.pop(bit, None)
                continue
            repeat = bit in self.SEEK or bit in self.VOLUME
            if bit not in self._next:
                self._next[bit] = now + self.delay
            elif repeat and now >= self._next[bit]:
                self._next[bit] = now + self.rate
            else:
                continue
            out.append(self._action(bit))
        return out

    def _action(self, bit: int) -> tuple:
        if bit == A_BUTTON:
            return ("cycle", "pause")
        if bit == B_BUTTON:
            return ("quit",)
        if bit == X_BUTTON:
            return ("cycle", "audio")
        if bit == Y_BUTTON:
            return ("cycle", "sub")
        if bit in self.SEEK:
            return ("seek", self.SEEK[bit], "relative")
        return ("add", "volume", self.VOLUME[bit])

    # Lo que se ve después de cada botón (mpv expande ${…}; tras ":" va el texto si no hay pista).
    FEEDBACK = {
        "audio": ("show-text", "Audio · ${current-tracks/audio/lang:${current-tracks/audio/title:—}}", 1600),
        "sub": ("show-text", "Subtítulos · ${current-tracks/sub/lang:no}", 1600),
        "volume": ("show-text", "Volumen · ${volume}%", 900),
    }

    def update(self, buttons: int, now: float) -> None:
        for action in self.actions(buttons, now):
            self.mpv.command(*action)
            if action[0] == "seek" or action == ("cycle", "pause"):
                self.mpv.command("show-progress")
            elif action[0] != "quit":
                self.mpv.command(*self.FEEDBACK[action[1]])


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
    """Arranca mpv, lo vigila y al terminar avisa cuánto se vio (para Seguir viendo).

    El proceso lo lanza el Launcher de Orbital (así Home, la pausa, Select+Start y la vuelta a
    Orbital funcionan igual que con un juego); aquí solo se sigue la posición por la tubería.
    """

    POLL = 3.0

    def __init__(self, on_finished=None, mpv: Mpv | None = None, idle_seconds: float = 0, on_idle=None) -> None:
        self.mpv = mpv or Mpv()
        self.remote = PlayerRemote(self.mpv)
        self.current: Playback | None = None
        self.on_finished = on_finished  # (meta, posición, duración, segundos vistos)
        # Un video olvidado en pausa (saliste con Home y te fuiste) se cierra solo; el avance se guarda.
        self.idle_seconds = idle_seconds
        self.on_idle = on_idle  # (título, minutos): para avisar en Orbital

    def play(self, run, mpv_exe: str, url: str, title: str, meta: dict, *, subtitles: str = "en",
             fallback_subs=None, **options) -> subprocess.Popen:
        """`run(argv)` lanza el proceso; `fallback_subs()` da URLs de subtítulos si el video no trae."""
        self.stop()
        process = run(build_command(mpv_exe, url, title, subtitles=subtitles, **options))
        playback = Playback(title, process, time.time(), meta)
        self.current = playback
        threading.Thread(target=self._watch, args=(playback, float(options.get("start") or 0), subtitles, fallback_subs,
                                                   options.get("audio", "en")),
                         daemon=True, name="mpv").start()
        log.info("Reproduciendo en mpv: %s", title)
        return process

    def _watch(self, playback: Playback, start: float, subtitles: str, fallback_subs, audio: str = "en") -> None:
        # Mientras reproduce, pregunta la posición cada pocos segundos (al cerrar ya no se puede).
        position, duration, watched, subs_checked = start, 0.0, 0.0, False
        last = time.monotonic()
        paused_since: float | None = None
        while playback.process.poll() is None:
            time.sleep(self.POLL)
            pos, dur = self.mpv.get("time-pos"), self.mpv.get("duration")
            now = time.monotonic()
            paused = bool(self.mpv.get("pause"))
            paused_since = (paused_since or now) if paused else None
            if paused_since is not None and idle_expired(paused_since, now, self.idle_seconds):
                log.info("%s llevaba %d min en pausa: se cierra (el avance queda guardado)",
                         playback.title, self.idle_seconds // 60)
                self.mpv.command("quit")
                if self.on_idle:
                    self.on_idle(playback.title, int(self.idle_seconds // 60))
                paused_since = None
            if isinstance(pos, (int, float)) and isinstance(dur, (int, float)) and dur > 0:
                if not paused:
                    watched += min(now - last, abs(pos - position) + 1)
                position, duration = float(pos), float(dur)
                if not subs_checked:
                    subs_checked = True
                    tracks = self.mpv.get("track-list") or []
                    if wrong_audio(tracks, audio):
                        # El archivo dice ser de otro idioma (un doblaje mal etiquetado): avisa en vez de callar.
                        self.mpv.command("show-text", "Esta fuente no trae audio en tu idioma  ·  B para elegir otra", 6000)
                    elif start > 5:
                        self.mpv.command("show-text", "Sigues donde te quedaste  ·  LB para regresar 1 min", 2600)
                    self._ensure_subtitles(subtitles, fallback_subs)
            last = now
        if self.current is playback:
            self.current = None
        if self.on_finished and duration:
            try:
                self.on_finished(playback.meta, position, duration, watched)
            except Exception:  # noqa: BLE001
                log.exception("Error guardando el progreso")

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
        self.mpv.command("show-progress")

    # --- para la voz -----------------------------------------------------------------------
    def set_pause(self, paused: bool) -> None:
        self.mpv.command("set_property", "pause", paused)
        self.show_progress()

    def seek(self, seconds: float) -> None:
        self.mpv.command("seek", seconds, "relative")
        self.show_progress()

    def select_language(self, kind: str, lang: str) -> bool:
        """Cambia a la pista de audio o subtítulos en ese idioma, si el video la trae."""
        codes = {c.lower() for c in build_lang_list(lang)}
        track = next((t for t in self.mpv.get("track-list") or []
                      if t.get("type") == kind and str(t.get("lang") or "").lower() in codes), None)
        if track is None:
            return False
        self.mpv.command("set_property", "aid" if kind == "audio" else "sid", track["id"])
        self.mpv.command(*PlayerRemote.FEEDBACK["audio" if kind == "audio" else "sub"])
        return True

    def add_subtitles(self, url: str, lang: str) -> None:
        self.mpv.command("sub-add", url, "select", "Subtítulos", lang)
        self.mpv.command(*PlayerRemote.FEEDBACK["sub"])

    def subtitles_off(self) -> None:
        self.mpv.command("set_property", "sid", "no")
        self.mpv.command(*PlayerRemote.FEEDBACK["sub"])

    def stop(self) -> None:
        if self.current and self.current.process.poll() is None:
            self.mpv.command("quit")
            try:
                self.current.process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                self.current.process.kill()

    @property
    def playing(self) -> bool:
        return self.current is not None and self.current.process.poll() is None
