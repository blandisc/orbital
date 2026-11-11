"""Tus idiomas y las fuentes de un video: buscarlas, la disponibilidad y la que se elige."""

from __future__ import annotations

import logging
import time
from dataclasses import replace

from .. import player, rd_requests
from ..library import cinemeta, realdebrid, streams, stremio_api, torrentio
from .accounts import _Accounts
from .base import DEBRID_CAUSES
from .versions import choice_line, language_code, player_ui_day, ready_now, spanish_variant

log = logging.getLogger("orbital.watch")  # el mismo nombre de siempre: los avisos y la bitácora no cambian


class _Sources(_Accounts):
    """Tus idiomas y las fuentes de un video: buscarlas, la disponibilidad y la que se elige."""

    @property
    def languages(self) -> list[str]:
        """Ajustes › Tus idiomas (N4-A): lo guardado o, si nunca la tocaste, la que sale de tu «Idioma» de antes."""
        langs = self.setting("languages")
        if streams.valid_languages(langs):
            return list(langs)
        return list(streams.languages_from_audio(str(self.setting("audio", self.config.stremio.audio) or "en")))

    def set_languages(self, langs: list[str]) -> None:
        """Guarda tu orden y lo lleva a donde se usa (N4-A: la única fuente): el «Idioma» de antes (lo que todavía lo lee),
        los «Idiomas primero» de Torrentio y las búsquedas ya hechas (se vuelven a ordenar)."""
        if not streams.valid_languages(langs):
            raise ValueError("Ese orden de idiomas no sirve")
        self.state.set_setting("languages", list(langs))
        if langs[0] in ("en", "es-419", "es-ES"):
            self.state.set_setting("audio", langs[0])
        codes = {v: k for k, v in torrentio.LANGUAGES.items()}
        wanted = [codes[c] for c in langs if c in codes]
        options = dict(self.addon_list.torrentio().options or {})
        if options.get("language") != wanted:
            self.set_torrentio({**options, "language": wanted})
        self.streams.forget_all()

    @property
    def stream_prefs(self) -> streams.Preferences:
        """Ajustes › Idioma: «en», «es» (cualquier español), «es-419» (latino) o «es-ES» (castellano)."""
        quality = self.setting("quality", self.config.stremio.quality)
        langs = self.setting("languages")
        if streams.valid_languages(langs):  # N4-A: Ajustes › Tus idiomas manda
            return streams.prefs_from_languages(langs, quality)
        audio = str(self.setting("audio", self.config.stremio.audio) or "en")
        variant = spanish_variant(audio)
        if audio == "es" and not variant:  # el ajuste de antes («Español» + «Latino» aparte)
            variant = streams.DUB_CODES.get(str(self.setting("dub", "") or ""), "")
        return streams.Preferences(audio="es" if variant else audio, spanish=variant,
                                   quality=self.setting("quality", self.config.stremio.quality))

    @property
    def subtitles_lang(self) -> str:
        return self.setting("subtitles", self.config.stremio.subtitles)

    def language_for(self, meta_id: str) -> tuple[streams.Preferences, str]:
        """Idioma de audio y subtítulos para un título: el que elegiste viéndolo (cada serie
        recuerda el suyo) o, si nunca cambiaste, el de Ajustes."""
        saved = self.state.prefs(f"stremio:{meta_id}")
        prefs = self.stream_prefs
        # Solo texto: un valor raro en state.json («audio»: ["x"]) impedía reproducir ese título.
        if isinstance(saved.get("audio"), str) and saved["audio"]:
            prefs = replace(prefs, audio=saved["audio"])
        spanish = saved.get("spanish") if "spanish" in saved else streams.DUB_CODES.get(str(saved.get("dub") or ""))  # «dub»: como se guardaba antes
        if prefs.audio == "es" and spanish in streams.SPANISH_VARIANTS:
            prefs = replace(prefs, spanish=spanish)  # elegiste la pista latina (o castellana) de esta serie
        subtitles = saved.get("subtitles")
        return prefs, subtitles if isinstance(subtitles, str) else self.subtitles_lang

    def asked_language(self, meta: dict) -> tuple[streams.Preferences, str]:
        """El idioma de este video: el que se pidió por voz solo para esta vez (`meta["asked"]`: «pon Los Simpson en
        latino») encima del que recuerda el título. Lo usan el respaldo, otra versión y el siguiente episodio."""
        prefs, subtitles = self.language_for(meta["meta_id"]) if meta.get("meta_id") else (self.stream_prefs, self.subtitles_lang)
        asked = meta.get("asked")
        asked = asked if isinstance(asked, dict) else {}
        if isinstance(asked.get("audio"), str) and asked["audio"]:
            variant = asked.get("spanish") if asked.get("spanish") in streams.SPANISH_VARIANTS else ""
            prefs = replace(prefs, audio=asked["audio"], spanish=variant or (prefs.spanish if asked["audio"] == "es" else ""))
        if isinstance(asked.get("subtitles"), str):
            subtitles = asked["subtitles"]
        return prefs, subtitles

    def remember_title_language(self, meta_id: str, audio: str | None = None, spanish: str | None = None,
                                subtitles: str | None = None) -> None:
        """«… siempre en latino», «… siempre con subtítulos en inglés»: ese título lo recuerda (audio, doblaje y
        subtítulos). Lo dicho por voz sin «siempre» es solo para esta vez y no pasa por aquí."""
        key = f"stremio:{meta_id}"
        if audio:
            self.state.set_pref(key, "audio", audio)
            if spanish is not None or audio != "es":
                self.state.set_pref(key, "spanish", spanish if audio == "es" and spanish in streams.SPANISH_VARIANTS else "")
        if subtitles is not None:
            self.state.set_pref(key, "subtitles", subtitles)
        log.info("%s recordará audio %s%s, subtítulos %s", meta_id, audio, f" ({spanish})" if spanish else "", subtitles)

    def _spanish_for(self, meta: dict) -> str:
        """El doblaje del español de este video (para elegir la pista latina o castellana): el pedido para esta vez o el
        del título."""
        asked = meta.get("asked")
        asked = asked if isinstance(asked, dict) else {}
        if asked.get("spanish") in streams.SPANISH_VARIANTS:
            return asked["spanish"]
        return self.language_for(meta["meta_id"])[0].spanish if meta.get("meta_id") else ""

    def _remember_language(self, meta: dict, kind: str, code: str) -> None:
        """Cambiaste el audio o los subtítulos en el reproductor: esa serie (o película) lo recuerda."""
        lang = language_code(code)
        if meta.get("meta_id") and lang is not None:
            self.state.set_pref(f"stremio:{meta['meta_id']}", kind, lang)
            if kind == "audio" and lang == "es" and spanish_variant(code):  # la pista latina: los siguientes, en latino
                self.state.set_pref(f"stremio:{meta['meta_id']}", "spanish", spanish_variant(code))
            log.info("%s recordará %s: %s", meta.get("title") or meta["meta_id"], kind, lang or "sin subtítulos")

    def stream_sources(self, kind: str, video_id: str, prefs: streams.Preferences | None = None) -> list[streams.Source]:
        """Fuentes de tus addons, ordenadas por tus preferencias (la primera es la recomendada). Tu OneDrive ya no va aquí
        (como el iPhone): tu copia se ve desde Mi media (play_own)."""
        if not self.has_addons:
            raise stremio_api.StremioError(stremio_api.NOT_LINKED)
        found = self.streams.find(kind, video_id, prefs or self.stream_prefs)
        refused = self.rd.refused()
        if refused or any(s.refused for s in found):
            # FQ2-A como el iPhone: lo que Real-Debrid no dejó bajar resta 1500 (solo es la tarjeta de su casilla si está
            # sola). La lista viene de la caché: se quita lo de antes para no restarlo dos veces.
            for s in found:
                now = not s.cached and s.info_hash in refused
                s.score += (1500 if s.refused else 0) - (1500 if now else 0)
                s.refused = now
            found = sorted(found, key=lambda s: s.score, reverse=True)
        req = self.rd.status(video_id)
        if not (req and req.get("mine") and req.get("state") == rd_requests.READY):
            # Otro episodio de un paquete de temporada que pediste y ya está: el archivo de este episodio lo dice
            # Torrentio (solo se marca lo que lista; nunca se adivina el archivo). Error 1 del iPhone.
            packs = self.rd.ready_packs(video_id.split(":")[0]) if kind == "series" else set()
            same = [s for s in found if s.info_hash in packs and not s.doubtful]
            for s in same:
                s.cached, s.requested = True, True
            return [*same, *[s for s in found if s not in same]] if same else found
        # Tu pedido ya terminó: Torrentio puede seguir marcando ese torrent «[RD download]» un rato. Cuenta como al
        # instante («Al instante · la pediste») y va primero; si Torrentio no lo lista, se arma con el archivo pedido.
        done = str(req.get("hash") or "").lower()
        same = [s for s in found if s.info_hash == done]
        for s in same:
            s.cached, s.requested = True, True
        if same:
            return [*same, *[s for s in found if s not in same]]
        mine = self.rd.ready_source(kind, video_id)
        if mine is not None:
            mine.requested = True
        return [mine, *found] if mine is not None else found

    ASK_INDEX = 100_000  # las que solo salen sin la clave van numeradas aparte: nunca chocan con las de tu Torrentio

    def askable(self, kind: str, video_id: str, prefs: streams.Preferences, found: list[streams.Source]) -> list[streams.Source]:
        """«Versión» con tu Torrentio en «Solo lo que ya está en Real-Debrid» (como el iPhone, 4 nov): Torrentio no trae nada
        que pedir, así que «Hay que pedirlas» saldría vacío. Se buscan sin la clave (lo mismo que usa «Pedir a la nube») y
        se agregan como por pedir; las que ya trae tu lista no se repiten. Vacío si tu lista ya trae qué pedir o sin clave."""
        if self.rd.client() is None or any(s.debrid and not s.cached for s in found):
            return []
        have = {s.info_hash for s in found if s.info_hash}
        refused = self.rd.refused()
        out: list[streams.Source] = []
        for s in self.rd.candidates(kind, video_id, prefs):
            if not s.info_hash or s.info_hash in have:
                continue
            gone = s.info_hash in refused
            out.append(replace(s, index=self.ASK_INDEX + len(out), debrid=True, cached=False, refused=gone,
                               score=s.score - (1500 if gone else 0)))  # FQ2-A: lo que no dejó bajar, al final
            have.add(s.info_hash)
        return out

    def availability(self, kind: str, meta_id: str, video_id: str) -> dict:
        """Por qué no hay una versión que arranque ya y qué se puede hacer (la ficha lo dice con sus palabras, RD-1 y RD-5):
        {"why": "ok" | "unreleased" | "offline" | "no-addons" | "debrid" | "none", "message", "detail", "can_request",
        "request"}. «debrid»: existe en internet pero Real-Debrid aún no lo tiene (se le puede pedir)."""
        prefs = self.asked_language({"meta_id": meta_id})[0]
        out = {"why": "ok", "message": "", "detail": "", "can_request": False, "request": self.rd.status(video_id)}
        req = out["request"]
        if not (req and req.get("mine")) and kind == "series":
            try:  # un paquete tuyo que se sigue bajando y que Torrentio lista para este episodio: ya está pedido
                listed = {s.info_hash for s in self.stream_sources(kind, video_id, prefs) if s.info_hash and not s.doubtful}
            except stremio_api.StremioError:
                listed = set()
            pack = self.rd.pack_for(meta_id, listed) if listed else None
            if pack:
                out["request"] = req = pack
        if req and req.get("mine") and req["state"] in rd_requests.ACTIVE:
            stuck = str(req.get("detail") or "").startswith("Sigue sin bajar")  # 24 h sin avanzar: su hoja ofrece otra
            return {**out, "why": "requested", "message": req["message"],
                    "detail": req["detail"] if stuck or req["state"] not in (rd_requests.DOWNLOADING, rd_requests.QUEUED)
                    else rd_requests.CLOUD}
        when = self._release_of(kind, meta_id, video_id)
        if when and when > time.time():
            day = player_ui_day(when)
            return {**out, "why": "unreleased", "message": f"Aún no se estrena · sale {day}",
                    "detail": "Cuando salga, aparece aquí"}
        try:
            found = self.stream_sources(kind, video_id, prefs)
        except stremio_api.StremioError as exc:
            return {**out, "why": "no-addons", "message": "No puedo buscar versiones", "detail": str(exc)}
        ready = [s for s in found if ready_now(s)]
        if ready:
            offer = self._dub_offer(kind, video_id, prefs, found, ready)
            return {**out, "offer": offer} if offer else out
        outcome = self.streams.outcome.get(f"{kind}:{video_id}")
        if self.rd.client() is not None:  # tu cuenta va antes que lo de cada versión (el orden de vocabulario.json)
            cause = DEBRID_CAUSES.get(self.debrid_status(fresh=outcome == "debrid-account").get("problem") or "")
            if cause:
                return {**out, "why": "debrid-account", "message": cause[0], "detail": cause[1]}
        if outcome == "offline":
            return {**out, "why": "offline", "message": "No pude conectar con tus complementos",
                    "detail": "Revisa Internet e inténtalo de nuevo"}
        if outcome == "no-addons":
            return {**out, "why": "no-addons", "message": "No tienes complementos prendidos",
                    "detail": "Ajustes › Complementos"}
        if self.rd.client() is None:
            # Sin clave no hay qué pedir ni cómo saber si alguien lo tiene: la salida es conectar Real-Debrid, nunca
            # «Nadie lo tiene» sin salida (análisis de fondo con el iPhone, escenario 16).
            return {**out, "why": "debrid-account", "message": "Vuelve a conectar Real-Debrid",
                    "detail": "Ajustes › Cuentas › Real-Debrid"}
        exists = bool(found) or bool(self.rd.candidates(kind, video_id, prefs))
        if exists and self.rd.client() is not None and req and req.get("mine") and req["state"] in (
                rd_requests.REFUSED, rd_requests.TOO_MANY):
            return {**out, "why": "debrid", "can_request": True, "message": req["message"], "detail": req["detail"]}
        if exists and self.rd.client() is not None:
            language = streams.LANG_NAMES.get(prefs.audio, prefs.audio).lower()
            return {**out, "why": "debrid", "can_request": True, "message": "Todavía no está en la nube",
                    "detail": f"La nube lo puede bajar por ti, de preferencia en {language}; tarda según cuánta gente lo comparte"}
        return {**out, "why": "none", "message": "Nadie lo tiene todavía en internet",
                "detail": "Suele aparecer en unas horas o días · vuelve a buscar más tarde"}

    def _dub_offer(self, kind: str, video_id: str, prefs: streams.Preferences, found: list[streams.Source],
                   ready: list[streams.Source]) -> dict | None:
        """FQ1-A (Fernando, 3 nov): quieres latino y lo que arranca ya es otro idioma. «Ver» pone la que arranca y, al lado,
        «Pedir a la nube en latino» pide la tuya: {"label", "hash"}; None si ya arranca en tu doblaje o no hay cuál pedir."""
        want = prefs.spanish if prefs.audio == "es" and prefs.spanish in streams.SPANISH_VARIANTS else None
        if not want or self.rd.client() is None or any(want in s.audio_langs for s in ready):
            return None
        refused = self.rd.refused()
        pool = [s for s in found if s.debrid and not s.cached] or self.rd.candidates(kind, video_id, prefs)
        pick = next((s for s in pool if want in s.audio_langs and s.info_hash and s.info_hash not in refused
                     and not s.doubtful and not {"CAM", "Tráiler", "3D"} & set(s.tags)), None)
        if pick is None:
            return None
        return {"label": f"Pedir a la nube en {streams.LANG_NAMES.get(want, want).lower()}", "hash": pick.info_hash}

    def request_debrid(self, kind: str, meta_id: str, video_id: str, title: str = "", want: str | None = None) -> dict:
        """«Pedirlo y avisarme»: Real-Debrid empieza a bajarlo (RD-1); con `want`, justo esa versión (la huella que trae
        «Versión», T8-A). Lanza LookupError con el motivo en palabras."""
        prefs = self.asked_language({"meta_id": meta_id})[0]
        if not title:
            try:
                info = self.cinemeta.meta(kind, meta_id)
                title = self._episode_title(info, meta_id, video_id)[0] if kind == "series" else info.get("name") or ""
            except cinemeta.CinemetaError:
                title = ""
        try:
            parts = video_id.split(":")
            season, episode = (int(parts[1]), int(parts[2])) if kind == "series" and len(parts) == 3 and                 parts[1].isdigit() and parts[2].isdigit() else (None, None)
            return self.rd.request(kind, video_id, title or "tu pedido", prefs, meta_id=meta_id, season=season,
                                   episode=episode, want=want)
        except realdebrid.RealDebridError as exc:
            raise LookupError(str(exc)) from exc

    def _release_of(self, kind: str, meta_id: str, video_id: str) -> float | None:
        """Cuándo sale esa película o ese episodio (None si no se sabe). Una película por estrenarse decía «Nadie lo
        tiene» (análisis de fondo con el iPhone, escenario 14)."""
        if kind not in ("movie", "series"):
            return None
        try:
            info = self.cinemeta.meta(kind, meta_id)
        except cinemeta.CinemetaError:
            return None
        if kind == "movie":
            return cinemeta.released_at(info.get("released"))
        for season in cinemeta.seasons(info):
            for episode in season["episodes"]:
                if episode["id"] == video_id:
                    return cinemeta.released_at(episode.get("released"))
        return None

    def _url_for(self, source: streams.Source) -> str | None:
        if source.stream.get("onedrive") and self.onedrive is not None:
            return self.onedrive.stream_url(source)
        return player.stream_url(source.stream)

    def best_source(self, kind: str, video_id: str, binge: str | None = None,
                    skip: set[int] | None = None, prefs: streams.Preferences | None = None) -> streams.Source | None:
        """La fuente recomendada; en una serie, mejor la del mismo grupo que el episodio anterior
        (misma calidad e idioma: así lo hace Stremio con bingeGroup)."""
        found = [s for s in self.stream_sources(kind, video_id, prefs) if s.index not in (skip or set())]
        if self.native_player:  # solo las que el reproductor de Orbital puede abrir (una ftp:// atoraba el respaldo)
            found = [s for s in found if player.stream_url(s.stream) or s.stream.get("onedrive")]
        if not found:
            return None
        # Nunca una de cine, un tráiler ni una que parece de otro título o de otra temporada si hay otra (invariante 4
        # de los escenarios comunes con el iPhone): al instante, una de otra temporada todavía puede sumar más.
        # Tampoco una que Real-Debrid no dejó bajar (FQ2-A): pedirla otra vez falla igual.
        refused = self.rd.refused()
        clean = [s for s in found if not s.doubtful and not {"CAM", "Tráiler", "3D"} & set(s.tags)
                 and (s.cached or s.info_hash not in refused)]
        found = clean or found
        if binge:
            same = next((s for s in found if s.binge == binge and s.score > found[0].score - 700), None)
            if same:
                return same
        return found[0]

    def remembered(self, limit: int = 60) -> list[dict]:
        """Ajustes › «Lo que recuerda cada título»: el nombre (de tu biblioteca, si está) y lo que eligió."""
        names = {i.id.split(":", 1)[-1]: i.title for i in self.stremio_items}
        return [{"id": meta_id, "title": names.get(meta_id) or meta_id, "line": choice_line(fields)}
                for meta_id, fields in self.state.remembered_titles()[:limit]]

    def remember_version(self, kind: str, meta_id: str, video_id: str, index: int) -> None:
        """«Versión» › «Desde aquí»: la serie sigue con el idioma (y el doblaje) de la versión que elegiste. «Solo este
        episodio» no llama aquí: el siguiente vuelve a lo de siempre."""
        source = self.streams.get(kind, video_id, self.language_for(meta_id)[0], index)
        if source is None or not source.languages:
            return
        prefs = self.language_for(meta_id)[0]
        lang = prefs.audio if prefs.audio in source.languages and len(source.languages) > 1 else source.languages[0]
        key = f"stremio:{meta_id}"
        self.state.set_pref(key, "audio", lang)
        if lang == "es" and source.dub in streams.DUB_CODES:
            self.state.set_pref(key, "spanish", streams.DUB_CODES[source.dub])

    def choose_source(self, kind: str, video_id: str, prefs: streams.Preferences,
                      resume: dict | None = None) -> streams.Source | None:
        """La que pone «Ver»: la fuente con la que lo dejaste («Continuar»), si sigue ahí; si no, la recomendada. La misma
        cuenta para reproducir y para decir en la ficha qué va a sonar (antes la ficha describía otra)."""
        if resume and resume.get("source"):
            found = self.stream_sources(kind, video_id, prefs)
            # Lo que pediste y ya está le gana a la de «Continuar», y la de «Continuar» nunca es una de cine, un tráiler
            # ni una que parece de otro título o episodio (análisis de fondo con el iPhone, error 9).
            mine = next((s for s in found if s.requested), None)
            same = next((s for s in found if s.key == resume["source"]), None)
            if mine is not None and (same is None or not same.requested):
                return mine
            if same is not None and not same.doubtful and not {"CAM", "Tráiler"} & set(same.tags):
                return same
        return self.best_source(kind, video_id, prefs=prefs)

    def no_sources_message(self, kind: str, video_id: str) -> str:
        """Por qué no hay dónde verlo, con qué hacer: sin Internet, sin complementos o de verdad no hay."""
        why = self.streams.outcome.get(f"{kind}:{video_id}")
        if why == "offline":
            return "No pude conectar con tus complementos. Revisa Internet e inténtalo de nuevo."
        if why == "no-addons":
            return "No tienes complementos prendidos. Ajustes › Complementos."
        return "No encontré dónde ver esto: tus complementos no lo tienen."
