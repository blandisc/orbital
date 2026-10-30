import Foundation
import OrbitalCore

/// Calificar como en Trakt: tus estrellas (5 con medias, 1…10 en Trakt) y el recordatorio inteligente que asoma sobre la
/// barra de pestañas con lo que terminaste hace poco y aún no calificas. Calificar se ve al momento y viaja por la bandeja
/// de Trakt (`TraktOutbox`): sin conexión no se pierde.
@MainActor
public final class RatingsModel: ObservableModel {
    /// Algo que te toca calificar.
    public struct Candidate: Sendable, Equatable, Identifiable {
        public var imdb: String, kind: String, title: String, poster: String
        public var finished: Date
        public var id: String { imdb }
        public init(imdb: String, kind: String, title: String, poster: String, finished: Date) {
            self.imdb = imdb; self.kind = kind; self.title = title; self.poster = poster; self.finished = finished
        }
    }

    /// Cuánto hacia atrás se busca lo que terminaste.
    public nonisolated static let window: TimeInterval = 14 * 86400
    /// Una serie se recuerda cuando ya llevas varios episodios en la ventana (uno solo aún no es opinión).
    public nonisolated static let seriesEpisodes = 3
    static let dismissedKey = "ratings-dismissed"
    /// Lo que se recuerda de lo que dijiste «no calificar» (lo más reciente).
    static let memory = 300

    public private(set) var ratings: [String: Int] = [:] { didSet { changed() } }
    public private(set) var queue: [Candidate] = [] { didSet { changed() } }

    private let services: Services
    private let clock: @Sendable () -> Date
    public init(_ services: Services, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.services = services; self.clock = clock
        super.init()
    }

    /// Lo primero de la fila y cuántas más esperan («y 2 más»).
    public var current: Candidate? { queue.first }
    public var more: Int { max(0, queue.count - 1) }

    /// Tus estrellas para un título (lo pendiente de mandar gana sobre lo que dice Trakt).
    public func stars(_ imdb: String) -> Double? {
        if let pending = services.traktOutbox.pendingRatings[imdb] { return pending.map(RatingScale.stars(trakt:)) }
        return ratings[imdb].map(RatingScale.stars(trakt:))
    }

    /// Trae tus calificaciones y lo que viste en la ventana, y arma la fila del recordatorio.
    public func refresh() async {
        guard let trakt = services.trakt, trakt.linked else { ratings = [:]; queue = []; return }
        let now = clock()
        async let rated = try? trakt.myRatings()
        async let plays = try? trakt.plays(since: now.addingTimeInterval(-Self.window), until: now, maxPages: 2)
        if let rated = await rated { ratings = rated }
        queue = Self.reminders(plays: await plays ?? [], rated: Set(ratings.keys).union(services.traktOutbox.pendingRatings.keys),
                               dismissed: dismissed, now: now)
    }

    /// Calificar (o, con nil, quitar tu calificación). Sale de la fila y se manda a Trakt.
    public func rate(imdb: String, kind: String, stars: Double?) async {
        let value = stars.map(RatingScale.trakt(stars:))
        if let value { ratings[imdb] = value } else { ratings[imdb] = nil }
        queue.removeAll { $0.imdb == imdb }
        services.traktOutbox.enqueue(.rating(imdb: imdb, series: kind == "series", value))
        await services.traktOutbox.flush(services.trakt)
    }

    /// «No calificar esta»: no vuelve a aparecer en el recordatorio.
    public func dismiss(_ imdb: String) {
        queue.removeAll { $0.imdb == imdb }
        let list = (services.kv.data(Self.dismissedKey).flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []).filter { $0 != imdb } + [imdb]
        services.kv.set(Self.dismissedKey, data: try? JSONEncoder().encode(Array(list.suffix(Self.memory))))
    }

    private var dismissed: Set<String> {
        Set(services.kv.data(Self.dismissedKey).flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? [])
    }

    /// La regla del recordatorio: películas que terminaste en la ventana y series con varios episodios en ella; sin lo ya
    /// calificado ni lo descartado; lo más reciente primero.
    public nonisolated static func reminders(plays: [TraktPlay], rated: Set<String>, dismissed: Set<String>, now: Date) -> [Candidate] {
        let recent = plays.filter { $0.at <= now && now.timeIntervalSince($0.at) <= window && !$0.imdb.isEmpty }
        var out: [String: Candidate] = [:]
        var episodes: [String: Int] = [:]
        for play in recent {
            if play.kind == "series" { episodes[play.imdb, default: 0] += 1 }
            let candidate = Candidate(imdb: play.imdb, kind: play.kind, title: play.title,
                                      poster: String(format: ForYou.metahubPoster, play.imdb), finished: play.at)
            if let have = out[play.imdb], have.finished >= play.at { continue }
            out[play.imdb] = candidate
        }
        return out.values
            .filter { !rated.contains($0.imdb) && !dismissed.contains($0.imdb) }
            .filter { $0.kind != "series" || episodes[$0.imdb, default: 0] >= seriesEpisodes }
            .sorted { $0.finished > $1.finished }
    }
}
