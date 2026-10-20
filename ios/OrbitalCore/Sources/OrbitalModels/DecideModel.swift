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
    public private(set) var sourceIDs: Set<String> = [] { didSet { changed() } }
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
    private let services: Services
    private let pool: [Suggestion]
    /// Lo que Cinemeta dice de cada candidata (género, duración, calificación, año). Se guarda entre aperturas: con eso los
    /// filtros se resuelven sin red y «Barajar» no espera.
    struct Detail: Codable, Equatable {
        var genres: [String]; var minutes: Int?; var rating: Double?; var year: Int?
        /// La de TMDB (se pide solo si la eliges); `tmdbChecked`: ya se preguntó (aunque TMDB no la tenga).
        var tmdbRating: Double?; var tmdbChecked: Bool?
    }
    private var details: [String: Detail] = [:]
    static let detailsKey = "decide-details", detailsLimit = 1500
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

    /// Baja los carteles antes de enseñarlos (la app lo pone): los tres aparecen juntos, ya con imagen, en vez de uno y
    /// luego los otros.
    public var warmPosters: (@MainActor ([String]) async -> Void)?
    /// Los siguientes tríos, ya buscados y con sus carteles bajados mientras ves estos (dos por delante): «Barajar» los
    /// cambia al instante. Cada uno espera al anterior (no buscan dos a la vez).
    private var upcoming: [(key: String, task: Task<[Suggestion], Never>)] = []
    static let ahead = 2
    /// Los datos de toda la lista se piden una vez, en segundo plano, al abrir.
    private var describingAll: Task<Void, Never>?
    private var enriching: Task<Void, Never>?

    /// Lo que se está preparando ya no sirve (cambiaron los filtros o se cerró): se cancela, no se espera.
    private func dropUpcoming() {
        for item in upcoming { item.task.cancel() }
        upcoming = []
    }

    /// Prepara tríos hasta tener `ahead` listos (o en camino) para los filtros de ahora.
    private func fillUpcoming() {
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
    private var filtersKey: String {
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
    private var ratingTMDB: Task<Void, Never>?
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

    private var candidatesPool: [Suggestion] {
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
    /// Cuántas opciones hay con lo elegido (o con un cambio: `change`), sin contar lo que ya viste ni lo apartado hoy. Lo
    /// que aún no se sabe (sin datos de Cinemeta) no cuenta todavía; el número sube solo cuando llegan.
    /// `strictTime`: que el tiempo filtre aunque no lo hayas elegido (los conteos del menú «Tiempo»).
    public func count(strictTime: Bool? = nil, _ change: (inout Filters) -> Void = { _ in }) -> Int {
        let strict = strictTime ?? timeChosen
        var f = filters
        change(&f)
        let skipped = notToday()
        let seen = f.includeWatched ? [] : (watched ?? [])
        return candidatesPool.filter { s in
            guard !skipped.contains(s.imdb), !seen.contains(s.imdb), f.kind == nil || s.kind == f.kind, let v = verdict(s, f) else { return false }
            // El tiempo de la hora (no lo elegiste) ordena, no filtra: cuenta lo mismo que se puede proponer.
            return v.matches && (v.fits || !strict)
        }.count
    }

    /// Las listas elegidas, para decir de dónde salen («de «Terror de octubre»», «de 2 listas»).
    public var chosenSourceNames: [String] { sources.filter { sourceIDs.contains($0.id) }.map(\.name) }

    /// Cuántas candidatas aún no se pueden decidir con lo elegido (falta su género, año o calificación de Cinemeta).
    public func unknownCount() -> Int {
        let f = filters
        return candidatesPool.filter { verdict($0, f) == nil }.count
    }

    /// Pide ya a Cinemeta lo que falta para decidir con lo elegido (en «Más filtros», al tocar un género o una época): el
    /// conteo llega solo, en vez de decir «sin opciones» mientras no se sabe.
    private var resolving: Task<Void, Never>?
    public func resolveUnknown() {
        let f = filters
        let unknown = candidatesPool.filter { verdict($0, f) == nil }
        guard !unknown.isEmpty, resolving == nil else { return }
        resolving = Task { [weak self] in
            for start in stride(from: 0, to: unknown.count, by: Self.chunk) {
                guard !Task.isCancelled, let self else { return }
                await self.describe(Array(unknown[start..<min(start + Self.chunk, unknown.count)]))
            }
            self?.resolving = nil
        }
    }

    /// Nada cumple: qué quitar (o qué tiempo dar) y con cuántas quedarías; los dos que más abren.
    public func relaxations() -> [(relax: Relax, count: Int)] {
        var out: [(Relax, Int)] = []
        for g in genres { out.append((.genre(g), count { $0.genres.remove(g) })) }
        if mood != nil { out.append((.mood, count { $0.mood = nil })) }
        if kind != nil { out.append((.kind, count { $0.kind = nil })) }
        if !decades.isEmpty { out.append((.decades, count { $0.decades = [] })) }
        if minRating > 0 { out.append((.rating, count { $0.minRating = 0 })) }
        if timeChosen { for t in Time.allCases where t != time { out.append((.time(t), count(strictTime: true) { $0.time = t })) } }
        return Array(out.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }.prefix(2))
    }

    public func relax(_ r: Relax) async {
        switch r {
        case .genre(let g): genres.remove(g)
        case .mood: mood = nil
        case .kind: kind = nil
        case .decades: decades = []
        case .rating: minRating = 0
        case .time(let t): time = t; timeChosen = true
        case .lists: sourceIDs = []
        }
        await apply()
    }

    /// «Limpiar» en «Más filtros»: géneros, época, listas y lo visto (la calificación va aparte).
    public func clearMoreFilters() async {
        genres = []; decades = []; includeWatched = false; sourceIDs = []
        await apply()
    }

    private func prepare() async {
        dropUpcoming()
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
    ///
    /// Mientras busca, los tres de antes se quedan quietos (antes el nombre cambiaba con cada búsqueda y los carteles
    /// hasta el final); los nuevos llegan juntos, con sus datos y sus carteles.
    public func next() async {
        let key = filtersKey
        var found: [Suggestion] = []
        if let ready = upcoming.first, ready.key == key {
            upcoming.removeFirst()
            // Casi siempre ya está listo (se preparó mientras veías los de antes); si no, se espera solo a ese.
            isLoading = true
            let skipped = notToday()
            found = await ready.task.value.filter { !skipped.contains($0.imdb) }
        }
        if found.isEmpty {
            dropUpcoming()
            isLoading = true
            found = await trio(waitForPosters: true)
        }
        isLoading = false   // ya se ven: «Barajar» responde otra vez (antes esperaba también la duración y la calificación)
        picks = found
        if let first = found.first { select(first) } else { pick = nil; exhausted = true }
        // La duración y la calificación llegan después, sin bloquear nada; los siguientes se preparan desde ya.
        fillUpcoming()
        enrichPicks(found)
    }

    /// La duración y la calificación de los tres que se ven, si faltan: llegan solas al renglón de datos.
    private func enrichPicks(_ found: [Suggestion]) {
        enriching?.cancel()
        guard found.contains(where: { details[$0.imdb] == nil }) else { return }
        enriching = Task { [weak self] in
            await self?.describe(found)
            guard let self, !Task.isCancelled, let current = self.pick, found.contains(where: { $0.imdb == current.imdb }) else { return }
            self.select(current)
        }
    }

    /// Tres que caben, con sus datos y sus carteles. `waitForPosters`: los de ahora esperan sus carteles un momento (si la
    /// red tarda, se enseñan igual); los que se preparan por adelantado los bajan completos, sin prisa.
    private func trio(waitForPosters: Bool) async -> [Suggestion] {
        var found: [Suggestion] = []
        for _ in 0..<Self.trio {
            guard !Task.isCancelled, let p = await search(), !found.contains(where: { $0.imdb == p.imdb }) else { break }
            found.append(p)
        }
        guard !Task.isCancelled, let warm = warmPosters else { return found }
        let posters = found.compactMap(\.poster)
        if !waitForPosters { await warm(posters); return found }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await warm(posters) }
            group.addTask { try? await Task.sleep(nanoseconds: UInt64(Self.posterWait * 1_000_000_000)) }
            await group.next()
            group.cancelAll()
        }
        return found
    }

    /// Tocar uno de los tres carteles: esa es la propuesta.
    public func select(_ s: Suggestion) {
        pick = s
        minutes = s.runtime ?? details[s.imdb]?.minutes
        imdbRating = details[s.imdb]?.rating
    }

    /// La siguiente candidata que cabe (y la marca como enseñada); nil: no hay ninguna.
    private func search(retried: Bool = false) async -> Suggestion? {
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
        let f = filters
        func verdict(_ s: Suggestion) -> (matches: Bool, fits: Bool)? { self.verdict(s, f) }
        func take(_ s: Suggestion) -> Suggestion {
            shown.insert(s.imdb)
            return s
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
            if Task.isCancelled || services.now().timeIntervalSince(started) > Self.budget { break }
            await describe(chunk)
            for s in chunk {
                guard let v = verdict(s) else { continue }
                if v.matches && v.fits { return take(s) }
                if v.matches, closest == nil { closest = s }
            }
        }
        // La más cercana (aunque dure más de lo que tienes), solo si el tiempo no lo elegiste tú: si dijiste «30 min», no se
        // propone una de dos horas. Solo esa cuenta como enseñada, no todas las revisadas.
        if let closest, !timeChosen { return take(closest) }
        // Con un filtro, las que cumplen ya salieron todas: otra vuelta desde el principio (una vez), no «No encontré».
        if !retried, !shown.isEmpty { shown = []; return await search(retried: true) }
        return nil
    }

    /// ¿Cumple? (nil: falta preguntarle a Cinemeta o a TMDB). `fits`: cabe en el tiempo.
    private func verdict(_ s: Suggestion, _ f: Filters) -> (matches: Bool, fits: Bool)? {
        let d = details[s.imdb]
        let genreList = s.genres.isEmpty ? d?.genres : s.genres
        if (!f.genres.isEmpty || f.mood != nil) && genreList == nil { return nil }
        let year = s.year ?? d?.year
        if !f.decades.isEmpty && year == nil && d == nil { return nil }
        var ok = true
        if !f.genres.isEmpty { ok = Self.matches(genreList ?? [], picked: f.genres) }
        else if let mood = f.mood { ok = Self.matches(genreList ?? [], mood) }
        if ok, !f.decades.isEmpty { ok = year.map { Self.inDecades($0, f.decades) } ?? false }
        if ok, f.minRating > 0 {
            // Basta con que una de las elegidas llegue; si ninguna se sabe y falta preguntar, aún no se decide.
            var known: [Double] = []
            var pending = false
            for source in f.ratingSources {
                switch source {
                case .imdb: if let r = d?.rating { known.append(r) } else if d == nil { pending = true }
                case .trakt: if let r = s.traktRating { known.append(r) }
                case .tmdb: if let r = d?.tmdbRating { known.append(r) } else if d?.tmdbChecked != true && services.tmdb.configured { pending = true }
                }
            }
            if known.contains(where: { $0 >= f.minRating }) { ok = true }
            else if pending { return nil }
            else { ok = false }
        }
        return (ok, Self.fits(s.runtime ?? d?.minutes, f.time))
    }

    static let chunk = 12
    static let watchedWait: Double = 1.5
    /// Lo más que se busca antes de proponer la más cercana (segundos).
    static let budget: TimeInterval = 6
    /// Lo más que se espera a los carteles antes de enseñar los tres (segundos).
    static let posterWait: Double = 1.2

    /// Volver a las preguntas.
    public func reset() async { pick = nil; exhausted = false; dropUpcoming() }

    /// Al cerrar la hoja: lo que se preparaba en segundo plano ya no hace falta.
    public func stop() {
        dropUpcoming(); enriching?.cancel(); describingAll?.cancel(); describingAll = nil; ratingTMDB?.cancel(); ratingTMDB = nil
        resolving?.cancel(); resolving = nil
    }

    /// «No me interesa» (lo mismo que en Para ti): ya no se sugiere en ningún lado (ni en la TV) y se cambia por otra.
    public func notInterested() async {
        if let pick {
            await services.forYou.dismiss(pick.imdb)
            if services.orbital.isConfigured { await services.forYouRemote.dismiss(pick.imdb) }
        }
        await skipToday()
    }

    /// «Hoy no»: no vuelve a salir en 24 horas; y otra.
    public func skipToday() async {
        if let pick {
            var skipped = notTodayRaw()
            skipped[pick.imdb] = services.now().timeIntervalSince1970
            services.kv.set(Self.skipKey, data: try? JSONEncoder().encode(skipped))
            // Solo esa se cambia por otra; las otras dos se quedan.
            let current = pick.imdb
            let others = picks.filter { $0.imdb != current }
            dropUpcoming()   // los preparados ya no cuentan (se piden otros abajo, sin esperar a los viejos)
            if let fresh = await search(), !others.contains(where: { $0.imdb == fresh.imdb }) {
                await describe([fresh])
                await warmPosters?([fresh.poster].compactMap { $0 })
                picks = picks.map { $0.imdb == current ? fresh : $0 }
                select(fresh)
            } else {
                picks = others
                if let first = others.first { select(first) }
            }
            fillUpcoming()
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
        var learned = false
        for (id, genres, minutes, rating, year) in found {
            let old = details[id]
            details[id] = Detail(genres: genres, minutes: minutes, rating: rating, year: year, tmdbRating: old?.tmdbRating, tmdbChecked: old?.tmdbChecked)
            learned = learned || !genres.isEmpty || minutes != nil || rating != nil || year != nil
        }
        if learned { saveDetails(); changed() }   // los conteos («34 opciones») suben solos
    }

    /// Se guardan solo los que trajeron algo (un fallo de red se vuelve a preguntar la próxima vez), hasta un tope.
    private func saveDetails() {
        var keep = details.filter { !$0.value.genres.isEmpty || $0.value.minutes != nil || $0.value.rating != nil || $0.value.year != nil }
        if keep.count > Self.detailsLimit { keep = Dictionary(uniqueKeysWithValues: keep.prefix(Self.detailsLimit).map { ($0.key, $0.value) }) }
        services.kv.set(Self.detailsKey, data: try? JSONEncoder().encode(keep))
    }
}
