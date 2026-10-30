import Foundation

/// El filtro avanzado de Buscar (docs/producto/muvy-busqueda-premios/prototipo-filtro.html): seis principales (formato,
/// género, época, tiempo, calificación y qué tan conocida) y, en «Ver más», origen y estudios. Todo se traduce a una sola
/// búsqueda de TMDB (/discover) por tipo; sin conteos en vivo: los resultados salen al tocar «Ver resultados».
public struct AdvancedFilter: Sendable, Equatable, Hashable {
    public enum Format: String, Sendable, CaseIterable { case all, movie, series }
    /// Solo con «Series»: en emisión o terminadas.
    public enum SeriesStatus: String, Sendable, CaseIterable { case any, airing, ended }
    /// El tiempo que tienes: corta, normal o larga (en series, lo que dura un capítulo).
    public enum Length: String, Sendable, CaseIterable { case any, short, regular, long }
    /// «Qué tan conocida»: el cuadro fama × calificación.
    public enum Fame: String, Sendable, CaseIterable { case any, gems, classics, niche, blockbusters }

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

    public init() {}

    /// Cuántos filtros están puestos (el «Ver resultados · 3» y el punto en la puerta).
    public var activeCount: Int {
        [format != .all, seriesStatus != .any && format == .series, !genres.isEmpty || !excluded.isEmpty, years != nil,
         length != .any, minRating != nil, fame != .any, !countries.isEmpty, !studios.isEmpty].filter { $0 }.count
    }
    public var isEmpty: Bool { activeCount == 0 }

    /// Qué tipos se buscan: los dos, o solo uno. Estudios y «Taquilleras» son de películas.
    public var kinds: [String] {
        switch format {
        case .movie: return ["movie"]
        case .series: return ["series"]
        case .all: return fame == .blockbusters ? ["movie"] : ["movie", "series"]
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
        var votes: (min: Int?, max: Int?) = (100, nil)
        var sort = "popularity.desc"
        switch fame {
        case .any: break
        case .gems: rating = max(rating ?? 0, 7.2); votes = (150, 2500); sort = "vote_average.desc"
        case .classics: rating = max(rating ?? 0, 7.5); votes = (series ? 2000 : 8000, nil); sort = "vote_average.desc"
        case .niche: votes = (20, 300); sort = "vote_average.desc"
        case .blockbusters: votes = (3000, nil); sort = series ? "popularity.desc" : "revenue.desc"
        }
        if let rating { p.append(("vote_average.gte", String(format: "%.1f", rating))) }
        if let v = votes.min { p.append(("vote_count.gte", String(v))) }
        if let v = votes.max { p.append(("vote_count.lte", String(v))) }
        p.append(("sort_by", sort))
        p.append(("include_adult", "false"))
        return p
    }
}

extension Tmdb {
    /// Resultados del filtro avanzado: una página de /discover por tipo, en el orden del filtro (películas y series
    /// intercaladas cuando van los dos). Cada fila trae su IMDb después (`ForYou.suggestions`).
    public func discover(_ filter: AdvancedFilter, page: Int = 1) async throws -> [TmdbRow] {
        var lists: [[TmdbRow]] = []
        for kind in filter.kinds {
            let data = try await get("/discover/\(Tmdb.kinds[kind] ?? "movie")", filter.params(kind: kind) + [("page", String(page))])
            lists.append((data["results"]?.array ?? []).compactMap { r in
                r["id"]?.intValue.map { TmdbRow(kind: kind, id: $0, voteAverage: r["vote_average"]?.doubleValue ?? 0, popularity: r["popularity"]?.doubleValue ?? 0) }
            })
        }
        // Intercaladas: una y una, para que «Todo» no sean veinte películas y luego veinte series.
        var out: [TmdbRow] = []
        for i in 0..<(lists.map(\.count).max() ?? 0) { for list in lists where i < list.count { out.append(list[i]) } }
        return out
    }
}
