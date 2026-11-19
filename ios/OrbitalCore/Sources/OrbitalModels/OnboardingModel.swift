import Foundation
import OrbitalCore

/// La guía de la primera vez, versión 3 (Fernando, 18 nov 2026: «Me gusta, empieza a construir»; prototipo en
/// `docs/producto/guia-trabajos-2026-11-18/onboarding/`). El camino sale de la versión y de lo que ya pasó, sin preguntar
/// qué tienes: bienvenida, tu TV (solo donde hay TV), Trakt, «Trajimos lo tuyo» (solo si Trakt trajo algo), tu nube (Plus y
/// Ultra) o tus plataformas (la de la tienda), más subtítulos y «Listo». Nada es obligatorio. Si cierras la app a medias,
/// antes de 24 h sigue donde ibas. Se reabre desde Ajustes › Aprende Orbital.
@MainActor
public final class OnboardingModel: ObservableModel {
    public enum Step: String, CaseIterable, Hashable, Sendable {
        case welcome, tv, trakt, win, debrid, platforms, subtitles, done
        var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }
    }

    /// Lo que la guía explica (cuenta como visto en «Aprende» al terminar).
    public enum Piece: String, CaseIterable, Sendable { case debrid, trakt, tv }

    static let seenKey = "onboarding-seen"
    static let progressKey = "onboarding-progress"
    static let resumeWindow: TimeInterval = 24 * 3600

    public let debrid: DebridModel
    public let addons: AddonsModel
    /// El enlace de Trakt con código (el mismo de Ajustes).
    public let settings: SettingsModel
    /// Lo que se trajo de Trakt al conectarlo (TK-L2, 18 nov 2026): vistas, en Mi lista y series que sigues. Todo en cero es
    /// una cuenta nueva: la pantalla no enseña ceros.
    public private(set) var brought: Brought? { didSet { changed() } }
    public struct Brought: Equatable, Sendable {
        public let watched: Int, listed: Int, shows: Int
        public init(watched: Int, listed: Int, shows: Int) { self.watched = watched; self.listed = listed; self.shows = shows }
        public var isEmpty: Bool { watched == 0 && listed == 0 && shows == 0 }
    }
    /// Los pósters para elegir lo que te gusta (lo popular de ahora).
    public private(set) var candidates: [Suggestion] = [] { didSet { changed() } }
    public private(set) var liked: [String] = [] { didSet { changed() } }
    /// Las plataformas de tu país, para prender las tuyas.
    public private(set) var platforms: [(brand: String, name: String, logo: String?)] = [] { didSet { changed() } }
    public private(set) var chosenPlatforms: Set<String> = [] { didSet { changed() } }
    private let services: Services

    public init(_ services: Services) {
        self.services = services
        debrid = DebridModel(services); addons = AddonsModel(services); settings = SettingsModel(services)
        liked = Taste.likes(services.kv).map(\.imdb)
        chosenPlatforms = Set(Taste.platforms(services.kv))
        super.init()
    }

    /// ¿Se enseña la guía al abrir? La primera vez. Quien ya usaba la app (Real-Debrid o Trakt conectados) no la ve.
    public static func shouldShow(_ services: Services) -> Bool {
        services.kv.data(seenKey) == nil && !services.debrid.hasToken && services.trakt?.linked != true
    }

    // MARK: los pasos

    /// ¿La TV es parte de esta app? (En la Mac, Plus y Orbital no: `capabilities.console`.)
    public var offersTV: Bool { services.capabilities.console }
    /// ¿Ver al instante (Real-Debrid) es parte de esta versión? En Orbital (App Store) no.
    public var offersDebrid: Bool { services.capabilities.instantStreams }
    /// ¿Hay cómo conectar Trakt en esta compilación?
    public var offersTrakt: Bool { if case .off = settings.trakt { return false }; return true }

    /// ¿Se ofrece conectar OpenSubtitles? Con la clave de la app y sin tu cuenta todavía (se lee al abrir la guía).
    /// La guía de práctica (Aprende › «Ver la guía otra vez»): corre sobre unos `Services` aparte y lo que conecta es de mentira.
    public var practice = false
    /// La versión y el aparato de estos `Services` (la TV de la guía pregunta aquí, no a la app).
    public var orbitalConfigured: Bool { services.orbital.isConfigured }
    /// Práctica: «conecta» la TV de mentira en estos `Services` (nada sale a tu TV de verdad).
    public func connectPracticeTV() {
        guard practice else { return }
        services.settings.update { $0.orbitalAddress = "tv.practica.invalid"; $0.orbitalEnabled = true }
        services.secrets.set(SecretKey.orbitalToken, "practica")
        changed()
    }
    public var offersSubtitles = false { didSet { if oldValue != offersSubtitles { changed() } } }
    /// Los pasos donde ya estuviste: siguen en el plan aunque ahí mismo conectes la pieza (si no, la luna del arco regresaba
    /// al principio al conectar tu nube o Trakt; 18 nov 2026). Regla en `docs/ios-interfaz.md` § «La guía no se reacomoda».
    private var visited: Set<Step> = [] { didSet { if oldValue != visited { changed() } } }

    public func isConnected(_ piece: Piece) -> Bool {
        switch piece {
        case .debrid: services.debrid.hasToken
        case .trakt: services.trakt?.linked == true
        case .tv: services.orbital.isConfigured
        }
    }

    /// Los pasos de tu guía (v3): lo ya conectado antes de llegar no se explica; donde ya estuviste, sigue aunque ahí lo
    /// conectes. «Trajimos lo tuyo» solo si Trakt trajo algo. Con nube (Plus y Ultra) se explica tu nube; sin ella (la de la
    /// tienda), tus plataformas.
    public var plan: [Step] {
        var out: [Step] = [.welcome]
        if offersTV, visited.contains(.tv) || !isConnected(.tv) { out.append(.tv) }
        if offersTrakt, visited.contains(.trakt) || !isConnected(.trakt) { out.append(.trakt) }
        if visited.contains(.win) || brought.map({ !$0.isEmpty }) == true { out.append(.win) }
        if offersDebrid {
            if visited.contains(.debrid) || !isConnected(.debrid) { out.append(.debrid) }
        } else {
            out.append(.platforms)
        }
        // Más subtítulos (OpenSubtitles): solo si esta versión trae la clave de la app y aún no está tu cuenta.
        if offersSubtitles { out.append(.subtitles) }
        out.append(.done)
        return out
    }

    /// Los pasos que cuentan los puntos del arco: el camino más largo (con «Trajimos lo tuyo» donde va Trakt), para que el
    /// número no cambie a medio camino cuando Trakt trae algo.
    var dotPlan: [Step] {
        var out = plan
        if out.contains(.trakt), !out.contains(.win), let i = out.firstIndex(of: .trakt) { out.insert(.win, at: i + 1) }
        return out
    }

    /// El paso que sigue según tu plan.
    public func next(after step: Step) -> Step? {
        let plan = plan
        guard let i = plan.firstIndex(of: step) else { return plan.first { $0.order > step.order } }
        return i + 1 < plan.count ? plan[i + 1] : nil
    }

    /// En qué paso vas y cuántos son (la luna en el arco).
    public func position(_ step: Step) -> (current: Int, total: Int) {
        let plan = dotPlan
        return (plan.firstIndex(of: step) ?? 0, plan.count)
    }

    /// Nada detiene la guía: cada paso tiene «Ahora no».
    public func canContinue(_ step: Step) -> Bool { true }

    // MARK: retomar

    /// Guarda en qué paso vas (para seguir ahí si cierras la app antes de 24 h).
    public func reached(_ step: Step) {
        visited.insert(step)
        guard step != .welcome, step != .done else { return }
        let saved: [String: String] = ["step": step.rawValue, "at": String(services.now().timeIntervalSince1970)]
        services.kv.set(Self.progressKey, data: try? JSONEncoder().encode(saved))
    }

    /// El paso donde ibas, si cerraste la app hace menos de 24 h.
    public var resumeStep: Step? {
        guard let data = services.kv.data(Self.progressKey), let saved = try? JSONDecoder().decode([String: String].self, from: data),
              let step = saved["step"].flatMap(Step.init(rawValue:)), let at = saved["at"].flatMap(Double.init) else { return nil }
        return services.now().timeIntervalSince1970 - at < Self.resumeWindow ? step : nil
    }

    /// ¿Quedó a medias hace más de 24 h? Inicio lo dice sin obligar: «Termina de preparar Orbital».
    public static func unfinished(_ services: Services) -> Bool {
        services.kv.data(seenKey) == nil && services.kv.data(progressKey) != nil && OnboardingModel(services).resumeStep == nil
    }

    // MARK: los pósters de la bienvenida y tus plataformas

    /// Lo popular de ahora, películas y series alternadas; sin red, el último mosaico guardado.
    public func loadCandidates() async {
        guard candidates.isEmpty else { return }
        let forYou = services.forYou
        async let movies = (try? await forYou.items(listID: "trend", kind: "movie")) ?? []
        async let series = (try? await forYou.items(listID: "trend", kind: "series")) ?? []
        let (m, s) = await (movies, series)
        var mixed: [Suggestion] = [], seen = Set<String>()
        for i in 0..<max(m.count, s.count) {
            for list in [m, s] where i < list.count && !list[i].poster.isEmpty && seen.insert(list[i].imdb).inserted { mixed.append(list[i]) }
        }
        if mixed.isEmpty { mixed = await forYou.cachedMosaic().filter { !$0.poster.isEmpty } }
        candidates = Array(mixed.prefix(18))
    }

    public func loadPlatforms() async {
        let found = await services.forYou.platforms()
        platforms = Tmdb.platforms.compactMap { p in found[p.brand].map { (p.brand, p.name, $0.logo) } }
    }

    public func togglePlatform(_ brand: String) {
        if chosenPlatforms.contains(brand) { chosenPlatforms.remove(brand) } else { chosenPlatforms.insert(brand) }
        Taste.setPlatforms(chosenPlatforms.sorted(), services.kv)
    }

    // MARK: Trakt

    /// Trakt quedó conectado: se trae lo tuyo y se cuenta para decirlo.
    public func traktLinked() async {
        await services.syncLibrary(force: true)
        let all = services.library.all
        brought = Self.count(all)
    }

    // MARK: Trajimos lo tuyo (K4-B)

    /// Un póster del mosaico de «Trajimos lo tuyo»: lo más reciente de tu historial y tu lista.
    public struct WinTile: Equatable, Sendable, Identifiable {
        public let id: String, kind: String, title: String, poster: String?, listed: Bool
    }
    /// La sugerencia de ejemplo con su porqué («Porque viste Severance»): sale de lo que Trakt trajo.
    public struct Tonight: Equatable, Sendable {
        public let seed: String, seedID: String, seedKind: String, pick: Suggestion
    }
    public private(set) var winTiles: [WinTile] = [] { didSet { changed() } }
    public private(set) var tonight: Tonight? { didSet { changed() } }
    public static let winTileCount = 18

    /// Arma «Trajimos lo tuyo»: el mosaico con lo tuyo (con póster, lo más reciente primero) y una sugerencia con su porqué.
    /// La semilla queda en el mosaico para iluminarla.
    public func loadWin() async {
        if winTiles.isEmpty { winTiles = Self.tiles(services.library.all) }
        guard tonight == nil, let found = await services.forYou.becauseYouWatched(), let pick = found.items.first else { return }
        tonight = Tonight(seed: found.seed.title, seedID: found.seed.imdb, seedKind: found.seed.kind, pick: pick)
        if !winTiles.contains(where: { $0.id == found.seed.imdb }),
           let entry = services.library.all.first(where: { $0.metaID == found.seed.imdb && $0.poster != nil }) {
            winTiles = Array(([WinTile(id: entry.metaID, kind: entry.kind, title: entry.name, poster: entry.poster, listed: entry.inList)] + winTiles).prefix(Self.winTileCount))
        }
    }

    /// Lo tuyo para el mosaico: lo que no ocultaste, con póster, visto o en tu lista, lo más reciente primero.
    public static func tiles(_ all: [LibraryEntry]) -> [WinTile] {
        all.filter { $0.hiddenAt == nil && $0.poster?.isEmpty == false && (!$0.seen.isEmpty || $0.inList) }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(winTileCount)
            .map { WinTile(id: $0.metaID, kind: $0.kind, title: $0.name, poster: $0.poster, listed: $0.inList) }
    }

    /// Lo que cuenta la pantalla de Trakt: lo visto (cada película y cada episodio), lo de Mi lista y las series con algo visto.
    public static func count(_ all: [LibraryEntry]) -> Brought {
        let shown = all.filter { $0.hiddenAt == nil }
        return Brought(watched: shown.reduce(0) { $0 + $1.seen.count }, listed: shown.filter(\.inList).count,
                       shows: shown.filter { $0.kind == "series" && !$0.seen.isEmpty }.count)
    }

    /// El nombre de la cuenta de Trakt conectada.
    /// El nombre de tu cuenta de Trakt; `nil` si Trakt no lo dio (vacío o solo espacios), para no decir «Listo,» a secas.
    public var traktName: String? {
        guard case .linked(let name) = settings.trakt else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: fin

    /// Termina la guía (no se vuelve a enseñar sola). Lo que se explicó aquí cuenta como visto en «Aprende» y en la tarjeta
    /// «Así funciona» de Real-Debrid (`learn.seen.debrid-flow`).
    public func finish(explained: Set<Piece> = []) {
        services.kv.set(Self.seenKey, data: Data("1".utf8))
        services.kv.set(Self.progressKey, data: nil)
        let learn = LearnModel(services)
        if explained.contains(.debrid) { learn.markSeen(LearnContent.instant.id); learn.markSeen(LearnModel.debridFlowKey) }
        if explained.contains(.trakt) { learn.markSeen(LearnContent.thread.id) }
        learn.guideFinished()
    }
}
