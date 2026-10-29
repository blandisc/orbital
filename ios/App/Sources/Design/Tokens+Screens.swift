import SwiftUI
import OrbitalCore

/// Tokens de pantallas y piezas concretas (Inicio, Para ti, la ficha, Ajustes, el control remoto…). Los de base
/// (colores, espacios, radios, letra, movimiento, tamaños, imágenes) siguen en `Tokens.swift`.
extension DS {
    /// Las acciones de la ficha (Guardar, Descargar, Tráiler, Fuente): el alto del rectángulo y el grueso del anillo de avance. El anillo es el mismo en la fila de un episodio (`ring`).
    /// «Un Simpson al azar»: la ruleta de episodios (ancho de cada imagen, espacio, cuánto gira y cuánto se queda el elegido
    /// antes de empezar), la dona y el amarillo de Los Simpson.
    enum Simpsons {
        // Un cambio de canal (≈2.4 s): aparece con rebote (0.25 s), tres clics con estática y su número de canal (~0.35 s),
        // se queda y brilla, se sostiene en el canal elegido (0.7 s) y la imagen crece despacio desde la pantalla hasta
        // llenar el iPhone (1.1 s, arranque suave y aterrizaje largo), una pausa breve con la imagen llena y entra el video.
        static let reelLength = 3, warmWait: Double = 0.25
        /// Lo más que la tele sintoniza esperando las imágenes de los episodios (desde el Centro de control no estaban listas).
        static let imageWait: Double = 3
        /// Cuánto espera Inicio antes de preparar la ruleta (la ficha de ~650 KB no compite con el arranque).
        static let prefetchDelay: Double = 4
        static let appear: Double = 0.25, bounce: Double = 0.35, staticBurst: Double = 0.08, flip: Double = 0.1
        static let settle: Double = 0.15, flashOff: Double = 0.08, hold: Double = 0.7, zoom: Double = 1.1, handoff: Double = 0.05
        static let zoomRest: Double = 0.2   // la imagen ya llena, quieta un instante antes de que entre el reproductor
        /// Curva del crecimiento: sale lento, avanza y se posa sin frenazo (no «te la avienta»).
        static let zoomCurve = Animation.timingCurve(0.4, 0, 0.15, 1, duration: zoom)
        static let channels = [3, 7, 12]
        // La tele.
        static let screen: CGFloat = 220, screenAspect: CGFloat = 4 / 3, screenRadius: CGFloat = 28, screenFrame: CGFloat = 3
        static let tvRadius: CGFloat = 38, bezel: CGFloat = 18, tvGlow: CGFloat = 40
        static let knobSize: CGFloat = 24, knobMark: CGFloat = 3, knobTurn: Double = 45
        static let grilleLines = 4, grilleLine: CGFloat = 3, grilleGap: CGFloat = 4
        static let antennaWidth: CGFloat = 170, antennaHeight: CGFloat = 92, antennaLine: CGFloat = 3, antennaTip: CGFloat = 5
        static let antennaBase: CGFloat = 16, antennaWobble: Double = -4
        static let legSpan: CGFloat = 200, legWidth: CGFloat = 12, legHeight: CGFloat = 16
        static let appearScale: CGFloat = 0.82, tvBehind: CGFloat = 1.15, ghost: Double = 0.35, flash: Double = 0.35, osdGlow: CGFloat = 6
        static let staticLine: CGFloat = 3, captionHeight: CGFloat = 96, glow: CGFloat = 420
        static let amarillo = Color(red: 1, green: 0.85, blue: 0.12)    // el amarillo de Los Simpson
        static let tvBody = Color(red: 0.6, green: 0.42, blue: 0.74)    // la tele morada de la sala
        static let tvShade = Color(red: 0.42, green: 0.27, blue: 0.55)
        static let knob = Color(red: 0.3, green: 0.18, blue: 0.4)
        static let antenna = Color(red: 0.62, green: 0.62, blue: 0.66)
        static let osd = Color(red: 0.35, green: 1, blue: 0.45)          // el número de canal verde de las teles viejas
    }

