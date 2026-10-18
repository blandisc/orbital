import Foundation

/// Los valores de diseño de Orbital, sin SwiftUI (se prueban contra `design/tokens.json`, el mismo archivo que usa la TV;
/// la app los convierte a `Color`).
/// «Nada se crea suelto»: las pantallas usan estos tokens, no colores ni medidas a mano.
public enum DesignTokens {
    /// Paleta única: los mismos valores que `orbital/web/styles/palette.json`.
    public static let palette: [String: String] = [
        "ink-1000": "#070708", "ink-950": "#0c0c0e", "ink-900": "#131316", "ink-850": "#18181c", "ink-800": "#1e1e23",
        "ink-700": "#2a2a30", "ink-500": "#55555d", "ink-300": "#a3a3ab", "ink-200": "#cdcdd3", "paper": "#f5f4f0",
        "red-400": "#f0574d", "amber-300": "#f4c24d", "teal-300": "#5fd6c6",
        "pad-green": "#5cbf6d", "pad-red": "#e2514a", "pad-blue": "#4a8ae8", "pad-yellow": "#eec03a",
    ]

    /// Los colores por su papel, en modo oscuro (la paleta de la consola) y en modo claro. Las pantallas nunca usan la paleta
    /// directa: usan estos papeles (`DS.bg`, `DS.text`…), que cambian solos con el modo. El claro es «papel»: el mismo
    /// grafito de la consola invertido, con el teal oscurecido para leerse sobre papel (prueba de contraste en `DesignTests`).
    public enum Role: String, CaseIterable, Sendable {
        /// Fondo de pantalla y superficies (tarjetas, renglones agrupados) y la superficie elevada (placeholders, hojas).
        case background, surface, surfaceRaised
        /// Texto principal, secundario y terciario (el terciario también se lee: ≥ 4.5:1, como `--color-text-faint` de la TV,
        /// el blanco al 50 % sobre el fondo).
        case label, secondaryLabel, tertiaryLabel
        /// Solo adornos que no son texto que leer (la cifra grande del Top 10): `--color-decorative` en la TV.
        case decorative
        /// La acción principal (una por pantalla) y el texto sobre ella.
        case primary, onPrimary
        /// Avance, selección y foco: el papel, como la TV (`--color-focus`, las barras de avance). El color lo pone el arte
        /// (`ArtPalette`), no un acento fijo.
        case accent
        /// «En vivo» (TV en vivo): el único uso del teal, como `--color-live` en la TV.
        case live
        /// La luna de la marca (ícono y logotipo «orbital»), como `--color-brand-moon`: fija, la misma en los dos modos.
        case brandMoon
        /// Avisos.
        case warning, danger

        /// «#rrggbb» de cada modo.
        public var hex: (dark: String, light: String) {
            switch self {
            case .background: (palette["ink-950"]!, "#f6f5f1")
            case .surface: (palette["ink-850"]!, "#ffffff")
            case .surfaceRaised: (palette["ink-800"]!, "#ebe9e3")
            case .label: (palette["paper"]!, "#111113")
            case .secondaryLabel: (palette["ink-300"]!, "#5c5c64")
            case .tertiaryLabel: ("#868687", "#6b6b72")
            case .decorative: (palette["ink-500"]!, "#9a9aa1")
            case .primary: (palette["paper"]!, "#111113")
            case .onPrimary: (palette["ink-1000"]!, palette["paper"]!)
            case .accent: (palette["paper"]!, "#111113")
            case .live: (palette["teal-300"]!, "#0b7a6e")
            case .brandMoon: (palette["teal-300"]!, palette["teal-300"]!)
            case .warning: (palette["amber-300"]!, "#9a6200")
            case .danger: (palette["red-400"]!, "#c4362c")
            }
        }
    }

    /// Las capas translúcidas (líneas, rellenos, velos) se calculan sobre el color de texto de cada modo: blanco en oscuro y
    /// negro en claro, con las opacidades de `Opacity`. Los velos sobre el arte son siempre negros (el arte es la sala oscura).
    public enum Ink { public static let darkOverlay = "#ffffff", lightOverlay = "#000000", scrim = "#000000" }

    /// El tono del arte que ilumina la pantalla (Proyección): cuánto se mezcla el color medio del arte con el fondo de cada modo.
    /// En oscuro se hunde hacia el grafito; en claro se vuelve un velo de color muy suave sobre el papel.
    public enum Projection { public static let darkMix = 0.55, lightMix = 0.84, fadeTo = 0.62 }

    /// El color de cada plataforma («otra»: Apple TV+ y las demás, plata). Igual que `platforms` en design/tokens.json.
    public enum Platform {
        public static let hex: [String: String] = ["netflix": "#e60a14", "disney": "#456eff", "hbo": "#7a3dff", "prime": "#1a99ff",
                                                   "paramount": "#0063ff", "otra": "#c7c7d1"]
        public static func color(_ brand: String) -> String { hex[brand] ?? hex["otra"]! }
    }

