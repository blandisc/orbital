import Foundation
import OrbitalCore

/// «¿Qué vemos?» (Para ti › 🎲): tres carteles con su porqué y «Barajar»; debajo, filtros que se aplican al tocarlos (el
/// tiempo, el ánimo, series o películas) y, aparte, «Más filtros» (géneros, época, de qué listas, bien calificada en
/// IMDb, Trakt o TMDB, incluir lo visto). Cuenta cuántas opciones quedan y, si ninguna, qué filtro quitar.
/// Siempre de tus sugerencias (o de las listas que elijas), que no hayas visto ni apartado hoy.
@MainActor
public final class DecideModel: ObservableModel {
    public enum Time: String, CaseIterable, Sendable { case short, hour, long }
    public enum Mood: String, CaseIterable, Sendable { case light, intense, think, together }
    /// De dónde sale la calificación: IMDb (Cinemeta), Trakt y TMDB. Con varias, basta con que una llegue al mínimo.
    public enum RatingSource: String, CaseIterable, Sendable { case imdb, trakt, tmdb }

    /// De dónde puede salir la propuesta: una de tus listas o estantes. `items` lo que ya se tiene; `load`, para las que aún
    /// no se han abierto (tus listas de Trakt): se piden al elegirlas. `origin` agrupa («Trakt», «Orbital», «Sugerencias»).
    public struct Source: Sendable, Identifiable {
        public let id: String, name: String, origin: String, items: [Suggestion]
        public let load: (@Sendable () async -> [Suggestion])?
        public init(id: String, name: String, origin: String = "", items: [Suggestion], load: (@Sendable () async -> [Suggestion])? = nil) {
            self.id = id; self.name = name; self.origin = origin; self.items = items; self.load = load
        }
    }

    /// Lo que eliges, junto (para contar «cuántas quedan» con o sin cada cosa).
    public struct Filters: Equatable, Sendable {
        public var time: Time
        public var mood: Mood?
        public var kind: String?
        public var genres: Set<String>
        public var decades: Set<Int>
        public var minRating: Double
        public var ratingSources: Set<RatingSource>
        public var includeWatched: Bool
    }

    /// Un filtro que se puede quitar (o aflojar) cuando nada cumple, y con cuántas quedarían.
    public enum Relax: Hashable, Sendable { case genre(String), mood, kind, decades, rating, time(Time), lists }

    public internal(set) var pick: Suggestion? { didSet { changed() } }
    /// Las tres que se proponen a la vez (carteles lado a lado); `pick` es la elegida de ellas.
    public internal(set) var picks: [Suggestion] = [] { didSet { changed() } }
    public static let trio = 3
    /// Por qué esta: la duración y lo que coincide («58 min · ligera»).
    public internal(set) var minutes: Int? { didSet { changed() } }
    /// La calificación de IMDb de la propuesta, si se conoce.
    public internal(set) var imdbRating: Double? { didSet { changed() } }
    public internal(set) var isLoading = false { didSet { changed() } }
    public internal(set) var exhausted = false { didSet { changed() } }
    public var time: Time { didSet { changed() } }
    /// Si el tiempo lo elegiste tú (si no, es el de la hora: no cuenta como filtro puesto).
    public var timeChosen = false { didSet { changed() } }
    /// nil: cualquier ánimo (la propuesta rápida no lo pregunta).
    public var mood: Mood? { didSet { changed() } }
    /// Solo series o solo películas (nil: las dos).
    public var kind: String? { didSet { changed() } }
    /// Géneros elegidos (en inglés, en minúsculas); si hay, mandan sobre el ánimo.
    public var genres: Set<String> = [] { didSet { changed() } }
    /// También lo que ya viste.
    public var includeWatched = false { didSet { changed() } }
    /// De qué listas (vacío: de todo lo sugerido).
    public internal(set) var sourceIDs: Set<String> = [] { didSet { changed() } }
    /// Las listas usadas hace poco (las primeras en el selector), guardadas entre aperturas.
    public private(set) var recentSourceIDs: [String] = []
    private var loadedItems: [String: [Suggestion]] = [:]
    static let recentKey = "decide-recent-lists", recentLimit = 5
    /// Nivel 3: épocas (el año en que empieza cada década: 2020, 2010…; 1980 cuenta todo lo anterior a 1990).
    public var decades: Set<Int> = [] { didSet { changed() } }
    /// Calificación mínima (0: sin mínimo) y según qué servicios (basta uno).
    public var minRating: Double = 0 { didSet { changed() } }
    public var ratingSources: Set<RatingSource> = [.imdb, .trakt] { didSet { changed() } }
    public static let ratingSteps: [Double] = [0, 6, 7, 8]