    /// Lo que va a la derecha del título de una sección («Ver todo ›», «Todo ⌄», «📅 Octubre», el switch Películas · Series):
    /// todo del mismo alto que el segmentado del sistema (32 pt a la vista) y con 44 pt para tocar, como pide Apple.
    enum HeaderControl {
        static let height: CGFloat = 32, padding: CGFloat = 14, iconGap: CGFloat = 5
    }

    /// El calendario de estrenos (Sale hoy › el mes): cada día pintado con el color del arte de lo que sale.
    enum ReleaseDays {
        static let cell: CGFloat = 50, radius: CGFloat = 10, inset: CGFloat = 3, split: CGFloat = 1.5
        /// Cuántas series se pintan por día (dos: la casilla partida a la mitad); más, con «+N».
        static let maxColors = 2
        static let pastOpacity: Double = 0.55
    }

    /// «Elegir versión»: lo más angosto que queda una calidad (dos por renglón en cualquier iPhone: con tres se cortaba el texto), el punto de
    /// «Al instante» y el borde de la recomendada.
    enum Version {
        static let chipMinimum: CGFloat = 136, dot: CGFloat = 8, pickedStroke: CGFloat = 1.5
        /// Un idioma que se supone (no lo dice el nombre ni se comprobó): borde punteado.
        static let guessLine: CGFloat = 1, guessDash: CGFloat = 4
    }

    /// «Todas las fuentes» (`AllSourcesList`): el punto de qué tan rápido arranca (turquesa: ya está en Real-Debrid; ámbar:
    /// Real-Debrid aún no la tiene), cuántas se ven por calidad antes de «+N más» y lo atenuadas que van las ocultas.
    enum AllSourcesList {
        static let dot: CGFloat = 8
        static let ready = DS.brandMoon, mustDownload = DS.warning
        static let shownPerGroup = 3
        static let hiddenOpacity = DesignTokens.Opacity.faint
    }

    /// Al deslizar la ficha, el arte se recoge (`BleedArt(collapse:)`, aritmética en `OrbitalModels.HeroCollapse`): se queda un
    /// poco atrás, se encoge apenas, se oscurece hacia el color del fondo con un degradado que sube desde abajo, se difumina
    /// al final y se desvanece; el logo y la frase se van antes (no se quedan detrás de los datos).
    enum TitleHero {
        /// Parallax (parte del desplazamiento que se queda atrás), cuánto se encoge y el desenfoque máximo (desde qué progreso).
        static let parallax: Double = 0.4, shrink: Double = 0.05, blur: Double = 10, blurFrom: Double = 0.3
        /// El velo parejo ya recogido, a qué progreso el degradado de abajo cubre todo y desde cuándo se desvanece el arte.
        static let dim: Double = 0.55, riseEnd: Double = 0.8, fadeFrom: Double = 0.6
        /// El logo y la frase: a qué progreso ya se fueron y cuánto se encogen mientras.
        static let contentFadeEnd: Double = 0.35, contentShrink: Double = 0.06
        /// El degradado que sube: transparente arriba (el mismo color sin opacidad, para que no se agrise), casi sólido a esta
        /// altura y sólido al pie.
        static let riseTopOpacity: Double = 0, riseSolidAt: Double = 0.65, riseSolidOpacity: Double = 0.9
        /// Lo mínimo que mide el degradado (una escala de 0 no se puede invertir).
        static let riseMin: Double = 0.001
    }

    /// «Guardar en…»: cuántos renglones de tus listas se ven sin desplazar (más, se desplazan dentro de su zona) y cuántos
    /// se apartan la primera vez (sin saber cuántas tienes).
    enum SaveSheet {
        static let visibleRows = 5, fallbackRows = 3
    }

