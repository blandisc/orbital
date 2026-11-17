import SwiftUI

/// El mini sistema de la Mac (MAC-A, 16 nov 2026): la letra y los tamaños propios de la app «Diseñada para iPad» en la Mac.
/// Regla en docs/ios-interfaz.md § «iPad y Mac: su propio tamaño».
extension DS {
    /// SF Pro en su estilo: en iPhone y iPad, con Dynamic Type; en la Mac (que no tiene Dynamic Type), al tamaño del estilo
    /// por `DS.Mac.typeScale`, porque macOS dibuja la app al 77 % y la letra salía de 13 (MAC-A, 16 nov 2026).
    static func styled(_ style: Font.TextStyle) -> Font {
        guard ProcessInfo.processInfo.isiOSAppOnMac else { return .system(style, design: .default) }
        return .system(size: (Mac.styleSizes[style] ?? Mac.bodySize) * Mac.typeScale, design: .default)
    }

    /// La Mac («Diseñada para iPad»): macOS dibuja la app al 77 % en ventana, así que la letra arranca más grande y los pósters
    /// de las tiras crecen (MAC-A, Fernando, 16 nov 2026: «los botones están muy pequeños»). iPhone y iPad no los usan.
    enum Mac {
        /// Cuánto crece la letra: con 1.25 el cuerpo de 17 pt sale de ~16 en pantalla en vez de 13.
        static let typeScale: CGFloat = 1.25
        /// Los tamaños de cada estilo del iPhone (letra «Grande», la de fábrica): en la Mac se parte de estos.
        static let bodySize: CGFloat = 17
        static let styleSizes: [Font.TextStyle: CGFloat] = [
            .largeTitle: 34, .title: 28, .title2: 22, .title3: 20, .headline: 17, .body: 17, .callout: 16,
            .subheadline: 15, .footnote: 13, .caption: 12, .caption2: 11,
        ]
        /// El póster de una tira en la Mac: con 148 pt se veía de ~114.
        static let railWidth: CGFloat = 188
        /// Cuántos renglones de «Lo más popular hoy» lleva Buscar vacío en la Mac: los que caben a lo alto de la ventana bajo la
        /// búsqueda avanzada (`searchTop`), al menos `searchRowsMin` (con dos fijos quedaba vacío el tercio de abajo).
        static let searchRowsMin = 2, searchTop: CGFloat = 340, searchCaption: CGFloat = 52
        /// La sombra bajo la barra de la Mac: las pestañas se leen aunque pase un póster detrás (Explorar, 16 nov 2026).
        static let topScrim: CGFloat = 120
        /// Un control de tamaño fijo (los círculos del selector de tipo): en la Mac crece como la letra, si no su ícono lo llena.
        static func sized(_ points: CGFloat) -> CGFloat { ProcessInfo.processInfo.isiOSAppOnMac ? points * typeScale : points }
    }
}
