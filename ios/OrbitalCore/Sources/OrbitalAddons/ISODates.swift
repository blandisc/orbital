import Foundation

/// Las fechas ISO 8601 («2026-10-23T02:00:00.000Z», con o sin milésimas, o solo el día), con formateadores creados UNA vez.
/// Regla del repo (21 nov 2026): nunca `ISO8601DateFormatter()` por llamada. Crear uno arranca ICU y gasta mucha pila; la
/// ficha de una serie armaba dos en cada dibujo y, al girar el iPhone a horizontal, la app se cerró por pila agotada (2436).
/// `ISO8601DateFormatter` es seguro entre hilos. `ISODatesRuleTests` vigila que nadie vuelva a crearlos sueltos.
public enum ISODates {
    nonisolated(unsafe) public static let precise: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    nonisolated(unsafe) public static let plain = ISO8601DateFormatter()
    /// Solo el día («2026-10-23»).
    nonisolated(unsafe) public static let day: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f
    }()

    /// Con milésimas o sin ellas.
    public static func parse(_ text: String) -> Date? { precise.date(from: text) ?? plain.date(from: text) }
    /// «2026-10-23T02:00:00Z».
    public static func string(_ date: Date) -> String { plain.string(from: date) }
}