    enum TitleAction {
        /// El nombre en la barra no pasa por debajo del ‹ ni de los botones de la derecha.
        static let barTitleInset: CGFloat = 110
        /// El ancho máximo de la ficha en ventanas anchas (iPad, Mac): a todo lo ancho, en horizontal el arte llenaba la
        /// pantalla y las acciones quedaban abajo, fuera de la vista. El iPhone (440 pt como mucho) no lo alcanza.
        static let readableWidth: CGFloat = 720
        /// El zoom del póster hacia el panel de la derecha (iPad, Mac): dónde cae el arte (desde arriba de la ventana) y qué
        /// tanto rebota el resorte al llegar.
        static let panelArtTop: CGFloat = 70, flightBounce: Double = 0.18
        /// El desvanecido bajo la barra de arriba (además de la barra) y a qué parte del arte ya está completo.
        static let topFade: CGFloat = 36, fadeAt: CGFloat = 0.85
        /// El nombre en la barra: empieza a salir a esta parte del arte y termina de salir en este tramo.
        static let titleFrom: CGFloat = 0.7, titleSpan: CGFloat = 0.25
        /// Cuánto se oscurece el color del arte en el modo claro (para que se lea sobre el papel).
        static let lightDeepen: Double = 0.45
        static let tile: CGFloat = 64, ring: CGFloat = 3, ringSmall: CGFloat = 26, ringSmallLine: CGFloat = 2.5
        /// Cuántos renglones de sinopsis antes de «más».
        static let synopsisLines = 3
        /// El alto del arte de la ficha (proporción ancho / alto) y el ancho máximo del logo centrado.
        static let heroAspect: CGFloat = 0.9, logoWidth: CGFloat = 0.66
        /// En un teléfono bajito (SE) el arte es más ancho que alto: «Ver» y sus botones quedan a la vista sin deslizar.
        static let heroAspectShort: CGFloat = 1.3, shortScreen: CGFloat = 700
        /// Lo más ancho (bajito) que se vuelve el arte para que las acciones queden sobre la barra de pestañas.
        static let heroAspectMax: CGFloat = 1.6
        /// Con letra de accesibilidad el arte cede más (las acciones ocupan dos renglones).
        static let heroAspectMaxLarge: CGFloat = 3
        /// «Ver» / «Continuar»: el botón sólido de la ficha (con la calidad en un segundo renglón) y su barrita de avance.
        static let primaryHeight: CGFloat = 60, primaryProgress: CGFloat = 3
        /// El velo bajo la barra de la ficha: desde cuánto se baja, su alto (reloj y botones) y qué tan sólido queda a media altura.
        static let veilAfter: CGFloat = 240, veilHeight: CGFloat = 130, veilEdge: Double = 0.85
    }

    /// La entrada de la app (`LaunchSplash`): los mismos tiempos que la TV y la computadora (~1.4 s).
    enum Splash {
        static let wordSize: CGFloat = 52
        static let start = 0.1, ring = 0.5, moonAt = 0.5, leaveAt = 0.4, leaveSeconds = 0.5
        static let letterStagger = 0.04, letterRise: CGFloat = 0.14
        static let letter = Animation.easeOut(duration: 0.4).delay(0.08)
        static let moon = Animation.spring(duration: 0.55, bounce: 0.45)
        static let leave = Animation.spring(duration: 0.5, bounce: 0.08)
        /// Con «Reducir movimiento»: quieto un momento y un fundido.
        static let still = 0.5, fade = 0.3
    }

    /// La animación de carga del reproductor (`DSLoader`): una órbita delgada con una luna turquesa que la recorre dejando estela.
    /// Del tamaño del botón grande, para ocupar su lugar.
    enum Loader {
        static let size: CGFloat = 56
        static let ringWidth: CGFloat = 1.5, trailWidth: CGFloat = 3, moon: CGFloat = 7, moonGlow: CGFloat = 4
        /// Cuánto tarda una vuelta, qué parte de la órbita ocupa la estela y qué tan visible es su punta.
        static let seconds = 1.4
        static let trail: CGFloat = 0.35, trailOpacity = 0.9
        /// Dentro del botón grande: qué tan adentro de su orilla corre la luna.
        static let buttonInset: CGFloat = 5
    }

    /// El corazón de la ficha (`FavoriteButton`, tus favoritos de Trakt): lleno en frambuesa (el color de las listas con
    /// puesto, que se lee en claro y en oscuro) y vacío con el color de los demás botones de la barra.
    enum Favorites {
        static let filled = ListTint.chart
        static let symbol = "heart", symbolFilled = "heart.fill"
    }

