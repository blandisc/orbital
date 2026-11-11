"""De lo dicho a un intent: las reglas de texto libre, los números dichos, los idiomas y las frases de cada momento."""

from __future__ import annotations

import logging
import math
import re
from dataclasses import dataclass, field

from ..catalog import normalize

log = logging.getLogger("orbital.voice")  # el nombre de siempre: la bitácora no cambia

DIRECTIONS = {
    "arriba": "up", "abajo": "down", "izquierda": "left", "derecha": "right",
    "seleccionar": "select", "selecciona": "select", "aceptar": "select", "ok": "select",
    "atras": "back", "regresar": "back", "volver": "back", "inicio": "home",
    "up": "up", "down": "down", "left": "left", "right": "right",
    "select": "select", "back": "back", "home": "home",
}


SECTIONS = {"juegos": "games", "peliculas": "media", "series": "media", "peliculas y series": "media",
            "games": "games", "media": "media",
            "mis juegos": "games", "explorar": "foryou", "para ti": "foryou", "recomendaciones": "foryou", "sugerencias": "foryou", "foryou": "foryou",
            "tv en vivo": "tv", "tele en vivo": "tv", "television en vivo": "tv", "la tele": "tv", "tele": "tv", "television": "tv",
            "la television": "tv", "canales": "tv", "los canales": "tv", "tv": "tv"}

SECTION_NAMES = {"games": "Juegos", "media": "Películas y series", "foryou": "Explorar", "tv": "la TV en vivo"}

CHANNEL_NEXT = {"next", "siguiente", "sube", "suba", "adelante", "otro"}

CHANNEL_PREVIOUS = {"previous", "anterior", "baja", "baje", "atras", "el anterior"}

QUICK_LOOKUP = 3.5  # s: Alexa corta a los ~8 s; si Trakt tarda, se enseña en pantalla y se dice que ahí está

# «En latino» y «en castellano» piden el doblaje («es-419» / «es-ES»); «en español» es cualquiera de los dos. Alexa manda
# el valor de su slot ya resuelto («es-419» llega como «es 419» al normalizarlo).
LANGUAGES = {
    "ingles": "en", "english": "en", "en": "en",
    "espanol": "es", "spanish": "es", "es": "es",
    "latino": "es-419", "espanol latino": "es-419", "latin spanish": "es-419", "es 419": "es-419",
    "castellano": "es-ES", "espanol de espana": "es-ES", "castilian": "es-ES", "es es": "es-ES",
    "frances": "fr", "french": "fr", "fr": "fr", "portugues": "pt", "brasileno": "pt", "pt": "pt",
    "italiano": "it", "it": "it", "aleman": "de", "de": "de", "japones": "ja", "ja": "ja", "coreano": "ko", "ko": "ko",
}

LANGUAGE_NAMES = {"en": "inglés", "es": "español", "es-419": "latino", "es-ES": "castellano", "fr": "francés", "pt": "portugués", "it": "italiano",
                  "de": "alemán", "ja": "japonés", "ko": "coreano"}

VAGUE_MEDIA = {"una pelicula", "una serie", "algo", "peliculas", "series", "una peli", "pelis", "algo bueno",
               "una telenovela", "una novela", "telenovelas", "novelas", "una caricatura", "caricaturas",
               "un documental", "documentales", "algo de ver", "algo para ver"}

# «Pon la novela», «pon mi serie»: lo que estabas viendo (antes: «No encontré la telenovela en tu biblioteca»).
# Géneros dichos en español → los de Cinemeta («pon algo de terror», «una película de acción»).
GENRES = {"terror": "Horror", "miedo": "Horror", "horror": "Horror", "sustos": "Horror", "comedia": "Comedy", "risa": "Comedy",
          "reir": "Comedy", "accion": "Action", "drama": "Drama", "animada": "Animation", "animacion": "Animation",
          "caricatura": "Animation", "caricaturas": "Animation", "romantica": "Romance", "romance": "Romance", "amor": "Romance",
          "ciencia ficcion": "Sci-Fi", "sci fi": "Sci-Fi", "suspenso": "Thriller", "thriller": "Thriller", "documental": "Documentary",
          "documentales": "Documentary", "misterio": "Mystery", "aventura": "Adventure", "aventuras": "Adventure",
          "fantasia": "Fantasy", "crimen": "Crime", "policiaca": "Crime", "guerra": "War", "belica": "War", "familiar": "Family",
          "ninos": "Family", "infantil": "Family", "musical": "Musical", "vaqueros": "Western", "western": "Western"}

