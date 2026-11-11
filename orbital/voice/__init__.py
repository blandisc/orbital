"""Traduce comandos de voz (intents de Alexa o texto libre) en acciones del catálogo.

Es un paquete: `parsing` (de lo dicho a un intent con sus datos: las reglas de texto libre, los números dichos, los
idiomas) y una pieza por tema de `VoiceController` (live: TV en vivo; system: juegos, Orbital y la tele; media: buscar y
poner películas y series; controls: lo que se hace con un video puesto). `VoiceController`, aquí, es la fachada: arma el
estado y reparte cada intent a su manejador, con la misma API de siempre. Las piezas se heredan en cadena (cada una ve
las de antes) solo para que los tipos se revisen; lo que comparten está descrito en base.py.
"""

from __future__ import annotations

import re

from ..catalog import Catalog, normalize
from .controls import _Controls
from .parsing import _ADDRESS as _ADDRESS
from .parsing import _ALWAYS_AFTER as _ALWAYS_AFTER
from .parsing import _ALWAYS_BEFORE as _ALWAYS_BEFORE
from .parsing import _CLITIC_VERBS as _CLITIC_VERBS
from .parsing import _EPISODE as _EPISODE
from .parsing import _EPISODE_FORMS as _EPISODE_FORMS
from .parsing import _EPISODE_ONLY as _EPISODE_ONLY
from .parsing import _INVOKED as _INVOKED
from .parsing import _INVOKED_SLOT as _INVOKED_SLOT
from .parsing import _KIND_OF as _KIND_OF
from .parsing import _KIND_WORDS as _KIND_WORDS
from .parsing import _LANGS as _LANGS
from .parsing import _LEAD_IN as _LEAD_IN
from .parsing import _ORD as _ORD
from .parsing import _ORDINALS as _ORDINALS
from .parsing import _POLITE as _POLITE
from .parsing import _SAY_AS as _SAY_AS
from .parsing import _TAIL as _TAIL
from .parsing import _TENS as _TENS
from .parsing import _TEXT_RULES as _TEXT_RULES
from .parsing import _TITLE_TAIL as _TITLE_TAIL
from .parsing import _TU as _TU
from .parsing import _UNITS as _UNITS
from .parsing import _V as _V
from .parsing import _WHERE as _WHERE
from .parsing import CHANNEL_NEXT as CHANNEL_NEXT
from .parsing import CHANNEL_PREVIOUS as CHANNEL_PREVIOUS
from .parsing import CLOUD as CLOUD
from .parsing import DIRECTIONS as DIRECTIONS
from .parsing import GENRE_NAMES as GENRE_NAMES
from .parsing import GENRES as GENRES
from .parsing import LANGUAGE_NAMES as LANGUAGE_NAMES
from .parsing import LANGUAGES as LANGUAGES
from .parsing import MAX_SEEK as MAX_SEEK
from .parsing import MEDIA_OPTIONS as MEDIA_OPTIONS
from .parsing import MOMENT_SAY as MOMENT_SAY
from .parsing import NEXT_SAY as NEXT_SAY
from .parsing import NO_TOAST as NO_TOAST
from .parsing import NUMERIC as NUMERIC
from .parsing import OTHER_SAY as OTHER_SAY
from .parsing import OTHER_WINDOW as OTHER_WINDOW
from .parsing import QUICK_LOOKUP as QUICK_LOOKUP
from .parsing import SECTION_NAMES as SECTION_NAMES
from .parsing import SECTIONS as SECTIONS
from .parsing import SEEK_BACK as SEEK_BACK
from .parsing import THE_USUAL as THE_USUAL
from .parsing import VAGUE_MEDIA as VAGUE_MEDIA
from .parsing import VOICE_WAIT as VOICE_WAIT
from .parsing import VOLUME_DOWN as VOLUME_DOWN
from .parsing import WAKES as WAKES
from .parsing import VoiceResult as VoiceResult
from .parsing import _media_tail as _media_tail
from .parsing import _parse as _parse
from .parsing import _plain as _plain
from .parsing import _title_slots as _title_slots
from .parsing import always_said as always_said
from .parsing import episode_request as episode_request
from .parsing import kind_hint as kind_hint
from .parsing import log as log
from .parsing import parse_text as parse_text
from .parsing import slot_text as slot_text
from .parsing import split_language as split_language
from .parsing import spoken_list as spoken_list
from .parsing import spoken_number as spoken_number
from .parsing import tidy as tidy
from .parsing import title_tail as title_tail
from .parsing import upcoming_speech as upcoming_speech
from .parsing import words_to_numbers as words_to_numbers


