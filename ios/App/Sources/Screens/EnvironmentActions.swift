import SwiftUI

// Las acciones que la raíz de cada ventana pasa por el entorno (V9, revisión del 10 nov 2026). El entorno solo lleva datos
// (si existen, de qué ventana son); lo que hacen vive en `AppUI`. Con un cierre dentro, SwiftUI daba el valor por cambiado
// en cada pasada de la raíz (cada sondeo de la TV) aunque `==` dijera que era igual, y volvía a pintar Inicio entera
// (`-perf-why`: «_openRemote changed», 25 veces al abrir una ficha).

extension EnvironmentValues {
    /// Abre el control de tu Orbital (el botón de la barra de Inicio); nil sin tu Orbital conectada.
    @Entry var openRemote: RemoteOpener? = nil
}

/// El botón del control de Inicio: si abre como panel o como hoja, y de qué ventana es.
struct RemoteOpener: Equatable {
    /// Lo único que cambia lo que hace: si el control abre como panel o como hoja.
    let wide: Bool
    /// De qué ventana es (su acción, en `AppUI.remoteButtons`).
    let window: Int
    @MainActor func callAsFunction() { AppEnvironment.shared.ui.remoteButtons[window]?() }
}

extension TitlePanelOpener {
    /// Abre la ficha en el panel de la ventana que la pidió (iPad, Mac).
    @MainActor func callAsFunction(_ route: TitleRoute, from frame: CGRect? = nil) { AppEnvironment.shared.ui.titlePanels[window]?(route, frame) }
}
