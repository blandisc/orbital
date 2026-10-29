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

    /// Una capa translúcida sobre el color de texto de cada modo (blanco en oscuro, negro en claro).
    static func overlay(_ opacity: Double) -> Color {
        adaptive(dark: DesignTokens.Ink.darkOverlay, light: DesignTokens.Ink.lightOverlay, opacity: opacity)
    }

    /// Con «Aumentar contraste» usa `highDark`/`highLight` (si no se dan, los mismos de siempre).
    private static func adaptive(dark: String, light: String, highDark: String? = nil, highLight: String? = nil, opacity: Double = 1) -> Color {
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
    static let eyebrow = role(.warning)
    /// La luna de la marca (turquesa, igual en los dos modos).
    static let brandMoon = role(.brandMoon)
    /// Lo que salió bien o ya está (visto, descargado, conectado): el papel, como la TV.
    static let good = role(.accent)
    /// Un interruptor prendido que tiene que leerse de lejos (los avisos de estrenos): el verde del sistema.
    static let switchOn = Color.green
    /// Lo que confirmas que va bien («Este va bien» de los subtítulos): el mismo verde.
    static let success = switchOn
    static let warning = role(.warning)
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

    /// Subtítulos: medidas relativas a la letra o al video (la letra misma sale de Ajustes › Tamaño de subtítulos).
    enum Subtitle {
        static let minFont = CGFloat(DesignTokens.Subtitle.minFont), liftWithControls = CGFloat(DesignTokens.Subtitle.liftWithControls)
        /// Con la píldora «2×» a la vista en horizontal: la línea queda justo por encima de ella (el video va a
        /// sangre y la píldora, dentro del área segura).
        static let liftWithSpeedPill: CGFloat = 120
        static let lineGap = CGFloat(DesignTokens.Subtitle.lineGap), edgeMargin = CGFloat(DesignTokens.Subtitle.edgeMargin)
        static let shadowRadius = CGFloat(DesignTokens.Subtitle.shadowRadius), outlineWidth = CGFloat(DesignTokens.Subtitle.outlineWidth)
        static let raisedMargin = CGFloat(DesignTokens.Subtitle.raisedMargin)
        static let boxPaddingH = CGFloat(DesignTokens.Subtitle.boxPaddingH), boxPaddingV = CGFloat(DesignTokens.Subtitle.boxPaddingV)
        static let boxRadius = CGFloat(DesignTokens.Subtitle.boxRadius)
    }

    /// Brillo, volumen y buscar arrastrando (como Infuse): el umbral que decide el eje (el mismo número que usa
    /// `PlayerGestures`, la aritmética pura) y el tamaño del indicador.
    enum Gesture {
        /// La franja de cada orilla donde el doble toque salta ±10 s (al centro, pausa o sigue).
        /// Doble toque: tres zonas parejas (izquierda −10 s, centro pausa, derecha +10 s), como YouTube.
        static let edgeShare: CGFloat = 1.0 / 3.0
        /// Tras un doble toque, cada toque más del mismo lado suma 10 s (+10, +20, +30) mientras no pase este rato.
        static let skipChain: TimeInterval = 0.7
        /// ×2: deslizar hacia abajo esta distancia, desde donde apoyaste el dedo, lo fija. Si hasta el borde
        /// de abajo queda menos, se usa ese hueco, pero nunca menos de `fastForwardLockDragMin`. Hacia arriba,
        /// esta misma distancia lo quita al momento (sin esperar a soltar).
        static let fastForwardLockDrag: CGFloat = 60
        /// Lo menos que puede medir el deslizamiento hacia abajo cuando el dedo ya está cerca del borde.
        static let fastForwardLockDragMin: CGFloat = 40
        /// A cuántos segundos del destino ya se da por llegado un salto (el pulgar vuelve a seguir el avance).
        static let seekArrived: Double = 2
        static let axisThreshold = CGFloat(DesignTokens.Gesture.axisThreshold)
        /// La onda del doble toque: la media luna sale de la orilla y ocupa este tanto del alto del video.
        static let rippleHeight: CGFloat = 1.5
        static let indicatorBarHeight: CGFloat = 120
        static let indicatorBarWidth: CGFloat = 4
        /// Lo que mide el indicador además de la barra (el ícono y su espacio), y lo más corta que puede quedar.
        static let indicatorChrome: CGFloat = 32
        static let indicatorBarMin: CGFloat = 48
        /// Qué tan lejos de la orilla va (en vertical, casi pegado; en horizontal, fuera de la zona de la cámara y los botones).
        static let indicatorInsetPortrait: CGFloat = DS.Space.s3, indicatorInsetLandscape: CGFloat = DS.Space.s8
        /// Un toque de un dedo y uno de dos tan juntos son el mismo toque (s).
        static let twoFingerTapGuard: TimeInterval = 0.35
        /// Un pellizco que termina este rato después de girar el teléfono es el agarre, no un pellizco (no cambia el zoom).
        static let pinchAfterRotationGuard: TimeInterval = 1.0
        /// Un pellizco tiene que durar al menos esto (un toque con dos dedos es instantáneo) y no contar si hubo un toque con dos
        /// dedos en este rato (iOS los mide como si abrieras los dedos).
        static let pinchMinDuration: TimeInterval = 0.15, pinchTapGuard: TimeInterval = 0.6
        /// La burbuja de buscar no se acerca más que esto a los bordes de la pantalla.
        static let seekBubbleSideMargin: CGFloat = 64
        /// De la burbuja (su centro) al borde inferior: justo encima de la barra de avance (que vive dentro del
        /// `padding(DS.Space.s6)` de `controls`, con la hilera de tiempos debajo de la barra).
        static let seekBubbleBottomInset: CGFloat = 128
        /// La píldora «2×» en horizontal, dentro del área segura (igual que los controles): el borde de abajo
        /// queda un `s3` por encima de la hilera de tiempos y de la barra (`padding` de `controls` + `scrubHit`).
        static var fastForwardPillBottomInset: CGFloat {
            DS.Space.s6 + DS.PlayerPanel.scrubHit + DS.PlayerPanel.scrubTimes + DS.Space.s3
        }
        /// «Recortar» en vertical, con los controles a la vista: encima de la barra (aire de abajo, «Saltar intro», la propia
        /// barra y sus tiempos).
        static var fastForwardPillFillInset: CGFloat {
            DS.Space.s8 + DS.Size.touchTarget + DS.Space.s3 + DS.PlayerPanel.scrubHit + DS.PlayerPanel.scrubTimes + DS.Space.s3
        }
    }

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
        func color(_ color: Color) -> Elevation { Elevation(color: color, radius: radius, y: y) }
        func drop(_ y: CGFloat) -> Elevation { Elevation(color: color, radius: radius, y: y) }
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
        /// El tope de letra del campo de búsqueda del sistema (con letra de accesibilidad se dibujaba vacío).
        static let searchFieldMax = DynamicTypeSize.xxxLarge
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
        /// Un resorte sin rebote, para lo que cambia de alto y de forma a la vez (el control al estirarse o encogerse, los
        /// sustos al abrirse): sigue a la hoja en lugar de ir por su lado.
        static func smooth(_ reduce: Bool) -> Animation? { reduce ? nil : .smooth(duration: DesignTokens.Motion.slow) }
        /// Un rebote más marcado y corto: elegir un mosaico («¿Qué vemos?» › Más filtros).
        static func pop(_ reduce: Bool) -> Animation? { reduce ? nil : .spring(duration: DesignTokens.Motion.base, bounce: 0.45) }
        /// El aviso de pantalla bloqueada entra con un fundido (también con «Reducir movimiento»).
        static func lockNoticeIn() -> Animation { .easeOut(duration: DesignTokens.Motion.base) }
        /// Se encoge al círculo del candado. Con «Reducir movimiento» no hay movimiento: solo el fundido de salida.
        static let lockShrinkDuration = 0.3
        static func lockShrink(_ reduce: Bool) -> Animation? { reduce ? nil : .easeInOut(duration: lockShrinkDuration) }
        /// El candado sube y se desvanece. Con «Reducir movimiento» se desvanece en su sitio.
        static let lockRiseDuration = 0.4
        static func lockRise(_ reduce: Bool) -> Animation? { .easeOut(duration: reduce ? DesignTokens.Motion.base : lockRiseDuration) }
    }

    /// La marca de Orbital (la de la TV: icons.js · mark y status-bar.css «La marca»). Todo en las unidades de su caja de 32
    /// (el planeta y el anillo) o en em de la palabra (la luna, el interletrado, el tamaño de la marca junto a la palabra).
    /// La píldora de una plataforma (`PlatformBadge`): el logo de la app a la izquierda, con sus esquinas.
    enum PlatformBadge { static let logo: CGFloat = 16, logoRadius: CGFloat = 4 }

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

    enum Brand {
        static let box: CGFloat = 32
        static let planetRadius: CGFloat = 7.2, planetStroke: CGFloat = 2.8, ringStroke: CGFloat = 2.1
        /// El anillo, un poco más tenue que el planeta.
        /// La luna: su ancho, lo que sube sobre la línea de base y lo que la separa de la palabra (em).
        static let moon: CGFloat = 0.26, moonRise: CGFloat = 0.62, moonGap: CGFloat = 0.1
        /// De dónde cae la luna al aparecer (em) y lo chica que empieza.
        static let moonFromX: CGFloat = -0.9, moonFromY: CGFloat = -0.7, moonFromScale: CGFloat = 0.2
        /// «orbital»: interletrado apretado (em); la marca mide 1.7 veces la letra y va a media letra de ella.
        static let tracking: CGFloat = -0.035, markScale: CGFloat = 1.7, markGap: CGFloat = 0.2
        /// Al arrancar: el anillo se dibuja en este tiempo y la luna cae después (s), como en la TV (--duration-land).
        static let drawSeconds = 0.76, moonDelay = 0.76 * 1.7
        /// La letra de «orbital» (en la TV, Segoe UI Variable Display): SF Pro Rounded en negrita, del tamaño de la marca.
        static func wordFont(_ size: CGFloat) -> Font { .system(size: size, weight: .bold, design: .rounded) }
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

    /// El reproductor: el video en vertical, «Audio y subtítulos» (a la derecha en horizontal, bajo el video en vertical) y los controles.
    enum PlayerPanel {
        /// El video en vertical, al arrastrarlo: lo más arriba que sube (debajo de la barra de ✕ y el nombre: botón de 44 y
        /// su aire) y lo que deja libre abajo para los controles (la barra, «Saltar intro», ±10, el botón grande y la pista).
        static let portraitTopClearance: CGFloat = 60, portraitControlsReserve: CGFloat = 260
        /// Lo más cuadrado que se le da espacio en vertical (4:3, la tele de antes); algo más angosto ya va con franjas.
        static let portraitMinAspect: Double = 4.0 / 3.0
        /// La agarradera del video en vertical: la rayita, la franja de abajo que la toma (y lo que se mete sobre el video).
        /// «Audio y subtítulos»: cuántos idiomas de otra versión se ofrecen junto a las pistas de este archivo.
        static let otherVersionsShown = 2
        /// Sin conexión, cuántos idiomas más (de los que sí hay) salen junto a Español e Inglés en Subtítulos.
        static let offlineExtraLanguages = 2
        /// La agarradera va dentro del borde de abajo del video (sobre un velo): la rayita, a cuánto del borde, el alto del velo, la
        /// franja que la toma (dentro del video, desde abajo, y un poco por fuera) y el aire hasta la barra de avance.
        static let handleGrab: CGFloat = 40, handleBelow: CGFloat = 12, handleGap: CGFloat = 12
        static let handleReach: CGFloat = 12
        /// Cuántas funciones da el video un brinquito (hacia abajo y de regreso) para enseñar que se mueve, y de qué tamaño (parte del alto).
        static let moveHintTimes = 3
        static let moveNudge: Double = 0.025
        /// Al arrastrarlo: la sombra que lo levanta.
        static let liftShadow: CGFloat = 24
        /// VoiceOver: cuánto sube o baja el video cada vez (parte del alto).
        static let voiceOverStep: Double = 0.1
        /// Subtítulos rápidos: ancho máximo del panel.
        static let dockWidth: CGFloat = 560
        /// Vertical con «Recortar»: cuánto del alto ocupan los controles abajo (los subtítulos suben por encima).
        static let portraitFillControlsShare: CGFloat = 0.3
        /// El globo del «⋯» entra un poco más chico.
        static let lockScale: CGFloat = 0.9
        /// El aviso de pantalla bloqueada: el círculo al que se encoge el candado, y cuánto sube al irse.
        static let lockNoticeIcon: CGFloat = 36, lockNoticeRise: CGFloat = 28
        static let width: CGFloat = 420, radius: CGFloat = 30, rowRadius: CGFloat = 16, icon: CGFloat = 32
        /// En horizontal, lo más que ocupa el panel de la derecha (parte del ancho), para que en iPhone chicos quede video.
        static let widthShare: CGFloat = 0.55
        /// «Episodios»: el ancho de la imagen de cada episodio y qué tan tenue se ve uno que no se puede poner (sin descargar).
        static let episodeThumb: CGFloat = 112, unavailableOpacity = 0.4
        /// «Siguiente» en los controles aparece al llegar a esta parte del episodio (antes no estorba).
        static let nextAt = 0.9
        /// El ancho del nombre del tamaño de subtítulos («Mediano») entre − y +: no brinca al cambiar.
        static let sizeValue: CGFloat = 72
        /// Tamaños de letra de muestra («Aa») para chico, mediano y grande.
        static let sampleSizes: [String: CGFloat] = ["small": 12, "medium": 15, "large": 19]
        /// En vertical: dónde va el centro del video (parte de la altura; se mueve arrastrando) y entre qué límites.
        static let portraitCenter: CGFloat = -1, portraitCenterRange: ClosedRange<CGFloat> = 0.2...0.62
        /// Mientras no lo mueves (`portraitCenter` < 0), el video queda a esta distancia bajo el área segura: la misma en todos los
        /// iPhone (antes era una fracción del alto y en un Pro Max quedaba cientos de puntos más abajo que en un SE).
        static let portraitTop: CGFloat = 24
        /// En vertical sin controles a la vista, el video se centra.
        /// El botón de reproducir, más grande que ±10 (lo que más se toca).
        static let playButton: CGFloat = 76, playGlyph: CGFloat = 30, sideButton: CGFloat = 56
        /// ±10: la flecha en círculo, sin fondo (el botón grande es el único con círculo).
        static let skipGlyph: CGFloat = 32
        /// La barra de avance fina: el riel, la perilla (crece al arrastrar) y el alto que ocupa (se toca en
        /// `DS.Size.touchTarget`: la zona táctil sobresale arriba y abajo).
        static let scrubTrack: CGFloat = 3, scrubTrackActive: CGFloat = 10, scrubHit: CGFloat = 32
        /// El punto de la barra (quieta y arrastrando) y a qué altura sobre la barra va la burbuja del minuto (su centro).
        static let scrubKnob: CGFloat = 12, scrubKnobActive: CGFloat = 22, scrubBubbleLift: CGFloat = 48
        /// Las rayitas del fin de la intro y del inicio de los créditos: su grosor y cuánto sobresalen de la barra; la hilera de
        /// tiempos bajo la barra.
        static let scrubTickWidth: CGFloat = 1.5, scrubTickReach: CGFloat = 3, scrubTimes: CGFloat = 16
        /// El menú del «⋯»: su ancho.
        static let menuWidth: CGFloat = 272
        /// «Siguiente episodio»: el ancho de la imagen del episodio y el anillo de la cuenta atrás en «Ver ahora».
        static let upNextThumb: CGFloat = 96, ring: CGFloat = 22, ringWidth: CGFloat = 2.5
        /// El degradado oscuro de arriba (detrás del nombre y el episodio), para leerlos sobre un video claro.
        static let topScrimHeight: CGFloat = 170
        /// El cuadro que se guarda al irse a segundo plano (para tenerlo a la vista al volver): lo más grande que se guarda.
        static let frozenFrameMax = CGSize(width: 1920, height: 1080)
        /// El fondo ambiente en vertical: la imagen chica (se difumina, no hace falta más), cuánto se difumina y qué tan visible es.
        static let ambientImage: CGFloat = 200, ambientBlur: CGFloat = 60, ambientOpacity = 0.5
    }

    /// «Modo iPod» del reproductor vertical: un iPod Classic blanco o negro (la caja, la pantalla con su marco y la rueda).
    /// Colores fijos a propósito: son los del aparato, no cambian con el modo claro u oscuro (se elige la cara).
    enum IPod {
        // La caja.
        static let whiteTop = Color(red: 0.96, green: 0.96, blue: 0.95), whiteBottom = Color(red: 0.88, green: 0.88, blue: 0.87)
        static let blackTop = Color(red: 0.17, green: 0.17, blue: 0.18), blackBottom = Color(red: 0.05, green: 0.05, blue: 0.06)
        // La pantalla: el marco negro, el fondo claro, la barra «Reproduciendo» y el avance azul.
        static let bezelColor = Color(red: 0.06, green: 0.06, blue: 0.06)
        static let lcd = Color(red: 0.97, green: 0.97, blue: 0.97)
        static let lcdText = Color(red: 0.07, green: 0.07, blue: 0.07), lcdMuted = Color(red: 0.28, green: 0.28, blue: 0.28)
        static let barTop = Color(red: 0.99, green: 0.99, blue: 0.99), barBottom = Color(red: 0.79, green: 0.81, blue: 0.84)
        static let barLine = Color(red: 0.55, green: 0.59, blue: 0.63)
        static let fillTop = Color(red: 0.56, green: 0.76, blue: 0.96), fillBottom = Color(red: 0.18, green: 0.5, blue: 0.82)
        /// La pantalla del iPod negro: todo oscuro (para ver de noche), con las letras claras.
        static let lcdDark = Color(red: 0.09, green: 0.09, blue: 0.1)
        static let lcdDarkText = Color(red: 0.93, green: 0.93, blue: 0.93), lcdDarkMuted = Color(red: 0.66, green: 0.66, blue: 0.68)
        static let barDarkTop = Color(red: 0.24, green: 0.24, blue: 0.26), barDarkBottom = Color(red: 0.12, green: 0.12, blue: 0.13)
        static let barDarkLine = Color(red: 0.3, green: 0.3, blue: 0.32)
        // La rueda: la cara, su orilla, el botón del centro y las letras (MENU, ⏮ ⏭ ▶❚❚), en blanco y en negro.
        static let wheelWhiteTop = Color(red: 1, green: 1, blue: 1), wheelWhiteBottom = Color(red: 0.91, green: 0.91, blue: 0.9)
        static let wheelWhiteEdge = Color(red: 0.8, green: 0.8, blue: 0.79), labelWhite = Color(red: 0.45, green: 0.45, blue: 0.45)
        static let centerWhiteTop = Color(red: 0.92, green: 0.92, blue: 0.91), centerWhiteBottom = Color(red: 0.98, green: 0.98, blue: 0.97)
        static let wheelBlackTop = Color(red: 0.23, green: 0.23, blue: 0.24), wheelBlackBottom = Color(red: 0.13, green: 0.13, blue: 0.14)
        static let wheelBlackEdge = Color(red: 0.03, green: 0.03, blue: 0.03), labelBlack = Color(red: 0.8, green: 0.8, blue: 0.8)
        static let centerBlackTop = Color(red: 0.08, green: 0.08, blue: 0.09), centerBlackBottom = Color(red: 0.18, green: 0.18, blue: 0.19)
        // Medidas: margen a los lados, marco, esquinas, la barra de arriba, lo de abajo del video y la rueda.
        static let inset: CGFloat = 12, bezel: CGFloat = 6, bezelRadius: CGFloat = 14, lcdRadius: CGFloat = 8
        static let statusHeight: CGFloat = 26, infoHeight: CGFloat = 92, progressHeight: CGFloat = 10, line: CGFloat = 1
        /// La rueda nunca baja de este ancho (en veces el del teléfono): hasta ahí puede crecer el video.
        static let wheelMinShare: CGFloat = 0.52
        /// La rueda: qué parte del ancho ocupa, el botón del centro (parte del diámetro) y dónde van las letras (desde la orilla).
        static let wheelShare: CGFloat = 0.74, centerShare: CGFloat = 0.38, labelReach: CGFloat = 0.11
        /// Cada muesca de la rueda (en grados) busca 10 s; girando rápido (muescas a menos de `fastNotch` s), un minuto.
        static let notchDegrees: Double = 30, fastNotch: Double = 0.06, fastStep: Double = 60
        static let menuTracking: CGFloat = 1.5
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
        static let markHeight: CGFloat = 18
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
        /// El sello de dónde viene una lista (Trakt, Stremio, tu Orbital).
        static let stremio = Color(red: 0.54, green: 0.35, blue: 0.67), orbital = Color(red: 0.24, green: 0.48, blue: 0.85)
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

    /// Medidas fijas.
    enum Size {
        /// Cuánto se desvanece la orilla de una tira horizontal que no cabe (`edgeFade`).
        static let edgeFade: CGFloat = 28
        /// La gota de los puntos de un carrusel: cuánto se alarga la activa y su resorte (respuesta y amortiguación).
        static let pageDotStretch: CGFloat = 2.6, pageDotSpring: Double = 0.38, pageDotDamping: Double = 0.62
        /// El logotipo arriba de Inicio (el tamaño de la letra de «orbital»).
        static let tabBarClearance: CGFloat = 76   // lo que ocupa la barra de pestañas (los avisos de abajo van encima)
        /// La marca de Inicio. Con 32 (a la par del título grande de Para ti, Descargas y Buscar) la barra no cabía en un iPhone de
        /// 375 pt y el perfil se iba al «···»: en un teléfono angosto va sin el planeta y a `headerWordmarkCompact`.
        static let headerWordmark: CGFloat = 32, headerWordmarkCompact: CGFloat = 28, compactWidth: CGFloat = 400
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
        /// La cuenta regresiva («1:12:24») tiene ancho fijo: un `Text(timerInterval:)` sin él se estira a todo lo que puede (en
        /// la isla compacta salía enorme y en medio). En la compacta, en vez de texto, un anillo chico que se llena solo.
        static let timerWidth: CGFloat = 64, compactRing: CGFloat = 18
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

    /// Los avisos (`Toast`).
    enum Toast {
        /// El alto de la cápsula de la salida («Deshacer», «Reintentar»).
        static let actionHeight: CGFloat = 32
        /// El borde del que te necesita (ámbar) o del que avisa que algo se perdió (rojo): su color, tenue.
        static let toneStroke = 0.4, strokeWidth: CGFloat = 1
        /// Lo que hay que deslizar hacia abajo para quitarlo, y lo más ancho que se pone (en iPad u horizontal no cruza la pantalla).
        static let swipe: CGFloat = 12, maxWidth: CGFloat = 520
        /// Cuántos avisos esperan detrás del que tiene salida (los de más se descartan: ya no vienen al caso).
        static let queueLimit = 3
        /// Antes de esto (segundos), el aviso de pasar a la TV dice «desde el principio» y no «desde 0:12».
        static let fromStartUnder: Double = 30
    }

    /// Esperas de la interfaz (nanosegundos para `Task.sleep`).
    enum Timing {
        /// De vuelta de segundo plano: cada cuánto se mira si el video ya está para quitar el cuadro guardado.
        static let frozenFramePoll: UInt64 = 100_000_000
        /// Cuánto espera una lista abierta (un premio) antes de dar por hecho que no llegará y mostrar el vacío.
        static let listGiveUp: UInt64 = 15_000_000_000
        /// Lo más que el pulgar espera en el destino de un salto antes de volver al avance real.
        static let seekPatience: UInt64 = 4_000_000_000
        /// Cuánto espera una confirmación («¿Ver en la TV?») antes de cerrarse sola.
        static let confirm: UInt64 = 3_500_000_000
        static let controlsHide = UInt64(DesignTokens.Timing.controlsHide * 1e9), banner = UInt64(DesignTokens.Timing.banner * 1e9)
        /// El giro de la pantalla tarda esto en asentarse. (Cuándo sale la carga lo decide `PlayerPresentation`.)
        static let rotationSettle = UInt64(0.5 * 1e9)
        /// Un toque en este rato después de que los controles empezaron a esconderse los vuelve a mostrar.
        static let controlsFadeGrace: TimeInterval = 0.4
        /// Cuánto se queda un aviso con salida («Sigue en tu Orbital · Deshacer», «Bajando · Otra»).
        static let toastAction = UInt64(8 * 1e9)
        static let searchDebounce = UInt64(DesignTokens.Timing.searchDebounce * 1e9), tick = UInt64(DesignTokens.Timing.tick * 1e9)
        static let longPressDelay = DesignTokens.Timing.longPressDelay
        /// ×2: cuánto mantener el dedo en la mitad derecha para que arranque (casi al instante, como YouTube).
        /// Fijarlo es deslizar hacia abajo sin soltar; hacia arriba lo quita y vuelve a la velocidad previa.
        static let fastForwardStart = 0.3
        /// Cada cuánto, como pronto, le pide iOS a la app mirar en segundo plano lo que dejó la TV (iOS decide si y cuándo corre).
        static let inboxRefresh: TimeInterval = 15 * 60
        /// Cada cuánto (como mínimo) iOS despierta la app para ver si un estreno ya se puede ver.
        static let releaseRefresh: TimeInterval = 30 * 60
        /// Revisar estrenos: lo más pronto que se pide la siguiente y cuánto después de que sale un episodio (para que ya tenga fuente).
        static let releaseSoonest: TimeInterval = 15 * 60, releaseAfterAiring: TimeInterval = 15 * 60
        /// La imagen del aviso de estreno: lo más que se espera por ella (en segundo plano el tiempo es poco; sin ella igual se avisa).
        static let releaseImageTimeout: TimeInterval = 5
        /// Al bloquear: la cápsula «Pantalla bloqueada» antes de encogerse.
        static let lockNotice: UInt64 = 1_000_000_000
        /// Lo que duran el encogido y la subida del candado (los mismos segundos que `DS.Motion`).
        static var lockNoticeShrink: UInt64 { UInt64(DS.Motion.lockShrinkDuration * 1_000_000_000) }
        static var lockNoticeRise: UInt64 { UInt64(DS.Motion.lockRiseDuration * 1_000_000_000) }
        /// Tras un toque con la pantalla bloqueada: la cápsula con «Desbloquear» antes de encogerse.
        static let unlockPrompt: UInt64 = 3_000_000_000
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
        /// La imagen de un aviso («Ya está para ver»): el lado más largo y la calidad del JPEG.
        static let notification = 1000, notificationQuality: CGFloat = 0.82
    }

    enum Poster {
        static let aspect = DesignTokens.Aspect.poster
        static let heroAspect = DesignTokens.Aspect.hero, stillAspect = DesignTokens.Aspect.still
        static let railWidth: CGFloat = 112
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
        static let episodeThumbWidth: CGFloat = 122
        /// Una tarjeta de «Próximos estrenos»: dos y un pedazo (`peek`) de la tercera, en cualquier ancho (con un ancho fijo, en un
        /// iPhone de 375 pt las dos llenaban la pantalla y parecía una cuadrícula que terminaba a 5 pt del borde).
        static let peek: CGFloat = 28
        static var airingWidth: CGFloat { (WindowMetrics.size.width - DS.Space.gutter - DS.Space.s3 - peek) / 2 }
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

extension View {
    /// Una sombra del sistema de diseño (`DS.Elevation`).
    func shadow(_ elevation: DS.Elevation) -> some View {
        shadow(color: elevation.color, radius: elevation.radius, y: elevation.y)
    }
}