    /// El carrusel de «En tendencia» en Inicio (`DeckCard`, `deckTransition`): tarjetas con lo que sigue a los lados, más
    /// chicas, oscuras y desenfocadas, giradas en 3D (coverflow).
    enum Deck {
        /// Qué parte del ancho toma la tarjeta del frente (asoman las de los lados) y su alto.
        static let sideMargin: CGFloat = 66, height: CGFloat = 430
        /// Cuántas veces se repiten las tarjetas para la vuelta infinita (se empieza a la mitad: nunca se llega al final).
        static let loopCopies = 40
        static let radius: CGFloat = 28, spacing: CGFloat = -18   // negativa: las de los lados se meten tras la del frente y asoman
        /// Lo que pierde una tarjeta a un lugar de distancia: tamaño, nitidez y luz.
        static let sideShrink: CGFloat = 0.12, sideBlur: CGFloat = 3, sideDim: Double = 0.16
        static let coverflowAngle: Double = 38, perspective: CGFloat = 0.6
        /// Donde empieza el velo (para que el texto se lea) y la sombra de la tarjeta.
        static let veilStart: CGFloat = 0.38, shadow: CGFloat = 24, shadowY: CGFloat = 14
    }

    /// La ficha rica (como Infuse): caras del reparto, insignias de calidad, calificaciones, tráiler y logos.
    enum Rich {
        static let face: CGFloat = 72, faceColumn: CGFloat = 84
        static let badgeStroke: CGFloat = 1, badgeRadius: CGFloat = 4
        static let clipWidth: CGFloat = 240, trailerPlay: CGFloat = 44
        static let logo: CGFloat = 36, logoRadius: CGFloat = 8
        static let personPhoto: CGFloat = 120, bioLines = 5
    }

    /// La dirección «Editorial» (A + una portada): espacio entre secciones, la portada y la pieza panorámica.
    enum Editorial {
        /// La tarjeta de un pendiente de tu watchlist (dos renglones que se deslizan juntos).
        static let watchlistWidth: CGFloat = 300, watchlistPoster: CGFloat = 64, watchlistRow: CGFloat = 112, watchlistInRow = 20
        static let sectionGap: CGFloat = 36, coverHeight: CGFloat = 200, wideWidth: CGFloat = 250, veilStart: CGFloat = 0.35

        /// Hasta dónde crece el logo en la portada y en la pieza panorámica.
        static let coverLogo = CGSize(width: 200, height: 60), wideLogo = CGSize(width: 130, height: 34)
    }

    /// Los colores de marca de las calificaciones (IMDb, TMDB, Trakt) para sus logotipos en la ficha.
    /// Las marcas de las calificaciones: los logos oficiales viven como vectores en `Assets.xcassets/Ratings` (IMDb, TMDB,
    /// Trakt), con sus colores de marca (ds-exception: logos de terceros, no se tiñen). Aquí, el rojo de Trakt que usan las
    /// colecciones y el alto común de los tres logos.
    enum RatingBrand {
        static let trakt = Color(red: 0.93, green: 0.11, blue: 0.14)
        /// Los logos, chicos y un poco apagados: son un dato bajo el nombre, no un titular.
        static let markHeight: CGFloat = 14, markOpacity: Double = 0.85
    }

    /// «Lo que puedes decir»: el globo con la frase para empezar toma un poco del color de su lugar.
    enum VoiceGuide { static let starterFill = 0.18 }

    /// «Tu año»: el mapa de calor (una columna por semana) y sus colores.
    enum YearMap {
        static let cell: CGFloat = 9, gap: CGFloat = 3, radius: CGFloat = 2
        /// El aro del día elegido y el póster de lo que viste ese día.
        static let ring: CGFloat = 1.5, dayPoster: CGFloat = 40
        static let movies = Color(red: 0.24, green: 0.44, blue: 0.85), series = Color(red: 0.42, green: 0.29, blue: 0.77), both = Color(red: 0.69, green: 0.29, blue: 0.84)
    }

    /// La barra de espacio de Descargas.
    enum Storage {
        static let height: CGFloat = 14, gap: CGFloat = 2, minSegment: CGFloat = 3, dot: CGFloat = 8
        /// Por debajo de esta parte libre, el dato se pone en ámbar.
        static let lowFraction = 0.1
    }

