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

from . import player_ui
from .gamepad import (A_BUTTON, B_BUTTON, BACK, DPAD_DOWN, DPAD_LEFT, DPAD_RIGHT, DPAD_UP, GUIDE, START,
                      X_BUTTON, Y_BUTTON)

log = logging.getLogger(__name__)

SEEK = {"left": -10, "right": 10, "lb": -60, "rb": 60}

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

    def command_named(self, **args) -> dict | None:
        """Comando con argumentos por nombre (osd-overlay los necesita)."""
        with self._lock:
            try:
                with open(self.pipe, "r+b", buffering=0) as fh:
                    fh.write((json.dumps({"command": args}) + "\n").encode())
                    for _ in range(20):
                        line = fh.readline()
                        if not line:
                            return None
                        data = json.loads(line)
                        if "error" in data:
                            return data
            except (OSError, ValueError) as exc:
                log.debug("mpv no respondió a %s: %s", args.get("name"), exc)
        return None

    def get(self, prop: str):
        reply = self.command("get_property", prop)
        return reply.get("data") if reply and reply.get("error") == "success" else None

    def show(self, text: str, ms: int = 1800) -> None:
        self.command("show-text", text, ms)


class PlayerRemote:
    """Botones del mando -> nombres de botón ("a", "left"…), con autorrepetición al mantener la
    cruceta y LB/RB. Qué hace cada uno lo decide el reproductor (depende de si hay un menú abierto)."""

    BUTTONS = {A_BUTTON: "a", B_BUTTON: "b", X_BUTTON: "x", Y_BUTTON: "y", DPAD_LEFT: "left", DPAD_RIGHT: "right",
               DPAD_UP: "up", DPAD_DOWN: "down", LB: "lb", RB: "rb"}
    REPEAT = {DPAD_LEFT, DPAD_RIGHT, DPAD_UP, DPAD_DOWN, LB, RB}

    def __init__(self, on_press, delay: float = .35, rate: float = .15) -> None:
        self.on_press = on_press
        self.delay = delay
        self.rate = rate
        self._next: dict[int, float] = {}

    def actions(self, buttons: int, now: float) -> list[str]:
        """Qué botones cuentan como pulsados en este momento (separado para poder probarlo)."""
        if buttons & (GUIDE | BACK | START):
            self._next.clear()  # Home y Select+Start son de Orbital
            return []
        out = []
        for bit, name in self.BUTTONS.items():
            if not buttons & bit:
                self._next.pop(bit, None)
                continue
            if bit not in self._next:
                self._next[bit] = now + self.delay
            elif bit in self.REPEAT and now >= self._next[bit]:
                self._next[bit] = now + self.rate
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
    """Arranca mpv, lo vigila y al terminar avisa cuánto se vio (para Seguir viendo).

    El proceso lo lanza el Launcher de Orbital (así Home, la pausa, Select+Start y la vuelta a
    Orbital funcionan igual que con un juego); aquí solo se sigue la posición por la tubería.
    """

    POLL = 3.0

    def __init__(self, on_finished=None, mpv: Mpv | None = None, idle_seconds: float = 0, on_idle=None) -> None:
        self.mpv = mpv or Mpv()
        self.remote = PlayerRemote(self.press)
        self.current: Playback | None = None
        self.menu: player_ui.Menu | None = None
        self._hud_timer: threading.Timer | None = None
        self._toast_timer: threading.Timer | None = None
        self._subs_lang = "en"
        self._fallback_subs = None
        self.on_finished = on_finished  # (meta, posición, duración, segundos vistos)
        # Un video olvidado en pausa (saliste con Home y te fuiste) se cierra solo; el avance se guarda.
        self.idle_seconds = idle_seconds
        self.on_idle = on_idle  # (título, minutos): para avisar en Orbital

    def play(self, run, mpv_exe: str, url: str, title: str, meta: dict, *, subtitles: str = "en",
             fallback_subs=None, **options) -> subprocess.Popen:
        """`run(argv)` lanza el proceso; `fallback_subs()` da URLs de subtítulos si el video no trae."""
        self.stop()
        process = run(build_command(mpv_exe, url, title, subtitles=subtitles, **options))
        self.menu = None
        self._subs_lang, self._fallback_subs = subtitles, fallback_subs
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
                        self.toast("Esta fuente no trae audio en tu idioma · B para elegir otra", 6)
                    elif start > 5:
                        self.toast("Sigues donde te quedaste · LB regresa 1 min", 3.5)
                    self._ensure_subtitles(subtitles, fallback_subs)
                    self.show_hud()  # al empezar: qué estás viendo y qué hace cada botón
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
        self.show_hud()

    # --- interfaz encima del video (player_ui) -------------------------------------------------
    HUD_SECONDS = 4.0

    def _overlay(self, overlay_id: int, ass: str | None) -> None:
        self.mpv.command_named(name="osd-overlay", id=overlay_id, format="ass-events" if ass else "none",
                               data=ass or "", res_x=player_ui.W, res_y=player_ui.H, z=overlay_id)

    def show_hud(self) -> None:
        """Barra inferior: se queda en pausa; reproduciendo, se va sola a los pocos segundos."""
        if self.current is None or self.menu is not None:
            return
        tracks = self.mpv.get("track-list") or []
        paused = bool(self.mpv.get("pause"))
        hud = player_ui.Hud(
            title=self.current.title, detail=self.current.meta.get("detail", ""),
            position=self.mpv.get("time-pos"), duration=self.mpv.get("duration"), paused=paused,
            audio=player_ui.current_label(tracks, "audio"), subtitles=player_ui.current_label(tracks, "sub"))
        self._overlay(1, player_ui.hud_ass(hud))
        if self._hud_timer:
            self._hud_timer.cancel()
        if not paused:
            self._hud_timer = threading.Timer(self.HUD_SECONDS, self._hide_hud_if_playing)
            self._hud_timer.daemon = True
            self._hud_timer.start()

    def _hide_hud_if_playing(self) -> None:
        if not self.mpv.get("pause"):
            self._overlay(1, None)

    def toast(self, text: str, seconds: float = 1.6) -> None:
        self._overlay(3, player_ui.toast_ass(text))
        if self._toast_timer:
            self._toast_timer.cancel()
        self._toast_timer = threading.Timer(seconds, lambda: self._overlay(3, None))
        self._toast_timer.daemon = True
        self._toast_timer.start()

    def open_menu(self, kind: str) -> None:
        tracks = self.mpv.get("track-list") or []
        extra = []
        if kind == "sub" and self._fallback_subs and self._subs_lang:
            extra.append({"label": f"Buscar subtítulos en {player_ui.language(self._subs_lang).lower()}…",
                          "action": ("fetch", self._subs_lang), "current": False})
        self.menu = player_ui.track_menu(kind, tracks, extra)
        self._overlay(1, None)
        self._overlay(2, player_ui.menu_ass(self.menu))

    def close_menu(self) -> None:
        self.menu = None
        self._overlay(2, None)

    def _choose(self, option: dict) -> None:
        prop, value = option["action"]
        self.close_menu()
        if prop == "fetch":
            self.toast("Buscando subtítulos…", 3)
            threading.Thread(target=self._fetch_subs, args=(value,), daemon=True).start()
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

    def press(self, button: str) -> None:
        """Un botón del mando con el reproductor al frente."""
        if self.menu is not None:
            menu = self.menu
            if button in ("up", "down"):
                menu.index = max(0, min(len(menu.options) - 1, menu.index + (-1 if button == "up" else 1)))
                self._overlay(2, player_ui.menu_ass(menu))
            elif button == "a" and menu.options:
                self._choose(menu.options[menu.index])
            elif button == "b":
                self.close_menu()
            elif button in ("x", "y"):
                kind = "audio" if button == "x" else "sub"
                if kind == menu.kind:
                    self.close_menu()
                else:
                    self.open_menu(kind)
            return
        if button == "a":
            self.mpv.command("cycle", "pause")
            self.show_hud()
        elif button == "b":
            self.mpv.command("quit")
        elif button in ("x", "y"):
            self.open_menu("audio" if button == "x" else "sub")
        elif button in SEEK:
            self.mpv.command("seek", SEEK[button], "relative")
            self.show_hud()
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
            self.mpv.command("quit")
            try:
                self.current.process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                self.current.process.kill()

    @property
    def playing(self) -> bool:
        return self.current is not None and self.current.process.poll() is None
