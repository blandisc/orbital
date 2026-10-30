import SwiftUI

/// Tokens del Inicio nuevo (docs/producto/inicio-benchmark/): el selector de la barra y sus tiempos.
extension DS {
    enum HomeKind {
        /// Cuánto se queda a la vista el nombre del tipo elegido («Series») después de tocar su ícono en la barra.
        static let tipHold: Duration = .milliseconds(1100)
    }
}
