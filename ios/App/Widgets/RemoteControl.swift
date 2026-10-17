import AppIntents
import OrbitalCore
import SwiftUI
import WidgetKit

/// El control de tu Orbital en el Centro de control (y en la pantalla bloqueada o el botón de Acción): abre la app con el
/// control completo, como el del Apple TV.
struct RemoteControlButton: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "mx.iracheta.orbital.remote") {
            ControlWidgetButton(action: OpenRemoteIntent()) {
                Label("Control de Orbital", image: "orbital.mark")   // la marca de Orbital (símbolo propio, como lo pide el Centro de control)
            }
        }
        .displayName("Control de Orbital")
        .description("Abre el control de tu Orbital.")
    }
}

/// Abre Orbital en el control.
struct OpenRemoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Abrir el control de Orbital"
    static let isDiscoverable = true

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(WidgetLink.remoteURL))
    }
}
