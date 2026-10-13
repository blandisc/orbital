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
    }

    static let bg = Palette.color("ink-950")
    static let backdropDeep = Palette.color("ink-1000")
    static let surface = Palette.color("ink-900")
    static let surfaceRaised = Palette.color("ink-800")
    static let sheetTop = Palette.color("ink-850")
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
    }

    /// Esperas de la interfaz (nanosegundos para `Task.sleep`).
    enum Timing {
        static let controlsHide = UInt64(DesignTokens.Timing.controlsHide * 1e9), banner = UInt64(DesignTokens.Timing.banner * 1e9)
        static let searchDebounce = UInt64(DesignTokens.Timing.searchDebounce * 1e9), tick = UInt64(DesignTokens.Timing.tick * 1e9)
    }

    /// Tamaño de los pósters (relación 2:3, como en la TV).
    enum Poster {
        static let aspect = DesignTokens.Aspect.poster
        static let heroAspect = DesignTokens.Aspect.hero, stillAspect = DesignTokens.Aspect.still
        static let railWidth: CGFloat = 112
        static let gridMinimum: CGFloat = 100
        static let episodeThumbWidth: CGFloat = 122
        static let heroHeight: CGFloat = 300
    }
}
