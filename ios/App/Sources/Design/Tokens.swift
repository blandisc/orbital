import SwiftUI
import OrbitalCore

/// Sistema de diseño de Orbital para iPhone. Los valores salen de `OrbitalCore.DesignTokens` (los mismos de
/// `orbital/web/styles/palette.json`). **Nada se crea suelto**: las pantallas usan `DS.*` y las piezas de `Components.swift`.
/// Una prueba (`DesignTests`) revisa que ninguna pantalla escriba colores, tamaños ni duraciones a mano.
enum DS {
    // MARK: Color
    enum Palette {
        static func color(_ name: String) -> Color {
            guard let hex = DesignTokens.palette[name], let c = rgb(hex: hex) else { return .clear }
            return Color(red: c.r, green: c.g, blue: c.b)
        }

        /// Un color calculado a partir del arte («#rrggbb», p. ej. el tono del póster en el snapshot del widget).
        static func color(hex: String?) -> Color? {
            guard let hex, let c = rgb(hex: hex) else { return nil }
            return Color(red: c.r, green: c.g, blue: c.b)
        }
    }

    /// Un color que cambia con el modo claro u oscuro (`DesignTokens.Role`).
    static func role(_ role: DesignTokens.Role) -> Color { adaptive(dark: role.hex.dark, light: role.hex.light) }

    /// Una capa translúcida sobre el color de texto de cada modo (blanco en oscuro, negro en claro).
    static func overlay(_ opacity: Double) -> Color {
        adaptive(dark: DesignTokens.Ink.darkOverlay, light: DesignTokens.Ink.lightOverlay, opacity: opacity)
    }

    private static func adaptive(dark: String, light: String, opacity: Double = 1) -> Color {
        func ui(_ hex: String) -> UIColor {
            let c = rgb(hex: hex) ?? (0, 0, 0)
            return UIColor(red: c.r, green: c.g, blue: c.b, alpha: opacity)
        }
        let (d, l) = (ui(dark), ui(light))
        return Color(uiColor: UIColor { $0.userInterfaceStyle == .light ? l : d })
    }

    // MARK: Papeles (cambian solos con el modo)
    static let bg = role(.background)
    static let surface = role(.surface)
    static let surfaceRaised = role(.surfaceRaised)
    static let text = role(.label)
    static let textMuted = role(.secondaryLabel)
    static let textFaint = role(.tertiaryLabel)
    static let ink500 = role(.decorative)
    static let primary = role(.primary)
    static let onPrimary = role(.onPrimary)
    static let accent = role(.accent)
    /// «En vivo» (el único teal, como en la TV).
    static let live = role(.live)
    /// La línea del porqué arriba de un encabezado (ámbar, como el «porqué» de las portadas).
    static let eyebrow = role(.warning)
    /// La luna de la marca (turquesa, igual en los dos modos).
    static let brandMoon = role(.brandMoon)
    /// Lo que salió bien o ya está (visto, descargado, conectado): el papel, como la TV.
    static let good = role(.accent)
    static let warning = role(.warning)
    static let danger = role(.danger)
    static let hairline = overlay(DesignTokens.Opacity.hairline)
    static let fill = overlay(DesignTokens.Opacity.fill)
    static let fillStrong = overlay(DesignTokens.Opacity.fillStrong)
    static let track = overlay(DesignTokens.Opacity.track)

    // MARK: Sobre el arte (siempre la sala oscura, en los dos modos)
    /// El grafito más profundo: el fondo del tono del arte en modo oscuro y la base de los velos.
    static let backdropDeep = Palette.color("ink-1000")
    /// El papel: la base del tono del arte en modo claro.
    static let paper = Palette.color("paper")
    static let scrim = Palette.color("ink-1000").opacity(DesignTokens.Opacity.scrim)
    /// El texto secundario sobre el velo del arte (más claro que `textMuted`: el arte de fondo le quita contraste).
    static let onArtSecondary = Palette.color("paper").opacity(DesignTokens.Opacity.onArtSecondary)
    static let badgeBackground = Palette.color("ink-1000").opacity(DesignTokens.Opacity.badge)
    static let scrimStrong = Palette.color("ink-1000").opacity(DesignTokens.Opacity.scrimStrong)
    static let video = Color.black   // detrás de un video: negro de verdad
    static let subtitleText = Color.white       // subtítulos: blanco puro sobre el video, como cualquier reproductor
    static let subtitleShadow = Color.black.opacity(DesignTokens.Opacity.subtitleShadow)

