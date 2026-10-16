"""Traduce comandos de voz (intents de Alexa o texto libre) en acciones del catálogo."""

from __future__ import annotations

import logging
import math
import re
import threading
import time
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


SECTIONS = {"juegos": "games", "peliculas": "media", "series": "media", "peliculas y series": "media",
            "apps": "apps", "aplicaciones": "apps", "games": "games", "media": "media",
            "mis juegos": "games", "para ti": "foryou", "recomendaciones": "foryou", "sugerencias": "foryou", "foryou": "foryou",
            "tv en vivo": "tv", "tele en vivo": "tv", "television en vivo": "tv", "la tele": "tv", "tele": "tv", "television": "tv",
            "la television": "tv", "canales": "tv", "los canales": "tv", "tv": "tv"}
SECTION_NAMES = {"games": "Juegos", "media": "Películas y series", "apps": "Apps", "foryou": "Para ti", "tv": "la TV en vivo"}
CHANNEL_NEXT = {"next", "siguiente", "sube", "suba", "adelante", "otro"}
CHANNEL_PREVIOUS = {"previous", "anterior", "baja", "baje", "atras", "el anterior"}
QUICK_LOOKUP = 3.5  # s: Alexa corta a los ~8 s; si Trakt tarda, se enseña en pantalla y se dice que ahí está

LANGUAGES = {
    "ingles": "en", "english": "en", "en": "en",
    "espanol": "es", "spanish": "es", "castellano": "es", "latino": "es", "es": "es",
    "frances": "fr", "french": "fr", "fr": "fr", "portugues": "pt", "brasileno": "pt", "pt": "pt",
    "italiano": "it", "it": "it", "aleman": "de", "de": "de", "japones": "ja", "ja": "ja", "coreano": "ko", "ko": "ko",
}
LANGUAGE_NAMES = {"en": "inglés", "es": "español", "fr": "francés", "pt": "portugués", "it": "italiano",
                  "de": "alemán", "ja": "japonés", "ko": "coreano"}
VAGUE_MEDIA = {"una pelicula", "una serie", "algo", "peliculas", "series", "una peli", "pelis", "algo bueno",
               "una telenovela", "una novela", "telenovelas", "novelas", "una caricatura", "caricaturas",
               "un documental", "documentales", "algo de ver", "algo para ver"}
# «Pon la novela», «pon mi serie»: lo que estabas viendo (antes: «No encontré la telenovela en tu biblioteca»).
THE_USUAL = {"la telenovela", "la novela", "mi novela", "mi telenovela", "mi serie", "la serie", "lo que estaba viendo",
             "lo que estabamos viendo", "lo de siempre", "mi pelicula", "la pelicula que estaba viendo"}
NO_TOAST = {"type": "noop"}  # la interfaz ignora este evento
VOLUME_DOWN = {"down", "baja", "baje", "bajale", "bajarle", "menos"}
# Lo que la voz espera a saber si hay fuente antes de contestar (Alexa corta a los ~8 s; el túnel y
# Alexa se llevan el resto): así dice «No encontré dónde ver…» en vez de «Poniendo…» y luego nada.
VOICE_WAIT = 4.5
MAX_SEEK = 6 * 3600  # s: nadie adelanta más de una película entera de golpe


def spoken_number(value) -> float | None:
    """Un número dicho o escrito: "30", "treinta", "media" (0.5). None si no lo es o es absurdo (1e999)."""
    text = normalize(str(value or ""))
    if text in ("medio", "media"):
        return .5
    try:
        number = float(words_to_numbers(text))
    except (ValueError, OverflowError):
        return None
    return number if math.isfinite(number) else None


SEEK_BACK = {"back", "regresa", "regrese", "retrocede", "retroceda", "atrasa", "atrase", "atras"}
CLOUD = re.compile(r"\s+(?:en|desde)\s+(?:la\s+nube|geforce(?:\s+now)?|gfn)$")


def spoken_list(names: list[str]) -> str:
    """["Andor", "Silo", "The Bear"] → «Andor, Silo y The Bear»."""
    names = [n for n in names if n]
    return names[0] if len(names) == 1 else ", ".join(names[:-1]) + " y " + names[-1] if names else ""


