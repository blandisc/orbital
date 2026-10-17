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
    static let skipKey = "decide-not-today"

    public init(_ services: Services, pool: [Suggestion]) {
        self.services = services
        var seen = Set<String>()
        self.pool = pool.filter { seen.insert($0.imdb).inserted }
        super.init()
    }

    /// Qué géneros (los de Cinemeta, en inglés) cuentan para cada ánimo.
    nonisolated static func genres(for mood: Mood) -> Set<String> {
        switch mood {
        case .light: ["Comedy", "Animation", "Family", "Adventure", "Musical"]
        case .intense: ["Thriller", "Action", "Horror", "Crime", "War"]
        case .think: ["Drama", "Documentary", "Sci-Fi", "Mystery", "History", "Biography"]
        case .together: ["Romance", "Comedy", "Fantasy", "Music"]
        }
    }

    /// ¿Cabe en el tiempo que tienes? (una serie cuenta por episodio).
    nonisolated static func fits(_ minutes: Int?, _ time: Time) -> Bool {
        guard let minutes, minutes > 0 else { return time != .short }   // sin dato: no para «30 min»
        switch time { case .short: return minutes <= 35; case .hour: return minutes <= 75; case .long: return true }
    }

    public func decide() async {
        shown = []
        exhausted = false
        await next()
    }

    /// La siguiente que cabe (pide géneros y duración a Cinemeta solo de las que hacen falta, unas cuantas a la vez).
    public func next() async {
        isLoading = true
        defer { isLoading = false }
        let skipped = notToday()
        let wanted = Self.genres(for: mood)
        let candidates = pool.filter { !shown.contains($0.imdb) && !skipped.contains($0.imdb) }
        var closest: Suggestion?   // del ánimo, aunque dure más: mejor eso que nada
        for chunk in stride(from: 0, to: candidates.count, by: 8).map({ Array(candidates[$0..<min($0 + 8, candidates.count)]) }) {
            await describe(chunk)
            if let hit = chunk.first(where: { s in
                let d = details[s.imdb]
                return Self.fits(d?.minutes ?? s.runtime, time) && !wanted.isDisjoint(with: d?.genres ?? [])
            }) {
                shown.insert(hit.imdb)
                pick = hit
                minutes = details[hit.imdb]?.minutes ?? hit.runtime
                return
            }
            if closest == nil { closest = chunk.first { !wanted.isDisjoint(with: details[$0.imdb]?.genres ?? []) } }
            for s in chunk { shown.insert(s.imdb) }
        }
        if let closest {
            pick = closest
            minutes = details[closest.imdb]?.minutes ?? closest.runtime
            return
        }
        pick = nil
        exhausted = true
    }

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