class VoiceController(_Controls):
    def __init__(self, catalog: Catalog, kiosk=None, tv=None) -> None:
        self.catalog = catalog
        self.kiosk = kiosk  # KioskWindow, o None si la interfaz no la abrió Orbital
        self.tv = tv  # roku.RokuTv: «abre Orbital» prende la tele y la pone en la entrada de Orbital
        self._candidates: list[dict] = []  # lo que encontró la última búsqueda de un título (para «otro»)
        self._last: dict | None = None  # lo último que se puso por nombre: {at, query, options, seen, candidates}

    def handle_text(self, text: str) -> VoiceResult:
        heard = tidy(normalize(text))
        parsed = parse_text(text)
        if not parsed:
            # Decir qué se oyó ayuda más que «no entendí» a secas (Siri a veces transcribe otra cosa).
            said = f" «{heard}»" if heard and len(heard) <= 60 else ""
            speech = f"No entendí{said}. Prueba con: pon Dune, pausa o sube el volumen."
            toast = {"type": "toast", "message": f"No entendí{said}", "detail": "Prueba: «pon Dune», «pausa», «sube el volumen»",
                     "ok": False, "tone": "warn", "voice": True, "action": {"type": "voice-guide"}}
            return VoiceResult(speech, ok=False, heard=heard, events=[toast])
        intent, slots = parsed
        if intent == "SearchMediaIntent" and re.match(r"(?:que\s+)?(?:busca|busque|buscar)\b", heard):
            slots = {**slots, "browse": "1"}  # «busca Dune»: pediste buscar, así que con varias se pregunta cuál
        result = self.handle_intent(intent, slots)
        result.heard, result.intent = heard, intent
        return result

    def handle_intent(self, intent: str, slots: dict[str, str] | None = None) -> VoiceResult:
        slots = {k: slot_text(v) if isinstance(v, str) else v for k, v in (slots.items() if isinstance(slots, dict) else ()) if v}
        slots = {k: v for k, v in slots.items() if v}
        log.info("Voz: %s %s", intent, slots)
        if intent in WAKES or (intent == "ResumeIntent" and not self.catalog.player.playing):
            self._wake_tv()
        # Solo los manejadores de intents (`_algo_intent`): el nombre viene de fuera (Alexa, el túnel).
        name = "_" + re.sub(r"(?<!^)(?=[A-Z])", "_", str(intent or "")).lower()
        handler = getattr(self, name, None) if name.endswith("_intent") and name.isidentifier() else None
        if handler is None:
            return VoiceResult("Ese comando todavía no está disponible.", ok=False)
        try:
            result = handler(slots)
        except Exception:  # noqa: BLE001 - el usuario oye un error amable, el log tiene el detalle
            log.exception("Error manejando %s", intent)
            return VoiceResult("Algo salió mal al ejecutar el comando.", ok=False)
        if not isinstance(result, VoiceResult):
            return VoiceResult("Algo salió mal al ejecutar el comando.", ok=False)
        if not result.events:
            result.events.append({"type": "toast", "message": result.speech, "ok": result.ok, "voice": True})
        elif NO_TOAST in result.events and not result.ok and self.catalog.player.playing:
            # El video está encima: un "no pude" se ve en el reproductor (antes se perdía).
            self.catalog.player.toast(result.speech, 4)
        return result

    def _wake_tv(self) -> None:
        """La tele prendida y en la entrada de Orbital (en segundo plano: Alexa no espera). Si ya lo está, no hace nada."""
        if self.tv is not None and getattr(self.tv, "enabled", False):
            self.tv.turn_on_soon()

    def moment(self) -> str:
        """Qué hay ahora: «live» (un canal al aire), «series» o «movie» (el reproductor) u «home» (nada puesto)."""
        if self._live_on_air():
            return "live"
        if self.catalog.player.playing:
            meta = getattr(self.catalog.player.current, "meta", None) or {}
            return "series" if isinstance(meta, dict) and meta.get("kind") == "series" else "movie"
        return "home"

    def hints(self) -> dict:
        """Las tres frases de este momento (las mismas que la tele enseña en el aviso): la pista del iPhone."""
        moment = self.moment()
        return {"moment": moment, "hints": list(MOMENT_SAY[moment])}

    def _tips_on(self) -> bool:
        state = getattr(self.catalog, "state", None)
        try:
            return state.settings().get("voice_tips", True) is not False if state is not None else True
        except Exception:  # noqa: BLE001 - sin ajustes, lo de siempre
            return True

    def _playing_event(self, message: str, moment: str) -> dict:
        """El aviso de la tele cuando algo se puso: qué, y en el segundo renglón lo que puedes decir en este momento
        (solo con «Frases en pantalla» en Sí)."""
        event = {"type": "toast", "message": message, "ok": True, "voice": True}
        if self._tips_on() and moment in NEXT_SAY:
            first, second = NEXT_SAY[moment]
            event["detail"] = f"Di «{first}» o «{second}»"
        return event

    # --- intents -------------------------------------------------------------
    def _fallback_intent(self, slots: dict) -> VoiceResult:
        """Alexa no acomodó lo dicho en ningún intent (y no manda el texto): la skill lo avisa para que quede en voz.log y
        en la tele (antes contestaba sola y no quedaba rastro de qué falló)."""
        return VoiceResult("No entendí eso. Prueba con: pausa, pon Dune o sube el volumen.", ok=False,
                           events=[{"type": "toast", "message": "Alexa no entendió", "detail": "Prueba: «pon Dune», «pausa»",
                                    "ok": False, "tone": "warn", "voice": True, "action": {"type": "voice-guide"}}])
