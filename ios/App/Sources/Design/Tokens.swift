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
        static let sideMargin: CGFloat = 36, height: CGFloat = 430
        static let radius: CGFloat = 28, spacing: CGFloat = 4
        /// Lo que pierde una tarjeta a un lugar de distancia: tamaño, nitidez y luz.
        static let sideShrink: CGFloat = 0.12, sideBlur: CGFloat = 5, sideDim: Double = 0.28
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

    /// El color de cada plataforma (su tarjeta en abanico, el brillo de su logo y de los números de sus rankings).
    enum PlatformTint {
        static func color(_ brand: String) -> Color {
            switch brand {
            case "netflix": Color(red: 0.9, green: 0.04, blue: 0.08)
            case "disney": Color(red: 0.27, green: 0.43, blue: 1)
            case "hbo": Color(red: 0.48, green: 0.24, blue: 1)
            case "prime": Color(red: 0.1, green: 0.6, blue: 1)
            case "paramount": Color(red: 0, green: 0.39, blue: 1)
            default: Color(red: 0.78, green: 0.78, blue: 0.82)   // Apple TV+ y las demás: plata
            }
        }
    }

    /// «Tus plataformas»: la tarjeta con su top 3 en abanico y su página de rankings.
    enum PlatformFan {
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
        /// Alto del pad táctil y de cada tecla.
        static let padHeight: CGFloat = 200, keyHeight: CGFloat = 60
        /// Qué parte del alto de la hoja estirada toma el pad (en un iPhone grande crece en vez de dejar un hueco abajo).
        static let padShare: CGFloat = 0.37
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
        static let touchTarget = CGFloat(DesignTokens.Size.touchTarget), thumbSmall = CGFloat(DesignTokens.Size.thumbSmall)
        static let cardMax = CGFloat(DesignTokens.Size.cardMax), grabber = CGFloat(DesignTokens.Size.grabber), grabberHeight = CGFloat(DesignTokens.Size.grabberHeight)
        static let logo = CGFloat(DesignTokens.Size.logo)
        /// La letra de «orbital» en la marca grande (la bienvenida) y el planeta solo, junto a un título o en el widget.
        static let wordmark: CGFloat = 40, markSmall: CGFloat = 22
        /// Un ícono de lista junto al título de su estante (`ListIcon`).
        static let listIcon: CGFloat = 22
        static let platformLogo = CGFloat(DesignTokens.Size.platformLogo)
        static let rankNumber = CGFloat(DesignTokens.Size.rankNumber)
        /// La cifra de un Top 10: enorme y pesada; no crece con Dynamic Type (es un adorno, el puesto ya se dice en la etiqueta).
        static var rankFont: Font { .system(size: rankNumber, weight: .black, design: .rounded) }
        static let logoHero = CGFloat(DesignTokens.Size.logoHero)
        /// El anillo de la pieza enfocada del mosaico y la línea fina de las demás.
        static let focusRing: CGFloat = 2.5, hairline: CGFloat = 0.5
        /// El alto del logo en la franja del mosaico.
        static let captionLogo: CGFloat = 34
        /// El arte redondo del accesorio «En la TV».
        static let accessoryArt: CGFloat = 32
        /// La columna del símbolo en los renglones de una guía («Lo que puedes decir»): alinea los textos.
        static let iconColumn: CGFloat = 24
        /// El alto de un mosaico con arte (géneros de Explora).
        static let artTileHeight: CGFloat = 96
        /// Hasta cuántas temporadas se enseñan como filtros; con más, un menú.
        static let seasonChipsMax = 4
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
    }

    /// Esperas de la interfaz (nanosegundos para `Task.sleep`).
    enum Timing {
        static let controlsHide = UInt64(DesignTokens.Timing.controlsHide * 1e9), banner = UInt64(DesignTokens.Timing.banner * 1e9)
        static let searchDebounce = UInt64(DesignTokens.Timing.searchDebounce * 1e9), tick = UInt64(DesignTokens.Timing.tick * 1e9)
        static let longPressDelay = DesignTokens.Timing.longPressDelay
        /// Cada cuánto, como pronto, le pide iOS a la app mirar en segundo plano lo que dejó la TV (iOS decide si y cuándo corre).
        static let inboxRefresh: TimeInterval = 15 * 60
        /// Cuánto se queda a la vista el indicador de brillo o volumen tras soltar, antes de desvanecerse.
        static let gestureIndicatorHold = UInt64(DesignTokens.Timing.gestureIndicatorHold * 1e9)
        /// Quieto en el mosaico: a los 30 s el ambiente despierta solo; sobre una pieza, a los 2,2 s cobra vida.
        static let mosaicIdle = UInt64(DesignTokens.Mosaic.idleSeconds * 1e9), mosaicAlive = UInt64(DesignTokens.Mosaic.aliveSeconds * 1e9)
        static let mosaicDrift = UInt64(DesignTokens.Mosaic.driftTick * 1e9)
        static let mosaicFlingFrame = UInt64(DesignTokens.Mosaic.flingFrame * 1e9)
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
        /// El póster chico de un renglón (listas con puesto, descargas).
        static let rowWidth: CGFloat = 36
        /// Una pieza ancha (16:9) de un riel: «También tenías», episodios nuevos.
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
