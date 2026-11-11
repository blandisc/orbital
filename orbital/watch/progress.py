"""El avance: dónde te quedaste, las elecciones que se recuerdan y guardar el progreso."""

from __future__ import annotations

import logging
import time

from ..library import cinemeta, stremio_api
from ..library import subtitles as subtitle_lib
from ..scrobble import not_the_video
from .base import STREMIO_KEY
from .items import expired_session
from .sources import _Sources

log = logging.getLogger("orbital.watch")  # el mismo nombre de siempre: los avisos y la bitácora no cambian


class _Progress(_Sources):
    """El avance: dónde te quedaste, las elecciones que se recuerdan y guardar el progreso."""

    def _player_finished(self, meta: dict, position: float, duration: float, watched: float) -> None:
        self._save_progress(meta, position, duration, watched, refresh=True)

    def _subtitle_search(self, meta: dict, url: str | None) -> list[dict] | None:
        """Los subtítulos de internet de lo que ves (todos los idiomas), con la huella del archivo si el servidor la da (dos
        pedidos de 64 KB): los de tu copia exacta salen primero. None si nadie contestó."""
        kind = "series" if meta.get("kind") == "series" else "movie"
        if not meta.get("video_id"):
            return None
        cache = self.__dict__.setdefault("_fingerprints", {})
        if url and url not in cache:
            cache[url] = subtitle_lib.remote_fingerprint(url)
        return self.streams.subtitle_options(kind, meta["video_id"], cache.get(url) if url else None)

    def _remember_sub_release(self, meta: dict, release: str | None) -> None:
        """«Este va bien» en una serie: la copia de ese subtítulo («…-NTb»). En los siguientes episodios, los subtítulos
        del mismo grupo van primero."""
        if meta.get("meta_id") and release:
            self.state.set_pref(f"stremio:{meta['meta_id']}", "sub_release", release)

    def _safe_remember(self, meta: dict) -> None:
        try:
            self._remember_choice(meta)
        except Exception:  # noqa: BLE001 - recordar la fuente nunca tumba el guardado del avance
            log.exception("No pude recordar la fuente y los subtítulos")

    def resume_choice(self, meta_id: str, video_id: str) -> dict | None:
        """Con qué fuente y qué subtítulos dejaste ese video (para «Continuar»), o None."""
        saved = self.state.prefs(f"stremio:{meta_id}").get("resume")
        return saved if isinstance(saved, dict) and saved.get("video_id") == video_id else None

    def _remember_choice(self, meta: dict) -> None:
        """Junto a «dónde ibas»: la fuente (su huella) y la pista de subtítulos que tenías."""
        if not meta.get("meta_id") or not meta.get("video_id") or meta.get("live"):
            return
        choice = {"video_id": meta["video_id"], "source": meta.get("source_key"), "sub": self.player.current_subtitle(),
                  "audio": self.player.current_audio()}
        saved = self.state.prefs(f"stremio:{meta['meta_id']}").get("resume") or {}
        now = time.time()
        # Con su hora: en «Continuar» gana lo último que viste, aquí o en el iPhone, iPad o Mac (`apply_resume`). La hora se
        # renueva aunque no cambies nada (a lo más una vez por minuto): lo último visto aquí sigue siendo lo más reciente.
        if choice != {k: v for k, v in saved.items() if k != "at"} or now - float(saved.get("at") or 0) >= 50:
            self.state.set_pref(f"stremio:{meta['meta_id']}", "resume", {**choice, "at": now})

    def apply_resume(self, meta_id: str, choice: dict) -> bool:
        """Lo que tenías puesto en otro aparato (iPhone, iPad, Mac) al guardar tu avance: se queda si es más reciente que lo
        de aquí, para que «Continuar» en la TV siga con esa fuente, ese audio y esos subtítulos. False si lo de aquí es más nuevo."""
        saved = self.state.prefs(f"stremio:{meta_id}").get("resume") or {}
        if float(saved.get("at") or 0) >= float(choice.get("at") or 0):
            return False
        self.state.set_pref(f"stremio:{meta_id}", "resume", choice)
        return True

    def resumes_for(self, meta_ids: list[str]) -> dict:
        """«Continuar» en otro aparato: lo que recuerda la TV de cada título (fuente, audio, subtítulos y su hora)."""
        out = {}
        for meta_id in meta_ids:
            saved = self.state.prefs(f"stremio:{meta_id}").get("resume")
            if isinstance(saved, dict) and saved.get("video_id"):
                out[meta_id] = saved
        return out

    def _save_progress(self, meta: dict, position: float, duration: float, watched: float, refresh: bool) -> None:
        """Guarda en tu cuenta de Stremio dónde te quedaste (Seguir viendo, en Orbital y en Stremio).
        Se llama cada minuto, al pausar y al terminar; `watched` son los segundos vistos desde la vez anterior."""
        if not_the_video(meta, duration):  # un relleno de 30 s no «termina» una película de dos horas
            log.info("No guardo avance de %s: el video dura %d s (no es el título)", meta.get("video_id"), duration)
            return
        if position >= 60:  # con qué fuente y subtítulos lo dejaste (para «Continuar»)
            self._safe_remember(meta)
        auth = self.credentials.get(STREMIO_KEY)
        if not auth or (refresh and watched < 20 and position < 60):
            return  # se abrió y cerró sin ver nada: no se toca tu biblioteca
        # Uno a la vez: un guardado de cada minuto que tarda no pisa al final con una posición vieja.
        with self._saving:
            self._save_progress_now(auth, meta, position, duration, watched, refresh)

    def _save_progress_now(self, auth: str, meta: dict, position: float, duration: float, watched: float,
                           refresh: bool) -> None:
        kind, meta_id, video_id = meta["kind"], meta["meta_id"], meta["video_id"]
        try:
            info = self.cinemeta.meta(kind, meta_id, localized=False)  # Stremio guarda el título original
        except cinemeta.CinemetaError:
            info = {}
        next_video = cinemeta.next_episode(info, video_id) if kind == "series" and info else None
        try:
            raw = self.stremio_client.library_item(auth, meta_id)
            item = stremio_api.with_progress(
                raw, meta_id=meta_id, kind=kind, name=info.get("name") or meta.get("title") or meta_id,
                poster=info.get("poster"), video_id=video_id, position=position, duration=duration,
                watched=watched, next_video=next_video, now=time.time(),
                video_ids=[v["id"] for v in info.get("videos") or [] if isinstance(v, dict) and v.get("id")])
            if not self.setting("stremio_copy", True):
                return
            self.stremio_client.save_library_item(auth, item)
            log.info("Progreso guardado en Stremio: %s %d/%d s", video_id, position, duration)
        except stremio_api.StremioError as exc:
            log.warning("No pude guardar el progreso en Stremio: %s", exc)
            if expired_session(exc):
                self.events.publish({"type": "toast", "ok": False,
                                     "message": "Tu sesión de Stremio caducó: vuelve a conectarla en Ajustes › Cuentas"})
        if refresh:
            self.refresh_stremio(background=True)
