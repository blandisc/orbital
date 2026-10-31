import Foundation

/// El filtro avanzado de Buscar (docs/producto/muvy-busqueda-premios/prototipo-filtro.html): seis principales (formato,
/// género, época, tiempo, calificación y qué tan conocida) y, en «Ver más», origen y estudios. Todo se traduce a una sola
/// búsqueda de TMDB (/discover) por tipo; sin conteos en vivo: los resultados salen al tocar «Ver resultados».
public struct AdvancedFilter: Sendable, Equatable, Hashable, Codable {
    public enum Format: String, Sendable, CaseIterable, Codable { case all, movie, series }
    /// En qué orden salen: lo más popular, lo mejor calificado o lo más nuevo.
    public enum Sort: String, Sendable, CaseIterable, Codable { case popular, rating, newest }
    /// Solo con «Series»: en emisión o terminadas.
    public enum SeriesStatus: String, Sendable, CaseIterable, Codable { case any, airing, ended }
    /// El tiempo que tienes: corta, normal o larga (en series, lo que dura un capítulo).
    public enum Length: String, Sendable, CaseIterable, Codable { case any, short, regular, long }
    /// «Qué tan conocida»: el cuadro fama × calificación.
    public enum Fame: String, Sendable, CaseIterable, Codable { case any, gems, classics, niche, blockbusters }

    public var format: Format = .all
    public var seriesStatus: SeriesStatus = .any
    /// Slugs de `Tmdb.genres`: los que quieres (cualquiera de ellos) y los que no.
    public var genres: Set<String> = []
    public var excluded: Set<String> = []
    /// Años de estreno, inclusivos (nil: cualquiera).
    public var years: ClosedRange<Int>?
    public var length: Length = .any
    /// Calificación mínima, 0–10 (la de TMDB; nil: cualquiera).
    public var minRating: Double?
    public var fame: Fame = .any
    /// Países de origen (ISO 3166, «MX») y estudios (ids de TMDB).
    public var countries: Set<String> = []
    public var studios: Set<Int> = []
    /// Dónde verla: plataformas de TMDB (ids de proveedor) en tu país (`region`); vacío: en cualquiera.
    public var providers: Set<Int> = []
    public var region = "MX"
    /// Lo que ya viste (de Trakt) no sale; encendido de entrada.
    public var hideWatched = true
    public var sort: Sort = .popular
    /// Hoy, «2026-10-30»: «Más nuevas» no trae lo que aún no se estrena.
    public var today = AdvancedFilter.day(Date())
    /// El año de hoy: con «desde este año» el piso de votos baja (lo recién estrenado aún tiene pocos).
    public var currentYear = Calendar.current.component(.year, from: Date())

    public init() {}

