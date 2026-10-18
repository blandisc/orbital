import Foundation
import OrbitalCore

/// «¿Qué vemos?» (Para ti › 🎲), en tres niveles de la misma hoja:
/// 1. Al abrir, una propuesta rápida con el contexto (la hora, lo que sigues), que se baraja.
/// 2. Estirada: cuánto tiempo, qué ánimo, series o películas, géneros.
/// 3. Hasta arriba: de qué lista, época y calificación mínima en un servicio.
/// Siempre una sola propuesta (de tus sugerencias, que no hayas visto ni apartado hoy) con su porqué.
@MainActor
public final class DecideModel: ObservableModel {
    public enum Time: String, CaseIterable, Sendable { case short, hour, long }
    public enum Mood: String, CaseIterable, Sendable { case light, intense, think, together }
    public enum RatingService: String, CaseIterable, Sendable { case imdb, trakt }

    /// De dónde puede salir la propuesta (nivel 3): una de tus listas o estantes, con lo que tiene.
    public struct Source: Sendable, Identifiable {
        public let id: String, name: String, items: [Suggestion]
        public init(id: String, name: String, items: [Suggestion]) { self.id = id; self.name = name; self.items = items }
    }

    public private(set) var pick: Suggestion? { didSet { changed() } }
    /// Las tres que se proponen a la vez (carteles lado a lado); `pick` es la elegida de ellas.
    public private(set) var picks: [Suggestion] = [] { didSet { changed() } }
    public static let trio = 3
    /// Por qué esta: la duración y lo que coincide («58 min · ligera»).
    public private(set) var minutes: Int? { didSet { changed() } }
    /// La calificación de IMDb de la propuesta, si se conoce.
    public private(set) var imdbRating: Double? { didSet { changed() } }
    public private(set) var isLoading = false { didSet { changed() } }
    public private(set) var exhausted = false { didSet { changed() } }
    public var time: Time { didSet { changed() } }
    /// nil: cualquier ánimo (la propuesta rápida no lo pregunta).
    public var mood: Mood? { didSet { changed() } }
    /// Solo series o solo películas (nil: las dos).
    public var kind: String? { didSet { changed() } }
    /// Géneros elegidos (en inglés, en minúsculas); si hay, mandan sobre el ánimo.
    public var genres: Set<String> = [] { didSet { changed() } }
    /// También lo que ya viste.
    public var includeWatched = false { didSet { changed() } }
    /// Nivel 3: de qué lista (nil: de todo lo sugerido).
    public var sourceID: String? { didSet { changed() } }
    /// Nivel 3: épocas (el año en que empieza cada década: 2020, 2010…; 1980 cuenta todo lo anterior a 1990).
    public var decades: Set<Int> = [] { didSet { changed() } }
    /// Nivel 3: calificación mínima (0: sin mínimo) y en qué servicio.
    public var minRating: Double = 0 { didSet { changed() } }
    public var ratingService: RatingService = .imdb { didSet { changed() } }

    /// Los géneros que se ofrecen (su nombre en inglés, como los dan Trakt y Cinemeta).
    public static let genreChoices = ["comedy", "drama", "action", "thriller", "horror", "sci-fi", "animation", "romance", "documentary", "crime", "fantasy", "mystery"]
    public static let decadeChoices = [2020, 2010, 2000, 1990, 1980]

    public let sources: [Source]
    private let services: Services
    private let pool: [Suggestion]
    private var details: [String: (genres: [String], minutes: Int?, rating: Double?, year: Int?)] = [:]
    private var shown = Set<String>()
    /// Las candidatas en el orden de esta vuelta.
    private var order: [Suggestion] = []
    /// Lo que tu historial de Trakt dice que ya viste (se pide una vez por hoja).
    private var watched: Set<String>?
    static let skipKey = "decide-not-today"

