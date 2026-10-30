import Foundation

/// «Lo que ves» (docs/producto/muvy-busqueda-premios/prototipo-wrapped.html): tu historial de Trakt contado para un periodo
/// (la semana, el mes, el año o desde siempre). Lo mismo alimenta las gráficas y las historias del Wrapped.
public struct WatchingStats: Sendable, Equatable {
    public enum Period: String, Sendable, CaseIterable { case week, month, year, all }
    public struct Title: Sendable, Equatable, Identifiable {
        public var imdb: String, kind: String, title: String, plays: Int, minutes: Int
        public var id: String { imdb }
        public var poster: String { String(format: ForYou.metahubPoster, imdb) }
    }
    /// Una barra: un día (semana), una semana (mes), un mes (año) o un año (siempre).
    public struct Bucket: Sendable, Equatable { public var start: Date; public var minutes: Int }

    public var period: Period
    public var start: Date, end: Date
    public var minutes: Int
    public var movies: Int, episodes: Int
    /// Títulos distintos (una serie cuenta una vez).
    public var titles: Int
    public var days: [Date: YearInReview.Day]
    public var longestStreak: Int
    /// Días seguidos hasta hoy (0 si hoy y ayer no viste nada).
    public var currentStreak: Int
    public var buckets: [Bucket]
    /// Géneros de Trakt («drama») con cuántas veces, de más a menos.
    public var genres: [(name: String, count: Int)]
    public var top: [Title]
    public var busiestDay: (day: Date, minutes: Int)?

    public var hours: Int { minutes / 60 }
    public var isEmpty: Bool { movies + episodes == 0 }

    public static func == (a: WatchingStats, b: WatchingStats) -> Bool {
        a.period == b.period && a.start == b.start && a.minutes == b.minutes && a.titles == b.titles && a.top == b.top
            && a.buckets == b.buckets && a.genres.map(\.name) == b.genres.map(\.name)
    }

    /// El inicio de un periodo: lunes de esta semana, día 1 del mes, 1 de enero, o lo más viejo que haya.
    public static func start(of period: Period, now: Date, calendar: Calendar, oldest: Date? = nil) -> Date {
        switch period {
        case .week: return calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
        case .month: return calendar.dateInterval(of: .month, for: now)?.start ?? calendar.startOfDay(for: now)
        case .year: return calendar.dateInterval(of: .year, for: now)?.start ?? calendar.startOfDay(for: now)
        case .all: return calendar.startOfDay(for: oldest ?? now)
        }
    }

    public static func make(_ all: [TraktPlay], period: Period, now: Date, calendar: Calendar) -> WatchingStats {
        let start = start(of: period, now: now, calendar: calendar, oldest: all.map(\.at).min())
        let plays = all.filter { $0.at >= start && $0.at <= now }
        var days: [Date: YearInReview.Day] = [:], perDay: [Date: Int] = [:]
        var minutes = 0, movies = 0, episodes = 0
        var genres: [String: Int] = [:], titles: [String: Title] = [:]
        for p in plays {
            let day = calendar.startOfDay(for: p.at)
            let kind: YearInReview.Day = p.kind == "movie" ? .movies : .series
            days[day] = days[day].map { $0 == kind ? $0 : .both } ?? kind
            perDay[day, default: 0] += p.minutes
            minutes += p.minutes
            if p.kind == "movie" { movies += 1 } else { episodes += 1 }
            for g in p.genres { genres[g, default: 0] += 1 }
            var t = titles[p.imdb] ?? Title(imdb: p.imdb, kind: p.kind, title: p.title, plays: 0, minutes: 0)
            t.plays += 1; t.minutes += p.minutes
            titles[p.imdb] = t
        }
        // Rachas: la más larga del periodo y la de hoy (contando ayer, por si hoy aún no ves nada).
        let sorted = days.keys.sorted()
        var longest = 0, run = 0, previous: Date?
        for day in sorted {
            if let previous, calendar.dateComponents([.day], from: previous, to: day).day == 1 { run += 1 } else { run = 1 }
            longest = max(longest, run); previous = day
        }
        var current = 0
        var cursor = calendar.startOfDay(for: now)
        if days[cursor] == nil, let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) { cursor = yesterday }
        while days[cursor] != nil, let before = calendar.date(byAdding: .day, value: -1, to: cursor) { current += 1; cursor = before }

        let unit: Calendar.Component = switch period { case .week: .day; case .month: .weekOfYear; case .year: .month; case .all: .year }
        var buckets: [Bucket] = []
        var bucketStart = calendar.dateInterval(of: unit, for: start)?.start ?? start
        while bucketStart <= now {
            let next = calendar.date(byAdding: unit, value: 1, to: bucketStart) ?? now
            let m = plays.filter { $0.at >= bucketStart && $0.at < next }.reduce(0) { $0 + $1.minutes }
            buckets.append(Bucket(start: bucketStart, minutes: m))
            bucketStart = next
        }
        let busiest = perDay.max { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) }
        return WatchingStats(period: period, start: start, end: now, minutes: minutes, movies: movies, episodes: episodes,
                             titles: titles.count, days: days, longestStreak: longest, currentStreak: current, buckets: buckets,
                             genres: genres.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map { ($0.key, $0.value) },
                             top: titles.values.sorted { $0.minutes != $1.minutes ? $0.minutes > $1.minutes : $0.title < $1.title },
                             busiestDay: busiest.map { ($0.key, $0.value) })
    }
}
