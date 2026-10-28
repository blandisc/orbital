import AppIntents
import SwiftUI
import WidgetKit

/// «Un Simpson al azar» en el Centro de control (y en la pantalla bloqueada o el botón de Acción): abre Orbital en la tele
/// de Los Simpson, que elige un episodio de las temporadas de Ajustes. Vive en `Shared/` por lo mismo que el control
/// de tu Orbital (`RemoteControlButton`): el intent corre dentro de la app.
struct SimpsonsControlButton: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "mx.iracheta.orbital.simpsons") {
            ControlWidgetButton(action: OpenSimpsonsIntent()) {
                Label { Text("Un Simpson al azar") } icon: { Image("simpsons.donut") }   // la dona de Los Simpson (símbolo propio)
            }
        }
        .displayName("Un Simpson al azar")
        .description("Pone un episodio de Los Simpson al azar.")
    }
}

/// Abre Orbital en la ruleta de Los Simpson. Corre en la app (`openAppWhenRun`): la app le dice qué hacer al arrancar (`open`).
struct OpenSimpsonsIntent: AppIntent {
    static let title: LocalizedStringResource = "Un Simpson al azar"
    static let isDiscoverable = true
    static let openAppWhenRun = true
    /// Lo pone la app al arrancar (abre la ruleta); en la extensión no existe y no hace nada.
    @MainActor static var open: (() -> Void)?

    @MainActor
    func perform() async throws -> some IntentResult {
        Self.open?()
        return .result()
    }
}