    /// El círculo de avance de una descarga junto a un episodio (el del sistema mide 58 pt: se encoge al tamaño de un ícono).
    enum Gauge { static let episodeScale = CGFloat(DesignTokens.Size.gaugeScale) }

    /// Subtítulos: medidas relativas a la letra o al video (la letra misma sale de Ajustes › Tamaño de subtítulos).
    enum Subtitle {
        static let minFont = CGFloat(DesignTokens.Subtitle.minFont), liftWithControls = CGFloat(DesignTokens.Subtitle.liftWithControls)
        static let lineGap = CGFloat(DesignTokens.Subtitle.lineGap), edgeMargin = CGFloat(DesignTokens.Subtitle.edgeMargin)
        static let shadowRadius = CGFloat(DesignTokens.Subtitle.shadowRadius), outlineWidth = CGFloat(DesignTokens.Subtitle.outlineWidth)
    }

    /// Brillo, volumen y buscar arrastrando (como Infuse): el umbral que decide el eje (el mismo número que usa
    /// `PlayerGestures`, la aritmética pura) y el tamaño del indicador.
    enum Gesture {
        /// La franja de cada orilla donde el doble toque salta ±10 s (al centro, pausa o sigue).
        static let edgeShare: CGFloat = 0.28
        /// A cuántos segundos del destino ya se da por llegado un salto (el pulgar vuelve a seguir el avance).
        static let seekArrived: Double = 2
        static let axisThreshold = CGFloat(DesignTokens.Gesture.axisThreshold)
        static let indicatorBarHeight: CGFloat = 120
        static let indicatorBarWidth: CGFloat = 5
        /// La burbuja de buscar no se acerca más que esto a los bordes de la pantalla.
        static let seekBubbleSideMargin: CGFloat = 64
        /// De la burbuja (su centro) al borde inferior: justo encima de la barra de avance (que vive dentro del
        /// `padding(DS.Space.s6)` de `controls`, con el slider y la hilera de tiempos debajo).
        static let seekBubbleBottomInset: CGFloat = 108
    }

    // MARK: Espacio y forma
    enum Space {
        static let s1 = CGFloat(DesignTokens.Space.s1), s2 = CGFloat(DesignTokens.Space.s2), s3 = CGFloat(DesignTokens.Space.s3)
        static let s4 = CGFloat(DesignTokens.Space.s4), s5 = CGFloat(DesignTokens.Space.s5), s6 = CGFloat(DesignTokens.Space.s6)
        static let s8 = CGFloat(DesignTokens.Space.s8), s10 = CGFloat(DesignTokens.Space.s10), s14 = CGFloat(DesignTokens.Space.s14)
        /// Margen lateral de las pantallas.
        static let gutter = s4
    }

    enum Radius {
        static let xs = CGFloat(DesignTokens.Radius.xs), sm = CGFloat(DesignTokens.Radius.sm), md = CGFloat(DesignTokens.Radius.md)
        static let lg = CGFloat(DesignTokens.Radius.lg), xl = CGFloat(DesignTokens.Radius.xl), xxl = CGFloat(DesignTokens.Radius.xxl)
        static let pill = CGFloat(DesignTokens.Radius.pill)
    }

    // MARK: Tipografía (con Dynamic Type: hace de «Tamaño del texto»)
    enum Typeface {
        case xs, sm, md, lg, xl, xxl, display
        var style: Font.TextStyle {
            switch self { case .xs: .caption2; case .sm: .caption; case .md: .subheadline; case .lg: .headline; case .xl: .title2; case .xxl: .title; case .display: .largeTitle }
        }
    }

