import SwiftUI

/// Tokens del Inicio nuevo (docs/producto/inicio-benchmark/): el selector de la barra y sus tiempos.
extension DS {
    /// La portada de Inicio: arte de borde a borde (pasa detrás de la barra) que se desliza entre títulos.
    enum HomeHero {
        /// Ancho entre alto del arte: casi un póster en el iPhone; más bajo en pantallas cortas (el SE) y apaisado en ventana
        /// ancha (iPad, Mac), donde un póster quedaría altísimo.
        static let aspect: CGFloat = 0.78, aspectShort: CGFloat = 1.25, shortScreen: CGFloat = 700, aspectWide: CGFloat = 1.9
        /// Cuánto se enciman «Seguir viendo» sobre el borde de abajo de la portada (se ve sin bajar).
        static let overlap: CGFloat = 44
    }

    enum HomeKind {
        /// Cuánto se queda a la vista el nombre del tipo elegido («Series») después de tocar su ícono en la barra.
        static let tipHold: Duration = .milliseconds(1100)
    }
}