GENRE_NAMES = {"Horror": "terror", "Comedy": "comedia", "Action": "acción", "Drama": "drama", "Animation": "animación",
               "Romance": "romance", "Sci-Fi": "ciencia ficción", "Thriller": "suspenso", "Documentary": "documental",
               "Mystery": "misterio", "Adventure": "aventura", "Fantasy": "fantasía", "Crime": "crimen", "War": "guerra",
               "Family": "familiar", "Musical": "musical", "Western": "vaqueros"}

THE_USUAL = {"la telenovela", "la novela", "mi novela", "mi telenovela", "mi serie", "la serie", "lo que estaba viendo",
             "lo que estabamos viendo", "lo de siempre", "mi pelicula", "la pelicula que estaba viendo"}

NO_TOAST = {"type": "noop"}  # la interfaz ignora este evento

VOLUME_DOWN = {"down", "baja", "baje", "bajale", "bajarle", "menos"}

# Lo que la voz espera a saber si hay fuente antes de contestar (Alexa corta a los ~8 s; el túnel y
# Alexa se llevan el resto): así dice «No encontré dónde ver…» en vez de «Poniendo…» y luego nada.
VOICE_WAIT = 4.5

MAX_SEEK = 6 * 3600  # s: nadie adelanta más de una película entera de golpe

# Lo que pone algo en la pantalla: con la tele apagada (o en otra entrada) la prende y la pone en la de Orbital antes. Antes
# solo «prende la consola» lo hacía, y «pon The Office» sonaba en una tele apagada.
WAKES = {"LaunchGameIntent", "SearchMediaIntent", "WatchEpisodeIntent", "ContinueWatchingIntent", "LiveTvIntent",
         "RecommendIntent", "OpenStremioIntent", "OpenSteamIntent", "OtherIntent"}

OTHER_WINDOW = 30 * 60  # s: «otro» cambia lo último que pediste si fue hace menos de esto

# Lo que se puede decir en cada momento: el segundo renglón del aviso en la tele. Solo frases de «Lo esencial»
# (alexa/commands.json · core; una prueba lo comprueba) y solo con «Frases en pantalla» (voice_tips) en Sí.
# Tres por momento: el iPhone enseña las tres como pista (/api/voice/hints y la respuesta a cada orden suya); la tele, las
# dos primeras en el segundo renglón del aviso.
MOMENT_SAY = {"series": ("pausa", "siguiente episodio", "pon subtítulos"), "movie": ("pausa", "pon subtítulos", "sube el volumen"),
              "live": ("pon el canal ADN 40", "sube el volumen", "cierra el video"),
              "home": ("pon The Office", "sigue viendo", "qué sale hoy")}

NEXT_SAY = {moment: said[:2] for moment, said in MOMENT_SAY.items()}

OTHER_SAY = "Si no es esa, di «otro»"  # una corrección, no una pista: sale siempre


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
    # Qué se entendió (texto libre: Siri, el micrófono del iPhone): el iPhone lo enseña («Entendí: pon dune») y, si no
    # se entendió, sabe que fue la frase y no la consola.
    heard: str | None = None
    intent: str | None = None
    choices: list[dict] | None = None  # varias con el mismo nombre: el iPhone las enseña para tocar
    guide: bool = False  # «¿qué puedo decir?»: el iPhone abre su guía «Lo que puedes decir»
    picked: str | None = None  # «pon Dune» con varias: la que ya se puso (las demás de `choices` son para cambiar)

    def as_dict(self) -> dict:
        out = {"ok": self.ok, "speech": self.speech}
        if self.intent:
            out["intent"] = self.intent
        if self.heard is not None:
            out["heard"] = self.heard
        if self.choices:
            out["choices"] = self.choices
        if self.guide:
            out["guide"] = True
        if self.picked:
            out["picked"] = self.picked
        return out


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
            found = {k.rstrip("2"): v for k, v in m.groupdict().items() if v and k != "tail"}
            return {**found, **_media_tail(m.group("tail"))}
    return None


_LANGS = (r"(?:espanol latino|espanol de espana|espanol|ingles|frances|portugues|italiano|aleman|japones|coreano|original"
          r"|latino|castellano)")

# Lo que va después del episodio: «… en latino», «… con subtítulos (en inglés)», en cualquier orden (`_media_tail`).
_TAIL = rf"(?P<tail>(?:\s+(?:en\s+(?:{_LANGS}|\w+)|con\s+subtitulos(?:\s+en\s+(?:{_LANGS}|\w+))?))*)"