    static func font(_ face: Typeface, weight: Font.Weight = .regular) -> Font { .system(face.style, design: .default).weight(weight) }

    /// Recetas de texto de Proyección: cada pantalla usa estas, no tamaños sueltos. SF Pro con Dynamic Type; los datos
    /// (tiempos, temporadas, tamaños) en SF Mono, la única marca tipográfica de la app.
    enum TextRecipe {
        /// Título grande de pantalla (lo pinta la barra de navegación nativa), título de sección, título de pieza, cuerpo,
        /// secundario, pie y dato.
        case display, title, section, cardTitle, body, secondary, footnote, caption, eyebrow, data
        var font: Font {
            switch self {
            case .display: .system(.largeTitle, design: .default).weight(.bold)
            case .title: .system(.title, design: .default).weight(.bold)
            case .section: .system(.title2, design: .default).weight(.bold)
            case .cardTitle: .system(.headline, design: .default)
            case .body: .system(.body, design: .default)
            case .secondary: .system(.subheadline, design: .default)
            case .footnote: .system(.footnote, design: .default)
            case .caption: .system(.caption, design: .default)
            case .eyebrow: .system(.footnote, design: .default).weight(.semibold)
            case .data: .system(.footnote, design: .default).monospacedDigit()   // números tabulares, como `tabular-nums` en la TV
            }
        }
    }

    // MARK: Movimiento (sin movimiento con «Reducir movimiento»)
    enum Motion {
        static func base(_ reduce: Bool) -> Animation? { reduce ? nil : .easeOut(duration: DesignTokens.Motion.base) }
        static func enter(_ reduce: Bool) -> Animation? { reduce ? nil : .easeOut(duration: DesignTokens.Motion.enter) }
        static func tint(_ reduce: Bool) -> Animation? { reduce ? nil : .easeInOut(duration: DesignTokens.Motion.tint) }
        static func spring(_ reduce: Bool) -> Animation? { reduce ? nil : .spring(duration: DesignTokens.Motion.slow, bounce: 0.2) }
    }

    /// La marca de Orbital (la de la TV: icons.js · mark y status-bar.css «La marca»). Todo en las unidades de su caja de 32
    /// (el planeta y el anillo) o en em de la palabra (la luna, el interletrado, el tamaño de la marca junto a la palabra).
    enum Brand {
        static let box: CGFloat = 32
        static let planetRadius: CGFloat = 7.2, planetStroke: CGFloat = 2.8, ringStroke: CGFloat = 2.1
        /// El anillo, un poco más tenue que el planeta.
        static let ringOpacity: Double = 0.7
        /// La luna: su ancho, lo que sube sobre la línea de base y lo que la separa de la palabra (em).
        static let moon: CGFloat = 0.26, moonRise: CGFloat = 0.62, moonGap: CGFloat = 0.1
        /// De dónde cae la luna al aparecer (em) y lo chica que empieza.
        static let moonFromX: CGFloat = -0.9, moonFromY: CGFloat = -0.7, moonFromScale: CGFloat = 0.2
        /// «orbital»: interletrado apretado (em); la marca mide 1.7 veces la letra y va a media letra de ella.
        static let tracking: CGFloat = -0.035, markScale: CGFloat = 1.7, markGap: CGFloat = 0.5
        /// Al arrancar: el anillo se dibuja en este tiempo y la luna cae después (s), como en la TV (--duration-land).
        static let drawSeconds = 0.76, moonDelay = 0.76 * 1.7
        /// La letra de «orbital» (en la TV, Segoe UI Variable Display): SF Pro Rounded en negrita, del tamaño de la marca.
        static func wordFont(_ size: CGFloat) -> Font { .system(size: size, weight: .bold, design: .rounded) }
    }

