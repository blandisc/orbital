"""Reproducir: abrir una versión en mpv o mandarla al iPhone, y lo que pasa con el video abierto (otra versión,
episodios, subtítulos, pistas)."""

from __future__ import annotations

import logging
import re
import threading
import time
from dataclasses import replace

from .. import companion, flags, player, player_ui, remote_art
from ..library import cinemeta, streams, stremio_api
from ..library import trakt as trakt_api
from .base import STREMIO_KEY
from .progress import _Progress
from .versions import (
    FALLBACK_TRIES,
    fallback_source,
    give_up_words,
    handoff_pick,
    language_code,
    player_source_label,
    ready_now,
    source_label,
    spanish_variant,
    version_grid,
)

log = logging.getLogger("orbital.watch")  # el mismo nombre de siempre: los avisos y la bitácora no cambian


class _Playback(_Progress):
    """Reproducir en mpv o en el iPhone, y lo que pasa con el video abierto (otra versión, episodios, pistas)."""

    def play_own(self, kind: str, meta_id: str, video_id: str, title: str, file_id: str | None = None,
                 keep: bool = False, from_start: bool = False) -> dict:
        """Mi media: tu copia de OneDrive (la mejor versión, o la que elegiste). Si no abre, Real-Debrid en el mismo punto
        (el respaldo de siempre); el siguiente episodio también sale de tu carpeta si está."""
        source = self.onedrive.source(kind, video_id, file_id) if self.onedrive is not None else None
        mpv_exe = player.find_mpv()
        if source is None:
            raise LookupError("Eso ya no está en tu carpeta de OneDrive.")
        if not mpv_exe:
            raise LookupError("Falta el reproductor de Orbital (mpv) para ver tu copia.")
        url = self.onedrive.stream_url(source) if self.onedrive is not None else None
        if not url:
            raise LookupError("OneDrive no me dio el archivo. Inténtalo de nuevo.")
        prefs, subtitles = self.language_for(meta_id)
        self.play_native(mpv_exe, url, kind, meta_id, video_id, title, keep=keep, source=source, from_start=from_start,
                         audio=prefs.audio, subtitles=subtitles, own=True)
        return {"source": source.public(), "label": f"Tu copia · {source.resolution}" if source.resolution else "Tu copia en OneDrive"}

    def _wire_player(self) -> None:
        """Lo que el reproductor le pregunta al catálogo (siguiente episodio, otras fuentes…)."""
        p = self.player
        p.on_progress = lambda meta, pos, dur, watched: self._save_progress(meta, pos, dur, watched, refresh=False)
        p.on_scrobble = self.scrobbler.event
        p.on_channel = self._channel_seen
        p.on_failed = self._source_failed
        p.next_provider = self._next_up
        p.still_provider = self._episode_still
        p.sources_provider = self._player_sources
        p.on_switch_source = self._switch_source
        p.on_episode = self._step_episode
        p.episodes_provider = self._season_episodes
        p.on_play_episode = self._jump_episode
        p.on_sub_scale = lambda scale: self.state.set_setting("sub_scale", scale)
        p.iphone_provider = lambda: companion.phone_ready(self.config)
        p.on_send_iphone = self._send_to_phone
        p.idle_seconds = int(self.setting("video_idle_minutes", self.config.sessions.video_idle_minutes)) * 60
        p.on_language = self._remember_language
        p.on_tracks = self._tracks_seen
        p.versions_provider = self._other_versions
        p.subtitle_search = self._subtitle_search  # «Probar otros»: los de internet con su copia y descargas
        p.good_release = lambda meta: self.state.prefs(f"stremio:{meta.get('meta_id')}").get("sub_release") if meta.get("meta_id") else None
        p.on_good_release = self._remember_sub_release
        p.on_sub_kept = self._safe_remember  # «Probar otros» › «Este va bien»: esos subtítulos (y su sincronía), ya
        p.spanish_provider = self._spanish_for
        p.pip_on_home = self.setting("video_home", "pip") == "pip"  # la barra dice «Home · Ver en pequeño»
        p.sub_scale = float(self.setting("sub_scale", 1.0) or 1.0)
        player_ui.set_text_size(self.setting("text_size", "normal"))  # la letra del reproductor sigue a Ajustes

    def _channel_seen(self, meta: dict, position: float, duration: float, watched: float, finished: bool) -> None:
        """V2: un episodio de un canal de Orbital. A medias, sale en Seguir viendo (sin tocar Trakt ni Stremio); terminado,
        queda visto en Trakt y Seguir viendo regresa a tu orden de antes (trakt_sync.ChannelDetours)."""
        imdb, video = meta.get("meta_id"), meta.get("video_id")
        store = self.trakt_library.channel
        if not imdb or not video or store is None or not self.trakt_library.active:
            return
        your_next = self.trakt_library.your_next(imdb)
        if finished:
            store.finished(imdb, video, time.time(), your_next)
            self.scrobbler.event("stop", {**meta, "kind": "series", "finished": True}, duration, duration)
        elif not store.progress(imdb, video, position, duration, watched, time.time(), your_next, title=meta.get("series") or ""):
            return  # zapear no cambia nada
        self._publish_videos()

    def _send_to_phone(self, meta: dict, action: str, position: float | None = None) -> str:
        """Y › «Seguir en el iPhone» (el mismo minuto) / «Enviar al iPhone» / «Descargar en el iPhone» con lo que se está
        viendo (el episodio en curso; el de un canal de Orbital, como episodio de su serie)."""
        kind = "series" if meta.get("synthetic") or meta.get("kind") == "channel" else meta.get("kind") or "movie"
        # «Seguir en el iPhone»: el mismo segundo, la misma fuente, el mismo audio y los mismos subtítulos.
        choice = {"source": meta.get("source_key"), "audio": self.player.current_audio(),
                  "subtitle": self.player.current_subtitle()} if action == "continue" else None
        sent = companion.send_to_phone(self, self.config, "open" if action == "continue" else action, kind,
                                       meta.get("meta_id") or "", meta.get("video_id"),
                                       position=position if action == "continue" else None, choice=choice)
        if action == "continue":
            minute = int((position or 0) // 60)
            return f"Abriendo en tu iPhone · {sent.get('episode_label') or sent.get('title') or ''} en el minuto {minute}".replace(" ·  en", " en")
        return companion.SENT_TOAST[action]

    def _media_meta(self, kind: str, meta_id: str, video_id: str, title: str, source: streams.Source) -> dict:
        """Lo que el reproductor necesita saber del video (y lo que se guarda en Stremio). En pausa
        muestra también los datos y la sinopsis (del episodio, si la hay; si no, de la serie)."""
        detail, facts, description, poster, upcoming = "", "", "", None, ""
        try:
            info = self.cinemeta.meta(kind, meta_id)
        except cinemeta.CinemetaError:
            info = None
        if info:
            poster = info.get("poster")
            about = cinemeta.describe_meta(info)
            facts = " · ".join(p for p in (about.get("year"), about.get("rating") and f"★ {about['rating']}",
                                           ", ".join((about.get("genres") or [])[:2])) if p)
            description = about.get("description") or ""
            if kind == "series":
                label, name = self._episode_label(info, video_id)
                detail = " · ".join(p for p in (label, name) if p)
                upcoming = self._next_label(info, video_id)
                episode = next((e for s in cinemeta.seasons(info) for e in s["episodes"] if e["id"] == video_id), None)
                description = (episode or {}).get("overview") or description
        return {"kind": kind, "meta_id": meta_id, "video_id": video_id, "title": title, "detail": detail,
                "facts": facts, "description": description, "poster": poster, "next": upcoming,
                "source": source.index, "source_label": source_label(source), "binge": source.binge,
                "source_key": source.key, "source_dub": source.dub, "tried": [source.index],
                # La copia que ves («…WEB-DL-NTb»): «Probar otros» pone primero los subtítulos hechos para ella.
                "release": str((source.stream.get("behaviorHints") or {}).get("filename") or source.release or "")}

    def play_best(self, kind: str, meta_id: str, video_id: str, title: str, keep: bool = False,
                  from_start: bool = False, handoff: dict | None = None) -> dict:
        """"Ver": sin lista de fuentes. Orbital elige la recomendada y arranca (la lista queda en Y). Si lo descargaste,
        tu descarga, del disco (arranca al instante y sin internet).
        `handoff`: lo que venía viendo el iPhone («Ver en la TV» desde su reproductor): {position, source, audio,
        subtitle}. Se sigue en ese segundo, con esa fuente (si la TV la tiene), ese audio y esos subtítulos."""
        handoff = handoff if handoff and not from_start else None
        start_at = handoff.get("position") if handoff else None
        pick = handoff_pick(handoff) if handoff else None
        if self.downloads is not None and self.downloads.file_for(video_id) \
                and self.play_downloaded(video_id, from_start=from_start, start_at=start_at, sub_pick=pick):
            return {"source": None, "label": "Tu descarga · sin internet"}
        prefs, subtitles = self.language_for(meta_id)
        resume = None if from_start else self.resume_choice(meta_id, video_id)
        if resume and isinstance(resume.get("audio"), dict):  # el audio con que lo dejaste en la TV
            resume = {**resume, "sub": {**(resume.get("sub") or {}), "audio": resume["audio"]}}
        if handoff:
            resume = {"video_id": video_id, "source": handoff.get("source"), "sub": pick}
            code = (handoff.get("audio") or {}).get("lang")
            audio = language_code(code)
            if audio:  # el idioma del audio del iPhone (con su variante): también para elegir fuente si la suya no está
                prefs = replace(prefs, audio=audio, spanish=spanish_variant(code) or (prefs.spanish if audio == "es" else ""))
            sub = handoff.get("subtitle") or {}
            if sub.get("off"):
                subtitles = ""
            elif language_code(sub.get("lang")):
                subtitles = language_code(sub.get("lang")) or subtitles
        source = self.choose_source(kind, video_id, prefs, resume)
        if source is None:
            raise LookupError(self.no_sources_message(kind, video_id))
        self.play_source(kind, meta_id, video_id, source.index, title, keep=keep, from_start=from_start,
                         prefs=prefs, subtitles=subtitles, sub_pick=(resume or {}).get("sub"), start_at=start_at)
        return {"source": source.public(), "label": source_label(source)}

    def play_source(self, kind: str, meta_id: str, video_id: str, index: int, title: str, keep: bool = False,
                    from_start: bool = False, prefs: streams.Preferences | None = None,
                    subtitles: str | None = None, sub_pick: dict | None = None, start_at: float | None = None,
                    asked: dict | None = None) -> str:
        """Reproduce la fuente elegida: en el reproductor de Orbital (mpv, con el mando) o, si no
        está o así se configuró, directo en el de Stremio (sin su lista de fuentes).
        `prefs`/`subtitles`: idioma pedido para esta vez ("…en español"); si no, el de Ajustes. `asked`: lo pedido por voz
        para esta vez (audio, doblaje, subtítulos), que siguen el respaldo, otra versión y el siguiente episodio."""
        self.sessions.revealing = False
        saved_prefs, saved_subs = self.language_for(meta_id)
        prefs = prefs or saved_prefs
        subtitles = saved_subs if subtitles is None else subtitles
        from ..onedrive_library import INDEX as ONEDRIVE_INDEX

        source = self.onedrive.source(kind, video_id) if index == ONEDRIVE_INDEX and self.onedrive is not None \
            else self.streams.get(kind, video_id, prefs, index)
        if source is None:  # la lista caducó o se pidió con otro idioma: se vuelve a buscar una vez
            self.stream_sources(kind, video_id, prefs)
            source = self.streams.get(kind, video_id, prefs, index)
        if source is None:
            raise ValueError("Esa versión ya no está disponible; vuelve a abrir la lista")
        mpv_exe = player.find_mpv() if self.config.stremio.player == "orbital" else None
        # «Tu OneDrive»: Microsoft da una dirección temporal del archivo (se pide al momento de ver).
        url = self.onedrive.stream_url(source) if source.stream.get("onedrive") and self.onedrive is not None \
            else player.stream_url(source.stream)
        if source.stream.get("onedrive") and not mpv_exe:
            mpv_exe = player.find_mpv()  # Stremio no sabe abrir tu OneDrive: siempre el reproductor de Orbital
        if mpv_exe and url:
            self.play_native(mpv_exe, url, kind, meta_id, video_id, title, keep=keep, source=source,
                             from_start=from_start, audio=prefs.audio, subtitles=subtitles, sub_pick=sub_pick,
                             start_at=start_at, asked=asked)
            return "orbital"
        uri = streams.player_link(source, cinemeta.MANIFEST, kind, meta_id, video_id)
        self.sessions.open_stremio(uri, title)
        return uri

    def download_url(self, job: dict) -> tuple[str, str]:
        """Para Descargas: la dirección del archivo que se va a bajar (tu OneDrive; si no, una directa de 1080p)."""
        from ..downloads import pick_source

        prefs = self.language_for(job["meta_id"])[0]
        # Tu copia de OneDrive primero (la de 1080p si la hay, como el iPhone); si no, Real-Debrid.
        mine = self.onedrive.versions(job["kind"], job["video_id"]) if self.onedrive is not None else []
        if mine:
            pick = next((v for v in mine if v["resolution"] == "1080p"), mine[0])
            source = self.onedrive.source(job["kind"], job["video_id"], pick["id"]) if self.onedrive is not None else None
            if source is not None:
                job["quality"] = source.resolution or None
                return self.onedrive.stream_url(source) or "", source.release
        source = pick_source(self.stream_sources(job["kind"], job["video_id"], prefs), prefs.audio)
        if source is None:
            return "", ""
        job["quality"] = source.resolution or None
        if source.stream.get("onedrive") and self.onedrive is not None:
            return self.onedrive.stream_url(source) or "", source.release
        return player.stream_url(source.stream) or "", source.release

    def play_downloaded(self, video_id: str, from_start: bool = False, start_at: float | None = None,
                        sub_pick: dict | None = None) -> bool:
        """Lo que bajaste, directo del disco (sin internet). False si no está descargado."""
        if self.downloads is None:
            return False
        job = self.downloads.find(video_id)
        path = self.downloads.file_for(video_id) if job else None
        mpv_exe = player.find_mpv()
        if job is None or not path or not mpv_exe:
            return False
        title = job.get("title") or "Video"
        self.play_native(mpv_exe, str(path), job["kind"], job["meta_id"], video_id, title, from_start=from_start,
                         start_at=start_at, sub_pick=sub_pick)
        return True

    def resume_position(self, meta_id: str, video_id: str) -> float:
        """Dónde ibas: lo más reciente entre Stremio y Trakt (lo que pausaste en el iPhone o en otra app), como el
        iPhone. Sin Trakt, lo de Stremio. 0 si no se sabe."""
        seconds, when, duration = 0.0, None, None
        try:
            raw = self.stremio_client.library_item(self.credentials.get(STREMIO_KEY) or "", meta_id)
            seconds = stremio_api.resume_seconds(raw, video_id)
            state = stremio_api.state_of(raw)
            if state.get("video_id") == video_id:  # su fecha y su duración solo cuentan si son de este mismo video
                when = stremio_api.watched_at(raw)
                duration = stremio_api.as_int(state.get("duration")) / 1000 or None
        except (stremio_api.StremioError, ValueError, TypeError, AttributeError, OverflowError) as exc:
            log.info("No pude leer dónde ibas en Stremio: %s", exc)
        trakt = self._trakt_playback(meta_id, video_id)
        start = trakt_api.latest_resume(seconds, when, duration, trakt)
        store = getattr(getattr(self, "trakt_library", None), "channel", None)
        channel = store.position(meta_id, video_id) if store else None
        if channel and start < 1:  # V2: lo dejaste a medias en un canal (ni Stremio ni Trakt lo saben)
            log.info("Sigo donde lo dejaste en el canal: %.0f s", channel[0])
            return channel[0]
        if trakt and start != seconds:
            log.info("Sigo donde dice Trakt (%.0f %%): %.0f s (Stremio: %.0f s)", trakt["percent"], start, seconds)
        return start

    def _trakt_playback(self, meta_id: str, video_id: str) -> dict | None:
        """El avance de Trakt de ese video (None sin Trakt conectado, sin internet o si no hay)."""
        try:
            trakt = self.scrobbler.trakt()
            kind = "series" if ":" in str(video_id or "") else "movie"
            key = trakt_api.playback_key(kind, meta_id, video_id)
            if trakt is None or not trakt.linked or key is None:
                return None
            return trakt.playback().get(key)
        except Exception as exc:  # noqa: BLE001 - TraktError, sin internet…: se sigue con Stremio
            log.info("No pude leer el avance de Trakt: %s", exc)
            return None

    def _fallback_subs(self, kind: str, video_id: str, subs: str | None = None):
        subs = self.subtitles_lang if subs is None else subs
        if subs == "forced":
            return None  # solo los forzados que trae el video: no se buscan subtítulos completos
        return (lambda: self.streams.subtitles(kind, video_id, subs)) if subs else None

    def play_native(self, mpv_exe: str, url: str, kind: str, meta_id: str, video_id: str, title: str,
                    keep: bool = False, source: streams.Source | None = None, from_start: bool = False,
                    audio: str | None = None, subtitles: str | None = None, sub_pick: dict | None = None,
                    own: bool = False, start_at: float | None = None, asked: dict | None = None) -> None:
        """mpv a pantalla completa, desde donde te quedaste (según Stremio); con `start_at`, desde ese segundo (el que
        venía viendo el iPhone)."""
        if not from_start and self.player.starting(video_id, source.key if source else None):
            # Ya está cargando: Orbital sigue tapando hasta la primera imagen (el aviso del primer intento sigue en pie).
            log.info("%s ya se está abriendo: no lo empiezo otra vez", title)
            self.sessions.revealing = True
            return
        if not from_start and start_at is None and self.player.showing(video_id, source.key if source else None):
            # Ya se está viendo: vuelve al frente donde va (no se recarga desde lo último guardado).
            log.info("%s ya se está viendo: lo traigo al frente", title)
            if getattr(self.player, "pip", False):
                self.player.exit_pip()
            self.sessions.revealing = self.sessions.to_front("media:player", title, ready=lambda: True)
            return
        if from_start:
            start = 0.0
        elif isinstance(start_at, (int, float)) and start_at > 0:
            start = float(start_at)
        else:
            start = self.resume_position(meta_id, video_id)
        meta: dict = self._media_meta(kind, meta_id, video_id, title, source) if source else \
            {"kind": kind, "meta_id": meta_id, "video_id": video_id, "title": title}
        if own:
            meta["own"] = True  # desde Mi media: el siguiente episodio también de tu carpeta
        if asked:
            meta["asked"] = asked  # «pon Los Simpson en latino»: solo para esta vez (el título no lo recuerda)
        # Lo que estaba abierto se cierra justo antes de abrir el video, no antes de buscar sus datos por
        # internet (si algo fallaba, tu juego ya se había cerrado para nada).
        if self.sessions.before_launch and not keep:
            self.sessions.before_launch("media:player")
        self._wire_player()
        pinned = self.sessions.pin()
        try:
            # Vigilar el proceso en el mismo paso que lo abre: con dos «pon…» a la vez, el vigilante
            # del primero (ya cerrado) borraba al segundo.
            self.player.play(
                self.launcher.run, mpv_exe, url, title, meta,
                start=start, audio=audio or self.stream_prefs.audio,
                subtitles=self.subtitles_lang if subtitles is None else subtitles,
                fallback_subs=self._fallback_subs(kind, video_id, subtitles), sub_pick=None if from_start else sub_pick,
                started=lambda process: self.launcher.track("media:player", title, process, runner="Reproductor"))
        except BaseException:
            self.sessions.unpin(pinned)  # mpv no abrió: Orbital no se queda «siempre encima»
            raise
        # Hasta la primera imagen del video (cargar un stream tarda): antes se veía la ventana negra de mpv.
        self.sessions.revealing = self.sessions.to_front("media:player", title, pinned=pinned, timeout=player.STARTUP_TIMEOUT + 5,
                                        ready=lambda: bool(self.player.segment and self.player.segment.playing))

    def _load_in_player(self, kind: str, meta_id: str, video_id: str, title: str, source: streams.Source,
                        start: float = 0, message: str | None = None, tried: list[int] | None = None, own: bool = False,
                        back_to: int | None = None, asked: dict | None = None) -> bool:
        url = self._url_for(source)
        if not url:
            return False
        meta = self._media_meta(kind, meta_id, video_id, title, source)
        meta["tried"] = sorted(set(tried or []) | {source.index})
        if back_to is not None and back_to != source.index:
            meta["back_to"] = back_to  # si la que elegiste a mano no abre, de vuelta a esta
        if own:
            meta["own"] = True
        if asked:
            meta["asked"] = asked
        prefs, subtitles = self.asked_language(meta)  # el audio y los subtítulos que esta serie recuerda (o los de esta vez)
        return self.player.load(url, title, meta, start=start, message=message, subtitles=subtitles, audio=prefs.audio,
                                fallback_subs=self._fallback_subs(kind, video_id, subtitles))

    def _source_failed(self, meta: dict, position: float, alive: bool) -> bool:
        """Una fuente no arrancó o se cortó: la siguiente mejor, en el mismo punto. True si se intenta."""
        title = meta.get("title") or "esto"
        if meta.get("clip"):  # un tráiler no tiene otra versión
            self.events.publish({"type": "toast", "ok": False, "message": "No pude reproducir el tráiler", "detail": "Inténtalo otra vez"})
            return False
        back_to = meta.get("back_to")
        if alive and back_to is not None:
            # Cambiaste de versión a mano y esa no abrió: de vuelta a la que estabas viendo, en el mismo segundo (antes
            # brincaba a «otra fuente» que no habías elegido, y parecía que el cambio había fallado).
            previous = self._source_by_index(meta, back_to, self.language_for(meta["meta_id"])[0])
            if previous is not None:
                log.info("La versión elegida de %s no abrió: de vuelta a %s", title, source_label(previous))
                if self._load_in_player(meta["kind"], meta["meta_id"], meta["video_id"], title, previous, start=position,
                                        message="Esa versión no abrió · sigues con la de antes", tried=meta.get("tried")):
                    return True
        if alive and meta.get("source") is not None:
            tried = set(meta.get("tried") or [meta["source"]])
            prefs = self.asked_language(meta)[0]
            try:
                found = [s for s in self.stream_sources(meta["kind"], meta["video_id"], prefs) if s.index not in tried]
            except stremio_api.StremioError:
                found = []
            source = fallback_source(found, prefs.audio, self.native_player)
            if source is not None and len(tried) < FALLBACK_TRIES:
                other = prefs.audio not in source.languages  # otro idioma: se dice cuál
                log.info("Probando otra fuente para %s (%s%s)", title, source_label(source), ", otro idioma" if other else "")
                label = player_source_label(source) if other else source_label(source)
                ok = self._load_in_player(meta["kind"], meta["meta_id"], meta["video_id"], title, source, start=position,
                                          message=f"Probando {'en otro idioma' if other else 'otra versión'} · {label}",
                                          tried=list(tried), asked=meta.get("asked"))
                if ok:
                    return True
                tried.add(source.index)
                meta = {**meta, "tried": sorted(tried)}
                return self._source_failed(meta, position, alive)  # esa tampoco abrió: la siguiente
            message, detail = give_up_words(title, found, prefs.audio)
            self.events.publish({"type": "toast", "ok": False, "message": message, "detail": detail})
            self.player.toast(f"{message} · {detail}", 6)
            return False
        self.events.publish({"type": "toast", "ok": False,
                      "message": f"No pude reproducir {title}", "detail": "Prueba otra versión desde la ficha (Y)"})
        if alive:
            self.player.toast(f"No pude reproducir {title} · Prueba otra versión con Y", 6)
        return False

    def _title_facts(self, kind: str, video_id: str) -> dict | None:
        """Idioma original y nombres del título (TMDB, recordado un día; también el de Cinemeta) para las fuentes."""
        # «kitsu:1:1» es el episodio 1 de «kitsu:1» (antes se buscaba la ficha «kitsu», que no existe).
        parts = video_id.split(":")
        meta_id = ":".join(parts[:2]) if parts[0] == "kitsu" and len(parts) > 1 else parts[0]
        facts = dict(self.localizer.facts(kind, meta_id) or {})
        if parts[0] == "kitsu":
            facts.setdefault("original", "ja")  # Anime Kitsu: sin IMDb ni TMDB, su idioma original es japonés
        try:
            info = self.cinemeta.meta(kind, meta_id)
        except cinemeta.CinemetaError:
            info = {}
        name = info.get("name")
        if isinstance(name, str) and name:
            facts["titles"] = [*facts.get("titles", []), name]
        if not facts.get("original") and (from_country := streams.original_from_country(info.get("country"))):
            facts["original"] = from_country  # sin TMDB, el país de Cinemeta (como el iPhone)
        if kind == "series":  # «2003–2005»: una versión de otros años es otra serie (streams.other_years)
            facts["years"] = str(info.get("releaseInfo") or info.get("year") or "")
        year = re.match(r"(19|20)\d\d", str(info.get("year") or info.get("releaseInfo") or ""))
        if year:
            facts.setdefault("year", int(year.group()))  # una versión que dice otro año es otra película
        return facts

    def _tracks_seen(self, meta: dict, tracks: list[dict]) -> str | None:
        """El reproductor abrió una fuente y vio sus pistas: se recuerda (la próxima vez sale «Comprobado»); en español,
        se pone la pista del doblaje que prefieres si el archivo trae los dos; y, si no trae el idioma que querías, dice
        cuál trae y dónde está el tuyo. None: nada que avisar (o las pistas no dicen su idioma: no se sabe, no se avisa)."""
        key = meta.get("source_key")
        audio = [{"type": "audio", "lang": t.get("lang"), "title": t.get("title")} for t in tracks or []
                 if isinstance(t, dict) and t.get("type") == "audio"]
        langs = streams.track_languages(audio)
        if not key or not langs or not meta.get("meta_id"):
            return None
        self.heard.put(key, audio)
        prefs = self.asked_language(meta)[0]
        for src in self.streams.cached(meta.get("kind") or "", meta.get("video_id") or "", prefs):
            if src.key == key:
                streams.heard(src, audio)  # la lista ya buscada también lo sabe (X › Audio, Y › Versión)
        # La pista del doblaje (con dos «spa») la pone el reproductor (_pick_dub, con spanish_provider).
        wanted = self._wanted_codes(prefs)
        if set(langs) & wanted or (prefs.audio == "es" and "es" in langs):
            return None  # lo trae (o es español sin decir cuál: no se sabe, no se avisa)
        name = "español" if prefs.audio == "es" and not prefs.spanish else streams.LANG_NAMES.get(next(iter(wanted)), "").lower()
        names = [streams.LANG_NAMES.get(c, c).lower() for c in langs]
        if len(names) > 3:
            names = [*names[:3], f"{len(names) - 3} más"]
        has = " y ".join(filter(None, [", ".join(names[:-1]), names[-1]]))  # «inglés, francés y castellano»
        other = any(v["code"] in wanted for v in self._other_versions(meta))
        where = f"X › Audio: hay {name} en otra versión" if other else "Y › Versión para elegir otra"
        return f"Esta versión no trae {name}: sus pistas son {has} · {where}"

    @staticmethod
    def _wanted_codes(prefs: streams.Preferences) -> set[str]:
        """Los idiomas que te sirven: en español, el doblaje que prefieres (o cualquiera de los dos)."""
        if prefs.audio != "es":
            return {prefs.audio}
        return {prefs.spanish} & set(streams.SPANISH_VARIANTS) or {"es-419", "es-ES"}

    def _other_versions(self, meta: dict) -> list[dict]:
        """X › Audio en el reproductor: tu idioma (y los que no trae esta) en OTRA versión, la mejor de cada uno,
        de la lista ya buscada (sin ir a internet: el panel no puede esperar). Elegirla cambia de fuente donde ibas."""
        if meta.get("source") is None or not meta.get("kind") or not meta.get("video_id") or not meta.get("meta_id"):
            return []
        prefs = self.asked_language(meta)[0]
        found = self.streams.cached(meta["kind"], meta["video_id"], prefs)
        current = next((s for s in found if s.index == meta["source"]), None)
        have = set(current.audio_langs) if current else set()
        out, seen = [], set(have)
        for src in found:  # ya van de mejor a peor
            if src.doubtful or {"CAM", "Tráiler", "3D"} & set(src.tags):
                continue
            for code, how in src.audio_langs.items():
                if code in seen or how == "maybe":
                    continue
                seen.add(code)
                # Corto: la columna Audio es angosta (con cuatro columnas cabe «Castellano» + «En otra · 1080p», medido con
                # player_ui.text_width; «Latino · en otra versión» y «4K HDR · al instante» se cortaban).
                out.append({"id": src.index, "code": code, "label": streams.LANG_NAMES.get(code, code), "flag": flags.flag_for(code),
                            "hint": f"En otra · {src.resolution or 'SD'}"})
        wanted = self._wanted_codes(prefs)
        out.sort(key=lambda o: o["code"] not in wanted)  # tu idioma primero (en español sin preferencia, los dos)
        return out[:4]

    def _player_sources(self, meta: dict) -> list[dict]:
        """Y › Versión del reproductor: por idioma y calidad, como «Versión» de la ficha (version_rows)."""
        if meta.get("source") is None:
            return []
        prefs = self.asked_language(meta)[0]
        return version_grid(self.stream_sources(meta["kind"], meta["video_id"], prefs), prefs, meta["source"], self.rd.refused())

    def _source_by_index(self, meta: dict, index: int, prefs: streams.Preferences) -> streams.Source | None:
        """Una fuente por su número (estable entre búsquedas), de la lista ya buscada; si ya caducó (10 min: llevabas
        rato viendo), se busca otra vez. Antes, pasados 10 min, cambiar de versión decía «No pude cambiar de fuente»."""
        source = self.streams.get(meta["kind"], meta["video_id"], prefs, index)
        if source is None:
            try:
                found = self.stream_sources(meta["kind"], meta["video_id"], prefs)
            except stremio_api.StremioError:
                return None
            source = next((s for s in found if s.index == index), None)
        return source

    def _switch_source(self, meta: dict, index: int, position: float) -> bool:
        """False si no se pudo (el reproductor lo avisa). Una fuente de un solo idioma distinto (la de
        español en una serie que estaba en inglés): la serie lo recuerda para los siguientes episodios. Si la elegida
        no abre, se regresa a la que estabas viendo (back_to), en el mismo segundo."""
        prefs = self.asked_language(meta)[0]
        source = self._source_by_index(meta, index, prefs)
        if source is None:
            return False
        back_to = None if meta.get("own") else meta.get("source")
        ok = self._load_in_player(meta["kind"], meta["meta_id"], meta["video_id"], meta.get("title") or "",
                                  source, start=position, message=f"Cambiando a {source_label(source)}…", back_to=back_to,
                                  asked=meta.get("asked"))
        if ok and len(source.languages) == 1 and source.languages[0] != prefs.audio:
            self._remember_language(meta, "audio", source.languages[0])
        sure = [c for c in ("es-419", "es-ES") if streams.EVIDENCE[source.audio_langs.get(c, "maybe")] >= streams.EVIDENCE["original"]]
        if ok and len(sure) == 1 and meta.get("meta_id") and (prefs.audio == "es" or source.languages == ["es"]):
            self.state.set_pref(f"stremio:{meta['meta_id']}", "spanish", sure[0])  # pediste latino: la serie lo recuerda
        return ok

    def _next_up(self, meta: dict) -> dict | None:
        """Para la tarjeta "Siguiente episodio": cuál es y cómo ponerlo (la fuente se busca ya)."""
        info = self.cinemeta.meta("series", meta["meta_id"])
        next_id = cinemeta.next_episode(info, meta["video_id"])
        if next_id is None:
            return None
        title, detail = self._episode_title(info, meta["meta_id"], next_id)
        ready = True
        try:  # que al llegar el momento ya esté buscada, y saber si arranca ya (RD-4)
            found = self.stream_sources("series", next_id, self.asked_language(meta)[0])
            ready = any(ready_now(s) for s in found) or (not found and self.streams.outcome.get(f"series:{next_id}") == "offline")
        except stremio_api.StremioError:
            pass
        requested = False
        if not ready and not meta.get("own") and self.setting("rd_auto_request", True):
            try:  # RD-6: unos minutos antes del final, Real-Debrid ya lo está bajando
                requested = self.request_debrid("series", meta["meta_id"], next_id, title).get("state") in ("downloading", "ready")
            except LookupError as exc:
                log.info("No pedí el siguiente episodio a Real-Debrid: %s", exc)
        label, name = self._episode_label(info, next_id)
        still = next((e["thumbnail"] for s in cinemeta.seasons(info) for e in s["episodes"] if e["id"] == next_id), None)
        return {"label": label, "title": name, "still": still if remote_art.allowed(still or "") else None,
                "ready": ready or bool(meta.get("own")), "requested": requested,  # de tu carpeta de OneDrive arranca aunque Real-Debrid no lo tenga
                "request": lambda: self.request_debrid("series", meta["meta_id"], next_id, title),
                "play": lambda: self._play_episode(meta["meta_id"], next_id, title, meta.get("binge"), own=bool(meta.get("own")),
                                                   asked=meta.get("asked"))}

    @staticmethod
    def _episode_still(url: str, width: int) -> bytes | None:
        """El cuadro del episodio que sigue, del ancho en que se ve en la tarjeta (bajado una vez, como el arte de Orbital)."""
        path = remote_art.sized(url, width)
        return path.read_bytes() if path is not None else None

    def _play_episode(self, meta_id: str, video_id: str, title: str, binge: str | None = None,
                      start: float = 0, own: bool = False, asked: dict | None = None) -> bool | None:
        """Otro episodio en el mismo reproductor (sin volver a Orbital). False: no cargó; None: ya se avisó. Desde Mi
        media (`own`), de tu carpeta si está."""
        mine = self.onedrive.source("series", video_id) if own and self.onedrive is not None else None
        if mine is not None:
            return self._load_in_player("series", meta_id, video_id, title, mine, start=start, own=True, asked=asked)
        # El idioma que esta serie recuerda (antes: el de Ajustes, y el siguiente episodio salía en otro idioma); el pedido
        # por voz para esta vez sigue mientras no cierres el reproductor.
        prefs = self.asked_language({"meta_id": meta_id, "asked": asked})[0]
        source = self.best_source("series", video_id, binge, prefs=prefs)
        if source is None:
            self.player.toast("No encontré dónde ver ese episodio", 4)
            return None
        return self._load_in_player("series", meta_id, video_id, title, source, start=start, asked=asked)

    def _step_episode(self, meta: dict, delta: int) -> bool | None:
        """LT/RT en el reproductor: episodio anterior o siguiente."""
        info = self.cinemeta.meta("series", meta["meta_id"])
        episodes = [e["id"] for s in cinemeta.seasons(info) if s["season"] != 0 for e in s["episodes"]]
        if meta["video_id"] not in episodes:
            return
        i = episodes.index(meta["video_id"]) + delta
        if not 0 <= i < len(episodes):
            self.player.toast("No hay episodio " + ("anterior" if delta < 0 else "siguiente"), 2.5)
            return
        title, _ = self._episode_title(info, meta["meta_id"], episodes[i])
        return self._play_episode(meta["meta_id"], episodes[i], title, meta.get("binge"),
                                  start=self.resume_position(meta["meta_id"], episodes[i]), own=bool(meta.get("own")),
                                  asked=meta.get("asked"))

    def _season_episodes(self, meta: dict) -> list[dict]:
        """Y › Episodios en el reproductor: todas las temporadas (cada episodio con su `season`; el panel abre en la que
        ves y LB/RB las cambia), con el que ves y el que sigue marcados."""
        try:
            info = self.cinemeta.meta("series", meta["meta_id"])
        except cinemeta.CinemetaError:
            return []
        seasons = cinemeta.seasons(info)
        if not any(e["id"] == meta["video_id"] for s in seasons for e in s["episodes"]):
            return []
        upcoming = cinemeta.next_episode(info, meta["video_id"])
        return [{"id": e["id"], "label": f"E{e['episode']} · {e['title']}", "season": s["season"],
                 "current": e["id"] == meta["video_id"], "next": e["id"] == upcoming}
                for s in seasons for e in s["episodes"]]

    def _jump_episode(self, meta: dict, video_id: str) -> bool | None:
        """Elegir un episodio desde el reproductor: lo pone donde ibas (o desde el principio)."""
        info = self.cinemeta.meta("series", meta["meta_id"])
        title, _ = self._episode_title(info, meta["meta_id"], video_id)
        # None: _play_episode ya avisó (no hay fuente); False sí es «no pude» y lo avisa el reproductor.
        return self._play_episode(meta["meta_id"], video_id, title, meta.get("binge"),
                                  start=self.resume_position(meta["meta_id"], video_id), own=bool(meta.get("own")),
                                  asked=meta.get("asked"))

    def play_title(self, kind: str, meta_id: str, video_id: str, title: str, audio: str | None = None,
                   wait: float = 0.0, from_start: bool = False, spanish: str = "", subtitles: str | None = None,
                   remember: bool = False) -> str | None:
        """Para la voz: pone algo sin preguntar, con la fuente recomendada. Buscar fuentes tarda
        unos segundos (Alexa corta a los ~8 s), así que se hace en segundo plano.

        `wait`: segundos que se espera a saber si hay fuente, para que Alexa diga lo que pasó («No
        encontré dónde ver…») en vez de «Poniendo…» y luego un aviso que solo se ve en la pantalla.
        Devuelve el problema (texto) si ya se sabe, o None (se está poniendo, o sigue buscando).

        `audio`: idioma pedido ("…en español"; «es-419» / «es-ES» traen el doblaje). `spanish`: el doblaje («en
        latino»: "es-419"; «en castellano»: "es-ES"; "" cualquiera): la versión elegida y la pista que suena lo respetan.
        Si ninguna fuente trae el audio, se pone la mejor en tu idioma de siempre con subtítulos en el pedido, y se avisa.
        `subtitles`: «… con subtítulos en inglés» ("" sin subtítulos). Todo es solo para esta vez (el respaldo, otra
        versión y el siguiente episodio lo siguen mientras no cierres el reproductor); con `remember` («… siempre en
        latino») el título lo recuerda."""
        if audio and spanish_variant(audio):  # «es-419»: español latino
            spanish, audio = spanish or spanish_variant(audio), "es"
        spanish = spanish if audio == "es" and spanish in streams.SPANISH_VARIANTS else ""
        if not self.native_player:
            self.sessions.play_stremio(kind, meta_id, video_id, title)
            if remember:
                self.remember_title_language(meta_id, audio, spanish if audio else None, subtitles)
            return None
        searched = threading.Event()
        problem: list[str] = []
        # Sin idioma pedido: el que recuerda ese título (el mismo con el que se listan sus fuentes).
        prefs = self.language_for(meta_id)[0]
        if audio:
            prefs = replace(prefs, audio=audio, spanish=spanish or (prefs.spanish if audio == "es" else ""))
        asked_subs = subtitles

        def run() -> None:
            try:
                source = self.best_source(kind, video_id, prefs=prefs)
                if source is None:
                    message = self.no_sources_message(kind, video_id)
                    problem.append(message)
                    searched.set()
                    self.events.publish({"type": "toast", "message": message, "ok": False})
                    return
                searched.set()
                subs = None
                if audio and audio != self.stream_prefs.audio:
                    if audio in source.languages:
                        subs = ""  # lo pediste doblado: sin subtítulos encima
                    else:
                        subs = audio
                        name = {"es": "español", "en": "inglés"}.get(audio, audio)
                        self.events.publish({"type": "toast", "tone": "warn", "message": f"No hay audio en {name} para {title}",
                                             "detail": f"Va con subtítulos en {name}"})
                if spanish and audio in source.languages and streams.DUB_CODES.get(source.dub, spanish) != spanish:
                    wanted, got = ("latino", "castellano") if spanish == "es-419" else ("castellano", "latino")
                    self.events.publish({"type": "toast", "tone": "warn", "message": f"No hay versión en {wanted} para {title}",
                                         "detail": f"Va en {got}"})
                if asked_subs is not None:
                    subs = asked_subs  # «… con subtítulos en inglés»: lo dicho manda
                asked = {k: v for k, v in (("audio", audio or None), ("spanish", spanish or None), ("subtitles", subs))
                         if v is not None}
                self.play_source(kind, meta_id, video_id, source.index, title, prefs=prefs, subtitles=subs, from_start=from_start,
                                 asked=asked or None)
                if remember:  # «… siempre en latino»: el título lo recuerda (el siguiente episodio, «Ver», el iPhone…)
                    self.remember_title_language(meta_id, audio, spanish if audio else None, subs)
            except Exception as exc:  # noqa: BLE001 - se avisa en pantalla
                log.exception("No pude poner %s", title)
                message = f"No pude poner {title}: {exc}"
                problem.append(message)
                searched.set()
                self.events.publish({"type": "toast", "message": message, "ok": False})

        threading.Thread(target=run, daemon=True, name="play-title").start()
        if wait > 0:
            searched.wait(wait)
        return problem[0] if problem else None

    def play_next_episode(self) -> str | None:
        """El episodio que sigue al que se está viendo en el reproductor; None si no hay."""
        current = self.player.current if self.player.playing else None
        if current is None or current.meta.get("kind") != "series":
            return None
        meta_id = current.meta["meta_id"]
        info = self.cinemeta.meta("series", meta_id)
        next_id = cinemeta.next_episode(info, current.meta["video_id"])
        if next_id is None:
            return None
        title, _ = self._episode_title(info, meta_id, next_id)
        label, _ = self._episode_label(info, next_id)
        threading.Thread(target=self._play_episode, args=(meta_id, next_id, title, current.meta.get("binge")),
                         daemon=True, name="next-episode").start()
        return label or "el siguiente episodio"

    def play_episode_number(self, episode: int, season: int | None = None) -> str | None:
        """«Pon el capítulo 5»: de la serie que se ve (en su temporada si no se dice otra). None: no se ve
        una serie; "": no existe ese episodio."""
        current = self.player.current if self.player.playing else None
        if current is None or current.meta.get("kind") != "series":
            return None
        meta_id = current.meta["meta_id"]
        info = self.cinemeta.meta("series", meta_id)
        videos = [v for v in info.get("videos") or [] if isinstance(v, dict) and v.get("id")]
        if season is None:
            now = next((v for v in videos if v["id"] == current.meta.get("video_id")), None)
            season = now.get("season") if now else 1
        video = next((v for v in videos if v.get("season") == season and v.get("episode") == episode), None)
        if video is None:
            return ""
        title, _ = self._episode_title(info, meta_id, video["id"])
        label, _ = self._episode_label(info, video["id"])
        threading.Thread(target=self._play_episode, args=(meta_id, video["id"], title, current.meta.get("binge")),
                         kwargs={"start": self.resume_position(meta_id, video["id"])}, daemon=True,
                         name="episode-number").start()
        return label or f"el episodio {episode}"

    def play_previous_episode(self) -> str | None:
        """El episodio anterior al que se está viendo; None si no hay (o no es una serie)."""
        current = self.player.current if self.player.playing else None
        if current is None or current.meta.get("kind") != "series":
            return None
        meta_id = current.meta["meta_id"]
        info = self.cinemeta.meta("series", meta_id)
        episodes = [e["id"] for s in cinemeta.seasons(info) if s["season"] != 0 for e in s["episodes"]]
        if current.meta.get("video_id") not in episodes:
            return None
        i = episodes.index(current.meta["video_id"])
        if i == 0:
            return None
        label, _ = self._episode_label(info, episodes[i - 1])
        threading.Thread(target=self._step_episode, args=(current.meta, -1), daemon=True, name="prev-episode").start()
        return label or "el episodio anterior"

    def player_subtitles(self, lang: str) -> bool:
        """Subtítulos en ese idioma: los del video o, si no trae, los de tus addons."""
        if self.player.select_language("sub", lang):
            return True
        current = self.player.current
        if current is None or not self.has_addons:
            return False
        urls = self.streams.subtitles(current.meta["kind"], current.meta["video_id"], lang)
        if urls:
            self.player.add_subtitles(urls[0], lang)
        return bool(urls)
