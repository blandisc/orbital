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
    "Con géneros elegidos, el ánimo no cuenta.": "With genres picked, the mood doesn't count.", "Géneros": "Genres", "Incluir lo que ya vi": "Include what I've watched",
    "Ir a una sección": "Go to a section", "Mejor calificadas en IMDb": "Top rated on IMDb", "Mejor calificadas en Trakt": "Top rated on Trakt",
    "Menos opciones": "Fewer options", "Más opciones": "More options", "Qué": "What", "Toca otra vez para confirmar": "Tap again to confirm",
    "Todo lo que estás viendo": "Everything you're watching", "Todo lo que estás viendo · %@": "Everything you're watching · %@", "¿Ver en la TV?": "Watch on the TV?",
    "Listas de Trakt": "Trakt lists", "Listas de Stremio": "Stremio lists", "Próximos estrenos": "Upcoming",
    "Abre el control de tu Orbital.": "Opens your Orbital's remote.", "Abrir el control de Orbital": "Open the Orbital remote", "Control de Orbital": "Orbital remote",
    "Episodios de estas semanas y películas recién llegadas": "This week's episodes and newly arrived movies", "Estudios": "Studios",
    "Lo más visto": "Most watched", "Lo más visto de cada uno": "The most watched from each", "Nuevo en tus plataformas": "New on your platforms",
    "Año: más nuevas": "Year: newest", "Año: más viejas": "Year: oldest", "A–Z": "A–Z", "Como viene la lista": "As the list comes", "De %@": "From %@",
    "Género": "Genre", "Listas de Stremio": "Stremio lists", "Listas de Trakt": "Trakt lists", "Lo que Trakt relaciona con lo último que viste": "What Trakt relates to what you watched last",
    "Mostrar": "Show", "Nada con estos filtros.": "Nothing with these filters.", "Ocultar lo que ya vi": "Hide what I've watched", "Ordenar y filtrar": "Sort and filter",
    "Porque viste": "Because you watched", "Series o películas": "Shows or movies", "Sin lo que ya vi": "Without what I've watched", "Ordenar": "Sort", "Todos": "All",
    "Tus series": "Your shows", "Tu watchlist": "Your watchlist", "Mi lista": "My list",
    "Cine mexicano": "Mexican cinema", "De Trakt": "From Trakt", "Globos de Oro": "Golden Globes", "Lo más popular de cada año": "The most popular of each year",
    "Los ganadores, del más reciente": "The winners, newest first", "Mejor película": "Best Picture", "Mejor película dramática": "Best Motion Picture – Drama",
    "Mejor serie de drama": "Outstanding Drama Series", "Palma de Oro": "Palme d'Or", "Plataformas": "Platforms", "Por año": "By year", "Premios": "Awards",
    "Tus listas": "Your lists", "Óscar": "Oscar", "Ariel": "Ariel", "Emmy": "Emmy", "Cannes": "Cannes", "%lld títulos": "%lld titles",
    "Complementos, TMDB, país": "Add-ons, TMDB, country", "Crear": "Create", "Desde tu Orbital": "From your Orbital", "Guardar en…": "Save to…",
    "No pude cambiar tu lista de Trakt: %@": "I couldn't change your Trakt list: %@", "No pude crear la lista: %@": "I couldn't create the list: %@",
    "Nombre": "Name", "Nueva lista": "New list", "Nueva lista…": "New list…", "Ponle nombre a la lista": "Give the list a name",
    "Se crea en Trakt (privada) y este título entra en ella.": "It's created on Trakt (private) and this title goes in it.",
    "Todo lo que sigues": "Everything you're watching", "Todo lo que sigues · %@": "Everything you're watching · %@", "Tus listas de Trakt": "Your Trakt lists",
    "Avanzado": "Advanced", "Guardar": "Save", "Guardado": "Saved", "Ver": "View", "Pasó a tu Orbital": "Moved to your Orbital",
    "Cambiar lo que quiero": "Change what I want", "Conecta Trakt (en tu Orbital o en Ajustes) para ver tu año.": "Connect Trakt (on your Orbital or in Settings) to see your year.",
    "De lo último que viste": "From what you watched lately", "Decide por mí": "Decide for me", "Día por día": "Day by day", "En pareja": "As a couple",
    "Hoy no": "Not today", "Las dos": "Both", "Lo que más viste": "What you watched most", "Lo que viste": "What you watched",
    "No encontré otra con eso: prueba otro ánimo o más tiempo.": "I couldn't find another one: try another mood or more time.",
    "Otra": "Another", "Para pensar": "Thought-provoking", "Porque viste %@": "Because you watched %@", "Quiero algo": "I want something",
    "Sale el %@": "Out %@", "Sale mañana": "Out tomorrow", "Sale hoy": "Out today", "Tu %@": "Your %@", "Tu año": "Your year",
    "Una sola, de tus sugerencias, que no hayas visto.": "Just one, from your suggestions, that you haven't seen.", "¿Qué vemos?": "What should we watch?",
    "Tengo": "I have", "30 min": "30 min", "1 h": "1 h", "2 h o más": "2 h or more", "Ligero": "Light", "Intenso": "Intense",
    "vistas": "watched", "racha más larga": "longest streak", "tu género": "your genre", "%lld días": "%lld days",
    "%lld películas · %lld episodios": "%lld movies · %lld episodes", "%lld días con algo visto": "%lld days with something watched",
    "Tendencia": "Trending", "Top 10": "Top 10",
    "Hola": "Hi", "Hola, %@": "Hi, %@", "Cómo te llamamos": "What we call you", "Tu nombre": "Your name",
    "Actualiza tu Orbital para cambiar el volumen desde aquí.": "Update your Orbital to change the volume from here.",
    "Alexa, pídele a mi consola que…": "Alexa, ask my console to…", "Bajar volumen": "Volume down", "Subir volumen": "Volume up", "Quitar silencio": "Unmute",
    "Descargar funciona aunque estés fuera de casa.": "Downloading works even away from home.",
    "Estira el control hacia arriba y toca «Dile a Orbital». Se detiene solo cuando terminas.": "Pull the remote up and tap “Tell Orbital”. It stops on its own when you finish.",
    "Las frases de abajo funcionan igual en los tres.": "The phrases below work the same in all three.", "Oye Siri, habla con Orbital": "Hey Siri, talk to Orbital",
    "Sin «pídele a mi consola», Alexa intenta hacerlo ella sola.": "Without “ask my console”, Alexa tries to do it herself.",
    "Y cuando pregunte, la orden. Directo: «Oye Siri, pausa Orbital».": "Then, when asked, the command. Direct: “Hey Siri, pause Orbital”.",
    "Saltar resumen": "Skip recap",
    "Lo mejor disponible": "Best available",
    "Sale pronto": "Coming up", "Ver todo": "See all", "Sale hoy": "Out today",
    "Más lento": "Slower", "Más rápido": "Faster",
    "%@ de %@": "%@ of %@",
    "Ajustes del video": "Video settings", "Archivo descargado": "Downloaded file", "La que tienes": "Current", "Pasó a tu Orbital": "Moved to your Orbital",
    "Tamaño": "Size", "Tarda en empezar": "Slow to start", "Tu idioma": "Your language", "Ventana": "Window", "Idiomas": "Languages", "Otros": "Others",
    "Otras": "Others", "Al instante": "Instant", "Atrás": "Back", "%@ · sigue en %@": "%@ · continues at %@", "Deshacer": "Undo",
    "Creación": "Created by", "Dónde verlo": "Where to watch", "Este título no está en Stremio.": "This title isn't on Stremio.", "Filmografía": "Filmography",
    "La saga": "The saga", "Marcar temporada como vista": "Mark season as watched", "Más como esto": "More like this",
    "No pude traer a esta persona de TMDB.": "Couldn't load this person from TMDB.", "Reparto y equipo": "Cast and crew", "Tráiler y extras": "Trailer and extras",
    "Novela": "Novel", "%lld de %lld vistos": "%lld of %lld watched",
    "Sus rankings de hoy": "Their charts today", "%lld descargando": "%lld downloading", "Descarga inteligente": "Smart downloads",
    "En la TV: %@": "On TV: %@", "Sale hoy: %@": "Out today: %@", "%lld por terminar": "%lld to finish", "Inicio": "Home",
    "Otras apps": "Other apps", "Espacio": "Storage", "%@ libres de %@": "%@ free of %@",
    "%lld episodio": "%lld episode", "%lld temporadas": "%lld seasons", "Temporada %lld": "Season %lld", "Temporada %@": "Season %@", "Series": "Shows", "Películas": "Movies",
    # Repensado: Ajustes por páginas, un solo filtro en Para ti, Buscar integrado
    "Cambiar avatar": "Change avatar", "Conectado": "Connected", "Conectado: %@": "Connected: %@", "Conectando…": "Connecting…",
    "Conexiones": "Connections", "Cómo se acomodan las tarjetas de «Seguir viendo».": "How the Continue Watching cards are arranged.",
    "Cómo te dice la tarjeta lo que te queda por ver.": "How the card tells you how much is left.", "Idioma y subtítulos": "Language and subtitles",
    "Por género": "By genre", "Reproducción": "Playback", "Siempre": "Always", "Sin conectar": "Not connected", "Tu avatar": "Your avatar",
    "Tu perfil": "Your profile", "Ver el mosaico": "Show the mosaic", "Ver las listas": "Show the lists", "Voz y Siri": "Voice and Siri",
    "Ícono de la app": "App icon",
    # Proyección: modo claro y oscuro
    "Falta el archivo parcial": "The partial file is missing", "No se pudo reproducir": "Could not play",
    "Puesto %lld": "No. %lld", "Puesto %@": "No. %@", "Control remoto": "Remote control", "Esta semana en México": "This week in Mexico", "Las que estás viendo": "Shows you're watching", "Tendencia en JustWatch · México": "JustWatch trend · Mexico",
    "Tendencias en %@": "Trending on %@", "Top 10 en %@": "Top 10 on %@",
    "En tu watchlist": "In your watchlist", "En una de tus listas": "In one of your lists", "Tus series": "Your shows",
    "Nada por aquí por ahora.": "Nothing here for now.", "Ver %@": "Watch %@", "Ver T%lld E%lld": "Watch S%lld E%lld",
    "Ver la serie": "View series", "Elegir fuente": "Choose source", "Ver en la TV": "Watch on TV",
    "Descarga inteligente": "Smart downloads", "Listas para ver": "Ready to watch", "Ocupan %@ · libres %@": "%@ used · %@ free",
    "%lld episodios": "%lld episodes", "En la TV": "On TV", "En la TV · En vivo": "On TV · Live", "Reanudar": "Resume", "Pausa": "Pause",
    "Buscar": "Search", "Compartir": "Share", "Explora": "Explore", "Lo más popular hoy": "Most popular today", "Películas y series": "Movies and series",
    "Sci-Fi": "Sci-Fi", "termina a las %@": "ends at %@", "Nuevo": "New", "%lld de %lld": "%lld of %lld",
    "Apariencia": "Appearance", "Modo": "Mode", "Como el iPhone": "Match iPhone", "Claro": "Light", "Oscuro": "Dark",
    # Pasada de pulido (octubre 2026)
    "De tu Orbital": "From your Orbital", "Espacio": "Storage", "%@ · %@": "%@ · %@",
    "En una ficha, toca Descargar y lo ves aquí sin conexión.": "On a title, tap Download and watch it here offline.",
    "Lo siguiente para ti": "Up next for you", "Sigue viendo donde ibas.": "Keep watching where you left off.", "Nada pendiente": "Nothing pending",
    "Abrir Orbital": "Open Orbital", "Próximo estreno": "Next premiere", "Sigue: %@": "Next up: %@",
    # Para ti › Listas como feed de estantes (CEN-50)
    "Lo que sale de las series que sigues": "What is coming out from the shows you follow", "Abrir Ajustes": "Open Settings", "Agregada a tu lista.": "Added to your list.", "Conecta Trakt o tu Orbital": "Connect Trakt or your Orbital",
    "De todos los tiempos": "All time", "Lo más popular en Stremio": "Most popular on Stremio", "Lo más visto esta semana": "Most watched this week",
    "Lo que dejaste pendiente": "What you left for later", "Lo tuyo": "Yours", "N.º %lld en %@": "No. %lld on %@", "Por lo que has visto": "Based on what you've watched",
    "Recomendada por Trakt": "Recommended by Trakt", "Sin Trakt ni Orbital, esto es lo que ve todo el mundo": "Without Trakt or Orbital, this is what everyone is watching",
    "Tu watchlist, tus recomendaciones y el Top 10 de tus plataformas aparecen aquí.": "Your watchlist, your recommendations and your platforms' Top 10 show up here.",
    "Buenos días": "Good morning", "Buenas tardes": "Good afternoon", "Buenas noches": "Good evening", "También tenías": "You also had",
    "Último scrobble": "Last scrobble", "Cerrado": "Closed",
    "Todavía nada: aparece cuando veas algo en el iPhone.": "Nothing yet: it shows up once you watch something on the iPhone.",
    "Abrir en Infuse": "Open in Infuse", "Abrir siempre en Infuse": "Always open in Infuse", "Adelantar 10 segundos": "Forward 10 seconds",
    "Alexa": "Alexa", "Qué le puedes decir a Alexa": "What you can say to Alexa", "Cómo pedírselo": "How to ask", "Buscar una frase": "Search a phrase",
    "Copiar": "Copy", "Si Alexa dice que no puede, empieza con «pídele a mi consola que…»: sin eso, Alexa intenta hacerlo ella sola.":
        "If Alexa says she can't, start with “pídele a mi consola que…” (ask my console to…): without it, Alexa tries to do it herself.",
    "Próximos estrenos": "Upcoming episodes", "Por día": "By day", "Semana": "Week", "Hoy": "Today", "Mañana": "Tomorrow",
    "Sale hoy": "Out today", "Desde la madrugada": "Overnight", "Nada este día": "Nothing this day",
    "No sale nada en los próximos 14 días de las series que sigues.": "Nothing comes out in the next 14 days from the shows you follow.",
    "Agregar complemento": "Add add-on", "Ajustes": "Settings", "Al instante": "Instant", "Audio": "Audio", "Audio y subtítulos": "Audio and subtitles",
    "Aparece un código para escribir en trakt.tv/activate. Con Trakt conectado se avisa de lo que ves y salen tu watchlist y tus listas.":
        "A code appears to enter at trakt.tv/activate. With Trakt connected, what you watch is reported and your watchlist and lists show up.",
    "Aquí aparece lo que vas viendo, en el iPhone y en Orbital.": "What you're watching shows up here, on iPhone and on Orbital.",
    "Añadir a Mi lista": "Add to My List", "En Mi lista": "In My List", "Ver ficha": "View details", "Conecta Trakt (tu watchlist y tus listas) o agrega una clave de TMDB (lo popular en Netflix, Disney+ y HBO Max) en Ajustes.": "Connect Trakt (your watchlist and lists) or add a TMDB key (what is popular on Netflix, Disney+ and HBO Max) in Settings.", "Orbital · faltan %lld": "Orbital · %lld left", "Orbital · descargando": "Orbital · downloading", "Poniéndolo en la TV.": "Playing it on the TV.", "Desde la TV": "From the TV", "Descartar": "Dismiss", "Desde la TV: %@": "From the TV: %@", "Descargando %@ (desde la TV)": "Downloading %@ (from the TV)", "No encontré una fuente para descargar %@ (desde la TV)": "I did not find a source to download %@ (from the TV)", "No hay espacio para descargar %@ (desde la TV)": "Not enough space to download %@ (from the TV)", "No pude descargar %@ (desde la TV)": "I could not download %@ (from the TV)",
    "Dirección (orbital.tudominio.com)": "Address (orbital.yourdomain.com)", "Token guardado": "Token saved", "Token (el mismo de Alexa)": "Token (the same as Alexa's)",
    "Guardar token": "Save token", "Probar conexión": "Test connection", "Conectada": "Connected", "Tu Orbital (la TV)": "Your Orbital (the TV)",
    "Con tu Orbital conectada, «Ver en la TV» pone en la consola lo que ves aquí, donde ibas, y tu Trakt y las claves de Para ti salen de ella.": "With your Orbital connected, “Watch on TV” plays what you're watching here on the console, right where you were, and your Trakt and For You keys come from it.",
    "Conectada a %@": "Connected to %@", "En la TV: Ajustes › Cuentas › iPhone": "On the TV: Settings › Accounts › iPhone",
    "Aparece un código. Apúntale con la cámara del iPhone y toca «Abrir en Orbital»: queda conectada, sin escribir nada.": "A code appears. Point the iPhone camera at it and tap “Open in Orbital”: it connects, no typing.",
    "Cambiar a mano": "Change manually", "Conectar a mano": "Connect manually",
    "Con la sesión de tu Orbital: no hay nada que conectar aquí.": "Using your Orbital's session: nothing to connect here.",
    "Dejar de usar Trakt en el iPhone": "Stop using Trakt on iPhone",
    "Conecta tu Orbital (arriba) y Trakt se configura solo. Si no, crea una aplicación en developer.trakt.tv y pega aquí su Client ID.": "Connect your Orbital (above) and Trakt sets itself up. Otherwise, create an app at developer.trakt.tv and paste its Client ID here.",
    "Conectado con tu Orbital.": "Connected to your Orbital.", "Conectado con tu Orbital: %@ ya están aquí.": "Connected to your Orbital: %@ are here now.",
    "Traje de tu Orbital: %@. No hay que escribirlo aquí.": "Brought from your Orbital: %@. No need to type it here.", "Velocidad": "Speed", "Tamaño de subtítulos": "Subtitle size", "Chico": "Small", "Mediano": "Medium", "Grande": "Large", "Fuentes": "Sources", "Descargado": "Downloaded", "Ya está descargado. Lo encuentras en Descargas.": "Already downloaded. You'll find it in Downloads.", "Película": "Movie", "Serie": "Series",
    "Crea una aplicación en developer.trakt.tv y pega aquí su Client ID (las nuevas ya no dan secreto).": "Create an app at developer.trakt.tv and paste its Client ID here (new ones no longer have a secret).",
    "Client ID de tu aplicación de Trakt": "Your Trakt app's Client ID", "Aplicación anterior (con secreto)": "Older app (with a secret)", "Imagen dentro de imagen": "Picture in Picture",
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
     "Descargando": "Downloading", "Descargar": "Download", "Descargar con la fuente recomendada": "Download with the recommended source",
    "Descargar solo con Wi‑Fi": "Download only on Wi‑Fi", "Descargas": "Downloads", "Desconectar Trakt": "Disconnect Trakt", "Descubrir": "Discover",
    "Descargando. Lo verás en Descargas.": "Downloading. You'll see it in Downloads.", "Dirección": "Directed by",
    "El código caducó. Vuelve a intentarlo.": "The code expired. Try again.",
    "Elegir la fuente de este episodio": "Choose this episode's source", "Empieza en %lld s": "Starts in %lld s", "En cola": "Queued", "En pausa": "Paused",
    "En tendencia": "Trending", "En tu lista": "In your list", "En tu watchlist de Trakt": "In your Trakt watchlist", "En %@": "On %@", "En «%@»": "In “%@”",
    "Entra con tu cuenta de Stremio. Lo que veas aquí aparece en Orbital y al revés.": "Sign in with your Stremio account. What you watch here shows up on Orbital and vice versa.",
    "Entrar": "Sign in", "Episodio %lld": "Episode %lld", "Escribe este código en %@:": "Enter this code at %@:",
    "Escribe tu correo y tu contraseña de Stremio.": "Enter your Stremio email and password.", "Ese complemento no responde o no da fuentes ni fichas.": "That add-on doesn't respond or provides no sources or details.",
    "Especial": "Special", "A · desliza para moverte": "A · swipe to move", "Desliza para moverte; toca para %@": "Swipe to move; tap to %@", "Habla con Orbital": "Talk to Orbital", "Preguntándole a tu Orbital…": "Asking your Orbital…", "No te escuché. Toca y vuelve a intentar": "I didn't hear you. Tap and try again", "Desde la TV · %@": "From the TV · %@", "Opciones": "Options", "Anterior": "Previous", "Siguiente": "Next", "Acción X": "X action", "Te escucho…": "Listening…", "Permite el micrófono y el dictado en Ajustes": "Allow the microphone and dictation in Settings", "Dile a Orbital": "Tell Orbital",
    "Toca para terminar": "Tap to finish", "«Pon The Office», «pausa», «abre Zelda»": "“Play The Office”, “pause”, “open Zelda”", "Terminar la orden": "Finish the command",
    "Manda una orden a tu Orbital, como a Alexa: «pon The Office», «pausa», «abre Zelda».": "Send a command to your Orbital, like to Alexa: “play The Office”, “pause”, “open Zelda”.",
    "Orden": "Command", "¿Qué le digo a Orbital?": "What should I tell Orbital?", "Listo.": "Done.", "Pausar la TV": "Pause the TV", "En pausa.": "Paused.",
    "Seguir en la TV": "Resume the TV", "Sigue.": "Resuming.",
    "Actualiza tu Orbital para usar el control completo.": "Update your Orbital to use the full remote.", "Atrás": "Back", "Control de tu Orbital": "Orbital remote", "Nada en la TV ahora": "Nothing on the TV right now",
    "Desliza para moverte; toca para elegir": "Swipe to move; tap to select", "Desliza · toca para elegir": "Swipe · tap to select", "Escribir en la TV": "Type on the TV",
    "Estira hacia arriba para el control completo": "Pull up for the full remote", "Menú": "Menu", "Pad de la TV": "TV touchpad", "Tu Orbital": "Your Orbital",
    "Abre la ficha": "Opens the details", "Elegir": "Choose", "Especiales": "Specials", "Esperando…": "Waiting…", "Fuentes de Real-Debrid": "Real-Debrid sources", "Guardar clave de TMDB": "Save TMDB key", "Guion": "Written by", "Guardar secreto": "Save secret",
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
    # Los errores de las cuentas y de tu Orbital (OrbitalCore): llegan a avisos y a Ajustes.
    "Conecta tu Orbital en Ajustes (la dirección y el token).": "Connect your Orbital in Settings (the address and the token).",
    "Conecta tu cuenta de Stremio en Ajustes": "Connect your Stremio account in Settings",
    "Conecta tu cuenta de Trakt en Ajustes.": "Connect your Trakt account in Settings.",
    "Error de Stremio": "Stremio error",
    "Fecha inválida": "Invalid date",
    "Lista inválida": "Invalid list",
    "No encontré tu Orbital. ¿Está prendida la consola y el túnel?": "I couldn't find your Orbital. Are the console and the tunnel on?",
    "No pude conectar con Stremio: %@": "I couldn't connect to Stremio: %@",
    "No pude conectar con Trakt: %@": "I couldn't connect to Trakt: %@",
    "No pude leer el catálogo de Stremio: %@": "I couldn't read the Stremio catalog: %@",
    "Respuesta de Stremio sin resultado": "Stremio's response had no result",
    "Respuesta inesperada de Cinemeta": "Unexpected response from Cinemeta",
    "Stremio no devolvió la clave de sesión": "Stremio didn't return the session key",
    "Stremio respondió HTTP %@": "Stremio answered HTTP %@",
    "Trakt cerró tu sesión: vuelve a conectarla en Ajustes.": "Trakt signed you out: connect it again in Settings.",
    "Trakt no acepta la sesión de tu Orbital: reconecta Trakt en la TV (Ajustes › Cuentas).": "Trakt doesn't accept your Orbital's session: reconnect Trakt on the TV (Settings › Accounts).",
    "Trakt no devolvió una sesión": "Trakt didn't return a session",
    "Trakt no dio un código. Revisa la aplicación de Trakt.": "Trakt didn't give a code. Check the Trakt app.",
    "Trakt respondió HTTP %lld": "Trakt answered HTTP %lld",
    "Tu Orbital contestó con un error (%@).": "Your Orbital answered with an error (%@).",
    "Tu Orbital es de una versión anterior: actualízala para «Ver en la TV».": "Your Orbital is an older version: update it to use “Watch on TV”.",
    "Tu Orbital no aceptó el token. Revísalo en Ajustes.": "Your Orbital didn't accept the token. Check it in Settings.",
    "Tu Orbital pidió esperar un poco: demasiados intentos.": "Your Orbital asked to wait a bit: too many attempts.",
    "Tu sesión de Trakt caducó: vuelve a conectarla en Ajustes.": "Your Trakt session expired: connect it again in Settings.",
    "Título inválido": "Invalid title",
    "No encontré ese título.": "I couldn't find that title.",
    "Título no encontrado": "Title not found",
    # Los errores de la descarga (OrbitalCore/Downloads.swift y el transporte en segundo plano).
    "El archivo bajado está incompleto o no es el video": "The downloaded file is incomplete or isn't the video",
    "El enlace de la fuente caducó o ya no existe. Toca ▶ para buscar otro.": "The source link expired or no longer exists. Tap ▶ to find another.",
    "El nombre de este título no sirve para guardarlo.": "This title's name can't be used to save it.",
    "El servidor de la fuente falló. Se vuelve a intentar.": "The source's server failed. Trying again.",
    "Esta fuente no tiene un enlace para descargar.": "This source has no download link.",
    "La descarga falló (código %@).": "The download failed (code %@).",
    "La fuente pidió esperar un poco. Se vuelve a intentar.": "The source asked to wait a bit. Trying again.",
    "Lo bajado no cuadra con el archivo: se empieza de nuevo.": "What was downloaded doesn't match the file: starting over.",
    "No hay espacio: hacen falta %@ MB y hay %@ MB libres.": "Not enough space: %@ MB needed and %@ MB free.",
    "No pude guardar el archivo: %@": "I couldn't save the file: %@",
    "Ocupan %@": "%@ used", "Otra fuente": "Another source", "Otra fuente…": "Another source…",
    "Actualizar": "Refresh", "Para ti de tu Orbital": "For You, from your Orbital", "Calculado en el iPhone": "Calculated on the iPhone",
    "Tu Orbital no tiene sugerencias todavía.": "Your Orbital doesn't have suggestions yet.",
    "Para conectar Trakt hace falta una aplicación de la API de Trakt (trakt.tv/oauth/applications). Pega aquí su identificador.":
        "To connect Trakt you need a Trakt API application (trakt.tv/oauth/applications). Paste its identifier here.",
    "Para ti": "For You", "Pausar": "Pause", "País (para lo popular en plataformas)": "Country (for what's popular on platforms)",
    "Pega la dirección completa del complemento (https://…).": "Paste the add-on's full address (https://…).", "Pegar la dirección de un complemento": "Paste an add-on address",
    "Películas": "Movies", "Películas populares": "Popular movies", "Pendientes en Trakt": "Pending on Trakt", "Popular": "Popular",
    "Probando otra fuente (%lld)…": "Trying another source (%lld)…", "Quitar": "Remove", "Quitar de Mi lista": "Remove from My List", "Quitar de Seguir viendo": "Remove from Continue Watching", "Rechazaste la conexión en Trakt.": "You declined the connection on Trakt.", "Recomendada": "Recommended", "Recomendadas": "Recommended",
    "Reparto": "Cast", "Reproducir": "Play", "Reproducir T%lld E%lld": "Play S%lld E%lld", "Reproductor": "Player", "Retroceder 10 segundos": "Back 10 seconds",
    "Salir": "Leave", "Saltar intro": "Skip intro", "Secreto (si tu aplicación lo tiene)": "Secret (if your application has one)", "Seguir": "Continue",
    "Seguir viendo": "Continue Watching", "Series": "Series", "Series populares": "Popular series", "Sigue": "Next up", "Sigues viéndola": "You're watching",
    "Siguiente episodio": "Next episode", "Sin conexión: se ve lo último que guardé.": "Offline: showing what I saved last.", "Sin pistas de audio": "No audio tracks",
    "Sin subtítulos": "No subtitles", "Solo con Wi‑Fi": "Wi‑Fi only", "Solo subtítulos forzados": "Forced subtitles only", "Stremio al día": "Stremio up to date",
    "Stremio conectado": "Stremio connected", "Subtítulos": "Subtitles", "Sugerencias": "Suggestions", "Sí, marcar como visto": "Yes, mark as watched",
    "TMDB pone las fichas en español y busca lo popular en Netflix, Disney+ y HBO Max.": "TMDB provides translated titles and finds what's popular on Netflix, Disney+ and HBO Max.",
    "T%lld E%lld": "S%lld E%lld", "E%lld": "E%lld", "Temporada %lld": "Season %lld", "Temporada %@": "Season %@", "Todo": "All", "Trakt al día": "Trakt up to date", "Trakt conectado": "Trakt connected",
    "Trakt no aceptó el código.": "Trakt didn't accept the code.", "Trakt: %@": "Trakt: %@",
    "Tu contraseña no se guarda: solo la clave de sesión, en el Keychain de tu iPhone.": "Your password isn't stored: only the session key, in your iPhone's Keychain.",
    "Tu watchlist": "Your watchlist", "Tuyo": "Yours", "Ver": "Watch", "Ver ahora": "Watch now", "Viendo": "Watching", "Visto": "Watched", "Volver a intentar": "Try again",
    "Watchlist": "Watchlist", "Ya está descargado.": "Already downloaded.", "%lld cambios por subir": "%lld changes to upload",
    "¿Cerrar sesión de Stremio?": "Sign out of Stremio?", "¿Sigues viendo?": "Still watching?", "¿Terminaste de verlo?": "Did you finish it?",
    "quedan %lld h %lld min": "%lld h %lld min left", "quedan %lld h": "%lld h left", "quedan %lld min": "%lld min left",
    "Descargando %lld episodios. Los verás en Descargas.": "Downloading %lld episodes. You'll see them in Downloads.",
    "Descargando %@ en el iPhone.": "Downloading %@ on the iPhone.", "No encontré %@.": "I did not find %@.",
    "No encontré una fuente para descargar %@.": "I did not find a source to download %@.",
    "No hay nada en la TV para descargar.": "Nothing is playing on the TV to download.",
    "No hay nada en la TV para seguir aquí.": "Nothing is playing on the TV to continue here.", "No te escuché.": "I did not hear you.",
    "Abrir los permisos de Orbital": "Open Orbital's permissions",
    "Bajo la respuesta sale «Entendí: …». Si el nombre salió mal, dilo más despacio o búscalo con «Escribir».": "Under the answer you'll see “I heard: …”. If the name came out wrong, say it more slowly or search for it with “Type”.",
    "Busca la película y la descarga. Una serie, desde su ficha.": "Finds the movie and downloads it. For a series, use its page.",
    "Con Alexa": "With Alexa",
    "Con Siri": "With Siri",
    "Cuando hay varias": "When there are several",
    "Descarga en el iPhone lo que se ve en la TV.": "Downloads what's on the TV to the iPhone.",
    "Descargar funciona aunque estés fuera de casa; lo demás necesita tu Orbital encendida.": "Downloading works even away from home; everything else needs your Orbital on.",
    "Di «Oye Siri, habla con Orbital» y, cuando pregunte, la orden. Para lo de siempre, directo: «Oye Siri, pausa Orbital» o «Oye Siri, reanuda Orbital».": "Say “Hey Siri, talk to Orbital” and, when it asks, the command. For the everyday ones, directly: “Hey Siri, pause Orbital” or “Hey Siri, resume Orbital”.",
    "Dónde hablarle": "Where to talk to it",
    "El iPhone tiene que estar en la misma red que la consola (o con Tailscale), y Orbital abierta en la TV.": "The iPhone has to be on the same network as the console (or on Tailscale), with Orbital open on the TV.",
    "Empieza con «Alexa, pídele a mi consola que…»: sin eso, Alexa intenta hacerlo ella sola.": "Start with “Alexa, pídele a mi consola que…”: without it, Alexa tries to do it herself.",
    "En el control": "In the remote",
    "Las frases de abajo funcionan igual en los tres: las entiende tu Orbital.": "The phrases below work the same in all three: your Orbital understands them. They are in Spanish.",
    "Las teclas del mando, dichas solas.": "The controller buttons, said on their own.",
    "Listo": "Done",
    "Lo básico también en inglés.": "The basics in English too.",
    "Lo que puedes decir": "What you can say",
    "Permite el micrófono y el reconocimiento de voz para Orbital.": "Allow the microphone and speech recognition for Orbital.",
    "Revisa lo que entendió": "Check what it heard",
    "Si contesta que no encuentra tu Orbital": "If it says it can't find your Orbital",
    "Si dices «pon Dune» y hay más de una, salen bajo el micrófono con su póster: toca la que es.": "If you say “pon Dune” and there's more than one, they show up under the microphone with their poster: tap the right one.",
    "Si no funciona": "If it doesn't work",
    "Si no te escucha": "If it doesn't hear you",
    "Sigue aquí lo que se ve en la TV, donde iba.": "Continues here what's on the TV, where it was.",
    "Solo en el iPhone": "Only on the iPhone",
    "Toca «En la TV», estira la hoja hacia arriba y toca el micrófono. Habla con calma: cuando terminas, se detiene solo y te contesta en voz alta.": "Tap “On TV”, pull the sheet up and tap the microphone. Speak calmly: when you finish it stops on its own and answers out loud.",
    "Voz": "Voice",
    "«%@» no tiene ficha de IMDb: Trakt no lo puede registrar.": "“%@” has no IMDb page: Trakt can’t record it.",
    "Carrusel": "Carousel",
    "Coverflow": "Coverflow",
    "Abanico": "Fan",
    "Cuánto falta": "Time left",
    "Píldora de vidrio": "Glass pill",
    "El borde avanza": "Progress border",
    "Botón que se llena": "Filling button",
    "Arco orbital": "Orbit arc",
    "Cómo se acomodan las tarjetas de «Seguir viendo», cómo se dice cuánto te falta y tu avatar.": "How the “Continue watching” cards are laid out, how the time left is shown, and your avatar.",
    "%lld min": "%lld min",
    "Quedan %@ min": "%@ min left",
    "min": "min",
    "Hoy en tu país": "Today in your country",
    "JustWatch · hoy": "JustWatch · today",
    "Lo más popular · Películas": "Most popular · Movies",
    "Lo más popular · Series": "Most popular · Series",
    "Netflix · esta semana": "Netflix · this week",
    "Rankings de %@": "%@ rankings",
    "Sus rankings": "Its rankings",
    "Tendencia hoy · Películas": "Trending today · Movies",
    "Tendencia hoy · Series": "Trending today · Series",
    "Top 10 · Películas": "Top 10 · Movies",
    "Top 10 · Series": "Top 10 · Series",
    "Tus plataformas": "Your platforms",
    "Clásico": "Classic", "Cielo nocturno": "Night sky",
    "Ponerla en la TV": "Play it on the TV", "Poniendo %@.": "Playing %@.", "Abriendo %@ en la TV.": "Opening %@ on the TV.",
    "Sigue aquí.": "Continuing here.", "Abre Orbital y toca «Seguir aquí».": "Open Orbital and tap “Continue here”.",
    "Entendí: «%@»": "I heard: “%@”", "«Pon The Office», «pausa», «descárgalo»": "“Play The Office”, “pause”, “download it”",
    "No pude cambiar tu lista de Stremio: %@": "I couldn't change your Stremio list: %@", "No pude cambiar tu watchlist de Trakt: %@": "I couldn't change your Trakt watchlist: %@",
    "No pude marcarlo: %@": "I couldn't mark it: %@", "No pude pedir las fuentes: %@": "I couldn't get the sources: %@",
      "%@ de %@": "%@ of %@",  "Sí": "Yes",
    "En vivo": "Live", "Sin sonido": "Mute", "Canal anterior": "Previous channel", "Canal siguiente": "Next channel",
    "Salir del video": "Leave the video", "Seguir aquí": "Continue here",
    "Viendo en la TV": "Watching on TV",
}
# Textos que no se traducen: nombres propios, ids y formatos.
IGNORE = {"Content-Type", "T\\($0) · E\\($1)", "AVPlayer", "AirPlay", "Client Secret", "AetherEngine", "BluRay", "WEB-DL", "Orbital", "Trakt", "English", "Español", "1080p", "720p", "4K", "TMDB", "Infuse", "Stremio", "Real-Debrid",
          "REMUX", "Atmos", "Dolby Vision", "Netflix", "Disney+", "HBO Max",
          "Icons/", "Avatars/", "Awards/", "AppIconPreview/day", "AppIconPreview/night", "AppIconNight"}  # el nombre de un ícono en el catálogo