def _media_tail(tail: str) -> dict[str, str]:
    """« en latino con subtitulos en ingles» → {"language": "latino", "subtitles": "ingles"} («con subtítulos» solo: "1")."""
    out: dict[str, str] = {}
    for m in re.finditer(rf"con\s+subtitulos(?:\s+en\s+(?P<sub>{_LANGS}|\w+))?|en\s+(?P<lang>{_LANGS}|\w+)", tail or ""):
        if m.group(0).startswith("con"):
            out["subtitles"] = m.group("sub") or "1"
        else:
            out["language"] = m.group("lang")
    return out


# «Ponlo siempre en latino», «pon Los Simpson en latino siempre», «pon siempre subtítulos en inglés»: lo dicho por voz es
# solo para esta vez; con «siempre» el título lo recuerda. («Lo de siempre» no: es lo que estabas viendo.)
_ALWAYS_BEFORE = re.compile(r"(?:^|\s)(?:para\s+)?siempre\s+(?=(?:en|con|el\s+audio|el\s+idioma|los\s+subtitulos|subtitulos)\b)")

_ALWAYS_AFTER = re.compile(rf"\b({_LANGS}|subtitulos)\s+(?:para\s+)?siempre$")


def always_said(clean: str) -> tuple[str, bool]:
    """La frase sin el «siempre» que va con el idioma o los subtítulos, y si lo dijo. `clean` ya normalizado."""
    m = _ALWAYS_BEFORE.search(clean)
    if m and not re.search(r"\bde\s*$", clean[:m.start() + 1]):
        return re.sub(r"\s+", " ", clean[:m.start()] + " " + clean[m.end():]).strip(), True
    m = _ALWAYS_AFTER.search(clean)
    if m:
        return clean[:m.start()] + m.group(1), True
    return clean, False


def split_language(code: str | None) -> tuple[str | None, str]:
    """«es-419» → ("es", "es-419"); «en» → ("en", ""); None → (None, "")."""
    if code in ("es-419", "es-ES"):
        return "es", code
    return code, ""

