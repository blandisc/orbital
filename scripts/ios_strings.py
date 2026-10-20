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
    "Se va a ver en: %@": "It will play in: %@",
    "Bajando %@ · la misma versión": "Downloading %@ · the same version",
    "Ya está en Descargas": "Already in Downloads",
    "Ya está en Descargas.": "Already in Downloads.",
    "Descargar este video": "Download this video",
    "Descargar": "Download",
    "Viene dentro del archivo": "Comes inside the file",
    "Caja oscura": "Dark box",
    "Carteles en tu idioma si el audio es otro": "Signs in your language when the audio is another",
    "Contorno": "Outline",
    "Después +": "Later +",
    "− Antes": "− Earlier",
    "El idioma, la versión y el ajuste de tiempo se recuerdan solos para cada serie o película. El estilo del iPhone se cambia en Ajustes › Accesibilidad › Subtítulos.": "Language, version and timing are remembered for each show or movie. The iPhone style is set in Settings › Accessibility › Subtitles.",
    "Esta versión no trae frases de texto para sincronizar. Usa Antes y Después.": "This version has no text lines to sync. Use Earlier and Later.",
    "Fondo": "Background",
    "Hecho para tu copia": "Made for your copy",
    "Idioma de siempre": "Usual language",
    "Listo: subtítulos %@ s antes": "Done: subtitles %@ s earlier",
    "Listo: subtítulos %@ s después": "Done: subtitles %@ s later",
    "Listo: ya iban a tiempo": "Done: they were already in sync",
    "Mira unas frases. Si las letras no van con la voz, prueba otra.": "Watch a few lines. If the text doesn't match the voices, try another.",
    "Misma fuente": "Same source",
    "Mostrarlos al regresar 10 s": "Show them when going back 10 s",
    "Más arriba": "Higher",
    "Más chico": "Smaller",
    "Más grande": "Larger",
    "Normal": "Normal",
    "Otra vez": "Again",
    "Posición": "Position",
    "Probar otra": "Try another",
    "Sincronizar con una línea": "Sync with a line",
    "Sí, va bien": "Yes, it's fine",
    "Tiempo y tamaño…": "Timing and size…",
    "Toca la frase en el momento en que la escuches.": "Tap the line the moment you hear it.",
    "Translúcido": "Translucent",
    "Usamos tu ajuste de %@ para esta versión.": "We used your %@ adjustment for this version.",
    "Usar el estilo del iPhone": "Use the iPhone style",
    "Volver a como venían": "Reset to original timing",
    "Ya probaste:": "Already tried:",
    "¿Va a tiempo?": "In sync?",
    "¿Ya van bien? Se recuerda para esta versión.": "In sync now? It's remembered for this version.",
    "%@ descargas": "%@ downloads",
    "%@ · %lld versiones": "%@ · %lld versions",
    "Bien": "OK",
    "Volver": "Back",
    "— Así se van a ver.": "— This is how they'll look.",
    "Calculando…": "Calculating…", "Otro…": "Other…", "Tiempo": "Timing", "Menos": "Less", "Ver todas las versiones": "See all versions",
    "Tu Orbital no contesta. ¿Está prendida la consola?": "Your Orbital isn't responding. Is the console on?", "Ese correo no tiene cuenta de Stremio.": "That email doesn't have a Stremio account.", "La contraseña no coincide.": "The password doesn't match.", "Tu sesión de Stremio se cerró: vuelve a entrar.": "Your Stremio session ended: sign in again.", "Sin conexión. Revisa tu internet e intenta de nuevo.": "No connection. Check your internet and try again.", "%@. Revisa tu conexión e intenta de nuevo.": "%@. Check your connection and try again.",
    "Tu sesión de Stremio se cerró. Vuelve a entrar para ver lo que tienes a medias y tu lista.": "Your Stremio session ended. Sign in again to see what you're watching and your list.", "Volver a entrar": "Sign in again", "Tu sesión de Trakt se cerró": "Your Trakt session ended", "Conéctala otra vez para tus recomendaciones y lo que viste.": "Connect it again for your recommendations and history.", "Conectar": "Connect", "No pudimos revisar tu OneDrive. Revisa tu conexión.": "We couldn't check your OneDrive. Check your connection.", "Volver a conectar": "Reconnect",
    "‹ Anterior": "‹ Previous", "Siguiente ›": "Next ›", "¿No va a tiempo o se ve mal? Toca Siguiente para probar otra.": "Out of sync or looks wrong? Tap Next to try another.", "Ya la probaste": "Already tried", "Con subtítulos para este video": "With subtitles for this video", "Buscar en internet": "Search online",
    "No pudimos cargar la ficha. Revisa tu conexión.": "We couldn't load this title. Check your connection.", "Aún sin episodios": "No episodes yet", "No pudimos armar tu mosaico": "We couldn't build your mosaic", "Revisa tu conexión e intenta de nuevo.": "Check your connection and try again.", "Tu Orbital ya no reconoce este iPhone": "Your Orbital no longer recognizes this iPhone", "Vuelve a conectarlos: en tu TV abre Ajustes › iPhone y escanea el código.": "Connect them again: on your TV open Settings › iPhone and scan the code.", "Tu Orbital no contesta": "Your Orbital isn't responding", "Revisa que la consola esté prendida y en la misma red que tu iPhone.": "Make sure the console is on and on the same network as your iPhone.",
    "Sin fuentes por ahora": "No sources yet", "Todavía no sale": "Not out yet", "Real-Debrid aún no lo tiene. Los estrenos suelen aparecer unas horas después.": "Real-Debrid doesn't have it yet. New releases usually show up a few hours later.",
    "Termina como a las %@": "Done around %@",
    "faltan %@": "%@ left", "Real-Debrid aún no tiene este título. Los estrenos suelen aparecer unas horas después.": "Real-Debrid doesn't have this title yet. New releases usually show up a few hours later.", "Sin conexión: no pudimos preguntar por fuentes. Revisa tu internet.": "No connection: we couldn't ask for sources. Check your internet.", "No pudimos buscar fuentes. Intenta de nuevo.": "We couldn't search for sources. Try again.", "Real-Debrid aún no tiene este título.": "Real-Debrid doesn't have this title yet.", "No pudimos preparar la descarga. Intenta de nuevo.": "We couldn't prepare the download. Try again.", "Sin conexión: no pudimos preguntar por fuentes.": "No connection: we couldn't ask for sources.",
    "Ajustar tiempo": "Adjust timing", "Apagar subtítulos": "Turn subtitles off", "Buscando versiones en internet…": "Searching online for versions…", "Desactivar": "Turn off", "Mantén presionado para apagarlos o prenderlos": "Touch and hold to turn them off or on", "No pudimos buscar subtítulos. Revisa tu conexión.": "We couldn't search for subtitles. Check your connection.", "Prender subtítulos": "Turn subtitles on", "Se recuerda para esta película.": "Remembered for this movie.", "Se recuerda para toda la serie.": "Remembered for the whole show.", "Subtítulos desactivados": "Subtitles off", "Versión": "Version", "¿Las letras salen antes que la voz? Toca +.": "Do the words show up before the voice? Tap +.", "Desactivados": "Off",
    "Llena la pantalla y recorta los lados": "Fills the screen and crops the sides",
    "Prueba de velocidad": "Speed test",
    "El archivo descargado no se puede leer. Bórralo en Descargas y bájalo otra vez.": "The downloaded file can't be read. Delete it in Downloads and download it again.", "Intentar de nuevo": "Try again", "La fuente dejó de responder. Al intentar de nuevo seguimos donde ibas, con otra si hace falta.": "The source stopped responding. Try again and we'll pick up where you were, with another source if needed.", "No pudimos reproducirlo": "We couldn't play it", "No se puede abrir la descarga": "The download can't be opened", "Probamos las fuentes que hay y ninguna respondió. A veces es momentáneo.": "We tried the available sources and none responded. Sometimes it's temporary.", "Real-Debrid aún no tiene esta película. Los estrenos suelen aparecer unas horas después; vuelve a intentarlo más tarde.": "Real-Debrid doesn't have this movie yet. New releases usually show up a few hours later; try again later.", "Real-Debrid aún no tiene este episodio. Los estrenos suelen aparecer unas horas después; vuelve a intentarlo más tarde.": "Real-Debrid doesn't have this episode yet. New releases usually show up a few hours later; try again later.", "Revisa tu conexión a internet e intenta de nuevo.": "Check your internet connection and try again.", "Se cortó el video": "The video stopped", "Sin conexión": "No connection", "Todavía no hay dónde verlo": "Nowhere to watch it yet",
    "Bajando %lld": "Downloading %lld",
    "Bajar también esta": "Download this one too", "Cambiarla por esta": "Replace it with this one", "La que elegiste": "The one you chose", "Puedes guardar varias versiones del mismo título.": "You can keep several versions of the same title.", "Ya la tienes": "You already have it",
    "Ahora no": "Not now", "Atajo": "Shortcut", "Aún no tienes listas en Trakt.": "You don't have any Trakt lists yet.", "Buscando en internet…": "Searching online…", "Buscar idioma": "Search language", "Calificación": "Rating", "Cambia el zoom del video": "Changes the video zoom", "Cargando…": "Loading…", "Cinemeta no contestó": "Cinemeta didn't respond", "Clasificación %@": "Rated %@", "Coincide con tu copia": "Matches your copy", "De %lld para arriba": "%lld and up", "De internet": "From the internet", "Del video": "From the video", "Década": "Decade", "En vertical solo se nota en videos de otro formato": "In portrait it only shows on videos with another aspect ratio", "Esta lista todavía no tiene títulos.": "This list has no titles yet.", "Este va bien": "This one works", "Lista de subtítulos": "Subtitle list", "Lo mejor disponible: %@": "Best available: %@", "Mantén presionado para ver la lista de subtítulos": "Touch and hold to see the subtitle list", "Mejor calificadas (IMDb y Trakt)": "Top rated (IMDb and Trakt)", "Más cortas primero": "Shortest first", "Más idiomas": "More languages", "Más idiomas…": "More languages…", "No hay subtítulos en este idioma.": "There are no subtitles in this language.", "No pude abrir este video. La fuente dejó de responder.": "I couldn't open this video. The source stopped responding.", "Otros idiomas": "Other languages", "Pantalla y giro bloqueados": "Screen and rotation locked", "Reconectando…": "Reconnecting…", "Siguiente subtítulo": "Next subtitle", "Sin filmografía": "No filmography", "Subtítulos antes": "Subtitles earlier", "Subtítulos después": "Subtitles later", "TMDB no tiene títulos de esta persona.": "TMDB has no titles for this person.", "Tus idiomas": "Your languages", "Versión %lld": "Version %lld", "Versión anterior": "Previous version", "Versión siguiente": "Next version", "Volver a los canales": "Back to channels", "Volver al reproductor": "Back to the player", "%@ para el siguiente susto": "%@ until the next scare",
    "CH %@": "CH %@",
    "Lo último que viste": "Last watched",
    "Calendario del mes": "Month calendar", "Ese día no sale nada de lo que sigues.": "Nothing you follow comes out that day.", "Mes anterior": "Previous month", "Mes siguiente": "Next month", "Nada sale": "Nothing out", "te recomendamos:": "we recommend:",
    "El N.º 1 de cada plataforma": "No. 1 on each platform", "Lo que todos están viendo": "What everyone's watching",
    "Lo número 1 en tus plataformas": "The number 1 on your platforms",
    "Mejor elige la carpeta de tus películas: con todo tu OneDrive la revisión tarda más.": "Better choose the folder with your movies: with your whole OneDrive the check takes longer.", "Todo tu OneDrive": "Your whole OneDrive", "Usar todo mi OneDrive": "Use my whole OneDrive",
    "Elegir carpeta": "Choose folder", "Elige la carpeta de tus películas": "Choose the folder with your movies", "Películas: %@ · Series: %@": "Movies: %@ · Shows: %@", "Películas: %lld · Series: %lld": "Movies: %lld · Shows: %lld", "Solo se mira esa carpeta y sus subcarpetas.": "Only that folder and its subfolders are read.", "Toca el del centro para volver a como venían.": "Tap the middle one to go back to how they came.", "«Ver» usa la mejor; «Descargar», la de 1080p.": "“Watch” uses the best one; “Download”, the 1080p one.",
    "A tiempo": "In sync", "Adelantar medio segundo": "Half a second earlier", "Ajustes de OneDrive": "OneDrive settings", "Antes": "Earlier", "Atrasar medio segundo": "Half a second later", "Bajar esta": "Download this one", "Bajar temporada": "Download season", "Busca el título": "Search for the title", "Buscar fuente": "Find a source", "Cada video se reconoce por su nombre: «Dune Part Two (2024).mkv», «Severance S01E03.mkv».": "Each video is recognized by its name: “Dune Part Two (2024).mkv”, “Severance S01E03.mkv”.", "Conecta tu OneDrive": "Connect your OneDrive", "Corregir": "Fix", "Corregir ficha": "Fix match", "Corregir ficha: búscala por nombre": "Fix match: search for it by name", "De Mi media": "From My media", "Después": "Later", "El archivo": "The file", "En el iPhone": "On iPhone", "Episodio %@": "Episode %@", "Esta carpeta está vacía.": "This folder is empty.", "Lo último que subiste": "The latest you uploaded", "Mi media": "My media", "Mi media se vacía. Lo que ya bajaste al iPhone se queda.": "My media is cleared. What you already downloaded to the iPhone stays.", "Nada reconocido todavía": "Nothing recognized yet", "No encontré ese archivo en tu OneDrive.": "I couldn't find that file on your OneDrive.", "No está en tu carpeta": "Not in your folder", "No los reconocí por su nombre: elige cuál es.": "I didn't recognize them by name: choose which one it is.", "No pude pedir el archivo a OneDrive.": "I couldn't get the file from OneDrive.", "Para ver se usa la mejor; para bajar, la de 1080p. Mantén presionada una para elegirla.": "The best one is used for watching; the 1080p one for downloading. Press and hold one to choose it.", "Por nombre": "By name", "Recién agregado": "Recently added", "Revisando tu carpeta…": "Checking your folder…", "Revisando…": "Checking…", "Saga": "Collection", "Sin ficha": "No match", "Sin resultados: prueba con el título en inglés.": "No results: try the English title.", "Sin ver": "Unwatched", "Sincronía": "Sync", "Tu OneDrive · %@": "Your OneDrive · %@", "Tus películas y series de OneDrive, aquí: se ven al instante y se bajan al iPhone.": "Your OneDrive movies and shows, here: they play instantly and download to the iPhone.", "Tus películas y series salen en Descargas › Mi media: se ven al instante y se bajan al iPhone.": "Your movies and shows appear in Downloads › My media: they play instantly and download to the iPhone.", "Ver carpetas": "Browse folders", "Ver esta": "Watch this one", "Versiones en tu carpeta": "Versions in your folder", "Ya no está en tu carpeta": "No longer in your folder", "¿No es esta película?": "Not this movie?", "¿No es esta serie?": "Not this show?", "%lld versiones": "%lld versions", "%lld películas · %lld series · %@": "%lld movies · %lld shows · %@", "Agregada": "Added",
    "%@ sin ficha: revisa que su nombre diga el título (y el año).": "%@ without a match: check that the file name says the title (and the year).", "Aparece un código para escribir en microsoft.com/link. Solo pide leer tus archivos.": "A code appears to type at microsoft.com/link. It only asks to read your files.", "Conectar OneDrive": "Connect OneDrive", "Copiar el código y abrir Microsoft": "Copy the code and open Microsoft", "Desconectar OneDrive": "Disconnect OneDrive", "Dónde están tus películas": "Where your movies are", "Elige una": "Choose one", "En tu OneDrive": "On your OneDrive", "Episodios": "Episodes", "Escribe este código en %@": "Type this code at %@", "Id. de aplicación (cliente)": "Application (client) ID", "Lo que encontré": "What I found", "Microsoft no aceptó el código.": "Microsoft didn't accept the code.", "No hay más carpetas aquí.": "No more folders here.", "OneDrive": "OneDrive", "OneDrive conectado": "OneDrive connected", "Orbital solo lee: nunca cambia ni borra nada": "Orbital only reads: it never changes or deletes anything", "Rechazaste la conexión en Microsoft.": "You declined the connection at Microsoft.", "Revisada %@": "Checked %@", "Revisar ahora": "Check now", "Se ven al instante y se pueden descargar": "They play instantly and can be downloaded", "Solo mira la carpeta que elijas después": "It only looks at the folder you choose next", "Solo se mira esa carpeta y sus subcarpetas. Cada video se reconoce por su nombre («Dune Part Two (2024).mkv», «Severance S01E03.mkv»).": "Only that folder and its subfolders are read. Each video is recognized by its name (“Dune Part Two (2024).mkv”, “Severance S01E03.mkv”).", "Tu OneDrive": "Your OneDrive", "Tu OneDrive primero; luego Real-Debrid, por calidad": "Your OneDrive first; then Real-Debrid, by quality", "Tu copia en OneDrive": "Your copy on OneDrive", "Tus videos de OneDrive dejan de salir como fuente. Lo descargado se queda.": "Your OneDrive videos stop showing up as sources. Downloads stay.", "Tus videos salen primero en «Fuente» de su película o episodio: se ven al instante y se pueden descargar.": "Your videos show up first under “Source” for their movie or episode: they play instantly and can be downloaded.", "Tus videos se ven directo, sin bajarlos completos": "Your videos play directly, without downloading them fully", "Usa la misma de la TV. Si aún no la tienes: en entra.microsoft.com › Registros de aplicaciones › Nuevo registro, ponle «Orbital», elige «Cuentas personales de Microsoft» y créala. En «Autenticación» activa «Permitir flujos de clientes públicos». Copia su «Id. de aplicación (cliente)».": "Use the same one as the TV. If you don't have it yet: at entra.microsoft.com › App registrations › New registration, name it “Orbital”, choose “Personal Microsoft accounts” and create it. Under “Authentication”, turn on “Allow public client flows”. Copy its “Application (client) ID”.", "Usar esta carpeta": "Use this folder", "¿Desconectar OneDrive?": "Disconnect OneDrive?",
    "Horas, tus días más intensos, lo que más viste y tu mapa de calor": "Hours, your busiest days, what you watched most and your heat map", "Lo más visto en tu país esta semana": "Most watched in your country this week", "Lo que todo el mundo está viendo": "What everyone is watching", "Lo que viste, día por día": "What you watched, day by day", "No pude traer los episodios de Los Simpson.": "I couldn't get The Simpsons episodes.", "Recomendadas con lo que ves": "Recommended from what you watch", "Top 10 en Netflix": "Top 10 on Netflix", "Tu año en Orbital": "Your year on Orbital", "Un Simpson al azar": "A random Simpsons", "Un Simpson al azar (T5–T15)": "A random Simpsons (S5–S15)", "Ver aquí": "Watch here",
    "Desliza hacia arriba o abajo para ir de un día con algo visto a otro": "Swipe up or down to move between days you watched something", "Día anterior con algo visto": "Previous day you watched something", "Día siguiente con algo visto": "Next day you watched something", "Elige otro título para recomendarte por él": "Pick another title to get recommendations from", "Ese día no viste nada.": "You didn't watch anything that day.", "Recomiéndame por…": "Recommend based on…", "Toca el nombre para elegir otro de lo que viste": "Tap the name to pick something else you watched",
    "Hoy no hay ranking de este servicio.": "No ranking for this service today.", "Lo más visto hoy · JustWatch": "Most watched today · JustWatch",
    "Abrir con Infuse": "Open with Infuse", "Activa los avisos de Orbital en Ajustes del iPhone.": "Turn on Orbital notifications in iPhone Settings.", "Apagados": "Off", "Avienta la carta para cambiar": "Flick the card to change", "Bajando %@": "Downloading %@", "Bajando la recomendada": "Downloading the recommended one", "Borrar la descarga": "Delete the download", "Cancelar la descarga": "Cancel the download", "Clasificación": "Rating", "Con": "With", "Conecta Trakt para saber qué series sigues.": "Connect Trakt so we know which shows you follow.", "Creada por": "Created by", "Cuando un estreno ya está para ver": "When a new episode is ready to watch", "Cómo eliges, en Para ti, de qué título quieres recomendaciones.": "How you pick, in For You, which title to get recommendations from.", "De Real-Debrid · por calidad, la recomendada primero": "From Real-Debrid · by quality, recommended first", "De las series que sigues en Trakt. Te avisa cuando ya hay fuente en Real-Debrid, con botones para verlo aquí, en la TV o bajarlo. De las 23 a las 8 el aviso espera a la mañana; varios el mismo día llegan juntos.": "For the shows you follow on Trakt. It tells you once there's a Real-Debrid source, with buttons to watch here, on the TV or download it. From 11 PM to 8 AM it waits until morning; several on the same day arrive together.", "Descargada": "Downloaded", "Desliza hacia arriba o abajo para cambiar el título": "Swipe up or down to change the title", "Detalles": "Details", "Duración": "Runtime", "Elegir la fuente…": "Choose the source…", "Estrenos": "New episodes", "Fuente": "Source", "Guardada": "Saved", "Guardada en Mi lista": "Saved to My list", "Inicio y Para ti": "Home and For You", "La elegimos por tu idioma, la calidad y el tamaño": "Picked for your language, quality and size", "Lleva %lld %": "%lld % done", "Los siguientes %@": "The next %@", "Mantén presionado para elegir en qué lista": "Touch and hold to choose which list", "Mazo de cartas": "Card deck", "Mini pósters": "Mini posters", "Primer episodio": "First episode", "Quitada de Mi lista": "Removed from My list", "Reintentar": "Retry", "Tus listas de Trakt…": "Your Trakt lists…", "Ver en Descargas": "See in Downloads", "Ver sin internet": "Watch offline", "Un estreno ya está para ver": "A new episode is ready to watch", "%lld estrenos ya para ver": "%lld new episodes ready to watch", "Ya está para ver": "Ready to watch", "Ya está para ver · «%@»": "Ready to watch · “%@”", "Cambiar": "Change", "Avisos": "Notifications", "Estudio": "Studio", "Cadena": "Network", "Disponible": "Available", "Estreno": "Release", "menos": "less", "más": "more",
    "Empieza en un momento…": "Starting in a moment…", "Ver ya": "Watch now", "Otro": "Another",
    "Cambia el orden o lo que ocultas.": "Change the sort or what you hide.", "Conecta Trakt": "Connect Trakt", "Este título no está en Stremio": "This title isn't on Stremio", "Nada con estos filtros": "Nothing with these filters", "Nada con «%@». Prueba con otro nombre.": "Nothing for “%@”. Try another name.", "Nada de ese tipo": "Nothing of that type", "Nada en los próximos 14 días": "Nothing in the next 14 days", "Nada por aquí por ahora": "Nothing here yet", "No encontré una con eso": "I couldn't find one like that", "No sale nada de las series que sigues.": "Nothing coming from the shows you follow.", "Películas %@": "Movies %@", "Prueba con otro filtro o más tiempo.": "Try another filter or more time.", "Prueba con «Todo».": "Try “All”.", "Series %@": "Shows %@", "Sin resultados": "No results", "Todavía nada": "Nothing yet",
    "Bloquear": "Lock", "Pantalla bloqueada": "Screen locked", "Toca para desbloquear": "Tap to unlock",
    "Español latino": "Latin American Spanish", "Arrastra el video para subirlo o bajarlo": "Drag the video to move it up or down",
    "Ahorro": "Saver", "Equilibrado": "Balanced", "Rendimiento": "Performance",
    "Esperando Wi‑Fi": "Waiting for Wi‑Fi", "Esperando conexión": "Waiting for connection", "En espera": "On hold",
    "termina a la %@": "ends at %@", "Buscando subtítulos…": "Searching subtitles…", "Se guardan con la descarga: también los ves sin conexión.": "They are saved with the download: you can watch them offline too.", "No encontré subtítulos para este video (o no hay conexión).": "I couldn't find subtitles for this video (or there's no connection).", "Subtítulos guardados con la descarga.": "Subtitles saved with the download.", "No pude bajar ese subtítulo: prueba otro.": "I couldn't download that subtitle: try another one.",
    "Cargando": "Charging", "Sustos": "Scares", "Avisarme": "Warn me", "Silencio": "Mute", "Arriba": "Up", "Abajo": "Down", "Izquierda": "Left", "Derecha": "Right", "Mantener": "Hold",
    "%@ de batería": "%@ of battery", "%@ GB libres": "%@ GB free",
    "%lld por delante · %lld fuertes": "%lld ahead · %lld big", "%lld sustos por delante": "%lld scares ahead", "Con datos móviles te avisamos antes de usar fuentes de más de %lld GB.": "On cellular we ask before using sources over %lld GB.", "De lo más popular": "Among the most popular", "Dejan de salir tu watchlist, tus listas y lo que sigues; lo que veas ya no se marca en Trakt.": "Your watchlist, lists and shows stop appearing; what you watch is no longer marked on Trakt.", "Desconectar": "Disconnect", "En tendencia y para ti": "Trending and for you", "Guardamos una sola copia: si la cambias, se borra la que tienes y se baja la nueva.": "We keep a single copy: if you replace it, yours is deleted and the new one downloads.", "Nada de ese tipo: prueba con «Todo».": "Nothing of that kind: try “All”.", "Reintentar la descarga": "Retry the download", "Se borra lo que tenías pendiente de subir y tus búsquedas recientes. Tus descargas se quedan en el iPhone.": "Pending uploads and your recent searches are deleted. Your downloads stay on the iPhone.", "Seguir la descarga": "Resume the download", "para el siguiente · fuerte": "to the next one · big", "para el siguiente · leve": "to the next one · mild", "síguela en mi iPhone": "continue it on my iPhone", "¿Desconectar Trakt?": "Disconnect Trakt?",
    "Desde el principio": "From the beginning", "No encontré subtítulos (o no hay conexión). Vuelve a intentar.": "I couldn't find subtitles (or there's no connection). Try again.", "No pude abrir ese archivo.": "I couldn't open that file.", "Tráiler": "Trailer", "Volver a buscar": "Search again",
    "El juego se cerró solo: no fuiste tú. Si se repite, revisa sus ajustes en la consola.": "The game closed on its own: it wasn't you. If it happens again, check its settings on the console.", "Se cerró por falta de memoria: cierra otras apps de la consola antes de volver a jugar.": "It closed because memory ran out: close other console apps before playing again.", "Sesión terminada": "Session over", "esta vez": "this time", "en total": "in total", "capturas": "captures",
    "Conectando con tu Orbital…": "Connecting to your Orbital…",
    "Buscando…": "Searching…", "Buscar subtítulos": "Search subtitles", "En internet": "Online", "Línea de tiempo": "Timeline", "Mapa de sustos · %lld": "Jump scare map · %lld", "Moverte por la TV": "Move around the TV", "No encontré subtítulos para este video.": "I couldn't find subtitles for this video.", "Ocultar el pad": "Hide the pad", "Ocultar los sustos": "Hide the scares", "Tiempos de Where's The Jump": "Times from Where's The Jump", "Vibra unos segundos antes de cada susto": "Vibrates a few seconds before each scare", "Ya no quedan sustos": "No scares left",
    "Año (lo más nuevo primero)": "Year (newest first)", "Calidad y tamaño en equilibrio": "Balanced quality and size",
    "Atmos · 5.1": "Atmos · 5.1", "Calidad, idioma y tamaño, a tu gusto": "Quality, language and size, your way", "Cambiarla por esta fuente": "Replace it with this source", "Compartir el archivo": "Share the file", "Compresión eficiente: se ve igual y ocupa menos.": "Efficient compression: looks the same, takes less space.", "De Real-Debrid · la recomendada va primero": "From Real-Debrid · the recommended one comes first", "Dejar la que tengo": "Keep the one I have", "Del servicio de streaming: buena calidad y tamaño medio.": "From the streaming service: good quality, medium size.", "Descargado · listo para ver sin conexión": "Downloaded · ready to watch offline", "Descargando %lld episodios": "Downloading %lld episodes", "Destacado": "Featured", "Lo que tienes a medias": "What you have halfway", "Elegir la fuente": "Choose the source", "En amarillo, las pesadas: con datos móviles te avisamos antes.": "Heavy ones are yellow: on cellular we ask first.", "Filtrar Destacado": "Filter Featured", "Grabada en el cine: mala imagen. Va hasta abajo.": "Recorded in a theater: poor picture. It goes last.", "Guardamos una sola copia. La que tienes es %@; si la cambias, se borra y se baja la nueva.": "We keep a single copy. Yours is %@; if you replace it, it’s deleted and the new one downloads.", "HDR · DV": "HDR · DV", "La copia íntegra del disco: la mejor imagen y la más pesada.": "The full disc copy: best picture, heaviest file.", "La mejor para el iPhone: calidad y tamaño en equilibrio": "Best for iPhone: balanced quality and size", "La recomendada": "The recommended one", "La que elegimos por calidad, idioma y tamaño. Es la que arranca sola.": "Our pick for quality, language and size. It’s the one that starts on its own.", "La resolución. 4K se luce en la TV; en el iPhone, 1080p ya se ve nítido.": "The resolution. 4K shines on the TV; on iPhone, 1080p already looks sharp.", "Los siguientes %lld episodios": "The next %lld episodes", "Mejor resultado": "Top result", "Más contraste y color. DV es Dolby Vision: el iPhone lo reproduce.": "More contrast and color. DV is Dolby Vision: iPhone plays it.", "Para verlos sin conexión, uno tras otro": "To watch offline, one after another", "Películas %lld": "Movies %lld", "Popular esta semana": "Popular this week", "Qué significa cada etiqueta": "What each tag means", "Series %lld": "Shows %lld", "Sonido envolvente. Con audífonos AirPods, Atmos se oye espacial.": "Surround sound. With AirPods, Atmos sounds spatial.", "Ya está en tu Real-Debrid: empieza sin esperar.": "Already in your Real-Debrid: starts right away.", "Ya la tienes descargada": "You already downloaded it",
    "Afinemos": "Let's fine-tune", "De las series que sigues": "From the shows you follow", "Encuéntrala": "Find it",
    "Dime con precisión qué quieres: de qué lista, de qué época y qué tan bien calificada.": "Tell me exactly what you want: which list, which era and how well rated.",
    "Lo que guardaste": "What you saved", "Seguir viendo: todas, %@": "Continue watching: all, %@", "Todas": "All", "Ver la ficha": "See details",
    "Abre el acompañante del juego": "Opens the game companion", "Seguir viendo: ver las %@": "Continue watching: see all %@", "Ver las %@": "See all %@",
    "A la consola le queda %lld %% de batería.": "The console has %lld %% battery left.", "Actualiza tu Orbital para ver la batería, los controles y la memoria.": "Update your Orbital to see its battery, controllers and memory.",
    "Batería baja en la consola": "Console battery low", "Buscar en la web": "Search the web", "Cerrar %@": "Close %@",
    "Cerrar el juego": "Close the game", "Dónde te quedaste, qué te falta…": "Where you left off, what's missing…", "El juego se va a cerrar": "The game is about to close",
    "En pausa en la consola": "Paused on the console", "Guía": "Guide", "Guías de la comunidad de Steam": "Steam community guides", "Guías en YouTube": "Guides on YouTube",
    "Ir al inicio": "Go home", "Jugando en la consola": "Playing on the console", "La consola": "The console", "La distribución habitual del emulador.": "The emulator's usual layout.",
    "Le queda %lld %%: conéctala antes de que se apague.": "%lld %% left: plug it in before it shuts down.", "Llevas %@": "%@ in", "Llevas %@ en %@.": "You've played %@ of %@.",
    "Pantalla táctil": "Touch screen", "Para el jefe que te atoró o el objeto que no encuentras.": "For the boss you're stuck on or the item you can't find.",
    "Se cumplió tu tiempo": "Time's up", "Stick derecho": "Right stick", "Te aviso al terminar; no cierro nada.": "I'll tell you when it's over; I won't close anything.",
    "Volver al juego": "Back to the game", "¿Cerrar el juego?": "Close the game?", "¿Cuánto quieres jugar?": "How long do you want to play?",
    "Calificación mínima": "Minimum rating", "Cualquiera": "Any", "De dónde": "From where", "De todo lo sugerido": "From everything suggested",
    "Desliza hasta arriba para más precisión: de qué lista, época y calificación": "Swipe all the way up for more precision: which list, era and rating",
    "Elige y toca «Decide por mí»": "Choose and tap «Decide for me»", "Lo que sea": "Anything", "No encontré una con eso: prueba con otro filtro o más tiempo.": "I couldn't find one with that: try another filter or more time.",
    "Una para ahora · desliza hacia arriba para elegir": "One for now · swipe up to choose", "Época": "Era", "Antes de los 90": "Before the 90s", "Barajar": "Shuffle",
    "Buscaste hace poco": "Recent searches", "Lo más popular de cada uno": "The most popular of each", "Lo que más se ve hoy en Stremio, películas y series": "What's most watched today on Stremio, movies and shows",
    "Con géneros elegidos, el ánimo no cuenta.": "With genres picked, the mood doesn't count.", "Géneros": "Genres", "Incluir lo que ya vi": "Include what I've watched",
    "Ir a una sección": "Go to a section", "Mejor calificadas en IMDb": "Top rated on IMDb", "Mejor calificadas en Trakt": "Top rated on Trakt",
    "Menos opciones": "Fewer options", "Más opciones": "More options", "Qué": "What", "Toca otra vez para confirmar": "Tap again to confirm",
    "Todo lo que estás viendo": "Everything you're watching", "Todo lo que estás viendo · %@": "Everything you're watching · %@", "¿Ver en la TV?": "Watch on the TV?",
    "Abre el control de tu Orbital.": "Opens your Orbital's remote.", "Abrir el control de Orbital": "Open the Orbital remote", "Control de Orbital": "Orbital remote",
    "Episodios de estas semanas y películas recién llegadas": "This week's episodes and newly arrived movies", "Estudios": "Studios",
    "Lo más visto": "Most watched", "Lo más visto de cada uno": "The most watched from each", "Nuevo en tus plataformas": "New on your platforms",
    "Año: más nuevas": "Year: newest", "Año: más viejas": "Year: oldest", "A–Z": "A–Z", "Como viene la lista": "As the list comes", "De %@": "From %@",
    "Género": "Genre", "Listas de Stremio": "Stremio lists", "Listas de Trakt": "Trakt lists", "Lo que Trakt relaciona con lo último que viste": "What Trakt relates to what you watched last",
    "Mostrar": "Show", "Nada con estos filtros.": "Nothing with these filters.", "Ocultar lo que ya vi": "Hide what I've watched", "Ordenar y filtrar": "Sort and filter",
    "Porque viste": "Because you watched", "Series o películas": "Shows or movies", "Sin lo que ya vi": "Without what I've watched", "Ordenar": "Sort", "Todos": "All",
    "Cine mexicano": "Mexican cinema", "De Trakt": "From Trakt", "Globos de Oro": "Golden Globes", "Lo más popular de cada año": "The most popular of each year",
    "Los ganadores, del más reciente": "The winners, newest first", "Mejor película": "Best Picture", "Mejor película dramática": "Best Motion Picture – Drama",
    "Mejor serie de drama": "Outstanding Drama Series", "Palma de Oro": "Palme d'Or", "Plataformas": "Platforms", "Por año": "By year", "Premios": "Awards",
    "Tus listas": "Your lists", "Óscar": "Oscar", "Ariel": "Ariel", "Emmy": "Emmy", "Cannes": "Cannes", "%lld títulos": "%lld titles",
    "Complementos, TMDB, país": "Add-ons, TMDB, country", "Crear": "Create", "Desde tu Orbital": "From your Orbital", "Guardar en…": "Save to…",
    "No pude cambiar tu lista de Trakt: %@": "I couldn't change your Trakt list: %@", "No pude crear la lista: %@": "I couldn't create the list: %@",
    "Nombre": "Name", "Nueva lista": "New list", "Nueva lista…": "New list…", "Ponle nombre a la lista": "Give the list a name",
    "Se crea en Trakt (privada) y este título entra en ella.": "It's created on Trakt (private) and this title goes in it.",
    "Todo lo que sigues": "Everything you're watching", "Todo lo que sigues · %@": "Everything you're watching · %@", "Tus listas de Trakt": "Your Trakt lists",
    "Avanzado": "Advanced", "Guardar": "Save", "Guardado": "Saved",
    "Cambiar lo que quiero": "Change what I want", "Conecta Trakt (en tu Orbital o en Ajustes) para ver tu año.": "Connect Trakt (on your Orbital or in Settings) to see your year.",
    "De lo último que viste": "From what you watched lately", "Decide por mí": "Decide for me", "Día por día": "Day by day", "En pareja": "As a couple",
    "Hoy no": "Not today", "Las dos": "Both", "Lo que más viste": "What you watched most", "Lo que viste": "What you watched",
    "No encontré otra con eso: prueba otro ánimo o más tiempo.": "I couldn't find another one: try another mood or more time.",
    "Otra": "Another", "Para pensar": "Thought-provoking", "Porque viste %@": "Because you watched %@", "Quiero algo": "I want something",
    "Sale el %@": "Out %@", "Sale mañana": "Out tomorrow", "Tu %@": "Your %@", "Tu año": "Your year",
    "Una sola, de tus sugerencias, que no hayas visto.": "Just one, from your suggestions, that you haven't seen.", "¿Qué vemos?": "What should we watch?",
    "Tengo": "I have", "30 min": "30 min", "1 h": "1 h", "2 h o más": "2 h or more", "Ligero": "Light", "Intenso": "Intense",
    "vistas": "watched", "racha más larga": "longest streak", "tu género": "your genre", "%lld días": "%lld days",
    "%lld películas · %lld episodios": "%lld movies · %lld episodes", "%lld días con algo visto": "%lld days with something watched",
    "Tendencia": "Trending", "Top 10": "Top 10",
    "Hola": "Hi", "Hola, %@": "Hi, %@", "Cómo te llamamos": "What we call you", "Tu nombre": "Your name",
    "Actualiza tu Orbital para cambiar el volumen desde aquí.": "Update your Orbital to change the volume from here.",
    "Alexa, pídele a Orbital que…": "Alexa, ask Orbital to…", "Bajar volumen": "Volume down", "Subir volumen": "Volume up", "Quitar silencio": "Unmute",
    "Descargar funciona aunque estés fuera de casa.": "Downloading works even away from home.",
    "Estira el control hacia arriba y toca «Dile a Orbital». Se detiene solo cuando terminas.": "Pull the remote up and tap “Tell Orbital”. It stops on its own when you finish.",
    "Las frases de abajo funcionan igual en los tres.": "The phrases below work the same in all three.", "Oye Siri, habla con Orbital": "Hey Siri, talk to Orbital",
    "Sin «pídele a Orbital», Alexa intenta hacerlo ella sola.": "Without “ask Orbital”, Alexa tries to do it herself.",
    "Y cuando pregunte, la orden. Directo: «Oye Siri, pausa Orbital».": "Then, when asked, the command. Direct: “Hey Siri, pause Orbital”.",
    "Saltar resumen": "Skip recap",
    "Lo mejor disponible": "Best available",
    "Sale pronto": "Coming up", "Ver todo": "See all",
    "Más lento": "Slower", "Más rápido": "Faster",
    "Ajustes del video": "Video settings", "Archivo descargado": "Downloaded file", "La que tienes": "Current", "Pasó a tu Orbital": "Moved to your Orbital",
    "Tamaño": "Size", "Tarda en empezar": "Slow to start", "Tu idioma": "Your language", "Ventana": "Window", "Idiomas": "Languages", "Otros": "Others",
    "Otras": "Others", "%@ · sigue en %@": "%@ · continues at %@", "Deshacer": "Undo",
    "Creación": "Created by", "Dónde verlo": "Where to watch", "Este título no está en Stremio.": "This title isn't on Stremio.", "Filmografía": "Filmography",
    "La saga": "The saga", "Marcar temporada como vista": "Mark season as watched", "Más como esto": "More like this",
    "No pude traer a esta persona de TMDB.": "Couldn't load this person from TMDB.", "Reparto y equipo": "Cast and crew", "Tráiler y extras": "Trailer and extras",
    "Novela": "Novel", "%lld de %lld vistos": "%lld of %lld watched",
    "Sus rankings de hoy": "Their charts today", "%lld descargando": "%lld downloading",
    "En la TV: %@": "On TV: %@", "Sale hoy: %@": "Out today: %@", "%lld por terminar": "%lld to finish",
    "Otras apps": "Other apps", "%@ libres de %@": "%@ free of %@",
    "%lld episodio": "%lld episode", "%lld temporadas": "%lld seasons",
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
    "Copiar": "Copy", "Si Alexa dice que no puede, empieza con «pídele a Orbital que…»: sin eso, Alexa intenta hacerlo ella sola.":
        "If Alexa says she can't, start with “pídele a Orbital que…” (ask Orbital to…): without it, Alexa tries to do it herself.",
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
    "Empieza con «Alexa, pídele a Orbital que…»: sin eso, Alexa intenta hacerlo ella sola.": "Start with “Alexa, pídele a Orbital que…”: without it, Alexa tries to do it herself.",
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
    "Quedan %lld min": "%lld min left",
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
IGNORE = {"The Simpsons", "Content-Type", "L · R", "L1 · R1", "L2 · R2", "LB · RB", "LT · RT", "ZL · ZR", "Start · Select", "Stick C", "IMDb %.1f", "Trakt %.1f", "T\\($0) · E\\($1)", "AVPlayer", "AirPlay", "Client Secret", "AetherEngine", "BluRay", "WEB-DL", "Orbital", "Trakt", "English", "Español", "1080p", "720p", "4K", "TMDB", "Infuse", "Stremio", "Real-Debrid",
          "REMUX", "Atmos", "Dolby Vision", "Netflix", "Disney+", "HBO Max",
          "Icons/", "Glyphs/donut", "Avatars/", "Awards/", "AppIconPreview/day", "AppIconPreview/night", "AppIconNight"}  # el nombre de un ícono en el catálogo