    /// Ajustes: los renglones con su ícono de color.
    enum SettingsLook {
        static let rowIcon: CGFloat = 28
        /// Lo que ocupa la flecha de un renglón que lleva a otra página.
        static let chevronSlot: CGFloat = 20
        static let profileAvatar: CGFloat = 60, editBadge: CGFloat = 22
        /// El anillo de lo elegido (los días del calendario de estrenos).
        static let optionRing: CGFloat = 2
    }

    /// El color de cada plataforma (su tarjeta en abanico, el brillo de su logo y de los números de sus rankings).
    enum PlatformTint {
        static func color(_ brand: String) -> Color { Palette.color(hex: DesignTokens.Platform.color(brand)) ?? .clear }   // design/tokens.json › platforms
    }

    /// «Tus plataformas»: la tarjeta con su top 3 en abanico y su página de rankings.
    /// Colecciones (Para ti › Listas): el alto de la estatuilla al frente, su halo y el color de cada premio.
    /// «¿Qué vemos?»: el alto de la hoja corta (la propuesta rápida), la parte de la pantalla de la estirada, el alto de la
    /// propuesta y los mínimos de calificación que se ofrecen.
    enum Decide {
        /// El alto de la hoja corta antes de medirse.
        static let quickHeight: CGFloat = 470
        /// Los tres carteles: el elegido con su borde; los otros, un poco más chicos y tenues.
        static let chosenStroke: CGFloat = 3, otherScale: CGFloat = 0.92, otherOpacity: Double = 0.7
        /// La frase de por qué verla: al menos estos caracteres antes de cortar en el primer punto.
        static let pitchMin = 40
        /// Los carteles apilados de una lista en «De qué listas».
        static let listPoster: CGFloat = 44
        /// Los mosaicos de «Más filtros»: alto de un género y de una época, y a qué tamaño se baja su arte.
        static let genreTile: CGFloat = 60, eraTile: CGFloat = 80
        /// Elegir un mosaico: crece un poco (y su imagen se acerca), anillo con brillo; los demás pierden color.
        static let chosenScale: CGFloat = 1.04, artZoom: CGFloat = 1.08, glowRadius: CGFloat = 10, glowOpacity: Double = 0.55
        static let dimSaturation: Double = 0.4, labelShadow: CGFloat = 4, eraTracking: CGFloat = -0.5
    }

    /// Modo acompañante: la tarjeta del juego, las del carrusel, la batería baja (%), las líneas de la nota y los tiempos
    /// del temporizador (minutos).
    enum Companion {
        static let dot: CGFloat = 8, cardHeight: CGFloat = 300, panelWidth: CGFloat = 300, panelHeight: CGFloat = 250
        static let lowBattery = 20, noteLines = 5
        /// Lo que se asoma la tarjeta siguiente del carrusel (una orilla, sin texto a medias): así se lee que se desliza.
        static let peek: CGFloat = 40
        static let timerSteps = [15, 30, 60, 90]
        /// Cuánto antes del cierre automático se avisa (segundos).
        static let closeWarning: TimeInterval = 600
    }