_TEXT_RULES: list[tuple] = [  # (patrón, intent, slot | None[, slots fijos])
    # --- el video que se está viendo, dicho en corto (el corpus del iPhone) ---
    (re.compile(r"^(?:desde el principio|desde el inicio|empieza de nuevo|empieza desde el principio|vuelve a empezar"
                r"|otra vez desde el principio|reinicialo|reinicia el video|desde cero)$"), "RestartIntent", None),
    (re.compile(r"^(?:espera|esperate|espereme|detenlo|detente|detengase|alto|stop)$"), "PauseIntent", None),
    (re.compile(r"^(?:play|sigue|siguele|continua|continue|continualo|reproduce)$"), "ResumeIntent", None),
    # «adelántale», «atrasa 10»: sin unidad son segundos. «regresa» a secas no: también es «atrás» en los menús.
    (re.compile(r"^(?P<seek>adelanta|adelante|avanza|avance|retrocede|retroceda|atrasa|atrase)(?:le)?(?:\s+(?P<amount>\d+))?$"
                r"|^(?P<seek2>regresa|regrese)(?:le\s*(?P<amount2>\d+)?|\s+(?P<amount3>\d+))$"), "SeekIntent", None),
    (re.compile(r"^(?:ve|vaya|ir|pon|ponlo|salta|brinca|pasa|lleva(?:me)?)\s+al\s+minuto\s+(?P<minute>\d+)$"), "SeekIntent", None),
    (re.compile(rf"^en\s+(?P<language>{_LANGS})$"), "AudioLanguageIntent", None),
    (re.compile(r"^otro\s+(?:episodio|capitulo)$"), "NextEpisodeIntent", None),
    (re.compile(r"^a\s+que\s+hora\s+(?:termina|acaba|se acaba|sale)(?:\s+(?:el video|la pelicula|el episodio))?$"), "TimeLeftIntent", None),
    # «apaga», «sal del video»: cierra el video (nunca apaga la consola ni cierra un juego sin pedirlo)
    (re.compile(r"^apaga(?:r)?\s+(?:la\s+)?(?:tele|tv|television|pantalla)$"), "TurnOffTvIntent", None),
    (re.compile(r"^(?:sal|salte|salir|quita)\s+del\s+video$|^apaga(?:\s+el\s+video)?$"),
     "CloseGameIntent", None, {"only": "video"}),
    (re.compile(r"^(?:prende|prenda|prender|enciende|encienda|encender)\s+(?:la\s+)?(?:tele|television|tv|pantalla)$"),
     "OpenOrbitalIntent", None),
    (re.compile(r"^(?:otro|otra|el otro|la otra|ese no|esa no|no ese|no esa|pon otro|pon otra|otra opcion)$"), "OtherIntent", None),
    # «¿Qué puedo decir?»: la guía en la tele (y el iPhone abre la suya: «guide» en la respuesta)
    (re.compile(r"^(?:que\s+(?:le\s+|te\s+)?(?:puedo|se puede)\s+(?:decir|pedir)(?:le)?|ayuda|ayudame|como\s+te\s+hablo"
                r"|(?:ensename|enseneme|ensena|ensene|muestrame|muestreme|muestra|muestre|dime)\s+(?:lo\s+que\s+puedo\s+decir|la\s+guia|que\s+puedo\s+decir)|abre\s+la\s+guia)$"),
     "GuideIntent", None),
    (re.compile(r"^(?:pon|ponme|quiero ver|ver)?\s*(?:las\s+)?(?:noticias|el noticiero|un noticiero)$"), "LiveTvIntent", None, {"category": "noticias"}),
    # «pon algo», «algo de terror», «una comedia»: no es un título (antes buscaba un juego llamado «algo»)
    (re.compile(r"^(?:pon|ponme|quiero ver|ver|recomiendame|sugiereme)\s+algo(?:\s+(?:de|para)\s+(?P<genre>[a-z ]+))?$"
                r"|^(?:pon|ponme|quiero ver|ver)\s+una?\s+(?P<what>peli(?:cula)?|serie|show)\s+(?:de|para)\s+(?P<genre2>[a-z ]+)$"
                r"|^(?:pon|ponme|quiero ver|ver)\s+una\s+(?P<genre3>comedia|caricatura)$"),
     "RecommendIntent", None),
    (re.compile(r"^(?:pon|ponme|quiero ver|ver|sigue con|continua con)?\s*(?:lo\s+que\s+(?:estaba|estabamos|estuve)\s+viendo"
                r"|lo\s+ultimo\s+que\s+vi|donde\s+me\s+quede|donde\s+nos\s+quedamos)$"), "ContinueWatchingIntent", None),
    # Episodios: «la temporada 2 de X», «el primer capítulo de X», «el último episodio de X», «temporada 2 capítulo 3»
    (re.compile(rf"^(?:pon|ponga|quiero ver|ver)\s+(?:la\s+)?temporada\s+(?P<season>\d+)\s+de\s+(?P<series>.+?){_TAIL}$"),
     "WatchEpisodeIntent", None, {"episode": "1"}),
    (re.compile(rf"^(?:pon|ponga|quiero ver|ver)\s+(?:el\s+)?(?:episodio|capitulo)\s+(?P<episode>\d+)\s+de\s+(?!la\s+temporada)"
                rf"(?P<series>.+?){_TAIL}$"),
     "WatchEpisodeIntent", None, {"season": "1"}),
    (re.compile(rf"^(?:pon|ponga|quiero ver|ver)\s+(?:el\s+)?(?:ultimo|nuevo)\s+(?:episodio|capitulo)\s+de\s+(?P<series>.+?){_TAIL}$"),
     "WatchEpisodeIntent", None, {"latest": "1"}),
    (re.compile(r"^(?:pon\s+)?(?:la\s+)?temporada\s+(?P<season>\d+)\s*,?\s+(?:episodio|capitulo|cap)\s+(?P<episode>\d+)$"),
     "PlayEpisodeIntent", None),
    # «pon la temporada 2» (de la serie que ves): su primer episodio
    (re.compile(r"^(?:pon|ponga|ve a|vaya a|pasa a|pase a)\s+(?:la\s+)?temporada\s+(?P<season>\d+)$"),
     "PlayEpisodeIntent", None, {"episode": "1"}),
    # «pon el capítulo 5» (de la serie que estás viendo), «ve al episodio 3 de la temporada 2»
    (re.compile(r"^(?:pon|ponga|quiero ver|ve al|vaya al|pasa al|pase al|cambia al|cambie al)\s+(?:el\s+)?"
                r"(?:episodio|capitulo|cap)\s+(?P<episode>\d+)(?:\s+de\s+la\s+temporada\s+(?P<season>\d+))?$"),
     "PlayEpisodeIntent", None),
    # "quiero ver los simpson temporada 5 episodio 3 en español"
    (re.compile(rf"^(?:quiero ver|pon|ponga|ver|reproduce)\s+(?:el\s+)?(?P<series>.+?)\s*,?\s+{_EPISODE}{_TAIL}$"),
     "WatchEpisodeIntent", None),
    # «pon Los Simpson temporada dos»: desde su primer episodio
    (re.compile(r"^(?:quiero ver|pon|ponga|ver|reproduce)\s+(?:el\s+)?(?P<series>.+?)\s*,?\s+temporada\s+(?P<season>\d+|[a-z]+)$"),
     "WatchEpisodeIntent", None, {"episode": "1"}),
    (re.compile(rf"^(?:quiero ver|pon|ponga|ver)\s+(?:el\s+)?{_EPISODE}\s+de\s+(?P<series>.+?){_TAIL}$"),
     "WatchEpisodeIntent", None),
    # Reproductor de Orbital (van primero: "pon subtítulos" no es abrir un juego llamado así).
    # Sin slot fijo: los grupos con nombre son los slots.
    (re.compile(r"^(?:pausa|pause|pon pausa|ponle pausa|ponga pausa|para|deten)(?:\s+(?:el video|la pelicula|la serie))?$"),
     "PauseIntent", None),
    (re.compile(r"^(?:reanuda|reanude|quita la pausa|quite la pausa|dale play|dele play)(?:\s+el video)?$"),
     "ResumeIntent", None),
    (re.compile(r"^(?P<seek>adelanta|adelante|avanza|avance|salta|salte|pasa|regresa|regrese|retrocede|retroceda|atrasa|atrase)"
                r"(?:\s+el video)?\s+(?:(?P<amount>\d+|media|medio)|un|una)\s+(?P<unit>minutos?|segundos?|horas?)$"), "SeekIntent", None),
    (re.compile(r"^(?:(?:pon|ponga|ponle|ponles|activa|active|cambia|cambie)(?:\s+los)?\s+)?subtitulos"
                rf"(?:\s+(?:en|a)\s+(?P<language>{_LANGS}|\w+))?$"), "SubtitlesIntent", None),
    (re.compile(r"^(?:quita|quite|apaga|apague)\s+(?:los\s+)?subtitulos$|^sin subtitulos$"), "SubtitlesOffIntent", None),
    (re.compile(rf"^(?:(?:pon|ponga|cambia|cambie)(?:\s+el)?\s+)?(?:audio|idioma)\s+(?:en|a)\s+(?P<language>{_LANGS}|\w+)$"),
     "AudioLanguageIntent", None),
    (re.compile(rf"^(?:ponlo|pongalo|ponla|pongala|ponmelo|cambialo|cambiala)\s+(?:en|a)\s+(?P<language>{_LANGS}|\w+)$"),
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
    (re.compile(r"^(?:pon|ponga|sintoniza|sintonice|quiero ver)\s+(?!(?:la\s+)?(?:tele|television|tv)\s+en\s+vivo$)(?P<v>.+?)\s+en\s+vivo$"),
     "LiveTvIntent", "channel"),
    (re.compile(r"^(?:pon|ponga|abre|abra|quiero ver|prende|prenda)\s+(?:la\s+)?(?:tele|television|tv)(?:\s+en\s+vivo)?$"
                r"|^(?:tele|television|tv)\s+en\s+vivo$|^(?:pon|ponga|abre|abra)\s+los\s+canales$"), "LiveTvIntent", None),
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
                r"(?P<direction>juegos|peliculas y series|peliculas|series|apps|aplicaciones|explorar|para ti|recomendaciones|tv en vivo|tele en vivo)$"),
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
    # «prende la consola»: también prende la tele y la pone en la entrada de Orbital («prende la tele» es la TV en vivo)
    (re.compile(r"^(?:prende|prenda|prender|enciende|encienda|encender)\s+(?:la\s+consola|orbital)$"), "OpenOrbitalIntent", None),
    (re.compile(rf"^{_V['move']}\s+(?:a\s+(?:la\s+)?)?(?P<v>\w+)$"), "NavigateIntent", "direction"),
    (re.compile(rf"^{_V['play']}\s+(?P<v>.+)$"), "LaunchGameIntent", "game"),  # «el juego X»: kind_hint lo lee
]


