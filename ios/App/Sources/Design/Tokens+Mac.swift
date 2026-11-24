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
        /// Cuántos pósters lleva cada fila de Biblioteca (`LibraryHome`): el resto, en su pantalla completa.
        static let libraryRow = 30
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
        /// El título de arriba de cada pantalla (Mi media, Descargas, una lista): lo dibuja la barra del sistema, que no pasa por
        /// `DS.styled` ni por `systemType`, y salía de 13 px (Fernando, 22 nov 2026: «en Mi media el título se me hace muy
        /// pequeño… hacían sentido en el iPhone los tamaños, pero aquí ya no»). En la Mac, del estilo `barTitle` con la escala.
        static let barTitle: Font.TextStyle = .title2
        @MainActor static func styleBarTitles() {
            guard ProcessInfo.processInfo.isiOSAppOnMac else { return }
            let size = (styleSizes[barTitle] ?? bodySize) * typeScale
            let bar = UINavigationBar.appearance()
            bar.titleTextAttributes = [.font: UIFont.systemFont(ofSize: size, weight: .bold)]
            bar.largeTitleTextAttributes = [.font: UIFont.systemFont(ofSize: (styleSizes[.largeTitle] ?? size) * typeScale, weight: .bold)]
        }
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
        /// «Mejor resultado» en Buscar: en la Mac la ventana es tan ancha que con el alto del iPhone quedaba una franja delgada y
        /// el arte casi no se veía (24 nov 2026).
        static let searchTopHeight: CGFloat = 320
        /// Cuánto después de abrir la app se arman, escondidas, Biblioteca y Explorar (`MacTabDeck`), y cuánto entre una y otra:
        /// primero que Inicio se asiente; luego una a la vez, para no trabar lo que estés haciendo.
        static let tabPrepareDelay: Double = 4, tabPrepareGap: Double = 2.5
        /// El tinte del vidrio del renglón de arriba (`macTopGlass`): lo justo para que se lea sobre el fondo oscuro sin volverse
        /// una cápsula sólida.
        static let topGlassTint = DS.surfaceRaised.opacity(0.45)
        /// DK (Fernando, 22 nov 2026: «hacer el dock de arriba un poquito más grande»): las pestañas, «Buscar» y tu foto, un
        /// paso más grandes en la Mac y en el iPad ancho (la letra de un nombre en tarjeta y más aire arriba y abajo).
        /// Otro paso el 23 nov 2026 («arriba donde dice Orbital y el dock, un poquito más grande»): la letra de una subsección
        /// (antes la de un nombre en tarjeta), más aire y el logo `markScale` (antes crecía como la letra, 1.25).
        static let topBarText = TextRecipe.sectionQuiet
        static let topBarPadV = Space.s2 + Space.s1
        static let markScale: CGFloat = 1.45
        /// La lista de Ajustes (MA1), como Ajustes del Sistema: desde AJ-A (22 nov 2026) una barra lateral angosta, un renglón
        /// por página sin su valor; la página de la derecha llena lo demás hasta `settingsPageWidth`.
        static let settingsListWidth: CGFloat = 340, settingsPageWidth: CGFloat = 1200
        /// Entre grupos de una página de Ajustes en la Mac: con el espacio de iOS, la explicación de un grupo quedaba pegada al
        /// nombre del siguiente y no se sabía de cuál era (23 nov 2026). Con 300 de barra, «Conectado a Trakt, Real-De…» se cortaba.
        static let settingsSectionGap = Space.s8
        /// Ajustes y cada una de sus páginas, un paso de letra arriba del resto de la Mac (Fernando, 23 nov 2026: «asegúrate que
        /// ya hiciste esa pasada también en Settings y dentro de cada una subpantalla»): junto a Inicio, los renglones, la barra
        /// lateral y las explicaciones se veían de iPhone. El nombre de la página, de título (antes el de una sección).
        static let settingsType: DynamicTypeSize = .xxxLarge
        /// La letra de los renglones de Ajustes en la Mac: la de la Mac va a tamaño fijo (`DS.styled`), así que el paso de arriba
        /// solo lo toman los controles del sistema; los nombres van con la de `title3` (20 en vez de 17, por la escala).
        static let settingsBody: Font.TextStyle = .title3
        static let settingsPaneTitle = TextRecipe.title
        /// MC1: cuánto se quedan quietas las animaciones del sistema al cambiar de pestaña en la Mac (lo que dura su fundido).
        static let tabSwitchQuiet: Double = 0.4
        /// El campo de Buscar en la Mac (MS1): grande, no la rayita de la barra; desde BU-A (22 nov 2026), a lo ancho de la
        /// cuadrícula. Un paso más alto que las cápsulas de la barra y de las puertas, con la letra de un nombre en tarjeta
        /// (Fernando, 23 nov 2026: «se ven demasiado grandes los botones respecto a los otros»; con 88 y la letra de título
        /// pesaba más que todo lo demás de la pantalla).
        static let searchFieldHeight: CGFloat = 64
        static let searchFieldText = TextRecipe.section   // el campo de texto del sistema no crece con la letra de la Mac: con `cardTitle` salía más chica que la de las puertas
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
    /// lados crece con la ventana como la orilla de la ficha ancha (el 5 %, de 48 a 160 pt): con un número fijo todo arrancaba
    /// pegado a la izquierda y la derecha quedaba vacía. En el iPhone y el iPad angosto, 16 (`gutter`).
    static var wideGutter: CGFloat {
        #if WIDGET_EXTENSION
        return s4
        #else
        return min(wideGutterMax, max(s12, (WindowMetrics.column.width * wideGutterShare).rounded()))
        #endif
    }
    static let wideGutterShare: CGFloat = 0.05, wideGutterMax: CGFloat = 160
}

extension DS.Poster {
    /// Una cuadrícula de puestos (el Top de un género, los rankings de una plataforma): cada celda cabe el póster y su cifra.
    /// Con el mínimo de dos pósters lado a lado (`pairWideMin`), en la Mac la tarjeta se salía de su celda, empezaba antes del
    /// margen y tapaba la cifra de la de al lado (22 nov 2026).
    static var rankedWideMin: CGFloat { railWidth + rankDigitRoom }
    static let rankDigitRoom: CGFloat = 64
    /// C5: con espacio, las tiras cuentan columnas (de 5 a 10 pósters, de 3 a 6 tarjetas anchas) y llenan el renglón hasta la orilla.
    static let railColumns = 5...10, stillColumns = 3...6
    /// El ancho para que quepan las que tocan (cerca de `target`) más un pedazo de la siguiente (`peek`), entre las dos orillas.
    static func filling(target: CGFloat, columns: ClosedRange<Int>) -> CGFloat {
        let room = WindowMetrics.column.width - 2 * DS.Space.gutter - peek
        let fit = Int(((room + DS.Space.s2) / (target + DS.Space.s2)).rounded())
        let count = min(columns.upperBound, max(columns.lowerBound, fit))
        return ((room - CGFloat(count) * DS.Space.s2) / CGFloat(count)).rounded(.down)
    }
}