def upcoming_speech(items: list[dict], limit: int = 3) -> str:
    """Los estrenos dichos por día: «Hoy sale Severance a las 20:00. Mañana: Andor y Silo, desde la madrugada.»"""
    days: dict[str, list[dict]] = {}
    for item in items:
        days.setdefault(item.get("day_label") or "", []).append(item)
    parts = []
    for label, group in list(days.items())[:limit]:
        names = [g["title"] for g in group[:4]]
        times = {g.get("time") for g in group}
        when = "" if len(times) != 1 else (", desde la madrugada" if times == {"Desde la madrugada"} else f" a las {group[0]['time']}")
        if label == "Hoy":
            parts.append(f"Hoy {'sale' if len(names) == 1 else 'salen'} {spoken_list(names)}{when}.")
        else:
            parts.append(f"{label}: {spoken_list(names)}{when}.")
    return " ".join(parts)


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

_EPISODE = (r"(?:(?:temporada|season)\s+(?P<season>\d+)\s*,?\s*(?:episodio|capitulo|cap)\s+(?P<episode>\d+)"
            r"|(?:episodio|capitulo|cap)\s+(?P<episode2>\d+)\s+de\s+la\s+temporada\s+(?P<season2>\d+))")

# Alexa a veces transcribe los números con letra ("temporada cinco episodio tres").
_UNITS = ["cero", "uno", "dos", "tres", "cuatro", "cinco", "seis", "siete", "ocho", "nueve", "diez", "once", "doce",
          "trece", "catorce", "quince", "dieciseis", "diecisiete", "dieciocho", "diecinueve", "veinte",
          "veintiuno", "veintidos", "veintitres", "veinticuatro", "veinticinco", "veintiseis", "veintisiete",
          "veintiocho", "veintinueve"]
_TENS = {"treinta": 30, "cuarenta": 40, "cincuenta": 50, "sesenta": 60, "setenta": 70, "ochenta": 80, "noventa": 90}


def words_to_numbers(text: str) -> str:
    """"temporada treinta y dos episodio un" -> "temporada 32 episodio 1" (texto ya normalizado)."""
    def tens(m):
        return str(_TENS[m.group(1)] + (_UNITS.index(m.group(2)) if m.group(2) else 0))
    text = re.sub(rf"\b({'|'.join(_TENS)})(?:\s+y\s+({'|'.join(_UNITS[1:10])}))?\b", tens, text)
    text = re.sub(r"\b(un|una|primer|primero|primera)\b(?=\s*(?:$|en\b|,))", "1", text)
    return re.sub(rf"\b({'|'.join(sorted(_UNITS, key=len, reverse=True))})\b", lambda m: str(_UNITS.index(m.group(1))), text)


_EPISODE_ONLY: list[re.Pattern] = []  # se arma abajo, con _EPISODE


def episode_request(text: str) -> dict | None:
    """¿Es un episodio concreto? "los simpson temporada 5 episodio 3 en español" -> slots de WatchEpisode.
    Sirve aunque Alexa lo mande como búsqueda ("quiero ver {query}") o como juego ("pon {game}")."""
    clean = words_to_numbers(normalize(text))
    for pattern in _EPISODE_ONLY:
        m = pattern.match(clean)
        if m:
            return {k.rstrip("2"): v for k, v in m.groupdict().items() if v}
    return None


