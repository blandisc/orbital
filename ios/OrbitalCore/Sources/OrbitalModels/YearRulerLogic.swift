import Foundation

/// Lo que decide la regla de años de Época (la vista `YearRuler` solo dibuja y mide): qué años quedan elegidos al tocar,
/// arrastrar la ventana o sus orillas, tocar una década o moverla con VoiceOver. Vivía dentro de la vista, sin pruebas
/// (auditoría, 31 oct 2026, T).
public struct YearRulerLogic: Sendable, Equatable {
    public let first: Int
    public let last: Int
    public init(first: Int, last: Int) { self.first = first; self.last = max(first, last) }

    /// Qué se arrastra: una orilla o la ventana entera (con dónde la tomó el dedo y cuántos años mide).
    public enum Drag: Equatable, Sendable { case lower, upper, move(offset: Int, length: Int) }

    /// La rayita de un año, de 0 (izquierda) a 1 (derecha).
    public func fraction(of year: Int) -> Double { Double(year - first) / Double(max(last - first, 1)) }

    /// El año más cercano a un punto de la regla (0…1), dentro de la regla.
    public func year(atFraction f: Double) -> Int {
        min(last, max(first, first + Int((f * Double(last - first)).rounded())))
    }

    /// Un paso del dedo. `drag` nil: es el primer toque; `nearLower`/`nearUpper`: si empezó sobre una orilla.
    /// - Sin nada elegido, el primer toque pone una década alrededor del dedo (y desde ahí se mueve entera).
    /// - Sobre una orilla, esa orilla; dentro de la ventana, la ventana entera; fuera, la orilla más cercana.
    public func change(_ years: ClosedRange<Int>?, drag: Drag?, at y: Int, nearLower: Bool, nearUpper: Bool) -> (years: ClosedRange<Int>?, drag: Drag?) {
        var drag = drag
        if drag == nil {
            guard let r = years else {
                let lower = max(first, min(y - 4, last - 9))
                return (lower...min(lower + 9, last), .move(offset: y - lower, length: min(9, last - lower)))
            }
            if nearLower { drag = .lower }
            else if nearUpper { drag = .upper }
            else if r.contains(y) { drag = .move(offset: y - r.lowerBound, length: r.upperBound - r.lowerBound) }
            else { drag = abs(y - r.lowerBound) <= abs(y - r.upperBound) ? .lower : .upper }
        }
        guard let r = years, let drag else { return (years, drag) }
        switch drag {
        case .lower: return (min(y, r.upperBound)...r.upperBound, drag)
        case .upper: return (r.lowerBound...max(y, r.lowerBound), drag)
        case .move(let offset, let length):
            let lower = max(first, min(last - length, y - offset))
            return (lower...(lower + length), drag)
        }
    }

    /// VoiceOver: la ventana un año a la izquierda o a la derecha (sin nada elegido, desde los últimos diez); en la orilla
    /// de la regla no se mueve.
    public func step(_ years: ClosedRange<Int>?, by step: Int) -> ClosedRange<Int>? {
        let r = years ?? (last - 9)...last
        guard r.lowerBound + step >= first, r.upperBound + step <= last else { return years }
        return (r.lowerBound + step)...(r.upperBound + step)
    }

    /// Las décadas de abajo (la última, hasta donde llega la regla).
    public var decades: [ClosedRange<Int>] { stride(from: first, through: last, by: 10).map { $0...min($0 + 9, last) } }

    /// Tocar una década la elige entera; tocarla otra vez, la quita.
    public func toggle(_ decade: ClosedRange<Int>, in years: ClosedRange<Int>?) -> ClosedRange<Int>? { years == decade ? nil : decade }
}