    enum Collections {
        /// El ícono de la tarjeta «Tu año» al final de Para ti.
        static let yearIcon: CGFloat = 60
        static let emblem: CGFloat = 70, glow: CGFloat = 16
        /// El sello de dónde viene una lista (Trakt, tus complementos, Rotten Tomatoes, tu Orbital).
        static let addon = Color(red: 0.13, green: 0.47, blue: 0.44), critics = Color(red: 0.78, green: 0.16, blue: 0.07), orbital = Color(red: 0.24, green: 0.48, blue: 0.85)
        static let badgeRadius: CGFloat = 5
        /// La tarjeta de una lista: su pila de pósters.
        static let stackPoster: CGFloat = 40, stackWidth: CGFloat = 54, stackAngle: Double = 8
        /// «Porque viste»: el póster de lo que viste y los relacionados.
        static let seedPoster: CGFloat = 104, relatedPoster: CGFloat = 92
        /// «Porque viste»: cuántos pósters vacíos ocupan el lugar de las relacionadas mientras llegan.
        static let relatedPlaceholders = 4
        /// «Porque viste» en mini pósters: el tamaño de cada uno, el elegido (crece) y qué tan apagados los demás.
        /// «Porque viste» en mazo: la carta de arriba, cuánto se corre y gira cada una de abajo, y cuánto hay que arrastrar.
        static let deckPoster: CGFloat = 112, deckShift: CGFloat = 7, deckTurn: Double = 3, deckShrink: CGFloat = 0.05, deckThrow: CGFloat = 40, deckDepth = 3
        /// Aventar la carta: sale volando de lado en 0.22 s y las de abajo suben con un resorte ágil.
        static let deckFly: Double = 0.22, deckFlyDistance: CGFloat = 340, deckSettle: Double = 0.28
        /// Los botones de anterior y siguiente del mazo: el glifo y el círculo (≥ 44 pt para tocar).
        static let deckNavGlyph: CGFloat = 22, deckNav: CGFloat = 48
        /// El alto del mazo (la carta y lo que se asoman las de abajo): la columna del nombre mide eso, sea corto o largo.
        static let deckHeight: CGFloat = deckPoster / DesignTokens.Aspect.poster + deckShift * CGFloat(deckDepth - 1)
        /// Lo más que se achica un nombre largo para caber en sus dos renglones.
        static let becauseTitleScale: CGFloat = 0.6
        /// «Por año»: la tarjeta (cuatro pósters) y su número.
        static let yearWidth: CGFloat = 150, yearHeight: CGFloat = 150
        /// La línea (desde arriba de lo visible, bajo la barra) que decide qué grupo marca el índice.
        static let spyLine: CGFloat = 70

        static let gold = Color(red: 0.83, green: 0.65, blue: 0.25), silver = Color(red: 0.78, green: 0.76, blue: 0.72)
        static let bronze = Color(red: 0.72, green: 0.45, blue: 0.26)
        /// El carrusel centrado: cuánto se encogen y apagan las de los lados; el reflejo (alto, separación, intensidad) y el peso.
        static let sideShrink: CGFloat = 0.1, sideFade: Double = 0.18
        static let reflection: CGFloat = 44, reflectionGap: CGFloat = 4, reflectionOpacity: Double = 0.3, reflectionBlur: CGFloat = 1.5
        /// Lo que la sección siguiente puede montarse sobre el reflejo de la última fila (su parte ya desvanecida): sin esto,
        /// entre una fila con reflejo y la siguiente quedaba el reflejo entero más el aire entre secciones (un hueco vacío).
        static let reflectionTail: CGFloat = 30
        static let weight: CGFloat = 18, weightY: CGFloat = 12, weightTint: Double = 0.35
        /// El aire entre Plataformas, Estudios, Premios y Por año (menos que entre secciones: el reflejo ya separa).
        static let groupGap: CGFloat = 20
        /// El halo de los estudios (neutro: cada estudio es de muchos colores).
        static let studio = Color(red: 0.55, green: 0.56, blue: 0.62)
        /// El logo del estudio en su cápsula.
        static let studioLogoWidth: CGFloat = 96, studioLogoHeight: CGFloat = 26
        /// El halo de cada temporada de «Temporadas»: Halloween naranja, Día de Muertos rosa mexicano, Navidad verde, San Valentín
        /// guinda y Verano ámbar. Los géneros usan el neutro de los estudios.
        static let halloween = Color(red: 0.95, green: 0.47, blue: 0.12), muertos = Color(red: 0.89, green: 0.0, blue: 0.49)
        static let navidad = Color(red: 0.13, green: 0.58, blue: 0.32), sanValentin = Color(red: 0.62, green: 0.11, blue: 0.25)
        static let verano = Color(red: 0.96, green: 0.71, blue: 0.16)
        static func season(_ slug: String) -> Color {
            switch slug { case "halloween": halloween; case "muertos": muertos; case "navidad": navidad; case "sanvalentin": sanValentin; case "verano": verano; default: studio }
        }
        /// El ícono blanco de una temporada o un género al pie de su tarjeta (con su nombre debajo) y en grande al abrirla.
        static let iconEmblem: CGFloat = 40, iconHeader: CGFloat = 56   // antes 22: al pie de la tarjeta se perdía
        /// El resplandor detrás del ícono de una temporada o género (cuánto tapa y de qué tamaño).
        static let iconBackdrop = 0.85, iconBackdropScale: CGFloat = 1.3
        static func tint(_ award: String) -> Color {
            switch award { case "emmy": silver; case "bafta", "ariel": bronze; default: gold }
        }
    }