# Textos que se arman en código (modelos) y llegan a la pantalla: se traducen si coinciden con una clave.
CODE_KEYS = {k for k in TRANSLATIONS}

INT_HINT = re.compile(r"^(Int\(|count\b|card\.secondsLeft|row\.number|season\.season|\bs\b|\be\b|\bh\b|\bm\b|\bn\b|episode\b|fraction|state\.remaining)")
# Enteros que pueden ir en cualquier parte de la expresión («model.results.filter {…}.count», «nextCount», «session.captures»):
# SwiftUI arma la clave con %lld y, si aquí saliera %@, el inglés no se encontraría nunca.
INT_ANYWHERE = re.compile(r"(\.count\b|Count\b|\bminutes\b|\bpercent\b|\.captures\b|\badded\b)")


def to_format(literal: str) -> str:
    """El literal de Swift con `\\(…)` → la clave que genera SwiftUI (%lld para enteros, %@ para el resto)."""
    def repl(m: re.Match) -> str:
        expr = m.group(1)
        # Una llamada («Strings.duration(minutes)») da texto aunque lleve un entero adentro.
        return "%lld" if INT_HINT.match(expr) or ("(" not in expr and INT_ANYWHERE.search(expr)) else "%@"
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
        if "/Platform/" in f or f.endswith(("/Support/Demo.swift", "/Support/Perf.swift", "Previews.swift", "/Design/Tokens.swift", "/Design/MosaicBench.swift", "/Design/ModelObserver.swift")):
            continue
        for number, line in enumerate(Path(f).read_text(encoding="utf-8").splitlines(), 1):
            stripped = line.strip()
            if stripped.startswith("//"):
                continue
            for m in lit.finditer(line):
                text = m.group(1)
                # Con mayúscula, o una frase en minúsculas que empieza con texto o con un número («\\(n) por delante»): las dos
                # salen en pantalla (antes las de minúscula se saltaban y se quedaban sin inglés).
                sentence = re.match(r"^(\\\([^)]*\)\s)?[a-záéíóúñ]+ [a-záéíóúñ]", text) is not None and "Text(" in line
                if len(text) < 3 or (not re.match(r"^[A-ZÁÉÍÓÚÑ¿]", text) and not sentence) or text in IGNORE:
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
