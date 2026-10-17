import Foundation
import OrbitalCore

/// Colecciones (Para ti › Listas): Mi lista de Stremio, los premios (fijos), lo más popular de cada año (con varios pósters
/// por año) y lo que ya viste (para «Ocultar lo que ya vi» en una lista abierta).
@MainActor
public final class CollectionsModel: ObservableModel {
    public let awards: [AwardCollection] = Awards.all
    /// Mi lista de Stremio (tu biblioteca), lo más reciente primero.
    public private(set) var myList: [Suggestion] = [] { didSet { changed() } }
    /// Los pósters de cada año en «Por año» (hasta cuatro): ganadoras de ese año y, si faltan, lo más popular.
    public private(set) var yearPosters: [Int: [String]] = [:] { didSet { changed() } }
    private var watchedCache: Set<String>?
    /// Los años de «Por año», del actual hacia atrás.
    public let years: [Int]

    private let services: Services
    private var yearItems: [String: [Suggestion]] = [:]

    public init(_ services: Services) {
        self.services = services
        let now = Calendar.current.component(.year, from: services.now())
        years = Array(stride(from: now, through: Self.firstYear, by: -1))
        super.init()
    }

    static let firstYear = 1980

    public var traktLinked: Bool { services.trakt?.linked ?? false }

    /// Mi lista de Stremio (tu biblioteca), lo último que agregaste o viste primero.
    public func loadMyList() async {
        guard let all = try? await services.watch.library() else { return }
        myList = all.filter(\.inLibrary).sorted { ($0.lastWatched ?? 0) > ($1.lastWatched ?? 0) }.compactMap { w in
            guard w.type == "movie" || w.type == "series" else { return nil }
            var s = Suggestion(art: w.id, kind: w.type, title: w.name, year: nil, reason: .inList("Mi lista"))
            if let poster = w.poster, !poster.isEmpty { s.poster = poster }
            return s
        }
    }

    /// Hasta cuatro pósters de un año: primero las películas premiadas de ese año (sin consultas), luego lo más popular.
    public func loadYearPosters(_ year: Int) async {
        guard yearPosters[year] == nil else { return }
        var posters: [String] = []
        for award in awards where award.kind == "movie" {
            for w in award.winners where w.year == year && !posters.contains(String(format: ForYou.metahubPoster, w.imdb)) {
                posters.append(String(format: ForYou.metahubPoster, w.imdb))
            }
        }
        if posters.count < Self.yearCover, let trakt = services.trakt {
            let popular = (try? await trakt.popular(kind: "movie", limit: Self.yearCover, years: String(year))) ?? []
            for e in popular where posters.count < Self.yearCover {
                let poster = String(format: ForYou.metahubPoster, e.imdb)
                if !posters.contains(poster) { posters.append(poster) }
            }
        }
        yearPosters[year] = Array(posters.prefix(Self.yearCover))
    }

    static let yearCover = 4

    /// Lo que ya viste (Trakt), para «Ocultar lo que ya vi»; se pide una vez.
    public func watchedIDs() async -> Set<String> {
        if let watchedCache { return watchedCache }
        guard let trakt = services.trakt, trakt.linked, let found = try? await trakt.watchedIDs() else { return [] }
        watchedCache = found
        return found
    }

    /// Lo más popular de un año en Trakt (películas o series).
    public func items(year: Int, kind: String) async -> [Suggestion] {
        let key = "\(kind):\(year)"
        if let cached = yearItems[key] { return cached }
        guard let trakt = services.trakt else { return [] }
        let found = ((try? await trakt.popular(kind: kind, limit: 60, years: String(year))) ?? []).map { Suggestion($0, reason: .popular) }
        yearItems[key] = found
        return found
    }
}