    /// El carrusel de «Seguir viendo» en Inicio (`DeckCard`, `deckTransition`): tarjetas con lo que sigue a los lados, más
    /// chicas, oscuras y desenfocadas; coverflow las gira en 3D y abanico las inclina desde abajo.
    enum Deck {
        /// Qué parte del ancho toma la tarjeta del frente (asoman las de los lados) y su alto.
        static let sideMargin: CGFloat = 66, height: CGFloat = 430
        /// Cuántas veces se repiten las tarjetas para la vuelta infinita (se empieza a la mitad: nunca se llega al final).
        static let loopCopies = 40
        static let radius: CGFloat = 28, spacing: CGFloat = -18   // negativa: las de los lados se meten tras la del frente y asoman
        /// Lo que pierde una tarjeta a un lugar de distancia: tamaño, nitidez y luz.
        static let sideShrink: CGFloat = 0.12, sideBlur: CGFloat = 3, sideDim: Double = 0.16
        static let coverflowAngle: Double = 38, perspective: CGFloat = 0.6
        static let fanAngle: Double = 9, fanDrop: CGFloat = 24
        /// Donde empieza el velo (para que el texto se lea) y la sombra de la tarjeta.
        static let veilStart: CGFloat = 0.38, shadow: CGFloat = 24, shadowY: CGFloat = 14
        /// El indicador de tiempo: la barrita de la píldora, el trazo del borde y del arco, y el tamaño de la órbita.
        static let pillBar: CGFloat = 56, edgeStroke: CGFloat = 3, arcStroke: CGFloat = 2.5, arcSize: CGFloat = 150, arcInset: CGFloat = 14
        /// La parte de la órbita que se ve dentro de la tarjeta (un cuarto) y su giro.
        static let arcQuarter: CGFloat = 0.25, arcQuarterDegrees: Double = 90
        /// El ancho del botón que se llena (con el de la TV al lado).
        static let fillWidth: CGFloat = 200
        static let moonDot: CGFloat = 9
        /// El botón que se llena: el tono del avance y lo tenue de los minutos.
        static let fillOpacity: Double = 0.55, fillMinutesOpacity: Double = 0.7
    }

    /// La ficha rica (como Infuse): caras del reparto, insignias de calidad, calificaciones, tráiler y logos.
    enum Rich {
        static let face: CGFloat = 72, faceColumn: CGFloat = 84
        static let badgeStroke: CGFloat = 1, badgeRadius: CGFloat = 4
        static let clipWidth: CGFloat = 240, trailerPlay: CGFloat = 44
        static let logo: CGFloat = 36, logoRadius: CGFloat = 8
        static let personPhoto: CGFloat = 120, bioLines = 5
    }

    /// El panel «Ajustes del video» del reproductor: a la derecha en horizontal, hoja ajustada en vertical.
    enum PlayerPanel {
        /// El ícono de una app (Infuse) junto a su botón: tamaño y redondeo como los íconos de iOS.
        static let appIcon: CGFloat = 20, appIconCorner: CGFloat = 0.225
        static let width: CGFloat = 420, radius: CGFloat = 30, rowRadius: CGFloat = 16, icon: CGFloat = 32
        /// El ancho del valor de la velocidad («1.25×») entre − y +.
        static let speedValue: CGFloat = 52
        /// Tamaños de letra de muestra («Aa») para chico, mediano y grande.
        static let sampleSizes: [String: CGFloat] = ["small": 12, "medium": 15, "large": 19]
        /// En vertical con el panel abierto, la parte de arriba de la pantalla que queda para el video.
        static let videoShare: CGFloat = 0.5
        /// En vertical: dónde va el centro del video (parte de la altura; se mueve arrastrando) y entre qué límites.
        static let portraitCenter: CGFloat = 0.32, portraitCenterRange: ClosedRange<CGFloat> = 0.2...0.62
        /// El botón de reproducir, más grande que ±10 (lo que más se toca).
        static let playButton: CGFloat = 72, playGlyph: CGFloat = 30, sideButton: CGFloat = 52
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
    enum RatingBrand {
        static let imdb = Color(red: 0.96, green: 0.77, blue: 0.09), imdbInk = Color(red: 0, green: 0, blue: 0)
        static let tmdbStart = Color(red: 0.56, green: 0.81, blue: 0.63), tmdbEnd = Color(red: 0, green: 0.71, blue: 0.89)
        static let tmdbInk = Color(red: 0.05, green: 0.15, blue: 0.25)
        static let trakt = Color(red: 0.93, green: 0.11, blue: 0.14)
        static let markHeight: CGFloat = 18, markRadius: CGFloat = 4
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