# Textos que se arman en código (modelos) y llegan a la pantalla: se traducen si coinciden con una clave.
CODE_KEYS = {k for k in TRANSLATIONS}

INT_HINT = re.compile(r"^(Int\(|count\b|card\.secondsLeft|row\.number|season\.season|\bs\b|\be\b|\bh\b|\bm\b|\bn\b|episode\b|fraction|state\.remaining)")


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
    files = glob.glob(str(ROOT / "ios/App/Sources/**/*.swift"), recursive=True) + glob.glob(str(ROOT / "ios/App/Widgets/*.swift")) + glob.glob(str(ROOT / "ios/OrbitalCore/Sources/OrbitalModels/*.swift")) + [str(ROOT / f"ios/OrbitalCore/Sources/OrbitalCore/{n}.swift") for n in ("Downloads", "OrbitalRemote", "Trakt", "Watch", "StremioAPI", "Cinemeta")]  # sus errores llegan a la pantalla
    for f in files:
        f = Path(f).as_posix()  # en Windows glob da «\»: sin esto el modo demo y Platform/ se colaban
        # El modo demo (solo Debug) no se traduce; de Design/ solo se saltan los tokens y el banco de pruebas (las piezas sí llevan texto).
        if "/Platform/" in f or f.endswith(("/Support/Demo.swift", "Previews.swift", "/Design/Tokens.swift", "/Design/MosaicBench.swift", "/Design/ModelObserver.swift")):
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
                if re.fullmatch(r"(%lld|%@|[ ·:|\-−/])+", key) or "|" in key or key.startswith(("%@:", "%@-", "Bearer ")):
                    continue
                found.setdefault(key, f"{Path(f).name}:{number}")
    return found


