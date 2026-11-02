import Foundation

/// El filtro avanzado de Buscar (docs/producto/muvy-busqueda-premios/filtro-a.md): el formato arriba, seis principales
/// (género, época, tiempo, calificación, qué tan conocida y dónde verla) y, en «Ver más», origen, premios y estudios. Todo
/// se traduce a búsquedas de TMDB (/discover) por tipo, salvo los premios, que salen de los ganadores que trae la app; sin
/// conteos en vivo: los resultados salen al tocar «Ver resultados».
public struct AdvancedFilter: Sendable, Equatable, Hashable, Codable {
    public enum Format: String, Sendable, CaseIterable, Codable { case all, movie, series }
    /// En qué orden salen: lo más popular, lo mejor calificado o lo más nuevo.
    public enum Sort: String, Sendable, CaseIterable, Codable { case popular, rating, newest }
    /// Solo con «Series»: en emisión o terminadas.
    public enum SeriesStatus: String, Sendable, CaseIterable, Codable { case any, airing, ended }
    /// El tiempo que tienes: corta, normal o larga (en series, lo que dura un capítulo), o que acabe antes de una hora.
    public enum Length: String, Sendable, CaseIterable, Codable { case any, short, regular, long, before }
    /// «Qué tan conocida»: el cuadro fama × calificación.
    public enum Fame: String, Sendable, CaseIterable, Codable { case any, gems, classics, niche, blockbusters }

    public var format: Format = .all
    public var seriesStatus: SeriesStatus = .any
    /// Slugs de `Tmdb.filterGenres`: los que quieres (cualquiera de ellos) y los que no.
    public var genres: Set<String> = []
    public var excluded: Set<String> = []
    /// Años de estreno, inclusivos (nil: cualquiera).
    public var years: ClosedRange<Int>?
    public var length: Length = .any
    /// Con «Que acabe antes de las…»: la hora, 0–24 (23.5 son las 11:30 pm).
    public var endsBy: Double = 23.5
    /// El minuto del día de ahora (lo pone el cajón al elegir la hora): con él se calcula cuánto cabe.
    public var nowMinute = AdvancedFilter.minuteOfDay(Date())
    /// «Repartido por décadas»: una de cada década del rango, para no caer siempre en lo reciente.
    public var spread = false
    /// Calificación mínima, 0–10 (la de TMDB; nil: cualquiera).
    public var minRating: Double?
    public var fame: Fame = .any
    /// Países de origen (ISO 3166, «MX») y estudios (ids de TMDB).
    public var countries: Set<String> = []
    public var studios: Set<Int> = []
    /// Premios (ids de `Awards.all`: oscar, palm, globe, bafta, ariel, emmy): los resultados son sus ganadores.
    public var awards: Set<String> = []
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

    /// Las épocas rápidas de la regla.
    public static let firstYear = 1950
    public static let classics = 1900...1989
    public var releases: ClosedRange<Int> { (currentYear - 1)...currentYear }

    /// El filtro sin la hora de ahora (la hora cambia sola; la búsqueda no).
    public var withoutClock: AdvancedFilter { var f = self; f.nowMinute = 0; return f }

