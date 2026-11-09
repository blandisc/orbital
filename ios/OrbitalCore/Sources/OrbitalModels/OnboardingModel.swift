import Foundation
import OrbitalCore

/// La guía de la primera vez, versión 2 (`docs/producto/guia-aprende/propuesta.md`; Fernando, 3 nov 2026: «A1 · B1 · C1 · D1 ·
/// E1 · F3 · G3 · H1»). Nada es obligatorio: bienvenida, lo que te gusta (gustos, no vistos), «¿Qué ya tienes?» y, según lo
/// que contestes, Real-Debrid, Trakt y la TV; luego «Listo». Pagar Real-Debrid no la detiene: «Cuando quiera ver algo» la
/// termina y la hoja de conectar sale la primera vez que tocas «Ver». Si cierras la app a medias, antes de 24 h sigue donde
/// ibas. Se reabre desde Ajustes › Aprende Orbital.
@MainActor
public final class OnboardingModel: ObservableModel {
    public enum Step: String, CaseIterable, Hashable, Sendable {
        case welcome, likes, have, debrid, trakt, tv, subtitles, done
        var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }
    }

    /// Lo que contestas en «¿Qué ya tienes?» de cada pieza.
    public enum Answer: String, Equatable, Sendable { case has, explain, later }

    /// Una pieza de «¿Qué ya tienes?».
    public enum Piece: String, CaseIterable, Sendable { case debrid, trakt, tv }

    static let seenKey = "onboarding-seen"
    static let progressKey = "onboarding-progress"
    static let resumeWindow: TimeInterval = 24 * 3600
    public static let minimumLikes = 3

    public let debrid: DebridModel
    public let addons: AddonsModel
    /// El enlace de Trakt con código (el mismo de Ajustes).
    public let settings: SettingsModel
    /// Lo que se trajo de Trakt al conectarlo: «Trajimos 214 vistos y 38 en tu lista».
    public private(set) var brought: (watched: Int, listed: Int)? { didSet { changed() } }
    public private(set) var answers: [Piece: Answer] = [:] { didSet { changed() } }
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
        for piece in Piece.allCases where isConnected(piece) { answers[piece] = .has }
    }

    /// ¿Se enseña la guía al abrir? La primera vez. Quien ya usaba la app (Real-Debrid o Trakt conectados) no la ve.
    public static func shouldShow(_ services: Services) -> Bool {
        services.kv.data(seenKey) == nil && !services.debrid.hasToken && services.trakt?.linked != true
    }

    // MARK: los pasos

    /// ¿La TV es parte de esta app? (En la Mac no: `allowsOrbital`.)
    public var offersTV: Bool { services.allowsOrbital }
    /// ¿Hay cómo conectar Trakt en esta compilación?
    public var offersTrakt: Bool { if case .off = settings.trakt { return false }; return true }
    public var pieces: [Piece] { Piece.allCases.filter { $0 != .tv || offersTV }.filter { $0 != .trakt || offersTrakt } }

    /// ¿Se ofrece conectar OpenSubtitles? Con la clave de la app y sin tu cuenta todavía (se lee al abrir la guía).
    public var offersSubtitles = false { didSet { if oldValue != offersSubtitles { changed() } } }

    public func isConnected(_ piece: Piece) -> Bool {
        switch piece {
        case .debrid: services.debrid.hasToken
        case .trakt: services.trakt?.linked == true
        case .tv: services.orbital.isConfigured
        }
    }

    public func answer(_ piece: Piece, _ value: Answer) { answers[piece] = value }

    /// Un toque en su objeto: lo tienes o no (Q1).
    public func toggle(_ piece: Piece) { answers[piece] = answers[piece] == .has ? nil : .has }

    /// ¿La pantalla de Trakt lleva también la de la TV? (Q3: con los dos, una sola de «tus aparatos».)
    public var traktWithTV: Bool { offersTV && !isConnected(.tv) && answers[.tv] == .has }

    /// Los pasos de tu guía con lo que marcaste (revisión del director, Q1: lo que no tienes, no se marca). «Ver aquí mismo» sale
    /// siempre que Real-Debrid no esté conectado (ahí se explica); Trakt y la TV, solo si marcaste que los tienes. Con los dos,
    /// van juntos en una sola pantalla de «tus aparatos» (Q3).
    public var plan: [Step] {
        var out: [Step] = [.welcome, .likes, .have]
        if !isConnected(.debrid), answers[.debrid] != .later { out.append(.debrid) }
        let trakt = offersTrakt && !isConnected(.trakt) && answers[.trakt] == .has
        let tv = offersTV && !isConnected(.tv) && answers[.tv] == .has
        if trakt { out.append(.trakt) }
        if tv && !trakt { out.append(.tv) }
        // Más subtítulos (OpenSubtitles): solo si esta versión trae la clave de la app y aún no está tu cuenta.
        if offersSubtitles { out.append(.subtitles) }
        out.append(.done)
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
        let plan = plan
        return (plan.firstIndex(of: step) ?? 0, plan.count)
    }

    /// Nada detiene la guía: Real-Debrid y Trakt tienen «Cuando quiera» y «Ahora no».
    public func canContinue(_ step: Step) -> Bool { true }

    // MARK: retomar

    /// Guarda en qué paso vas (para seguir ahí si cierras la app antes de 24 h).
    public func reached(_ step: Step) {
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

    // MARK: lo que te gusta (H1)

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

    public func toggleLike(_ item: Suggestion) {
        if let i = liked.firstIndex(of: item.imdb) { liked.remove(at: i) } else { liked.append(item.imdb) }
        let known = Dictionary(candidates.map { ($0.imdb, $0) }, uniquingKeysWith: { a, _ in a })
        let kept = Taste.likes(services.kv).filter { liked.contains($0.imdb) && known[$0.imdb] == nil }
        let new = liked.compactMap { known[$0] }.map { Taste.Like(kind: $0.kind, imdb: $0.imdb, title: $0.title, year: $0.year) }
        Taste.setLikes(kept + new, services.kv)
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
        brought = (all.reduce(0) { $0 + $1.seen.count }, all.filter(\.inList).count)
    }

    /// El nombre de la cuenta de Trakt conectada.
    public var traktName: String? { if case .linked(let name) = settings.trakt { return name }; return nil }

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