    public var filters: Filters {
        Filters(time: time, mood: mood, kind: kind, genres: genres, decades: decades, minRating: minRating, ratingSources: ratingSources, includeWatched: includeWatched)
    }

    /// Cuántos filtros hay puestos (el tiempo solo si lo elegiste; las listas cuentan como uno).
    public var activeFilters: Int {
        (timeChosen ? 1 : 0) + (mood == nil ? 0 : 1) + (kind == nil ? 0 : 1) + genres.count + (decades.isEmpty ? 0 : 1)
            + (minRating > 0 ? 1 : 0) + (sourceIDs.isEmpty ? 0 : 1) + (includeWatched ? 1 : 0)
    }
    /// Los de «Más filtros» (para «Más filtros · 2»); la calificación tiene su propia cápsula.
    public var moreFilters: Int {
        genres.count + (decades.isEmpty ? 0 : 1) + (sourceIDs.isEmpty ? 0 : 1) + (includeWatched ? 1 : 0)
    }

    /// Los géneros que se ofrecen (su nombre en inglés, como los dan Trakt y Cinemeta).
    public static let genreChoices = ["comedy", "drama", "action", "thriller", "horror", "sci-fi", "animation", "romance", "documentary", "crime", "fantasy", "mystery"]
    public static let decadeChoices = [2020, 2010, 2000, 1990, 1980]

    public let sources: [Source]
    let services: Services
    private let pool: [Suggestion]
    /// Lo que Cinemeta dice de cada candidata (género, duración, calificación, año). Se guarda entre aperturas: con eso los
    /// filtros se resuelven sin red y «Barajar» no espera.
    struct Detail: Codable, Equatable {
        var genres: [String]; var minutes: Int?; var rating: Double?; var year: Int?
        /// La de TMDB (se pide solo si la eliges); `tmdbChecked`: ya se preguntó (aunque TMDB no la tenga).
        var tmdbRating: Double?; var tmdbChecked: Bool?
    }
    var details: [String: Detail] = [:]
    static let detailsKey = "decide-details", detailsLimit = 1500
    var shown = Set<String>()
    /// Las candidatas en el orden de esta vuelta.
    var order: [Suggestion] = []
    /// Lo que tu historial de Trakt dice que ya viste (se pide una vez por hoja).
    var watched: Set<String>?
    static let skipKey = "decide-not-today"

    public init(_ services: Services, pool: [Suggestion], sources: [Source] = []) {
        self.services = services
        var seen = Set<String>()
        self.pool = (pool + sources.flatMap(\.items)).filter { seen.insert($0.imdb).inserted }
        self.sources = sources.filter { !$0.items.isEmpty || $0.load != nil }
        self.time = Self.contextTime(services.now())
        super.init()
        // Lo que ya viste: el de la última vez (guardado) sirve desde ya; el de hoy se pide aparte y se guarda para la próxima.
        // Antes se esperaba a Trakt (hasta 4 s) antes de enseñar nada.
        watched = services.kv.data(Self.watchedKey).flatMap { try? JSONDecoder().decode([String].self, from: $0) }.map(Set.init)
        details = services.kv.data(Self.detailsKey).flatMap { try? JSONDecoder().decode([String: Detail].self, from: $0) } ?? [:]
        recentSourceIDs = services.kv.data(Self.recentKey).flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
        if let trakt = services.trakt, trakt.linked {
            let kv = services.kv
            watchedTask = Task { [weak self] in
                let fresh = try? await trakt.watchedIDs()
                if let fresh { kv.set(Self.watchedKey, data: try? JSONEncoder().encode(Array(fresh))); self?.watched = fresh }
                return fresh
            }
        }
    }