    public init(_ services: Services, pool: [Suggestion], sources: [Source] = []) {
        self.services = services
        var seen = Set<String>()
        self.pool = (pool + sources.flatMap(\.items)).filter { seen.insert($0.imdb).inserted }
        self.sources = sources.filter { !$0.items.isEmpty }
        self.time = Self.contextTime(services.now())
        super.init()
        // Lo que ya viste se pide desde que se abre la hoja: al decidir ya está (o casi).
        if let trakt = services.trakt, trakt.linked { watchedTask = Task { try? await trakt.watchedIDs() } }
    }

    private var watchedTask: Task<Set<String>?, Never>?

    /// El tiempo según la hora: muy noche, poco; viernes en la noche y el fin de semana, dos horas o más; lo demás, una.
    nonisolated static func contextTime(_ now: Date, calendar: Calendar = .current) -> Time {
        let hour = calendar.component(.hour, from: now), weekday = calendar.component(.weekday, from: now)   // 1 domingo … 7 sábado
        if hour >= 23 || hour < 5 { return .short }
        if weekday == 1 || weekday == 7 || (weekday == 6 && hour >= 18) { return .long }
        return .hour
    }

    /// Qué géneros cuentan para cada ánimo (en minúsculas: sirven los de Cinemeta, «Sci-Fi», y los de Trakt, «science-fiction»).
    nonisolated static func genres(for mood: Mood) -> Set<String> {
        switch mood {
        case .light: ["comedy", "animation", "family", "adventure", "musical"]
        case .intense: ["thriller", "action", "horror", "crime", "war"]
        case .think: ["drama", "documentary", "sci-fi", "science-fiction", "science fiction", "mystery", "history", "biography"]
        case .together: ["romance", "comedy", "fantasy", "music"]
        }
    }

    /// ¿Alguno de estos géneros es del ánimo?
    nonisolated static func matches(_ list: [String], _ mood: Mood) -> Bool {
        !genres(for: mood).isDisjoint(with: list.map { $0.lowercased() })
    }

    /// ¿Alguno de estos géneros es de los elegidos? («Science Fiction», «science-fiction» y «Sci-Fi» son el mismo.)
    nonisolated static func matches(_ list: [String], picked: Set<String>) -> Bool {
        !picked.isDisjoint(with: list.map(normalized))
    }

    nonisolated static func normalized(_ genre: String) -> String {
        let g = genre.lowercased()
        return ["science-fiction", "science fiction"].contains(g) ? "sci-fi" : g
    }

    /// ¿Cabe en el tiempo que tienes? (una serie cuenta por episodio).
    nonisolated static func fits(_ minutes: Int?, _ time: Time) -> Bool {
        guard let minutes, minutes > 0 else { return time != .short }   // sin dato: no para «30 min»
        switch time { case .short: return minutes <= 35; case .hour: return minutes <= 75; case .long: return true }
    }

    /// ¿Es de alguna de estas épocas? (1980 cuenta todo lo anterior a 1990.)
    nonisolated static func inDecades(_ year: Int, _ decades: Set<Int>) -> Bool {
        decades.contains { d in d == 1980 ? year < 1990 : (d...(d + 9)).contains(year) }
    }

    /// Nivel 1: la propuesta rápida (lo que sigues primero si cabe; si no, al azar entre lo tuyo).
    public func quick() async {
        await prepare()
        let following = pool.filter { $0.reason == .watching }.shuffled()
        order = following + pool.filter { $0.reason != .watching }.shuffled()
        await next()
    }

    /// La duración y la calificación de la propuesta, si no se sabían (sin filtros no se le preguntaron a Cinemeta): el
    /// porqué siempre lleva datos que se pueden comprobar.
    private func enrichPick() async {
        guard let s = pick, details[s.imdb] == nil else { return }
        await describe([s])
        guard pick?.imdb == s.imdb else { return }
        minutes = s.runtime ?? details[s.imdb]?.minutes
        imdbRating = details[s.imdb]?.rating
    }

