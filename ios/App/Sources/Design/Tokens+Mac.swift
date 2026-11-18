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
        /// La escala de letra de la Mac (sistema de tamaños, Fernando, 16 nov 2026: «haz esa misma revisión en cuanto a tamaños
        /// de fuente y todos los botones»). Arriba, los del iPhone; abajo se aprietan: en el iPhone una nota de 11 pt se lee a
        /// palmo, pero en la Mac, al 77 % y a medio metro, salía de 10 px. Así lo más chico de la app sale de ~12.5 px.
        static let styleSizes: [Font.TextStyle: CGFloat] = [
            .largeTitle: 34, .title: 28, .title2: 22, .title3: 20, .headline: 17, .body: 17, .callout: 16,
            .subheadline: 16, .footnote: 15, .caption: 14, .caption2: 13,
        ]
        /// El tamaño de la letra del sistema (la de los controles nativos, menús, formularios, títulos de la barra) en la Mac:
        /// lo que no pasa por `DS.styled` crece igual que lo que sí (17 → 21 pt, como `typeScale`). Lo pone `macDefaults()` en `RootView`.
        static let systemType: DynamicTypeSize = .xxLarge
        /// Los controles nativos (botones, selectores) en la Mac van un tamaño arriba: con el de iPad salían de 24–30 px.
        /// Toda la app pide su tamaño con `dsControlSize`, que pasa por aquí; los que no piden ninguno toman `controlDefault` (el que sale de pedir `.large`).
        static let controlDefault: ControlSize = .extraLarge
        static func control(_ size: ControlSize) -> ControlSize {
            guard ProcessInfo.processInfo.isiOSAppOnMac else { return size }
            switch size {
            case .mini: return .small
            case .small: return .regular
            case .regular: return .large
            default: return .extraLarge
            }
        }
        /// La portada de Inicio en la Mac (17 nov 2026, Fernando: «se sigue viendo la imagen demasiado grande, el icono muy pequeño,
        /// los botones muy pequeños»): a lo más esta parte del alto de la ventana, y su logo y sus botones crecen `heroScale` sobre
        /// la letra de la Mac. Antes el tope de proporción (`aspectWideMax`) la dejaba en ~67 % (y en el ultrawide, más alta que
        /// la ventana); sin él manda esta parte, con el arte a la derecha cuando hace falta (`HomeHero.sideFade`).
        static let heroHeightShare: CGFloat = 0.56, heroScale: CGFloat = 1.5
        /// El póster de una tira en la Mac: con 148 pt se veía de ~114.
        static let railWidth: CGFloat = 188
        /// Cuántos renglones de «Lo más popular hoy» lleva Buscar vacío en la Mac: los que caben a lo alto de la ventana bajo la
        /// búsqueda avanzada (`searchTop`), al menos `searchRowsMin` (con dos fijos quedaba vacío el tercio de abajo).
        static let searchRowsMin = 2, searchTop: CGFloat = 520, searchCaption: CGFloat = 52
        /// La sombra bajo la barra de la Mac: las pestañas se leen aunque pase un póster detrás (Explorar, 16 nov 2026).
        static let topScrim: CGFloat = 120
        /// La columna de la izquierda de la Biblioteca (MB1) y la lista de Ajustes (MA1), como Música y Ajustes del Sistema.
        static let sidebarWidth: CGFloat = 340, settingsListWidth: CGFloat = 560
        /// MC1: cuánto se quedan quietas las animaciones del sistema al cambiar de pestaña en la Mac (lo que dura su fundido).
        static let tabSwitchQuiet: Double = 0.4
        /// El campo de Buscar en la Mac (MS1): grande y al centro, no la rayita de la barra.
        static let searchFieldWidth: CGFloat = 1100, searchFieldHeight: CGFloat = 88
        /// Los seis mosaicos de la búsqueda avanzada en la Mac (MS1): con 76 pt de alto y 360 de ancho eran franjas que se
        /// leían como botones de formulario; así son mosaicos, con su dibujo grande (Fernando, 16 nov 2026).
        static let doorTileHeight: CGFloat = 150, doorArtHeight: CGFloat = 52
        /// RF2: las reseñas de la ficha en la Mac, en columnas a lo ancho (como la tele, no una tira angosta a la izquierda).
        static let reviewColumns = 3
        /// RP2: el póster bajo el puntero crece un poco y lleva el marco crema del foco de la TV.
        static let hoverScale: CGFloat = 1.05, hoverRing: CGFloat = 3
        /// Desde este ancho de póster salen ▶ y ＋ al pasar el puntero (los de un renglón, de 40 pt, solo llevan el marco).
        static let quickMinWidth: CGFloat = 120
        /// RN2: desde este ancho de ventana la cápsula de pestañas va al centro con sus nombres; más angosta, junto al logo y
        /// solo con íconos (con la letra de la Mac, las tres con nombre miden ~330 pt y se encimaban con el logo y tu foto).
        static let centeredTabsFrom: CGFloat = 980
        /// Más angosta que esto, la barra de arriba lleva solo el planeta, sin «orbital» (`AppMark`).
        static let markOnlyBelow: CGFloat = 760
        /// RB2: qué parte del alto de la ventana ocupa un aviso vacío (`DSEmptyState`) en la Mac: queda al centro de lo visible.
        static let emptyShare: CGFloat = 0.72
        /// RN2: el puntito de Biblioteca (algo bajando) en la cápsula de pestañas.
        static let tabBadge: CGFloat = 8
        /// Un control de tamaño fijo (los círculos del selector de tipo): en la Mac crece como la letra, si no su ícono lo llena.
        static func sized(_ points: CGFloat) -> CGFloat { ProcessInfo.processInfo.isiOSAppOnMac ? points * typeScale : points }
    }
}

// La orilla y las columnas de una ventana con espacio (Mac, iPad grande o acostado): aquí y no en Tokens.swift (su tope de
// líneas); la extensión de widgets compila los dos.
extension DS.Space {
    /// C2 (Fernando, 18 nov 2026: Inicio replanteado): en ventana con espacio (Mac, iPad grande o acostado) el margen de los
    /// lados crece con la ventana como la orilla de la ficha ancha (el 5 %, de 40 a 160 pt): con un número fijo todo arrancaba
    /// pegado a la izquierda y la derecha quedaba vacía. En el iPhone y el iPad angosto, 16 (`gutter`).
    static var wideGutter: CGFloat {
        #if WIDGET_EXTENSION
        return s4
        #else
        return min(wideGutterMax, max(s10, (WindowMetrics.column.width * wideGutterShare).rounded()))
        #endif
    }
    static let wideGutterShare: CGFloat = 0.05, wideGutterMax: CGFloat = 160
}

extension DS.Poster {
    /// C5: con espacio, las tiras cuentan columnas (de 5 a 10 pósters, de 3 a 6 tarjetas anchas) y llenan el renglón hasta la orilla.
    static let railColumns = 5...10, stillColumns = 3...6
    /// El ancho para que quepan las que tocan (cerca de `target`) más un pedazo de la siguiente (`peek`), entre las dos orillas.
    static func filling(target: CGFloat, columns: ClosedRange<Int>) -> CGFloat {
        let room = WindowMetrics.column.width - 2 * DS.Space.gutter - peek
        let fit = Int(((room + DS.Space.s3) / (target + DS.Space.s3)).rounded())
        let count = min(columns.upperBound, max(columns.lowerBound, fit))
        return ((room - CGFloat(count) * DS.Space.s3) / CGFloat(count)).rounded(.down)
    }
}
