"""Voz: buscar y poner películas y series (por nombre, Seguir viendo, recomendaciones)."""

from __future__ import annotations

import re
import time
from difflib import SequenceMatcher

from ..catalog import normalize
from ..library import cinemeta
from .parsing import (
    GENRE_NAMES,
    GENRES,
    LANGUAGE_NAMES,
    LANGUAGES,
    MEDIA_OPTIONS,
    OTHER_SAY,
    QUICK_LOOKUP,
    THE_USUAL,
    VAGUE_MEDIA,
    VOICE_WAIT,
    VoiceResult,
    always_said,
    episode_request,
    kind_hint,
    log,
    split_language,
    spoken_list,
    title_tail,
    upcoming_speech,
)
from .system import _System


class _Media(_System):
    """Buscar y poner películas y series por voz."""

    def _open_stremio_intent(self, slots: dict) -> VoiceResult:
        self.catalog.sessions.launch("media:stremio")
        return VoiceResult("Abriendo Stremio.")

    def _search_media_intent(self, slots: dict) -> VoiceResult:
        query, kind = slots.get("query", ""), slots.get("kind")
        if not query:
            return VoiceResult("¿Qué quieres ver?", ok=False)
        query, options = self._media_options(query, slots)
        if kind is None:
            query, kind = kind_hint(query)
            kind = kind if kind in ("movie", "series") else None
        if (episode := episode_request(query)) is not None:  # "quiero ver Los Simpson temporada 5…"
            return self._watch_episode_intent({**options, **episode})
        if (vague := self._vague(query)) is not None:  # "quiero ver una película": no es un título
            return vague
        if (section := self._section(query)) is not None:  # «pon la tele», «quiero ver Para ti»
            return section
        if (channel := self._find_channel(query)) is not None:  # «pon ADN 40»: el canal en vivo (antes: buscarlo en Stremio)
            return self._play_channel(channel)
        # Si ya está en tu biblioteca de Stremio, se abre directo.
        item = self.catalog.find(query, source="stremio")
        if item is not None:
            return self._watch_item(item, options)
        try:
            exact = self._watch_exact(query, kind, options, ask=bool(slots.get("browse")))
        except cinemeta.CinemetaError:  # sin catálogo: la búsqueda de Stremio
            self.catalog.sessions.search_media(query)
            return VoiceResult(f"Buscando {query} en Stremio.")
        if exact:
            return exact
        # Varias opciones: la búsqueda de Orbital ya escrita, para elegir con el mando.
        return VoiceResult(f"Buscando {query}. Elige con el control.", events=[self._show_view({"buscar": query}, f"Buscando «{query}»")])

    @staticmethod
    def _media_options(name: str, slots: dict) -> tuple[str, dict]:
        """El título sin lo que va pegado («Los Simpson siempre en latino con subtítulos») y esas opciones (language,
        subtitles, from_start, always). El texto libre ya llega separado; Alexa lo manda todo en el slot del título."""
        options = {k: slots[k] for k in MEDIA_OPTIONS if slots.get(k)}
        said, always = always_said(normalize(name))
        title, extra = title_tail(said)
        if not always and not extra:
            return name, options
        if always:
            options.setdefault("always", "1")
        for key, value in extra.items():
            options.setdefault(key, value)
        return title, options

    def _subtitles_option(self, said: str | None) -> str | None:
        """«con subtítulos» ("1"): los de Ajustes (o en español); «con subtítulos en inglés»: "en". None: no se pidió."""
        if not said:
            return None
        if said == "1":
            return self.catalog.watch.subtitles_lang or "es"
        return split_language(LANGUAGES.get(normalize(said)))[0]

    def _media_request(self, options: dict) -> tuple[dict, str]:
        """Las opciones dichas → los argumentos de `play_title` (audio, spanish, subtitles, remember) y cómo se dicen
        («en latino con subtítulos en inglés»)."""
        code = LANGUAGES.get(normalize(options.get("language") or ""))
        audio, spanish = split_language(code)
        subtitles = self._subtitles_option(options.get("subtitles"))
        kwargs: dict = {}
        if audio:
            kwargs["audio"] = audio
        if spanish:
            kwargs["spanish"] = spanish
        if subtitles is not None:
            kwargs["subtitles"] = subtitles
        if options.get("always") and (audio or subtitles is not None):
            kwargs["remember"] = True
        how = (f" en {LANGUAGE_NAMES.get(code, code)}" if code else "") + \
            (f" con subtítulos en {LANGUAGE_NAMES.get(subtitles, subtitles)}" if subtitles else "")
        return kwargs, how

    def _remember_title(self, meta_id: str, title: str, kwargs: dict) -> None:
        """«… siempre en latino» sin poner nada (una serie: se elige el episodio): el título lo recuerda ya."""
        audio = kwargs.get("audio")
        self.catalog.watch.remember_title_language(meta_id, audio, kwargs.get("spanish", "") if audio else None,
                                                   kwargs.get("subtitles"))
        log.info("Voz: %s recordará %s", title, kwargs)

    def _vague(self, name: str) -> VoiceResult | None:
        """No es un título: «la telenovela» es lo que estabas viendo; «una película», a elegir."""
        said = normalize(name)
        if said in THE_USUAL:
            if self.catalog.stremio_linked and self.catalog.grouped_items("continue"):
                return self._continue_watching_intent({})
            return VoiceResult("¿Cuál? Dime el nombre, por ejemplo: quiero ver La Rosa de Guadalupe.", ok=False)
        if said in VAGUE_MEDIA:
            return self._open_stremio_intent({})
        return None

    def _ask_which(self, query: str, options: list[dict]) -> VoiceResult:
        """Varias con el mismo nombre (Dune de 1984 y de 2021): se pregunta en pantalla, como una
        consola, en vez de poner la primera que salga."""
        if self.kiosk is not None:
            self.kiosk.open()
        said = "; ".join(f"{o['title']}, {o['subtitle'].lower().replace(' · ', ' de ')}" for o in options[:3])
        choices = [{k: o.get(k) for k in ("id", "title", "subtitle", "kind", "meta_id", "image", "hero")} for o in options[:6]]
        return VoiceResult(f"Encontré varias: {said}. Elige con el control.",
                           events=[{"type": "choose", "query": query, "options": choices,
                                    "message": f"¿Cuál «{query}»?"}], choices=choices)

    def _show_view(self, view: dict, message: str = "") -> dict:
        """Trae Orbital al frente con una vista abierta (búsqueda o ficha), sin recargar la interfaz:
        no se pierde dónde estabas y se ve qué entendió Alexa."""
        if self.kiosk is not None:
            self.kiosk.open()
        return {"type": "open-view", "view": view, "message": message}

    def _watch_exact(self, query: str, kind: str | None = None, options: dict | None = None, ask: bool = False) -> VoiceResult | None:
        """Cualquier película o serie, esté o no en tu biblioteca: la película se pone directo y la serie arranca en su
        episodio. Varias con el mismo nombre («Dune»): la primera (la más popular), y «otro» pone la siguiente; el iPhone
        recibe todas para tocar la que es. Antes se pedía elegir en la tele con el control, que nadie tenía a la mano.
        None si no hay nada claro."""
        matches = self._resolve_title(query, kind)
        if ask and len(matches) > 1:
            return self._ask_which(query, matches)
        match = matches[0] if matches else None
        if match is None:
            return None
        options = options or {}
        ordered = matches + [c for c in self._candidates if c not in matches and (kind is None or c.get("kind") == kind)]
        self._last = {"at": time.time(), "query": query, "options": options, "seen": [match["meta_id"]], "candidates": ordered}
        result = self._play_match(match, options)
        if len(matches) > 1 and result.ok:
            result.speech += " Si no es esa, di otro."
            result.choices = [{k: o.get(k) for k in ("id", "title", "subtitle", "kind", "meta_id", "image", "hero")}
                              for o in matches[:6]]
            result.picked = match["meta_id"]
            for event in result.events:
                if event.get("type") == "toast":
                    event["detail"] = OTHER_SAY
        return result

    def _play_match(self, match: dict, options: dict) -> VoiceResult:
        """Una película o serie ya resuelta: la película donde ibas (o desde el principio); la serie, su primer episodio."""
        kwargs, how = self._media_request(options)
        memo = f" {match['title']} quedará{how}." if kwargs.get("remember") else ""
        if match["kind"] == "movie":
            problem = self.catalog.watch.play_title("movie", match["meta_id"], match["meta_id"], match["title"], wait=VOICE_WAIT,
                                                    from_start=bool(options.get("from_start")), **kwargs)
            if problem:
                return VoiceResult(problem, ok=False)
            start = " desde el principio" if options.get("from_start") else ""
            speech = f"Poniendo {match['title']}{how}{start}.{memo}"
            return VoiceResult(speech, events=[self._playing_event(f"Poniendo {match['title']}", "movie")])
        return self._play_series(match["meta_id"], match["title"], kwargs, how, memo)

    def _play_series(self, meta_id: str, title: str, kwargs: dict, how: str, memo: str) -> VoiceResult:
        """«Pon The Office» sin haberla visto: su primer episodio que ya salió (antes abría la lista de episodios y te dejaba
        frente a la tele sin el control). Sin la lista de episodios (Cinemeta caído), su ficha para elegir."""
        try:
            meta = self.catalog.cinemeta.meta("series", meta_id) or {}
        except cinemeta.CinemetaError:
            meta = {}
        videos = [v for v in meta.get("videos") or [] if isinstance(v, dict) and v.get("id") and (v.get("season") or 0) > 0]
        today = time.strftime("%Y-%m-%d")
        aired = [v for v in videos if str(v.get("released") or "")[:10] <= today] or videos
        first = min(aired, key=lambda v: (v.get("season") or 0, v.get("episode") or 0), default=None)
        if first is None:
            if memo:  # se elige el episodio en pantalla; con «siempre», ya lo recuerda
                self._remember_title(meta_id, title, kwargs)
            return VoiceResult(f"Abriendo {title}. Elige el episodio.{memo}",
                               events=[self._show_view({"serie": meta_id}, f"Abriendo {title}")])
        season, episode = first.get("season"), first.get("episode")
        problem = self.catalog.watch.play_title("series", meta_id, first["id"], f"{title} · T{season} E{episode}",
                                                wait=VOICE_WAIT - 2, **kwargs)
        if problem:
            return VoiceResult(problem, ok=False)
        return VoiceResult(f"Poniendo {title}, temporada {season}, episodio {episode}{how}.{memo}",
                           events=[self._playing_event(f"Poniendo {title} · T{season} E{episode}", "series")])

    def _resolve_title(self, query: str, kind: str | None = None) -> list[dict]:
        """Lo dicho → la película o serie que es. Cinemeta guarda el título en inglés: «El viaje de Chihiro» llega como
        «Spirited Away» y antes solo valía la coincidencia letra por letra («No encontré … en tu biblioteca»).
        1) exacto en Cinemeta; 2) TMDB en español (si hay clave): su título coincide o se parece mucho; 3) el primero de
        Cinemeta si se parece mucho (nunca «el único que salió»: un juego mal dicho ponía una película)."""
        target = normalize(query)
        movies = self.catalog.cinemeta.search("movie", query)
        series = self.catalog.cinemeta.search("series", query)
        results = [r for r in cinemeta.search_results(query, movies, series) if kind is None or r["kind"] == kind]
        self._candidates = results  # «otro»: la siguiente de esta misma búsqueda
        exact = [r for r in results if normalize(r["title"]) == target]
        if exact:
            return exact
        close = lambda title: SequenceMatcher(None, normalize(title), target).ratio() >= .85  # noqa: E731
        tmdb = getattr(getattr(self.catalog, "foryou", None), "tmdb", None)
        if tmdb is not None and getattr(tmdb, "configured", False):
            found = []
            for tmdb_kind in ("movie", "series") if kind is None else (kind,):
                try:
                    hit = tmdb.search(tmdb_kind, query)  # en español: «El viaje de Chihiro» sí lo encuentra
                except Exception as exc:  # noqa: BLE001 - sin TMDB, lo de Cinemeta
                    log.info("Voz: TMDB no respondió para %s: %s", query, exc)
                    hit = None
                if hit and hit.get("imdb") and close(hit.get("title") or ""):
                    found.append({"kind": tmdb_kind, "meta_id": hit["imdb"], "title": hit["title"]})
            if found:
                return found
        if results and close(results[0]["title"]):  # (solo si se parece: un juego mal dicho no pone una película)
            return [results[0]]
        return []

    def _continue_watching_intent(self, slots: dict) -> VoiceResult:
        # «continúa viendo la película» llega a Alexa como «continúa {show}» con show «viendo la película»: es seguir viendo.
        show = re.sub(r"^(?:viendo|con)\s+", "", slots.get("show", "").strip(), flags=re.IGNORECASE)
        if normalize(show) in THE_USUAL | {"la pelicula", "la peli", "la serie", "el video", "el capitulo", "el episodio"}:
            show = ""
        if not show and self.catalog.player.playing:  # «continúa» con un video abierto: quitarle la pausa
            return self._resume_intent({})
        if show and (episode := episode_request(show)) is not None:
            return self._watch_episode_intent(episode)
        if not self.catalog.stremio_linked:
            return VoiceResult("Primero conecta tu cuenta de Stremio en Ajustes de Orbital.", ok=False)
        if show:
            item = self.catalog.find(show, source="stremio")
            if item is None:
                return VoiceResult(f"No encontré {show} en tu biblioteca de Stremio.", ok=False)
        else:
            watching = self.catalog.grouped_items("continue")
            if not watching:
                return VoiceResult("No tienes nada a medias en Stremio.", ok=False)
            item = watching[0]
        detail = item.subtitle.split(" · ")[0].removeprefix("Sigue: ")  # "T3 E9" (sin "quedan 40 min")
        result = self._watch_item(item)
        if result.ok and not result.events:
            result.speech = f"Continuando {item.title}{', ' + detail if detail else ''}."
        return result

    def _watch_item(self, item, options: dict | None = None) -> VoiceResult:
        """Algo de tu biblioteca de Stremio: el episodio o la película donde ibas; una serie sin
        episodio pendiente abre sus episodios en Orbital. `options`: «… en latino con subtítulos (siempre)»."""
        extra = item.extra or {}
        kind, meta_id, video_id = extra.get("kind"), extra.get("meta_id"), extra.get("video_id")
        options = options or {}
        kwargs, how = self._media_request(options)
        memo = f" {item.title} quedará{how}." if kwargs.get("remember") else ""
        if kind in ("movie", "series") and meta_id and video_id:
            if options.get("from_start"):
                kwargs["from_start"] = True
            problem = self.catalog.watch.play_title(kind, meta_id, video_id, item.title, wait=VOICE_WAIT, **kwargs)
            start = " desde el principio" if options.get("from_start") else ""
            return VoiceResult(problem, ok=False) if problem else VoiceResult(f"Poniendo {item.title}{how}{start}.{memo}")
        if kind == "series" and meta_id:
            return self._play_series(meta_id, item.title, kwargs, how, memo)
        self.catalog.sessions.launch(item.id)
        return VoiceResult(f"Abriendo {item.title} en Stremio.")

    def _free_text_intent(self, slots: dict) -> VoiceResult:
        """Lo que Alexa no supo acomodar en otro intent («por favor pon…»): la frase tal cual, con el intérprete de texto
        (la skill la manda como `text`; esto es por si llega como intent)."""
        return self.handle_text(slots.get("query") or "")

    def _command_intent(self, slots: dict) -> VoiceResult:
        """El comodín de Alexa (la frase entera, sin frase de apoyo): igual, al intérprete de texto."""
        return self.handle_text(slots.get("command") or "")

    def _upcoming_intent(self, slots: dict) -> VoiceResult:
        """«¿Qué sale hoy?»: lo que sale de las series que sigues (Trakt), hoy y los próximos días."""
        foryou = self.catalog.foryou
        if not foryou.trakt.linked:
            return VoiceResult("Conecta Trakt en Ajustes de Orbital y te digo cuándo salen tus series.", ok=False)
        show = self._show_view({"seccion": "foryou"}, "Próximos estrenos")
        try:
            items = self._within(QUICK_LOOKUP, foryou.calendar)
        except Exception:  # noqa: BLE001 - sin red o Trakt caído: se dice, no «algo salió mal»
            return VoiceResult("No pude preguntarle a Trakt ahora. Inténtalo en un rato.", ok=False)
        if items is None:
            return VoiceResult("Trakt está tardando. Te los enseño en Para ti, en Próximos estrenos.", events=[show])
        if not items:
            return VoiceResult("No sale nada de tus series en los próximos 14 días.")
        return VoiceResult(upcoming_speech(items), events=[show])

    def _recommend_intent(self, slots: dict) -> VoiceResult:
        """«¿Qué me recomiendas?»: tres títulos de tus recomendaciones y Para ti en pantalla. Con género («algo de terror»):
        lo más popular de ese género, a elegir en la tele (y en el iPhone, que recibe la misma lista)."""
        said = normalize(slots.get("genre") or "")
        genre = GENRES.get(said) or next((g for word, g in GENRES.items() if word in said.split() or word == said), None)
        if genre:
            return self._recommend_genre(genre, "series" if normalize(slots.get("what") or "") == "serie" else "movie")
        foryou = self.catalog.foryou
        show = self._show_view({"seccion": "foryou"}, "Explorar")
        titles: list[str] = []
        if foryou.trakt.linked:
            try:
                items = self._within(QUICK_LOOKUP, lambda: foryou.list_items("recs", "series")[:2] + foryou.list_items("recs", "movie")[:1])
            except Exception:  # noqa: BLE001
                items = None
            titles = [i["title"] for i in items or [] if i.get("title")]
        if not titles:
            return VoiceResult("Te dejo Explorar abierto: ahí están tus sugerencias.", events=[show])
        return VoiceResult(f"Te recomiendo {spoken_list(titles)}. Están en Explorar.", events=[show])

    def _recommend_genre(self, genre: str, kind: str) -> VoiceResult:
        name = GENRE_NAMES.get(genre, genre.lower())
        try:
            metas = self._within(QUICK_LOOKUP, lambda: self.catalog.cinemeta.genre(kind, genre))
        except Exception:  # noqa: BLE001 - sin catálogo (o tardó): Para ti
            metas = None
        if not metas:
            return VoiceResult(f"No pude traer {'series' if kind == 'series' else 'películas'} de {name}. Te dejo Explorar.",
                               ok=False, events=[self._show_view({"seccion": "foryou"}, "Explorar")])
        options = [{**items[0].public(), "kind": kind, "meta_id": meta["id"]}  # uno por uno: el id va con su ficha
                   for meta in metas[:6] if (items := cinemeta.catalog_items(kind, [meta]))]
        if self.kiosk is not None:
            self.kiosk.open()
        what = "series" if kind == "series" else "películas"
        titles = [o["title"] for o in options[:3]]
        choices = [{k: o.get(k) for k in ("id", "title", "subtitle", "kind", "meta_id", "image", "hero")} for o in options]
        return VoiceResult(f"De {name} te recomiendo {spoken_list(titles)}. Elige una.", choices=choices,
                           events=[{"type": "choose", "query": f"{what} de {name}", "options": choices,
                                    "message": f"{what.capitalize()} de {name}"}])
