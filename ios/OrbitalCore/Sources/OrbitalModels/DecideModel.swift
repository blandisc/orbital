import Foundation
import OrbitalCore

/// «Decide por mí» (Para ti › 🎲): cuánto tiempo tienes y qué quieres, y una sola propuesta (de tus sugerencias, que no
/// hayas descartado hoy) con su porqué. «Otra» propone la siguiente; «Hoy no» la aparta 24 horas.
@MainActor
public final class DecideModel: ObservableModel {
    public enum Time: String, CaseIterable, Sendable { case short, hour, long }
    public enum Mood: String, CaseIterable, Sendable { case light, intense, think, together }

    public private(set) var pick: Suggestion? { didSet { changed() } }
    /// Por qué esta: la duración y el ánimo que coinciden («58 min · ligera»).
    public private(set) var minutes: Int? { didSet { changed() } }
    public private(set) var isLoading = false { didSet { changed() } }
    public private(set) var exhausted = false { didSet { changed() } }
    public var time: Time = .hour { didSet { changed() } }
    public var mood: Mood = .light { didSet { changed() } }

    private let services: Services
    private let pool: [Suggestion]
    private var details: [String: (genres: [String], minutes: Int?)] = [:]
    private var shown = Set<String>()
    /// Las candidatas en el orden de esta vuelta (se barajan en cada «Decide por mí»: no sale siempre la misma).
    private var order: [Suggestion] = []
    /// Lo que tu historial de Trakt dice que ya viste (se pide una vez por hoja).
    private var watched: Set<String>?
    static let skipKey = "decide-not-today"

    public init(_ services: Services, pool: [Suggestion]) {
        self.services = services
        var seen = Set<String>()
        self.pool = pool.filter { seen.insert($0.imdb).inserted }
        super.init()
        // Lo que ya viste se pide desde que se abre la hoja: al tocar «Decide por mí» ya está (o casi).
        if let trakt = services.trakt, trakt.linked { watchedTask = Task { try? await trakt.watchedIDs() } }
    }

    private var watchedTask: Task<Set<String>?, Never>?

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

    /// ¿Cabe en el tiempo que tienes? (una serie cuenta por episodio).
    nonisolated static func fits(_ minutes: Int?, _ time: Time) -> Bool {
        guard let minutes, minutes > 0 else { return time != .short }   // sin dato: no para «30 min»
        switch time { case .short: return minutes <= 35; case .hour: return minutes <= 75; case .long: return true }
    }

    public func decide() async {
        shown = []
        exhausted = false
        order = pool.shuffled()
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
        await next()
    }

    /// La siguiente que cabe. Lo que ya trae su género y su duración (lo de Trakt) se decide al momento; lo demás se le
    /// pregunta a Cinemeta, unas cuantas a la vez, con un tiempo máximo: si se acaba, la más cercana del ánimo.
    public func next() async {
        isLoading = true
        defer { isLoading = false }
        let started = services.now()
        let skipped = notToday()
        let seen = watched ?? []
        let candidates = (order.isEmpty ? pool : order).filter { !shown.contains($0.imdb) && !skipped.contains($0.imdb) && !seen.contains($0.imdb) }
        var closest: Suggestion?   // del ánimo, aunque dure más: mejor eso que nada
        func verdict(_ s: Suggestion) -> (mood: Bool, fits: Bool)? {
            let d = details[s.imdb]
            let genres = s.genres.isEmpty ? d?.genres : s.genres
            guard let genres else { return nil }   // falta preguntar
            return (Self.matches(genres, mood), Self.fits(s.runtime ?? d?.minutes, time))
        }
        func take(_ s: Suggestion) {
            shown.insert(s.imdb)
            pick = s
            minutes = s.runtime ?? details[s.imdb]?.minutes
        }
        // 1) Lo que ya se sabe, sin red.
        for s in candidates {
            guard let v = verdict(s) else { continue }
            if v.mood && v.fits { return take(s) }
            if v.mood, closest == nil { closest = s }
        }
        // 2) Lo demás, de 12 en 12, mientras haya tiempo.
        let unknown = candidates.filter { verdict($0) == nil }
        for chunk in stride(from: 0, to: unknown.count, by: Self.chunk).map({ Array(unknown[$0..<min($0 + Self.chunk, unknown.count)]) }) {
            if services.now().timeIntervalSince(started) > Self.budget { break }
            await describe(chunk)
            for s in chunk {
                guard let v = verdict(s) else { continue }
                if v.mood && v.fits { return take(s) }
                if v.mood, closest == nil { closest = s }
            }
        }
        for s in candidates where verdict(s) != nil { shown.insert(s.imdb) }
        if let closest { return take(closest) }
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
        let found = await withTaskGroup(of: (String, [String], Int?).self) { group in
            for s in missing {
                group.addTask {
                    guard let meta = try? await cinemeta.meta(kind: s.kind, id: s.imdb) else { return (s.imdb, [], nil) }
                    let info = CinemetaParsing.describe(meta)
                    let seconds = CinemetaParsing.runtimeSeconds(info.runtime); let minutes = seconds > 0 ? Int(seconds / 60) : nil
                    return (s.imdb, (meta["genres"]?.array ?? meta["genre"]?.array ?? []).compactMap(\.string), minutes)
                }
            }
            var out: [(String, [String], Int?)] = []
            for await r in group { out.append(r) }
            return out
        }
        for (id, genres, minutes) in found { details[id] = (genres, minutes) }
    }
}
