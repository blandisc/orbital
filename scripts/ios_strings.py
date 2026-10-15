"""Genera `ios/App/Resources/Localizable.xcstrings` (español base, inglés) y comprueba que ningún texto de la app se quede sin traducir.

    python scripts/ios_strings.py            # escribe el catálogo
    python scripts/ios_strings.py --check    # solo comprueba (falla si falta una traducción)

Los textos de las pantallas son su propia clave (en español), como en la TV. Para agregar uno: escríbelo en la pantalla y
añade aquí su traducción; la comprobación avisa si se te olvida.
"""

from __future__ import annotations

import glob
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "ios/App/Resources/Localizable.xcstrings"

TRANSLATIONS = {
    "Abrir en Infuse": "Open in Infuse", "Abrir siempre en Infuse": "Always open in Infuse", "Adelantar 10 segundos": "Forward 10 seconds",
    "Agregar complemento": "Add add-on", "Ajustes": "Settings", "Al instante": "Instant", "Audio": "Audio", "Audio y subtítulos": "Audio and subtitles",
    "Aparece un código para escribir en trakt.tv/activate. Con Trakt conectado se avisa de lo que ves y salen tu watchlist y tus listas.":
        "A code appears to enter at trakt.tv/activate. With Trakt connected, what you watch is reported and your watchlist and lists show up.",
    "Aquí aparece lo que vas viendo, en el iPhone y en Orbital.": "What you're watching shows up here, on iPhone and on Orbital.",
    "Añadir a Mi lista": "Add to My List", "En Mi lista": "In My List",
    "Lo más popular en Stremio. Conecta Trakt en Ajustes y el mosaico se arma con lo tuyo.": "What's popular on Stremio. Connect Trakt in Settings and the mosaic is built from your stuff.", "Nada descargado": "Nothing downloaded", "Avance": "Progress",
    "Bajar el siguiente episodio al terminar uno": "Download the next episode when one finishes", "Borrar": "Delete",
    "Borrar al terminar de verlo": "Delete when watched", "Buscando la mejor fuente…": "Finding the best source…",
    "Buscar películas y series": "Search movies and series", "Búsquedas recientes": "Recent searches", "Calidad": "Quality",
    "Cancelar": "Cancel", "Cerrar": "Close", "Cerrar sesión": "Sign out", "Clave de TMDB": "TMDB key", "Clave de TMDB guardada": "TMDB key saved",
    "Complementos": "Add-ons", "Con Wi‑Fi": "On Wi‑Fi", "Con datos móviles": "On cellular data",
    "Con datos móviles te avisamos antes de usar fuentes de más de 5 GB.": "On cellular data we warn you before using sources over 5 GB.",
    "Conecta Trakt o agrega una clave de TMDB en Ajustes para ver sugerencias.": "Connect Trakt or add a TMDB key in Settings to see suggestions.",
    "Conectar Trakt": "Connect Trakt", "Continuar": "Continue", "Continuar T%lld E%lld": "Continue S%lld E%lld", "Contraseña": "Password",
    "Correo de Stremio": "Stremio email", "Cuando descargues algo, aparece aquí.": "When you download something, it shows up here.", "Cuenta": "Account",
    "Descargado": "Downloaded", "Descargando": "Downloading", "Descargar": "Download", "Descargar con la fuente recomendada": "Download with the recommended source",
    "Descargar solo con Wi‑Fi": "Download only on Wi‑Fi", "Descargas": "Downloads", "Desconectar Trakt": "Disconnect Trakt", "Descubrir": "Discover",
    "Descargando. Lo verás en Descargas.": "Downloading. You'll see it in Downloads.", "Dirección": "Directed by",
    "El código caducó. Vuelve a intentarlo.": "The code expired. Try again.", "Elegir fuente": "Choose source",
    "Elegir la fuente de este episodio": "Choose this episode's source", "Empieza en %lld s": "Starts in %lld s", "En cola": "Queued", "En pausa": "Paused",
    "En tendencia": "Trending", "En tu lista": "In your list", "En tu watchlist de Trakt": "In your Trakt watchlist", "En %@": "On %@", "En «%@»": "In “%@”",
    "Entra con tu cuenta de Stremio. Lo que veas aquí aparece en Orbital y al revés.": "Sign in with your Stremio account. What you watch here shows up on Orbital and vice versa.",
    "Entrar": "Sign in", "Episodio %lld": "Episode %lld", "Escribe este código en %@:": "Enter this code at %@:",
    "Escribe tu correo y tu contraseña de Stremio.": "Enter your Stremio email and password.", "Ese complemento no responde o no da fuentes ni fichas.": "That add-on doesn't respond or provides no sources or details.",
    "Especiales": "Specials", "Esperando…": "Waiting…", "Fuentes de Real-Debrid": "Real-Debrid sources", "Guardar clave de TMDB": "Save TMDB key", "Guion": "Written by", "Guardar secreto": "Save secret",
    "Identificador de la aplicación (client id)": "Application identifier (client id)", "Idioma": "Language", "Idioma de la app y de las fichas": "App and title language",
    "Infuse no dice cuánto dura, así que no sé si llegaste al final.": "Infuse doesn't report the length, so I can't tell if you reached the end.",
    "Infuse no pudo reproducirlo.": "Infuse couldn't play it.", "Infuse no pudo reproducirlo: %@": "Infuse couldn't play it: %@", "Inicio": "Home",
    "La recomendada está arriba.": "The recommended one is at the top.", "Libres %@": "%@ free", "Listas": "Lists", "Listas para ver sin conexión": "Ready to watch offline",
    "Llevas tres episodios seguidos.": "You've watched three episodes in a row.", "Lo más popular": "Most popular", "Los siguientes 3 episodios": "The next 3 episodes",
    "Marcar como visto": "Mark as watched", "Mi lista": "My List", "Mosaico": "Mosaic", "Motor": "Engine", "Más": "More",
    "Ninguna fuente funcionó.": "No source worked.", "No": "No", "No encontré nada con ese nombre.": "I couldn't find anything with that name.",
    "No hay fuentes de Real-Debrid para descargar.": "No Real-Debrid sources to download.", "No hay fuentes de Real-Debrid para este título.": "No Real-Debrid sources for this title.",
    "No hay nada aquí todavía.": "Nothing here yet.", "No me interesa": "Not interested", "No pude abrir Infuse. ¿Está instalado?": "I couldn't open Infuse. Is it installed?",
    "No pude abrir el archivo descargado.": "I couldn't open the downloaded file.", "No pude abrir ese título.": "I couldn't open that title.",
    "No pude leer el catálogo de Stremio. Revisa tu conexión.": "I couldn't read the Stremio catalog. Check your connection.", "No se pudo descargar": "Download failed",
    "Ocupan %@": "%@ used", "Otra fuente": "Another source", "Otra fuente…": "Another source…",
    "Para conectar Trakt hace falta una aplicación de la API de Trakt (trakt.tv/oauth/applications). Pega aquí su identificador.":
        "To connect Trakt you need a Trakt API application (trakt.tv/oauth/applications). Paste its identifier here.",
    "Para ti": "For You", "Pausa": "Pause", "Pausar": "Pause", "País (para lo popular en plataformas)": "Country (for what's popular on platforms)",
    "Pega la dirección completa del complemento (https://…).": "Paste the add-on's full address (https://…).", "Pegar la dirección de un complemento": "Paste an add-on address",
    "Películas": "Movies", "Películas populares": "Popular movies", "Pendientes en Trakt": "Pending on Trakt", "Popular": "Popular",
    "Probando otra fuente (%lld)…": "Trying another source (%lld)…", "Quitar": "Remove", "Quitar de Mi lista": "Remove from My List", "Quitar de Seguir viendo": "Remove from Continue Watching",
    "Reanudar": "Resume", "Rechazaste la conexión en Trakt.": "You declined the connection on Trakt.", "Recomendada": "Recommended", "Recomendadas": "Recommended",
    "Reparto": "Cast", "Reproducir": "Play", "Reproducir T%lld E%lld": "Play S%lld E%lld", "Reproductor": "Player", "Retroceder 10 segundos": "Back 10 seconds",
    "Salir": "Leave", "Saltar intro": "Skip intro", "Secreto (si tu aplicación lo tiene)": "Secret (if your application has one)", "Seguir": "Continue",
    "Seguir viendo": "Continue Watching", "Series": "Series", "Series populares": "Popular series", "Sigue": "Next up", "Sigues viéndola": "You're watching",
    "Siguiente episodio": "Next episode", "Sin conexión: se ve lo último que guardé.": "Offline: showing what I saved last.", "Sin pistas de audio": "No audio tracks",
    "Sin subtítulos": "No subtitles", "Solo con Wi‑Fi": "Wi‑Fi only", "Solo subtítulos forzados": "Forced subtitles only", "Stremio al día": "Stremio up to date",
    "Stremio conectado": "Stremio connected", "Subtítulos": "Subtitles", "Sugerencias": "Suggestions", "Sí, marcar como visto": "Yes, mark as watched",
    "TMDB pone las fichas en español y busca lo popular en Netflix, Disney+ y HBO Max.": "TMDB provides translated titles and finds what's popular on Netflix, Disney+ and HBO Max.",
    "T%lld · E%lld": "S%lld · E%lld", "E%lld": "E%lld", "Temporada %lld": "Season %lld", "Todo": "All", "Trakt al día": "Trakt up to date", "Trakt conectado": "Trakt connected",
    "Trakt no aceptó el código.": "Trakt didn't accept the code.", "Trakt: %@": "Trakt: %@",
    "Tu contraseña no se guarda: solo la clave de sesión, en el Keychain de tu iPhone.": "Your password isn't stored: only the session key, in your iPhone's Keychain.",
    "Tu watchlist": "Your watchlist", "Tuyo": "Yours", "Ver": "Watch", "Ver ahora": "Watch now", "Viendo": "Watching", "Visto": "Watched", "Volver a intentar": "Try again",
    "Watchlist": "Watchlist", "Ya está descargado.": "Already downloaded.", "%lld cambios por subir": "%lld changes to upload",
    "¿Cerrar sesión de Stremio?": "Sign out of Stremio?", "¿Sigues viendo?": "Still watching?", "¿Terminaste de verlo?": "Did you finish it?",
    "quedan %lld h %lld min": "%lld h %lld min left", "quedan %lld h": "%lld h left", "quedan %lld min": "%lld min left",
    "Descargando %lld episodios. Los verás en Descargas.": "Downloading %lld episodes. You'll see them in Downloads.",
    "No pude cambiar tu lista de Stremio: %@": "I couldn't change your Stremio list: %@", "No pude cambiar tu watchlist de Trakt: %@": "I couldn't change your Trakt watchlist: %@",
    "No pude marcarlo: %@": "I couldn't mark it: %@", "No pude pedir las fuentes: %@": "I couldn't get the sources: %@",
    "Descargar": "Download", "Cuenta": "Account", "%@ de %@": "%@ of %@", "Cerrar": "Close", "Sí": "Yes",
}
# Textos que no se traducen: nombres propios, ids y formatos.
IGNORE = {"T\\($0) · E\\($1)", "AVPlayer", "AetherEngine", "BluRay", "WEB-DL", "Orbital", "Trakt", "English", "Español", "1080p", "720p", "4K", "TMDB", "Infuse", "Stremio", "Real-Debrid",
          "REMUX", "Atmos", "Dolby Vision", "Netflix", "Disney+", "HBO Max"}
