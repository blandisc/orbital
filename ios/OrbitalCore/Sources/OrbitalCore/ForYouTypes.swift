import Foundation

/// Los tipos de «Para ti»: la sugerencia y su porqué, los grupos, los estrenos del calendario y una lista.

/// Por qué se te sugiere algo (la interfaz lo pone en tu idioma: «Recomendada», «En tu lista»…).
public enum SuggestionReason: Sendable, Equatable, Hashable {
    case recommended, watching, inWatchlist, inList(String), trending, popular, onPlatform(String)
    /// El motivo tal como lo dice tu Orbital (uno que el iPhone no calcula por sí mismo): se enseña igual que en la TV.
    case console(String)
}

/// Una sugerencia: una película o serie (siempre con IMDb: sin él no se podrían pedir fuentes).
public struct Suggestion: Sendable, Equatable, Identifiable {
    public var kind: String            // movie | series
    public var imdb: String
    public var title: String
    public var year: Int?
    public var runtime: Int?
    public var overview: String
    /// Los géneros, si la fuente los trae (Trakt): «Decide por mí» no tiene que pedirlos.
    public var genres: [String] = []
    /// La calificación de Trakt (0 a 10), si la fuente la trae: «Mejor calificadas en Trakt» en una lista.
    public var traktRating: Double?
    public var poster: String
    public var wide: String
    /// Logo del título (metahub), como en la TV; si no carga o no hay, la interfaz cae al nombre en texto.
    public var logo: String?
    public var reason: SuggestionReason
    public var next: (season: Int, episode: Int)?
    /// El puesto en un Top 10 (chart de Netflix, JustWatch…), si la lista lo trae. Nil: no se pinta número.
    public var rank: Int?
    /// Cuántos lugares subió (+) o bajó (−) en su lista desde la foto anterior; nil si no hay foto (no se inventan flechas).
    public var movement: Int?
    /// Entró a la lista en esta foto (semana o día).
    public var isNew = false
    public var id: String { imdb }

    public init(kind: String, imdb: String, title: String, year: Int? = nil, runtime: Int? = nil, overview: String = "", poster: String, wide: String,
                logo: String? = nil, reason: SuggestionReason, next: (season: Int, episode: Int)? = nil, rank: Int? = nil) {
        self.kind = kind; self.imdb = imdb; self.title = title; self.year = year; self.runtime = runtime; self.overview = overview
        self.poster = poster; self.wide = wide; self.logo = logo; self.reason = reason; self.next = next; self.rank = rank
    }

    public static func == (a: Suggestion, b: Suggestion) -> Bool {
        a.kind == b.kind && a.imdb == b.imdb && a.title == b.title && a.year == b.year && a.reason == b.reason
            && a.poster == b.poster && a.next?.season == b.next?.season && a.next?.episode == b.next?.episode
    }
}

public enum ForYouGroup: String, Sendable, Codable { case mine, discover, platforms }

/// Un día de «Próximos estrenos» con lo que sale (vacío en la semana: «Nada este día»).
public struct AiringDay: Sendable, Equatable, Identifiable {
    public var day: Date
    public var airings: [Airing]
    public var id: Date { day }

    /// Por día: solo los días con estrenos, en orden.
    public static func byDay(_ airings: [Airing]) -> [AiringDay] {
        var out: [AiringDay] = []
        for a in airings {
            if out.last?.day == a.day { out[out.count - 1].airings.append(a) } else { out.append(AiringDay(day: a.day, airings: [a])) }
        }
        return out
    }

    /// La semana desde hoy: siete días, también los que no tienen nada.
    public static func week(_ airings: [Airing], from now: Date, calendar: Calendar = .current, days: Int = 7) -> [AiringDay] {
        let today = calendar.startOfDay(for: now)
        return (0..<days).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
            .map { day in AiringDay(day: day, airings: airings.filter { $0.day == day }) }
    }
}

/// Un estreno de «Próximos estrenos»: la serie (pulsar abre su ficha), el día y la hora de aquí, el episodio y dónde sale.
/// Varios episodios de la misma serie el mismo día (las plataformas sueltan tres juntos) son uno solo: «T2 E4–E6».
public struct Airing: Sendable, Equatable, Identifiable {
    public var series: Suggestion
    public var season: Int
    public var first: Int
    public var last: Int
    public var count: Int
    public var episodeTitle: String
    public var aired: Date
    /// El día (a medianoche, en la hora de aquí).
    public var day: Date
    public var network: String
    /// Sale antes de las 6 de la mañana (lo de streaming): «Desde la madrugada» en vez de la hora.
    public var atDawn: Bool
    public var id: String { "\(series.imdb):\(Int(day.timeIntervalSince1970))" }
    /// Un episodio como lo escribe la TV en español («T2 E5»): lo que se usa si la interfaz no da otro.
    public static let spanishEpisode: @Sendable (Int, Int) -> String = { "T\($0) E\($1)" }
    public var episodeLabel: String { episodeLabel(Self.spanishEpisode) }
    /// «T2 E4–E6» / «S2 E4–E6»: con cómo se escribe un episodio en el idioma de la app (`Services.episodeLabel`).
    public func episodeLabel(_ episode: (Int, Int) -> String) -> String { count > 1 ? "\(episode(season, first))–E\(last)" : episode(season, first) }
}

public struct ForYouList: Sendable, Equatable, Identifiable, Codable {
    public var id: String
    public var title: String           // nombre propio (listas de Trakt, plataformas); vacío = la interfaz lo nombra
    public var group: ForYouGroup
    public var brand: String?          // netflix | disney | hbo
    public var logo: String?
    public var splitsKinds: Bool       // tiene «Series | Películas»
    /// De dónde sale («Trakt», «Complemento», «Netflix», «JustWatch», «Rotten Tomatoes»…) y el dato secundario del estante
    /// («Esta semana en México»). Solo los trae la consola; local, la interfaz los pone según el id.
    public var source = ""
    public var meta = ""
    /// El origen de un catálogo de tus complementos.
    public static let addonSource = "Complemento"

    public init(id: String, title: String, group: ForYouGroup, brand: String? = nil, logo: String? = nil, splitsKinds: Bool, source: String = "", meta: String = "") {
        self.id = id; self.title = title; self.group = group; self.brand = brand; self.logo = logo; self.splitsKinds = splitsKinds
        self.source = source; self.meta = meta
    }
}