    enum PlatformFan {
        /// El subrayado de la lista elegida en la página de una plataforma.
        static let tabUnderline: CGFloat = 3
        /// Dos tarjetas y un pedazo de la tercera (como «Próximos estrenos»): en un iPhone de 375 pt las dos de 168 llenaban casi todo
        /// el ancho y dejaban 11 pt a la derecha contra 16 a la izquierda.
        static var width: CGFloat { min(maxWidth, (WindowMetrics.size.width - DS.Space.gutter - DS.Space.s3 - DS.Poster.peek) / 2) }
        static let maxWidth: CGFloat = 168, height: CGFloat = 176, radius: CGFloat = 22
        static let poster: CGFloat = 66, posterTop: CGFloat = 26, angle: Double = 15, spread: CGFloat = 8, lift: CGFloat = 6
        static let logo: CGFloat = 34, logoRadius: CGFloat = 10, glow: CGFloat = 18
        /// La pastilla de una plataforma (el Top 10 de Inicio): el logo (en círculo), el aire alrededor y el borde de la elegida.
        static let pillLogo: CGFloat = 26, pillInset: CGFloat = 5, pillStroke: CGFloat = 1.5
        static let tintTop: Double = 0.42, tintEdge: Double = 0.45
        /// El logo grande de la página de la plataforma y su halo.
        static let headerLogo: CGFloat = 72, headerGlow: CGFloat = 44
        /// El brillo de los números de un ranking.
        static let numberGlow: CGFloat = 12, numberTint: Double = 0.55
    }

    /// Tu avatar: en Inicio (junto al saludo) y en Ajustes.
    enum Avatar {
        static let toolbar: CGFloat = 34, picker: CGFloat = 64, ring: CGFloat = 3
        /// La esquina de un ícono de app (la curva de iOS: 22.37 % del lado).
        static let iconCorner: CGFloat = 0.2237
    }

    /// El color de cada lista (su ícono en Inicio y Para ti): fijo, el mismo siempre, para encontrarla de un vistazo. Tonos de
    /// brillo parecido para que ninguno grite más que los demás. En claro, el mismo tono más oscuro (`DesignTokens.ListTint`).
    enum ListTint {
        private static func tint(_ name: String) -> Color {
            guard let hex = DesignTokens.ListTint.hex[name] else { return .clear }
            return adaptive(dark: hex.dark, light: hex.light)
        }
        static let watching = tint("watching")   // ámbar
        static let library = tint("library")     // azul cielo
        static let bookmark = tint("bookmark")   // rosa
        static let spark = tint("spark")         // violeta
        static let calendar = tint("calendar")   // verde agua
        static let series = tint("series")       // azul
        static let trend = tint("trend")         // coral
        static let flame = tint("flame")         // naranja
        static let list = tint("list")           // verde
        static let addon = tint("addon")         // lila
        static let chart = tint("chart")         // frambuesa
        static let trophy = tint("trophy")       // oro
    }