_EPISODE_ONLY = [
    re.compile(rf"^(?:el\s+)?(?P<series>.+?)\s*,?\s+{_EPISODE}{_TAIL}$"),
    re.compile(rf"^(?:el\s+)?{_EPISODE}\s+de\s+(?P<series>.+?){_TAIL}$"),
]


MEDIA_OPTIONS = ("language", "subtitles", "from_start", "always")  # lo que va pegado a un título: «… en latino siempre»

NUMERIC = {"VolumeIntent", "SeekIntent", "PlayEpisodeIntent", "BrightnessIntent", "LiveTvIntent", "WatchEpisodeIntent"}  # «pon el volumen a cincuenta»: el número en palabras


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


# «Quiero que ABRAS Hades», «necesito que PONGAS el canal de los Simpson», «puedes subir el volumen»: lo que va después de
# una cortesía. El subjuntivo de tú (y casi todos los infinitivos) no se entendía (sí «ponga»): se lleva al imperativo.
_LEAD_IN = re.compile(r"^(?:(?:quiero|necesito|me gustaria|te pido|quisiera)\s+que|(?:puedes|podrias|podras|me puedes|me podrias)"
                      r"|(?:hazme el favor de|ayudame a|me ayudas a|trata de|intenta))\s+")

_TU = {"abras": "abre", "pongas": "pon", "subas": "sube", "bajes": "baja", "quites": "quita", "adelantes": "adelanta",
       "atrases": "atrasa", "regreses": "regresa", "cierres": "cierra", "sigas": "sigue", "continues": "continua",
       "busques": "busca", "reproduzcas": "reproduce", "juegues": "juega", "inicies": "inicia", "lances": "lanza",
       "pauses": "pausa", "pares": "para", "detengas": "deten", "vayas": "ve", "muestres": "muestra", "vuelvas": "vuelve",
       "saltes": "salta", "cambies": "cambia", "enciendas": "enciende", "prendas": "prende", "apagues": "apaga",
       "silencies": "silencia", "actives": "activa", "desactives": "desactiva", "sintonices": "sintoniza",
       "recomiendes": "recomienda", "avances": "avanza", "digas": "di", "captures": "captura", "tomes": "toma",
       # El infinitivo después de «puedes…» («¿puedes subir el volumen?»): antes solo se entendían poner, abrir y buscar.
       "subir": "sube", "bajar": "baja", "quitar": "quita", "adelantar": "adelanta", "atrasar": "atrasa", "regresar": "regresa",
       "pausar": "pausa", "parar": "para", "detener": "deten", "cambiar": "cambia", "saltar": "salta", "silenciar": "silencia",
       "activar": "activa", "desactivar": "desactiva", "prender": "prende", "encender": "enciende", "apagar": "apaga",
       "sintonizar": "sintoniza", "recomendar": "recomienda", "avanzar": "avanza", "capturar": "captura", "tomar": "toma"}


