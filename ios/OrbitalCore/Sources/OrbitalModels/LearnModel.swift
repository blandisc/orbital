import Foundation
import OrbitalCore

/// «Aprende Orbital» y los avisos sobre la pantalla (G3 y F3, Fernando, 3 nov 2026). Recuerda qué historias y qué avisos ya
/// viste (`learn.seen.<id>` en kv; la tarjeta «Así funciona» de Real-Debrid usa `learn.seen.debrid-flow`).
///
/// Los círculos de Inicio: hasta 4 sin ver, ordenados por lo que te falta. Se van a Ajustes cuando los viste todos o a los
/// 14 días de aparecer; «Cómo pagar» vuelve sola si tu Real-Debrid venció. Los avisos: nunca el mismo día de la guía, como
/// máximo uno cada vez que abres la app, nunca si ya usaste esa función, y «Saltar avisos» los apaga todos.
@MainActor
public final class LearnModel: ObservableModel {
    public static let debridFlowKey = "debrid-flow"
    static let ringsSinceKey = "learn.rings-since"
    static let coachOffKey = "learn.coach-off"
    static let guideDoneKey = "learn.guide-done"
    static let ringWindow: TimeInterval = 14 * 86400
    public static let ringLimit = 4

    /// Un aviso por cada vez que abres la app (no por pantalla): lo lleva la sesión, no el disco.
    static var coachShownThisLaunch = false

    private let services: Services

    public init(_ services: Services) {
        self.services = services
        super.init()
    }

    // MARK: historias

    /// Las historias de esta app (la de la TV, solo donde hay TV).
    public var stories: [LearnStory] { LearnContent.all.filter { $0.needs != .tv || services.allowsOrbital } }

    public func seen(_ id: String) -> Bool { services.kv.data("learn.seen.\(id)") != nil }

    public func markSeen(_ id: String) {
        guard !seen(id) else { return }
        services.kv.set("learn.seen.\(id)", data: Data("1".utf8))
        changed()
    }

    /// Lo que te falta, primero: sin Real-Debrid, cómo pagarlo; luego lo propio de Orbital que más se usa.
    var priority: [String] {
        var out: [String] = []
        if !services.debrid.hasToken { out += ["pay", "debrid"] }
        out += ["advanced", "player", "versions", "explore"]
        if services.trakt?.linked != true { out.append("trakt") }
        return out + stories.map(\.id)
    }

    /// Los círculos de arriba de Inicio (vacío: ya viven solo en Ajustes). `debridExpired`: tu cuenta venció.
    public func rings(debridExpired: Bool = false) -> [LearnStory] {
        let byID = Dictionary(stories.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var order: [String] = []
        for id in priority where !order.contains(id) { order.append(id) }
        if debridExpired { return byID["pay"].map { [$0] } ?? [] }   // vuelve sola, aunque ya la hayas visto
        guard services.kv.data(Self.guideDoneKey) != nil || !OnboardingModel.shouldShow(services) else { return [] }
        let since = ringsSince()
        guard services.now().timeIntervalSince1970 - since < Self.ringWindow else { return [] }
        return Array(order.compactMap { byID[$0] }.filter { !seen($0.id) }.prefix(Self.ringLimit))
    }

    /// Cuándo aparecieron los círculos por primera vez (se anota la primera vez que se piden).
    private func ringsSince() -> TimeInterval {
        if let data = services.kv.data(Self.ringsSinceKey), let text = String(data: data, encoding: .utf8), let at = Double(text) { return at }
        let now = services.now().timeIntervalSince1970
        services.kv.set(Self.ringsSinceKey, data: Data(String(now).utf8))
        return now
    }

    /// La guía terminó: los avisos esperan a la próxima vez que abras la app.
    public func guideFinished() {
        services.kv.set(Self.guideDoneKey, data: Data("1".utf8))
        Self.coachShownThisLaunch = true
    }

    // MARK: avisos sobre la pantalla

    public var coachOff: Bool { services.kv.data(Self.coachOffKey) != nil }

    /// ¿Sale este aviso ahora? `used`: ya usaste la función (no hace falta explicarla).
    public func shouldCoach(_ id: String, used: Bool = false) -> Bool {
        guard !coachOff, !Self.coachShownThisLaunch, !used, !seen("coach.\(id)") else { return false }
        guard services.kv.data(Self.guideDoneKey) != nil || !OnboardingModel.shouldShow(services) else { return false }
        return true
    }

    /// Salió un aviso: no se repite y no sale otro hasta que vuelvas a abrir la app.
    public func coached(_ id: String) {
        Self.coachShownThisLaunch = true
        markSeen("coach.\(id)")
    }

    /// «Saltar avisos»: no vuelve a salir ninguno.
    public func skipAllCoach() {
        services.kv.set(Self.coachOffKey, data: Data("1".utf8))
        changed()
    }

    /// Ajustes › Aprende › «Volver a ver los avisos»: los avisos y los círculos, desde cero.
    public func reset() {
        for story in LearnContent.all { services.kv.set("learn.seen.\(story.id)", data: nil) }
        for id in CoachID.allCases { services.kv.set("learn.seen.coach.\(id.rawValue)", data: nil) }
        services.kv.set(Self.coachOffKey, data: nil)
        services.kv.set(Self.ringsSinceKey, data: nil)
        Self.coachShownThisLaunch = false
        changed()
    }

    /// Los avisos que hay (F3): foco en la ficha y en la búsqueda avanzada; aviso chico en lo demás.
    public enum CoachID: String, CaseIterable, Sendable {
        case titlePlay = "title-play", advancedSearch = "advanced-search", explore, downloads, playerGestures = "player-gestures"
        /// ¿Con foco (oscurece todo menos el botón) o aviso chico?
        public var spotlight: Bool { self == .titlePlay || self == .advancedSearch }
        /// La historia que abre «Ver la historia».
        public var story: String {
            switch self {
            case .titlePlay: "versions"
            case .advancedSearch: "advanced"
            case .explore: "explore"
            case .downloads: "downloads"
            case .playerGestures: "player"
            }
        }
    }
}
