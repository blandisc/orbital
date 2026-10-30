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
    # «¿Qué vemos hoy?» (`MatchDeckScreen`, `MatchDeck`).
    "Encuentra tu match perfecto": "Find your perfect match", "¿Qué vemos hoy?": "What should we watch today?",
    "Ya viste todo el mazo": "You've gone through the whole deck", "Cambia de ánimo o vuelve mañana.": "Change the mood or come back tomorrow.",
    "Guardaste %lld. Están en tu lista.": "You saved %lld. They're in your list.", "Descartar": "Dismiss",
    # Lo que ves y el Wrapped (`WatchingView`, `WatchingCard`, `WrappedView`). Con enteros SwiftUI arma la clave con %lld.
    "Tu año, día por día": "Your year, day by day", "El mapa de todo el año y lo que viste cada día": "The whole year's map and what you watched each day",
    "Lo que ves": "What you watch", "Lo que viste, contado": "What you watched, counted", "Mes": "Month", "Año": "Year",
    "%@ h esta semana": "%@ h this week", "%lld h esta semana": "%lld h this week", "%@ días seguidos": "%@ days in a row",
    "%lld días seguidos": "%lld days in a row", "%lld títulos": "%lld titles", "%lld h": "%lld h",
    "%@ películas y %@ capítulos": "%@ movies and %@ episodes", "%lld películas y %lld capítulos": "%lld movies and %lld episodes",
    "%lld de lo que viste": "%lld of what you watched", "%lld capítulos · %lld h": "%lld episodes · %lld h",
    "%lld capítulos, %lld h": "%lld episodes, %lld h", "%lld h %lld min": "%lld h %lld min",
    "Adivina": "Guess", "Casi: fue %@": "Close: it was %@", "Cuándo ves": "When you watch", "Cómo calificas": "How you rate",
    "Eso fue": "That was", "Lo que veas aquí o en Trakt aparece solo.": "What you watch here or on Trakt shows up on its own.",
    "Minutos por periodo": "Minutes per period", "Nada en este periodo": "Nothing in this period", "Toca para cerrar": "Tap to close",
    "Todo lo que has visto": "Everything you've watched", "Tu mes": "Your month", "Tu semana": "Your week",
    "Tu promedio: %@ estrellas": "Your average: %@ stars", "Tu promedio: %@": "Your average: %@", "Tus géneros": "Your genres",
    "Ver tu Wrapped": "See your Wrapped", "días seguidos hasta hoy": "days in a row until today",
    "días seguidos viendo algo": "days in a row watching something", "días seguidos, tu mejor racha": "days in a row, your best streak",
    "en películas y series": "in movies and shows", "frente a la pantalla": "in front of the screen", "fue tu género": "was your genre",
    "horas frente a la pantalla": "hours in front of the screen", "tu día más intenso": "your busiest day", "tu mejor racha": "your best streak",
    "títulos distintos": "different titles", "¿Qué viste más?": "Which did you watch most?", "Día por día": "Day by day",
    "Las dos": "Both", "Lo que más viste": "What you watched most", "Semana": "Week", "Siempre": "All time",
    # Colecciones, la repisa (`RepisaView`, `CollectionsCard`, `CanonPoster`). Con un entero SwiftUI arma la clave con %lld.
    "%@ del canon en tu repisa": "%@ from the canon on your shelf", "%lld del canon en tu repisa": "%lld from the canon on your shelf",
    "Empieza tu repisa: lo que veas del canon se pinta aquí": "Start your shelf: what you watch from the canon lights up here",
    "Los premios y listas que hay que ver": "The awards and lists worth watching", "tu mejor racha": "your best streak",
    "racha de hoy": "today's streak", "%lld días": "%lld days",
    "A tu repisa": "On your shelf", "Colecciones": "Collections", "Colección Criterion": "The Criterion Collection",
    "La más clásica que te falta": "The oldest one you're missing", "La más reciente que te falta": "The newest one you're missing",
    "La n.º %@ de la lista": "No. %@ on the list", "La n.º %lld de la lista": "No. %lld on the list",
    "Listas famosas": "Famous lists", "Más antiguas": "Oldest", "Más recientes": "Newest", "También en %@": "Also in %@",
    "Te falta": "Not seen yet", "Top 250": "Top 250", "Top 250 de IMDb": "IMDb Top 250", "Ya la vi": "I've seen it",
    "%lld de %@": "%lld of %@", "Palma de Oro": "Palme d'Or",
    # Filtro avanzado (`AdvancedFilterSheet`, `FilterEditor`, `FilterTile`, `FameQuadrant`).
    "%@ solo filtra películas": "%@ only filters movies",
    "Filtros": "Filters", "Formato": "Format", "Origen": "Origin", "Qué tan conocida": "How well known", "Resultados": "Results",
    "Ver más": "Show more", "Ver menos": "Show less", "Ver resultados": "See results", "Ver resultados · %lld": "See results · %lld",
    "Series en emisión": "Airing shows", "Series terminadas": "Ended shows", "En emisión": "Airing", "Terminadas": "Ended",
    "¿Cuáles series?": "Which shows?", "Sin %@": "No %@", "Los %@": "The %@s", "%@ o más": "%@ or more",
    "Corta": "Short", "Larga": "Long", "Quiero": "Include", "Clásicas": "Classics", "Antes de 1980": "Before 1980",
    "Toca una década; toca otra para hacer un rango.": "Tap a decade; tap another to make a range.",
    "Arriba lo mejor calificado; a la derecha, lo más famoso.": "Top is best rated; right is most famous.",
    "Joyas ocultas": "Hidden gems", "Muy buenas, poco vistas": "Great, rarely seen", "Las de siempre": "The classics",
    "Muy buenas y famosas": "Great and famous", "Para pocos": "For the few", "Rarezas y culto": "Oddities and cult",
    "Taquilleras": "Blockbusters", "Las que llenaron salas": "The ones that packed theaters",
    "Menos conocida": "Less known", "Más famosa": "More famous",
    "La calificación de la comunidad de TMDB, de 0 a 10.": "TMDB's community rating, from 0 to 10.",
    "Calificación mínima": "Minimum rating",
    "Agrégala en Ajustes › Avanzado para buscar con filtros.": "Add it in Settings › Advanced to search with filters.",
    "Nada con esos filtros": "Nothing matches those filters", "Quita alguno para ver más opciones.": "Remove one to see more options.",
    "México": "Mexico", "Estados Unidos": "United States", "España": "Spain", "Reino Unido": "United Kingdom",
    "Corea del Sur": "South Korea", "Japón": "Japan",
    # Calificar como en Trakt (`RatingStars`, `RatingReminder`, `RatingQueue`).
    "Tu calificación": "Your rating",
    "Sin calificar": "Not rated",
    "%@ de 5 estrellas": "%@ of 5 stars",
    "¿Qué tal %@?": "How was %@?",
    "y %lld más": "and %lld more",
    "No calificar esta": "Don't rate this one",
    "No calificar": "Don't rate",
    "Nada por calificar": "Nothing to rate",
    "Por calificar": "To rate",
    # Inicio nuevo (docs/producto/inicio-benchmark/).
    "Sugerencias para ti": "Suggestions for you",
    "Recomendadas por Trakt con lo que ves": "Recommended by Trakt from what you watch",
    "Filtros de búsqueda": "Search filters",
    "En tendencia esta semana": "Trending this week",
    "Lo nuevo de lo tuyo": "New from your shows",
    "Por lo que viste": "Because you watched",
    "Canales": "Channels",
    # Para ti B.
    "A la derecha la guardas, a la izquierda no.": "Swipe right to save, left to skip.",
    "Años": "Years",
    "Encuentra tu match perfecto": "Find your perfect match",
    "Lo que se está viendo": "What's being watched",
    "Lo que ves": "What you watch",
    "Todas las formas de encontrar qué ver": "Every way to find something to watch",
    "Pasear por el mosaico": "Wander the mosaic",
    "¿Qué vemos hoy?": "What should we watch today?",
    "Quitar %@ de tus canales": "Remove %@ from your channels",
    "Añadir %@ a tus canales": "Add %@ to your channels",
    # Nombres de las series de arranque de Canales (`ChannelsModel.starters` y `suggested`).
    "Los Simpson": "The Simpsons", "The Office": "The Office", "Friends": "Friends", "Seinfeld": "Seinfeld", "Futurama": "Futurama",
    "Breaking Bad": "Breaking Bad", "Malcolm": "Malcolm in the Middle", "Brooklyn Nine-Nine": "Brooklyn Nine-Nine", "Ted Lasso": "Ted Lasso",
    "Stargate SG-1": "Stargate SG-1", "The Bear": "The Bear",
    "Siempre hay un episodio al aire": "There's always an episode on",
    "Elegir canales": "Choose channels",
    "Añadir canal": "Add channel",
    "Tus canales": "Your channels",
    "Te sugerimos": "Suggested",
    "Busca una serie para añadirla": "Search a show to add it",
    "Añadir": "Add",
    "Añadido": "Added",
    "Es canal": "Is a channel",
    "No es canal": "Not a channel",
    "Entra justo donde va": "Tune in right where it is",
    "Cada canal pasa episodios al azar de esa serie, todo el día. Toca uno y entras justo donde va.": "Each channel plays random episodes of that show all day. Tap one to tune in right where it is.",
    "No encontré «%@». Prueba con otro nombre.": "I couldn't find “%@”. Try another name.",
    "Cambia lo que viste y cambian las sugerencias": "Change what you watched and the suggestions change",
    "Ya salió y lo que viene": "Out now and coming up",
    "HOY": "TODAY",
    "Ayer": "Yesterday",
    "en %lld días": "in %lld days",
    "De la más cercana a la más lejana": "From the closest to the farthest",
    "La temporada · ahora": "The season · now", "La temporada · mañana": "The season · tomorrow",
    "La temporada · en %lld días": "The season · in %lld days", "La temporada · en %@ días": "The season · in %@ days", "Próximas temporadas": "Coming seasons", "Ver la colección": "See the collection",
    "Las que estás viendo": "The ones you're watching", "%@ · %lld": "%@ · %lld",
    # Modo degradado (docs/producto/modo-degradado.md): la causa de verdad y la salida (`Degraded`, `UserMessages`).
    "Trakt no contesta": "Trakt isn't responding",
    "Real-Debrid no contesta": "Real-Debrid isn't responding",
    "Tus complementos no contestan": "Your add-ons aren't responding",
    "TMDB no contesta": "TMDB isn't responding",
    "Falta conectar Real-Debrid": "Real-Debrid isn't connected",
    "Faltan tus complementos": "Your add-ons are missing",
    "Falta la clave de TMDB": "The TMDB key is missing",
    "Lo que está en el iPhone sigue aquí: tus descargas, Seguir viendo y Mi lista. Lo que marques se sincroniza al volver la red.":
        "What's on your iPhone is still here: your downloads, Continue Watching and My List. What you mark syncs when you're back online.",
    "Hay internet, pero Trakt no responde. Lo tuyo está guardado en el iPhone y se sincroniza solo cuando vuelva.":
        "You're online, but Trakt isn't answering. Your stuff is saved on the iPhone and syncs on its own when it's back.",
    "Hay internet, pero Real-Debrid no responde. Suele ser momentáneo; lo descargado sí se puede ver.":
        "You're online, but Real-Debrid isn't answering. It's usually brief; your downloads still play.",
    "Hay internet, pero ninguno respondió. Suele ser momentáneo; si sigue, revisa tus complementos en Stremio.":
        "You're online, but none of them answered. It's usually brief; if it keeps happening, check your add-ons in Stremio.",
    "Revisa que la consola esté prendida y en la misma red que el iPhone.": "Make sure the console is on and on the same network as the iPhone.",
    "Faltan algunas imágenes y colecciones; lo demás funciona.": "Some images and collections are missing; everything else works.",
    "Lo más popular, los géneros y tus recomendaciones vienen de Trakt. Conéctalo en Ajustes.":
        "Most popular, genres and your recommendations come from Trakt. Connect it in Settings.",
    "Con Real-Debrid se ven y se descargan las películas y series. Agrega tu cuenta en Ajustes.":
        "Real-Debrid is what plays and downloads movies and shows. Add your account in Settings.",
    "No hay complementos que den dónde verlo. Agrégalos en Stremio y vuelve a entrar.":
        "No add-ons can find where to watch. Add them in Stremio and sign in again.",
    "Prende «Usar con tu Orbital» en Ajustes para ver lo de la consola.": "Turn on “Use with your Orbital” in Settings to see the console's lists.",
    "Sin ella faltan colecciones y pósters sin texto. Agrégala en Ajustes › Avanzado.":
        "Without it, collections and text-free posters are missing. Add it in Settings › Advanced.",
    "Tus descargas": "Your downloads",
    "No encontré dónde verlo": "I couldn't find where to watch it",
    "Conecta tu Real-Debrid en Ajustes: sin él casi no hay versiones que se vean aquí":
        "Connect your Real-Debrid in Settings: without it there are almost no versions that play here",
    "Hay internet, pero ninguno respondió": "You're online, but none of them answered",
    "No se pudo cargar": "Couldn't load",
    "No pude cargar la ficha: el servicio de las fichas no contesta. Intenta en un rato.":
        "We couldn't load this title: the title service isn't answering. Try again in a bit.",
    "Tu iPhone no tiene internet": "Your iPhone has no internet",
    "Conéctalo al Wi-Fi de tu casa para controlar la TV.": "Connect it to your home Wi-Fi to control the TV.",
    "Ver tus descargas": "See your downloads",
    "Hay internet, pero ninguno respondió. Suele ser momentáneo; intenta de nuevo en un rato.":
        "You're online, but none of them answered. It's usually brief; try again in a bit.",
    "Revisa tu conexión a internet e intenta de nuevo. Lo que descargaste sí se puede ver.":
        "Check your internet connection and try again. Your downloads still play.",
    "Tus complementos no contestan: hay internet, pero ninguno respondió. Intenta en un rato.":
        "Your add-ons aren't responding: you're online, but none of them answered. Try again in a bit.",
    "El servicio no contesta ahora. Intenta en un rato.": "The service isn't responding right now. Try again in a bit.",
    "%@. El servicio no contesta ahora; intenta en un rato.": "%@. The service isn't responding right now; try again in a bit.",
    "Tu sesión se cerró. Vuelve a conectar la cuenta en Ajustes.": "Your session ended. Reconnect the account in Settings.",
    "%@. Tu sesión se cerró: vuelve a conectar la cuenta en Ajustes.": "%@. Your session ended: reconnect the account in Settings.",
    "Se llenó el iPhone. Libera espacio y toca Reintentar.": "Your iPhone is full. Free up space and tap Retry.",
    # La voz del iPhone (fase 2) y Siri recortada.
    "Ahora": "Now",
    "Ahora, viendo %@": "Now watching %@",
    "Lo esencial": "The essentials",
    "igual en la tele y con Alexa": "same on the TV and with Alexa",
    "Toca una para mandarla a la tele · mantén para ver qué hace": "Tap one to send it to the TV · press and hold to see what it does",
    "Mantén una para ver qué hace": "Press and hold one to see what it does",
    "Aquí": "Here",
    "Toca el micrófono del control": "Tap the remote's microphone",
    "Siri": "Siri",
    "Más frases, por tema": "More phrases, by topic",
    "%lld frases · cómo pedirlo · si no funciona": "%lld phrases · how to ask · if it doesn't work",
    "Mandar a la tele": "Send to the TV",
    "La manda a la tele": "Sends it to the TV",
    "Prueba: ": "Try: ",
    "Mandar «%@»": "Send “%@”",
    "Toca y habla": "Tap and speak",
    "TE ESCUCHO": "LISTENING",
    "PREGUNTÁNDOLE A TU ORBITAL": "ASKING YOUR ORBITAL",
    "Un momento": "One moment",
    "Se detiene sola al callarte": "It stops when you stop talking",
    "Elegir episodio": "Pick episode",
    "¿Cuál?": "Which one?",
    "Entendí: «%@» · desliza para ver más": "I heard: “%@” · swipe to see more",
    "Poniéndose": "Playing",
    "Poner esta": "Play this one",
    "No llegó a tu Orbital": "It didn't reach your Orbital",
    "Entendí: «%@» · no se mandó": "I heard: “%@” · not sent",
    "Probar la conexión": "Test the connection",
    "Tu iPhone": "Your iPhone",
    "Túnel": "Tunnel",
    "Tu iPhone no tiene internet. Conéctate a una red y prueba otra vez.": "Your iPhone has no internet. Connect to a network and try again.",
    "El túnel no contesta: la consola puede estar dormida o el túnel trabado. «Prende la tele» la despierta.": "The tunnel isn't answering: the console may be asleep or the tunnel stuck. “Turn on the TV” wakes it.",
    "El túnel contesta, Orbital no: puede estar cerrada o reiniciándose. Espera un momento.": "The tunnel answers but Orbital doesn't: it may be closed or restarting. Wait a moment.",
    "Tu Orbital ya no reconoce este iPhone. Vuelve a conectarlo en Ajustes › Usar con tu Orbital.": "Your Orbital no longer recognizes this iPhone. Reconnect it in Settings › Use with your Orbital.",
    "En la TV ahora": "On TV now",
    "No encontré los episodios": "I couldn't find the episodes",
    "Pídelo por voz: «pon The Office temporada 2 episodio 5».": "Ask by voice: “pon The Office temporada 2 episodio 5”.",
    "Ponerlo en la TV": "Play it on the TV",
    "Orden por voz": "Voice command",
    "Pausa, volumen, siguiente episodio y lo esencial, en una sola frase.": "Pause, volume, next episode and the essentials, in a single phrase.",
    "Le dé play": "Hit play",
    "Se salte la intro": "Skip the intro",
    "Lo ponga en latino": "Put it in Latin American Spanish",
    "Siga viendo": "Continue watching",
    "Ponga la tele en vivo": "Put on live TV",
    "Cierra el video": "Close the video",
    "Cierre el video": "Close the video",
    "Ponga el siguiente episodio": "Play the next episode",
    "Suba el volumen": "Turn up the volume",
    "Ponga subtítulos": "Turn on subtitles",
    "Ya viene incluida: fichas y sinopsis en español, temporadas y lo popular en Netflix, Disney+ y HBO Max. Pon la tuya solo si quieres.": "It's already included: details and synopses in Spanish, seasons and what's popular on Netflix, Disney+ and HBO Max. Add your own only if you want.",
    # Ajustes › «Usar con tu Orbital»: el interruptor, la conexión con el código y el tutorial.
    "Apagar": "Turn off",
    "Apunta al código de la TV": "Point at the code on the TV",
    "Apágalo cuando quieras: la app vuelve a ser solo del iPhone. Lo que viste sigue en Trakt.": "Turn it off anytime: the app goes back to being just for your iPhone. What you watched stays in Trakt.",
    "Con tu Orbital conectada, «Ver en la TV» pone en la consola lo que ves aquí, donde ibas. Trakt se conecta aparte en cada uno.": "With your Orbital connected, “Watch on TV” plays on the console what you're watching here, where you left off. Trakt is connected separately on each.",
    "Conecta tu Orbital": "Connect your Orbital",
    "El iPhone y la TV se reconocen una vez y ya.": "Your iPhone and your TV recognize each other once, and that's it.",
    "En cualquier película o serie toca «Ver en la TV»: empieza en la sala justo donde ibas. Lo que veas allá sale arriba de la barra, en «En la TV».": "On any movie or show, tap “Watch on TV”: it starts in the living room right where you left off. What's playing there shows above the tab bar, in “On TV”.",
    "En la TV abre Ajustes › Cuentas › iPhone. Aparece un código.": "On the TV, open Settings › Accounts › iPhone. A code appears.",
    "Escanear el código": "Scan the code",
    "Escribe la dirección y el token.": "Type the address and the token.",
    "Ese código no es de Orbital. En la TV abre Ajustes › Cuentas › iPhone.": "That code isn't from Orbital. On the TV, open Settings › Accounts › iPhone.",
    "Este aparato no puede leer el código.": "This device can't read the code.",
    "Háblale": "Talk to it",
    "Lo encuentras cuando lo necesites; no hay que aprenderlo ahora.": "You'll find it when you need it; no need to learn it now.",
    "Lo que mandes desde la sala al iPhone llega a Inicio, para verlo en la cama.": "What you send from the living room to your iPhone lands in Home, to watch in bed.",
    "Mientras juegas": "While you play",
    "Orbital en la TV": "Orbital on the TV",
    "Prende «Usar con tu Orbital» en Ajustes para conectarla.": "Turn on “Use with your Orbital” in Settings to connect it.",
    "Pásalo a la TV": "Send it to the TV",
    "Qué puedes hacer con la TV": "What you can do with the TV",
    "Saltar": "Skip",
    "Se esconden «Ver en la TV», el control y la voz. Lo que viste se queda: viaja por Trakt.": "“Watch on TV”, the remote and voice are hidden. What you watched stays: it travels through Trakt.",
    "Si abres un juego en la consola, el iPhone te muestra su guía, tus notas y un temporizador.": "If you open a game on the console, your iPhone shows its guide, your notes and a timer.",
    "Toca «En la TV» y luego el control: muévete por los menús, pausa y sube el volumen sin buscar el mando. También está en el Centro de control.": "Tap “On TV” and then the remote: move through menus, pause and turn up the volume without looking for the controller. It's also in Control Center.",
    "Toca «Escanear el código» y apúntale.": "Tap “Scan the code” and point at it.",
    "Tu Trakt, tu Real-Debrid y tu país se quedan como los tienes aquí.": "Your Trakt, your Real-Debrid and your country stay as you have them here.",
    "Tu iPhone es el control": "Your iPhone is the remote",
    "Tu iPhone y tu Orbital quedaron conectados.": "Your iPhone and your Orbital are connected.",
    "Usar con tu Orbital": "Use with your Orbital",
    "Ver qué puedes hacer": "See what you can do",
    "Y también": "And also",
    "Ya lo sé": "I know",
    "Ya se conocen": "They know each other now",
    "¿Dejar de usar tu Orbital?": "Stop using your Orbital?",
    "¿Tienes la consola Orbital en tu TV? Prende esto para mandarle lo que ves, usar el iPhone de control y hablarle.": "Have the Orbital console on your TV? Turn this on to send it what you watch, use your iPhone as the remote and talk to it.",
    "Aparece un código para escribir en la página de Trakt que se indica. La sesión es solo de este iPhone: se avisa de lo que ves, sigues donde ibas en tus otros aparatos y salen tu watchlist y tus listas.": "A code appears to type on the Trakt page shown. The session is only for this iPhone: what you watch is reported, you pick up where you left off on your other devices, and your watchlist and lists show up.",
    "Falta la aplicación de Trakt. Si usas la tuya, pega su Client ID en Avanzado.": "The Trakt app is missing. If you use your own, paste its Client ID in Advanced.",
    "Guarda dónde te quedaste, lo que ya viste y tu lista, para que todos tus aparatos sepan lo mismo. Es gratis.": "It saves where you left off, what you've watched and your list, so all your devices know the same. It's free.",
    "Más fuentes de video, también de tu Real-Debrid": "More video sources, also from your Real-Debrid",
    "Orbital junta dos piezas. Te ayudamos a conectar cada una.": "Orbital puts two pieces together. We'll help you connect each one.",
    # Desacoplar Stremio, corte B: tu Real-Debrid y los complementos recomendados (los avisos de vencimiento viven en Platform/).
    "Fuentes de video, servidas por tu Real-Debrid": "Video sources, served by your Real-Debrid",
    "Subtítulos en tu idioma": "Subtitles in your language",
    "HTTP %@": "HTTP %@",
    "La clave está incompleta. Cópiala completa de real-debrid.com/apitoken.": "The key is incomplete. Copy the whole key from real-debrid.com/apitoken.",
    "No pude hablar con Real-Debrid. Revisa tu conexión.": "I couldn't reach Real-Debrid. Check your connection.",
    "Real-Debrid contestó algo raro. Intenta otra vez.": "Real-Debrid sent an odd answer. Try again.",
    "Real-Debrid no reconoce esa clave. Revisa que sea la de real-debrid.com/apitoken.": "Real-Debrid doesn't recognize that key. Make sure it's the one from real-debrid.com/apitoken.",
    "Tu Real-Debrid venció ayer": "Your Real-Debrid expired yesterday",
    "Tu Real-Debrid venció hace %lld días": "Your Real-Debrid expired %lld days ago",
    "Tu Real-Debrid vence hoy": "Your Real-Debrid expires today", "Renovar": "Renew",
    "Tu Real-Debrid vence en %lld días": "Your Real-Debrid expires in %lld days",
    "Renuévalo para no quedarte sin fuentes. No se renueva solo.": "Renew it so you don't run out of sources. It doesn't renew on its own.",
    # La Mac no controla tu Orbital (29 oct 2026): lo que contesta Siri ahí.
    "En la Mac, Orbital no controla la TV. Usa tu iPhone o tu iPad.": "On the Mac, Orbital doesn't control the TV. Use your iPhone or iPad.",
    # Los sustos en la barra del reproductor (estaban en el catálogo pero no aquí).
    "En las películas de terror, puntos rojos (fuertes) y ámbar (leves) en la barra de avance, de Where's The Jump.": "In horror movies, red (major) and amber (minor) dots on the progress bar, from Where's The Jump.",
    "Los puntos de la barra son sustos": "The dots on the bar are jump scares",
    "Marcar los sustos en la barra": "Mark jump scares on the bar",
    "Rojo, fuerte · ámbar, leve. Arrastra la barra para leer cada uno; se quitan en Ajustes › Reproductor.": "Red, major · amber, minor. Drag the bar to read each one; turn them off in Settings › Player.",
    "Susto fuerte": "Major scare",
    "Susto leve": "Minor scare",
    # Desacoplar Stremio, corte D: las listas públicas salen de Trakt y los catálogos de complementos dicen «Complemento».
    "Aprobadas por la crítica": "Critically acclaimed", "Rotten Tomatoes": "Rotten Tomatoes",
    "Certified Fresh recientes · Series Fresh": "Recent Certified Fresh · Fresh shows",
    "Certified Fresh": "Certified Fresh",
    "Fresh en Rotten Tomatoes": "Fresh on Rotten Tomatoes",
    "De tus complementos": "From your add-ons",
    "Lo que más se está viendo ahora": "What people are watching right now",
    "Lo que más se está viendo ahora, películas y series": "What people are watching right now, movies and shows",
    "No encontré este título": "I couldn't find this title",
    "No pude buscar. Revisa tu conexión.": "I couldn't search. Check your connection.",
    "No pude cargar lo popular. Revisa tu conexión.": "I couldn't load what's popular. Check your connection.",
    "No pude leer el catálogo: %@": "I couldn't read the catalog: %@",
    "Complemento": "Add-on",
    "Ir": "Go",
    "Ajustes…": "Settings…",
    "Control de la TV": "TV remote",
    "Cerrar el reproductor": "Close player",
    # Favoritos de Trakt: el corazón de la ficha y su fila en Inicio.
    "Quitar de favoritos": "Remove from favorites",
    "Agregar a favoritos": "Add to favorites",
    "Agregada a tus favoritos": "Added to your favorites",
    "Quitada de tus favoritos": "Removed from your favorites",
    "En tus favoritos": "In your favorites",
    "No pude cambiar tus favoritos de Trakt": "I couldn't change your Trakt favorites",
    "Conecta Trakt en Ajustes": "Connect Trakt in Settings",
    "La anterior no respondió. Sigue en el mismo punto.": "The previous one didn't respond. Same spot.",
    "Elegir otra versión": "Choose another version",
    "Las clásicas": "The classics",
    # Nombres de encabezados HTTP (no se ven en pantalla): iguales en los dos idiomas.
    "X-Orbital-Device": "X-Orbital-Device",
    "X-Orbital-Device-Id": "X-Orbital-Device-Id",
    "X-Orbital-Device-Kind": "X-Orbital-Device-Kind",
    "Favoritos": "Favorites",
    "Lo que marcaste con el corazón": "What you marked with the heart",
    "No pude cambiar tus favoritos de Trakt: %@": "I couldn't change your Trakt favorites: %@",
    "Llegaste a 100 favoritos en Trakt: quita uno para agregar otro.": "You've reached 100 favorites on Trakt: remove one to add another.",
    # Un Simpson al azar (Centro de control y Ajustes), «Quitar de …» en tus listas y «Episodios» en el reproductor.
    "Pone un episodio de Los Simpson al azar.": "Plays a random episode of The Simpsons.",
    "La dona de Inicio elige un episodio de estas temporadas.": "The donut on Home picks an episode from these seasons.",
    "Las clásicas (%lld–%lld)": "The classics (%lld–%lld)",
    "Quitar de tu watchlist": "Remove from your watchlist",
    "No pude marcar «%@» como vista": "Couldn't mark “%@” as watched", "«%@» quedó como vista": "“%@” marked as watched",
    "No descargado": "Not downloaded", "Temporada %lld, episodio %lld, %@": "Season %lld, episode %lld, %@",
    "Siguiente · %@": "Next · %@", "T%lld": "S%lld",
    # La órbita de «Buscando la mejor versión».
    "Buscando en tus complementos": "Searching your add-ons", "1 versión encontrada": "1 version found",
    "%lld versiones encontradas": "%lld versions found", "%lld de %lld complementos": "%lld of %lld add-ons",
    "%@ y %lld más": "%@ and %lld more", "Elegimos %@": "Picked %@", "Abriendo…": "Opening…",
    # Subtítulos sin conexión (descargas).
    "Guardado con la descarga": "Saved with the download", "No disponible sin conexión": "Not available offline",
    "No encontré subtítulos en %@": "Couldn't find subtitles in %@",
    "Sin conexión: no hay subtítulos en %@ en esta descarga": "Offline: this download has no subtitles in %@",
    "Sin conexión: no hay subtítulos guardados en este idioma.": "Offline: no saved subtitles in this language.",
    "Sin conexión: solo los subtítulos del video y los guardados con la descarga.": "Offline: only the video's subtitles and the ones saved with the download.",
    "Sin conexión: solo los subtítulos del video.": "Offline: only the video's subtitles.",
    # «Guardar»: la watchlist de Trakt por omisión y la hoja «Guardar en…».
    "Guardada en tu watchlist": "Saved to your watchlist", "Quitada de tu watchlist": "Removed from your watchlist",
    "No pude cambiar tu watchlist de Trakt": "Couldn't change your Trakt watchlist",
    "Principales": "Main lists", "Cargando tus listas de Trakt": "Loading your Trakt lists", "Lista de Trakt": "Trakt list",
    "Guardado en el iPhone: llega a Trakt en cuanto haya conexión.": "Saved on your iPhone: it reaches Trakt as soon as there's a connection.",
    "Desliza para fijar": "Slide to lock", "Desliza para quitar": "Slide to unlock",
    "Subtítulo %lld de %lld": "Subtitle %lld of %lld",
    "Toca para quitar": "Tap to stop",
    "Continuar T%@ E%lld": "Continue S%@ E%lld", "Ver T%@ E%lld": "Watch S%@ E%lld",
    "Marcar como vista": "Mark as watched", "Versión de la serie": "Series version",
    "Subtítulos: %@": "Subtitles: %@",
    "Solo este episodio": "Just this episode",
    "Desde aquí": "From here on",
    "Para": "For",
    "Versión de la serie: %@": "Series version: %@",
    "Versión de este episodio…": "Version for this episode…",
    "Lo que recuerda cada título": "What each title remembers",
    "Olvidar": "Forget",
    "Lo que elegiste viendo cada uno; vale aquí y en tu Orbital. Desliza para olvidarlo.": "What you picked while watching each one; it applies here and on your Orbital. Swipe to forget it.",
    "Ningún título recuerda nada todavía": "No title remembers anything yet",
    "Subtítulos en inglés": "English subtitles", "Pon subtítulos en inglés": "Turn on English subtitles",
    "Ponga subtítulos en inglés": "Turn on English subtitles",
    "En latino": "In Latin American Spanish", "Pon el audio en latino": "Switch the audio to Latin American Spanish",
    "Ponlo en latino": "Put it in Latin American Spanish", "Póngalo en latino": "Put it in Latin American Spanish",
    "En castellano": "In Castilian Spanish", "Pon el audio en castellano": "Switch the audio to Castilian Spanish",
    "Ponlo en castellano": "Put it in Castilian Spanish", "Póngalo en castellano": "Put it in Castilian Spanish",
    "Buscando la mejor versión…": "Finding the best version…",
    "Buscar versión": "Find a version",
    "Con datos móviles te avisamos antes de usar versiones de más de %lld GB.": "On cellular we'll ask before using versions over %lld GB.",
    "De las series que sigues en Trakt. Te avisa cuando ya se puede ver en Real-Debrid, con botones para verlo aquí, en la TV o bajarlo. De las 23 a las 8 el aviso espera a la mañana; cada episodio llega en su propio aviso.": "For the shows you follow on Trakt. It tells you once it can be watched on Real-Debrid, with buttons to watch here, on the TV or download it. From 11 PM to 8 AM it waits until morning; each episode gets its own notification.",
    "El enlace de esta versión caducó o ya no existe. Toca ▶ para buscar otro.": "This version's link expired or no longer exists. Tap ▶ to find another.",
    "El servidor falló. Se vuelve a intentar.": "The server failed. Trying again.",
    "El servidor pidió esperar un poco. Se vuelve a intentar.": "The server asked to wait a bit. Trying again.",
    "Ese complemento no responde o no da videos ni fichas.": "That add-on isn't responding or doesn't provide videos or details.",
    "Esta versión no tiene un enlace para descargar.": "This version has no download link.",
    "La versión dejó de responder. Al intentar de nuevo seguimos donde ibas, con otra si hace falta.": "The version stopped responding. Trying again picks up where you were, with another one if needed.",
    "Misma versión": "Same version",
    "Ninguna versión funcionó.": "No version worked.",
    "No encontré una versión para descargar %@.": "I couldn't find a version to download %@.",
    "No hay versiones en Real-Debrid para este título.": "There are no Real-Debrid versions for this title.",
    "No pude abrir este video. La versión dejó de responder.": "I couldn't open this video. The version stopped responding.",
    "No pude buscar dónde verlo": "I couldn't look for where to watch it",
    "No pude buscar versiones. Intenta de nuevo.": "I couldn't look for versions. Try again.",
    "Probamos las versiones que hay y ninguna respondió. A veces es momentáneo.": "We tried the available versions and none responded. Sometimes it's temporary.",
    "Probando otra versión (%lld)…": "Trying another version (%lld)…",
    "Prueba otra versión o ábrela aquí": "Try another version or open it here",
    "Sin conexión: no pude buscar dónde verlo.": "Offline: I couldn't look for where to watch it.",
    "Sin versiones por ahora": "No versions yet",
    "Subtítulo %lld": "Subtitle %lld",
    "Subtítulo anterior": "Previous subtitle",
    "Subtítulo siguiente": "Next subtitle",
    "Todas las fuentes": "All sources",
    "Otra versión": "Another version",
    "Iba en %lld %%. Puedes reintentar o elegir otra versión.": "It was at %lld %%. You can retry or pick another version.",
    "No pudo empezar. Puedes reintentar o elegir otra versión.": "It couldn't start. You can retry or pick another version.",
    "Abierto": "Open",
    "%lld semillas": "%lld seeders",
    "Sin ajuste": "No offset", "Buscar…": "Search…", "en Real-Debrid": "on Real-Debrid", "Real-Debrid aún no la tiene": "Real-Debrid doesn't have it yet",
    "se supone": "assumed", "Descarga en el iPhone": "Download on iPhone", "Abre otra versión del video en el mismo punto": "Opens another version of the video at the same point",
    "Abrir": "Open", "Por idioma": "By language", "Todas (%lld)": "All (%lld)", "Cambiar a esta": "Switch to this one", 
    "Esa versión no abrió": "That version didn't open", "Volviste a la que veías, en el mismo punto.": "You're back on the one you were watching, at the same point.",
    "Mandó su aviso de «descargando». Puede tardar; prueba más tarde u otra versión.": "It sent its “downloading” notice. It may take a while; try later or another version.",
    "Real-Debrid aún no tiene esta versión": "Real-Debrid doesn't have this version yet", "Abrirla de todos modos": "Open it anyway", "Mejor no": "Never mind",
    "Empieza a bajarla y puede tardar minutos u horas. Si manda su aviso de «descargando», vuelves a la que ves en el mismo punto.": "It starts downloading it and may take minutes or hours. If it sends its “downloading” notice, you go back to the one you're watching at the same point.",
    "Del video · forzados": "From the video · forced", "Del video · para sordos": "From the video · SDH",
    "Centro": "Middle", "Mover el video": "Move the video",
    "Arrastra hacia arriba o hacia abajo": "Drag up or down", "Subir el video": "Move the video up", "Bajar el video": "Move the video down",
    "Más del episodio": "More for this episode",
    "Abriendo tu descarga…": "Opening your download…", "Abriendo la versión que elegiste…": "Opening the version you picked…",
    "Buscando recomendaciones": "Finding recommendations",
    "Trakt aún no relaciona nada con este título. Prueba con otro.": "Trakt doesn't relate anything to this title yet. Try another one.",
    "Modo iPod": "iPod mode", "Blanco": "White", "Negro": "Black", "Reproduciendo": "Now Playing",
    "Menú: cerrar el reproductor": "Menu: close the player", "Atrás 10 segundos": "Back 10 seconds",
    "Adelante 10 segundos": "Forward 10 seconds", "Reproducir o pausar": "Play or pause",
    "Elige uno o varios · el número es cuántas hay": "Pick one or more · the number is how many there are",
    "Buscando opciones…": "Finding options…",
    "de «%@»": "from “%@”",
    "de %lld listas": "from %lld lists",
    
    "Ninguna con estos filtros": "None with these filters",
    
    "Según (basta una)": "According to (any one)",
    "TMDB (falta su clave)": "TMDB (key missing)",
    "Más filtros · %lld": "More filters · %lld",
    "Buscar entre tus %lld listas": "Search your %lld lists",
    "Con %@": "With %@",
    "Cualquier ánimo": "Any mood",
    "Cualquier época": "Any era",
    "De qué listas": "Which lists",
    "Limpiar": "Clear",
    "Listo · %lld lista": "Done · %lld list",
    "Listo · %lld listas": "Done · %lld lists",
    "Listo · todo lo sugerido": "Done · everything suggested",
    "Más filtros": "More filters",
    "Nada con %@": "Nothing with %@",
    "Ninguno": "None",
    "Prueba quitando un filtro.": "Try removing a filter.",
    "Quitar %@": "Remove %@",
    "Según (basta una):": "According to (any one):",
    "Sin mínimo": "No minimum",
    "Sin opciones con eso": "No options with that",
    "TMDB necesita su clave en Ajustes.": "TMDB needs its key in Settings.",
    "Todas · %lld": "All · %lld",
    "Todas, de la A a la Z": "All, A to Z",
    "Todo lo sugerido": "Everything suggested",
    "Usadas hace poco": "Recently used",
    "Ver %lld": "See %lld",
    "Ánimo": "Mood",
    "%lld opción": "%lld option",
    "%lld opciones": "%lld options",
    
    
    
    
    
    "%lld lista": "%lld list",
    "%lld listas": "%lld lists",
    "de %lld": "of %lld",
    "%lld título": "%lld title",
    
    "Elegidas": "Chosen",
    
    
    
    "%lld puestos": "%lld set",
    
    
    "Bloquear pantalla": "Lock screen",
    "Ventana (PiP)": "Window (PiP)",
    "Ligera para guardar": "Light to save",
    "Toca una para verla · ↓ para guardarla": "Tap one to watch · ↓ to save it",
    "Copiar resultados": "Copy results",
    "Con la app abierta baja a toda velocidad; con la app cerrada iOS la frena mucho. Para bajar rápido, deja Orbital abierta: al salir, sigue sola, más lento.": "With the app open it downloads at full speed; with the app closed iOS slows it down a lot. To download fast, keep Orbital open: when you leave, it keeps going on its own, slower.",
    "Midiendo…": "Measuring…",
    "Probar la velocidad": "Test the speed",
    "Probar otra vez": "Test again",
    "Qué quiere decir": "What it means",
    "Real-Debrid limita cada conexión: con varias a la vez baja mucho más rápido, y así baja Orbital con la app abierta.": "Real-Debrid limits each connection: with several at once it downloads much faster, and that's how Orbital downloads with the app open.",
    "Real-Debrid te está dando menos que tu internet: puede ser su servidor de ese momento o la ruta hasta él.": "Real-Debrid is giving you less than your internet: it may be its server right now or the route to it.",
    "Real-Debrid y la app ya van a la velocidad de tu internet: el tope es tu conexión.": "Real-Debrid and the app already run at your internet speed: your connection is the limit.",
    "Si las descargas van lentas: mide tu internet, Real-Debrid y la forma en que baja la app.": "If downloads are slow: measures your internet, Real-Debrid and how the app downloads.",
    "Unos segundos cada una, sin guardar nada. Hazla con Wi‑Fi y con la app abierta.": "A few seconds each, nothing is saved. Run it on Wi‑Fi with the app open.",
    "Tu internet (sin Real-Debrid)": "Your internet (without Real-Debrid)",
    "Real-Debrid · 1 conexión": "Real-Debrid · 1 connection",
    "Real-Debrid · 8 conexiones": "Real-Debrid · 8 connections",
    "Real-Debrid · con la app cerrada (segundo plano)": "Real-Debrid · with the app closed (background)",
    "Sin enlace": "No link",
    "No respondió": "No response",
    "No pude conseguir un enlace de Real-Debrid para probar.": "I couldn't get a Real-Debrid link to test.",
    "Empezar": "Start",
    "Copiado": "Copied",
    "Se va a ver en: %@": "It will play in: %@",
    "Bajando %@ · la misma versión": "Downloading %@ · the same version",
    "Ya está en Descargas": "Already in Downloads",
    "Ya está en Descargas.": "Already in Downloads.",
    "Descargar este video": "Download this video",
    
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
    "Tu sesión de Stremio se cerró. Vuelve a entrar para ver lo que tienes a medias y tu lista.": "Your Stremio session ended. Sign in again to see what you're watching and your list.", "Volver a entrar": "Sign in again", "Tu sesión de Trakt se cerró": "Your Trakt session ended", "Conéctala otra vez para tus recomendaciones y lo que viste.": "Connect it again for your recommendations and history.", "Conectar": "Connect", "No pude revisar tu OneDrive. Revisa tu conexión.": "We couldn't check your OneDrive. Check your connection.", "Volver a conectar": "Reconnect",
    "‹ Anterior": "‹ Previous", "Ya la probaste": "Already tried", "Con subtítulos para este video": "With subtitles for this video", "Buscar en internet": "Search online",
    "No pude cargar la ficha. Revisa tu conexión.": "We couldn't load this title. Check your connection.", "Aún sin episodios": "No episodes yet", "No pude armar tu mosaico": "We couldn't build your mosaic", "Revisa tu conexión e intenta de nuevo.": "Check your connection and try again.", "Tu Orbital ya no reconoce este iPhone": "Your Orbital no longer recognizes this iPhone", "Vuelve a conectarlos: en tu TV abre Ajustes › iPhone y escanea el código.": "Connect them again: on your TV open Settings › iPhone and scan the code.", "Tu Orbital no contesta": "Your Orbital isn't responding", "Revisa que la consola esté prendida y en la misma red que tu iPhone.": "Make sure the console is on and on the same network as your iPhone.",
    "Sin fuentes por ahora": "No sources yet", "Todavía no sale": "Not out yet", "Real-Debrid aún no lo tiene. Los estrenos suelen aparecer unas horas después.": "Real-Debrid doesn't have it yet. New releases usually show up a few hours later.",
    "Termina como a las %@": "Done around %@",
    "faltan %@": "%@ left", "Real-Debrid aún no tiene este título. Los estrenos suelen aparecer unas horas después.": "Real-Debrid doesn't have this title yet. New releases usually show up a few hours later.", "Sin conexión: no pude preguntar por fuentes. Revisa tu internet.": "No connection: we couldn't ask for sources. Check your internet.", "No pude buscar fuentes. Intenta de nuevo.": "We couldn't search for sources. Try again.", "Real-Debrid aún no tiene este título.": "Real-Debrid doesn't have this title yet.", "No pude preparar la descarga. Intenta de nuevo.": "We couldn't prepare the download. Try again.", "Sin conexión: no pude preguntar por fuentes.": "No connection: we couldn't ask for sources.",
    "Ajustar tiempo": "Adjust timing", "Apagar subtítulos": "Turn subtitles off", "Buscando versiones en internet…": "Searching online for versions…", "Mantén presionado para apagarlos o prenderlos": "Touch and hold to turn them off or on", "Prender subtítulos": "Turn subtitles on", "Subtítulos desactivados": "Subtitles off", "¿Las letras salen antes que la voz? Toca +.": "Do the words show up before the voice? Tap +.", "Desactivados": "Off",
    "Llena la pantalla y recorta los lados": "Fills the screen and crops the sides",
    "Prueba de velocidad": "Speed test",
    "El archivo descargado no se puede leer. Bórralo en Descargas y bájalo otra vez.": "The downloaded file can't be read. Delete it in Downloads and download it again.", "Intentar de nuevo": "Try again", "La fuente dejó de responder. Al intentar de nuevo seguimos donde ibas, con otra si hace falta.": "The source stopped responding. Try again and we'll pick up where you were, with another source if needed.", "No pude reproducirlo": "We couldn't play it", "No se puede abrir la descarga": "The download can't be opened", "Probamos las fuentes que hay y ninguna respondió. A veces es momentáneo.": "We tried the available sources and none responded. Sometimes it's temporary.", "Real-Debrid aún no tiene esta película. Los estrenos suelen aparecer unas horas después; vuelve a intentarlo más tarde.": "Real-Debrid doesn't have this movie yet. New releases usually show up a few hours later; try again later.", "Real-Debrid aún no tiene este episodio. Los estrenos suelen aparecer unas horas después; vuelve a intentarlo más tarde.": "Real-Debrid doesn't have this episode yet. New releases usually show up a few hours later; try again later.", "Revisa tu conexión a internet e intenta de nuevo.": "Check your internet connection and try again.", "Se cortó el video": "The video stopped", "Sin conexión": "No connection", "Todavía no hay dónde verlo": "Nowhere to watch it yet",
    "Bajando %lld": "Downloading %lld",
    "Bajar también esta": "Download this one too", "Cambiarla por esta": "Replace it with this one", "La que elegiste": "The one you chose", "Puedes guardar varias versiones del mismo título.": "You can keep several versions of the same title.", "Ya la tienes": "You already have it",
    "Ahora no": "Not now", "Atajo": "Shortcut", "Aún no tienes listas en Trakt.": "You don't have any Trakt lists yet.", "Buscando en internet…": "Searching online…", "Buscar idioma": "Search language", "Calificación": "Rating", "Cambia el zoom del video": "Changes the video zoom", "Cargando…": "Loading…","Clasificación %@": "Rated %@", "Coincide con tu copia": "Matches your copy", "De %lld para arriba": "%lld and up", "De internet": "From the internet", "Del video": "From the video", "Década": "Decade", "En vertical solo se nota en videos de otro formato": "In portrait it only shows on videos with another aspect ratio", "Esta lista todavía no tiene títulos.": "This list has no titles yet.", "Lista de subtítulos": "Subtitle list", "Lo mejor disponible: %@": "Best available: %@", "Mantén presionado para ver la lista de subtítulos": "Touch and hold to see the subtitle list", "Mejor calificadas (IMDb y Trakt)": "Top rated (IMDb and Trakt)", "Más cortas primero": "Shortest first", "Más idiomas": "More languages", "No hay subtítulos en este idioma.": "There are no subtitles in this language.", "No pude abrir este video. La fuente dejó de responder.": "I couldn't open this video. The source stopped responding.", "Otros idiomas": "Other languages", "Pantalla y giro bloqueados": "Screen and rotation locked", "Reconectando…": "Reconnecting…", "Siguiente subtítulo": "Next subtitle", "Sin filmografía": "No filmography", "Subtítulos antes": "Subtitles earlier", "Subtítulos después": "Subtitles later", "TMDB no tiene títulos de esta persona.": "TMDB has no titles for this person.", "Tus idiomas": "Your languages", "Versión %lld": "Version %lld", "Versión anterior": "Previous version", "Versión siguiente": "Next version", "Volver a los canales": "Back to channels", "Volver al reproductor": "Back to the player", "%@ para el siguiente susto": "%@ until the next scare",
    "CH %@": "CH %@",
    "Lo último que viste": "Last watched",
    "Calendario del mes": "Month calendar", "Ese día no sale nada de lo que sigues.": "Nothing you follow comes out that day.", "Mes anterior": "Previous month", "Mes siguiente": "Next month", "Nada sale": "Nothing out", "te recomendamos:": "we recommend:",
    "El N.º 1 de cada plataforma": "No. 1 on each platform", "Lo que todos están viendo": "What everyone's watching",
    "Lo número 1 en tus plataformas": "The number 1 on your platforms",
    "Mejor elige la carpeta de tus películas: con todo tu OneDrive la revisión tarda más.": "Better choose the folder with your movies: with your whole OneDrive the check takes longer.", "Todo tu OneDrive": "Your whole OneDrive", "Usar todo mi OneDrive": "Use my whole OneDrive",
    "Elegir carpeta": "Choose folder", "Elige la carpeta de tus películas": "Choose the folder with your movies", "Películas: %@ · Series: %@": "Movies: %@ · Shows: %@", "Películas: %lld · Series: %lld": "Movies: %lld · Shows: %lld", "Solo se mira esa carpeta y sus subcarpetas.": "Only that folder and its subfolders are read.", "Toca el del centro para volver a como venían.": "Tap the middle one to go back to how they came.", "«Ver» usa la mejor; «Descargar», la de 1080p.": "“Watch” uses the best one; “Download”, the 1080p one.",
    "A tiempo": "In sync", "Ajustes de OneDrive": "OneDrive settings", "Antes": "Earlier", "Bajar esta": "Download this one", "Bajar temporada": "Download season", "Busca el título": "Search for the title", "Cada video se reconoce por su nombre: «Dune Part Two (2024).mkv», «Severance S01E03.mkv».": "Each video is recognized by its name: “Dune Part Two (2024).mkv”, “Severance S01E03.mkv”.", "Conecta tu OneDrive": "Connect your OneDrive", "Corregir": "Fix", "Corregir ficha": "Fix match", "Corregir ficha: búscala por nombre": "Fix match: search for it by name", "De Mi media": "From My media", "Después": "Later", "El archivo": "The file", "En el iPhone": "On iPhone", "Episodio %@": "Episode %@", "Esta carpeta está vacía.": "This folder is empty.", "Lo último que subiste": "The latest you uploaded", "Mi media": "My media", "Mi media se vacía. Lo que ya bajaste al iPhone se queda.": "My media is cleared. What you already downloaded to the iPhone stays.", "Nada reconocido todavía": "Nothing recognized yet", "No encontré ese archivo en tu OneDrive.": "I couldn't find that file on your OneDrive.", "No está en tu carpeta": "Not in your folder", "No los reconocí por su nombre: elige cuál es.": "I didn't recognize them by name: choose which one it is.", "No pude pedir el archivo a OneDrive.": "I couldn't get the file from OneDrive.", "Para ver se usa la mejor; para bajar, la de 1080p. Mantén presionada una para elegirla.": "The best one is used for watching; the 1080p one for downloading. Press and hold one to choose it.", "Por nombre": "By name", "Recién agregado": "Recently added", "Revisando tu carpeta…": "Checking your folder…", "Revisando…": "Checking…", "Saga": "Collection", "Sin ficha": "No match", "Sin resultados: prueba con el título en inglés.": "No results: try the English title.", "Sin ver": "Unwatched", "Sincronía": "Sync", "Tu OneDrive · %@": "Your OneDrive · %@", "Tus películas y series de OneDrive, aquí: se ven al instante y se bajan al iPhone.": "Your OneDrive movies and shows, here: they play instantly and download to the iPhone.", "Tus películas y series salen en Descargas › Mi media: se ven al instante y se bajan al iPhone.": "Your movies and shows appear in Downloads › My media: they play instantly and download to the iPhone.", "Ver carpetas": "Browse folders", "Ver esta": "Watch this one", "Versiones en tu carpeta": "Versions in your folder", "Ya no está en tu carpeta": "No longer in your folder", "¿No es esta película?": "Not this movie?", "¿No es esta serie?": "Not this show?", "%lld versiones": "%lld versions", "%lld películas · %lld series · %@": "%lld movies · %lld shows · %@", "Agregada": "Added",
    "%@ sin ficha: revisa que su nombre diga el título (y el año).": "%@ without a match: check that the file name says the title (and the year).", "Aparece un código para escribir en microsoft.com/link. Solo pide leer tus archivos.": "A code appears to type at microsoft.com/link. It only asks to read your files.", "Conectar OneDrive": "Connect OneDrive", "Copiar el código y abrir Microsoft": "Copy the code and open Microsoft", "Desconectar OneDrive": "Disconnect OneDrive", "Dónde están tus películas": "Where your movies are", "Elige una": "Choose one", "En tu OneDrive": "On your OneDrive", "Episodios": "Episodes", "Escribe este código en %@": "Type this code at %@", "Id. de aplicación (cliente)": "Application (client) ID", "Lo que encontré": "What I found", "Microsoft no aceptó el código.": "Microsoft didn't accept the code.", "No hay más carpetas aquí.": "No more folders here.", "OneDrive": "OneDrive", "OneDrive conectado": "OneDrive connected", "Orbital solo lee: nunca cambia ni borra nada": "Orbital only reads: it never changes or deletes anything", "Rechazaste la conexión en Microsoft.": "You declined the connection at Microsoft.", "Revisada %@": "Checked %@", "Revisar ahora": "Check now", "Se ven al instante y se pueden descargar": "They play instantly and can be downloaded", "Solo mira la carpeta que elijas después": "It only looks at the folder you choose next", "Solo se mira esa carpeta y sus subcarpetas. Cada video se reconoce por su nombre («Dune Part Two (2024).mkv», «Severance S01E03.mkv»).": "Only that folder and its subfolders are read. Each video is recognized by its name (“Dune Part Two (2024).mkv”, “Severance S01E03.mkv”).", "Tu OneDrive": "Your OneDrive", "Tu OneDrive primero; luego Real-Debrid, por calidad": "Your OneDrive first; then Real-Debrid, by quality", "Tu copia en OneDrive": "Your copy on OneDrive", "Tus videos de OneDrive dejan de salir como fuente. Lo descargado se queda.": "Your OneDrive videos stop showing up as sources. Downloads stay.", "Tus videos salen primero en «Fuente» de su película o episodio: se ven al instante y se pueden descargar.": "Your videos show up first under “Source” for their movie or episode: they play instantly and can be downloaded.", "Tus videos se ven directo, sin bajarlos completos": "Your videos play directly, without downloading them fully", "Usa la misma de la TV. Si aún no la tienes: en entra.microsoft.com › Registros de aplicaciones › Nuevo registro, ponle «Orbital», elige «Cuentas personales de Microsoft» y créala. En «Autenticación» activa «Permitir flujos de clientes públicos». Copia su «Id. de aplicación (cliente)».": "Use the same one as the TV. If you don't have it yet: at entra.microsoft.com › App registrations › New registration, name it “Orbital”, choose “Personal Microsoft accounts” and create it. Under “Authentication”, turn on “Allow public client flows”. Copy its “Application (client) ID”.", "Usar esta carpeta": "Use this folder", "¿Desconectar OneDrive?": "Disconnect OneDrive?",
    "Horas, tus días más intensos, lo que más viste y tu mapa de calor": "Hours, your busiest days, what you watched most and your heat map", "Lo más visto en tu país esta semana": "Most watched in your country this week", "Lo que todo el mundo está viendo": "What everyone is watching", "Lo que viste, día por día": "What you watched, day by day", "No pude traer los episodios de Los Simpson.": "I couldn't get The Simpsons episodes.", "Recomendadas con lo que ves": "Recommended from what you watch", "Top 10 en Netflix": "Top 10 on Netflix", "Tu año en Orbital": "Your year on Orbital", "Un Simpson al azar": "A random Simpsons", "Un Simpson al azar (T5–T15)": "A random Simpsons (S5–S15)", 
    "Desliza hacia arriba o abajo para ir de un día con algo visto a otro": "Swipe up or down to move between days you watched something", "Día anterior con algo visto": "Previous day you watched something", "Día siguiente con algo visto": "Next day you watched something", "Elige otro título para recomendarte por él": "Pick another title to get recommendations from", "Ese día no viste nada.": "You didn't watch anything that day.", "Recomiéndame por…": "Recommend based on…", "Toca el nombre para elegir otro de lo que viste": "Tap the name to pick something else you watched",
    "Hoy no hay ranking de este servicio.": "No ranking for this service today.", "Lo más visto hoy · JustWatch": "Most watched today · JustWatch",
    "Abrir con Infuse": "Open with Infuse", "Activa los avisos de Orbital en Ajustes del iPhone.": "Turn on Orbital notifications in iPhone Settings.", "Apagados": "Off", "Avienta la carta para cambiar": "Flick the card to change", "Bajando %@": "Downloading %@", "Bajando la recomendada": "Downloading the recommended one", "Borrar la descarga": "Delete the download", "Cancelar la descarga": "Cancel the download", "Clasificación": "Rating", "Con": "With", "Conecta Trakt para saber qué series sigues.": "Connect Trakt so we know which shows you follow.", "Creada por": "Created by", "Cuando un estreno ya está para ver": "When a new episode is ready to watch", "Cómo eliges, en Para ti, de qué título quieres recomendaciones.": "How you pick, in For You, which title to get recommendations from.", "De Real-Debrid · por calidad, la recomendada primero": "From Real-Debrid · by quality, recommended first", "De las series que sigues en Trakt. Te avisa cuando ya hay fuente en Real-Debrid, con botones para verlo aquí, en la TV o bajarlo. De las 23 a las 8 el aviso espera a la mañana; cada episodio llega en su propio aviso.": "For the shows you follow on Trakt. It tells you once there's a Real-Debrid source, with buttons to watch here, on the TV or download it. From 11 PM to 8 AM it waits until morning; each episode gets its own notification.", "Descargada": "Downloaded", "Desliza hacia arriba o abajo para cambiar el título": "Swipe up or down to change the title", "Detalles": "Details", "Duración": "Runtime", "Elegir la fuente…": "Choose the source…", "Estrenos": "New episodes", "Fuente": "Source", "Guardada": "Saved", "Guardada en Mi lista": "Saved to My list", "Inicio y Para ti": "Home and For You", "La elegimos por tu idioma, la calidad y el tamaño": "Picked for your language, quality and size", "Lleva %lld %": "%lld % done", "Los siguientes %@": "The next %@", "Mantén presionado para elegir en qué lista": "Touch and hold to choose which list", "Mazo de cartas": "Card deck", "Mini pósters": "Mini posters", "Primer episodio": "First episode", "Quitada de Mi lista": "Removed from My list", "Reintentar": "Retry", "Tus listas de Trakt…": "Your Trakt lists…", "Ver en Descargas": "See in Downloads", "Ver sin internet": "Watch offline", "Un estreno ya está para ver": "A new episode is ready to watch", "Ya está para ver": "Ready to watch", "Al instante": "Instant", "Cambiar": "Change", "Avisos": "Notifications", "Estudio": "Studio", "Cadena": "Network", "Disponible": "Available", "Estreno": "Release", "menos": "less", "más": "more",
    "Empieza en un momento…": "Starting in a moment…", "Ver ya": "Watch now", "Otro": "Another",
    "Cambia el orden o lo que ocultas.": "Change the sort or what you hide.", "Conecta Trakt": "Connect Trakt","Nada con estos filtros": "Nothing with these filters", "Nada con «%@». Prueba con otro nombre.": "Nothing for “%@”. Try another name.", "Nada de ese tipo": "Nothing of that type", "Nada en los próximos 14 días": "Nothing in the next 14 days", "Nada por aquí por ahora": "Nothing here yet", "No encontré una con eso": "I couldn't find one like that", "No sale nada de las series que sigues.": "Nothing coming from the shows you follow.", "Películas %@": "Movies %@", "Prueba con otro filtro o más tiempo.": "Try another filter or more time.", "Prueba con «Todo».": "Try “All”.", "Series %@": "Shows %@", "Sin resultados": "No results", "Todavía nada": "Nothing yet",
    "Bloquear": "Lock", "Desbloquear": "Unlock", "Pantalla bloqueada": "Screen locked", "Toca para desbloquear": "Tap to unlock",
    "Español latino": "Latin American Spanish", "Arrastra el video para subirlo o bajarlo": "Drag the video to move it up or down",
    "Ahorro": "Saver", "Equilibrado": "Balanced", "Rendimiento": "Performance",
    "Esperando Wi‑Fi": "Waiting for Wi‑Fi", "Esperando conexión": "Waiting for connection", "En espera": "On hold",
    "termina a la %@": "ends at %@", "Buscando subtítulos…": "Searching subtitles…", "Se guardan con la descarga: también los ves sin conexión.": "They are saved with the download: you can watch them offline too.", "No encontré subtítulos para este video (o no hay conexión).": "I couldn't find subtitles for this video (or there's no connection).", "Subtítulos guardados con la descarga.": "Subtitles saved with the download.", "No pude bajar ese subtítulo: prueba otro.": "I couldn't download that subtitle: try another one.",
    "Cargando": "Charging", "Sustos": "Scares", "Avisarme": "Warn me", "Silencio": "Mute", "Arriba": "Up", "Abajo": "Down", "Izquierda": "Left", "Derecha": "Right", "Mantener": "Hold",
    "%@ de batería": "%@ of battery", "%@ GB libres": "%@ GB free",
    "%lld por delante · %lld fuertes": "%lld ahead · %lld big", "%lld por delante · 1 fuerte": "%lld ahead · 1 big", "%lld sustos por delante": "%lld scares ahead", "Con datos móviles te avisamos antes de usar fuentes de más de %lld GB.": "On cellular we ask before using sources over %lld GB.", "De lo más popular": "Among the most popular", "Dejan de salir tu watchlist, tus listas y lo que sigues; lo que veas ya no se marca en Trakt.": "Your watchlist, lists and shows stop appearing; what you watch is no longer marked on Trakt.", "Desconectar": "Disconnect", "En tendencia y para ti": "Trending and for you", "Guardamos una sola copia: si la cambias, se borra la que tienes y se baja la nueva.": "We keep a single copy: if you replace it, yours is deleted and the new one downloads.", "Nada de ese tipo: prueba con «Todo».": "Nothing of that kind: try “All”.", "Reintentar la descarga": "Retry the download", "Se borra lo que tenías pendiente de subir y tus búsquedas recientes. Tus descargas se quedan en el iPhone.": "Pending uploads and your recent searches are deleted. Your downloads stay on the iPhone.", "Seguir la descarga": "Resume the download", "para el siguiente · fuerte": "to the next one · big", "para el siguiente · leve": "to the next one · mild", "síguela en mi iPhone": "continue it on my iPhone", "¿Desconectar Trakt?": "Disconnect Trakt?",
    "Desde el principio": "From the beginning", "No encontré subtítulos (o no hay conexión). Vuelve a intentar.": "I couldn't find subtitles (or there's no connection). Try again.", "No pude abrir ese archivo.": "I couldn't open that file.", "Tráiler": "Trailer",
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
    "Buscaste hace poco": "Recent searches", "Lo más popular de cada uno": "The most popular of each",
    "Con géneros elegidos, el ánimo no cuenta.": "With genres picked, the mood doesn't count.", "Géneros": "Genres", "Incluir lo que ya vi": "Include what I've watched",
    "Ir a una sección": "Go to a section", "Mejor calificadas en IMDb": "Top rated on IMDb", "Mejor calificadas en Trakt": "Top rated on Trakt",
    "Menos opciones": "Fewer options", "Más opciones": "More options", "Qué": "What", "Toca otra vez para confirmar": "Tap again to confirm",
    "Todo lo que estás viendo": "Everything you're watching", "Todo lo que estás viendo · %@": "Everything you're watching · %@", "¿Ver en la TV?": "Watch on the TV?",
    "Abre el control de tu Orbital.": "Opens your Orbital's remote.", "Abrir el control de Orbital": "Open the Orbital remote", "Control de Orbital": "Orbital remote",
    "Episodios de estas semanas y películas recién llegadas": "This week's episodes and newly arrived movies", "Estudios": "Studios",
    "Lo más visto": "Most watched", "Lo más visto de cada uno": "The most watched from each", "Nuevo en tus plataformas": "New on your platforms",
    "Año: más nuevas": "Year: newest", "Año: más viejas": "Year: oldest", "A–Z": "A–Z", "Como viene la lista": "As the list comes", "De %@": "From %@",
    "Género": "Genre","Listas de Trakt": "Trakt lists", "Lo que Trakt relaciona con lo último que viste": "What Trakt relates to what you watched last",
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
    "Alexa, pídele a mi consola que…": "Alexa, ask my console to…", "Bajar volumen": "Volume down", "Subir volumen": "Volume up", "Quitar silencio": "Unmute",
    "Descargar funciona aunque estés fuera de casa.": "Downloading works even away from home.",
    "Estira el control hacia arriba y toca «Dile a Orbital». Se detiene solo cuando terminas.": "Pull the remote up and tap “Tell Orbital”. It stops on its own when you finish.",
    "Las frases de abajo funcionan igual en los tres.": "The phrases below work the same in all three.", "Oye Siri, habla con Orbital": "Hey Siri, talk to Orbital",
    "Sin «pídele a mi consola», Alexa intenta hacerlo ella sola.": "Without “ask my console”, Alexa tries to do it herself.",
    "Y cuando pregunte, la orden. Directo: «Oye Siri, pausa Orbital» o «Oye Siri, prende Orbital».": "Then, when asked, the command. Direct: “Hey Siri, pause Orbital” or “Hey Siri, turn on Orbital”.",
    "Saltar resumen": "Skip recap",
    "Lo mejor disponible": "Best available",
    "Sale pronto": "Coming up", "Ver todo": "See all",
    "La que tienes": "Current", "Sigue en tu Orbital": "Now on your Orbital",
    "Tamaño": "Size", "Tarda en empezar": "Slow to start", "Ventana": "Window", "Idiomas": "Languages", "Otros": "Others",
    "Otras": "Others", "desde el principio": "from the start", "desde %@": "from %@", "Deshacer": "Undo",
    "Creación": "Created by", "Dónde verlo": "Where to watch","Filmografía": "Filmography",
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
    "Ver la serie": "View series", "Ver en la TV": "Watch on TV",
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
    "Lo que sale de las series que sigues": "What is coming out from the shows you follow", "Agregada a tu lista.": "Added to your list.", "Conecta Trakt o tu Orbital": "Connect Trakt or your Orbital",
    "De todos los tiempos": "All time","Lo más visto esta semana": "Most watched this week",
    "Lo que dejaste pendiente": "What you left for later", "Lo tuyo": "Yours", "N.º %lld en %@": "No. %lld on %@", "N.º %lld": "No. %lld", "Número %lld en %@": "Number %lld on %@", "Por lo que has visto": "Based on what you've watched",
    "Recomendada por Trakt": "Recommended by Trakt",
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
    "Agregar complemento": "Add add-on", "Ajustes": "Settings", "Audio y subtítulos": "Audio and subtitles",
    "Aparece un código para escribir en la página de Trakt que se indica. La sesión es solo de este iPhone (tu Orbital tiene la suya): se avisa de lo que ves, sigues donde ibas en la TV y salen tu watchlist y tus listas.":
        "A code appears to enter on the Trakt page shown. The session belongs to this iPhone only (your Orbital has its own): what you watch is reported, you pick up where you left off on the TV, and your watchlist and lists show up.",
    "Aquí aparece lo que vas viendo, en el iPhone y en Orbital.": "What you're watching shows up here, on iPhone and on Orbital.",
    "Añadir a Mi lista": "Add to My List", "En Mi lista": "In My List", "Ver ficha": "View details", "Conecta Trakt (tu watchlist y tus listas) o agrega una clave de TMDB (lo popular en Netflix, Disney+ y HBO Max) en Ajustes.": "Connect Trakt (your watchlist and lists) or add a TMDB key (what is popular on Netflix, Disney+ and HBO Max) in Settings.", "Orbital · faltan %lld": "Orbital · %lld left", "Orbital · descargando": "Orbital · downloading", "Poniéndolo en la TV.": "Playing it on the TV.", "Desde la TV": "From the TV", "Descartar": "Dismiss", "Desde la TV: %@": "From the TV: %@", "Descargando %@ (desde la TV)": "Downloading %@ (from the TV)", "No encontré una fuente para descargar %@ (desde la TV)": "I did not find a source to download %@ (from the TV)", "No hay espacio para descargar %@ (desde la TV)": "Not enough space to download %@ (from the TV)", "No pude descargar %@ (desde la TV)": "I could not download %@ (from the TV)",
    "Dirección (orbital.tudominio.com)": "Address (orbital.yourdomain.com)", "Token guardado": "Token saved", "Token (el mismo de Alexa)": "Token (the same as Alexa's)",
    "Guardar token": "Save token", "Probar conexión": "Test connection", "Conectada": "Connected", "Tu Orbital (la TV)": "Your Orbital (the TV)",
    "Con tu Orbital conectada, «Ver en la TV» pone en la consola lo que ves aquí, donde ibas, y las claves de Para ti salen de ella. Trakt se conecta aparte en cada uno.": "With your Orbital connected, “Watch on TV” plays what you're watching here on the console, right where you were, and your For You keys come from it. Trakt is connected separately on each one.",
    "Conecta Trakt en este iPhone (Ajustes › Trakt).": "Connect Trakt on this iPhone (Settings › Trakt).",
    "Solo si usas tu propia aplicación (developer.trakt.tv). Vacío: la de Orbital.": "Only if you use your own app (developer.trakt.tv). Empty: Orbital's.",
    "Conectada a %@": "Connected to %@", "En la TV: Ajustes › Cuentas › iPhone": "On the TV: Settings › Accounts › iPhone",
    "Aparece un código. Apúntale con la cámara del iPhone y toca «Abrir en Orbital»: queda conectada, sin escribir nada.": "A code appears. Point the iPhone camera at it and tap “Open in Orbital”: it connects, no typing.",
    "Cambiar a mano": "Change manually", "Conectar a mano": "Connect manually",
    "Conecta tu Orbital (arriba) y Trakt queda listo. Si usas tu propia aplicación de Trakt, pega su Client ID en Avanzado.": "Connect your Orbital (above) and Trakt is ready. If you use your own Trakt app, paste its Client ID in Advanced.",
    "Conectado con tu Orbital.": "Connected to your Orbital.", "Conectado con tu Orbital: %@ ya están aquí.": "Connected to your Orbital: %@ are here now.",
    "Traje de tu Orbital: %@. No hay que escribirlo aquí.": "Brought from your Orbital: %@. No need to type it here.", "Velocidad": "Speed", "Tamaño de subtítulos": "Subtitle size", "Chico": "Small", "Mediano": "Medium", "Grande": "Large", "Fuentes": "Sources", "Descargado": "Downloaded", "Ya está descargado. Lo encuentras en Descargas.": "Already downloaded. You'll find it in Downloads.", "Película": "Movie", "Serie": "Series",
    "Crea una aplicación en developer.trakt.tv y pega aquí su Client ID (las nuevas ya no dan secreto).": "Create an app at developer.trakt.tv and paste its Client ID here (new ones no longer have a secret).",
    "Client ID de tu aplicación de Trakt": "Your Trakt app's Client ID", "Imagen dentro de imagen": "Picture in Picture",