    /// Ajustes: los renglones con su ícono de color y las vistas previas de cada estilo de Inicio.
    enum SettingsLook {
        static let rowIcon: CGFloat = 28
        static let profileAvatar: CGFloat = 60, editBadge: CGFloat = 22
        /// La vista previa del carrusel: tres tarjetas chicas que se deslizan solas, de ida y vuelta.
        static let deckPreviewHeight: CGFloat = 120, deckPreviewCard = CGSize(width: 58, height: 86), deckPreviewStep: CGFloat = 50
        static let deckPreviewBlur: CGFloat = 1.5, deckPreviewDrop: CGFloat = 6, deckPreviewSpeed: Double = 0.9
        /// La vista previa de cuánto falta: una tarjeta del tamaño real, reducida.
        static let timePreviewCard = CGSize(width: 300, height: 190), timePreviewScale: CGFloat = 0.5
        static let optionRadius: CGFloat = 18, optionRing: CGFloat = 2
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
        static let quickHeight: CGFloat = 470, moreShare: CGFloat = 0.72, cardHeight: CGFloat = 230, compactCardHeight: CGFloat = 130
        /// Los tres carteles: el elegido con su borde; los otros, un poco más chicos y tenues; al elegir filtros, más bajos.
        static let chosenStroke: CGFloat = 3, otherScale: CGFloat = 0.92, otherOpacity: Double = 0.7, trioCompactHeight: CGFloat = 150
        /// La frase de por qué verla: al menos estos caracteres antes de cortar en el primer punto.
        static let pitchMin = 40
        static let ratingSteps: [Double] = [0, 6, 7, 8]
    }

    /// Modo acompañante: la tarjeta del juego, las del carrusel, la batería baja (%), las líneas de la nota y los tiempos
    /// del temporizador (minutos).
    enum Companion {
        static let dot: CGFloat = 8, cardHeight: CGFloat = 300, panelWidth: CGFloat = 300, panelHeight: CGFloat = 250
        static let lowBattery = 20, noteLines = 5
        static let timerSteps = [15, 30, 60, 90]
        /// Cuánto antes del cierre automático se avisa (segundos).
        static let closeWarning: TimeInterval = 600
    }

    enum Collections {
        /// El ícono de la tarjeta «Tu año» al final de Para ti.
        static let yearIcon: CGFloat = 60
        static let emblem: CGFloat = 70, glow: CGFloat = 16
        /// El sello de dónde viene una lista (Trakt, Stremio, tu Orbital).
        static let stremio = Color(red: 0.54, green: 0.35, blue: 0.67), orbital = Color(red: 0.24, green: 0.48, blue: 0.85)
        static let badgeRadius: CGFloat = 5
        /// La tarjeta de una lista: su pila de pósters.
        static let stackPoster: CGFloat = 40, stackWidth: CGFloat = 54, stackAngle: Double = 8
        /// «Porque viste»: el póster de lo que viste y los relacionados.
        static let seedPoster: CGFloat = 104, relatedPoster: CGFloat = 64
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
        static func tint(_ award: String) -> Color {
            switch award { case "emmy": silver; case "bafta", "ariel": bronze; default: gold }
        }
    }

