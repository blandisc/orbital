import Foundation

/// «Tu año»: lo guardado de una sugerencia y el resumen del año.

/// Una sugerencia tal como se guarda en el teléfono (`Suggestion` lleva una tupla y un motivo con datos).
struct SavedSuggestion: Codable {
    var kind, imdb, title, overview, poster, wide: String
    var year, runtime, rank, movement, nextSeason, nextEpisode: Int?
    var logo: String?
    var reason: String
    var reasonText: String?
    var isNew: Bool

    init(_ s: Suggestion) {
        kind = s.kind; imdb = s.imdb; title = s.title; overview = s.overview; poster = s.poster; wide = s.wide
        year = s.year; runtime = s.runtime; rank = s.rank; movement = s.movement; logo = s.logo; isNew = s.isNew
        nextSeason = s.next?.season; nextEpisode = s.next?.episode
        switch s.reason {
        case .recommended: reason = "recommended"
        case .watching: reason = "watching"
        case .inWatchlist: reason = "inWatchlist"
        case .inList(let name): reason = "inList"; reasonText = name
        case .trending: reason = "trending"
        case .popular: reason = "popular"
        case .onPlatform(let name): reason = "onPlatform"; reasonText = name
        case .console(let text): reason = "console"; reasonText = text
        }
    }

    var suggestion: Suggestion {
        let why: SuggestionReason = switch reason {
        case "watching": .watching
        case "inWatchlist": .inWatchlist
        case "inList": .inList(reasonText ?? "")
        case "trending": .trending
        case "popular": .popular
        case "onPlatform": .onPlatform(reasonText ?? "")
        case "console": .console(reasonText ?? "")
        default: .recommended
        }
        var s = Suggestion(kind: kind, imdb: imdb, title: title, year: year, runtime: runtime, overview: overview, poster: poster, wide: wide,
                           logo: logo, reason: why)
        if let nextSeason, let nextEpisode { s.next = (nextSeason, nextEpisode) }
        s.rank = rank; s.movement = movement; s.isNew = isNew
        return s
    }
}

/// «Tu año»: lo que viste en el año, día por día (película, serie o las dos), horas, racha más larga, tu género y lo que más viste.
public struct YearInReview: Sendable, Equatable {
    public enum Day: Sendable, Equatable { case movies, series, both }
    public struct Top: Sendable, Equatable, Identifiable { public var imdb: String; public var kind: String; public var title: String; public var plays: Int; public var id: String { imdb } }
    public var year: Int
    public var days: [Date: Day]
    public var hours: Int
    public var movies: Int
    public var episodes: Int
    public var longestStreak: Int
    public var topGenre: String?
    public var top: [Top]
    /// Lo que viste cada día (en el orden en que lo viste): al tocar un día del mapa.
    public var plays: [Date: [TraktPlay]] = [:]

    public static func make(_ plays: [TraktPlay], year: Int, calendar: Calendar) -> YearInReview {
        var days: [Date: Day] = [:], minutes = 0, movies = 0, episodes = 0
        var genres: [String: Int] = [:], counts: [String: Top] = [:]
        var byDay: [Date: [TraktPlay]] = [:]
        for p in plays {
            let day = calendar.startOfDay(for: p.at)
            byDay[day, default: []].append(p)
            let kind: Day = p.kind == "movie" ? .movies : .series
            days[day] = days[day].map { $0 == kind ? $0 : .both } ?? kind
            minutes += p.minutes
            if p.kind == "movie" { movies += 1 } else { episodes += 1 }
            for g in p.genres { genres[g, default: 0] += 1 }
            counts[p.imdb, default: Top(imdb: p.imdb, kind: p.kind, title: p.title, plays: 0)].plays += 1
        }
        // La racha más larga: días seguidos con algo visto.
        var longest = 0, run = 0, previous: Date?
        for day in days.keys.sorted() {
            if let previous, let next = calendar.date(byAdding: .day, value: 1, to: previous), calendar.isDate(next, inSameDayAs: day) { run += 1 } else { run = 1 }
            longest = max(longest, run); previous = day
        }
        let top = counts.values.sorted { ($0.plays, $1.title) > ($1.plays, $0.title) }.prefix(10)
        return YearInReview(year: year, days: days, hours: Int((Double(minutes) / 60).rounded()), movies: movies, episodes: episodes,
                            longestStreak: longest, topGenre: genres.max { ($0.value, $1.key) < ($1.value, $0.key) }?.key, top: Array(top),
                            plays: byDay.mapValues { $0.sorted { $0.at < $1.at } })
    }
}