_TEXT_RULES: list[tuple] = [  # (patrón, intent, slot | None[, slots fijos])
    # «pon la temporada 2» (de la serie que ves): su primer episodio
    (re.compile(r"^(?:pon|ponga|ve a|vaya a|pasa a|pase a)\s+(?:la\s+)?temporada\s+(?P<season>\d+)$"),
     "PlayEpisodeIntent", None, {"episode": "1"}),
    # «pon el capítulo 5» (de la serie que estás viendo), «ve al episodio 3 de la temporada 2»
    (re.compile(r"^(?:pon|ponga|quiero ver|ve al|vaya al|pasa al|pase al|cambia al|cambie al)\s+(?:el\s+)?"
                r"(?:episodio|capitulo|cap)\s+(?P<episode>\d+)(?:\s+de\s+la\s+temporada\s+(?P<season>\d+))?$"),
     "PlayEpisodeIntent", None),
    # "quiero ver los simpson temporada 5 episodio 3 en español"
    (re.compile(rf"^(?:quiero ver|pon|ponga|ver|reproduce)\s+(?:el\s+)?(?P<series>.+?)\s*,?\s+{_EPISODE}"
                r"(?:\s+en\s+(?P<language>\w+))?$"), "WatchEpisodeIntent", None),
    # «pon Los Simpson temporada dos»: desde su primer episodio
    (re.compile(r"^(?:quiero ver|pon|ponga|ver|reproduce)\s+(?:el\s+)?(?P<series>.+?)\s*,?\s+temporada\s+(?P<season>\d+|[a-z]+)$"),
     "WatchEpisodeIntent", None, {"episode": "1"}),
    (re.compile(rf"^(?:quiero ver|pon|ponga|ver)\s+(?:el\s+)?{_EPISODE}\s+de\s+(?P<series>.+?)"
                r"(?:\s+en\s+(?P<language>\w+))?$"), "WatchEpisodeIntent", None),
    # Reproductor de Orbital (van primero: "pon subtítulos" no es abrir un juego llamado así).
    # Sin slot fijo: los grupos con nombre son los slots.
    (re.compile(r"^(?:pausa|pause|pon pausa|ponle pausa|ponga pausa|para|deten)(?:\s+(?:el video|la pelicula|la serie))?$"),
     "PauseIntent", None),
    (re.compile(r"^(?:reanuda|reanude|quita la pausa|quite la pausa|dale play|dele play)(?:\s+el video)?$"),
     "ResumeIntent", None),
    (re.compile(r"^(?P<seek>adelanta|adelante|avanza|avance|salta|salte|pasa|regresa|regrese|retrocede|retroceda|atrasa|atrase)"
                r"(?:\s+el video)?\s+(?:(?P<amount>\d+|media|medio)|un|una)\s+(?P<unit>minutos?|segundos?|horas?)$"), "SeekIntent", None),
    (re.compile(r"^(?:(?:pon|ponga|ponle|ponles|activa|active|cambia|cambie)(?:\s+los)?\s+)?subtitulos"
                r"(?:\s+(?:en|a)\s+(?P<language>\w+))?$"), "SubtitlesIntent", None),
    (re.compile(r"^(?:quita|quite|apaga|apague)\s+los\s+subtitulos$|^sin subtitulos$"), "SubtitlesOffIntent", None),
    (re.compile(r"^(?:(?:pon|ponga|cambia|cambie)(?:\s+el)?\s+)?(?:audio|idioma)\s+(?:en|a)\s+(?P<language>\w+)$"),
     "AudioLanguageIntent", None),
    (re.compile(r"^(?:ponlo|pongalo|ponla|pongala|ponmelo|cambialo|cambiala)\s+(?:en|a)\s+(?P<language>\w+)$"),
     "AudioLanguageIntent", None),
    (re.compile(r"^(?:salta|salte|saltate|saltar|brinca|brinque|brincate|omite|omita|quita|quite)(?:\s+(?:la|el))?\s+"
                r"(?:intro|introduccion|entrada|presentacion|opening|resumen)$"), "SkipIntroIntent", None),
    (re.compile(r"^(?:(?:pon|ponga|pasa al|pase al)\s+)?(?:el\s+)?siguiente(?:\s+(?:episodio|capitulo))?$"
                r"|^(?:(?:pon|ponga)\s+)?el que sigue$"), "NextEpisodeIntent", None),
    (re.compile(r"^(?:pon|ponga|la)\s+siguiente\s+cancion$|^siguiente\s+cancion$|^cambia(?:\s+la)?\s+cancion$"),
     "NextEpisodeIntent", None),
    (re.compile(r"^(?:pausa|pon pausa a|deten)\s+la\s+musica$"), "PauseIntent", None),
    (re.compile(r"^(?:quita la pausa a|sigue con|reanuda)\s+la\s+musica$"), "ResumeIntent", None),
    (re.compile(r"^(?:cuanto|cuanto tiempo)\s+(?:le\s+)?(?:falta|queda)(?:\s+(?:al video|a la pelicula|al episodio))?$"),
     "TimeLeftIntent", None),
    (re.compile(r"^(?:toma|tome|haz|haga)\s+(?:una\s+)?captura(?:\s+de\s+pantalla)?$|^captura\s+(?:la\s+)?pantalla$"),
     "CaptureIntent", None),
    (re.compile(r"^(?P<volume>sube|suba|subele|baja|baje|bajale)(?:\s+el)?\s+volumen(?:\s+a\s+(?P<level>\d+))?$"),
     "VolumeIntent", None),
    (re.compile(r"^(?P<volume>sube|suba|subele|baja|baje|bajale)(?:\s+el)?\s+volumen\s+(?P<amount>\d+)(?:\s+puntos)?$"),
     "VolumeIntent", None),
    (re.compile(r"^(?:pon|ponga)\s+el\s+volumen\s+(?:en|a|al)\s+(?P<level>\d+)(?:\s+por\s*ciento)?$"),
     "VolumeIntent", None),
    (re.compile(r"^(?:pon|ponga|sube|suba)\s+el\s+volumen\s+al\s+maximo$"), "VolumeIntent", None, {"level": "100"}),
    (re.compile(r"^(?:pon|ponga|baja|baje)\s+el\s+volumen\s+al\s+minimo$"), "VolumeIntent", None, {"level": "5"}),
    (re.compile(r"^(?:silencia|silencie|silencio|mute|quita el sonido|quite el sonido)(?:\s+la\s+(?:tele|tv|consola))?$"),
     "MuteIntent", None),
    (re.compile(r"^(?:quita|quite)\s+el\s+silencio$|^(?:regresa|devuelve|pon)\s+el\s+sonido$"), "UnmuteIntent", None),
    (re.compile(r"^(?:(?:pon|ponga|regresa al|regrese al)\s+)?(?:el\s+)?(?:episodio|capitulo)\s+anterior$"),
     "PreviousEpisodeIntent", None),
    (re.compile(r"^(?:cierra|cierre|quita|quite)\s+(?:el\s+video|la\s+pelicula|la\s+serie|stremio)$"),
     "CloseGameIntent", None),
    (re.compile(r"^que\s+(?:estoy viendo|pelicula es esta|serie es esta|se esta reproduciendo)$"), "WhatsPlayingIntent", None),
    # TV en vivo: «pon el canal ADN 40», «pon Azteca Uno en vivo», «siguiente canal», «pon la tele»
    (re.compile(r"^(?:siguiente|el siguiente|otro)\s+canal$|^(?:cambia|cambie|sube|suba)\s+(?:de\s+|el\s+)?canal$"),
     "ChannelStepIntent", None, {"step": "next"}),
    (re.compile(r"^(?:el\s+)?canal\s+anterior$|^(?:regresa|regrese|baja|baje)\s+(?:de\s+|el\s+|al\s+)?canal(?:\s+anterior)?$"),
     "ChannelStepIntent", None, {"step": "previous"}),
    (re.compile(r"^(?:pon|ponga|sintoniza|sintonice|cambia a|cambie a|cambia al|cambie al|quiero ver)\s+(?:el\s+)?canal\s+(?P<v>.+)$"),
     "LiveTvIntent", "channel"),
    (re.compile(r"^(?:pon|ponga|sintoniza|sintonice|quiero ver)\s+(?P<v>.+?)\s+en\s+vivo$"), "LiveTvIntent", "channel"),
    (re.compile(r"^(?:pon|ponga|abre|abra|quiero ver|prende|prenda)\s+(?:la\s+)?(?:tele|television|tv)(?:\s+en\s+vivo)?$"
                r"|^(?:tele|television|tv)\s+en\s+vivo$"), "LiveTvIntent", None),
    # Para ti: «qué sale hoy», «qué me recomiendas»
    (re.compile(r"^(?:que|cuales)\s+(?:episodios\s+|estrenos\s+|capitulos\s+)?(?:sale|salen|se estrena|se estrenan|hay)\s+"
                r"(?:hoy|esta semana|manana|de nuevo|nuevos?)$|^(?:que\s+)?(?:proximos\s+)?estrenos(?:\s+hay)?$"), "UpcomingIntent", None),
    (re.compile(r"^(?:que|que me)\s+(?:recomiendas|sugieres)(?:\s+ver)?$|^(?:recomiendame|sugiereme|recomiendeme)\s+algo(?:\s+de\s+ver)?$"),
     "RecommendIntent", None),
    # Brillo de la pantalla
    (re.compile(r"^(?P<brightness>sube|suba|subele|baja|baje|bajale)(?:\s+el)?\s+brillo(?:\s+a\s+(?P<level>\d+))?$"), "BrightnessIntent", None),
    (re.compile(r"^(?:pon|ponga)\s+el\s+brillo\s+(?:en|a|al)\s+(?P<level>\d+)(?:\s+por\s*ciento)?$"), "BrightnessIntent", None),
    (re.compile(rf"^{_V['search']}\s+(?P<v>.+?)\s+en\s+stremio$"), "SearchMediaIntent", "query"),
    (re.compile(r"^(?:busca|busque|buscar)\s+(?P<v>.+)$"), "SearchMediaIntent", "query"),
    (re.compile(rf"^(?:{_V['go']}|{_V['move']}|{_V['open']})\s+(?:a\s+)?(?:la\s+seccion\s+de\s+|los\s+|las\s+|mis\s+)?"
                r"(?P<direction>juegos|peliculas y series|peliculas|series|apps|aplicaciones|para ti|recomendaciones|tv en vivo|tele en vivo)$"),
     "NavigateIntent", None),
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


_EPISODE_ONLY = [
    re.compile(rf"^(?:el\s+)?(?P<series>.+?)\s*,?\s+{_EPISODE}(?:\s+en\s+(?P<language>\w+))?$"),
    re.compile(rf"^(?:el\s+)?{_EPISODE}\s+de\s+(?P<series>.+?)(?:\s+en\s+(?P<language>\w+))?$"),
]


NUMERIC = {"VolumeIntent", "SeekIntent", "PlayEpisodeIntent", "BrightnessIntent", "LiveTvIntent"}  # «pon el volumen a cincuenta»: el número en palabras


# Cómo se dice en México con «pídele a mi consola que…»: «le suba al volumen», «súbele tantito»,
# «ponme Los Simpson», «quítale los subtítulos», «se regrese diez segundos». Se lleva a la forma
# simple («sube el volumen») y se vuelve a probar.
_CLITIC_VERBS = {
    "subele": "sube", "subale": "suba", "subanle": "suba", "bajale": "baja", "bajele": "baje", "bajanle": "baje",
    "ponme": "pon", "pongame": "ponga", "ponnos": "pon", "quitale": "quita", "quitele": "quite",
    "regresale": "regresa", "regresele": "regrese", "adelantale": "adelanta", "adelantele": "adelante",
    "cierralo": "cierra el juego", "cierrelo": "cierre el juego", "cierrala": "cierra el juego",
    "pausalo": "pausa", "pausala": "pausa", "pausale": "pausa",
    # de tú: «me pones…», «me abres…», «pásale al siguiente», «búscame…»
    "pones": "pon", "abres": "abre", "pasale": "pasa", "pasas": "pasa", "subes": "sube", "bajas": "baja",
    "quitas": "quita", "buscas": "busca", "buscame": "busca", "busqueme": "busque", "abreme": "abre", "abrame": "abra",
}


def _plain(clean: str) -> str:
    words = clean.split()
    while words and words[0] in ("le", "me", "se", "nos", "que"):
        words = words[1:]
    text = " ".join(_CLITIC_VERBS.get(w, w) for w in words)
    text = re.sub(r"\b(?:tantito|un poquito|un poco|mas)$", "", text).strip()
    text = re.sub(r"^(sube|suba|baja|baje)\s+al\s+volumen", r"\1 el volumen", text)
    text = re.sub(r"^(sube|suba|baja|baje)(?:\s+al)?$", r"\1 el volumen", text)  # «súbele» a secas
    text = re.sub(r"^(?:ponle|dale|dele)\s+play$", "dale play", text)
    return text


def parse_text(text: str) -> tuple[str, dict[str, str]] | None:
    found = _parse(normalize(text))
    if found is None:
        plain = _plain(normalize(text))
        if plain and plain != normalize(text):
            found = _parse(plain)
    return found


def _parse(clean: str) -> tuple[str, dict[str, str]] | None:
    numeric = words_to_numbers(clean)
    for pattern, intent, slot, *fixed in _TEXT_RULES:
        m = pattern.match(numeric if intent in NUMERIC else clean)
        if m:
            if fixed:
                return intent, {**{k: v for k, v in m.groupdict().items() if v}, **fixed[0]}
            if slot:
                return intent, ({slot: m.group("v")} if m.group("v") else {})
            found = {k.rstrip("2"): v for k, v in m.groupdict().items() if v}
            return intent, found
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
        slots = {k: v for k, v in (slots.items() if isinstance(slots, dict) else ()) if v}
        log.info("Voz: %s %s", intent, slots)
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

    # --- intents -------------------------------------------------------------
    def _launch_game_intent(self, slots: dict) -> VoiceResult:
        name = slots.get("game", "")
        if not name:
            return VoiceResult("¿Qué juego quieres abrir?", ok=False)
        if (episode := episode_request(name)) is not None:  # "pon Los Simpson temporada 5 episodio 3"
            return self._watch_episode_intent(episode)
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
                or self.catalog.find(name, source="stremio"))
        if item is None:
            # Ni juego ni biblioteca: ¿es una película o serie? ("abre The Office")
            if (channel := self._find_channel(name)) is not None:  # «abre Bandamax»: un canal de TV en vivo
                return self._play_channel(channel)
            try:
                watch = self._watch_exact(name)
            except cinemeta.CinemetaError:
                watch = None
            return watch or VoiceResult(f"No encontré {name} en tu biblioteca. Di busca {name} para buscarlo.", ok=False)
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
        self.catalog.sessions.launch("media:stremio")
        return VoiceResult("Abriendo Stremio.")

    def _search_media_intent(self, slots: dict) -> VoiceResult:
        query = slots.get("query", "")
        if not query:
            return VoiceResult("¿Qué quieres ver?", ok=False)
        if (episode := episode_request(query)) is not None:  # "quiero ver Los Simpson temporada 5…"
            return self._watch_episode_intent(episode)
        if (vague := self._vague(query)) is not None:  # "quiero ver una película": no es un título
            return vague
        if (section := self._section(query)) is not None:  # «pon la tele», «quiero ver Para ti»
            return section
        if (channel := self._find_channel(query)) is not None:  # «pon ADN 40»: el canal en vivo (antes: buscarlo en Stremio)
            return self._play_channel(channel)
        # Si ya está en tu biblioteca de Stremio, se abre directo.
        item = self.catalog.find(query, source="stremio")
        if item is not None:
            return self._watch_item(item)
        try:
            exact = self._watch_exact(query)
        except cinemeta.CinemetaError:  # sin catálogo: la búsqueda de Stremio
            self.catalog.sessions.search_media(query)
            return VoiceResult(f"Buscando {query} en Stremio.")
        if exact:
            return exact
        # Varias opciones: la búsqueda de Orbital ya escrita, para elegir con el mando.
        return VoiceResult(f"Buscando {query}. Elige con el control.", events=[self._show_view({"buscar": query}, f"Buscando «{query}»")])

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
                                    "message": f"¿Cuál «{query}»?"}])

    def _show_view(self, view: dict, message: str = "") -> dict:
        """Trae Orbital al frente con una vista abierta (búsqueda o ficha), sin recargar la interfaz:
        no se pierde dónde estabas y se ve qué entendió Alexa."""
        if self.kiosk is not None:
            self.kiosk.open()
        return {"type": "open-view", "view": view, "message": message}

    def _watch_exact(self, query: str) -> VoiceResult | None:
        """Si el título coincide exacto con una película o serie: la película se pone directo y la
        serie abre sus episodios en Orbital. None si no hay coincidencia exacta."""
        target = normalize(query)
        movies = self.catalog.cinemeta.search("movie", query)
        series = self.catalog.cinemeta.search("series", query)
        matches = [r for r in cinemeta.search_results(query, movies, series) if normalize(r["title"]) == target]
        if len(matches) > 1:
            return self._ask_which(query, matches)
        match = matches[0] if matches else None
        if match is None:
            return None
        if match["kind"] == "movie":
            problem = self.catalog.watch.play_title("movie", match["meta_id"], match["meta_id"], match["title"], wait=VOICE_WAIT)
            return VoiceResult(problem, ok=False) if problem else VoiceResult(f"Poniendo {match['title']}.")
        return VoiceResult(f"Abriendo {match['title']}. Elige el episodio.", events=[self._show_view({"serie": match["meta_id"]}, f"Abriendo {match['title']}")])

    def _continue_watching_intent(self, slots: dict) -> VoiceResult:
        show = slots.get("show", "")
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

    def _watch_item(self, item) -> VoiceResult:
        """Algo de tu biblioteca de Stremio: el episodio o la película donde ibas; una serie sin
        episodio pendiente abre sus episodios en Orbital."""
        extra = item.extra or {}
        kind, meta_id, video_id = extra.get("kind"), extra.get("meta_id"), extra.get("video_id")
        if kind in ("movie", "series") and meta_id and video_id:
            problem = self.catalog.watch.play_title(kind, meta_id, video_id, item.title, wait=VOICE_WAIT)
            return VoiceResult(problem, ok=False) if problem else VoiceResult(f"Poniendo {item.title}.")
        if kind == "series" and meta_id:
            return VoiceResult(f"Abriendo {item.title}. Elige el episodio.", events=[self._show_view({"serie": meta_id}, f"Abriendo {item.title}")])
        self.catalog.sessions.launch(item.id)
        return VoiceResult(f"Abriendo {item.title} en Stremio.")

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
        if self.kiosk is None:
            return VoiceResult("No puedo abrir la pantalla de la consola desde aquí.", ok=False)
        self.kiosk.open()
        return VoiceResult("Abriendo la consola.")

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

    @staticmethod
    def _channel_key(name: str) -> str:
        """«ADN 40 (720p) [Not 24/7]» → «adn 40»; «Azteca Uno» → «azteca 1» (Alexa dice los números con letra o cifra)."""
        plain = re.sub(r"\s*[\(\[][^\)\]]*[\)\]]", "", str(name or ""))
        return words_to_numbers(normalize(plain)).strip()

    def _find_channel(self, said: str):
        """El canal de TV en vivo con ese nombre (o «canal 5» si no hay uno que se llame así: su número en Orbital)."""
        tv = getattr(self.catalog, "tv", None)
        if tv is None:
            return None
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
        if not said:  # «pon la tele»: la sección de canales
            return VoiceResult("Abriendo la TV en vivo.", events=[self._show_view({"seccion": "tv"}, "TV en vivo")])
        channel = self._find_channel(said)
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
        """«¿Qué me recomiendas?»: tres títulos de tus recomendaciones y Para ti en pantalla."""
        foryou = self.catalog.foryou
        show = self._show_view({"seccion": "foryou"}, "Para ti")
        titles: list[str] = []
        if foryou.trakt.linked:
            try:
                items = self._within(QUICK_LOOKUP, lambda: foryou.list_items("recs", "series")[:2] + foryou.list_items("recs", "movie")[:1])
            except Exception:  # noqa: BLE001
                items = None
            titles = [i["title"] for i in items or [] if i.get("title")]
        if not titles:
            return VoiceResult("Te dejo Para ti abierto: ahí están tus sugerencias.", events=[show])
        return VoiceResult(f"Te recomiendo {spoken_list(titles)}. Están en Para ti.", events=[show])

    def _brightness_intent(self, slots: dict) -> VoiceResult:
        from . import quick

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

    # --- reproductor de Orbital -------------------------------------------------------------
    # Sin aviso en la interfaz (events=[NO_TOAST]): el video está encima y mpv ya lo muestra.
    def _playing(self) -> VoiceResult | None:
        """None si hay algo en el reproductor de Orbital; si no, la respuesta para Alexa."""
        if self.catalog.player.playing:
            return None
        return VoiceResult("No hay nada reproduciéndose en Orbital.", ok=False)

    def _music(self, action: str, speech: str) -> VoiceResult | None:
        """Sin nada en el reproductor de Orbital, la orden va a la música de Windows (Apple Music…)."""
        from . import music

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
        if not self.catalog.player.playing and (done := self._music("play", "Listo.")):
            return done
        if (idle := self._playing()) is not None:
            return idle
        self.catalog.player.set_pause(False)
        return VoiceResult("Listo.", events=[NO_TOAST])

    def _seek_intent(self, slots: dict) -> VoiceResult:
        if (idle := self._playing()) is not None:
            return idle
        unit = normalize(slots.get("unit", ""))
        size, word = (3600, "hora") if unit.startswith(("hour", "hora")) else (60, "minuto") if unit.startswith("min") else (1, "segundo")
        amount = spoken_number(slots.get("amount")) if slots.get("amount") else None
        if amount is None:
            amount = 1 if unit else 30  # "adelanta un minuto" / "adelanta un poco"
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

    def _time_left_intent(self, slots: dict) -> VoiceResult:
        if (idle := self._playing()) is not None:
            return idle
        segment = self.catalog.player.segment
        if segment is None or not segment.duration:
            return VoiceResult("Todavía no sé cuánto dura.", ok=False)
        left = max(0, segment.duration - segment.position)
        ends = time.strftime("%H:%M", time.localtime(time.time() + left))
        minutes = round(left / 60)
        what = "menos de un minuto" if minutes < 1 else f"{minutes} minuto{'s' if minutes != 1 else ''}"
        return VoiceResult(f"Faltan {what}; termina a las {ends}.")

    def _capture_intent(self, slots: dict) -> VoiceResult:
        from . import capture

        status = self.catalog.launcher.status()
        event = capture.take_and_describe(status["title"] if status else "")
        return VoiceResult("Listo, guardé la captura." if event.get("ok", True) else event["message"],
                           ok=event.get("ok", True), events=[event])

    def _volume_intent(self, slots: dict) -> VoiceResult:
        from . import quick

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
        from . import quick

        if quick.set_volume(muted=True) is None:
            return VoiceResult("No encuentro el control de volumen.", ok=False)
        return VoiceResult("Sin sonido. Di quita el silencio para volver.")

    def _unmute_intent(self, slots: dict) -> VoiceResult:
        from . import quick

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
        lang = self._language(slots) or self.catalog.config.stremio.subtitles or "en"
        name = LANGUAGE_NAMES.get(lang, lang)
        if self.catalog.watch.player_subtitles(lang):
            return VoiceResult(f"Subtítulos en {name}.", events=[NO_TOAST])
        return VoiceResult(f"No encontré subtítulos en {name} para esto.", ok=False, events=[NO_TOAST])

    def _subtitles_off_intent(self, slots: dict) -> VoiceResult:
        if (idle := self._playing()) is not None:
            return idle
        self.catalog.player.subtitles_off()
        return VoiceResult("Sin subtítulos.", events=[NO_TOAST])

    def _audio_language_intent(self, slots: dict) -> VoiceResult:
        if (idle := self._playing()) is not None:
            return idle
        lang = self._language(slots)
        if lang is None:
            return VoiceResult("¿En qué idioma? Por ejemplo: pon el audio en español.", ok=False)
        name = LANGUAGE_NAMES.get(lang, lang)
        if self.catalog.player.select_language("audio", lang):
            return VoiceResult(f"Audio en {name}.", events=[NO_TOAST])
        return VoiceResult(f"Este video no trae audio en {name}.", ok=False, events=[NO_TOAST])

    def _next_episode_intent(self, slots: dict) -> VoiceResult:
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
        try:
            season = int(float(words_to_numbers(normalize(str(slots.get("season", ""))))))
            episode = int(float(words_to_numbers(normalize(str(slots.get("episode", ""))))))
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
        video = next((v for v in meta.get("videos") or []
                      if v.get("season") == season and v.get("episode") == episode and v.get("id")), None)
        name = meta.get("name") or match["name"]
        if video is None:
            return VoiceResult(f"{name} no tiene temporada {season} episodio {episode}.", ok=False)
        lang = self._language(slots)
        label = f"{name} · T{season} E{episode}"
        # Aquí ya se buscó la serie en Cinemeta (unos segundos): se espera menos a la fuente.
        problem = self.catalog.watch.play_title("series", match["id"], video["id"], label, audio=lang, wait=VOICE_WAIT - 2)
        if problem:
            return VoiceResult(problem, ok=False)
        in_lang = f" en {LANGUAGE_NAMES.get(lang, lang)}" if lang else ""
        return VoiceResult(f"Poniendo {name}, temporada {season}, episodio {episode}{in_lang}.")