# Textos que se arman en código (modelos) y llegan a la pantalla: se traducen si coinciden con una clave.
CODE_KEYS = {k for k in TRANSLATIONS}

INT_HINT = re.compile(r"^(Int\(|count\b|card\.secondsLeft|row\.number|season\.season|\bs\b|\be\b|\bh\b|\bm\b|\bn\b|episode\b|fraction)")


def to_format(literal: str) -> str:
    """El literal de Swift con `\\(…)` → la clave que genera SwiftUI (%lld para enteros, %@ para el resto)."""
    def repl(m: re.Match) -> str:
        expr = m.group(1)
        return "%lld" if INT_HINT.match(expr) else "%@"
    # Interpolaciones sin paréntesis anidados profundos (el código de la app no usa más de un nivel).
    out, i = "", 0
    while i < len(literal):
        if literal.startswith("\\(", i):
            depth, j = 1, i + 2
            while j < len(literal) and depth:
                depth += (literal[j] == "(") - (literal[j] == ")")
                j += 1
            out += repl(re.match(r"(.*)", literal[i + 2:j - 1]))
            i = j
        else:
            out += literal[i]; i += 1
    return out


def used_literals() -> dict[str, str]:
    lit = re.compile(r'"((?:[^"\\]|\\.)*)"')
    found: dict[str, str] = {}
    files = glob.glob(str(ROOT / "ios/App/Sources/**/*.swift"), recursive=True) + glob.glob(str(ROOT / "ios/OrbitalCore/Sources/OrbitalModels/*.swift"))
    for f in files:
        if "/Design/" in f or "/Platform/" in f or f.endswith("/Support/Demo.swift"):   # el modo demo (solo Debug) no se traduce
            continue
        for number, line in enumerate(Path(f).read_text(encoding="utf-8").splitlines(), 1):
            stripped = line.strip()
            if stripped.startswith("//"):
                continue
            for m in lit.finditer(line):
                text = m.group(1)
                if len(text) < 3 or not re.match(r"^[A-ZÁÉÍÓÚÑ¿]", text) or text in IGNORE:
                    continue
                if re.fullmatch(r"[A-Z0-9_ ]+", text) and len(text) < 6:
                    continue
                key = to_format(text)
                if re.fullmatch(r"(%lld|%@|[ ·:|\-−/])+", key) or "|" in key or key.startswith("%@:") or key.startswith("%@-"):
                    continue
                found.setdefault(key, f"{Path(f).name}:{number}")
    return found


def build() -> dict:
    strings = {}
    for key, english in sorted(TRANSLATIONS.items()):
        strings[key] = {"extractionState": "manual", "localizations": {"en": {"stringUnit": {"state": "translated", "value": english}}}}
    return {"sourceLanguage": "es", "strings": strings, "version": "1.0"}


def main() -> int:
    missing = {k: where for k, where in used_literals().items() if k not in TRANSLATIONS}
    # Algunos literales son nombres de símbolos, ids o formatos de código (no son textos de pantalla).
    ignorable = {k for k in missing if re.fullmatch(r"[A-Za-z0-9_.]+", k) and " " not in k}
    for k in ignorable:
        missing.pop(k)
    if missing:
        print("Faltan traducciones al inglés (agrégalas a TRANSLATIONS en scripts/ios_strings.py):")
        for key, where in sorted(missing.items()):
            print(f"  {where}: {key!r}")
        if "--check" in sys.argv or True:
            return 1
    if "--check" not in sys.argv:
        OUT.parent.mkdir(parents=True, exist_ok=True)
        OUT.write_text(json.dumps(build(), ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print(f"Escrito {OUT.relative_to(ROOT)} con {len(TRANSLATIONS)} textos")
    else:
        print("Todos los textos tienen traducción.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
