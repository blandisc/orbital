import Foundation
import OrbitalCore

/// «Lo que ves» y el Wrapped: tu historial de Trakt (se trae una vez y se guarda un rato) contado por periodo. La tarjeta de
/// Para ti usa la semana; la pantalla cambia entre semana, mes, año y siempre.
@MainActor
public final class WatchingModel: ObservableModel {
    public private(set) var plays: [TraktPlay] = [] { didSet { changed() } }
    public private(set) var loaded = false { didSet { changed() } }
    /// La última vez no llegó el historial y no hay nada guardado: «No se pudo cargar», no «Nada en este periodo».
    public private(set) var failed = false { didSet { changed() } }
    public var period: WatchingStats.Period = .month { didSet { if period != oldValue { changed() } } }
    private var fetchedAt: Date?

    /// Cuánto se usa lo traído antes de preguntar por lo nuevo.
    public nonisolated static let ttl: TimeInterval = 10 * 60
    /// Hasta dónde se mira atrás para «Siempre».
    public nonisolated static let years = 10
    static let cacheKey = "watching-history"
    /// Lo guardado en el iPhone: desde cuándo cubre y las vistas (así no se vuelve a bajar todo en cada arranque).
    private struct Saved: Codable {
        struct P: Codable { var at: Date; var kind, imdb, title: String; var minutes: Int; var genres: [String]; var season, episode: Int? }
        var since: Date
        var plays: [P]
    }
    private var since: Date?

    private let services: Services
    private let clock: @Sendable () -> Date
    private let calendar: Calendar
    public init(_ services: Services, clock: @escaping @Sendable () -> Date = { Date() }, calendar: Calendar = .current) {
        self.services = services; self.clock = clock; self.calendar = calendar
        super.init()
        if let data = services.kv.data(Self.cacheKey), let saved = try? JSONDecoder().decode(Saved.self, from: data) {
            plays = saved.plays.map { TraktPlay(at: $0.at, kind: $0.kind, imdb: $0.imdb, title: $0.title, minutes: $0.minutes, genres: $0.genres, season: $0.season, episode: $0.episode) }
            since = saved.since
            loaded = true
        }
    }

    public var linked: Bool { services.trakt?.linked == true }

    public func stats(_ period: WatchingStats.Period? = nil) -> WatchingStats {
        WatchingStats.make(plays, period: period ?? self.period, now: clock(), calendar: calendar)
    }

    /// Quitaste algo de vistos (la ficha): sale ya de «Lo que ves» (lo guardado solo pregunta por lo nuevo y nunca se
    /// enteraba de lo que quitabas). `videoID` «tt123:1:5» es un episodio; si no, toda la película.
    public func forget(metaID: String, videoID: String) {
        let parts = videoID.split(separator: ":")
        if parts.count == 3, let season = Int(parts[1]), let episode = Int(parts[2]) {
            plays.removeAll { $0.imdb == metaID && $0.season == season && $0.episode == episode }
        } else {
            plays.removeAll { $0.imdb == metaID }
        }
        save()
    }

    /// Un historial ya armado (modo demostración, vistas previas): cuenta como recién traído.
    public func preload(_ plays: [TraktPlay]) {
        self.plays = plays; since = .distantPast; fetchedAt = clock(); loaded = true
    }

    /// Trae tu historial. La tarjeta de Para ti pide solo la semana (`full: false`); «Lo que ves» pide los diez años la
    /// primera vez. Lo traído se guarda en el iPhone y después solo se pregunta por lo nuevo (desde la última vista).
    public func load(full: Bool = false, force: Bool = false) async {
        guard let trakt = services.trakt, trakt.linked else { if fetchedAt == nil && since == nil { plays = [] }; loaded = true; return }
        let now = clock()
        let needed = full ? (calendar.date(byAdding: .year, value: -Self.years, to: now) ?? now)
                          : WatchingStats.start(of: .week, now: now, calendar: calendar)
        let covered = since.map { $0 <= needed } ?? false
        if covered, !force, let fetchedAt, now.timeIntervalSince(fetchedAt) < Self.ttl { return }
        var ok = true
        if covered {
            // Ya está guardado: solo lo nuevo desde la última vista.
            let from = plays.map(\.at).max() ?? needed
            if let new = try? await trakt.plays(since: from.addingTimeInterval(1), until: now, maxPages: 5) { merge(new) } else { ok = false }
        } else if let found = try? await trakt.plays(since: needed, until: now, maxPages: full ? 20 : 2) {
            plays = found; since = needed
        } else { ok = false }
        // Con algo guardado se muestra eso (aunque no llegara lo nuevo); sin nada, es un error de verdad.
        failed = !ok && plays.isEmpty
        guard ok else { loaded = true; return }
        fetchedAt = now
        loaded = true
        save()
    }

    private func merge(_ new: [TraktPlay]) {
        func key(_ p: TraktPlay) -> String { "\(p.at.timeIntervalSince1970)|\(p.imdb)|\(p.season ?? -1)|\(p.episode ?? -1)" }
        var seen = Set(plays.map(key))
        plays += new.filter { seen.insert(key($0)).inserted }
    }

    private func save() {
        guard let since else { return }
        let saved = Saved(since: since, plays: plays.map { .init(at: $0.at, kind: $0.kind, imdb: $0.imdb, title: $0.title, minutes: $0.minutes, genres: $0.genres, season: $0.season, episode: $0.episode) })
        services.kv.set(Self.cacheKey, data: try? JSONEncoder().encode(saved))
    }
}