    /// Niveles 2 y 3: con lo que elegiste.
    public func decide() async {
        await prepare()
        order = candidatesPool.shuffled()
        await next()
    }

    private var candidatesPool: [Suggestion] {
        if let sourceID, let source = sources.first(where: { $0.id == sourceID }) { return source.items }
        return pool
    }

    private func prepare() async {
        shown = []
        exhausted = false
        if watched == nil, let trakt = services.trakt, trakt.linked {
            isLoading = true
            // Lo que ya viste, con tiempo máximo: si Trakt tarda, se decide sin eso (y se pide otra vez la próxima).
            let pending = watchedTask ?? Task { try? await trakt.watchedIDs() }
            let found = await withTaskGroup(of: Set<String>?.self) { group -> Set<String>? in
                group.addTask { await pending.value }
                group.addTask { try? await Task.sleep(nanoseconds: UInt64(Self.watchedWait * 1_000_000_000)); return nil }
                let first = await group.next() ?? nil
                group.cancelAll()
                return first
            }
            watched = found
        }
    }

    /// La siguiente que cabe. Lo que ya trae su género, duración, año y calificación se decide al momento; lo demás se le
    /// pregunta a Cinemeta, unas cuantas a la vez, con un tiempo máximo: si se acaba, la más cercana.
    public func next() async {
        var found: [Suggestion] = []
        for _ in 0..<Self.trio {
            await search()
            guard let p = pick, !found.contains(where: { $0.imdb == p.imdb }) else { break }
            found.append(p)
        }
        // Las tres con sus datos (duración, calificación), de una vez; la primera queda elegida.
        await describe(found)
        picks = found
        if let first = found.first { select(first) } else { pick = nil }
    }

    /// Tocar uno de los tres carteles: esa es la propuesta.
    public func select(_ s: Suggestion) {
        pick = s
        minutes = s.runtime ?? details[s.imdb]?.minutes
        imdbRating = details[s.imdb]?.rating
    }

    private func search(retried: Bool = false) async {
        isLoading = true
        defer { isLoading = false }
        let started = services.now()
        let skipped = notToday()
        let seen = includeWatched ? [] : (watched ?? [])
        func available() -> [Suggestion] {
            (order.isEmpty ? candidatesPool : order).filter {
                !shown.contains($0.imdb) && !skipped.contains($0.imdb) && !seen.contains($0.imdb) && (kind == nil || $0.kind == kind)
            }
        }
        var candidates = available()
        // Ya se enseñó todo lo que cabe: se da otra vuelta (antes se quedaba en «No encontré» sin botones).
        if candidates.isEmpty, !shown.isEmpty { shown = []; candidates = available() }
        var closest: Suggestion?   // de lo que pediste, aunque dure más: mejor eso que nada
        func verdict(_ s: Suggestion) -> (matches: Bool, fits: Bool)? {
            let d = details[s.imdb]
            let genreList = s.genres.isEmpty ? d?.genres : s.genres
            if (!genres.isEmpty || mood != nil) && genreList == nil { return nil }   // falta preguntar
            let year = s.year ?? d?.year
            if !decades.isEmpty && year == nil && d == nil { return nil }
            if minRating > 0 && ratingService == .imdb && d == nil { return nil }
            let rating: Double? = ratingService == .trakt ? s.traktRating : d?.rating
            var ok = true
            if !genres.isEmpty { ok = Self.matches(genreList ?? [], picked: genres) }
            else if let mood { ok = Self.matches(genreList ?? [], mood) }
            if ok, !decades.isEmpty { ok = year.map { Self.inDecades($0, decades) } ?? false }
            if ok, minRating > 0 { ok = (rating ?? 0) >= minRating }
            return (ok, Self.fits(s.runtime ?? d?.minutes, time))
        }
        func take(_ s: Suggestion) {
            shown.insert(s.imdb)
            pick = s
            minutes = s.runtime ?? details[s.imdb]?.minutes
            imdbRating = details[s.imdb]?.rating
        }
        // 1) Lo que ya se sabe, sin red.
        for s in candidates {
            guard let v = verdict(s) else { continue }
            if v.matches && v.fits { return take(s) }
            if v.matches, closest == nil { closest = s }
        }
        // 2) Lo demás, de 12 en 12, mientras haya tiempo.
        let unknown = candidates.filter { verdict($0) == nil }
        for chunk in stride(from: 0, to: unknown.count, by: Self.chunk).map({ Array(unknown[$0..<min($0 + Self.chunk, unknown.count)]) }) {
            if services.now().timeIntervalSince(started) > Self.budget { break }
            await describe(chunk)
            for s in chunk {
                guard let v = verdict(s) else { continue }
                if v.matches && v.fits { return take(s) }
                if v.matches, closest == nil { closest = s }
            }
        }
        // La más cercana (aunque dure más de lo que tienes); solo esa cuenta como enseñada, no todas las revisadas.
        if let closest { return take(closest) }
        // Con un filtro, las que cumplen ya salieron todas: otra vuelta desde el principio (una vez), no «No encontré».
        if !retried, !shown.isEmpty { shown = []; isLoading = false; return await search(retried: true) }
        pick = nil
        exhausted = true
    }