    static let watchedKey = "decide-watched"

    var watchedTask: Task<Set<String>?, Never>?

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

    /// Baja los carteles antes de enseñarlos (la app lo pone): los tres aparecen juntos, ya con imagen, en vez de uno y
    /// luego los otros.
    public var warmPosters: (@MainActor ([String]) async -> Void)?
    /// Los siguientes tríos, ya buscados y con sus carteles bajados mientras ves estos (dos por delante): «Barajar» los
    /// cambia al instante. Cada uno espera al anterior (no buscan dos a la vez).
    var upcoming: [(key: String, task: Task<[Suggestion], Never>)] = []
    static let ahead = 2
    /// Los datos de toda la lista se piden una vez, en segundo plano, al abrir.
    var describingAll: Task<Void, Never>?
    var enriching: Task<Void, Never>?

    /// Lo que se está preparando ya no sirve (cambiaron los filtros o se cerró): se cancela, no se espera.
    func dropUpcoming() {
        for item in upcoming { item.task.cancel() }
        upcoming = []
    }

    /// Prepara tríos hasta tener `ahead` listos (o en camino) para los filtros de ahora.
    func fillUpcoming() {
        let key = filtersKey
        if upcoming.contains(where: { $0.key != key }) { dropUpcoming() }
        while upcoming.count < Self.ahead {
            let previous = upcoming.last?.task
            let task = Task { [weak self] () -> [Suggestion] in
                _ = await previous?.value
                guard !Task.isCancelled, let self else { return [] }
                return await self.trio(waitForPosters: false)
            }
            upcoming.append((key, task))
        }
    }

    /// Lo que eligiste, en una cadena: los siguientes ya buscados solo sirven si no cambió.
    var filtersKey: String {
        [time.rawValue, mood?.rawValue ?? "", kind ?? "", genres.sorted().joined(separator: ","), "\(includeWatched)", sourceIDs.sorted().joined(separator: ","),
         decades.sorted().map(String.init).joined(separator: ","), "\(minRating)", ratingSources.map(\.rawValue).sorted().joined(separator: ",")].joined(separator: "|")
    }

    /// Nivel 1: la propuesta rápida (lo que sigues primero si cabe; si no, al azar entre lo tuyo).
    public func quick() async {
        let following = pool.filter { $0.reason == .watching }.shuffled()
        order = following + pool.filter { $0.reason != .watching }.shuffled()
        // Los carteles de las primeras candidatas empiezan a bajar ya (mientras se decide).
        if let warm = warmPosters { let first = order.prefix(Self.trio * 3).map(\.poster); Task { await warm(first) } }
        await prepare()
        await next()
        describeAllInBackground()
    }

    /// Duración, género, año y calificación de todo lo sugerido, de a poco y sin estorbar: así los filtros (niveles 2 y 3)
    /// ya no tienen que preguntar a Cinemeta mientras esperas.
    private func describeAllInBackground() {
        guard describingAll == nil else { return }
        describingAll = describeInBackground(pool)
    }

    @discardableResult
    private func describeInBackground(_ items: [Suggestion]) -> Task<Void, Never>? {
        let missing = items.filter { details[$0.imdb] == nil }
        guard !missing.isEmpty else { return nil }
        return Task(priority: .utility) { [weak self] in
            for start in stride(from: 0, to: missing.count, by: Self.chunk) {
                guard !Task.isCancelled, let self else { return }
                await self.describe(Array(missing[start..<min(start + Self.chunk, missing.count)]))
            }
        }
    }