    enum PlatformFan {
        /// El subrayado de la lista elegida en la página de una plataforma.
        static let tabUnderline: CGFloat = 3
        static let width: CGFloat = 168, height: CGFloat = 176, radius: CGFloat = 22
        static let poster: CGFloat = 66, posterTop: CGFloat = 26, angle: Double = 15, spread: CGFloat = 8, lift: CGFloat = 6
        static let logo: CGFloat = 34, logoRadius: CGFloat = 10, glow: CGFloat = 18
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
    /// brillo parecido para que ninguno grite más que los demás.
    enum ListTint {
        static let watching = Color(red: 1, green: 0.71, blue: 0.28)        // ámbar
        static let library = Color(red: 0.35, green: 0.78, blue: 0.98)      // azul cielo
        static let bookmark = Color(red: 1, green: 0.44, blue: 0.68)        // rosa
        static let spark = Color(red: 0.71, green: 0.55, blue: 1)           // violeta
        static let calendar = Color(red: 0.18, green: 0.77, blue: 0.65)     // verde agua
        static let series = Color(red: 0.48, green: 0.64, blue: 1)          // azul
        static let trend = Color(red: 1, green: 0.48, blue: 0.35)           // coral
        static let flame = Color(red: 1, green: 0.62, blue: 0.04)           // naranja
        static let list = Color(red: 0.62, green: 0.82, blue: 0.42)         // verde
        static let addon = Color(red: 0.79, green: 0.63, blue: 1)           // lila
        static let chart = Color(red: 1, green: 0.37, blue: 0.49)           // frambuesa
        static let trophy = Color(red: 1, green: 0.82, blue: 0.4)           // oro
    }

    /// El control completo de la TV (`TouchPad`, `RemoteKey`).
    enum Remote {
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
        static let padHeight: CGFloat = 200, keyHeight: CGFloat = 60
        /// Qué parte del alto de la pantalla toma el pad (en un iPhone grande crece).
        static let padShare: CGFloat = 0.25
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

    /// Medidas fijas.
    enum Size {
        /// La gota de los puntos de un carrusel: cuánto se alarga la activa y su resorte (respuesta y amortiguación).
        static let pageDotStretch: CGFloat = 2.6, pageDotSpring: Double = 0.38, pageDotDamping: Double = 0.62
        /// El logotipo arriba de Inicio (el tamaño de la letra de «orbital»).
        static let headerWordmark: CGFloat = 26
        /// Lo más que se encoge un número de «Tu año» para caber en su tarjeta.
        static let statScale: CGFloat = 0.6
        /// Cuánto hay que bajar para que el título grande se encoja (y el de Inicio diga otra cosa).
        static let titleCollapse: CGFloat = 8
        static let touchTarget = CGFloat(DesignTokens.Size.touchTarget), thumbSmall = CGFloat(DesignTokens.Size.thumbSmall)
        static let cardMax = CGFloat(DesignTokens.Size.cardMax), grabber = CGFloat(DesignTokens.Size.grabber), grabberHeight = CGFloat(DesignTokens.Size.grabberHeight)
        static let logo = CGFloat(DesignTokens.Size.logo)
        /// La letra de «orbital» en la marca grande (la bienvenida) y el planeta solo, junto a un título o en el widget.
        static let wordmark: CGFloat = 40, markSmall: CGFloat = 22
        static let platformLogo = CGFloat(DesignTokens.Size.platformLogo)
        static let rankNumber = CGFloat(DesignTokens.Size.rankNumber)
        /// La cifra de un Top 10: enorme y pesada; no crece con Dynamic Type (es un adorno, el puesto ya se dice en la etiqueta).
        /// Como la TV (`.card-ranked__number`): la letra de siempre en negrita y las cifras juntas (`--tracking-rank: -.08em`).
        static var rankFont: Font { .system(size: rankNumber, weight: .bold) }
        static let rankTracking = -rankNumber * 0.08
        /// El «10»: sus cifras más juntas y el póster encima de parte del cero (no empuja el póster ni se achata).
        static let rankTwoDigitsOverlap = rankNumber * 0.42
        static let logoHero = CGFloat(DesignTokens.Size.logoHero)
        /// El anillo de la pieza enfocada del mosaico y la línea fina de las demás.
        static let focusRing: CGFloat = 2.5, hairline: CGFloat = 0.5
        /// El alto del logo en la franja del mosaico.
        static let captionLogo: CGFloat = 34
        /// El arte redondo del accesorio «En la TV».
        static let accessoryArt: CGFloat = 38   // alto del póster en el accesorio de abajo
        /// La columna del símbolo en los renglones de una guía («Lo que puedes decir»): alinea los textos.
        static let iconColumn: CGFloat = 24
        /// El alto de un mosaico con arte (géneros de Explora).
        static let artTileHeight: CGFloat = 96
        /// Hasta cuántas temporadas se enseñan como filtros; con más, un menú.
        static let seasonChipsMax = 4
        /// Cuántos pósters de lo popular se piden al abrir la app (los del Top 10 de Buscar).
        static let searchPrefetch = 10
        /// El mejor resultado de Buscar, en grande.
        static let searchTopHeight: CGFloat = 200
        /// «Los siguientes N episodios» del panel de Descargar.
        static let downloadNext = 3
        /// Los puntos de un carrusel.
        static let pageDot = CGFloat(DesignTokens.Size.pageDot)
    }