    /// Contraste WCAG entre dos colores «#rrggbb» (1…21).
    public static func contrast(_ a: String, _ b: String) -> Double {
        func luminance(_ hex: String) -> Double {
            guard let c = rgb(hex: hex) else { return 0 }
            func channel(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
            return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b)
        }
        let (l1, l2) = (luminance(a), luminance(b))
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    /// Espacio (puntos): 4, 8, 12, 16, 20, 24, 32, 40, 56.
    public enum Space { public static let s1 = 4.0, s2 = 8.0, s3 = 12.0, s4 = 16.0, s5 = 20.0, s6 = 24.0, s8 = 32.0, s10 = 40.0, s14 = 56.0 }
    public enum Radius { public static let xs = 5.0, sm = 7.0, md = 10.0, lg = 13.0, xl = 18.0, xxl = 22.0, pill = 999.0 }
    /// Tamaños de letra (se escalan con Dynamic Type, que hace de «Tamaño del texto»).
    public enum TextSize { public static let xs = 11.0, sm = 12.5, md = 15.0, lg = 17.0, xl = 22.0, xxl = 28.0, display = 34.0 }
    /// Duraciones en segundos (las de la TV: `design/tokens.json`); con «Reducir movimiento» valen 0.
    public enum Motion { public static let fast = 0.14, base = 0.22, slow = 0.32, enter = 0.52, tint = 0.7 }
    public enum Opacity {
        public static let hairline = 0.09, fill = 0.10, fillStrong = 0.16, faint = 0.5, track = 0.2, scrim = 0.62
        public static let scrimStrong = 0.92, badge = 0.8, pressed = 0.8, disabled = 0.4, shrink = 0.85, subtitleShadow = 0.9
        /// El texto secundario sobre el velo del arte.
        public static let onArtSecondary = 0.82
        /// Por debajo de esta luminancia media un logo se considera oscuro y se pinta claro sobre el arte.
        public static let darkLogoLuminance = 0.3
        /// …salvo que más de esta parte de sus píxeles tenga color (es un logo de color, no uno negro).
        public static let colorfulLogoShare = 0.08
    }
    /// Subtítulos sobre el video: letra mínima, cuánto suben con los controles a la vista, espacio entre líneas
    /// (fracción de la letra), margen con el borde del video (fracción de su alto), sombra y contorno (fracción
    /// de la letra, para leerse sobre fondos claros).
    public enum Subtitle { public static let minFont = 15.0, liftWithControls = 72.0, lineGap = 0.15, edgeMargin = 0.05, shadowRadius = 0.08, outlineWidth = 0.06 }
    /// Medidas fijas (puntos): el mínimo táctil de iOS, miniaturas, tarjetas.
    public enum Size {
        public static let touchTarget = 44.0, thumbSmall = 48.0, cardMax = 320.0, grabber = 40.0, grabberHeight = 5.0, logo = 80.0, gaugeScale = 0.45
        /// El logo de una plataforma (Netflix, Disney+…) en un chip o un encabezado: siempre la misma altura, venga el logo
        /// cuadrado o apaisado.
        public static let platformLogo = 18.0
        /// La cifra enorme de un Top 10 (estilo Netflix), detrás del póster.
        public static let rankNumber = 132.0
        /// El logo del título en el destacado de Inicio y en la ficha (en una pieza del mosaico va `logo`): tope de alto; de ancho,
        /// `cardMax`. Es el mismo tope relativo que `.title__logo` en la TV (más grande que el de la ficha lateral).
        public static let logoHero = 96.0
        /// Los puntos de un carrusel (como el control de páginas de iOS).
        public static let pageDot = 7.0
    }
    /// El fondo de pantalla (`Backdrop`, como `--art-tint` y `.backdrop__space` en la TV): hasta dónde se aclara el tono del arte
    /// hacia abajo (mezcla con el grafito), las estrellas del espacio vivo (cuántas, cuánto miden, qué tan tenues) y desde dónde se
    /// funde el arte a sangre con el fondo (fracción de su alto).
    public enum Backdrop {
        public static let scrimStart = 0.0, scrimMid = 0.42
        public static let tintFloor = 0.5, starCount = 56, starRadius = 1.1, starOpacity = 0.35, starSeed = 7.0, artFadeStart = 0.6
    }
    /// Relaciones de aspecto de las imágenes.
    public enum Aspect { public static let poster = 2.0 / 3.0, hero = 16.0 / 11.0, still = 16.0 / 9.0 }
    /// Esperas de la interfaz (segundos).
    public enum Timing {
        public static let controlsHide = 4.0, banner = 4.0, searchDebounce = 0.3, tick = 1.0, longPressDelay = 0.4
        /// Cuánto se queda a la vista el indicador de brillo o volumen después de soltar, antes de desvanecerse.
        public static let gestureIndicatorHold = 1.0
    }
    /// Gestos del reproductor (brillo, volumen, buscar arrastrando, 2× manteniendo el dedo), como en Infuse.
    public enum Gesture {
        /// Puntos de arrastre antes de decidir si el gesto es horizontal o vertical (y de que el toque deje de ser toque).
        public static let axisThreshold = 12.0
        /// Arrastrar horizontalmente toda la pantalla vale esta fracción de la duración…
        public static let seekMaxFraction = 0.10
        /// …o este tope en segundos, lo que sea menor.
        public static let seekMaxSeconds = 180.0
    }
    /// El widget «Lo siguiente para ti»: imágenes reducidas (el widget no va a la red y su memoria es corta), cuánto se oscurece el
    /// tono del arte (como `ArtTint`), la calidad del JPEG, cada cuánto se pide recarga si la app no avisa, el alto de la barra de
    /// avance y el ancho de la miniatura de los renglones del widget mediano (puntos).
    public enum Widget {
        public static let maxImagePixels = 300.0, jpegQuality = 0.7, tintMix = 0.55, fallbackRefreshHours = 6.0
        /// Segundos que el app espera antes de preparar el widget (no compite con la pantalla que se está abriendo).
        public static let publishDelay = 2.0
        public static let progressHeight = 3.0, thumbWidth = 44.0
        /// Dónde empieza el velo inferior del póster (fracción de su alto) para que el título se lea.
        public static let scrimStart = 0.25, scrimStartWide = 0.05
        /// Alto del logo del título y radio de la sombra del texto sobre el arte (contraste del dato, como en el destacado de Inicio).
        public static let logoHeight = 28.0, textShadowRadius = 3.0
    }
    /// El mosaico de «Para ti» (como `foryou-mosaic.js` en la TV): cuánto se ensancha la columna enfocada,
    /// cuánto se espera quieto antes del ambiente o de «cobrar vida», y a qué ritmo sube sola cada columna.
    public enum Mosaic {
        /// Carriles: 3 en un iPhone a lo alto (2 si es angosto, menos de `compactWidth` puntos), 5 a lo ancho o en iPad; todas
        /// las piezas del mismo tamaño (`uniform`), para que ninguna quede tan chica que no se vea.
        public static let columnsPortrait = 3, columnsCompact = 2, columnsLandscape = 5, compactWidth = 360.0
        public static let uniform = true
        /// La enfocada crece un poco y las demás se apagan (como `.foryou-mosaic` en la TV: opacidad .5 y `saturate(.6)`; en el
        /// teléfono un poco menos apagadas, porque se ven a la vez más cerca).
        public static let focusScale = 1.04, dimmedOpacity = 0.6, dimmedSaturation = 0.6
        public static let growRatio = 1.8
        public static let idleSeconds = 3.0, aliveSeconds = 2.2, driftTick = 1.0
        public static let driftPerSecond = 16.0
        /// Inercia al soltar el mosaico, como una lista de iOS: cuánto de la velocidad queda tras un segundo (0.998 por ms,
        /// la desaceleración normal de `UIScrollView`), cuándo se detiene (pt/s) y cada cuánto se mueve (s).
        public static let flingDecayPerSecond = 0.135, flingStopSpeed = 20.0, flingFrame = 1.0 / 120
        /// Puntos por segundo de cada columna en el ambiente, en el mismo orden que `DRIFT` de la TV (se repite si hay más columnas).
        public static let driftPattern: [Double] = [16, 12, 19, 14, 17, 13]
        /// Cuánto tarda la pieza quieta en acercarse («cobra vida», `--duration-alive` de la TV).
        public static let aliveZoomSeconds = 9.0
        public static let bufferHeight = 360.0
        /// Piezas fuera de pantalla que aún se pintan, × el alto del mosaico (arriba y abajo); el resto no se renderiza.
        public static let cullMargin = 0.5
        /// La fila enfocada, en alto, × el ancho de su columna: con las columnas angostas del iPhone
        /// hace falta más que en la TV (0,64) para que quepan etiqueta + logo + dato sin encimarse.
        public static let focusedRowRatio = 1.6
    }
}

/// Convierte «#rrggbb» en sus componentes 0…1.
public func rgb(hex: String) -> (r: Double, g: Double, b: Double)? {
    var text = hex.trimmingCharacters(in: .whitespaces)
    if text.hasPrefix("#") { text.removeFirst() }
    guard text.count == 6, let value = Int(text, radix: 16) else { return nil }
    return (Double((value >> 16) & 0xff) / 255, Double((value >> 8) & 0xff) / 255, Double(value & 0xff) / 255)
}