    /// La calificación de TMDB (una consulta por título, con su id de IMDb), solo si la elegiste y hay clave.
    var ratingTMDB: Task<Void, Never>?
    private func rateWithTMDBInBackground(_ items: [Suggestion]) {
        let tmdb = services.tmdb
        guard tmdb.configured, ratingTMDB == nil else { return }
        let missing = items.filter { details[$0.imdb]?.tmdbChecked != true }
        guard !missing.isEmpty else { return }
        ratingTMDB = Task(priority: .utility) { [weak self] in
            for start in stride(from: 0, to: missing.count, by: Self.chunk) {
                guard !Task.isCancelled else { break }
                let chunk = Array(missing[start..<min(start + Self.chunk, missing.count)])
                let found = await withTaskGroup(of: (String, Double?).self) { group in
                    for s in chunk { group.addTask { (s.imdb, try? await tmdb.rating(imdb: s.imdb, kind: s.kind)) } }
                    var out: [(String, Double?)] = []
                    for await r in group { out.append(r) }
                    return out
                }
                guard let self else { return }
                for (id, rating) in found {
                    var d = self.details[id] ?? Detail(genres: [], minutes: nil, rating: nil, year: nil)
                    d.tmdbRating = rating; d.tmdbChecked = true
                    self.details[id] = d
                }
                self.saveDetails(); self.changed()
            }
            self?.ratingTMDB = nil
        }
    }

    /// Niveles 2 y 3: con lo que elegiste.
    public func decide() async { await apply() }

    var candidatesPool: [Suggestion] {
        guard !sourceIDs.isEmpty else { return pool }
        var seen = Set<String>()
        return sources.filter { sourceIDs.contains($0.id) }.flatMap { items(of: $0) }.filter { seen.insert($0.imdb).inserted }
    }

    /// Lo que tiene una lista: lo que ya traía o lo que se pidió al elegirla.
    public func items(of source: Source) -> [Suggestion] { source.items.isEmpty ? (loadedItems[source.id] ?? []) : source.items }
    /// Cuántos títulos tiene (nil: aún no se sabe, no se ha abierto).
    public func itemCount(_ source: Source) -> Int? {
        if !source.items.isEmpty { return source.items.count }
        return loadedItems[source.id]?.count
    }

    /// Elegir de qué listas: las que no se han abierto se piden (a la vez), se recuerdan como usadas y se aplica.
    public func setSources(_ ids: Set<String>) async {
        sourceIDs = ids
        let missing = sources.filter { ids.contains($0.id) && $0.items.isEmpty && loadedItems[$0.id] == nil && $0.load != nil }
        if !missing.isEmpty {
            isLoading = true
            let found = await withTaskGroup(of: (String, [Suggestion]).self) { group in
                for source in missing { if let load = source.load { group.addTask { (source.id, await load()) } } }
                var out: [(String, [Suggestion])] = []
                for await r in group { out.append(r) }
                return out
            }
            for (id, items) in found { loadedItems[id] = items }
            describeInBackground(found.flatMap(\.1))
        }
        var recent = recentSourceIDs.filter { !ids.contains($0) }
        recent.insert(contentsOf: ids.sorted(), at: 0)
        recentSourceIDs = Array(recent.prefix(Self.recentLimit))
        services.kv.set(Self.recentKey, data: try? JSONEncoder().encode(recentSourceIDs))
        await apply()
    }

    /// Aplicar lo elegido al momento (los filtros ya no esperan un botón): otros tres que cumplan.
    public func apply() async {
        dropUpcoming()
        shown = []
        exhausted = false
        order = candidatesPool.shuffled()
        if filters.minRating > 0, filters.ratingSources.contains(.tmdb) { rateWithTMDBInBackground(order) }
        await next()
    }

    // MARK: cuántas quedan

    /// Pide ya a Cinemeta lo que falta para decidir con lo elegido (en «Más filtros», al tocar un género o una época): el
    /// conteo llega solo, en vez de decir «sin opciones» mientras no se sabe.
    var resolving: Task<Void, Never>?

}
