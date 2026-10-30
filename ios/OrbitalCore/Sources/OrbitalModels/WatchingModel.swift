import Foundation
import OrbitalCore

/// «Lo que ves» y el Wrapped: tu historial de Trakt (se trae una vez y se guarda un rato) contado por periodo. La tarjeta de
/// Para ti usa la semana; la pantalla cambia entre semana, mes, año y siempre.
@MainActor
public final class WatchingModel: ObservableModel {
    public private(set) var plays: [TraktPlay] = [] { didSet { changed() } }
    public private(set) var loaded = false { didSet { changed() } }
    public var period: WatchingStats.Period = .month { didSet { if period != oldValue { changed() } } }
    private var fetchedAt: Date?

    /// Cuánto se usa lo traído antes de volver a pedirlo (son hasta 20 páginas de Trakt).
    public nonisolated static let ttl: TimeInterval = 30 * 60
    /// Hasta dónde se mira atrás para «Siempre».
    public nonisolated static let years = 10

    private let services: Services
    private let clock: @Sendable () -> Date
    private let calendar: Calendar
    public init(_ services: Services, clock: @escaping @Sendable () -> Date = { Date() }, calendar: Calendar = .current) {
        self.services = services; self.clock = clock; self.calendar = calendar
        super.init()
    }

    public var linked: Bool { services.trakt?.linked == true }

    public func stats(_ period: WatchingStats.Period? = nil) -> WatchingStats {
        WatchingStats.make(plays, period: period ?? self.period, now: clock(), calendar: calendar)
    }

    /// Un historial ya armado (modo demostración, vistas previas): cuenta como recién traído.
    public func preload(_ plays: [TraktPlay]) { self.plays = plays; fetchedAt = clock(); loaded = true }

    /// Trae tu historial (si no es reciente). `force` al deslizar para actualizar o al terminar de ver algo.
    public func load(force: Bool = false) async {
        guard let trakt = services.trakt, trakt.linked else { if fetchedAt == nil { plays = [] }; loaded = true; return }
        let now = clock()
        if !force, let fetchedAt, now.timeIntervalSince(fetchedAt) < Self.ttl { return }
        let since = calendar.date(byAdding: .year, value: -Self.years, to: now) ?? now
        if let found = try? await trakt.plays(since: since, until: now, maxPages: 20) {
            plays = found
            fetchedAt = now
        }
        loaded = true
    }
}