def _plain(clean: str) -> str:
    clean = _LEAD_IN.sub("", clean, count=1)
    words = clean.split()
    while words and words[0] in ("le", "me", "se", "nos", "que"):
        words = words[1:]
    if words:
        words[0] = _TU.get(words[0], words[0])
    text = " ".join(_CLITIC_VERBS.get(w, w) for w in words)
    text = re.sub(r"\b(?:tantito|un poquito|un poco|mas)$", "", text).strip()
    text = re.sub(r"^(sube|suba|baja|baje)\s+al\s+volumen", r"\1 el volumen", text)
    text = re.sub(r"^(sube|suba|baja|baje)(?:\s+al)?$", r"\1 el volumen", text)  # «súbele» a secas
    text = re.sub(r"^(?:ponle|dale|dele)\s+play$", "dale play", text)
    return text


# --- lo que la gente dice de más (Siri, el micrófono del iPhone, Alexa con texto libre) -------------------------------
# «Oye Siri, dile a Orbital que ponga Dune por favor en la tele» llega como «que ponga dune por favor en la tele»: antes
# no se entendía, o se buscaba un título llamado «dune por favor en la tele».
_ADDRESS = re.compile(r"^(?:(?:oye|hey|ok|okay|eh)\s+)?(?:(?:orbital|consola|mi consola)\s+)?"
                      r"(?:(?:dile|digale|pidele|pidale|pide)\s+(?:a\s+)?(?:orbital|la consola|mi consola)\s+que\s+)?")

_POLITE = re.compile(r"\s+(?:por favor|porfa|porfis|porfavor|please|ahora|ya|ahorita)$|^(?:por favor|porfa)\s+")

_WHERE = re.compile(r"\s+en\s+(?:la\s+)?(?:tele|television|tv|pantalla|consola|orbital|la sala)$")