"Nada descargado": "Nothing downloaded", "Avance": "Progress",
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
    "Descargar solo con Wi‑Fi": "Download only on Wi‑Fi", "Desconectar Trakt": "Disconnect Trakt", "Descubrir": "Discover",
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
    # Siri: la orden y el título en la misma frase («pausa en Orbital», «pon The Office en Orbital»).
    "Orden rápida": "Quick command", "Pausa, volumen, siguiente episodio y lo de todos los días, en una sola frase.": "Pause, volume, next episode and the everyday things, in a single phrase.",
    "Poner en la TV": "Play on the TV", "Pone en tu Orbital una película o una serie, donde ibas.": "Plays a movie or a show on your Orbital, where you left off.",
    "Título": "Title", "¿Qué pongo en la TV?": "What should I play on the TV?",
    "Pon pausa": "Pause it", "Pausa la tele": "Pause the TV", "Espera": "Wait", "Reanuda": "Resume", "Quita la pausa": "Unpause",
    "Dale play": "Hit play", "Continúa": "Continue", "Siguiente capítulo": "Next chapter",
    "Pon el siguiente episodio": "Play the next episode", "Episodio anterior": "Previous episode", "Capítulo anterior": "Previous chapter",
    "Salta la intro": "Skip the intro", "Sáltate la intro": "Skip the intro", "Brinca la intro": "Skip the intro",
    "Empieza de nuevo": "Start over", "Vuelve a empezar": "Start again",
    "Adelanta": "Skip ahead", "Adelántale": "Skip ahead", "Adelanta treinta segundos": "Skip ahead thirty seconds",
    "Regresa": "Go back", "Regrésale": "Go back", "Regresa treinta segundos": "Go back thirty seconds",
    "Sube el volumen": "Turn up the volume", "Súbele": "Louder", "Más fuerte": "Louder", "Baja el volumen": "Turn down the volume",
    "Bájale": "Quieter", "Más bajo": "Quieter", "Silencia": "Mute", "Quita el sonido": "Turn off the sound",
    "Quita el silencio": "Unmute", "Regresa el sonido": "Bring the sound back", "Pon subtítulos": "Turn on subtitles",
    "Activa los subtítulos": "Turn on the subtitles", "Quita los subtítulos": "Turn off subtitles", "Apaga los subtítulos": "Turn off the subtitles",
    "Cuánto le queda": "How long is left", "Sal del video": "Exit the video", "Quita el video": "Stop the video",
    "Detén el video": "Stop the video", "Sigue viendo": "Continue watching", "Pon lo que estaba viendo": "Play what I was watching",
    "Pon la tele": "Put on live TV", "Pon la tele en vivo": "Put on live TV", "Siguiente canal": "Next channel", "Cambia de canal": "Change the channel",
    "Qué sale hoy": "What's out today", "Qué estrenos hay": "What's new",
    "Qué me recomiendas": "What do you recommend", "Recomiéndame algo": "Recommend me something", "Qué está abierto": "What's open",
    "Qué estoy viendo": "What am I watching", "Qué estoy jugando": "What am I playing", "Cierra el juego": "Close the game",
    "Sal del juego": "Exit the game", "Ve a inicio": "Go home", "Ve al inicio": "Go to the start", "Toma una captura": "Take a screenshot",
    "Captura la pantalla": "Capture the screen",
    "Prender la consola": "Turn on the console", "Prende la tele en la entrada de tu Orbital y muestra la consola.": "Turns on the TV on your Orbital's input and shows the console.",
    "Cómo pedirlo": "How to ask", "No hace falta decirlo exacto.": "You don't need to say it exactly.",
    "Actualiza tu Orbital para usar el control completo.": "Update your Orbital to use the full remote.", "Atrás": "Back", "Control de tu Orbital": "Orbital remote", "Nada en la TV ahora": "Nothing on the TV right now",
    "Desliza para moverte; toca para elegir": "Swipe to move; tap to select", "Desliza · toca para elegir": "Swipe · tap to select", "Escribir en la TV": "Type on the TV",
    "Estira hacia arriba para el control completo": "Pull up for the full remote", "Menú": "Menu", "Pad de la TV": "TV touchpad", "Tu Orbital": "Your Orbital",
    "Abre la ficha": "Opens the details", "Elegir": "Choose", "Especiales": "Specials", "Esperando…": "Waiting…", "Fuentes de Real-Debrid": "Real-Debrid sources", "Guardar clave de TMDB": "Save TMDB key", "Guion": "Written by",
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
"No se pudo descargar": "Download failed",
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
    "Hacen falta %@ MB y hay %@ MB libres.": "%@ MB needed and %@ MB free.",
    "No pude guardar el archivo: %@": "I couldn't save the file: %@",
    "Ocupan %@": "%@ used",
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
    "Siguiente episodio": "Next episode", "Sin conexión: se ve lo último que guardé.": "Offline: showing what I saved last.",
    "Sin subtítulos": "No subtitles", "Solo con Wi‑Fi": "Wi‑Fi only", "Solo subtítulos forzados": "Forced subtitles only",
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
    # Los avisos (un solo tipo, con su dato y su salida).
    "Actívalos en Ajustes del iPhone": "Turn them on in iPhone Settings", "Bajando en el iPhone": "Downloading on the iPhone",
    "Conectado con tu Orbital": "Connected to your Orbital", "En el iPhone, para ver sin conexión": "On the iPhone, to watch offline",
    "En tu Orbital": "On your Orbital", "Infuse no pudo con esta versión": "Infuse couldn't play this version",
    "Intenta de nuevo en un momento.": "Try again in a moment.", "La TV te mandó «%@»": "Your TV sent “%@”",
    "La misma versión que estás viendo": "The same version you're watching", "Libera espacio en Descargas": "Free up space in Downloads",
    "Lo mandó la TV: intenta desde su ficha": "The TV sent it: try from its page", "Los avisos están apagados": "Notifications are off",
    "Los estrenos suelen llegar unas horas después": "New releases usually show up a few hours later", "No cabe en el iPhone": "It doesn't fit on the iPhone",
    "No encontré ese archivo en tu OneDrive": "I couldn't find that file in your OneDrive", "No hay una versión para bajar": "There's no version to download",
    "No pude abrir Infuse": "I couldn't open Infuse", "No pude abrir ese archivo": "I couldn't open that file", "No pude abrir «%@»": "I couldn't open “%@”",
    "No pude bajar ese subtítulo": "I couldn't download that subtitle", "No pude bajar «%@»": "I couldn't download “%@”",