    /// El control completo de la TV (`TouchPad`, `RemoteKey`).
    enum Remote {
        /// Desde qué ancho de ventana el control va en un panel fijo a la derecha (iPad horizontal, Mac) en vez de una
        /// tarjeta: el iPad de pie (de 820 a 1024 pt) se queda con la tarjeta, que no aprieta el contenido.
        static let panelWindowWidth: CGFloat = 1000
        /// El ancho del panel: el de un iPhone, para el que está hecho el control.
        static let panelMin: CGFloat = 360, panelIdeal: CGFloat = 390, panelMax: CGFloat = 440
        /// De qué tamaño parte lo que se despliega en el control (los sustos): crece desde arriba a su tamaño.
        static let revealScale: CGFloat = 0.96
        /// Cuánto espera la hoja del control a que su contenido deje de cambiar antes de tomar su nuevo alto (en una sola
        /// animación, en lugar de seguir cada paso).
        static let heightSettle: Double = 0.12
        /// La línea de tiempo con sustos: alto de la barra, de la marca leve y de la fuerte; el punto donde vas.
        static let timelineBar: CGFloat = 6, scareMark: CGFloat = 12, scareMarkMajor: CGFloat = 20, scareMarkWidth: CGFloat = 3
        static let playhead: CGFloat = 14
        /// Cuántos segundos antes de un susto vibra (si pediste el aviso) y cada cuánto se revisa.
        static let scareLead: Double = 5, scareTick: Double = 0.5
        /// Tras «mantener», cuánto se ignora el toque de soltar.
        static let holdTapWindow: TimeInterval = 0.8
        /// Cuánto se mantiene una tecla para su segunda acción (mantener «Atrás»: al inicio).
        static let holdSeconds: Double = 0.6
        /// La barra del volumen de la TV en el control.
        static let volumeBar: CGFloat = 6
        /// Alto del pad táctil y de cada tecla.
        static let padHeight: CGFloat = 170, keyHeight: CGFloat = 60
        /// En un teléfono bajito (SE) el pad y las teclas se encogen: «Atrás» y «Escribir en la TV» caben sin deslizar.
        static let padHeightShort: CGFloat = 116, keyHeightShort: CGFloat = 46, shortScreen: CGFloat = 700
        /// El alto fijo del ícono de una tecla: los nombres quedan en el mismo renglón aunque los símbolos midan distinto.
        static let keyIcon: CGFloat = 24
        static var isShortScreen: Bool { WindowMetrics.size.height < shortScreen }
        /// El alto de una tecla y del pad según el teléfono.
        static var keyHeightFitted: CGFloat { isShortScreen ? keyHeightShort : keyHeight }
        /// En un SE la hoja estirada puede llegar arriba del todo (opaca) para que quepa el control completo.
        static var maxShareFitted: CGFloat { isShortScreen ? 1 : maxShare }
        static var padHeightFitted: CGFloat { isShortScreen ? padHeightShort : max(padHeight, WindowMetrics.size.height * padShare) }
        /// Qué parte del alto de la pantalla toma el pad (en un iPhone grande crece).
        static let padShare: CGFloat = 0.2
        /// Lo más que crece la hoja estirada (por debajo de la altura completa, que iOS vuelve opaca).
        static let maxShare: CGFloat = 0.86
        /// Cuánto hay que deslizar para una flecha (y cada cuánto se repite al seguir deslizando).
        static let swipeStep: CGFloat = 56
        /// Lo que se puede mover el dedo y seguir contando como toque (A).
        static let tapSlop: CGFloat = 10
        /// La luz bajo el dedo en el pad.
        static let touchGlow: CGFloat = 72
        /// Cuánto se espera a que dejes de escribir para mandar el texto a la TV.
        static let typeDebounce = UInt64(0.35 * 1e9)
    }

    /// El mosaico de «Para ti» (equivalente a `foryou-mosaic` en la TV): columnas, cuánto crece la enfocada
    /// y las esperas de su ambiente y «cobra vida».
    enum Mosaic {
        static let columnsPortrait = DesignTokens.Mosaic.columnsPortrait, columnsLandscape = DesignTokens.Mosaic.columnsLandscape
        static let columnsCompact = DesignTokens.Mosaic.columnsCompact, compactWidth = CGFloat(DesignTokens.Mosaic.compactWidth)
        static let uniform = DesignTokens.Mosaic.uniform
        static let growRatio = CGFloat(DesignTokens.Mosaic.growRatio)
        static let idle = DesignTokens.Mosaic.idleSeconds, alive = DesignTokens.Mosaic.aliveSeconds
        static let driftTick = DesignTokens.Mosaic.driftTick
        static let driftPerSecond = CGFloat(DesignTokens.Mosaic.driftPerSecond)
        static let buffer = CGFloat(DesignTokens.Mosaic.bufferHeight)
        static let focusedRowRatio = DesignTokens.Mosaic.focusedRowRatio
    }
}