UI_CALL = r'(Text|Button|Label|Section|Toggle|Picker|TextField|SecureField|Tab|navigationTitle|secondary|DSChip|DSBadge|DSNotice|DSSectionHead|DSIconButton|LabeledContent|DisclosureGroup)\(\s*(text:\s*|title:\s*)?"{}"'


def ui_word(word: str) -> bool:
    """¿La palabra aparece como el texto de un control en alguna pantalla?"""
    pattern = re.compile(UI_CALL.format(re.escape(word)))
    files = glob.glob(str(ROOT / "ios/App/Sources/Screens/*.swift")) + glob.glob(str(ROOT / "ios/App/Sources/Design/Components.swift")) + [str(ROOT / f"ios/App/Sources/Design/{n}.swift") for n in ("Projection", "Shelf", "Mosaic")]
    return any(pattern.search(Path(f).read_text(encoding="utf-8")) for f in files)


def build() -> dict:
    strings = {}
    for key, english in sorted(TRANSLATIONS.items()):
        strings[key] = {"extractionState": "manual", "localizations": {"en": {"stringUnit": {"state": "translated", "value": english}}}}
    return {"sourceLanguage": "es", "strings": strings, "version": "1.0"}


def main() -> int:
    missing = {k: where for k, where in used_literals().items() if k not in TRANSLATIONS}
    # Algunos literales son nombres de símbolos, ids o formatos de código (no son textos de pantalla).
    # …salvo que sean el texto de un control («Fuentes» en un botón sí es un texto de pantalla).
    ignorable = {k for k in missing if re.fullmatch(r"[A-Za-z0-9_.]+", k) and " " not in k and not ui_word(k)}
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