"No pude pedir el archivo a OneDrive": "I couldn't get the file from OneDrive",
    "No pude preguntar por fuentes": "I couldn't look for sources", "No pude preparar la descarga": "I couldn't prepare the download",
    "No pude traer los episodios de Los Simpson": "I couldn't get The Simpsons episodes", "Prueba otra fuente o ábrela aquí": "Try another source or open it here",
    "Prueba otro": "Try another one", "Real-Debrid aún no lo tiene": "Real-Debrid doesn't have it yet",
    "Real-Debrid no tiene un archivo de este título": "Real-Debrid has no file for this title", "Revisa tu internet": "Check your internet",
    "Sin ella no llegan tus recomendaciones": "Without it, your recommendations stop", "Sin internet": "No internet",
    "Subtítulos guardados con la descarga": "Subtitles saved with the download", "Tu Orbital no contestó.": "Your Orbital didn't respond.",
    "Ya está descargada": "Already downloaded", "¿Está instalado?": "Is it installed?", "«%@» no cabe en el iPhone": "“%@” doesn't fit on the iPhone",
    "Abrir Ajustes": "Open Settings", "Ver aquí": "Watch here", "Descargas": "Downloads",
    "A la consola le queda %lld %%": "The console has %lld %% left", "Conéctala antes de que se apague": "Plug it in before it turns off",
    "Se detuvo «%@»": "“%@” stopped", "Iba en %lld %%. Puedes reintentar o elegir otra fuente.": "It was at %lld %%. You can retry or pick another source.",
    "No pudo empezar. Puedes reintentar o elegir otra fuente.": "It couldn't start. You can retry or pick another source.",
    "Descargando «%@»": "Downloading “%@”", "Empezando…": "Starting…",
    # «Elegir versión» (las mismas palabras que la TV).
    "Buscando versión…": "Finding a version…", "No trae %@": "No %@ here", "El nombre del archivo dice el idioma:": "The file name says the language:",
    "Elegir versión": "Choose version", "Elegir versión…": "Choose version…", "Es el original": "It's the original",
    "Español (cualquiera)": "Spanish (any)", "Español de España": "Castilian Spanish", "Esta versión no trae %@": "This version doesn't have %@",
    "Hay pistas, pero no seguras (muchas banderas o solo «español»).": "There are hints, but not sure ones (many flags or just “Spanish”).",
    "Lo dice el nombre": "The name says so", "Lo dice el sitio": "The site says so",
    "Nada en el nombre lo dice: es el idioma original del título.": "Nothing in the name says it: it's the title's original language.",
    "Nada lo dice y no se sabe el idioma original: suponemos inglés.": "Nothing says it and the original language is unknown: we assume English.",
    "No dice idioma": "No language info", "No dice si latino o castellano": "Doesn't say Latin American or Castilian",
    "Otras %lld en %@ %@": "%lld more in %@ %@", "Otros idiomas · ": "Other languages · ", "Por idioma y calidad · toca una": "By language and quality · tap one",
    "Sus pistas: %@": "Its tracks: %@", "Tal vez": "Maybe", "También trae: ": "Also has: ", "Viene de %@, que solo sube %@.": "From %@, which only uploads %@.",
    "Ya la viste: son las pistas de audio del archivo.": "You've watched it: these are the file's audio tracks.", "¿Otro título?": "Another title?",
    "¿Otro título? El nombre dice otro año: puede ser otra película.": "Another title? The name says another year: it may be a different movie.",
    "1 oculta: grabada en el cine o tráiler": "1 hidden: a theater recording or trailer",
    "Arrastra para mover": "Drag to move", "Llena la pantalla deformando la imagen": "Fills the screen by stretching the picture", "Ajuste de aspecto": "Aspect Fit", "Recortar": "Crop", "Estirar": "Stretch", "Mantén presionado para apagar o prender los subtítulos": "Touch and hold to turn subtitles on or off", " · otra versión": " · another version", "Audio": "Audio", "Arrastra para mover el video": "Drag to move the video",
    " y ": " and ", "Tu idioma": "Your language", "Original": "Original", "Comprobado": "Checked", "Versión": "Version",
    # «Todas las fuentes» (AllSourcesList) y la velocidad honesta de «Elegir versión».
    "Filtrar": "Filter", "Filtrar · %lld": "Filter · %lld", "Más chicas primero": "Smallest first", "Más semillas primero": "Most seeders first",
    "Solo las que ya están en Real-Debrid": "Only those already on Real-Debrid", "Grabaciones de cine y tráileres": "Theater recordings and trailers",
    "Real-Debrid aún no la tiene: puede tardar en abrir": "Real-Debrid doesn't have it yet: it may take a while to open",
    "Ya está en Real-Debrid": "Already on Real-Debrid", "Quitar filtros": "Clear filters", "+%lld más": "+%lld more", "+%lld más en %@": "+%lld more in %@",
    "%lld ocultas: grabadas en el cine o tráileres": "%lld hidden: theater recordings or trailers",
    "Toca para ver los detalles": "Tap to see the details", "Toca para cerrar los detalles": "Tap to close the details", "Copiar nombre": "Copy name",
    "Grabada en el cine": "Theater recording", "La que ves": "Playing now", "comprobado": "checked", "lo dice el nombre": "the name says so",
    "lo dice el sitio": "the site says so", "Todas, por calidad · toca una": "All, by quality · tap one",
    # Para ti › Listas: «Temporadas» y «Lo mejor del género» (los nombres y frases vienen de Tmdb.seasons / Tmdb.genres).
    "Temporadas": "Seasons", "La de ahora, primero": "The current one first", "Lo mejor del género": "Best by genre",
    "Las mejor calificadas del año": "The year's top rated", "Las más populares de %@": "The most popular of %@",
    "Lo mejor de %@ en %@": "The best of %@ in %@", "Pocas de %@: las mejor calificadas de %@": "Few from %@: the top rated of %@",
    "Pocas de %@: lo más visto en %@": "Few from %@: the most watched in %@",
    "Halloween": "Halloween", "Día de Muertos": "Day of the Dead", "Navidad": "Christmas", "San Valentín": "Valentine's Day", "Verano": "Summer",
    "Sustos, brujas y calabazas": "Scares, witches and pumpkins", "Para recordar a los que se fueron": "To remember those who are gone",
    "Para ver en familia": "To watch with the family", "Para ver en pareja": "To watch as a couple", "Sol, playa y vacaciones": "Sun, beach and vacation",
    "Acción": "Action", "Aventura": "Adventure", "Animación": "Animation", "Comedia": "Comedy", "Crimen": "Crime", "Documental": "Documentary",
    "Drama": "Drama", "Familia": "Family", "Fantasía": "Fantasy", "Terror": "Horror", "Misterio": "Mystery", "Romance": "Romance",
    "Ciencia ficción": "Science fiction", "Suspenso": "Thriller",
    # Desacoplar Stremio, corte A: lo tuyo vive en el teléfono y viaja por Trakt; Stremio es un respaldo opcional.
    "Cerrar sesión de Stremio": "Sign out of Stremio", "Stremio · respaldo": "Stremio · backup", "Sin cuentas conectadas": "No accounts connected",
    "Conecta tu cuenta de Stremio como respaldo: lo que veas también se guarda ahí, como copia.": "Connect your Stremio account as a backup: what you watch is also saved there, as a copy.",
    "Lo que ves también se guarda ahí, como copia.": "What you watch is also saved there, as a copy.",
    "Lo tuyo se queda en el iPhone y en Trakt; Stremio deja de recibir la copia.": "Your stuff stays on the iPhone and on Trakt; Stremio stops getting the copy.",
    "No pude cambiar Mi lista": "I couldn't change My List",
    # Corte C: la guía de la primera vez, Ajustes › Cuentas y Complementos.
    "Abre la cámara del iPhone y apunta al código de la TV": "Open the iPhone camera and point it at the code on the TV",
    "Abrir Trakt": "Open Trakt", "Agregar": "Add", "Cambiar clave": "Change key",
    "Con ella Orbital puede pedir videos a tu cuenta.": "With it, Orbital can request videos from your account.",
    "Conectado como %@": "Connected as %@", "Conectar Stremio": "Connect Stremio",
    "Conéctala para mandarle lo que ves y usar el iPhone de control.": "Connect it to send what you watch and use the iPhone as a remote.",
    "Conéctalo para traer tu historial y que siga al día mientras probamos. Es opcional.": "Connect it to bring your history and keep it up to date while we test. It's optional.",
    "Copia el texto largo que aparece": "Copy the long text that appears", "Crear cuenta en real-debrid.com": "Create an account at real-debrid.com",
    "Cuenta gratuita": "Free account", "Cuánto cuesta": "How much it costs", "Cómo funciona Orbital": "How Orbital works",
    "Cómo funciona": "How it works", "De aquí salen los videos.": "This is where the videos come from.",
    "De dónde salen las versiones": "Where the versions come from",
    "Desde unos 3 € por 15 días. El precio lo confirma su web.": "From about €3 for 15 days. Their website confirms the price.",
    "Empezar a ver": "Start watching", "En la TV: Ajustes › iPhone › Conectar": "On the TV: Settings › iPhone › Connect",
    "Entra a trakt.tv/activate y escribe este código.": "Go to trakt.tv/activate and type this code.",
    "Es un servicio de pago que guarda los videos en sus servidores y te los entrega al instante, sin descargar nada de otras personas.": "It's a paid service that keeps videos on its servers and delivers them instantly, without downloading anything from other people.",
    "Esperando a que lo apruebes…": "Waiting for you to approve it…",
    "Esta copia de la app no trae la aplicación de Trakt: conéctalo después en Ajustes.": "This copy of the app doesn't include the Trakt app: connect it later in Settings.",
    "Falta Real-Debrid": "Real-Debrid missing", "Fuentes y listas": "Sources and lists",
    "Guarda dónde te quedaste, lo que viste y Mi lista, para todos tus aparatos.": "Keeps where you left off, what you watched and My List, for all your devices.",
    "Guarda dónde te quedaste, lo que ya viste y tu lista, para que la TV, el iPad y la Mac sepan lo mismo. Es gratis.": "Keeps where you left off, what you've watched and your list, so the TV, iPad and Mac know the same. It's free.",
    "Hacerla Premium": "Make it Premium", "La dirección completa del complemento.": "The add-on's full address.",
    "Los complementos son buscadores: encuentran versiones de cada película y Real-Debrid te las entrega.": "Add-ons are search engines: they find versions of each movie and Real-Debrid delivers them.",
    "Manda lo que ves a la pantalla grande y usa el iPhone de control.": "Send what you watch to the big screen and use the iPhone as a remote.",
    "Marcar como no visto": "Mark as unwatched", "No conectada": "Not connected", "No conectado": "Not connected",
    "No se renueva solo: Orbital te avisa antes de que se te acabe.": "It doesn't renew itself: Orbital warns you before it runs out.",
    "Orbital junta tres piezas. Te ayudamos a conectar cada una.": "Orbital puts three pieces together. We'll help you connect each one.",
    "Paso %@ de %@": "Step %@ of %@", "Pega tu clave": "Paste your key", "Pegar dirección": "Paste address",
    "Puedes cambiarlos cuando quieras en Ajustes › Complementos.": "You can change them anytime in Settings › Add-ons.",
    "Recomendados": "Recommended", "Sacar tu clave en real-debrid.com/apitoken": "Get your key at real-debrid.com/apitoken",
    "Se paga por adelantado, por días.": "You pay in advance, by days.",
    "Se preguntan en este orden. Toca «Ordenar» y arrastra para cambiarlo.": "They're asked in this order. Tap “Reorder” and drag to change it.",
    "Sin complementos: agrega uno para tener fuentes.": "No add-ons: add one to get sources.", "TMDB, país": "TMDB, country",
    "Te avisamos 14 días antes, 3 días antes y el día que vence. No se renueva solo.": "We'll remind you 14 days before, 3 days before and the day it expires. It doesn't renew itself.",
    "Te quedan %@ días · vence el %@": "%@ days left · expires on %@", "Te quedan %@ días": "%@ days left",
    "Toca el aviso de Orbital que aparece": "Tap the Orbital prompt that appears", "Todo listo": "All set",
    "Trajimos %@ vistos y %@ en tu lista.": "We brought %@ watched and %@ in your list.", "Trakt · principal": "Trakt · main",
    "Trayendo lo tuyo…": "Bringing your stuff…", "Tu Orbital en la TV": "Your Orbital on the TV", "Tu Orbital está conectada": "Your Orbital is connected",
    "Tu avance en la nube, en todos tus aparatos.": "Your progress in the cloud, on all your devices.",
    "Tu clave de Real-Debrid": "Your Real-Debrid key", "Tu cuenta es gratuita: necesitas Premium para ver.": "Your account is free: you need Premium to watch.",
    "Tus películas y series en tu bolsillo.": "Your movies and shows in your pocket.",
    "Usa tu Real-Debrid": "Uses your Real-Debrid", "Vence hoy": "Expires today", "Venció hace %@ días": "Expired %@ days ago", "Venció": "Expired",
    "Volver a importar": "Import again", "Vuelve aquí y pégalo": "Come back here and paste it", "Ya dejamos listos estos": "We set these up for you",
    "Ya la conecté": "I connected it", "Ya puedes ver lo que quieras.": "You can watch whatever you want.", "Ya tengo cuenta": "I already have an account",
    "¿Usas Stremio?": "Do you use Stremio?", "%@ sustos por delante": "%@ scares ahead", "Configurar": "Set up",
}
# Textos que no se traducen: nombres propios, ids y formatos.
IGNORE = {"The Simpsons", "Content-Type", "L · R", "L1 · R1", "L2 · R2", "LB · RB", "LT · RT", "ZL · ZR", "Start · Select", "Stick C", "IMDb %.1f", "Trakt %.1f", "T\\($0) · E\\($1)", "AVPlayer", "AirPlay", "Client Secret", "AetherEngine", "BluRay", "WEB-DL", "Orbital", "Trakt", "English", "Español", "1080p", "720p", "4K", "TMDB", "Infuse", "Stremio", "Real-Debrid",
          "REMUX", "Atmos", "Dolby Vision", "Netflix", "Disney+", "HBO Max",
          "Icons/", "Glyphs/donut", "Avatars/", "Awards/", "Collections/", "AppIconPreview/day", "AppIconPreview/night", "AppIconNight"}  # el nombre de un ícono en el catálogo
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
    files = glob.glob(str(ROOT / "ios/App/Sources/**/*.swift"), recursive=True) + glob.glob(str(ROOT / "ios/App/Widgets/*.swift")) + glob.glob(str(ROOT / "ios/OrbitalCore/Sources/OrbitalModels/*.swift")) + [str(ROOT / f"ios/OrbitalCore/Sources/OrbitalCore/{n}.swift") for n in ("Downloads", "OrbitalRemote", "Trakt", "Watch", "StremioAPI", "Cinemeta")] + glob.glob(str(ROOT / "ios/OrbitalCore/Sources/OrbitalAddons/*.swift"))  # sus errores (y los recomendados) llegan a la pantalla
    for f in files:
        f = Path(f).as_posix()  # en Windows glob da «\»: sin esto el modo demo y Platform/ se colaban
        # El modo demo (solo Debug) no se traduce; de Design/ solo se saltan los tokens y el banco de pruebas (las piezas sí llevan texto).
        # El modo demostración (Demo.swift y sus partes Demo*.swift, como DemoHTTPClient): datos de mentira, no textos de pantalla.
        if "/Platform/" in f or "/Support/Demo" in f or f.endswith(("/Support/Perf.swift", "Previews.swift", "/Design/Tokens.swift", "/Design/MosaicBench.swift", "/Design/ModelObserver.swift")):
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


