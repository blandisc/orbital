"""Traduce comandos de voz (intents de Alexa o texto libre) en acciones del catálogo."""

from __future__ import annotations

import logging
import re
from dataclasses import dataclass, field

from .catalog import Catalog, normalize

log = logging.getLogger(__name__)

DIRECTIONS = {
    "arriba": "up", "abajo": "down", "izquierda": "left", "derecha": "right",
    "seleccionar": "select", "selecciona": "select", "aceptar": "select", "ok": "select",
    "atras": "back", "regresar": "back", "volver": "back", "inicio": "home",
    "up": "up", "down": "down", "left": "left", "right": "right",
    "select": "select", "back": "back", "home": "home",
}


@dataclass
class VoiceResult:
    speech: str
    ok: bool = True
    # Evento opcional que se reenvía a la interfaz (toast, navegación...).
    events: list[dict] = field(default_factory=list)

    def as_dict(self) -> dict:
        return {"ok": self.ok, "speech": self.speech}


# Patrones para texto libre en español (también sirven para Home Assistant, atajos, etc.).
_TEXT_RULES: list[tuple[re.Pattern, str, str | None]] = [
    (re.compile(r"^(?:busca|buscar|pon|reproduce)\s+(?P<v>.+?)\s+en\s+stremio$"), "SearchMediaIntent", "query"),
    (re.compile(r"^(?:abre|abrir|inicia|lanza)\s+stremio$"), "OpenStremioIntent", None),
    (re.compile(r"^(?:abre|abrir)\s+(?:steam|big picture)$"), "OpenSteamIntent", None),
    (re.compile(r"^(?:cierra|cerrar|salir de)\s+(?:el\s+)?(?:juego|aplicacion|app)$"), "CloseGameIntent", None),
    (re.compile(r"^(?:que|que estoy)\s+(?:se esta jugando|jugando|esta abierto)$"), "WhatsPlayingIntent", None),
    (re.compile(r"^(?:sal|salir|ve|ir|vete)\s+al\s+escritorio$|^(?:cierra|cerrar)\s+orbital$"), "ExitToDesktopIntent", None),
    (re.compile(r"^(?:abre|abrir|vuelve a|volver a|regresa a)\s+(?:la\s+consola|orbital)$"), "OpenOrbitalIntent", None),
    (re.compile(r"^(?:ve|ir|mueve(?:te)?)\s+(?:a\s+(?:la\s+)?)?(?P<v>\w+)$"), "NavigateIntent", "direction"),
    (re.compile(r"^(?:abre|abrir|juega|jugar|inicia|lanza|pon)\s+(?P<v>.+)$"), "LaunchGameIntent", "game"),
]


def parse_text(text: str) -> tuple[str, dict[str, str]] | None:
    clean = normalize(text)
    for pattern, intent, slot in _TEXT_RULES:
        m = pattern.match(clean)
        if m:
            return intent, ({slot: m.group("v")} if slot else {})
    return None


class VoiceController:
    def __init__(self, catalog: Catalog, kiosk=None) -> None:
        self.catalog = catalog
        self.kiosk = kiosk  # KioskWindow, o None si la interfaz no la abrió Orbital

    def handle_text(self, text: str) -> VoiceResult:
        parsed = parse_text(text)
        if not parsed:
            return VoiceResult("No entendí el comando.", ok=False)
        return self.handle_intent(*parsed)

    def handle_intent(self, intent: str, slots: dict[str, str] | None = None) -> VoiceResult:
        slots = {k: v for k, v in (slots or {}).items() if v}
        handler = getattr(self, "_" + re.sub(r"(?<!^)(?=[A-Z])", "_", intent).lower(), None)
        if handler is None:
            return VoiceResult("Ese comando todavía no está disponible.", ok=False)
        try:
            result = handler(slots)
        except Exception:  # noqa: BLE001 - el usuario oye un error amable, el log tiene el detalle
            log.exception("Error manejando %s", intent)
            return VoiceResult("Algo salió mal al ejecutar el comando.", ok=False)
        if not result.events:
            result.events.append({"type": "toast", "message": result.speech, "ok": result.ok})
        return result

    # --- intents -------------------------------------------------------------
    def _launch_game_intent(self, slots: dict) -> VoiceResult:
        name = slots.get("game", "")
        if not name:
            return VoiceResult("¿Qué juego quieres abrir?", ok=False)
        item = self.catalog.find(name)
        if item is None:
            return VoiceResult(f"No encontré {name} en tu biblioteca.", ok=False)
        self.catalog.launch(item.id)
        return VoiceResult(f"Abriendo {item.title}.")

    def _open_stremio_intent(self, slots: dict) -> VoiceResult:
        self.catalog.launch("media:stremio")
        return VoiceResult("Abriendo Stremio.")

    def _search_media_intent(self, slots: dict) -> VoiceResult:
        query = slots.get("query", "")
        if not query:
            return VoiceResult("¿Qué quieres ver?", ok=False)
        self.catalog.search_media(query)
        return VoiceResult(f"Buscando {query} en Stremio.")

    def _open_steam_intent(self, slots: dict) -> VoiceResult:
        if self.catalog.get("steam:bigpicture") is None:
            return VoiceResult("No encontré Steam en este equipo.", ok=False)
        self.catalog.launch("steam:bigpicture")
        return VoiceResult("Abriendo Steam.")

    def _close_game_intent(self, slots: dict) -> VoiceResult:
        status = self.catalog.launcher.status()
        if self.catalog.launcher.stop():
            return VoiceResult(f"Cerré {status['title']}." if status else "Listo, lo cerré.")
        if status:
            # Lo abrió Steam/Stremio vía URI: no es nuestro proceso, no lo matamos a ciegas.
            return VoiceResult(f"{status['title']} lo maneja otra aplicación; ciérralo desde ahí.", ok=False)
        return VoiceResult("No hay nada abierto.", ok=False)

    def _whats_playing_intent(self, slots: dict) -> VoiceResult:
        status = self.catalog.launcher.status()
        return VoiceResult(f"Está abierto {status['title']}." if status else "No hay nada abierto.")

    def _exit_to_desktop_intent(self, slots: dict) -> VoiceResult:
        if self.kiosk is None or not self.kiosk.is_open:
            return VoiceResult("La consola no está abierta en pantalla.", ok=False)
        self.kiosk.close()
        return VoiceResult("Listo, saliste al escritorio. Di abre la consola para volver.")

    def _open_orbital_intent(self, slots: dict) -> VoiceResult:
        if self.kiosk is None:
            return VoiceResult("No puedo abrir la pantalla de la consola desde aquí.", ok=False)
        self.kiosk.open()
        return VoiceResult("Abriendo la consola.")

    def _navigate_intent(self, slots: dict) -> VoiceResult:
        direction = DIRECTIONS.get(normalize(slots.get("direction", "")))
        if not direction:
            return VoiceResult("No entendí hacia dónde moverme.", ok=False)
        return VoiceResult("Listo.", events=[{"type": "navigate", "direction": direction}])