    public static func minuteOfDay(_ date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    /// Los minutos que faltan para `endsBy` desde `nowMinute` (si la hora ya pasó, es la de mañana).
    public var minutesLeft: Int {
        let end = Int((endsBy * 60).rounded())
        let left = (end - nowMinute + 24 * 60) % (24 * 60)
        return left == 0 ? 24 * 60 : left
    }

    static func day(_ date: Date) -> String {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// Los géneros elegidos que TMDB no tiene para series (Terror, Romance, Suspenso, Aventura): solo filtran películas.
    public var moviesOnlyGenres: [TmdbGenre] { Tmdb.filterGenres.filter { genres.contains($0.slug) && $0.tv == nil } }

    /// Cuántos filtros están puestos (el «Ver resultados · 3» y el punto en la puerta).
    public var activeCount: Int {
        [format != .all, seriesStatus != .any && format == .series, !genres.isEmpty || !excluded.isEmpty, years != nil || spread,
         length != .any, minRating != nil, fame != .any, !countries.isEmpty, !studios.isEmpty, !providers.isEmpty, !awards.isEmpty].filter { $0 }.count
    }
    public var isEmpty: Bool { activeCount == 0 }

    /// Qué tipos se buscan: los dos, o solo uno. Estudios y «Taquilleras» son de películas.
    public var kinds: [String] {
        // Si todos los géneros que elegiste no existen en series (Terror, Romance…), no se buscan series: antes «Series +
        // Terror» pedía las series sin género y salían todas.
        let onlyMovieGenres = !genres.isEmpty && moviesOnlyGenres.count == genres.count
        switch format {
        case .movie: return ["movie"]
        case .series: return onlyMovieGenres ? [] : ["series"]
        case .all:
            // Taquilleras son películas.
            return fame == .blockbusters || onlyMovieGenres ? ["movie"] : ["movie", "series"]
        }
    }

    /// Los minutos de cada largo (en series se mide el capítulo).
    func runtime(series: Bool) -> (min: Int?, max: Int?) {
        if length == .before { return (series ? nil : Self.featureMinutes, max(minutesLeft, 20)) }
        return Self.runtime(length, series: series)
    }

    /// ¿Cabe en el tiempo que elegiste? Solo se revisa en series (con la duración del capítulo de su ficha): en películas
    /// ya lo filtró TMDB. Sin duración conocida, sí (no se tira por falta de dato).
    public func fits(kind: String, runtime minutes: Int?) -> Bool {
        guard kind == "series", length != .any, let minutes else { return true }
        let range = runtime(series: true)
        return (range.min.map { minutes >= $0 } ?? true) && (range.max.map { minutes <= $0 } ?? true)
    }

    /// Lo menos que dura una película (sin esto «Corta» traía cortometrajes de 5 minutos).
    static let featureMinutes = 60

    static func runtime(_ length: Length, series: Bool) -> (min: Int?, max: Int?) {
        switch (length, series) {
        case (.before, _): return (nil, nil)
        case (.any, _): return (nil, nil)
        case (.short, false): return (featureMinutes, 95)
        case (.regular, false): return (96, 130)
        case (.long, false): return (131, nil)
        case (.short, true): return (nil, 30)
        case (.regular, true): return (30, 50)
        case (.long, true): return (50, nil)
        }
    }

    /// Los parámetros de /discover para un tipo («movie» o «series»).
    public func params(kind: String) -> [(String, String)] { params(kind: kind, years: years) }

    /// Las décadas de «Repartido por décadas»: las del rango (o de 1950 a hoy), cada una recortada al rango.
    public var decades: [ClosedRange<Int>] {
        let range = years ?? Self.firstYear...currentYear
        let lo = max(range.lowerBound, Self.firstYear), hi = range.upperBound
        guard lo <= hi else { return [range] }
        return stride(from: lo / 10 * 10, through: hi, by: 10).map { max($0, lo)...min($0 + 9, hi) }
    }

    /// Los parámetros de /discover para un tipo y unos años (una década, con «Repartido por décadas»).
    /// Lo que TMDB llama series pero no lo son para ver aquí: noticieros, realities, telenovelas diarias y programas de
    /// entrevistas (y lo infantil, salvo que pidas Familia o Animación). Antes llenaban «Series» de relleno.
    static let tvFiller = [10763, 10764, 10766, 10767], tvKids = 10762

    /// ¿Es de un país donde casi nadie vota en TMDB? (México, Corea… sí; Estados Unidos e Inglaterra, no.) Ahí los pisos de
    /// votos bajan: con los de siempre una película mexicana muy vista no llegaba.
    var smallMarket: Bool { !countries.isEmpty && !countries.isSubset(of: ["US", "GB"]) }

    /// Los parámetros de /discover para un tipo y unos años (una década, con «Repartido por décadas»).
    public func params(kind: String, years: ClosedRange<Int>?) -> [(String, String)] {
        let series = kind == "series"
        var p: [(String, String)] = []
        let wanted = Tmdb.filterGenres.filter { genres.contains($0.slug) }.compactMap { series ? $0.tv : $0.movie }
        var unwanted = Tmdb.filterGenres.filter { excluded.contains($0.slug) }.compactMap { series ? $0.tv : $0.movie }
        if series {
            unwanted += Self.tvFiller
            if !genres.contains("familia"), !genres.contains("animacion") { unwanted.append(Self.tvKids) }
        }
        if !wanted.isEmpty { p.append(("with_genres", Set(wanted).sorted().map(String.init).joined(separator: "|"))) }
        if !unwanted.isEmpty { p.append(("without_genres", Set(unwanted).sorted().map(String.init).joined(separator: ","))) }
        // Nunca lo que aún no se estrena (antes solo con «Más nuevas»): con o sin años, hasta hoy.
        let field = series ? "first_air_date" : "primary_release_date"
        if let years { p.append(("\(field).gte", "\(years.lowerBound)-01-01")) }
        let end = years.map { "\($0.upperBound)-12-31" } ?? today
        p.append(("\(field).lte", min(end, today)))
        // En series TMDB mide el capítulo con un dato que casi ninguna trae: filtrar ahí dejaba fuera casi todo. El largo de
        // una serie se revisa después, con su ficha (`AdvancedFilterModel`).
        if !series {
            let minutes = runtime(series: false)
            if let m = minutes.min { p.append(("with_runtime.gte", String(m))) }
            if let m = minutes.max { p.append(("with_runtime.lte", String(m))) }
        }
        if series, format == .series {
            switch seriesStatus {
            case .airing: p.append(("with_status", "0|2"))     // en emisión o en producción
            case .ended: p.append(("with_status", "3|4"))      // terminada o cancelada
            case .any: break
            }
        }
        if !countries.isEmpty { p.append(("with_origin_country", countries.sorted().joined(separator: "|"))) }
        if !series, !studios.isEmpty { p.append(("with_companies", studios.sorted().map(String.init).joined(separator: "|"))) }
        // El piso de votos es lo que separa lo que la gente ve de las rarezas: con 25 salían títulos de moda en otro país y
        // con «Mejor calificadas» ganaban especiales con tres votos de 10. Lo popular pide 100 (series 50); lo mejor calificado,
        // 300 (series 200), como el «Top Rated» de TMDB. De un país chico o recién estrenado, mucho menos.
        let scale = smallMarket ? 0.2 : 1.0
        let recent = (years?.lowerBound ?? 0) >= currentYear - 1
        func floor(_ movie: Int, _ tv: Int) -> Int { max(10, Int((Double(series ? tv : movie) * scale * (recent ? 0.3 : 1)).rounded())) }
        var rating = minRating
        var votes: (min: Int?, max: Int?) = (sort == .rating ? floor(300, 200) : floor(100, 50), nil)
        var order = "popularity.desc"
        // Cada «Qué tan conocida» va por popularidad dentro de su rango (antes por calificación, y el menú decía «Más
        // populares»): así salen las joyas que sí se reconocen, no la de 9.8 que vieron 40 personas.
        switch fame {
        case .any: break
        case .gems: rating = max(rating ?? 0, 7.2); votes = (floor(300, 200), Int(3000 * scale))
        case .classics: rating = max(rating ?? 0, 7.5); votes = (floor(3000, 800), nil)
        case .niche: rating = max(rating ?? 0, 6.5); votes = (floor(50, 30), Int(500 * scale))
        case .blockbusters: votes = (floor(3000, 1000), nil); order = series ? "popularity.desc" : "revenue.desc"
        }
        if !providers.isEmpty {
            p.append(("with_watch_providers", providers.sorted().map(String.init).joined(separator: "|")))
            p.append(("watch_region", region))
            p.append(("with_watch_monetization_types", "flatrate|free|ads"))   // también lo gratis (ViX, Pluto TV)
        }
        // El orden que elegiste manda sobre el de «Qué tan conocida».
        switch sort {
        case .popular: break
        case .rating: order = "vote_average.desc"; votes.min = max(votes.min ?? 0, floor(300, 200))
        case .newest: order = series ? "first_air_date.desc" : "primary_release_date.desc"
        }
        if let rating { p.append(("vote_average.gte", String(format: "%.1f", rating))) }
        if let v = votes.min { p.append(("vote_count.gte", String(v))) }
        if let v = votes.max { p.append(("vote_count.lte", String(v))) }
        p.append(("sort_by", order))
        p.append(("include_adult", "false"))
        return p
    }
}

extension AdvancedFilter {
    private enum Keys: String, CodingKey {
        case format, seriesStatus, genres, excluded, years, length, endsBy, spread, minRating, fame, countries, studios, awards,
             providers, region, hideWatched, sort
    }

    /// Lo guardado de una versión anterior (sin los campos nuevos) se lee igual: lo que falta queda de entrada.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        self.init()
        format = try c.decodeIfPresent(Format.self, forKey: .format) ?? format
        seriesStatus = try c.decodeIfPresent(SeriesStatus.self, forKey: .seriesStatus) ?? seriesStatus
        genres = try c.decodeIfPresent(Set<String>.self, forKey: .genres) ?? genres
        excluded = try c.decodeIfPresent(Set<String>.self, forKey: .excluded) ?? excluded
        years = try c.decodeIfPresent(ClosedRange<Int>.self, forKey: .years)
        length = (try? c.decodeIfPresent(Length.self, forKey: .length)) ?? length
        endsBy = try c.decodeIfPresent(Double.self, forKey: .endsBy) ?? endsBy
        spread = try c.decodeIfPresent(Bool.self, forKey: .spread) ?? spread
        minRating = try c.decodeIfPresent(Double.self, forKey: .minRating)
        fame = (try? c.decodeIfPresent(Fame.self, forKey: .fame)) ?? fame
        countries = try c.decodeIfPresent(Set<String>.self, forKey: .countries) ?? countries
        studios = try c.decodeIfPresent(Set<Int>.self, forKey: .studios) ?? studios
        awards = try c.decodeIfPresent(Set<String>.self, forKey: .awards) ?? awards
        providers = try c.decodeIfPresent(Set<Int>.self, forKey: .providers) ?? providers
        region = try c.decodeIfPresent(String.self, forKey: .region) ?? region
        hideWatched = try c.decodeIfPresent(Bool.self, forKey: .hideWatched) ?? hideWatched
        sort = (try? c.decodeIfPresent(Sort.self, forKey: .sort)) ?? sort
    }

    /// El día, el año y la hora de ahora no se guardan: al leerlo valen los de hoy.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(format, forKey: .format); try c.encode(seriesStatus, forKey: .seriesStatus)
        try c.encode(genres, forKey: .genres); try c.encode(excluded, forKey: .excluded); try c.encodeIfPresent(years, forKey: .years)
        try c.encode(length, forKey: .length); try c.encode(endsBy, forKey: .endsBy); try c.encode(spread, forKey: .spread)
        try c.encodeIfPresent(minRating, forKey: .minRating); try c.encode(fame, forKey: .fame)
        try c.encode(countries, forKey: .countries); try c.encode(studios, forKey: .studios); try c.encode(awards, forKey: .awards)
        try c.encode(providers, forKey: .providers); try c.encode(region, forKey: .region)
        try c.encode(hideWatched, forKey: .hideWatched); try c.encode(sort, forKey: .sort)
    }

