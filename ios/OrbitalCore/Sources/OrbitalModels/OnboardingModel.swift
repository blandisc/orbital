import Foundation
import OrbitalCore

/// La guía de la primera vez (`docs/producto/desacoplar-stremio/maquetas.html`, pantallas 1–10): Real-Debrid y Trakt son
/// obligatorios; Stremio se puede dejar para después. La app es de una sola pieza: la guía no habla de la TV (tu Orbital se
/// prende en Ajustes). Se reabre desde Ajustes › «Cómo funciona Orbital».
@MainActor
public final class OnboardingModel: ObservableModel {
    public enum Step: Int, CaseIterable, Hashable, Sendable {
        case welcome, howItWorks, debridIntro, debridKey, addons, trakt, traktDone, done
    }
    static let seenKey = "onboarding-seen"

    public let debrid: DebridModel
    public let addons: AddonsModel
    /// El enlace de Trakt con código (el mismo de Ajustes).
    public let settings: SettingsModel
    /// Lo que se trajo de Trakt al conectarlo: «Trajimos 214 vistos y 38 en tu lista».
    public private(set) var brought: (watched: Int, listed: Int)? { didSet { changed() } }
    private let services: Services

    public init(_ services: Services) {
        self.services = services
        debrid = DebridModel(services); addons = AddonsModel(services); settings = SettingsModel(services)
        super.init()
    }

    /// ¿Se enseña la guía al abrir? La primera vez, salvo que ya tengas Real-Debrid y Trakt conectados.
    public static func shouldShow(_ services: Services) -> Bool {
        services.kv.data(seenKey) == nil && !(services.debrid.hasToken && services.trakt?.linked == true)
    }

    /// ¿Se puede seguir desde este paso? Real-Debrid y Trakt no dejan avanzar sin quedar conectados.
    public func canContinue(_ step: Step) -> Bool {
        switch step {
        case .debridKey: return debrid.ready
        // Sin aplicación de Trakt en esta compilación no hay cómo conectarlo: no se traba la guía.
        case .trakt: if case .off = settings.trakt { return true } else { return settings.traktLinked }
        default: return true
        }
    }

    /// El paso que sigue (el de «Trakt conectado» solo si se conectó).
    public func next(after step: Step) -> Step? {
        guard let i = Step.allCases.firstIndex(of: step), i + 1 < Step.allCases.count else { return nil }
        let following = Step.allCases[i + 1]
        if following == .traktDone, !settings.traktLinked { return .done }
        return following
    }

    /// Trakt quedó conectado: se trae lo tuyo y se cuenta para decirlo.
    public func traktLinked() async {
        await services.syncLibrary(force: true)
        let all = services.library.all
        brought = (all.reduce(0) { $0 + $1.seen.count }, all.filter(\.inList).count)
    }

    /// El nombre de la cuenta de Trakt conectada.
    public var traktName: String? { if case .linked(let name) = settings.trakt { return name }; return nil }

    /// Termina la guía (no se vuelve a enseñar sola).
    public func finish() { services.kv.set(Self.seenKey, data: Data("1".utf8)) }
}