    /// El widget «Lo siguiente para ti» (también lo compila la extensión de widgets): barra de avance, miniatura de los renglones,
    /// dónde empieza el velo inferior del póster y cada cuánto se pide recarga si la app no avisa.
    enum Widget {
        static let progressHeight = CGFloat(DesignTokens.Widget.progressHeight), thumbWidth = CGFloat(DesignTokens.Widget.thumbWidth)
        static let scrimStart = DesignTokens.Widget.scrimStart, scrimStartWide = DesignTokens.Widget.scrimStartWide
        static let logoHeight = CGFloat(DesignTokens.Widget.logoHeight), textShadowRadius = CGFloat(DesignTokens.Widget.textShadowRadius)
        static let fallbackRefresh = DesignTokens.Widget.fallbackRefreshHours * 3600
        /// La actividad en vivo de descargas: el póster (pixeles con que se guarda, ancho en la pantalla bloqueada y en la isla).
        static let activityPosterPixels: CGFloat = 240, activityPoster: CGFloat = 52, islandPoster: CGFloat = 44
        static let posterRadius: CGFloat = 8
    }

    /// El fondo de pantalla: tono del arte, estrellas del espacio vivo y el fundido del arte a sangre.
    enum Backdrop {
        /// Cuánto se mezcla el color del arte con el fondo de cada modo, y hasta dónde llega antes de fundirse con el fondo.
        static let darkMix = DesignTokens.Projection.darkMix, lightMix = DesignTokens.Projection.lightMix, fadeTo = DesignTokens.Projection.fadeTo
        static let tintFloor = DesignTokens.Backdrop.tintFloor
        /// Dónde empieza el velo sobre el arte, dónde llega a medio y (al pie) a fondo.
        static let scrimStart = DesignTokens.Backdrop.scrimStart, scrimMid = DesignTokens.Backdrop.scrimMid
        static let starCount = DesignTokens.Backdrop.starCount, starSeed = DesignTokens.Backdrop.starSeed
        static let starRadius = CGFloat(DesignTokens.Backdrop.starRadius), starOpacity = DesignTokens.Backdrop.starOpacity
        static let artFadeStart = DesignTokens.Backdrop.artFadeStart
        /// Un segundo brillo del mismo tono, abajo a un lado: lo de debajo del destacado no queda en negro liso.
        static let lowGlow: Double = 0.22
        static let lowGlowCenter = UnitPoint(x: 0.85, y: 0.75)
        static let lowGlowRadius: CGFloat = 420
        /// La ficha inmersiva (como un álbum en Música): toda la pantalla del tono del arte, que se hunde hacia el pie.
        static let immersiveDeep: Double = 0.55, immersiveGlow: Double = 0.35
        static let immersiveGlowRadius: CGFloat = 520
    }