    /// Los ganadores de los premios elegidos que cumplen el formato, la época y lo que ya viste (los demás filtros no
    /// aplican: los premios no traen género ni calificación). Del premio más reciente al más viejo; con «Más nuevas», por
    /// año de estreno.
    public func awardWinners(_ all: [AwardCollection] = Awards.all, hiding watched: Set<String> = []) -> [Suggestion] {
        var seen = Set<String>()
        var picked: [(kind: String, winner: AwardCollection.Winner)] = []
        for award in all where awards.contains(award.id) {
            if format == .movie, award.kind != "movie" { continue }
            if format == .series, award.kind == "movie" { continue }
            for w in award.winners {
                if let years, !years.contains(w.year) { continue }
                if hideWatched, watched.contains(w.imdb) { continue }
                picked.append((award.kind, w))
            }
        }
        let byNewest = sort == .newest
        picked.sort { byNewest ? $0.winner.year > $1.winner.year : $0.winner.awardYear > $1.winner.awardYear }
        let winners = picked.filter { seen.insert($0.winner.imdb).inserted }
        return winners.map { kind, w in Suggestion(art: w.imdb, kind: kind, title: w.title, year: w.year, reason: .console(String(w.awardYear))) }
    }
}

extension Tmdb {
    /// Resultados del filtro avanzado: una página de /discover por tipo, en el orden del filtro (películas y series
    /// intercaladas cuando van los dos). Cada fila trae su IMDb después (`ForYou.suggestions`).
    public func discover(_ filter: AdvancedFilter, page: Int = 1) async throws -> [TmdbRow] {
        try await discoverCounting(filter, page: page).rows
    }