UI_CALL = r'(Text|Button|CommandMenu|Label|Section|Toggle|Picker|TextField|SecureField|Tab|navigationTitle|secondary|DSChip|DSBadge|DSNotice|DSSectionHead|DSIconButton|LabeledContent|DisclosureGroup)\(\s*(text:\s*|title:\s*)?"{}"'


def ui_word(word: str) -> bool:
    """¿La palabra aparece como el texto de un control en alguna pantalla?"""
    pattern = re.compile(UI_CALL.format(re.escape(word)))
    files = glob.glob(str(ROOT / "ios/App/Sources/Screens/*.swift")) + glob.glob(str(ROOT / "ios/App/Sources/Design/Components.swift")) + [str(ROOT / f"ios/App/Sources/Design/{n}.swift") for n in ("Projection", "Shelf", "Mosaic")]
    return any(pattern.search(Path(f).read_text(encoding="utf-8")) for f in files)


# El aparato en los textos: la misma app corre en iPhone, iPad y Mac («Diseñada para iPad»). Un texto que dice «iPhone»
# lleva una variación por aparato del catálogo (Apple elige la del aparato) y en el iPhone se lee igual que siempre.
# No se tocan los que nombran algo literal: el menú «Ajustes › iPhone» de la TV y la frase de voz «… en mi iPhone».
DEVICE_LITERAL = ("› iPhone", "mi iPhone")
MAC_ES = [("del iPhone", "de la Mac"), ("al iPhone", "a la Mac"), ("este iPhone", "esta Mac"), ("El iPhone", "La Mac"),
          ("el iPhone", "la Mac"), ("iPhone", "Mac")]