    /// Esperas de la interfaz (nanosegundos para `Task.sleep`).
    enum Timing {
        /// Lo más que el pulgar espera en el destino de un salto antes de volver al avance real.
        static let seekPatience: UInt64 = 4_000_000_000
        /// Entre que se cierra una hoja y se abre otra (el resumen del juego tras cerrar su hoja).
        static let sheetHandoff: UInt64 = 600_000_000
        /// Cuánto espera una confirmación («¿Ver en la TV?») antes de cerrarse sola.
        static let confirm: UInt64 = 3_500_000_000
        static let controlsHide = UInt64(DesignTokens.Timing.controlsHide * 1e9), banner = UInt64(DesignTokens.Timing.banner * 1e9)
        /// Cuánto se queda el aviso «Pasó a tu Orbital» (con «Deshacer»).
        static let handoff = UInt64(8 * 1e9)
        static let searchDebounce = UInt64(DesignTokens.Timing.searchDebounce * 1e9), tick = UInt64(DesignTokens.Timing.tick * 1e9)
        static let longPressDelay = DesignTokens.Timing.longPressDelay
        /// Cada cuánto, como pronto, le pide iOS a la app mirar en segundo plano lo que dejó la TV (iOS decide si y cuándo corre).
        static let inboxRefresh: TimeInterval = 15 * 60
        /// Cuánto se queda a la vista el indicador de brillo o volumen tras soltar, antes de desvanecerse.
        static let gestureIndicatorHold = UInt64(DesignTokens.Timing.gestureIndicatorHold * 1e9)
        /// Quieto en el mosaico: a los 30 s el ambiente despierta solo; sobre una pieza, a los 2,2 s cobra vida.
        static let mosaicIdle = UInt64(DesignTokens.Mosaic.idleSeconds * 1e9), mosaicAlive = UInt64(DesignTokens.Mosaic.aliveSeconds * 1e9)
        static let mosaicDrift = UInt64(DesignTokens.Mosaic.driftTick * 1e9)
    }

    /// Tamaño de los pósters (relación 2:3, como en la TV).
    /// A qué tamaño (lado más largo, en puntos) se reduce cada imagen remota al bajarla (`RemoteImage`).
    enum Image {
        static let card: CGFloat = 200, mosaic: CGFloat = 192, logo: CGFloat = 240, platformLogo: CGFloat = 96, bleed: CGFloat = 480
        /// Basta una miniatura para sacar el color medio del fondo.
        static let tintPixels: CGFloat = 48
    }

    enum Poster {
        static let aspect = DesignTokens.Aspect.poster
        static let heroAspect = DesignTokens.Aspect.hero, stillAspect = DesignTokens.Aspect.still
        static let railWidth: CGFloat = 112
        static let gridMinimum: CGFloat = 100
        static let episodeThumbWidth: CGFloat = 122
        /// Una pieza ancha (16:9) de un riel: «Todo lo que sigues», episodios nuevos.
        static let stillWidth: CGFloat = 220
        static let heroHeight: CGFloat = 300
        /// El póster pequeño de «Viendo en la TV» (misma relación 2:3, más chico que el de la tira).
        static let nowPlayingWidth: CGFloat = 56
        /// La tarjeta «Desde la TV»: arte ancho con su logo, datos y acciones encima.
        static let fromTVHeight: CGFloat = 220
    }

    /// «Viendo en la TV»: cada cuánto se vuelve a dibujar la barra de avance mientras se interpola entre sondeos.
    enum NowPlaying {
        static let progressTick = DesignTokens.Timing.tick
        /// Opacidad de un botón mientras su acción sigue en vuelo (sin duplicar el toque).
        static let busyOpacity = CGFloat(DesignTokens.Opacity.faint)
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
