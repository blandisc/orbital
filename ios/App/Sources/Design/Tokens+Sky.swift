import SwiftUI
import OrbitalCore

extension DS {
    /// El cielo de fondo (`SkyField`), mínimo: cuántas estrellas hay por capa y de qué tamaño, cuánto se desliza e inclina
    /// cada capa, cómo titilan las de cerca, la franja de luz y la estrella fugaz.
    enum Sky {
        private static func tint(_ name: String) -> Color {
            guard let hex = DesignTokens.Sky.hex[name] else { return .clear }
            return adaptive(dark: hex.dark, light: hex.light)
        }
        static let dusk = tint("dusk"), star = tint("star"), cold = tint("cold"), warm = tint("warm"), band = tint("band")

        /// Lejos y cerca: muchas diminutas y pocas más grandes, como en el cielo real.
        static let counts = [72, 14]
        static let radius: [ClosedRange<CGFloat>] = [0.3...0.7, 0.7...1.5]
        static let opacity: [Double] = [0.5, 0.85]
        /// Puntos por segundo que se desliza cada capa y cuánto se inclina al mover el teléfono.
        static let drift: [CGFloat] = [0.4, 0.9], tilt: [CGFloat] = [3, 8]
        /// De cada cien: cuántas tiran a frío y cuántas a cálido (las demás, blancas).
        static let coldShare = 0.15, warmShare = 0.08
        /// Las tres más brillantes llevan un halo suave; las de cerca titilan despacio (segundos por vuelta y cuánto bajan).
        static let halos = 3, haloScale: CGFloat = 4, haloOpacity = 0.2
        static let twinkle: ClosedRange<Double> = 6...11, twinkleDepth = 0.35
        /// La franja de luz: de dónde a dónde cruza (de 0 a 1 en la pantalla), qué tan ancha, desenfocada y tenue.
        static let bandFrom = CGPoint(x: -0.1, y: 0.68), bandTo = CGPoint(x: 1.1, y: 0.12)
        static let bandWidth: CGFloat = 0.36, bandBlur: CGFloat = 56, bandOpacity = 0.08, bandOpacityLight = 0.5
        /// Hasta dónde llega el tono del cielo antes de fundirse con el fondo, y cuánto se ven las estrellas de día.
        static let duskFade = 0.7, lightStars = 0.5
        /// La estrella fugaz: cada cuánto, cuánto dura, qué tan larga, brillante y gruesa.
        static let shootEvery: TimeInterval = 60, shootFor: TimeInterval = 0.8, shootLength: CGFloat = 80
        static let shootOpacity = 0.6, shootWidth: CGFloat = 1
        static let seed: UInt64 = 0x0B17A1
        /// Cuadros por segundo: el cielo es lento (12); solo la fugaz va fluida (30).
        static let frame: TimeInterval = 1.0 / 12, shootFrame: TimeInterval = 1.0 / 30
        /// El sensor: cada cuánto lee, qué tan rápido el reposo sigue a tu mano, cuánto se nota y qué tan suave.
        static let motionInterval: TimeInterval = 1.0 / 20, restFollow: CGFloat = 0.01, tiltGain: CGFloat = 3, tiltEase: CGFloat = 0.25
    }
}
