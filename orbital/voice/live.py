"""Voz: la TV en vivo (poner un canal por nombre o número, cambiar de canal, la guía)."""

from __future__ import annotations

import re
import threading

from ..catalog import normalize
from .base import _Base
from .parsing import CHANNEL_PREVIOUS, MOMENT_SAY, NO_TOAST, VoiceResult, words_to_numbers


class _Live(_Base):
    """La TV en vivo por voz."""

    @staticmethod
    def _channel_key(name: str) -> str:
        """«ADN 40 (720p) [Not 24/7]» → «adn 40»; «Azteca Uno» → «azteca 1» (Alexa dice los números con letra o cifra)."""
        plain = re.sub(r"\s*[\(\[][^\)\]]*[\)\]]", "", str(name or ""))
        return words_to_numbers(normalize(plain)).strip()

    def _find_own(self, said: str, asked_channel: bool):
        """Un canal de Orbital (synthetic.py) por cómo se pide: «el canal de los Simpson», «Los Simpson 24/7». Solo si se
        pidió un canal (`asked_channel`, o lo dice): «pon los Simpson» sigue siendo la serie."""
        own = getattr(getattr(self.catalog, "tv", None), "synthetic", None)
        if own is None:
            return None
        key = words_to_numbers(normalize(said)).strip()
        asked_channel = asked_channel or "canal" in key.split() or bool(re.search(r"\b24\s*7\b", key))
        key = re.sub(r"\s*\b24\s*7\b\s*", " ", key).strip()
        key = re.sub(r"^(?:el\s+)?(?:canal\s+)?(?:de\s+)?", "", key).strip()
        if not asked_channel or not key:
            return None
        return next((c for c in own.channels if key in {normalize(a) for a in (*c.aliases, c.name)}), None)

    def _find_channel(self, said: str, asked_channel: bool = False):
        """El canal de TV en vivo con ese nombre (o «canal 5» si no hay uno que se llame así: su número en Orbital)."""
        tv = getattr(self.catalog, "tv", None)
        if tv is None:
            return None
        if (own := self._find_own(said, asked_channel)) is not None:
            return own
        key = self._channel_key(said).removeprefix("el ")
        bare = key.removeprefix("canal ")  # «canal 5» y «5» (de «pon el canal {channel}») buscan lo mismo
        if not key:
            return None
        channels = tv.visible()
        # Los que ya fallaron, al final: se prefiere uno que abre.
        ranked = sorted(channels, key=lambda c: tv.store.verified(c.id) is False)
        exact = [c for c in ranked if self._channel_key(c.name) in (key, bare, f"canal {bare}")]
        if exact:
            return exact[0]
        if bare.isdigit():  # «pon el canal 12» (sin uno que se llame así): el número que tiene en Orbital
            return next((c for c in channels if tv.store.number(c.id) == int(bare)), None)
        # «pon Azteca Deportes»: el nombre empieza así (solo si es uno, para no adivinar)
        starts = [c for c in ranked if self._channel_key(c.name).startswith(key + " ")]
        return starts[0] if len({self._channel_key(c.name) for c in starts}) == 1 else None

    def _play_channel(self, channel) -> VoiceResult:
        try:
            result = self.catalog.tv.play(channel.id)
        except (LookupError, OSError) as exc:
            return VoiceResult(str(exc) or f"No pude poner {channel.name}.", ok=False)
        if self.kiosk is not None and result.get("reveal") is False and not result.get("tuned"):
            self.kiosk.open()
        name = re.sub(r"\s*[\(\[][^\)\]]*[\)\]]", "", channel.name).strip()
        return VoiceResult(f"Poniendo {name}.")

    def _live_tv_intent(self, slots: dict) -> VoiceResult:
        said = slots.get("channel", "")
        if slots.get("category") and not said:  # «pon las noticias»: el primero de esa categoría que abre
            tv = getattr(self.catalog, "tv", None)
            wanted = normalize(slots["category"])
            found = [c for c in (tv.visible() if tv else []) if any(wanted in normalize(cat) for cat in c.categories)]
            found.sort(key=lambda c: tv.store.verified(c.id) is False)
            if found:
                return self._play_channel(found[0])
            return VoiceResult(f"No encontré canales de {slots['category']}.", ok=False,
                               events=[self._show_view({"seccion": "tv"}, "TV en vivo")])
        if not said:  # «pon la tele»: la sección de canales
            return VoiceResult("Abriendo la TV en vivo.", events=[self._show_view({"seccion": "tv"}, "TV en vivo")])
        channel = self._find_channel(said, asked_channel=True)
        if channel is None:
            return VoiceResult(f"No encontré el canal {said}. Te dejo la lista de canales.",
                               ok=False, events=[self._show_view({"seccion": "tv"}, "TV en vivo")])
        return self._play_channel(channel)

    def _channel_step_intent(self, slots: dict) -> VoiceResult:
        tv = self.catalog.tv
        on_air = tv.playing()
        segment = getattr(self.catalog.watch.player, "segment", None)
        if on_air is None or segment is None:
            return VoiceResult("No hay un canal al aire. Di, por ejemplo: pon el canal ADN 40.", ok=False)
        step = normalize(slots.get("step", "next"))
        delta = -1 if step in CHANNEL_PREVIOUS else 1
        category, channels = tv.zap_list(segment.meta.get("list"))
        ids = [c.id for c in channels]
        if not ids:
            return VoiceResult("No hay más canales en esta lista.", ok=False, events=[NO_TOAST])
        here = ids.index(on_air) if on_air in ids else -1
        target = channels[(here + delta) % len(ids)]
        if not tv.tune(segment.meta, target.id, category):
            return VoiceResult(f"No pude cambiar a {target.name}.", ok=False, events=[NO_TOAST])
        return VoiceResult(f"Canal {target.name}.", events=[NO_TOAST])

    @staticmethod
    def _within(seconds: float, load):
        """Lo que tarde menos de `seconds` (Alexa corta a los ~8 s); si no, None y sigue en segundo plano."""
        box: dict = {}

        def run() -> None:
            try:
                box["value"] = load()
            except Exception as exc:  # noqa: BLE001 - quien llama decide qué decir
                box["error"] = exc

        worker = threading.Thread(target=run, daemon=True)
        worker.start()
        worker.join(seconds)
        if "error" in box:
            raise box["error"]
        return box.get("value")

    def _live_on_air(self) -> bool:
        tv = getattr(self.catalog, "tv", None)
        try:
            return bool(tv is not None and self.catalog.player.playing and tv.playing())
        except Exception:  # noqa: BLE001 - sin TV en vivo, lo de siempre
            return False

    def _guide_intent(self, slots: dict) -> VoiceResult:
        """«¿Qué puedo decir?»: la guía en la tele y, si preguntó el iPhone, la suya (`guide`). Dice tres frases de ahora."""
        if self.kiosk is not None:
            self.kiosk.open()
        first, second, third = MOMENT_SAY[self.moment()]
        return VoiceResult(f"Te enseño lo que puedes decir. Por ejemplo: {first}, {second} o {third}.", guide=True,
                           events=[{"type": "open-guide"}])