def unit(value: str) -> dict:
    return {"stringUnit": {"state": "translated", "value": value}}


def by_device(text: str, ipad: str, mac: str) -> dict:
    return {"variations": {"device": {"iphone": unit(text), "ipad": unit(ipad), "mac": unit(mac), "other": unit(text)}}}


def mac_es(text: str) -> str:
    for old, new in MAC_ES:
        text = text.replace(old, new)
    return text


# Textos que en la Mac dicen otra cosa: la Mac no se conecta con tu Orbital (`Services.allowsOrbital`). (español, inglés)
MAC_ONLY = {
    "Conecta Trakt o tu Orbital": ("Conecta Trakt", "Connect Trakt"),
    "Conecta Trakt (en tu Orbital o en Ajustes) para ver tu año.": ("Conecta Trakt en Ajustes para ver tu año.", "Connect Trakt in Settings to see your year."),
}


# En la Mac no se toca: se hace clic (29 oct 2026). Lo mismo para «Mantén presionado». En el iPad se toca igual que en el iPhone.
MAC_TOUCH_ES = [(r"Mantén presionada", "Mantén el clic en"), (r"Mantén presionado", "Mantén el clic"),
                (r"\bToca (para|y|otra vez)\b", r"Haz clic \1"), (r"\btoca (para|y|otra vez)\b", r"haz clic \1"),
                (r"\bToca ", "Haz clic en "), (r"\btoca ", "haz clic en ")]
