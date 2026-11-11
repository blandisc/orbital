"""La ficha de un título, su arte, Mi lista y el tráiler."""

from __future__ import annotations

import logging
import threading
import time

from .. import player, ytdlp
from ..library import cinemeta, stremio_api
from ..library import tmdb as tmdb_api
from ..library import trakt as trakt_api
from .base import STREMIO_KEY
from .items import trailer_id
from .playback import _Playback

log = logging.getLogger("orbital.watch")  # el mismo nombre de siempre: los avisos y la bitácora no cambian


class _Details(_Playback):
    """La ficha de un título, su arte, Mi lista y el tráiler."""

    def title_details(self, kind: str, meta_id: str) -> dict:
        """Todo para la ficha: datos, reparto, temporadas y dónde ibas (para "Continuar T3 E5")."""
        info = self.cinemeta.meta(kind, meta_id)
        chosen = self.art_for(meta_id)  # «Cambiar el arte»
        details = {"id": meta_id, "kind": kind, "title": info.get("name") or "", "poster": chosen.get("poster") or info.get("poster"),
                   "background": chosen.get("background") or info.get("background") or None, **cinemeta.describe_meta(info),
                   **cinemeta.credits(info)}
        if kind == "series":
            details["seasons"] = cinemeta.seasons(info)
        resume = None
        stremio_when = None
        details["watched"] = []
        details["in_library"] = False
        auth = self.credentials.get(STREMIO_KEY)
        if auth:
            try:
                raw = self.stremio_client.library_item(auth, meta_id)
            except stremio_api.StremioError as exc:
                log.info("No pude leer dónde ibas en %s: %s", meta_id, exc)
                raw = None
            raw = raw if isinstance(raw, dict) else None
            state = stremio_api.state_of(raw)
            stremio_when = stremio_api.watched_at(raw)
            details["in_library"] = bool(raw) and not raw.get("removed") and not raw.get("temp")
            if kind == "series":  # los vistos de verdad (no "todo lo anterior al que ibas")
                ids = [v["id"] for v in info.get("videos") or [] if isinstance(v, dict) and v.get("id")]
                details["watched"] = sorted(stremio_api.parse_watched(state.get("watched"), ids))
            video_id = state.get("video_id") if isinstance(state.get("video_id"), str) else None
            if video_id:
                position = stremio_api.resume_seconds(raw, video_id)
                duration = stremio_api.as_int(state.get("duration")) / 1000
                label, name = self._episode_label(info, video_id) if kind == "series" else ("", "")
                if position or (kind == "series" and video_id != meta_id):
                    resume = {"video_id": video_id, "position": position, "duration": duration,
                              "label": label, "episode_title": name}
        details["resume"] = self._trakt_title(details, info, kind, meta_id, stremio_when, resume)
        video = trailer_id(info)
        details["trailer"] = video if video and self.trailer_available(video) else None  # «Tráiler» solo si se puede ver
        return details

    def _trakt_title(self, details: dict, info: dict, kind: str, meta_id: str, stremio_when: float | None,
                     resume: dict | None) -> dict | None:
        """La ficha con lo de Trakt (lo que viste o pausaste en el iPhone): Mi lista es tu watchlist, los ✓ se suman y
        «Continuar» va a lo más reciente entre Stremio y Trakt. Devuelve el «Continuar» que queda."""
        if not self.trakt_library.active:
            return resume
        listed = self.trakt_library.in_watchlist(meta_id)
        if listed is not None:
            details["in_library"] = listed
        best: tuple[float, dict] | None = None
        playback, _, movies, _ = self.trakt_library.snapshot()
        if kind == "movie":  # el botón de estado de la ficha (G1-A): «Vista»
            details["seen"] = meta_id in movies
        for row in playback:
            if row["meta_id"] == meta_id and (best is None or row["paused_at"] > best[0]):
                length = row.get("runtime") or 0
                best = (row["paused_at"], {"video_id": row["video_id"], "position": row["percent"] / 100 * length,
                                           "duration": length})
        if kind == "series":
            try:
                watched, nxt = self.trakt_library.watched_episodes(meta_id)
            except trakt_api.TraktError as exc:
                log.info("No pude leer qué episodios viste en Trakt: %s", exc)
                watched, nxt = set(), None
            ids = {v["id"] for v in info.get("videos") or [] if isinstance(v, dict) and v.get("id")}
            details["watched"] = sorted(set(details["watched"]) | (watched & ids))
            if nxt and nxt[0] in ids and (best is None or nxt[1] > best[0]):
                best = (nxt[1], {"video_id": nxt[0], "position": 0, "duration": 0})
        if best is None or (stremio_when is not None and stremio_when >= best[0]):
            return resume
        found = best[1]
        if found["position"] < 1 and (kind != "series" or found["video_id"] == meta_id):
            return resume  # sin avance que sirva
        label, name = self._episode_label(info, found["video_id"]) if kind == "series" else ("", "")
        return {**found, "position": round(found["position"]), "label": label, "episode_title": name}

    # --- «Cambiar el arte» de una película o serie ---------------------------------------------------------------------
    ART_KINDS = ("poster", "background")

    def art_choices(self, kind: str, meta_id: str) -> dict:
        """Los pósters y fondos que se pueden elegir (de TMDB) y los que tiene ahora. LookupError en palabras si no hay."""
        tmdb = self.localizer.tmdb
        if not tmdb.configured:
            raise LookupError("Para elegir otro arte hace falta la clave de TMDB (Ajustes › Cuentas).")
        try:
            tmdb_id = tmdb.find_id(meta_id, kind)
            found = tmdb.images(kind, tmdb_id) if tmdb_id else {"posters": [], "backgrounds": []}
        except tmdb_api.TmdbError as exc:
            raise LookupError(str(exc)) from exc
        if not found["posters"] and not found["backgrounds"]:
            raise LookupError("TMDB no tiene otras imágenes de este título.")
        return {**found, "current": self.art_for(meta_id)}

    def art_for(self, meta_id: str | None) -> dict:
        """El arte que elegiste para ese título ({"poster", "background"}); {} si nunca lo cambiaste."""
        saved = self.state.prefs(f"stremio:{meta_id}").get("art") if meta_id else None
        return {k: v for k, v in (saved or {}).items() if k in self.ART_KINDS and isinstance(v, str) and v} if isinstance(saved, dict) else {}

    def set_art(self, meta_id: str, which: str, url: str | None) -> dict:
        """Recuerda el póster o el fondo elegido (`url` None: vuelve el de siempre). Devuelve el arte de ese título."""
        if which not in self.ART_KINDS:
            raise ValueError("Solo se cambia el póster o el fondo")
        if url is not None and not str(url).startswith(tmdb_api.IMAGES):
            raise ValueError("Esa imagen no es de TMDB")
        art = self.art_for(meta_id)
        if url:
            art[which] = url
        else:
            art.pop(which, None)
        self.state.set_pref(f"stremio:{meta_id}", "art", art or None)
        return art

    def set_in_library(self, kind: str, meta_id: str, add: bool) -> None:
        """Añadir o quitar de Mi lista: tu watchlist de Trakt (la del iPhone) y, mientras dura la prueba, una copia en tu
        biblioteca de Stremio. Sin Trakt, solo Stremio, como antes."""
        trakt = self.trakt_library.client()
        auth = self.credentials.get(STREMIO_KEY)
        if trakt is None and not auth:
            raise stremio_api.StremioError(stremio_api.NOT_LINKED)
        if trakt is not None:
            trakt.set_watchlist(kind, meta_id, add)  # TraktError: no se guardó en ningún lado (la API lo dice)
            self.trakt_library.forget("watchlist")
        if auth:
            try:
                try:
                    info = self.cinemeta.meta(kind, meta_id, localized=False)  # Stremio guarda el título original
                except cinemeta.CinemetaError:
                    info = {}
                raw = self.stremio_client.library_item(auth, meta_id)
                item = stremio_api.library_toggled(raw, meta_id=meta_id, kind=kind, name=info.get("name") or meta_id,
                                                   poster=info.get("poster"), add=add, now=time.time())
                self._save_stremio(auth, item)
            except stremio_api.StremioError as exc:
                if trakt is None:
                    raise
                log.info("Mi lista: la copia en Stremio no se guardó: %s", exc)  # la de Trakt sí: es la que cuenta
        # La biblioteca entera se vuelve a leer por detrás: la ficha ya cambió su botón (antes esperaba esta recarga,
        # varios segundos, y «Guardar» parecía trabado).
        def refresh() -> None:
            self.refresh_stremio()
            if trakt is not None:
                self.refresh_trakt()
            self.events.publish({"type": "library-changed"})
        threading.Thread(target=refresh, daemon=True, name="mi-lista").start()

    def play_trailer(self, kind: str, meta_id: str, keep: bool = False) -> bool:
        """El tráiler dentro de Orbital: el mismo mpv de las películas, que abre el video de YouTube con yt-dlp (en tu idioma
        si trae doblaje). Es un «clip»: no guarda avance, no avisa a Trakt, sin versiones ni episodios. Al terminar o con B
        se regresa a la ficha. Devuelve si Orbital sigue tapando hasta la primera imagen."""
        info = self.cinemeta.meta(kind, meta_id)
        video = trailer_id(info)
        if not video or not self.trailer_available(video):
            raise LookupError("Este título no tiene tráiler")
        try:
            url = ytdlp.watch_url(video)
        except ValueError:
            raise LookupError("Este título no tiene tráiler")
        mpv_exe = player.find_mpv()
        if not mpv_exe:
            raise LookupError("No encuentro mpv, el reproductor de Orbital. Instálalo desde Ajustes o revisa tu instalación.")
        try:
            ytdl = self.ytdlp.ensure()  # la primera vez lo baja (unos segundos)
        except ytdlp.YtDlpError as exc:
            raise LookupError(str(exc))
        title = f"{info.get('name') or 'Tráiler'} · Tráiler"
        current = self.player.segment
        if current is not None and current.meta.get("clip") == video and not current.failed and not current.closed                 and self.player.playing:
            log.info("El tráiler de %s ya está abierto: lo traigo al frente", title)
            self.sessions.revealing = self.sessions.to_front("media:player", title, ready=lambda: True)
            return self.sessions.revealing
        meta = {"kind": "trailer", "clip": video, "title": title, "detail": "Tráiler", "trailer_of": meta_id}
        if self.sessions.before_launch and not keep:
            self.sessions.before_launch("media:player")
        self._wire_player()
        pinned = self.sessions.pin()
        audio = self.stream_prefs.audio
        try:
            self.player.play(
                self.launcher.run, mpv_exe, url, title, meta, audio=audio, subtitles="", ytdl=ytdl,
                ytdl_format=ytdlp.video_format(audio), paused=True,  # empieza cuando se va la pantalla de carga
                started=lambda process: self.launcher.track("media:player", title, process, runner="Reproductor"))
        except BaseException:
            self.sessions.unpin(pinned)  # mpv no abrió: Orbital no se queda «siempre encima»
            raise
        # Resolver el video en YouTube tarda unos segundos: Orbital sigue tapando hasta la primera imagen.
        self.sessions.revealing = self.sessions.to_front("media:player", title, pinned=pinned, timeout=player.STARTUP_TIMEOUT + 5,
                                                         ready=lambda: bool(self.player.segment and self.player.segment.playing),
                                                         on_reveal=self.player.release_start)
        if not self.sessions.revealing:
            self.player.release_start()  # sin pantalla de carga que esperar (fuera de Windows): ya
        return self.sessions.revealing
