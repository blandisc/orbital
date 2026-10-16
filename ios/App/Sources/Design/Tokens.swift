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

    static let bg = Palette.color("ink-950")
    static let backdropDeep = Palette.color("ink-1000")
    static let surface = Palette.color("ink-900")
    static let surfaceRaised = Palette.color("ink-800")
    static let ink500 = Palette.color("ink-500")
    static let text = Palette.color("paper")
    static let textMuted = Palette.color("ink-300")
    static let textFaint = Color.white.opacity(DesignTokens.Opacity.faint)
    static let primary = Palette.color("paper")
    static let onPrimary = Palette.color("ink-1000")
    static let hairline = Color.white.opacity(DesignTokens.Opacity.hairline)
    static let fill = Color.white.opacity(DesignTokens.Opacity.fill)
    static let fillStrong = Color.white.opacity(DesignTokens.Opacity.fillStrong)
    static let track = Color.white.opacity(DesignTokens.Opacity.track)
    static let scrim = Palette.color("ink-1000").opacity(DesignTokens.Opacity.scrim)
    static let badgeBackground = Palette.color("ink-1000").opacity(DesignTokens.Opacity.badge)
    static let scrimStrong = Palette.color("ink-1000").opacity(DesignTokens.Opacity.scrimStrong)
    static let good = Palette.color("teal-300")
    static let warning = Palette.color("amber-300")
    static let danger = Palette.color("red-400")
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

    // MARK: Movimiento (sin movimiento con «Reducir movimiento»)
    enum Motion {
        static func base(_ reduce: Bool) -> Animation? { reduce ? nil : .easeOut(duration: DesignTokens.Motion.base) }
        static func enter(_ reduce: Bool) -> Animation? { reduce ? nil : .easeOut(duration: DesignTokens.Motion.enter) }
        static func tint(_ reduce: Bool) -> Animation? { reduce ? nil : .easeInOut(duration: DesignTokens.Motion.tint) }
        static func spring(_ reduce: Bool) -> Animation? { reduce ? nil : .spring(duration: DesignTokens.Motion.slow, bounce: 0.2) }
    }

    /// Medidas fijas.
    enum Size {
        static let touchTarget = CGFloat(DesignTokens.Size.touchTarget), thumbSmall = CGFloat(DesignTokens.Size.thumbSmall)
        static let cardMax = CGFloat(DesignTokens.Size.cardMax), grabber = CGFloat(DesignTokens.Size.grabber), grabberHeight = CGFloat(DesignTokens.Size.grabberHeight)
        static let logo = CGFloat(DesignTokens.Size.logo)
        static let platformLogo = CGFloat(DesignTokens.Size.platformLogo)
        static let rankNumber = CGFloat(DesignTokens.Size.rankNumber)
        /// La cifra de un Top 10: enorme y pesada; no crece con Dynamic Type (es un adorno, el puesto ya se dice en la etiqueta).
        static var rankFont: Font { .system(size: rankNumber, weight: .black, design: .rounded) }
        static let logoHero = CGFloat(DesignTokens.Size.logoHero)
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
        static let tintFloor = DesignTokens.Backdrop.tintFloor
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
    }

    /// Tamaño de los pósters (relación 2:3, como en la TV).
    enum Poster {
        static let aspect = DesignTokens.Aspect.poster
        static let heroAspect = DesignTokens.Aspect.hero, stillAspect = DesignTokens.Aspect.still
        static let railWidth: CGFloat = 112
        static let gridMinimum: CGFloat = 100
        static let episodeThumbWidth: CGFloat = 122
        static let heroHeight: CGFloat = 300
        /// El póster pequeño de «Viendo en la TV» (misma relación 2:3, más chico que el de la tira).
        static let nowPlayingWidth: CGFloat = 56
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
        static let growRatio = CGFloat(DesignTokens.Mosaic.growRatio)
        static let idle = DesignTokens.Mosaic.idleSeconds, alive = DesignTokens.Mosaic.aliveSeconds
        static let driftTick = DesignTokens.Mosaic.driftTick
        static let driftPerSecond = CGFloat(DesignTokens.Mosaic.driftPerSecond)
        static let buffer = CGFloat(DesignTokens.Mosaic.bufferHeight)
        static let focusedRowRatio = DesignTokens.Mosaic.focusedRowRatio
    }
}