MAC_TOUCH_EN = [(r"Touch and hold", "Click and hold"), (r"Press and hold", "Click and hold"), (r"\bTap\b", "Click"), (r"\btap\b", "click")]


def mac_touch(text: str, rules: list) -> str:
    for old, new in rules:
        text = re.sub(old, new, text)
    return text


def varies_by_device(key: str) -> bool:
    iphone = "iPhone" in key and not any(literal in key for literal in DEVICE_LITERAL)
    return iphone or mac_touch(key, MAC_TOUCH_ES) != key


def build() -> dict:
    strings = {}
    for key, english in sorted(TRANSLATIONS.items()):
        if key in MAC_ONLY:
            mac, mac_en = MAC_ONLY[key]
            localizations = {"es": by_device(key, key, mac), "en": by_device(english, english, mac_en)}
        elif varies_by_device(key):
            localizations = {"es": by_device(key, key.replace("iPhone", "iPad"), mac_touch(mac_es(key), MAC_TOUCH_ES)),
                             "en": by_device(english, english.replace("iPhone", "iPad"), mac_touch(english.replace("iPhone", "Mac"), MAC_TOUCH_EN))}
        else:
            localizations = {"en": unit(english)}
        strings[key] = {"extractionState": "manual", "localizations": localizations}
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
