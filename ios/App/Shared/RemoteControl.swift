import AppIntents
import SwiftUI
import WidgetKit

/// El control de tu Orbital en el Centro de control (y en la pantalla bloqueada o el botón de Acción): abre la app con el
/// control completo, como el del Apple TV. Vive en `Shared/` (la app y la extensión): iOS ejecuta el intent dentro de la
/// app, y si solo la extensión lo conoce el control sale en blanco y tocarlo no hace nada (antes devolvía un enlace
/// `orbital-ios://remote`, que en un iPhone de verdad no abría nada).
struct RemoteControlButton: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "mx.iracheta.orbital.remote") {
            ControlWidgetButton(action: OpenRemoteIntent()) {
                Label { Text("Control de Orbital") } icon: { Image("orbital.mark") }   // la marca de Orbital (símbolo propio)
            }
        }
        .displayName("Control de Orbital")
        .description("Abre el control de tu Orbital.")
    }
}

/// Abre Orbital en el control. Corre en la app (`openAppWhenRun`): la app le dice qué hacer al arrancar (`open`).
struct OpenRemoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Abrir el control de Orbital"
    static let isDiscoverable = true
    static let openAppWhenRun = true
    /// Lo pone la app al arrancar (abre el control); en la extensión no existe y no hace nada.
    @MainActor static var open: (() -> Void)?

    @MainActor
    func perform() async throws -> some IntentResult {
        Self.open?()
        return .result()
    }
}
