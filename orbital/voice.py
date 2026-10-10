"""Traduce comandos de voz (intents de Alexa o texto libre) en acciones del catálogo."""

from __future__ import annotations

import logging
import re
from dataclasses import dataclass, field

from .catalog import Catalog, normalize
from .library import cinemeta

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
# Imperativo ("abre"), subjuntivo ("pídele que abra") e infinitivo ("usa mi consola para abrir").
_V = {
    "open": r"(?:abre|abra|abrir|inicia|inicie|iniciar|lanza|lance|lanzar)",
    "play": r"(?:abre|abra|abrir|juega|juegue|jugar|inicia|inicie|iniciar|lanza|lance|lanzar|pon|ponga|poner)",
    "search": r"(?:busca|busque|buscar|pon|ponga|poner|reproduce|reproduzca|reproducir)",
    "close": r"(?:cierra|cierre|cerrar|sal|salga|salir)",
    "continue": r"(?:sigue|siga|seguir|continua|continue|continuar)",
    "go": r"(?:ve|vaya|ir|vete|sal|salga|salir|muestra|muestre|mostrar)",
    "move": r"(?:ve|vaya|ir|mueve(?:te)?|mueva(?:se)?|se mueva|moverse)",
    "back": r"(?:vuelve|vuelva|volver|regresa|regrese|regresar)",
}

_TEXT_RULES: list[tuple[re.Pattern, str, str | None]] = [
    (re.compile(rf"^{_V['search']}\s+(?P<v>.+?)\s+en\s+stremio$"), "SearchMediaIntent", "query"),
    (re.compile(rf"^{_V['continue']}(?:\s+viendo)?(?:\s+(?P<v>.+))?$"), "ContinueWatchingIntent", "show"),
    # "quiero ver dune", "reproduce the office": como en Alexa.
    (re.compile(r"^(?:quiero ver|reproduce|reproduzca|reproducir)\s+(?P<v>.+)$"), "SearchMediaIntent", "query"),
    (re.compile(rf"^{_V['open']}\s+stremio$"), "OpenStremioIntent", None),
    (re.compile(rf"^{_V['open']}\s+(?:steam|big picture)$"), "OpenSteamIntent", None),
    (re.compile(rf"^{_V['close']}\s+(?:de\s+)?(?:el\s+|la\s+)?(?:juego|aplicacion|app)$"), "CloseGameIntent", None),
    (re.compile(r"^(?:que|que estoy)\s+(?:se esta jugando|jugando|esta abierto|hay abierto)$"), "WhatsPlayingIntent", None),
    (re.compile(rf"^{_V['go']}\s+(?:al\s+|el\s+)escritorio$|^{_V['close']}\s+orbital$"), "ExitToDesktopIntent", None),
    (re.compile(rf"^(?:{_V['open']}|{_V['back']}\s+a|{_V['go']})\s+(?:la\s+consola|orbital)$"), "OpenOrbitalIntent", None),
    (re.compile(rf"^{_V['move']}\s+(?:a\s+(?:la\s+)?)?(?P<v>\w+)$"), "NavigateIntent", "direction"),
    (re.compile(rf"^{_V['play']}\s+(?:el\s+juego\s+)?(?P<v>.+)$"), "LaunchGameIntent", "game"),
]


def parse_text(text: str) -> tuple[str, dict[str, str]] | None:
    clean = normalize(text)
    for pattern, intent, slot in _TEXT_RULES:
        m = pattern.match(clean)
        if m:
            return intent, ({slot: m.group("v")} if slot and m.group("v") else {})
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
        name, runner = self._split_runner(name)
        # Primero juegos y apps; si no hay, algo de tu biblioteca de Stremio ("abre The Office").
        item = (self.catalog.find(name, exclude_source=("stremio", "cinemeta"))
                or self.catalog.find(name, source="stremio"))
        if item is None:
            # Ni juego ni biblioteca: ¿es una película o serie? ("abre The Office")
            try:
                watch = self._watch_exact(name)
            except cinemeta.CinemetaError:
                watch = None
            return watch or VoiceResult(f"No encontré {name} en tu biblioteca.", ok=False)
        runner_id = None
        if runner:
            match = next((r for r in item.runners if normalize(r.name) == runner), None)
            if match is None:
                return VoiceResult(f"{item.title} no se puede abrir con {runner}.", ok=False)
            runner_id = match.id
        self.catalog.launch(item.id, runner_id)
        if item.source == "stremio":
            return VoiceResult(f"Abriendo {item.title} en Stremio.")
        return VoiceResult(f"Abriendo {item.title} con {runner}." if runner else f"Abriendo {item.title}.")

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

    def _open_stremio_intent(self, slots: dict) -> VoiceResult:
        self.catalog.launch("media:stremio")
        return VoiceResult("Abriendo Stremio.")

    def _search_media_intent(self, slots: dict) -> VoiceResult:
        query = slots.get("query", "")
        if not query:
            return VoiceResult("¿Qué quieres ver?", ok=False)
        # Si ya está en tu biblioteca de Stremio, se abre directo.
        item = self.catalog.find(query, source="stremio")
        if item is not None:
            self.catalog.launch(item.id)
            return VoiceResult(f"Abriendo {item.title} en Stremio.")
        try:
            exact = self._watch_exact(query)
        except cinemeta.CinemetaError:  # sin catálogo: la búsqueda de Stremio
            self.catalog.search_media(query)
            return VoiceResult(f"Buscando {query} en Stremio.")
        if exact:
            return exact
        # Varias opciones: la búsqueda de Orbital ya escrita, para elegir con el mando.
        return VoiceResult(f"Buscando {query}. Elige con el control.", events=[self._show_view({"buscar": query})])

    def _show_view(self, view: dict) -> dict:
        """Trae Orbital al frente con una vista abierta (búsqueda o episodios)."""
        if self.kiosk is not None:
            self.kiosk.open()
        return {"type": "reload", "view": view}

    def _watch_exact(self, query: str) -> VoiceResult | None:
        """Si el título coincide exacto con una película o serie: la película se pone directo y la
        serie abre sus episodios en Orbital. None si no hay coincidencia exacta."""
        target = normalize(query)
        movies = self.catalog.cinemeta.search("movie", query)
        series = self.catalog.cinemeta.search("series", query)
        match = next((r for r in cinemeta.search_results(query, movies, series) if normalize(r["title"]) == target), None)
        if match is None:
            return None
        if match["kind"] == "movie":
            self.catalog.play_stremio("movie", match["meta_id"], None, match["title"])
            return VoiceResult(f"Poniendo {match['title']}.")
        return VoiceResult(f"Abriendo {match['title']}. Elige el episodio.", events=[self._show_view({"serie": match["meta_id"]})])

    def _continue_watching_intent(self, slots: dict) -> VoiceResult:
        show = slots.get("show", "")
        if not self.catalog.stremio_linked:
            return VoiceResult("Primero conecta tu cuenta de Stremio con orbital stremio login.", ok=False)
        if show:
            item = self.catalog.find(show, source="stremio")
            if item is None:
                return VoiceResult(f"No encontré {show} en tu biblioteca de Stremio.", ok=False)
        else:
            watching = self.catalog.grouped_items("continue")
            if not watching:
                return VoiceResult("No tienes nada a medias en Stremio.", ok=False)
            item = watching[0]
        self.catalog.launch(item.id)
        detail = item.subtitle.removeprefix("Stremio").strip(" ·")
        return VoiceResult(f"Continuando {item.title}{', ' + detail if detail else ''}.")

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
