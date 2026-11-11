"""Voz: juegos, Orbital y la tele (abrir y cerrar juegos, navegar, brillo, capturas, apagar)."""

from __future__ import annotations

import re
from difflib import SequenceMatcher

from ..catalog import normalize
from ..library import cinemeta
from .live import _Live
from .parsing import (
    CLOUD,
    DIRECTIONS,
    SECTION_NAMES,
    SECTIONS,
    VOLUME_DOWN,
    VoiceResult,
    episode_request,
    kind_hint,
    spoken_number,
)


class _System(_Live):
    """Juegos, Orbital y la tele por voz."""

    def _launch_game_intent(self, slots: dict) -> VoiceResult:
        name = slots.get("game", "")
        if not name:
            return VoiceResult("¿Qué juego quieres abrir?", ok=False)
        name, media = self._media_options(name, slots)  # Alexa manda «Los Simpson en latino» en el mismo slot
        if (episode := episode_request(name)) is not None:  # "pon Los Simpson temporada 5 episodio 3"
            return self._watch_episode_intent({**media, **episode})
        name, hinted = kind_hint(name)
        kind = slots.get("kind") or hinted
        if kind in ("movie", "series") or media:  # «pon la película Dune», «pon Dune en inglés»: ni juegos ni apps
            return self._search_media_intent({"query": name, "kind": kind if kind in ("movie", "series") else None, **media})
        if (vague := self._vague(name)) is not None:  # «pon la telenovela», «pon una película»
            return vague
        if (section := self._section(name)) is not None:  # «abre Para ti», «abre la tele»
            return section
        cloud = CLOUD.search(normalize(name))
        if cloud:  # "abre Fortnite en la nube / en GeForce NOW"
            name = normalize(name)[:cloud.start()]
            item = self.catalog.find(name, source="geforcenow")
            if item is None:
                return VoiceResult(f"{name} no está en tus juegos de GeForce NOW.", ok=False)
            self.catalog.sessions.launch(item.id)
            return VoiceResult(f"Abriendo {item.title} en GeForce NOW.")
        name, runner = self._split_runner(name)
        # Primero juegos y apps; si no hay, algo de tu biblioteca de Stremio ("abre The Office").
        item = (self.catalog.find(name, exclude_source=("stremio", "cinemeta"))
                or (None if kind == "game" else self.catalog.find(name, source="stremio")))
        if item is None and kind == "game":  # «abre el juego X»: no se pone una película que se llame parecido
            return VoiceResult(f"No encontré el juego {name}.", ok=False)
        if item is None:
            # Ni juego ni biblioteca: ¿es una película o serie? ("abre The Office")
            if (channel := self._find_channel(name)) is not None:  # «abre Bandamax»: un canal de TV en vivo
                return self._play_channel(channel)
            try:
                watch = self._watch_exact(name)
            except cinemeta.CinemetaError:
                watch = None
            if watch:
                return watch
            near = self._closest_title(name)
            if near:
                return VoiceResult(f"No encontré {name}. ¿Quisiste decir {near}? Di: abre {near}.", ok=False)
            return VoiceResult(f"No encontré {name}. Di busca {name} para buscarlo.", ok=False)
        runner_id = None
        if runner:
            match = next((r for r in item.runners if normalize(r.name) == runner), None)
            if match is None:
                return VoiceResult(f"{item.title} no se puede abrir con {runner}.", ok=False)
            runner_id = match.id
        if item.source == "stremio":
            return self._watch_item(item)
        if item.source == "search":  # «abre buscar»: la búsqueda de Orbital (no se «lanza»; cerraba el juego)
            return VoiceResult("Abriendo la búsqueda.", events=[self._show_view({"buscar": ""}, "Buscar")])
        self.catalog.sessions.launch(item.id, runner_id)
        speech = f"Abriendo {item.title} con {runner}." if runner else f"Abriendo {item.title}."
        said, title = normalize(name), normalize(item.title)
        if said and said not in title:  # se parecía, no era igual («jades» → Hades): que se vea qué oyó, y deshacerlo
            return VoiceResult(speech, events=[{"type": "toast", "message": f"Abriendo {item.title}", "detail": f"Entendí «{name}»",
                                                "ok": True, "voice": True, "action": {"type": "voice-undo", "query": name}}])
        return VoiceResult(speech)

    def _closest_title(self, said: str) -> str | None:
        """El juego o app de tu biblioteca que más se parece a lo dicho («jades» → Hades), o None."""
        target = normalize(said)
        best, score = None, 0.0
        for item in self.catalog.items():
            if item.source in ("stremio", "cinemeta", "search", "genre", "collection"):
                continue
            ratio = SequenceMatcher(None, normalize(item.title), target).ratio()
            if ratio > score:
                best, score = item.title, ratio
        return best if score >= .72 else None

    def _split_runner(self, name: str) -> tuple[str, str | None]:
        """ "zelda con eden" -> ("zelda", "eden") si "eden" es un emulador conocido.

        Alexa no permite otro slot junto a una búsqueda libre, así que el emulador viene
        dentro del mismo texto y lo separamos aquí.
        """
        match = re.match(r"^(?P<game>.+?)\s+(?:con|en)\s+(?P<runner>[\w-]+)$", normalize(name))
        if not match:
            return name, None
        known = {normalize(r.name) for i in self.catalog.items() for r in i.runners}
        runner = match.group("runner")
        return (match.group("game"), runner) if runner in known else (name, None)

    def _open_steam_intent(self, slots: dict) -> VoiceResult:
        if self.catalog.get("steam:bigpicture") is None:
            return VoiceResult("No encontré Steam en este equipo.", ok=False)
        self.catalog.sessions.launch("steam:bigpicture")
        return VoiceResult("Abriendo Steam.")

    def _close_game_intent(self, slots: dict) -> VoiceResult:
        status = self.catalog.launcher.status()
        if self.catalog.player.playing:  # «cierra el video»: se cierra bien (lo visto se guarda)
            title = getattr(self.catalog.player.current, "title", "") or "el video"
            self.catalog.player.stop()
            return VoiceResult(f"Cerré {title}. Guardé dónde ibas.")
        if slots.get("only") == "video":  # «apaga»: nunca cierra un juego (ni apaga la consola) sin decirlo claro
            if status:
                return VoiceResult(f"No hay un video abierto. Para cerrar {status['title']}, di: cierra el juego.", ok=False)
            return VoiceResult("No hay un video abierto.", ok=False)
        if self.catalog.launcher.stop():
            return VoiceResult(f"Cerré {status['title']}." if status else "Listo, lo cerré.")
        if status:
            # Lo abrió Steam/Stremio vía URI: no es nuestro proceso, no lo matamos a ciegas.
            return VoiceResult(f"{status['title']} lo maneja otra aplicación; ciérralo desde ahí.", ok=False)
        return VoiceResult("No hay nada abierto.", ok=False)

    def _whats_playing_intent(self, slots: dict) -> VoiceResult:
        if self.catalog.player.playing and (current := self.catalog.player.current) is not None:
            return VoiceResult(f"Estás viendo {current.title}.")
        status = self.catalog.launcher.status()
        return VoiceResult(f"Está abierto {status['title']}." if status else "No hay nada abierto.")

    def _exit_to_desktop_intent(self, slots: dict) -> VoiceResult:
        if self.kiosk is None or not self.kiosk.is_open:
            return VoiceResult("La consola no está abierta en pantalla.", ok=False)
        self.kiosk.close()
        return VoiceResult("Listo, saliste al escritorio. Di abre la consola para volver.")

    def _open_orbital_intent(self, slots: dict) -> VoiceResult:
        if self.tv is not None and self.tv.enabled:
            self.tv.turn_on_soon()  # en segundo plano: prender tarda más de lo que Alexa espera
        if self.kiosk is None:
            return VoiceResult("No puedo abrir la pantalla de la consola desde aquí.", ok=False)
        self.kiosk.open()
        if self.tv is not None and self.tv.enabled:
            return VoiceResult("Prendiendo la tele en Orbital.", events=[self._playing_event("Prendiendo la tele", "home")])
        return VoiceResult("Abriendo la consola.", events=[self._playing_event("Abriendo la consola", "home")])

    def _navigate_intent(self, slots: dict) -> VoiceResult:
        said = normalize(slots.get("direction", ""))
        if (section := self._section(said)) is not None:  # «ve a juegos», «ve a Para ti»
            return section
        direction = DIRECTIONS.get(said) or DIRECTIONS.get(said.removeprefix("la ").removeprefix("el "))
        if not direction:
            return VoiceResult("No entendí a dónde ir. Puedes decir: ve a juegos, ve a Para ti o ve a la tele.", ok=False)
        return VoiceResult("Listo.", events=[{"type": "navigate", "direction": direction}])

    # --- secciones, TV en vivo y Para ti ------------------------------------------------------
    def _section(self, said: str) -> VoiceResult | None:
        """«Para ti», «la tele», «juegos»: abre esa sección. None si no es el nombre de una."""
        key = normalize(said).removeprefix("la seccion de ").removeprefix("seccion de ")
        section = SECTIONS.get(key)
        if section is None:
            return None
        name = SECTION_NAMES[section]
        return VoiceResult(f"Abriendo {name}.", events=[self._show_view({"seccion": section}, name[:1].upper() + name[1:])])

    def _brightness_intent(self, slots: dict) -> VoiceResult:
        from .. import quick

        current = quick.brightness()
        if current is None:
            return VoiceResult("No puedo cambiar el brillo de esta pantalla.", ok=False)
        level = spoken_number(slots.get("level")) if slots.get("level") else None
        if level is None:
            amount = spoken_number(slots.get("amount")) if slots.get("amount") else None
            step = 15 if amount is None else min(100, abs(amount))
            level = current + (-step if normalize(slots.get("brightness", "")) in VOLUME_DOWN else step)
        after = quick.set_brightness(int(level))
        return VoiceResult(f"Brillo en {after if after is not None else current} por ciento.")

    def _capture_intent(self, slots: dict) -> VoiceResult:
        from .. import capture

        status = self.catalog.launcher.status()
        event = capture.take_and_describe(status["title"] if status else "")
        return VoiceResult("Listo, guardé la captura." if event.get("ok", True) else event["message"],
                           ok=event.get("ok", True), events=[event])

    def _turn_off_tv_intent(self, slots: dict) -> VoiceResult:
        """«Apaga la tele»: guarda dónde ibas, cierra el video y apaga la tele (nunca cierra un juego ni apaga la consola)."""
        closed = ""
        if self.catalog.player.playing:
            title = getattr(self.catalog.player.current, "title", "") or "el video"
            self.catalog.player.stop()
            closed = f"Guardé dónde ibas en {title}. "
        if self.tv is None or not getattr(self.tv, "enabled", False):
            return VoiceResult(f"{closed}Orbital no tiene una tele conectada para apagarla.", ok=bool(closed))
        self.tv.turn_off_soon()
        return VoiceResult(f"{closed}Apagando la tele.")