    /// Lo mismo, con cuántos títulos hay en total (la suma de lo que TMDB dice de cada búsqueda). Con «Repartido por
    /// décadas» hay una búsqueda por década y tipo, y se intercalan: una de cada década, luego la siguiente.
    public func discoverCounting(_ filter: AdvancedFilter, page: Int = 1) async throws -> (rows: [TmdbRow], total: Int) {
        let spans: [ClosedRange<Int>?] = filter.spread ? filter.decades.map { Optional($0) } : [filter.years]
        let asks = spans.flatMap { span in filter.kinds.map { (kind: $0, years: span) } }
        let lists = try await withThrowingTaskGroup(of: (Int, [TmdbRow], Int).self) { group in
            for (i, ask) in asks.enumerated() {
                group.addTask {
                    let data = try await get("/discover/\(Tmdb.kinds[ask.kind] ?? "movie")", filter.params(kind: ask.kind, years: ask.years) + [("page", String(page))])
                    let rows = (data["results"]?.array ?? []).compactMap { r in
                        r["id"]?.intValue.map { TmdbRow(kind: ask.kind, id: $0, voteAverage: r["vote_average"]?.doubleValue ?? 0, popularity: r["popularity"]?.doubleValue ?? 0) }
                    }
                    return (i, rows, data["total_results"]?.intValue ?? rows.count)
                }
            }
            var out = [(rows: [TmdbRow], total: Int)](repeating: ([], 0), count: asks.count)
            for try await (i, rows, total) in group { out[i] = (rows, total) }
            return out
        }
        // Intercaladas: una y una, para que «Todo» no sean veinte películas y luego veinte series. Por calificación, juntas y
        // en orden (intercaladas quedaba un 6.9 junto a un 8.8).
        var out: [TmdbRow] = []
        for i in 0..<(lists.map(\.rows.count).max() ?? 0) { for list in lists where i < list.rows.count { out.append(list.rows[i]) } }
        if filter.sort == .rating { out.sort { $0.voteAverage > $1.voteAverage } }
        return (out, lists.reduce(0) { $0 + $1.total })
    }
}