    static func day(_ date: Date) -> String {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// Los géneros elegidos que TMDB no tiene para series (Terror, Romance, Suspenso, Aventura): solo filtran películas.
    public var moviesOnlyGenres: [TmdbGenre] { Tmdb.genres.filter { genres.contains($0.slug) && $0.tv == nil } }

    /// Cuántos filtros están puestos (el «Ver resultados · 3» y el punto en la puerta).
    public var activeCount: Int {
        [format != .all, seriesStatus != .any && format == .series, !genres.isEmpty || !excluded.isEmpty, years != nil,
         length != .any, minRating != nil, fame != .any, !countries.isEmpty, !studios.isEmpty, !providers.isEmpty].filter { $0 }.count
    }
    public var isEmpty: Bool { activeCount == 0 }

    /// Qué tipos se buscan: los dos, o solo uno. Estudios y «Taquilleras» son de películas.
    public var kinds: [String] {
        switch format {
        case .movie: return ["movie"]
        case .series: return ["series"]
        case .all:
            // Taquilleras son películas; y si todos los géneros que elegiste no existen en series, también.
            let onlyMovieGenres = !genres.isEmpty && moviesOnlyGenres.count == genres.count
            return fame == .blockbusters || onlyMovieGenres ? ["movie"] : ["movie", "series"]
        }
    }

    /// Los minutos de cada largo (en series se mide el capítulo).
    static func runtime(_ length: Length, series: Bool) -> (min: Int?, max: Int?) {
        switch (length, series) {
        case (.any, _): return (nil, nil)
        case (.short, false): return (nil, 95)
        case (.regular, false): return (90, 130)
        case (.long, false): return (130, nil)
        case (.short, true): return (nil, 30)
        case (.regular, true): return (30, 50)
        case (.long, true): return (50, nil)
        }
    }

    /// Los parámetros de /discover para un tipo («movie» o «series»).
    public func params(kind: String) -> [(String, String)] {
        let series = kind == "series"
        var p: [(String, String)] = []
        let wanted = Tmdb.genres.filter { genres.contains($0.slug) }.compactMap { series ? $0.tv : $0.movie }
        let unwanted = Tmdb.genres.filter { excluded.contains($0.slug) }.compactMap { series ? $0.tv : $0.movie }
        if !wanted.isEmpty { p.append(("with_genres", Set(wanted).sorted().map(String.init).joined(separator: "|"))) }
        if !unwanted.isEmpty { p.append(("without_genres", Set(unwanted).sorted().map(String.init).joined(separator: ","))) }
        if let years {
            let field = series ? "first_air_date" : "primary_release_date"
            p.append(("\(field).gte", "\(years.lowerBound)-01-01"))
            p.append(("\(field).lte", "\(years.upperBound)-12-31"))
        }
        let minutes = Self.runtime(length, series: series)
        if let m = minutes.min { p.append(("with_runtime.gte", String(m))) }
        if let m = minutes.max { p.append(("with_runtime.lte", String(m))) }
        if series, format == .series {
            switch seriesStatus {
            case .airing: p.append(("with_status", "0|2"))     // en emisión o en producción
            case .ended: p.append(("with_status", "3|4"))      // terminada o cancelada
            case .any: break
            }
        }
        if !countries.isEmpty { p.append(("with_origin_country", countries.sorted().joined(separator: "|"))) }
        if !series, !studios.isEmpty { p.append(("with_companies", studios.sorted().map(String.init).joined(separator: "|"))) }
        // Qué tan conocida y la calificación: el piso de votos evita lo que nadie ha visto (salvo «Para pocos»).
        var rating = minRating
        var votes: (min: Int?, max: Int?) = ((years?.lowerBound ?? 0) >= currentYear ? 30 : 100, nil)
        var order = "popularity.desc"
        switch fame {
        case .any: break
        case .gems: rating = max(rating ?? 0, 7.2); votes = (150, 2500); order = "vote_average.desc"
        case .classics: rating = max(rating ?? 0, 7.5); votes = (series ? 2000 : 8000, nil); order = "vote_average.desc"
        case .niche: votes = (20, 300); order = "vote_average.desc"
        case .blockbusters: votes = (3000, nil); order = series ? "popularity.desc" : "revenue.desc"
        }
        if !providers.isEmpty {
            p.append(("with_watch_providers", providers.sorted().map(String.init).joined(separator: "|")))
            p.append(("watch_region", region))
            p.append(("with_watch_monetization_types", "flatrate"))
        }
        // El orden que elegiste manda sobre el de «Qué tan conocida» (el piso de votos se queda: no sale lo que nadie vio).
        switch sort {
        case .popular: break
        case .rating: order = "vote_average.desc"
        case .newest:
            order = series ? "first_air_date.desc" : "primary_release_date.desc"
            p.append((series ? "first_air_date.lte" : "primary_release_date.lte", today))
        }
        if let rating { p.append(("vote_average.gte", String(format: "%.1f", rating))) }
        if let v = votes.min { p.append(("vote_count.gte", String(v))) }
        if let v = votes.max { p.append(("vote_count.lte", String(v))) }
        p.append(("sort_by", order))
        p.append(("include_adult", "false"))
        return p
    }
}

extension Tmdb {
    /// Resultados del filtro avanzado: una página de /discover por tipo, en el orden del filtro (películas y series
    /// intercaladas cuando van los dos). Cada fila trae su IMDb después (`ForYou.suggestions`).
    public func discover(_ filter: AdvancedFilter, page: Int = 1) async throws -> [TmdbRow] {
        // Películas y series a la par (con «Todo» tarda lo de una sola búsqueda).
        let lists = try await withThrowingTaskGroup(of: (Int, [TmdbRow]).self) { group in
            for (i, kind) in filter.kinds.enumerated() {
                group.addTask {
                    let data = try await get("/discover/\(Tmdb.kinds[kind] ?? "movie")", filter.params(kind: kind) + [("page", String(page))])
                    return (i, (data["results"]?.array ?? []).compactMap { r in
                        r["id"]?.intValue.map { TmdbRow(kind: kind, id: $0, voteAverage: r["vote_average"]?.doubleValue ?? 0, popularity: r["popularity"]?.doubleValue ?? 0) }
                    })
                }
            }
            var out = [[TmdbRow]](repeating: [], count: filter.kinds.count)
            for try await (i, rows) in group { out[i] = rows }
            return out
        }
        // Intercaladas: una y una, para que «Todo» no sean veinte películas y luego veinte series.
        var out: [TmdbRow] = []
        for i in 0..<(lists.map(\.count).max() ?? 0) { for list in lists where i < list.count { out.append(list[i]) } }
        return out
    }
}