# «Alexa, pausa en Orbital», «Alexa, pon Dune con Orbital»: Alexa deja el nombre de la skill pegado a la frase y a veces lo
# oye junto («norbital»). Nada coincidía («dune norbital») y Alexa contestaba «No entendí» sin preguntarle a la consola.
_INVOKED = re.compile(r"\s+(?:(?:en|con|desde|a)\s+(?:la\s+)?orbital|n\s?orbital)$")

# Lo mismo en un slot de Alexa, que llega sin normalizar («Dune en Orbital», «la película norbital»).
_INVOKED_SLOT = re.compile(r"\s+(?:(?:en|con|desde|a)\s+(?:la\s+)?|n\s?)?[oó]rbit[aá]l[.?!]?$", re.IGNORECASE)


def slot_text(value: str) -> str:
    """Un slot de Alexa sin el nombre de la skill que se le pegó al final."""
    return _INVOKED_SLOT.sub("", value).strip()

# Verbos que la gente usa y no estaban: se llevan a los que ya se entienden.
_SAY_AS = [
    (re.compile(r"^(?:quisiera|me gustaria|quiero|vamos a|voy a|deseo)\s+(?:ver|mirar)\s+"), "quiero ver "),
    (re.compile(r"^(?:quisiera|me gustaria|quiero|vamos a|voy a|a)\s+jugar(?:\s+a(?:l)?)?\s+"), "juega "),
    (re.compile(r"^juega\s+a(?:l)?\s+"), "juega "),
    (re.compile(r"^(?:mas\s+(?:alto|fuerte|volumen)|subele\s+mas)$"), "sube el volumen"),
    (re.compile(r"^(?:mas\s+(?:bajo|bajito|quedito)|menos\s+volumen)$"), "baja el volumen"),
    (re.compile(r"^volumen\s+(?:a|al|en)\s+"), "pon el volumen al "),
    (re.compile(r"^volumen\s+(?=\d|[a-z]+$)"), "pon el volumen al "),
    (re.compile(r"^ver\s+(?!a\b)"), "quiero ver "),
    (re.compile(r"^(regresale|regresele|atrasale|adelantale|adelantele)\s+(?:tantito|un poquito|un poco)$"), r"\1"),
    (re.compile(r"^(?:callate|callese|silenciala|silencialo|sin sonido)$"), "silencio"),
    # «ve al inicio», «regresa al inicio»: la contracción no se entendía (sí «ve a inicio»).
    (re.compile(r"^(?:ve|vete|vaya|ir|regresa|regrese|vuelve|vuelva)\s+al\s+(?:inicio|principio)$"), "ve a inicio"),
    (re.compile(r"^cuanto\s+(?:tiempo\s+)?(?:le\s+)?(?:falta|queda)\s+(?:para\s+que\s+)?(?:acabe|termine|se acabe)$"), "cuanto falta"),
]

# Episodios como se dicen: «quinta temporada», «el quinto capítulo», «T5 E3», «s05e03», «5x03».
_ORDINALS = {"primer": 1, "primera": 1, "primero": 1, "segunda": 2, "segundo": 2, "tercera": 3, "tercer": 3, "tercero": 3,
             "cuarta": 4, "cuarto": 4, "quinta": 5, "quinto": 5, "sexta": 6, "sexto": 6, "septima": 7, "septimo": 7,
             "octava": 8, "octavo": 8, "novena": 9, "noveno": 9, "decima": 10, "decimo": 10}

_ORD = "|".join(sorted(_ORDINALS, key=len, reverse=True))

_EPISODE_FORMS = [
    (re.compile(rf"\b(?:la\s+)?({_ORD})\s+temporada\b"), lambda m: f"temporada {_ORDINALS[m.group(1)]}"),
    (re.compile(rf"\b(?:el\s+)?({_ORD})\s+(episodio|capitulo)\b"), lambda m: f"el {m.group(2)} {_ORDINALS[m.group(1)]}"),
    (re.compile(r"\bs(\d{1,2})\s*e(\d{1,3})\b"), lambda m: f"temporada {int(m.group(1))} episodio {int(m.group(2))}"),
    (re.compile(r"\bt\s*(\d{1,2})\s*,?\s*e\s*(\d{1,3})\b"), lambda m: f"temporada {int(m.group(1))} episodio {int(m.group(2))}"),
    (re.compile(r"\b(\d{1,2})x(\d{1,3})\b"), lambda m: f"temporada {int(m.group(1))} episodio {int(m.group(2))}"),
]


