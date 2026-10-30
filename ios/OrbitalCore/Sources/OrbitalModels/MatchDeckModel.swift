import Foundation
import OrbitalCore

/// «¿Qué vemos hoy?» · Encuentra tu match perfecto: un mazo de cartas con lo que te propone Para ti, sin lo que ya viste
/// ni lo que descartaste hace poco. Arrastrar a la derecha guarda (en tu destino de siempre: la watchlist de Trakt o Mi lista),
/// a la izquierda descarta (no vuelve en un mes); los cuatro ánimos de «¿Qué vemos?» cambian el mazo.
@MainActor
public final class MatchDeckModel: ObservableModel {
    public private(set) var cards: [Suggestion] = [] { didSet { changed() } }
    public private(set) var loaded = false { didSet { changed() } }
    public var mood: DecideModel.Mood? { didSet { if mood != oldValue { rebuild() } } }
    /// Lo que guardaste en esta vuelta (el «Guardaste 3» del final).
    public private(set) var saved: [Suggestion] = [] { didSet { changed() } }

    /// Cuánto tarda en volver algo que descartaste.
    public nonisolated static let discardFor: TimeInterval = 30 * 86400
    static let discardedKey = "match-discarded"

    private let services: Services
    private let pool: [Suggestion]
    private let watchedSource: @MainActor () async -> Set<String>
    private let clock: @Sendable () -> Date
    private let titles: TitleActions
    private var watched: Set<String> = []

    /// `titles`: el mismo `TitleActions` de toda la app (guardar avisa igual que desde una ficha).
    public init(_ services: Services, pool: [Suggestion], titles: TitleActions? = nil, watched: @escaping @MainActor () async -> Set<String>, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.services = services; self.pool = pool; self.titles = titles ?? TitleActions(services); self.watchedSource = watched; self.clock = clock
        super.init()
    }

    public func load() async {
        watched = await watchedSource()
        rebuild()
        loaded = true
    }

    /// El mazo de hoy: sin repetir, sin lo visto ni lo descartado, del ánimo elegido, en un orden revuelto que cambia cada día.
    public nonisolated static func deck(_ pool: [Suggestion], watched: Set<String>, discarded: Set<String>, mood: DecideModel.Mood?, day: Int) -> [Suggestion] {
        var seen = Set<String>()
        let fresh = pool.filter { !$0.imdb.isEmpty && !watched.contains($0.imdb) && !discarded.contains($0.imdb) && seen.insert($0.imdb).inserted }
        let fit = mood.map { m in fresh.filter { DecideModel.matches($0.genres, m) } } ?? fresh
        // Revuelto fijo por día (el mismo orden si vuelves a abrirlo hoy).
        return fit.sorted { hash("\(day):\($0.imdb)") < hash("\(day):\($1.imdb)") }
    }

    nonisolated static func hash(_ s: String) -> UInt64 {
        var x = s.utf8.reduce(14_695_981_039_346_656_037) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }   // FNV-1a
        x ^= x >> 33; x = x &* 0xff51_afd7_ed55_8ccd; x ^= x >> 33   // mezcla final: un día distinto cambia todo el orden
        return x
    }

    private func rebuild() {
        let day = Int(clock().timeIntervalSince1970 / 86400)
        // Lo que ya guardaste en esta vuelta tampoco vuelve al cambiar de ánimo.
        cards = Self.deck(pool, watched: watched, discarded: discarded.union(saved.map(\.imdb)), mood: mood, day: day)
    }

    /// Guardar la de arriba (derecha o ＋).
    public func save(_ s: Suggestion) async {
        cards.removeAll { $0.imdb == s.imdb }
        saved.append(s)
        try? await titles.setSaved(s, in: titles.preferredDestination(for: s), add: true)
    }

    /// Descartar la de arriba (izquierda o ✕): no vuelve en un mes.
    public func discard(_ s: Suggestion) {
        cards.removeAll { $0.imdb == s.imdb }
        var all = discardedDates.filter { clock().timeIntervalSince($0.value) < Self.discardFor }
        all[s.imdb] = clock()
        services.kv.set(Self.discardedKey, data: try? JSONEncoder().encode(all))
    }

    private var discardedDates: [String: Date] {
        services.kv.data(Self.discardedKey).flatMap { try? JSONDecoder().decode([String: Date].self, from: $0) } ?? [:]
    }
    private var discarded: Set<String> { Set(discardedDates.filter { clock().timeIntervalSince($0.value) < Self.discardFor }.keys) }
}
