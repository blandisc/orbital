import ActivityKit
import AppIntents
import Foundation

/// «Viendo en la TV»: lo que tu Orbital está reproduciendo, en la pantalla bloqueada y en la isla, con pausa y ±30 s. La barra
/// avanza sola (de la posición y la hora en que se supo), así no hace falta mandar un avance por segundo.
struct TVActivityAttributes: ActivityAttributes, Sendable {
    struct ContentState: Codable, Hashable, Sendable {
        var title: String
        /// «T1 · E4» o el canal en vivo; vacío en una película.
        var detail: String
        /// El póster ya reducido en el App Group.
        var poster: String?
        /// Dónde iba (segundos) y cuánto dura, medidos a la hora `measuredAt`.
        var position: Double
        var duration: Double
        var measuredAt: Date
        var paused: Bool
        /// TV en vivo: sin barra ni ±30 s.
        var live: Bool
        var language: String

        /// Las horas de inicio y fin del video si siguiera sin pausa: la barra y «termina a las…» salen de aquí.
        var start: Date { measuredAt.addingTimeInterval(-position) }
        var end: Date { start.addingTimeInterval(duration) }
        var fraction: Double { duration > 0 ? min(1, max(0, position / duration)) : 0 }
    }
}

/// Un botón de la actividad: pausa, sigue o ±30 s en la TV. Corre en la app (iOS la despierta en segundo plano), que se lo pide
/// a la consola y actualiza la actividad.
struct TVControlIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Control de la TV"
    static let isDiscoverable = false

    @Parameter(title: "Orden") var action: String

    init() {}
    init(action: String) { self.action = action }

    /// Lo pone la app al arrancar.
    @MainActor static var run: ((String) async -> Void)?

    @MainActor
    func perform() async throws -> some IntentResult {
        await Self.run?(action)
        return .result()
    }
}
