import Foundation

/// El deslizador de Calificación del filtro avanzado (Fernando, 2 nov 2026; propuesta en
/// docs/producto/propuestas-2026-11-01/calificacion-deslizador-2.html): qué mínimo queda según dónde va el dedo, de décima en
/// décima. Del todo a la izquierda es «Sin mínimo» (nil). Con VoiceOver salta de nivel en nivel (Buena, Muy buena,
/// Excelente) y luego de medio en medio hasta el tope. El dibujo (la regla del público, las estrellas de los cinéfilos)
/// vive en la app; aquí solo la cuenta.
public struct RatingSlider: Sendable, Equatable {
    /// Donde empieza la escala (ahí es «Sin mínimo»), su tope y dónde empieza cada nivel.
    public let floor: Double
    public let ceiling: Double
    public let stops: [Double]
    /// Hasta dónde, cerca del inicio, el dedo todavía dice «Sin mínimo».
    public let noneUpTo: Double

    public init(floor: Double, ceiling: Double, stops: [Double], noneUpTo: Double) {
        self.floor = floor; self.ceiling = ceiling; self.stops = stops; self.noneUpTo = noneUpTo
    }

    /// El público (TMDB, de 10): una regla del 5 al 9 (abajo de 5 casi no hay nada que quitar, arriba de 9 casi no queda nada).
    public static let tmdb = RatingSlider(floor: 5, ceiling: 9, stops: [7, 7.5, 8], noneUpTo: 5.05)
    /// Los cinéfilos (Letterboxd, de 5 estrellas): las cinco estrellas enteras; un toquecito en la orilla no cuenta.
    public static let letterboxd = RatingSlider(floor: 0, ceiling: 5, stops: [3.5, 3.8, 4.2], noneUpTo: 0.25)

    /// El valor bajo el dedo, de 0 (inicio) a 1 (tope), redondeado a la décima.
    public func value(atFraction fraction: Double) -> Double? {
        let p = min(max(fraction, 0), 1)
        let v = ((floor + p * (ceiling - floor)) * 10).rounded() / 10
        return v <= noneUpTo ? nil : v
    }

    /// Dónde se dibuja un valor (0–1); «Sin mínimo» y lo que quede abajo de la escala, al inicio.
    public func fraction(of value: Double?) -> Double {
        guard let value else { return 0 }
        return min(max((value - floor) / (ceiling - floor), 0), 1)
    }

    /// El nivel más alto que alcanza (0 Buena, 1 Muy buena, 2 Excelente; nil abajo de Buena o sin mínimo).
    public func level(_ value: Double?) -> Int? {
        guard let value else { return nil }
        return stops.lastIndex { value >= $0 - 0.001 }
    }

    /// Un paso con VoiceOver: los niveles primero y, pasando Excelente, de medio en medio hasta el tope.
    public func step(_ value: Double?, up: Bool) -> Double? {
        let marks = stops + Array(stride(from: (stops.last ?? floor) + 0.5, through: ceiling, by: 0.5))
        if up {
            guard let v = value else { return marks.first }
            return marks.first { $0 > v + 0.001 } ?? v
        }
        guard let v = value else { return nil }
        return marks.last { $0 < v - 0.001 }
    }
}
