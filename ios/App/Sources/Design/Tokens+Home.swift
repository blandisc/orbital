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

    /// «Lo nuevo de lo tuyo»: el ancho de cada pieza, el renglón del día, la marca de hoy y lo apagado de lo que viene.
    enum HomeTimeline {
        static let width: CGFloat = 112, labelRow: CGFloat = 18, dot: CGFloat = 7
        static let markLine: CGFloat = 2, markPad: CGFloat = 3
        static let soonOpacity: Double = 0.62
        /// Dónde queda HOY al abrir (de 0 a 1 en el ancho): lo de antes a la izquierda y un poco de lo que viene.
        static let todayAnchor: CGFloat = 0.62
    }

    enum HomeKind {
        /// Cuánto se queda a la vista el nombre del tipo elegido («Series») después de tocar su ícono en la barra.
        static let tipHold: Duration = .milliseconds(1100)
    }
}
