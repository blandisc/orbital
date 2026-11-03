import Foundation

/// Cómo le ha ido a cada complemento en este aparato (C1, C2): lo que tardó la última vez que contestó y, si falla, desde
/// cuándo. La misma regla que `addons.Health` de la TV: tras `skipAfter` fallos seguidos ya no se le espera (`skip`) hasta su
/// próximo intento, con espera creciente (1 min, 2, 4… hasta 1 h), y regresa solo en cuanto contesta. Se guarda por la huella
/// de su dirección, nunca la dirección (lleva tu clave). No se comparte con la TV: lo que vive allá puede no contestar aquí.
public final class AddonHealth: @unchecked Sendable {
    public static let skipAfter = 2
    public static let retryBase: TimeInterval = 60
    public static let retryMax: TimeInterval = 3600
    /// «Contesta lento · 4,2 s» desde aquí.
    public static let slowSeconds = 3.0
    static let storeKey = "addon-health"

    public enum State: Equatable, Sendable {
        case unknown
        case ok(seconds: Double)
        case slow(seconds: Double)
        /// No contesta desde `since`; `skipped`: ya no se le espera.
        case down(since: Date, skipped: Bool)
    }

    struct Record: Codable, Equatable {
        var seconds: Double?
        var fails = 0
        var since: Date?
        var retry: Date?
    }

    private let vault: AddonVault?
    private let clock: @Sendable () -> Date
    private let lock = NSLock()
    private var records: [String: Record]

    public init(vault: AddonVault? = nil, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.vault = vault; self.clock = clock
        records = vault?.data(Self.storeKey).flatMap { try? JSONDecoder().decode([String: Record].self, from: $0) } ?? [:]
    }

    /// La huella de una dirección (la misma función que el id de un complemento): nunca se guarda la dirección.
    public static func key(_ url: String) -> String { AddonList.newID(url) }

    public func ok(_ url: String, seconds: Double) {
        change(url) { $0 = Record(seconds: (max(0, seconds) * 100).rounded() / 100) }
    }

    /// Falló (`at`: cuándo; por omisión, ahora).
    public func fail(_ url: String, at date: Date? = nil) {
        let now = date ?? clock()
        change(url) { record in
            record.fails += 1
            record.since = record.since ?? now
            let wait = record.fails >= Self.skipAfter ? min(Self.retryMax, Self.retryBase * pow(2, Double(record.fails - Self.skipAfter))) : 0
            record.retry = now.addingTimeInterval(wait)
        }
    }

    /// Ya no se le espera: falló `skipAfter` veces seguidas y todavía no le toca volver a probar.
    public func skip(_ url: String) -> Bool {
        let record = lock.withLock { records[Self.key(url)] }
        guard let record, record.fails >= Self.skipAfter, let retry = record.retry else { return false }
        return clock() < retry
    }

    public func status(_ url: String) -> State {
        guard let record = lock.withLock({ records[Self.key(url)] }) else { return .unknown }
        if record.fails > 0 { return .down(since: record.since ?? clock(), skipped: record.fails >= Self.skipAfter) }
        guard let seconds = record.seconds else { return .unknown }
        return seconds >= Self.slowSeconds ? .slow(seconds: seconds) : .ok(seconds: seconds)
    }

    private func change(_ url: String, _ edit: (inout Record) -> Void) {
        let data: Data? = lock.withLock {
            var record = records[Self.key(url)] ?? Record()
            edit(&record)
            records[Self.key(url)] = record
            return try? JSONEncoder().encode(records)
        }
        vault?.setData(Self.storeKey, data)
    }
}

/// C1 en palabras, iguales en la TV (design/vocabulario.json): «Contesta en 0,6 s», «Contesta lento · 4,2 s» y «No contesta
/// desde el sábado · se salta». Los textos van en español (la clave del catálogo); `tr` los traduce.
public enum AddonHealthWords {
    /// «0,6» en español; «0.6» en inglés.
    public static func seconds(_ value: Double, english: Bool = false) -> String {
        let text = String(format: "%.1f", value)
        return english ? text : text.replacingOccurrences(of: ".", with: ",")
    }

    /// El día desde el que no contesta: «hoy», «ayer» o el día de la semana («el sábado»).
    public static func since(_ date: Date, now: Date, calendar: Calendar = .current, english: Bool = false) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        if days <= 0 { return english ? "today" : "hoy" }
        if days == 1 { return english ? "yesterday" : "ayer" }
        let index = calendar.component(.weekday, from: date) - 1
        let es = ["el domingo", "el lunes", "el martes", "el miércoles", "el jueves", "el viernes", "el sábado"]
        let en = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        return english ? en[index] : es[index]
    }
}
