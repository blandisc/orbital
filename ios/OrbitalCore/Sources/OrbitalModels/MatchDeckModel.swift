import Foundation
import OrbitalCore

/// «¿Qué vemos hoy?» · Encuentra tu match perfecto: un mazo de cartas con lo que te propone Para ti, sin lo que ya viste
/// ni lo que descartaste hace poco. Arrastrar a la derecha guarda (con Trakt, en tu lista «Tu match perfecto»; si no, en Mi lista),
/// a la izquierda descarta (no vuelve en un mes); los cuatro ánimos de «¿Qué vemos?» cambian el mazo.
@MainActor
public final class MatchDeckModel: ObservableModel {
    public private(set) var cards: [Suggestion] = [] { didSet { changed() } }
    public private(set) var loaded = false { didSet { changed() } }
    /// Lo que guardaste en esta vuelta (el «Guardaste 3» del final).
    public private(set) var saved: [Suggestion] = [] { didSet { changed() } }
    /// Qué se ve en el mazo: "" es todo, «movie» o «series» (Fernando, 3 nov 2026: filtrar por películas o series).
    public var kind = "" { didSet { if kind != oldValue { rebuild() } } }
    /// Un género del mazo (su nombre en español, el de `Vocabulary`); nil, todos.
    public var genre: String? { didSet { if genre != oldValue { rebuild() } } }
    /// Los géneros que hay en el mazo (del tipo elegido), los que más salen primero.
    public private(set) var genres: [String] = [] { didSet { changed() } }
    /// Un nombre tal cual llegó para cada género (para nombrarlo en inglés).
    private var genreSamples: [String: String] = [:]
    /// Hay algo filtrado: el mazo vacío no es «ya viste todo».
    public var isFiltered: Bool { !kind.isEmpty || genre != nil }

