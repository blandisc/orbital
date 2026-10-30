import Foundation

// «Lo mejor del género» y «Temporadas» (Para ti › Listas): los mismos géneros, temporadas, pisos de votos y respaldos que la
// TV (`orbital/library/tmdb.py`: GENRES, SEASONS, genre_top, keyword_id, season_titles, ordered_seasons). El iPhone los
// calcula con su propia clave de TMDB.

/// Un día del año sin año (mes y día): las temporadas se repiten cada año. Se comparan como en la TV: mes y luego día.
public struct MonthDay: Hashable, Comparable, Sendable {
    public var month: Int, day: Int
    public init(_ month: Int, _ day: Int) { self.month = month; self.day = day }
    public static func < (a: MonthDay, b: MonthDay) -> Bool { (a.month, a.day) < (b.month, b.day) }
}

/// Un género de «Lo mejor del género»: id de película y, si TMDB tiene un género de serie que corresponde, el de serie.
/// Acción y aventura en series es uno solo (10759): lo usa Acción. Ciencia ficción y fantasía en series es uno (10765): lo usan
/// las dos. Terror, romance, suspenso y aventura no tienen género de serie propio.
public struct TmdbGenre: Hashable, Sendable {
    public let slug: String, title: String, movie: Int, tv: Int?
    public init(_ slug: String, _ title: String, _ movie: Int, _ tv: Int?) { self.slug = slug; self.title = title; self.movie = movie; self.tv = tv }
}

/// Una temporada de «Temporadas». `queries` se resuelven en TMDB (/search/keyword); las fechas no se enciman y Navidad cruza el año.
public struct TmdbSeason: Hashable, Sendable {
    public let slug: String, title: String, queries: [String], start: MonthDay, end: MonthDay, blurb: String
}

/// Una película o serie de discover, con lo que sirve para ordenar.
public struct TmdbRow: Hashable, Sendable {
    public var kind: String, id: Int, voteAverage: Double, popularity: Double
    public init(kind: String, id: Int, voteAverage: Double = 0, popularity: Double = 0) {
        self.kind = kind; self.id = id; self.voteAverage = voteAverage; self.popularity = popularity
    }
}

/// De dónde salió el Top de un género: por nota, por popularidad del año, o del año anterior (por nota o por popularidad).
public enum GenreBasis: String, Sendable, Equatable {
    case votes, popular, previous, previousPopular = "previous-popular"
}

/// El Top de un género: las filas, el año de verdad (puede ser el anterior) y de dónde salió.
public struct GenreTopRows: Sendable, Equatable {
    public var rows: [TmdbRow], year: Int, basis: GenreBasis
}

/// Un género abierto: su Top (con puesto), el año que se pidió, el de verdad y de dónde salió (el título y el renglón de la
/// pantalla lo dicen, como `_genre_heading` de la TV).
public struct GenreChart: Sendable, Equatable {
    public var items: [Suggestion], asked: Int, year: Int, basis: GenreBasis
    public init(items: [Suggestion], asked: Int, year: Int, basis: GenreBasis) { self.items = items; self.asked = asked; self.year = year; self.basis = basis }
}

extension Tmdb {
    public static let genres: [TmdbGenre] = [
        TmdbGenre("accion", "Acción", 28, 10759), TmdbGenre("aventura", "Aventura", 12, nil), TmdbGenre("animacion", "Animación", 16, 16),
        TmdbGenre("comedia", "Comedia", 35, 35), TmdbGenre("crimen", "Crimen", 80, 80), TmdbGenre("documental", "Documental", 99, 99),
        TmdbGenre("drama", "Drama", 18, 18), TmdbGenre("familia", "Familia", 10751, 10751), TmdbGenre("fantasia", "Fantasía", 14, 10765),
        TmdbGenre("terror", "Terror", 27, nil), TmdbGenre("misterio", "Misterio", 9648, 9648), TmdbGenre("romance", "Romance", 10749, nil),
        TmdbGenre("ciencia-ficcion", "Ciencia ficción", 878, 10765), TmdbGenre("suspenso", "Suspenso", 53, nil),
    ]
    /// Primero con bastantes votos; si no llegan a 10, se baja el piso. Luego popularidad del año y, al final, el año anterior.
    public static let genreVoteFloors = [150, 50]

