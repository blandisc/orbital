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

    /// Viste algo: «Ocultar lo que ya vi» se vuelve a preguntar.
    public func forgetWatched() { watchedCache = nil }
    /// Otra cuenta (o desconectaste Trakt): nada de la anterior se queda.
    public func resetAccount() { watchedCache = nil; myList = [] }
    /// Los estudios (Colecciones › Estudios) y lo que tiene cada uno (se pide al verlo).
    public let studios: [(id: Int, name: String)] = Tmdb.studios
    public private(set) var studioItems: [Int: [Suggestion]] = [:] { didSet { changed() } }
    /// El logo de cada estudio (TMDB), si lo tiene; se guarda en el iPhone (no cambia).
    public private(set) var studioLogos: [Int: String] = [:] { didSet { changed() } }
    public var tmdbReady: Bool { services.tmdb.configured }
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
            // Si se cancela (la tarjeta salió de la vista) o falla, no se guarda nada: la próxima vez se vuelve a pedir (antes
            // quedaba vacía para siempre).
            guard let popular = try? await trakt.popular(kind: "movie", limit: Self.yearCover, years: String(year)), !Task.isCancelled else {
                if !posters.isEmpty, !Task.isCancelled { yearPosters[year] = Array(posters.prefix(Self.yearCover)) }
                return
            }
            for e in popular where posters.count < Self.yearCover {
                let poster = String(format: ForYou.metahubPoster, e.imdb)
                if !posters.contains(poster) { posters.append(poster) }
            }
        }
        yearPosters[year] = Array(posters.prefix(Self.yearCover))
    }

    static let yearCover = 4

    /// Lo más popular de un estudio (una vez; luego de la caché).
    public func loadStudio(_ id: Int) async {
        guard studioItems[id] == nil, let studio = studios.first(where: { $0.id == id }) else { return }
        let found = await services.forYou.studioItems(companyID: id, name: studio.name)
        if !found.isEmpty { studioItems[id] = found }
        let key = "studio-logo.\(id)"
        if let saved = services.kv.data(key).flatMap({ String(data: $0, encoding: .utf8) }) { studioLogos[id] = saved }
        else if services.tmdb.configured, let logo = try? await services.tmdb.companyLogo(id) {
            studioLogos[id] = logo
            services.kv.set(key, data: logo.data(using: .utf8))
        }
    }

    /// La calificación de IMDb de cada título (de Cinemeta, 12 a la vez), para «Mejor calificadas en IMDb»; se recuerda.
    public func imdbRatings(_ ids: [(kind: String, imdb: String)]) async -> [String: Double] {
        let missing = ids.filter { imdbCache[$0.imdb] == nil }
        let cinemeta = services.cinemeta
        for chunk in stride(from: 0, to: missing.count, by: 12).map({ Array(missing[$0..<min($0 + 12, missing.count)]) }) {
            let found = await withTaskGroup(of: (String, Double?).self) { group in
                for item in chunk {
                    group.addTask {
                        let meta = try? await cinemeta.meta(kind: item.kind, id: item.imdb)
                        return (item.imdb, (meta?["imdbRating"]?.string).flatMap(Double.init) ?? meta?["imdbRating"]?.doubleValue)
                    }
                }
                var out: [(String, Double?)] = []
                for await r in group { out.append(r) }
                return out
            }
            for (id, rating) in found { imdbCache[id] = rating ?? 0 }
        }
        return imdbCache.filter { $0.value > 0 }
    }

    private var imdbCache: [String: Double] = [:]

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
        guard let entries = try? await trakt.popular(kind: kind, limit: 60, years: String(year)), !Task.isCancelled else { return [] }   // sin guardar el vacío
        let found = entries.map { Suggestion($0, reason: .popular) }
        yearItems[key] = found
        return found
    }
}