    /// Cuánto tarda en volver algo que descartaste.
    public nonisolated static let discardFor: TimeInterval = 30 * 86400
    static let discardedKey = "match-discarded"
    /// Lo que guardaste desde el mazo (cualquier día): no vuelve a salir (antes solo se recordaba mientras el mazo estaba
    /// abierto y, como el orden es el mismo todo el día, al volver a abrirlo salía arriba la que ya habías guardado).
    static let savedKey = "match-saved"

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
        await fillGenres()
    }

    /// Los géneros que Cinemeta sabe de cada título (las listas de complementos, los Top 10 y la consola no los traen y el
    /// filtro de género no salía; Fernando, 3 nov 2026).
    private var fetchedGenres: [String: [String]] = [:]
    /// Cuántas fichas a la vez y hasta cuántas (las primeras del mazo de hoy).
    nonisolated static let genreConcurrency = 12, genreLookups = 120

    /// Pide los géneros que faltan, con una ventana de pedidos (al terminar uno entra el siguiente), y vuelve a armar el mazo.
    private func fillGenres() async {
        var seen = Set<String>()
        let missing = cards.filter { $0.genres.isEmpty && seen.insert($0.imdb).inserted }.prefix(Self.genreLookups).map { (kind: $0.kind, imdb: $0.imdb) }
        guard !missing.isEmpty else { return }
        let cinemeta = services.cinemeta
        let found = await withTaskGroup(of: (String, [String]).self) { group in
            var next = 0, out: [(String, [String])] = []
            func add() {
                guard next < missing.count, !Task.isCancelled else { return }
                let item = missing[next]
                next += 1
                group.addTask {
                    let meta = try? await cinemeta.meta(kind: item.kind, id: item.imdb)
                    return (item.imdb, (meta?["genres"]?.array ?? meta?["genre"]?.array ?? []).compactMap(\.string))
                }
            }
            for _ in 0..<Self.genreConcurrency { add() }
            for await r in group { out.append(r); add() }
            return out
        }
        for (id, genres) in found where !genres.isEmpty { fetchedGenres[id] = genres }
        guard !Task.isCancelled else { return }
        rebuild()
    }

    private func withGenres(_ s: Suggestion) -> Suggestion {
        guard s.genres.isEmpty, let genres = fetchedGenres[s.imdb] else { return s }
        var x = s
        x.genres = genres
        return x
    }

    /// El mazo de hoy: sin repetir, sin lo visto ni lo descartado, de todo (sin ánimos: Fernando, 1 nov 2026), en un orden
    /// revuelto que cambia cada día.
    public nonisolated static func deck(_ pool: [Suggestion], watched: Set<String>, discarded: Set<String>, day: Int) -> [Suggestion] {
        var seen = Set<String>()
        let fresh = pool.filter { !$0.imdb.isEmpty && !watched.contains($0.imdb) && !discarded.contains($0.imdb) && seen.insert($0.imdb).inserted }
        // Revuelto fijo por día (el mismo orden si vuelves a abrirlo hoy).
        return fresh.sorted { hash("\(day):\($0.imdb)") < hash("\(day):\($1.imdb)") }
    }

    /// El género con el que se compara y se agrupa: su nombre en español («sci-fi» y «science-fiction» son uno).
    public nonisolated static func genreKey(_ genre: String) -> String { Vocabulary.genres([genre], language: "es").first ?? genre }

    /// Solo lo del tipo y el género elegidos ("" es todo; nil, cualquier género).
    public nonisolated static func filter(_ deck: [Suggestion], kind: String, genre: String?) -> [Suggestion] {
        deck.filter { s in
            (kind.isEmpty || (kind == "series") == (s.kind == "series")) && (genre.map { g in s.genres.contains { genreKey($0) == g } } ?? true)
        }
    }

    /// El nombre de un género del mazo en el idioma de la app.
    public func genreName(_ key: String, language: String) -> String {
        language.hasPrefix("es") ? key : Vocabulary.genres([genreSamples[key] ?? key], language: language).first ?? key
    }

    nonisolated static func hash(_ s: String) -> UInt64 {
        var x = s.utf8.reduce(14_695_981_039_346_656_037) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }   // FNV-1a
        x ^= x >> 33; x = x &* 0xff51_afd7_ed55_8ccd; x ^= x >> 33   // mezcla final: un día distinto cambia todo el orden
        return x
    }

    private func rebuild() {
        let day = Int(clock().timeIntervalSince1970 / 86400)
        // Lo que ya guardaste en esta vuelta tampoco vuelve.
        // Tampoco lo que ya está en Mi lista (guardado desde una ficha o desde otro aparato).
        let inList = Set(services.library.all.filter(\.inList).map(\.metaID))
        let deck = Self.deck(pool.map(withGenres), watched: watched, discarded: discarded.union(saved.map(\.imdb)).union(savedEver).union(inList), day: day)
        // Los géneros, de lo que hay del tipo elegido; si el elegido ya no hay, vuelve a todos.
        var counts: [String: Int] = [:], samples: [String: String] = [:]
        for s in Self.filter(deck, kind: kind, genre: nil) {
            for g in Set(s.genres.map(Self.genreKey)) { counts[g, default: 0] += 1 }
            for raw in s.genres { samples[Self.genreKey(raw)] = samples[Self.genreKey(raw)] ?? raw }
        }
        genreSamples = samples
        genres = counts.keys.sorted { counts[$0]! != counts[$1]! ? counts[$0]! > counts[$1]! : $0 < $1 }
        if let g = genre, counts[g] == nil { genre = nil; return }   // el didSet vuelve a armar el mazo
        cards = Self.filter(deck, kind: kind, genre: genre)
    }

    /// Guardar la de arriba (derecha o ＋).
    public func save(_ s: Suggestion) async {
        cards.removeAll { $0.imdb == s.imdb }
        saved.append(s)
        remember(s.imdb, saved: true)
        await keep(s, add: true)
    }

    /// «Para hoy» (deslizar hacia arriba o la ★, como el Súper de Tinder): se guarda como las demás y además entra a Mi lista
    /// con la marca «Para hoy», que en Inicio la pone primero ese día.
    public func saveForTonight(_ s: Suggestion) async {
        cards.removeAll { $0.imdb == s.imdb }
        saved.append(s)
        remember(s.imdb, saved: true)
        ParaHoy.mark(s.imdb, kv: services.kv, now: services.now())
        await keep(s, add: true)
        try? await titles.setSaved(s, in: titles.preferredDestination(for: s), add: true)
    }

    /// «Deshacer» del aviso de guardar: sale de donde se guardó y la carta vuelve arriba del mazo.
    public func undo(_ s: Suggestion) async {
        guard saved.contains(where: { $0.imdb == s.imdb }) else { return }
        remember(s.imdb, saved: false)
        if ParaHoy.ids(kv: services.kv, now: services.now()).contains(s.imdb) {   // era «Para hoy»: también sale de Mi lista
            ParaHoy.unmark(s.imdb, kv: services.kv)
            try? await titles.setSaved(s, in: titles.preferredDestination(for: s), add: false)
        }
        saved.removeAll { $0.imdb == s.imdb }
        cards.removeAll { $0.imdb == s.imdb }
        cards.insert(s, at: 0)
        await keep(s, add: false)
    }

    /// El nombre de la lista de Trakt donde caen las de la derecha (Fernando, 31 oct 2026).
    public static let matchListName = "Tu match perfecto"
    /// Las de la derecha van a «Tu match perfecto» de Trakt (con Trakt conectado); si no, a Mi lista.
    public var savesToTrakt: Bool { services.trakt?.linked ?? false }
    static let matchListKey = "match.trakt-list"

    /// Con Trakt, a tu lista «Tu match perfecto» (se crea la primera vez y se recuerda su id); sin Trakt o si falla, a tu
    /// destino de siempre (Mi lista).
    private func keep(_ s: Suggestion, add: Bool) async {
        if let trakt = services.trakt, trakt.linked, let list = try? await matchList(trakt),
           (try? await trakt.setListItem(listID: list, imdb: s.imdb, series: s.kind == "series", add: add)) != nil {
            await services.forYou.clearCache(["trakt:lists"])
            return
        }
        try? await titles.setSaved(s, in: titles.preferredDestination(for: s), add: add)
    }

    /// El id de «Tu match perfecto»: el recordado si sigue en tus listas, una con ese nombre o una nueva.
    func matchList(_ trakt: Trakt) async throws -> String {
        let remembered = services.kv.data(Self.matchListKey).map { String(decoding: $0, as: UTF8.self) }
        let lists = try await trakt.lists()
        if let remembered, lists.contains(where: { $0.id == remembered }) { return remembered }
        let found = lists.first { $0.name.compare(Self.matchListName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }?.id
        let id: String
        if let found { id = found } else { id = try await trakt.createList(name: Self.matchListName).id }
        services.kv.set(Self.matchListKey, data: Data(id.utf8))
        return id
    }

    /// Descartar la de arriba (izquierda o ✕): no vuelve en un mes.
    public func discard(_ s: Suggestion) {
        cards.removeAll { $0.imdb == s.imdb }
        var all = discardedDates.filter { clock().timeIntervalSince($0.value) < Self.discardFor }
        all[s.imdb] = clock()
        services.kv.set(Self.discardedKey, data: try? JSONEncoder().encode(all))
    }

    /// Lo guardado desde el mazo, para siempre (hasta «Deshacer»).
    private var savedEver: Set<String> { Set(services.kv.data(Self.savedKey).flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []) }
    private func remember(_ imdb: String, saved: Bool) {
        var all = savedEver
        if saved { all.insert(imdb) } else { all.remove(imdb) }
        services.kv.set(Self.savedKey, data: try? JSONEncoder().encode(all.sorted()))
    }

    private var discardedDates: [String: Date] {
        services.kv.data(Self.discardedKey).flatMap { try? JSONDecoder().decode([String: Date].self, from: $0) } ?? [:]
    }
    private var discarded: Set<String> { Set(discardedDates.filter { clock().timeIntervalSince($0.value) < Self.discardFor }.keys) }
}
