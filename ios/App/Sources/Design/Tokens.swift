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

    /// Un color que cambia con el modo claro u oscuro y con «Aumentar contraste» (`DesignTokens.Role`).
    static func role(_ role: DesignTokens.Role) -> Color {
        adaptive(dark: role.hex.dark, light: role.hex.light, highDark: role.highContrastHex.dark, highLight: role.highContrastHex.light)
    }
    /// Un papel solo del iPhone (`DesignTokens.PhoneRole`), con la misma regla.
    static func role(_ role: DesignTokens.PhoneRole) -> Color {
        adaptive(dark: role.hex.dark, light: role.hex.light, highDark: role.highContrastHex.dark, highLight: role.highContrastHex.light)
    }

    /// Una capa translúcida sobre el color de texto de cada modo (blanco en oscuro, negro en claro).
    static func overlay(_ opacity: Double) -> Color {
        adaptive(dark: DesignTokens.Ink.darkOverlay, light: DesignTokens.Ink.lightOverlay, opacity: opacity)
    }

    /// Con «Aumentar contraste» usa `highDark`/`highLight` (si no se dan, los mismos de siempre).
    static func adaptive(   // la usan también Tokens+Player y Tokens+Screens
dark: String, light: String, highDark: String? = nil, highLight: String? = nil, opacity: Double = 1) -> Color {
        func ui(_ hex: String) -> UIColor {
            let c = rgb(hex: hex) ?? (0, 0, 0)
            return UIColor(red: c.r, green: c.g, blue: c.b, alpha: opacity)
        }
        let (d, l) = (ui(dark), ui(light))
        let (hd, hl) = (ui(highDark ?? dark), ui(highLight ?? light))
        return Color(uiColor: UIColor { traits in
            let high = traits.accessibilityContrast == .high
            return traits.userInterfaceStyle == .light ? (high ? hl : l) : (high ? hd : d)
        })
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
    /// Desde el 30 oct 2026 (decisión de Fernando, docs/producto/inicio-benchmark/): el porqué va en el turquesa de Orbital,
    /// el mismo papel que «En vivo» (con su versión oscura en modo claro, que sí se lee sobre el papel). Solo para el porqué
    /// de una sección (`DSSectionHead`): las etiquetas que no son porqué (datos, «Siguiente») siguen en `DS.warning`.
    static let eyebrow = role(.live)
    /// La luna de la marca (turquesa, igual en los dos modos).
    static let brandMoon = role(.brandMoon)
    /// Lo que salió bien o ya está (visto, descargado, conectado): el papel, como la TV.
    static let good = role(.accent)
    /// Un interruptor prendido que tiene que leerse de lejos (los avisos de estrenos): el verde del sistema.
    static let switchOn = Color.green
    /// Lo que ya está o ya salió («Hoy», el listón «Nuevo», «conectado», «Este va bien» de los subtítulos) y la letra sobre
    /// él: cambian con el modo para leerse en los dos (≥ 4.5:1, `DesignTests`).
    static let success = role(.success)
    static let onSuccess = role(.onSuccess)
    static let warning = role(.warning)
    /// El azul de Orbital: el del puntito del logo (Fernando, 31 oct 2026). Los íconos de los rótulos de Para ti, el
    /// calendario y las horas de «Lo que ves».
    static let orbitalBlue = brandMoon   // el color del puntito del logo (Fernando, 31 oct 2026)
    static let danger = role(.danger)
    static let hairline = overlay(DesignTokens.Opacity.hairline)
    static let fill = overlay(DesignTokens.Opacity.fill)
    static let fillStrong = overlay(DesignTokens.Opacity.fillStrong)
    static let track = overlay(DesignTokens.Opacity.track)
    /// El botón principal sólido de la ficha: negro (el color del texto) en claro y, en oscuro, invertido a blanco, que es lo
    /// que más resalta sobre la sala oscura. La letra va con el color del fondo.
    static let solidPrimary = text
    static let onSolidPrimary = bg

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
    static let subtitleBox = Color.black.opacity(DesignTokens.Subtitle.boxOpacity)               // «Caja oscura»
    static let subtitleTranslucent = Color.black.opacity(DesignTokens.Subtitle.translucentOpacity) // «Translúcido»

    // MARK: Elevación (sombras)
    /// Las sombras de las piezas sobre el contenido: color, difuminado y cuánto bajan. Se usan con `.shadow(DS.Elevation.low)`.
    struct Elevation {
        var color: Color, radius: CGFloat, y: CGFloat = 0
        /// Un borde apenas despegado (texto, logos y tarjetas sobre el arte).
        static let low = Elevation(color: DS.scrim, radius: DS.Space.s1)
        /// Una pieza levantada que proyecta hacia abajo.
        static let medium = Elevation(color: DS.scrim, radius: DS.Space.s2, y: DS.Space.s1)
        /// Lo mismo, más marcado.
        static let high = Elevation(color: DS.scrimStrong, radius: DS.Space.s2, y: DS.Space.s1)
        /// La misma sombra con otro color (o `.clear` para quitarla sin mover nada) o con otra caída.
        /// Lo que flota encima de todo (la carta del mazo, el momento de la repisa): la más honda.
        static let floating = Elevation(color: DS.scrimStrong, radius: DS.Space.s4, y: DS.Space.s2)
        func color(_ color: Color) -> Elevation { Elevation(color: color, radius: radius, y: y) }
        func drop(_ y: CGFloat) -> Elevation { Elevation(color: color, radius: radius, y: y) }
    }

    /// Un brillo de color alrededor de una pieza (la cifra de un Top 10, un sello, lo elegido): no es sombra, no baja.
    /// Se usan con `.glow(color, .soft)`. Dos fuerzas, nada en medio.
    enum Glow {
        case soft, strong
        var radius: CGFloat { self == .soft ? DS.Space.s2 : DS.Space.s4 }
    }

    // MARK: Línea y opacidad
    /// Los grosores de toda línea (D5, 31 oct 2026): la fina de un separador, un contorno, lo elegido y el foco. Lo elegido
    /// va siempre en el color del texto (blanco en oscuro), nunca turquesa: `.dsSelectionRing(_:)`.
    enum Stroke {
        static let hairline: CGFloat = 0.5, regular: CGFloat = 1, selected: CGFloat = 2, focus: CGFloat = 3
    }

    /// Las opacidades con papel (D16): no se escribe otra. `disabled` lo que no se puede tocar; `dimmed` lo que aún no
    /// llega o ya pasó (un estreno próximo, un día pasado, las otras opciones); `faint` lo que casi no se ve (un fantasma,
    /// lo descartado); `pressed` al tocar; `selectedFill` el relleno de lo elegido.
    enum Opacity {
        static let disabled = DesignTokens.Opacity.disabled, dimmed = 0.6, faint = 0.35, pressed = DesignTokens.Opacity.pressed
        static let selectedFill = 0.12
    }

    // MARK: Espacio y forma
    /// Los cuatro espacios de toda pantalla (Fernando, 31 oct 2026, decisión 2), medidos desde donde termina lo que se ve
    /// (el pie de un póster cuenta): del título a lo suyo, entre subsecciones, entre secciones y al pie.
    /// Arriba de cada pantalla, `titleToContent`. `DesignRulesTests.testScreensKeepTheLayoutRhythm` revisa que el primer contenedor de cada pantalla los use.
    enum Layout {
        static let titleToContent = Space.s3, betweenSubsections = Space.s6, betweenSections = Space.s10, screenBottom = Space.s14
        static let screenTop = Space.s3
    }

    enum Space {
        static let s1 = CGFloat(DesignTokens.Space.s1), s2 = CGFloat(DesignTokens.Space.s2), s3 = CGFloat(DesignTokens.Space.s3)
        static let s4 = CGFloat(DesignTokens.Space.s4), s5 = CGFloat(DesignTokens.Space.s5), s6 = CGFloat(DesignTokens.Space.s6)
        static let s8 = CGFloat(DesignTokens.Space.s8), s10 = CGFloat(DesignTokens.Space.s10), s14 = CGFloat(DesignTokens.Space.s14)
        /// Margen lateral de las pantallas.
        static let gutter = s4
        /// De la orilla de arriba de una hoja (con su asa) al primer título, en toda hoja que arma su propio encabezado
        /// (`dsSheetContent()`). Antes cada una tenía el suyo: 16 el calendario, 20 «Decide por mí», 24 «Tu Orbital».
        static let sheetTop = s6
    }

    /// Las hojas: lo más que crece una hoja alta (por debajo de la altura completa, que iOS vuelve opaca).
    enum Sheet { static let maxShare: CGFloat = 0.86 }

    enum Radius {
        static let xs = CGFloat(DesignTokens.Radius.xs), sm = CGFloat(DesignTokens.Radius.sm), md = CGFloat(DesignTokens.Radius.md)
        static let lg = CGFloat(DesignTokens.Radius.lg), xl = CGFloat(DesignTokens.Radius.xl), xxl = CGFloat(DesignTokens.Radius.xxl)
        static let pill = CGFloat(DesignTokens.Radius.pill)
        /// Las placas chicas de texto o ícono (calidad, fuente, «4K»): una sola esquina (antes 4, 5 y 7).
        static let tag = xs
        /// El logo de una app o plataforma: la esquina del ícono de iOS, en proporción a su lado (antes 4, 8 y 10 fijos).
        static func logo(_ side: CGFloat) -> CGFloat { side * logoShare }
        static let logoShare: CGFloat = 0.225
    }

    // MARK: Tipografía (con Dynamic Type: hace de «Tamaño del texto»)
    enum Typeface {
        case xs, sm, md, lg, xl, xxl, display
        /// El tope de letra del campo de búsqueda del sistema (con letra de accesibilidad se dibujaba vacío).
        static let searchFieldMax = DynamicTypeSize.xxxLarge
        var style: Font.TextStyle {
            switch self { case .xs: .caption2; case .sm: .caption; case .md: .subheadline; case .lg: .headline; case .xl: .title2; case .xxl: .title; case .display: .largeTitle }
        }
    }

    static func font(_ face: Typeface, weight: Font.Weight = .regular) -> Font { .system(face.style, design: .default).weight(weight) }

    /// Recetas de texto de Proyección: cada pantalla usa estas, no tamaños sueltos. SF Pro con Dynamic Type; los datos
    /// (tiempos, temporadas, tamaños) con cifras tabulares (todas del mismo ancho), como `tabular-nums` en la TV.
    /// La escala de la app, una por papel (no se escriben tamaños sueltos):
    /// | Papel        | Receta       | Tamaño (Dynamic Type)  | Dónde                                              |
    /// |--------------|--------------|------------------------|----------------------------------------------------|
    /// | Pantalla     | (barra nativa) / `display` | largeTitle, negrita | «Para ti», «Buscar»; las cifras héroe         |
    /// | Título de hoja | `title`    | title, negrita         | `DSSheetHeader`                                    |
    /// | Sección      | `groupLabel` | caption, negrita, MAYÚSCULAS | `DSSectionHead(level: .section)` (pinta `DSChapterLabel`): agrupa varias cosas |
    /// | Subsección   | `section`    | title2, negrita        | `DSSectionHead` de una fila o estante, con su porqué |
    /// | Porqué       | `eyebrow`    | footnote, seminegrita, turquesa | solo arriba de una subsección o de una portada |
    /// | Pieza        | `cardTitle`  | headline               | el nombre en una tarjeta o renglón                 |
    /// | Cuerpo       | `body`       | body                   | lo que explica                                     |
    /// | Secundario   | `secondary`  | subheadline            | datos bajo un título                               |
    /// | Pie          | `footnote`   | footnote               | notas, ayuda                                       |
    /// | Etiqueta     | `caption`    | caption                | placas, «T2 E5», leyendas                          |
    /// | Dato         | `data`       | footnote tabular       | números que se comparan                            |
    /// | Rótulo       | `label`      | footnote, seminegrita  | botones chicos, datos que resaltan                 |
    /// | Rótulo grande| `labelLarge` | subheadline, seminegrita | el valor de un control, un nombre en un renglón  |
    /// | Placa        | `badge`      | caption, negrita       | «4K», «Nuevo», cifras en una placa                 |
    /// | Grupo        | `groupLabel` | caption, negrita       | el rótulo de un grupo (`DSGroupLabel`, en mayúsculas) |
    /// | Cifra        | `stat`       | largeTitle, gruesa, tabular | las cifras grandes de Lo que ves, el mazo     |
    enum TextRecipe {
        case display, title, section, cardTitle, body, secondary, footnote, caption, eyebrow, data
        /// Las que antes se armaban torciendo otra con `.weight` (D12): un rótulo o botón chico (`label`), uno mediano
        /// (`labelLarge`), una placa (`badge`), el rótulo de un grupo (`groupLabel`, en mayúsculas con `DSGroupLabel`) y una
        /// cifra grande (`stat`, tabular).
        case label, labelLarge, badge, groupLabel, stat
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
            case .label: .system(.footnote, design: .default).weight(.semibold)
            case .labelLarge: .system(.subheadline, design: .default).weight(.semibold)
            case .badge, .groupLabel: .system(.caption, design: .default).weight(.bold)
            case .stat: .system(.largeTitle, design: .default).weight(.heavy).monospacedDigit()
            }
        }
    }

    /// El texto que se recorre cuando no cabe (`MarqueeText`): espera, avanza despacio hasta el final, espera y regresa.
    enum Marquee {
        /// Lo que se queda quieto antes de avanzar y al llegar al final.
        static let rest: Duration = .seconds(3), hold: Duration = .seconds(1.5)
        /// Puntos por segundo: se lee mientras avanza.
        static let speed: Double = 30
        /// El desvanecido de las orillas mientras no se ve entero.
        static let fade = Space.s3
        /// El paso de ida o de regreso: parejo, sin acelerar (se va leyendo).
        static func travel(_ seconds: Double) -> Animation { .linear(duration: seconds) }
    }

    /// La palomita de «Visto» (`WatchedMark`): su tamaño, el grosor del trazo y el aire de la palomita dentro del círculo.
    enum WatchedMark {
        static let size: CGFloat = 24, line: CGFloat = 2, checkInset = DS.Space.s2
    }

    /// Tirar para actualizar (`RefreshOrbit`): la marca, la luna, su órbita (fracción del tamaño, aplastada como el anillo),
    /// lo que tarda una vuelta, cuánto hay que jalar y lo chica que empieza la marca.
    enum Refresh {
        static let mark: CGFloat = 34, moon: CGFloat = 6, orbit: CGFloat = 0.5, orbitSquash: CGFloat = 0.4
        static let lap: Double = 1.1, threshold: CGFloat = 80, startScale: CGFloat = 0.6
        /// El hueco que se abre arriba mientras actualiza (la marca y su aire).
        static let slot: CGFloat = 50
    }

    /// El arte con cuerpo (`Tiltable`): cuánto hay que mantener antes de inclinar, cuánto movimiento llega al tope, el tope en
    /// grados, la perspectiva, lo que se encoge agarrado y el brillo (opacidad y lo que recorre). Sin hundido en los pósters:
    /// en iOS 27 un estilo de botón propio retenía el dedo y la fila no se deslizaba (HomePicksUITests, 2 nov 2026).
    enum Tilt {
        static let hold: Double = 0.25, reach: CGFloat = 140, maxDegrees: Double = 9, perspective: CGFloat = 0.5, held: CGFloat = 0.98
        static let shine: Double = 0.28, shineTravel: CGFloat = 160
    }

    // MARK: Movimiento (sin movimiento con «Reducir movimiento»)
    enum Motion {
        /// Lo que tarda el salto de la barra de pestañas: lo que se recarga al volver a una pestaña espera esto.
        static let tabSettle: Duration = .milliseconds(450)
        static func base(_ reduce: Bool) -> Animation? { reduce ? nil : .easeOut(duration: DesignTokens.Motion.base) }
        static func enter(_ reduce: Bool) -> Animation? { reduce ? nil : .easeOut(duration: DesignTokens.Motion.enter) }
        static func tint(_ reduce: Bool) -> Animation? { reduce ? nil : .easeInOut(duration: DesignTokens.Motion.tint) }
        static func spring(_ reduce: Bool) -> Animation? { reduce ? nil : .spring(duration: DesignTokens.Motion.slow, bounce: 0.2) }
        /// Un resorte sin rebote, para lo que cambia de alto y de forma a la vez (el control al estirarse o encogerse, los
        /// sustos al abrirse): sigue a la hoja en lugar de ir por su lado.
        static func smooth(_ reduce: Bool) -> Animation? { reduce ? nil : .smooth(duration: DesignTokens.Motion.slow) }
        /// Un rebote más marcado y corto: elegir un mosaico («¿Qué vemos?» › Más filtros).
        static func pop(_ reduce: Bool) -> Animation? { reduce ? nil : .spring(duration: DesignTokens.Motion.base, bounce: 0.45) }
        /// Solo un fundido de opacidad: se vale también con «Reducir movimiento» (no mueve nada). Lo que antes se animaba
        /// con `DS.Motion.…(false)` (cambiar de pestaña de texto, de periodo, de filtro) va con esto.
        static let fade: Animation = .easeInOut(duration: DesignTokens.Motion.base)
        /// El arte que respira: parejo y muy lento (16 s, como la TV), para que no se note que se mueve, solo que está vivo.
        static let breathe: Animation = .linear(duration: 16)
        /// Lo que se va de una fila (lo que terminaste de ver) se encoge a esto mientras se desvanece.
        static let leaveScale: CGFloat = 0.85
        /// Los estantes que llegan: suben esto, cada uno este tiempo después del anterior, y a partir del quinto ya no esperan más.
        static let entranceRise: CGFloat = 16, entranceStep: Double = 0.06, entranceMax = 4
        /// Cuánto hay que empujar más allá de la orilla de una fila para el golpe en la mano, y qué tan fuerte.
        static let edgeOverscroll: CGFloat = 24, edgeIntensity: Double = 0.7
        /// Avance parejo, sin acelerar ni frenar: un anillo de progreso que se llena.
        static let steady: Animation = .linear(duration: DesignTokens.Motion.slow)
        /// Un salto corto y firme, sin rebote: algo que se acomoda en su lugar (una carta que vuelve, un riel que se reordena).
        static func snap(_ reduce: Bool) -> Animation? { reduce ? nil : .snappy(duration: DesignTokens.Motion.base) }
        /// Lo que se descubre despacio (el momento de la repisa, un número que aparece): sale y frena.
        static func reveal(_ reduce: Bool) -> Animation? { reduce ? nil : .easeOut(duration: DesignTokens.Motion.slow) }
        /// Una tarjeta que entra a una lista (Viendo en la TV, Desde la TV): baja un poco con un fundido y se va solo con el
        /// fundido. Con «Reducir movimiento», solo el fundido.
        static func appear(_ reduce: Bool) -> AnyTransition {
            reduce ? .opacity : .asymmetric(insertion: .opacity.combined(with: .offset(y: noticeDrop)), removal: .opacity)
        }
        /// El aviso de pantalla bloqueada entra con un fundido (también con «Reducir movimiento»).
        static func lockNoticeIn() -> Animation { .easeOut(duration: DesignTokens.Motion.base) }
        /// Lo que tarda en encogerse al círculo del candado.
        static let lockShrinkDuration = 0.3
        /// El candado sube y se desvanece. Con «Reducir movimiento» se desvanece en su sitio.
        static let lockRiseDuration = 0.4
        static func lockRise(_ reduce: Bool) -> Animation? { .easeOut(duration: reduce ? DesignTokens.Motion.base : lockRiseDuration) }
        /// Los avisos sobre la barra de pestañas (`Toast`, `BannerView`, la pastilla de calificar): el que llega baja un poco
        /// desde arriba con un fundido, y el que se va solo se desvanece (no brincan desde la orilla de abajo). Con «Reducir
        /// movimiento», solo el fundido.
        static let noticeDrop: CGFloat = -DS.Space.s4
        static func notice(_ reduce: Bool) -> AnyTransition {
            reduce ? .opacity : .asymmetric(insertion: .opacity.combined(with: .offset(y: noticeDrop)), removal: .opacity)
        }
    }

    /// La marca de Orbital (la de la TV: icons.js · mark y status-bar.css «La marca»). Todo en las unidades de su caja de 32
    /// (el planeta y el anillo) o en em de la palabra (la luna, el interletrado, el tamaño de la marca junto a la palabra).
    /// La píldora de una plataforma (`PlatformBadge`): el logo de la app a la izquierda, con sus esquinas.
    enum PlatformBadge { static let logo: CGFloat = 16, logoRadius = Radius.logo(16) }
    /// El listón de la esquina (`DSCornerRibbon`): la caja que recorta la esquina, el largo de la banda, dónde cruza su
    /// centro (en cada eje, desde la esquina) y el interletrado del texto en mayúsculas; el de siempre y el compacto (los
    /// pósters de 50 pt del widget). Los dos con el mismo giro y el mismo brillo.
    enum Ribbon {
        struct Size { let corner: CGFloat, length: CGFloat, center: CGFloat, tracking: CGFloat }
        static let regular = Size(corner: 60, length: 104, center: 22, tracking: 0.8)
        static let compact = Size(corner: 38, length: 66, center: 14, tracking: 0.4)
        static let angle: Double = -45, shine: Double = 0.28
    }

    enum Brand {
        static let box: CGFloat = 32
        static let planetRadius: CGFloat = 7.2, planetStroke: CGFloat = 2.8
        /// El anillo (la marca pulida del 1 nov 2026, la del ícono: scripts/make_icon.py): una pincelada centrada en el planeta e
        /// inclinada `ringTilt` grados, de `ringRadius` de punta a centro; su orilla de abajo baja `ringOuter` y la de arriba
        /// `ringInner` (gruesa al frente, en punta en las orillas). `ringGap`: el hueco que le abre al planeta; `ringReveal`, el
        /// trazo que la descubre al dibujarse.
        static let ringRadius: CGFloat = 14.51, ringOuter: CGFloat = 4.96, ringInner: CGFloat = 2.34, ringTilt: Double = -18.8   // ds-exception: en unidades de la caja de 32 (el dibujo de la marca)
        static let ringGap: CGFloat = 1.8, ringReveal: CGFloat = 5   // ds-exception: en unidades de la caja de 32 (el dibujo de la marca)
        /// La luna: su ancho, lo que sube sobre la línea de base y lo que la separa de la palabra (em).
        static let moon: CGFloat = 0.26, moonRise: CGFloat = 0.62, moonGap: CGFloat = 0.1   // ds-exception: en em de la palabra (la marca)
        /// De dónde cae la luna al aparecer (em) y lo chica que empieza.
        static let moonFromX: CGFloat = -0.9, moonFromY: CGFloat = -0.7, moonFromScale: CGFloat = 0.2
        /// «orbital»: interletrado apretado (em); la marca mide 1.7 veces la letra y va a media letra de ella.
        static let tracking: CGFloat = -0.03, markScale: CGFloat = 1.7, markGap: CGFloat = 0.2   // ds-exception: en em de la palabra (la marca)
        /// Al arrancar: el anillo se dibuja en este tiempo y la luna cae después (s), como en la TV (--duration-land).
        static let drawSeconds = 0.76, moonDelay = 0.76 * 1.7
        /// La letra de «orbital»: Sora SemiBold, la misma de la TV (--font-brand), del tamaño de la marca (Resources/Fonts).
        static func wordFont(_ size: CGFloat) -> Font { .custom("Sora-SemiBold", fixedSize: size) }
    }

    /// Medidas fijas.
    enum Size {
        /// Cuánto se desvanece la orilla de una tira horizontal que no cabe (`edgeFade`).
        static let edgeFade: CGFloat = 28
        /// La gota de los puntos de un carrusel: cuánto se alarga la activa y su resorte (respuesta y amortiguación).
        static let pageDotStretch: CGFloat = 2.6
        /// El logotipo arriba de Inicio (el tamaño de la letra de «orbital»).
        /// La marca de Inicio. Con 32 (a la par del título grande de Para ti, Descargas y Buscar) la barra no cabía en un iPhone de
        /// 375 pt y el perfil se iba al «···»: en un teléfono angosto va sin el planeta y a `headerWordmarkCompact`.
        static let headerWordmark: CGFloat = 32, headerWordmarkCompact: CGFloat = 28, compactWidth: CGFloat = 400
        /// Lo más ancho que crece un selector segmentado: en el iPad y la Mac no se estira a toda la ventana (como los de Apple).
        /// El iPhone (440 pt como mucho) no lo alcanza.
        static let segmentedMax: CGFloat = 480
        /// Lo más que se encoge un número de «Tu año» para caber en su tarjeta.
        static let statScale: CGFloat = 0.6
        /// Una sinopsis más larga que esto (caracteres) se corta con «más».
        static let synopsisFold = 160
        /// Cuántas tarjetas de «En tendencia» se piden de antemano (fondo y logo).
        static let heroPrefetch = 3
        /// Cuánto hay que bajar para que el título grande se encoja (y el de Inicio diga otra cosa).
        static let titleCollapse: CGFloat = 8
        /// Cuánto hay que deslizar en un sentido para que la barra de Buscar se esconda (al bajar) o vuelva (al subir).
        static let barScrollHide: CGFloat = 12
        static let touchTarget = CGFloat(DesignTokens.Size.touchTarget), thumbSmall = CGFloat(DesignTokens.Size.thumbSmall)
        /// Cuánto puede encogerse un título de sección largo («Top 10 en Paramount+») antes de cortarse: así no brinca a dos renglones.
        static let titleShrink: CGFloat = 0.8
        static let cardMax = CGFloat(DesignTokens.Size.cardMax), grabber = CGFloat(DesignTokens.Size.grabber), grabberHeight = CGFloat(DesignTokens.Size.grabberHeight)
        static let logo = CGFloat(DesignTokens.Size.logo)
        /// La letra de «orbital» en la marca grande (la bienvenida) y el planeta solo, junto a un título o en el widget.
        static let wordmark: CGFloat = 40, markSmall: CGFloat = 22
        /// Lo que una marca redonda (el jitomate) baja de la línea del título: como la «o», que cae un poco abajo de la línea,
        /// así su cuerpo queda centrado con las mayúsculas en vez de verse flotando.
        static let markOvershoot: CGFloat = 1.5
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
        static let focusRing: CGFloat = 2.5, hairline = Stroke.hairline
        /// El alto del logo en la franja del mosaico.
        static let captionLogo: CGFloat = 34
        /// El arte redondo del accesorio «En la TV».
        static let accessoryArt: CGFloat = 32   // alto del póster en el accesorio de abajo (como el de Música)
        /// La columna del símbolo en los renglones de una guía («Lo que puedes decir»): alinea los textos.
        static let iconColumn: CGFloat = 24
        /// El alto de un mosaico con arte (géneros de Explora).
        static let artTileHeight: CGFloat = 96
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
        static let posterRadius = Radius.md
        /// La cuenta regresiva («1:12:24») tiene ancho fijo: un `Text(timerInterval:)` sin él se estira a todo lo que puede (en
        /// la isla compacta salía enorme y en medio). En la compacta, en vez de texto, un anillo chico que se llena solo.
        static let timerWidth: CGFloat = 64, compactRing: CGFloat = 18
        /// «Lo nuevo de lo tuyo» mediano: cuántos pósters caben (y de ellos, cuántos de lo que ya salió) y su ancho.
        static let releasesShown = 5, releasesOut = 2
        static let releasePoster: CGFloat = 50
        /// Lo más que se encoge un rótulo corto antes de cortarse («Madrugada», «Miércoles»).
        static let labelShrink: CGFloat = 0.8
        /// «Aquí» y «En la TV»: el alto (y, solo el ícono, el ancho) de cada botón.
        static let button: CGFloat = 30
        /// «Viendo en la TV»: el ancho de cada botón (−10 s, pausa, +10 s).
        static let tvKey: CGFloat = 64
        /// «Un Simpson del día»: el ancho de la tele en el mediano, su proporción (con la antena), cuánto del ancho es pantalla,
        /// el marco y la esquina del mueble (fracciones del ancho) y la antena (alto, fracción del ancho; abertura en grados).
        static let simpsonsTV: CGFloat = 150, simpsonsTVAspect: CGFloat = 1.2, simpsonsScreenShare: CGFloat = 0.66
        static let simpsonsGap: CGFloat = 0.06, simpsonsBodyRadius: CGFloat = 0.12   // ds-exception: la tele de Los Simpson se dibuja como el aparato
        static let simpsonsAntenna: CGFloat = 0.22, simpsonsAntennaAngle: Double = 28
        /// «Mosaico de una lista»: columnas y pósters por columna del muro (mediano y grande), cuánto más ancho que el widget es
        /// el muro (inclinado no deja huecos en las esquinas), cuánto baja una columna sí y una no, y dónde empieza el velo.
        static let listColumnsMedium = 7, listRowsMedium = 3, listColumnsLarge = 6, listRowsLarge = 5
        static let listWallOverscan: CGFloat = 1.25, listStagger: CGFloat = 0.5, listVeilStart = 0.45
    }

    /// El fondo de pantalla: tono del arte, estrellas del espacio vivo y el fundido del arte a sangre.
    enum Backdrop {
        /// Cuánto se mezcla el color del arte con el fondo de cada modo, y hasta dónde llega antes de fundirse con el fondo.
        static let lightMix = DesignTokens.Projection.lightMix, fadeTo = DesignTokens.Projection.fadeTo
        static let tintFloor = DesignTokens.Backdrop.tintFloor
        /// Dónde empieza el velo sobre el arte, dónde llega a medio y (al pie) a fondo.
        static let scrimStart = DesignTokens.Backdrop.scrimStart, scrimMid = DesignTokens.Backdrop.scrimMid
        static let artFadeStart = DesignTokens.Backdrop.artFadeStart
        /// Un segundo brillo del mismo tono, abajo a un lado: lo de debajo del destacado no queda en negro liso.
        static let lowGlow: Double = 0.22
        static let lowGlowCenter = UnitPoint(x: 0.85, y: 0.75)
        static let lowGlowRadius: CGFloat = 420
        /// La ficha inmersiva (como un álbum en Música): toda la pantalla del tono del arte, que se hunde hacia el pie.
        static let immersiveDeep: Double = 0.55, immersiveGlow: Double = 0.35
        static let immersiveGlowRadius: CGFloat = 520
    }

    /// Tamaño de los pósters (relación 2:3, como en la TV).
    /// A qué tamaño (lado más largo, en puntos) se reduce cada imagen remota al bajarla (`RemoteImage`).
    enum Image {
        /// `bleed`: el arte a sangre (la ficha, «En tendencia»). Un fondo 16:9 que llena un marco alto se dibuja más ancho que la
        /// pantalla (en la ficha de un iPhone, ~800 pt): con 480 se veía agrandado y suave.
        static let card: CGFloat = 200, mosaic: CGFloat = 192, logo: CGFloat = 240, platformLogo: CGFloat = 96, bleed: CGFloat = 800
        /// Una tarjeta ancha de lado a lado (la portada de un estreno, `CoverCard`): con `card` se pedía la versión chica (480 px).
        static let wide: CGFloat = 420
        /// El desenfoque de la copia que rellena el marco cuando la imagen va completa (`ArtFit.whole`).
        static let wholeBlur: CGFloat = 28
        /// Basta una miniatura para sacar el color medio del fondo.
        static let tintPixels: CGFloat = 48
        /// La imagen de un aviso («Ya está para ver»): el lado más largo y la calidad del JPEG.
        static let notification = 1000, notificationQuality: CGFloat = 0.82
    }

    enum Poster {
        static let aspect = DesignTokens.Aspect.poster
        static let stillAspect = DesignTokens.Aspect.still
        /// El póster de una tira: 112 pt en el iPhone; en una ventana ancha (iPad, Mac, desde `gridWideWidth`) más grande: con
        /// el tamaño del teléfono se veían diminutos en una pantalla de 13". Se lee al pintar: cambia solo al cambiar la ventana.
        static var railWidth: CGFloat { WindowMetrics.size.width >= gridWideWidth ? railWidthWide : railWidthCompact }
        static let railWidthCompact: CGFloat = 112, railWidthWide: CGFloat = 148
        static let gridMinimum: CGFloat = 100
        /// `DSPosterGrid`: columnas fijas que llenan el ancho (3; 4 en pantallas anchas; 2 con letra de accesibilidad) y
        /// desde qué ancho de contenido cuenta como ancha (iPhone horizontal, iPad).
        static let gridColumns = 3, gridColumnsWide = 4, gridColumnsLarge = 2
        static let gridWideWidth: CGFloat = 600
        /// En ventanas anchas (iPad, Mac) caben más columnas: ninguna celda pasa de este ancho (con 4 fijas, en un iPad
        /// horizontal cada póster medía ~280 pt).
        static let gridCellMax: CGFloat = 160
        /// El ancho mínimo de un mosaico de género en Buscar (dos por renglón en todo iPhone; más en el iPad).
        static let genreTileMin: CGFloat = 160
        /// Cuántas columnas en `width` (el ancho del contenido, con sus márgenes).
        static func gridColumns(for width: CGFloat) -> Int {
            guard width >= gridWideWidth else { return gridColumns }
            let inner = width - DS.Space.gutter * 2 + DS.Space.s3
            return max(gridColumnsWide, Int(inner / (gridCellMax + DS.Space.s3)))
        }
        /// Las cuadrículas «de dos en dos» del iPhone (Top 10 completo, tus listas, Seguir viendo): en una ventana ancha (iPad,
        /// Mac) dos columnas hacían pósters de ~500 pt; ahí van tantas como quepan de al menos `wideMin`. El iPhone (vertical
        /// siempre, menos de `gridWideWidth`) queda igual: dos.
        static func pairColumns(spacing: CGFloat, wideMin: CGFloat = pairWideMin) -> [GridItem] {
            guard WindowMetrics.size.width >= gridWideWidth else { return Array(repeating: GridItem(.flexible(), spacing: spacing), count: 2) }
            return [GridItem(.adaptive(minimum: wideMin), spacing: spacing, alignment: .top)]
        }
        static let pairWideMin: CGFloat = 170, stillWideMin: CGFloat = 280
        static let episodeThumbWidth: CGFloat = 122
        /// Una tarjeta de «Próximos estrenos»: dos y un pedazo (`peek`) de la tercera, en cualquier ancho (con un ancho fijo, en un
        /// iPhone de 375 pt las dos llenaban la pantalla y parecía una cuadrícula que terminaba a 5 pt del borde).
        static let peek: CGFloat = 28
        /// Una pieza ancha (16:9) de un riel: «Todo lo que sigues», episodios nuevos.
        static var stillWidth: CGFloat { WindowMetrics.size.width >= gridWideWidth ? stillWidthWide : stillWidthCompact }
        static let stillWidthCompact: CGFloat = 220, stillWidthWide: CGFloat = 280
        static let heroHeight: CGFloat = 300
        /// El póster pequeño de «Viendo en la TV» (misma relación 2:3, más chico que el de la tira).
        static let nowPlayingWidth: CGFloat = 56
        /// La tarjeta «Desde la TV»: arte ancho con su logo, datos y acciones encima.
        static let fromTVHeight: CGFloat = 220
    }

}

extension View {
    /// Una sombra del sistema de diseño (`DS.Elevation`).
    func shadow(_ elevation: DS.Elevation) -> some View {
        shadow(color: elevation.color, radius: elevation.radius, y: elevation.y)
    }
}

extension MatchedTransitionSourceConfiguration {
    /// La misma sombra en el origen de un zoom (el póster del que sale la ficha).
    func shadow(_ elevation: DS.Elevation) -> some MatchedTransitionSourceConfiguration {
        shadow(color: elevation.color, radius: elevation.radius, y: elevation.y)
    }
}
