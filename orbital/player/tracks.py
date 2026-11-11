"""Audio y subtítulos, pausa, buscar, detener y qué se está viendo."""

from __future__ import annotations

import math
import subprocess
from urllib.parse import quote

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
from .base import log
from .upnext import _UpNext


class _Tracks(_UpNext):
    """Audio, subtítulos, pausa, buscar y qué se ve."""

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
            if url.startswith(("http://", "https://", opensubtitles.SCHEME)):
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
        """A un punto exacto (voz: «desde el principio», «ve al minuto 20»; el iPhone, al soltar su barra)."""
        target = max(0.0, seconds)
        self.mpv.command("seek", target, "absolute")
        self._ask("time-pos", target)  # lo que contesta now_playing ya es el punto nuevo (ver abajo)
        self.show_hud(position=target)

    def seek(self, seconds: float) -> None:
        """Adelantar o regresar (el iPhone: ±10 s). Antes el iPhone recibía el minuto de antes del salto (la TV lo anota una
        vez por segundo) y parecía que el botón no hacía nada."""
        self.show_hud(position=self._expected_position(seconds))
        self.mpv.command("seek", seconds, "relative")

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
        from ..companion import episode_numbers  # aquí: companion no se carga con el reproductor
        label = (meta.get("detail") or "").split(" · ", 1)[0]
        parts = label.split()
        episode_label = f"{parts[0]} · {parts[1]}" if len(parts) == 2 else ""
        return {"kind": meta.get("kind") or "movie", "live": False, "meta_id": meta.get("meta_id"),
                "video_id": meta.get("video_id"), "title": meta.get("title") or current.title,
                "episode_label": episode_label, "poster": meta.get("poster"),
                **episode_numbers(meta.get("video_id") if meta.get("kind") == "series" else None),
                "position": self._reported_position(segment), "duration": segment.duration,
                "paused": bool(self._value("pause"))}

    def _reported_position(self, segment: Segment) -> float:
        """Dónde va, contando un salto recién pedido (mpv lo confirma un instante después)."""
        want = self._value("time-pos")
        return float(want) if isinstance(want, (int, float)) and not isinstance(want, bool) else segment.position
