import SwiftUI
import OrbitalCore

/// «Decide por mí» con vida (Fernando, 13 nov 2026: «Pon un toque de color, hazlos más bonitos… una animación, una
/// interacción»). Aparte de Tokens+Screens para que ninguno pase de su tope. Regla en `docs/ios-interfaz.md` § «Decide se
/// siente vivo».
extension DS {
    enum DecideLive {
        /// Cada filtro puesto con su tinte (los de las listas; nunca el turquesa, que es de la voz y del porqué): la duración en
        /// azul cielo, el ánimo en rosa, la calificación en oro y lo demás (el botón «Filtros», géneros, época, listas) en
        /// verde. Sin leer se ve qué está puesto.
        static let time = ListTint.library, mood = ListTint.bookmark, rating = ListTint.trophy, refine = ListTint.list
        /// El símbolo sobre su tinte: la tinta más honda en los dos modos (los tintes son claros, ≥ 3:1 en claro y en oscuro).
        static let onTint = DS.backdropDeep
        /// El relleno de un filtro entra creciendo desde este tamaño (con `DS.Motion.grow`), no aparece de golpe.
        static let fillFrom: CGFloat = 0.4
        /// El resplandor detrás de los tres carteles, del color del elegido: lo fuerte que se ve y hasta dónde llega.
        static let glow = 0.32, glowReach: CGFloat = 260
        /// Barajar: los carteles salen y entran de uno en uno (este tiempo entre uno y otro), desde este tamaño y esta altura,
        /// y lo que tardan en irse antes de pedir los nuevos.
        static let shuffleStagger: Double = 0.05, shuffleFrom: CGFloat = 0.9, shuffleRise = DS.Space.s4
        static let leave: Duration = .milliseconds(180)
        /// Un cartel apretado se hunde tantito: respuesta al dedo.
        static let pressed: CGFloat = 0.96
        /// Cuánto se corre el contenido de una pestaña al entrar o salir de su lado.
        static let tabShift = DS.Space.s8
    }

    /// El mazo con vida: los botones de abajo se encienden del color de su sello mientras arrastras hacia su lado (hasta
    /// `litFill` y crecen `litGrow`), el sello crece desde `stampFrom` con el avance y la carta sale volando en un tiempo que
    /// sale de la velocidad del dedo (entre `throwMin` y `throwMax`).
    enum MatchLive {
        static let litFill = 0.24, litGrow: CGFloat = 0.08, stampFrom: CGFloat = 0.75
        static let throwMin = 0.14, throwMax = 0.34
    }
}

extension DS.Motion {
    /// Aventar algo con la velocidad del dedo: sale rápido y frena (lo que dura sale de la velocidad del gesto). Con «Reducir
    /// movimiento», nada (se funde en su lugar).
    static func fling(_ reduce: Bool, duration: Double) -> Animation? { reduce ? nil : .easeOut(duration: duration) }
}