    static let chunk = 12
    static let watchedWait: Double = 4
    /// Lo más que se busca antes de proponer la más cercana (segundos).
    static let budget: TimeInterval = 6

    /// Volver a las preguntas.
    public func reset() async { pick = nil; exhausted = false }

    /// «Hoy no»: no vuelve a salir en 24 horas; y otra.
    public func skipToday() async {
        if let pick {
            var skipped = notTodayRaw()
            skipped[pick.imdb] = services.now().timeIntervalSince1970
            services.kv.set(Self.skipKey, data: try? JSONEncoder().encode(skipped))
            // Solo esa se cambia por otra; las otras dos se quedan.
            let current = pick.imdb
            let others = picks.filter { $0.imdb != current }
            await search()
            if let fresh = self.pick, !others.contains(where: { $0.imdb == fresh.imdb }) {
                await describe([fresh])
                picks = picks.map { $0.imdb == current ? fresh : $0 }
                select(fresh)
            } else {
                picks = others
                if let first = others.first { select(first) }
            }
            return
        }
        await next()
    }

    private func notTodayRaw() -> [String: Double] {
        services.kv.data(Self.skipKey).flatMap { try? JSONDecoder().decode([String: Double].self, from: $0) } ?? [:]
    }

    private func notToday() -> Set<String> {
        let now = services.now().timeIntervalSince1970
        return Set(notTodayRaw().filter { now - $0.value < 24 * 3600 }.keys)
    }

    private func describe(_ items: [Suggestion]) async {
        let cinemeta = services.cinemeta
        let missing = items.filter { details[$0.imdb] == nil }
        let found = await withTaskGroup(of: (String, [String], Int?, Double?, Int?).self) { group in
            for s in missing {
                group.addTask {
                    guard let meta = try? await cinemeta.meta(kind: s.kind, id: s.imdb) else { return (s.imdb, [], nil, nil, nil) }
                    let info = CinemetaParsing.describe(meta)
                    let seconds = CinemetaParsing.runtimeSeconds(info.runtime); let minutes = seconds > 0 ? Int(seconds / 60) : nil
                    let rating = (meta["imdbRating"]?.string).flatMap(Double.init) ?? meta["imdbRating"]?.doubleValue
                    let year = (meta["year"]?.string).flatMap { Int($0.prefix(4)) } ?? meta["year"]?.intValue
                    return (s.imdb, (meta["genres"]?.array ?? meta["genre"]?.array ?? []).compactMap(\.string), minutes, rating, year)
                }
            }
            var out: [(String, [String], Int?, Double?, Int?)] = []
            for await r in group { out.append(r) }
            return out
        }
        for (id, genres, minutes, rating, year) in found { details[id] = (genres, minutes, rating, year) }
    }
}