def tidy(clean: str) -> str:
    """Lo dicho, sin lo que sobra: a quién se le habla («dile a Orbital que»), cortesía («por favor») y dónde («en la
    tele»); los verbos y las formas de episodio que la gente usa, llevados a los que se entienden. `clean` ya normalizado."""
    text = _ADDRESS.sub("", clean, count=1).strip()
    for _ in range(2):  # «… por favor en la tele» y «… en la tele por favor»
        text = _INVOKED.sub("", _WHERE.sub("", _POLITE.sub("", text))).strip()
    for pattern, said in _SAY_AS:
        text = pattern.sub(said, text, count=1)
    if re.search(r"temporada|episodio|capitulo|\bs\d|\bt\s*\d|\dx\d", text):
        for pattern, form in _EPISODE_FORMS:
            text = pattern.sub(form, text)
        text = words_to_numbers(text)
    return re.sub(r"\s+", " ", text).strip()


_KIND_WORDS = re.compile(r"^(?:(?:la|el|una|un|esa|ese)\s+)?(?P<kind>pelicula|peli|serie|caricatura|documental|novela|telenovela|juego)"
                         r"(?:\s+(?:de|que se llama|llamada|llamado))?\s+(?P<title>.+)$")

_KIND_OF = {"pelicula": "movie", "peli": "movie", "documental": "movie", "serie": "series", "caricatura": "series",
            "novela": "series", "telenovela": "series", "juego": "game"}


def kind_hint(name: str) -> tuple[str, str | None]:
    """«la película Dune» → ("dune", "movie"); «el juego Hades» → ("hades", "game"); lo demás, tal cual. Antes se buscaba un
    título llamado «la pelicula dune»."""
    m = _KIND_WORDS.match(normalize(name))
    return (m.group("title"), _KIND_OF[m.group("kind")]) if m else (name, None)


def parse_text(text: str) -> tuple[str, dict[str, str]] | None:
    clean, always = always_said(tidy(normalize(text)))
    if not clean:
        return None
    found = _parse(clean)
    if found is None and clean.startswith("que "):  # «que ponga Dune» (Siri: «dile a Orbital que…»); «qué estoy jugando» no
        found = _parse(clean[4:])
    if found is None:
        plain = _plain(clean)
        if plain and plain != clean:
            found = _parse(tidy(plain))
    if found is not None and always:
        found[1]["always"] = "1"
    return found


_TITLE_TAIL = [
    ("from_start", re.compile(r"\s+desde\s+(?:el\s+)?(?:principio|inicio|cero|el primer capitulo)$")),
    ("subtitles", re.compile(rf"\s+con\s+subtitulos(?:\s+en\s+(?P<lang>{_LANGS}))?$")),
    ("language", re.compile(rf"\s+en\s+(?P<lang>{_LANGS})$")),
]


def title_tail(title: str) -> tuple[str, dict[str, str]]:
    """«dune en ingles con subtitulos desde el principio» → ("dune", {language, subtitles, from_start}). `title` normalizado."""
    out: dict[str, str] = {}
    for _ in range(3):  # en cualquier orden
        for key, pattern in _TITLE_TAIL:
            m = pattern.search(title)
            if m:
                out[key] = (m.groupdict().get("lang") or "1") if key != "language" else m.group("lang")
                title = title[:m.start()].strip()
    return title, out


def _title_slots(title: str) -> dict[str, str]:
    """«la película de Dune en inglés con subtítulos desde el principio» → title «dune», kind, language, subtitles,
    from_start: lo que va pegado al título se vuelve opciones (antes se buscaba todo como si fuera el nombre)."""
    title, out = title_tail(title)
    title, kind = kind_hint(title)
    if kind:
        out["kind"] = kind
    out["title"] = title
    return out


def _parse(clean: str) -> tuple[str, dict[str, str]] | None:
    numeric = words_to_numbers(clean)
    for pattern, intent, slot, *fixed in _TEXT_RULES:
        m = pattern.match(numeric if intent in NUMERIC else clean)
        if m:
            if fixed:
                found = {k: v for k, v in m.groupdict().items() if v and k != "tail"}
                return intent, {**found, **_media_tail(m.groupdict().get("tail") or ""), **fixed[0]}
            if slot:
                if not m.group("v"):
                    return intent, {}
                if intent in ("LaunchGameIntent", "SearchMediaIntent"):  # el título, sin lo que va pegado
                    extra = _title_slots(m.group("v"))
                    return intent, {slot: extra.pop("title"), **extra}
                return intent, {slot: m.group("v")}
            found = {k.rstrip("23"): v for k, v in m.groupdict().items() if v and k != "tail"}
            if m.groupdict().get("tail"):
                found.update(_media_tail(m.group("tail")))
            return intent, found
    return None
