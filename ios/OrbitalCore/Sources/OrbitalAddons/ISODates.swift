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

    /// Un día del calendario («2026-10-23», o el día de «2026-10-23T00:00:00.000Z») a mediodía en tu zona: es ese día al
    /// enseñarlo y al mandarlo. Leído como medianoche UTC, en México salía el día anterior (Letterboxd y «El día que salió»,
    /// revisión del 28 nov 2026). Lo vigila `DesignRulesTests.testCalendarDaysAreReadInYourTimeZone`.
    public static func localDay(_ text: String, calendar: Calendar = .current) -> Date? {
        let parts = text.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard text.count >= 10, parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }

    /// Con milésimas o sin ellas.
    public static func parse(_ text: String) -> Date? { precise.date(from: text) ?? plain.date(from: text) }
    /// «2026-10-23T02:00:00Z».
    public static func string(_ date: Date) -> String { plain.string(from: date) }
}