    public static let seasons: [TmdbSeason] = [
        TmdbSeason(slug: "halloween", title: "Halloween", queries: ["halloween"], start: MonthDay(9, 25), end: MonthDay(10, 31), blurb: "Sustos, brujas y calabazas"),
        TmdbSeason(slug: "muertos", title: "Día de Muertos", queries: ["day of the dead", "dia de los muertos"], start: MonthDay(11, 1), end: MonthDay(11, 10),
                   blurb: "Para recordar a los que se fueron"),
        TmdbSeason(slug: "navidad", title: "Navidad", queries: ["christmas"], start: MonthDay(11, 25), end: MonthDay(1, 6), blurb: "Para ver en familia"),
        TmdbSeason(slug: "sanvalentin", title: "San Valentín", queries: ["valentine's day"], start: MonthDay(1, 25), end: MonthDay(2, 14), blurb: "Para ver en pareja"),
        TmdbSeason(slug: "verano", title: "Verano", queries: ["summer"], start: MonthDay(6, 1), end: MonthDay(8, 31), blurb: "Sol, playa y vacaciones"),
    ]
    public static let seasonVoteFloors = [50, 10]

    /// Día del año en uno no bisiesto (el 29 de febrero cuenta como 28: ninguna temporada depende de él).
    static func dayOfYear(_ d: MonthDay) -> Int {
        let before = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334]
        return before[max(0, min(11, d.month - 1))] + min(d.day, d.month == 2 ? 28 : 31)
    }

    static func inSeason(start: MonthDay, end: MonthDay, day: MonthDay) -> Bool {
        if start <= end { return start <= day && day <= end }
        return day >= start || day <= end   // cruza el año (Navidad)
    }

    static func daysUntil(_ start: MonthDay, from day: MonthDay) -> Int {
        let begin = dayOfYear(start), today = dayOfYear(day)
        return begin >= today ? begin - today : begin + 365 - today
    }

    /// La que va hoy primero (o, entre temporadas, la siguiente en llegar) y el resto en el orden en que llegan.
    public static func orderedSeasons(today: Date, calendar: Calendar = .current, seasons: [TmdbSeason] = Tmdb.seasons) -> [TmdbSeason] {
        seasonCountdown(today: today, calendar: calendar, seasons: seasons).map(\.season)
    }

    /// Cada temporada con cuántos días faltan para que empiece (0: ya va), de la más cercana a la más lejana: la de arriba es
    /// «La temporada» de Para ti y las demás, «Próximas temporadas».
    public static func seasonCountdown(today: Date, calendar: Calendar = .current, seasons: [TmdbSeason] = Tmdb.seasons) -> [(season: TmdbSeason, days: Int)] {
        let parts = calendar.dateComponents([.month, .day], from: today)
        let day = MonthDay(parts.month ?? 1, parts.day ?? 1)
        func days(_ s: TmdbSeason) -> Int { inSeason(start: s.start, end: s.end, day: day) ? 0 : daysUntil(s.start, from: day) }
        return seasons.enumerated().map { (season: $0.element, days: days($0.element), offset: $0.offset) }
            .sorted { ($0.days, $0.offset) < ($1.days, $1.offset) }
            .map { (season: $0.season, days: $0.days) }
    }

    func discoverRows(_ kind: String, _ params: [(String, String)]) async throws -> [TmdbRow] {
        let data = try await get("/discover/\(Tmdb.kinds[kind] ?? "movie")", params + [("page", "1")])
        return (data["results"]?.array ?? []).compactMap { r in
            guard let id = r["id"]?.intValue else { return nil }
            return TmdbRow(kind: kind, id: id, voteAverage: r["vote_average"]?.doubleValue ?? 0, popularity: r["popularity"]?.doubleValue ?? 0)
        }
    }

    /// Sin repetir (mismo tipo e id), de mejor a peor: por nota (y luego popularidad) o por popularidad (y luego nota).
    static func rank(_ found: [TmdbRow], byVotes: Bool) -> [TmdbRow] {
        var seen = Set<String>()
        let unique = found.filter { seen.insert("\($0.kind):\($0.id)").inserted }
        return unique.sorted { a, b in
            let (pa, pb) = byVotes ? (a.voteAverage, b.voteAverage) : (a.popularity, b.popularity)
            let (sa, sb) = byVotes ? (a.popularity, b.popularity) : (a.voteAverage, b.voteAverage)
            if pa != pb { return pa > pb }
            if sa != sb { return sa > sb }
            if a.kind != b.kind { return a.kind < b.kind }
            return a.id < b.id
        }
    }

    /// Películas y series de un género en un año, juntas, de mejor a peor según `sort`.
    func genreRows(movie: Int?, tv: Int?, year: Int, sort: String, floor: Int) async throws -> [TmdbRow] {
        var extra = [("sort_by", sort)]
        if floor > 0 { extra.append(("vote_count.gte", String(floor))) }
        var found: [TmdbRow] = []
        if let movie, movie > 0 { found += try await discoverRows("movie", [("with_genres", String(movie)), ("primary_release_year", String(year))] + extra) }
        if let tv, tv > 0 { found += try await discoverRows("series", [("with_genres", String(tv)), ("first_air_date_year", String(year))] + extra) }
        return Tmdb.rank(found, byVotes: sort.hasPrefix("vote"))
    }

    /// El Top del género en `year`: pide nota con un piso de votos; si no hay 10, baja el piso, luego lo más popular de ese año
    /// y, al final, el año anterior (por nota y luego por popularidad). `year` del resultado es el año de verdad.
    public func genreTop(movie: Int?, tv: Int?, year: Int) async throws -> GenreTopRows {
        for floor in Tmdb.genreVoteFloors {
            let rows = try await genreRows(movie: movie, tv: tv, year: year, sort: "vote_average.desc", floor: floor)
            if rows.count >= 10 { return GenreTopRows(rows: Array(rows.prefix(20)), year: year, basis: .votes) }
        }
        let popular = try await genreRows(movie: movie, tv: tv, year: year, sort: "popularity.desc", floor: 0)
        if popular.count >= 10 { return GenreTopRows(rows: Array(popular.prefix(20)), year: year, basis: .popular) }
        let previous = year - 1
        let voted = try await genreRows(movie: movie, tv: tv, year: previous, sort: "vote_average.desc", floor: Tmdb.genreVoteFloors.last ?? 0)
        if voted.count >= 10 { return GenreTopRows(rows: Array(voted.prefix(20)), year: previous, basis: .previous) }
        let last = try await genreRows(movie: movie, tv: tv, year: previous, sort: "popularity.desc", floor: 0)
        return GenreTopRows(rows: Array(last.prefix(20)), year: previous, basis: .previousPopular)
    }

    /// El id de una palabra clave de TMDB. Se busca en inglés (los nombres canónicos están en inglés) y gana el nombre exacto;
    /// si no hay, el primer resultado. Nil si ninguna consulta trae nada.
    public func keywordID(_ queries: [String]) async throws -> Int? {
        for query in queries {
            let data = try await get("/search/keyword", [("query", query), ("language", "en-US")])
            let results = (data["results"]?.array ?? []).filter { $0["id"]?.intValue != nil && !($0["name"]?.string ?? "").isEmpty }
            let exact = results.filter { ($0["name"]?.string ?? "").lowercased() == query.lowercased() }
            if let pick = (exact.first ?? results.first)?["id"]?.intValue { return pick }
        }
        return nil
    }

    /// Películas y series con esa palabra clave, lo más popular primero (en el idioma de la app). Si con el piso de votos no hay
    /// 10, lo baja y al final quita el piso.
    public func seasonTitles(keywordID: Int) async throws -> [TmdbRow] {
        var rows: [TmdbRow] = []
        for floor in Tmdb.seasonVoteFloors + [0] {
            var extra = [("with_keywords", String(keywordID)), ("sort_by", "popularity.desc")]
            if floor > 0 { extra.append(("vote_count.gte", String(floor))) }
            var found: [TmdbRow] = []
            for kind in ["movie", "series"] { found += try await discoverRows(kind, extra) }
            rows = Tmdb.rank(found, byVotes: false)
            if rows.count >= 10 || floor == 0 { return Array(rows.prefix(20)) }
        }
        return Array(rows.prefix(20))
    }
}
