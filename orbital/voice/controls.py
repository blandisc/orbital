"""Voz: lo que se hace con un video puesto (pausa, adelantar, volumen, idiomas, episodios)."""

from __future__ import annotations

import time

from ..catalog import normalize
from ..text import clock as text_clock
from .media import _Media
from .parsing import (
    LANGUAGE_NAMES,
    LANGUAGES,
    MAX_SEEK,
    NO_TOAST,
    OTHER_WINDOW,
    SEEK_BACK,
    VOICE_WAIT,
    VOLUME_DOWN,
    VoiceResult,
    split_language,
    spoken_number,
    words_to_numbers,
)


class _Controls(_Media):
    """Lo que se hace por voz con un video puesto."""

    # --- reproductor de Orbital -------------------------------------------------------------
    # Sin aviso en la interfaz (events=[NO_TOAST]): el video está encima y mpv ya lo muestra.
    def _playing(self) -> VoiceResult | None:
        """None si hay algo en el reproductor de Orbital; si no, la respuesta para Alexa."""
        if self.catalog.player.playing:
            return None
        return VoiceResult("No hay nada reproduciéndose en Orbital.", ok=False)

    def _music(self, action: str, speech: str) -> VoiceResult | None:
        """Sin nada en el reproductor de Orbital, la orden va a la música de Windows (Apple Music…)."""
        from .. import music

        if self.catalog.player.playing or not music.now_playing():
            return None
        return VoiceResult(speech) if music.command(action) else None

    def _pause_intent(self, slots: dict) -> VoiceResult:
        if not self.catalog.player.playing and (done := self._music("pause", "Música en pausa.")):
            return done
        if (idle := self._playing()) is not None:
            return idle
        self.catalog.player.set_pause(True)
        return VoiceResult("En pausa.", events=[NO_TOAST])

    def _resume_intent(self, slots: dict) -> VoiceResult:
        from .. import music

        if not self.catalog.player.playing and not music.now_playing() and self.catalog.stremio_linked:
            return self._continue_watching_intent({})  # «sigue», «play» sin nada abierto: lo que dejaste a medias
        return self._resume_now(slots)

    def _resume_now(self, slots: dict) -> VoiceResult:
        if not self.catalog.player.playing and (done := self._music("play", "Listo.")):
            return done
        if (idle := self._playing()) is not None:
            return idle
        self.catalog.player.set_pause(False)
        return VoiceResult("Listo.", events=[NO_TOAST])

    def _seek_intent(self, slots: dict) -> VoiceResult:
        if (idle := self._playing()) is not None:
            return idle
        if slots.get("minute"):  # «ve al minuto 20»
            minute = spoken_number(slots["minute"]) or 0
            self.catalog.player.seek_to(min(MAX_SEEK, minute * 60))
            return VoiceResult(f"Al minuto {int(minute)}.", events=[NO_TOAST])
        unit = normalize(slots.get("unit", ""))
        size, word = (3600, "hora") if unit.startswith(("hour", "hora")) else (60, "minuto") if unit.startswith("min") else (1, "segundo")
        amount = spoken_number(slots.get("amount")) if slots.get("amount") else None
        if amount is None:
            amount = 1 if unit else 10  # «adelanta un minuto» / «adelántale» (como el botón: 10 s)
            size, word = (size, word) if unit else (1, "segundo")
        amount = abs(amount)
        seconds = min(MAX_SEEK, round(amount * size))
        if seconds < 1:
            return VoiceResult("¿Cuánto? Por ejemplo: adelanta cinco minutos.", ok=False, events=[NO_TOAST])
        back = normalize(slots.get("seek") or slots.get("direction", "")) in SEEK_BACK
        self.catalog.player.seek(-seconds if back else seconds)
        if amount == .5 and size > 1:
            what = f"media {word}" if word == "hora" else f"medio {word}"
        else:
            shown = round(seconds / size) if seconds < MAX_SEEK else MAX_SEEK // size
            what = f"{shown} {word}{'s' if shown != 1 else ''}"
        return VoiceResult(f"{'Regresando' if back else 'Adelantando'} {what}.", events=[NO_TOAST])

    def _restart_intent(self, slots: dict) -> VoiceResult:
        """«Desde el principio», «empieza de nuevo»: el video al segundo cero."""
        if (idle := self._playing()) is not None:
            return idle
        self.catalog.player.seek_to(0)
        return VoiceResult("Desde el principio.", events=[NO_TOAST])

    def _time_left_intent(self, slots: dict) -> VoiceResult:
        if (idle := self._playing()) is not None:
            return idle
        segment = self.catalog.player.segment
        if segment is None or not segment.duration:
            return VoiceResult("Todavía no sé cuánto dura.", ok=False)
        left = max(0, segment.duration - segment.position)
        ends = text_clock(time.time() + left)
        minutes = round(left / 60)
        what = "menos de un minuto" if minutes < 1 else f"{minutes} minuto{'s' if minutes != 1 else ''}"
        return VoiceResult(f"Faltan {what}; termina a las {ends}.")

    def _volume_intent(self, slots: dict) -> VoiceResult:
        from .. import quick

        current = quick.volume()
        if current is None:
            return VoiceResult("No encuentro el control de volumen.", ok=False)
        level = spoken_number(slots.get("level")) if slots.get("level") else None
        amount = spoken_number(slots.get("amount")) if slots.get("amount") else None
        word = normalize(slots.get("volume", ""))
        if level is None and amount is not None and not word:
            level = amount  # "pon el volumen en 40"
        if level is None:  # «sube el volumen» (10) o «súbele 20 puntos»
            step = 10 if amount is None else min(100, abs(amount))
            level = current["level"] + (-step if word in VOLUME_DOWN else step)
        after = quick.set_volume(level=int(max(0, min(100, level))), muted=False) or current
        return VoiceResult(f"Volumen en {after['level']} por ciento.")

    def _mute_intent(self, slots: dict) -> VoiceResult:
        from .. import quick

        if quick.set_volume(muted=True) is None:
            return VoiceResult("No encuentro el control de volumen.", ok=False)
        return VoiceResult("Sin sonido. Di quita el silencio para volver.")

    def _unmute_intent(self, slots: dict) -> VoiceResult:
        from .. import quick

        after = quick.set_volume(muted=False)
        if after is None:
            return VoiceResult("No encuentro el control de volumen.", ok=False)
        return VoiceResult(f"Sonido de vuelta, en {after['level']} por ciento.")

    def _language(self, slots: dict) -> str | None:
        return LANGUAGES.get(normalize(slots.get("language", "")))

    def _subtitles_intent(self, slots: dict) -> VoiceResult:
        if (idle := self._playing()) is not None:
            return idle
        asked = slots.get("language", "")
        if asked and self._language(slots) is None:
            return VoiceResult(f"No conozco el idioma {asked}. Prueba con español, inglés, francés o portugués.", ok=False,
                               events=[NO_TOAST])
        lang = split_language(self._language(slots))[0] or self.catalog.config.stremio.subtitles or "en"
        name = LANGUAGE_NAMES.get(lang, lang)
        if self.catalog.watch.player_subtitles(lang):
            memo = self._remember_playing(f"con subtítulos en {name}", subtitles=lang) if slots.get("always") else ""
            return VoiceResult(f"Subtítulos en {name}.{memo}", events=[NO_TOAST])
        return VoiceResult(f"No encontré subtítulos en {name} para esto.", ok=False, events=[NO_TOAST])

    def _remember_playing(self, how: str, **language) -> str:
        """«… siempre»: lo que se ve lo recuerda (audio, doblaje o subtítulos) y se avisa encima del video («Los Simpson
        quedará en latino»). "" si no es un título que pueda recordarlo (un canal)."""
        current = self.catalog.player.current
        meta = getattr(current, "meta", None) or {}
        if not meta.get("meta_id") or meta.get("synthetic") or meta.get("live"):
            return ""
        self.catalog.watch.remember_title_language(meta["meta_id"], **language)
        title = str(meta.get("title") or getattr(current, "title", "") or "").split(" · ")[0] or "Este título"
        self.catalog.player.toast(f"{title} quedará {how}", 4)
        return f" {title} quedará {how}."

    def _subtitles_off_intent(self, slots: dict) -> VoiceResult:
        if (idle := self._playing()) is not None:
            return idle
        self.catalog.player.subtitles_off()
        return VoiceResult("Sin subtítulos.", events=[NO_TOAST])

    def _audio_language_intent(self, slots: dict) -> VoiceResult:
        if (idle := self._playing()) is not None:
            return idle
        code = self._language(slots)
        if code is None:
            return VoiceResult("¿En qué idioma? Por ejemplo: pon el audio en español.", ok=False)
        lang, variant = split_language(code)
        lang = lang or code
        name = LANGUAGE_NAMES.get(code, code)
        player = self.catalog.player
        # «en latino»: la pista latina (con las dos «spa», no la primera). Solo para esta vez; con «siempre», el título.
        if player.select_language("audio", lang, variant) if variant else player.select_language("audio", lang):
            memo = self._remember_playing(f"en {name}", audio=lang, spanish=variant) if slots.get("always") else ""
            return VoiceResult(f"Audio en {name}.{memo}", events=[NO_TOAST])
        return VoiceResult(f"Este video no trae audio en {name}.", ok=False, events=[NO_TOAST])

    def _other_intent(self, slots: dict) -> VoiceResult:
        """«Otro», «esa no»: en la TV en vivo, el siguiente canal; si acabas de pedir algo por nombre, la siguiente que se
        llama así («pon Dune» puso la de 2021: «otro» pone la de 1984)."""
        if self._live_on_air():
            return self._channel_step_intent({"step": "next"})
        last = self._last
        if last and time.time() - last["at"] < OTHER_WINDOW:
            rest = [c for c in last["candidates"] if c.get("meta_id") not in last["seen"]]
            if rest:
                pick = rest[0]
                last["seen"].append(pick["meta_id"])
                last["at"] = time.time()
                return self._play_match(pick, last["options"])
            return VoiceResult(f"No encontré otra que se llame {last['query']}. Di busca {last['query']} para verlas todas.", ok=False)
        return VoiceResult("¿Otro qué? Por ejemplo: pon Dune y luego «otro», o «siguiente episodio».", ok=False)

    def _next_episode_intent(self, slots: dict) -> VoiceResult:
        if self._live_on_air():  # «siguiente» en la TV en vivo: el siguiente canal
            return self._channel_step_intent({"step": "next"})
        if not self.catalog.player.playing and (done := self._music("next", "Siguiente canción.")):
            return done
        if (idle := self._playing()) is not None:
            return idle
        label = self.catalog.watch.play_next_episode()
        if label is None:
            return VoiceResult("No hay un episodio siguiente.", ok=False, events=[NO_TOAST])
        return VoiceResult(f"Poniendo {label}.")

    def _skip_intro_intent(self, slots: dict) -> VoiceResult:
        """«Salta la intro»: lo mismo que A en «Saltar intro» (si el video marca dónde termina)."""
        if (idle := self._playing()) is not None:
            return idle
        label = self.catalog.player.skip_intro()
        if label is None:
            return VoiceResult("Este video no marca dónde termina la intro. Puedes decir: adelanta noventa segundos.",
                               ok=False, events=[NO_TOAST])
        return VoiceResult("Listo, me salté el resumen." if "resumen" in label else "Listo, me salté la intro.",
                           events=[NO_TOAST])

    def _play_episode_intent(self, slots: dict) -> VoiceResult:
        """«Pon el capítulo 5»: de la serie que estás viendo (de la temporada en la que vas)."""
        try:
            episode = int(float(words_to_numbers(normalize(str(slots.get("episode", ""))))))
            season = int(float(words_to_numbers(normalize(str(slots["season"]))))) if slots.get("season") else None
        except ValueError:
            return VoiceResult("¿Qué episodio?", ok=False)
        if self._playing() is not None:
            return VoiceResult("¿De qué serie? Por ejemplo: pon Los Simpson temporada 1 episodio 5.", ok=False)
        label = self.catalog.watch.play_episode_number(episode, season)
        if label is None:
            return VoiceResult("Eso funciona con una serie. Di, por ejemplo: pon Los Simpson temporada 1 episodio 5.",
                               ok=False, events=[NO_TOAST])
        if not label:
            where = f"la temporada {season}" if season else "esta temporada"
            return VoiceResult(f"No encontré el episodio {episode} en {where}.", ok=False, events=[NO_TOAST])
        return VoiceResult(f"Poniendo {label}.")

    def _previous_episode_intent(self, slots: dict) -> VoiceResult:
        if self._live_on_air():  # «anterior» en la TV en vivo: el canal anterior
            return self._channel_step_intent({"step": "previous"})
        if (idle := self._playing()) is not None:
            return idle
        label = self.catalog.watch.play_previous_episode()
        if label is None:
            return VoiceResult("No hay un episodio anterior.", ok=False, events=[NO_TOAST])
        return VoiceResult(f"Poniendo {label}.")

    # --- un episodio concreto ------------------------------------------------------------------
    def _watch_episode_intent(self, slots: dict) -> VoiceResult:
        """«Quiero ver Los Simpson temporada 5 episodio 3 (en español)»."""
        show = (slots.get("series") or slots.get("show") or "").strip()
        latest = bool(slots.get("latest"))
        try:
            season = 0 if latest else int(float(words_to_numbers(normalize(str(slots.get("season", ""))))))
            episode = 0 if latest else int(float(words_to_numbers(normalize(str(slots.get("episode", ""))))))
        except ValueError:
            return VoiceResult("¿Qué temporada y qué episodio?", ok=False)
        if not show:
            return VoiceResult("¿De qué serie?", ok=False)
        found = self.catalog.cinemeta.search("series", show)
        if not found:
            return VoiceResult(f"No encontré la serie {show}.", ok=False)
        target = normalize(show)
        match = next((m for m in found if normalize(m["name"]) == target), found[0])
        meta = self.catalog.cinemeta.meta("series", match["id"])
        videos = [v for v in meta.get("videos") or [] if isinstance(v, dict) and v.get("id") and v.get("season")]
        if latest:  # «el último episodio de X»: el más reciente que ya salió
            today = time.strftime("%Y-%m-%d")
            aired = [v for v in videos if str(v.get("released") or "")[:10] <= today] or videos
            last = max(aired, key=lambda v: (v.get("season") or 0, v.get("episode") or 0), default=None)
            season, episode = (last.get("season"), last.get("episode")) if last else (0, 0)
        video = next((v for v in videos if v.get("season") == season and v.get("episode") == episode), None)
        name = meta.get("name") or match["name"]
        if video is None:
            return VoiceResult(f"{name} no tiene temporada {season} episodio {episode}.", ok=False)
        kwargs, how = self._media_request(slots)
        label = f"{name} · T{season} E{episode}"
        # Aquí ya se buscó la serie en Cinemeta (unos segundos): se espera menos a la fuente.
        problem = self.catalog.watch.play_title("series", match["id"], video["id"], label, wait=VOICE_WAIT - 2, **kwargs)
        if problem:
            return VoiceResult(problem, ok=False)
        memo = f" {name} quedará{how}." if kwargs.get("remember") else ""
        return VoiceResult(f"Poniendo {name}, temporada {season}, episodio {episode}{how}.{memo}")
