import SwiftUI
import OrbitalCore

/// Tokens del Inicio nuevo (docs/producto/inicio-benchmark/): el selector de la barra y sus tiempos.
extension DS {
    /// La portada de Inicio: arte de borde a borde (pasa detrás de la barra) que se desliza entre títulos.
    enum HomeHero {
        /// Ancho entre alto del arte: casi un póster en el iPhone; más bajo en pantallas cortas (el SE) y apaisado en ventana
        /// ancha (iPad, Mac), donde un póster quedaría altísimo.
        static let aspect: CGFloat = 0.78, aspectShort: CGFloat = 1.25, shortScreen: CGFloat = 700, aspectWide: CGFloat = 1.9
        /// Cuánto se enciman «Seguir viendo» sobre el borde de abajo de la portada (se ve sin bajar).
        static let overlap: CGFloat = 44
    }

    /// «Lo nuevo de lo tuyo»: el ancho de cada pieza, el renglón del día, la marca de hoy y lo apagado de lo que viene.
    enum HomeTimeline {
        static let width: CGFloat = 112, labelRow: CGFloat = 18, dot: CGFloat = 7
        static let markLine: CGFloat = 2, markPad: CGFloat = 3
        static let soonOpacity: Double = 0.62
        /// Dónde queda HOY al abrir (de 0 a 1 en el ancho): lo de antes a la izquierda y un poco de lo que viene.
        static let todayAnchor: CGFloat = 0.62
    }

    /// Canales: el ancho de cada canal, su logo, el velo, cada cuánto se recalcula, el acercamiento lento de la imagen del
    /// capítulo (el «cachito») y la hoja para elegir.
    enum HomeChannels {
        static let width: CGFloat = 268, addWidth: CGFloat = 150
        static let logoWidth: CGFloat = 96, logoHeight: CGFloat = 30
        static let veilStart: Double = 0.4
        static let tick: TimeInterval = 30
        static let drift: Double = 14, driftScale: CGFloat = 1.1
        static let searchDelay: Duration = .milliseconds(350)
        static let gridColumns = 4, resultPoster: CGFloat = 44
    }

    /// Para ti B: los círculos del índice, la portada del mosaico (su muro inclinado y el velo) y la tarjeta de «¿Qué vemos hoy?».
    enum ParaTiB {
        static let circle: CGFloat = 56, circleLabel: CGFloat = 84
        static let coverHeight: CGFloat = 300, coverWall: CGFloat = 620, coverColumns = 6, coverPosters = 36, coverTilt: Double = -10
        static let coverTopVeil: Double = 0.55, coverClearAt: Double = 0.25
        static let deckPoster: CGFloat = 84, deckShift: CGFloat = 10, deckTurn: Double = 5, deckBehind: Double = 0.6
    }

    enum HomeKind {
        /// Cuánto se queda a la vista el nombre del tipo elegido («Series») después de tocar su ícono en la barra.
        static let tipHold: Duration = .milliseconds(1100)
    }
}

extension DS.Collections {
    /// «Por lo que viste» en Inicio: cuánto se desenfoca el póster de fondo y cuánto se ve.
    static let becauseBlur: CGFloat = 30, becauseArtOpacity: Double = 0.9, becauseArtScale: CGFloat = 1.3
}

extension DS {
    /// El cielo de fondo (`SkyField`): cuántas estrellas hay por capa y de qué tamaño, cuánto se mueve cada capa, cómo
    /// respiran las brillantes, la franja de polvo y la estrella fugaz.
    enum Sky {
        private static func tint(_ name: String) -> Color {
            guard let hex = DesignTokens.Sky.hex[name] else { return .clear }
            return adaptive(dark: hex.dark, light: hex.light)
        }
        static let dusk = tint("dusk"), star = tint("star"), cold = tint("cold"), warm = tint("warm"), band = tint("band")

        /// Lejos, en medio y cerca: muchas diminutas y pocas grandes, como en el cielo real.
        static let counts = [170, 60, 16]
        static let radius: [ClosedRange<CGFloat>] = [0.35...0.8, 0.6...1.2, 1.1...2.1]
        static let opacity: [Double] = [0.45, 0.65, 0.9]
        /// Puntos por segundo que se desliza cada capa y cuánto se inclina al mover el teléfono.
        static let drift: [CGFloat] = [0.6, 1.2, 2.1], tilt: [CGFloat] = [4, 9, 16]
        /// De cada cien: cuántas tiran a frío y cuántas a cálido (las demás, blancas).
        static let coldShare = 0.22, warmShare = 0.14
        /// Las brillantes (la capa de cerca): las primeras llevan halo y una cruz de luz casi invisible.
        static let halos = 5, haloScale: CGFloat = 5, haloOpacity = 0.18, crossLength: CGFloat = 9, crossOpacity = 0.22, crossWidth: CGFloat = 0.5
        static let breath: ClosedRange<Double> = 5...9, breathDepth = 0.3
        /// La franja de polvo: en diagonal, ancha y muy tenue, y los granitos que se juntan sobre ella.
        static let bandOpacity = 0.11, bandOpacityLight = 0.55, bandWidth: CGFloat = 0.32, bandBlur: CGFloat = 48
        static let dust = 140, dustSpread: CGFloat = 0.09, dustOpacity = 0.3
        /// Hasta dónde llega el tono del cielo antes de fundirse con el fondo, y cuánto se ven las estrellas de día.
        static let duskFade = 0.75, lightStars = 0.55
        /// La estrella fugaz: cada cuánto, cuánto dura, qué tan larga y qué tan brillante.
        static let shootEvery: TimeInterval = 60, shootFor: TimeInterval = 0.9, shootLength: CGFloat = 110, shootOpacity = 0.7, shootWidth: CGFloat = 1.2
        static let seed: UInt64 = 0x0B17A1
        /// Cuadros por segundo: el cielo es lento; no hace falta más.
        static let frame: TimeInterval = 1.0 / 24
    }
}
