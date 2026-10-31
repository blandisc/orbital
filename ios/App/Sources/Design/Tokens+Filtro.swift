import SwiftUI

/// Los tokens del filtro avanzado y de «¿Cuándo la viste?» (aparte de Tokens+Screens para que ninguno pase de su tope).
extension DS {
    /// «¿Cuándo la viste?» (`WatchedWhenSheet`): el póster de arriba, el ancho del ícono de cada opción y su alto.
    enum Watched {
        static let poster: CGFloat = 64, icon: CGFloat = 28, row: CGFloat = 60
    }

    /// El filtro avanzado (`FilterTile`, `FilterChoice`, `FameQuadrant`, `YearRuler`): el alto de un filtro en el cajón y de
    /// una opción grande, el velo de lo elegido, los colores de cada filtro y el póster de resultados.
    enum Filter {
        static let tileHeight: CGFloat = 96, choiceHeight: CGFloat = 84, genreTile: CGFloat = 64, eraTile: CGFloat = 72
        /// La puerta A de Buscar (Fernando, 31 oct 2026): los mismos mosaicos del cajón en chiquito, tres por renglón.
        static let miniTileHeight: CGFloat = 70
        /// El dibujo arriba de cada mosaico (regla, logos, cuadro) en el cajón y en la puerta.
        static let artHeight: CGFloat = 30, miniArtHeight: CGFloat = 20
        /// La flechita del panel que se abre bajo su mosaico.
        static let notch: CGFloat = 14
        /// La regla de años: su alto, la ventana, las orillas que se arrastran y las rayitas (año, cada 5, cada 10).
        static let rulerHeight: CGFloat = 64, rulerWindow: CGFloat = 46, handleWidth: CGFloat = 12, handleHeight: CGFloat = 30
        static let tickYear: CGFloat = 8, tickFive: CGFloat = 14, tickDecade: CGFloat = 24, rulerBase: CGFloat = 16
        static let decadeButton: CGFloat = 40
        /// Qué tan lejos llega el brillo de la ventana de Época.
        static let glowRadius = DS.Glow.soft.radius
        /// El color de cada filtro (Fernando, 31 oct 2026, dirección A): solo en detalles (el ícono, un puntito cuando tiene
        /// algo y el control abierto); lo elegido sigue en blanco. Claros sobre oscuro y más intensos sobre el papel.
        static let coral = DS.adaptive(dark: "#ff7a6b", light: "#c9432f"), gold = DS.adaptive(dark: "#f4c24d", light: "#a86f00")
        static let lilac = DS.adaptive(dark: "#a99cff", light: "#5b4bd6"), mint = DS.adaptive(dark: "#7ee0a1", light: "#1f8a4c")
        static let rose = DS.adaptive(dark: "#ff8fb1", light: "#c43c6c"), sky = DS.adaptive(dark: "#7cc4ff", light: "#1f6fb8")
        /// El velo y el brillo dorados de la ventana de Época.
        static let goldFill = gold.opacity(0.16), goldGlow = gold.opacity(0.35)   // ds-exception: velo y brillo del dorado de la regla
        static let dot: CGFloat = 7
        /// Lo más angosto de la ventana de la regla chiquita (un año o dos se leen igual).
        static let miniWindow: CGFloat = 12, windowMin: CGFloat = 32
        /// «Qué tan conocida»: el alto de cada cuadrante y el velo rosa del elegido. Género: cuántos géneros caben en su mosaico.
        static let quadrantCell: CGFloat = 96, genreMosaicMax = 6
        static let roseFill = rose.opacity(0.2)   // ds-exception: el velo del cuadrante elegido, en el rosa de este filtro
        /// El logo de TMDB en el mosaico de Calificación (chico: el número manda).
        static let tmdbMark: CGFloat = 11
        /// Calificación: los atajos de un toque y el velo verde del elegido.
        static let ratingPresets: [Double] = [6, 7, 7.5, 8]
        static let mintFill = mint.opacity(0.18)   // ds-exception: el velo del atajo elegido, en el verde de Calificación
        /// La puerta de «Búsqueda avanzada» en Buscar: su círculo, su tinte azul y su orilla (otra cosa que buscar por nombre).
        static let doorIcon: CGFloat = 36
        static let doorFill = DS.orbitalBlue.opacity(0.1)   // ds-exception: el tinte de la búsqueda avanzada, apenas azul
        static let doorStroke = DS.orbitalBlue.opacity(0.35)   // ds-exception: su orilla, en el mismo azul
        /// Al cambiar de filtro: la pausa entre cerrar el de antes y abrir el nuevo, y cuándo se sube la lista para que se vea.
        static let switchPause: Duration = .milliseconds(180), revealAfter: Duration = .milliseconds(320)
        static let tickFaint = DS.text.opacity(0.22), tickMid = DS.text.opacity(0.36), tickStrong = DS.text.opacity(0.62)   // ds-exception: las rayitas de la regla, de tenue a firme
        /// Un premio (su estatuilla), un estudio (su logo) y una bandera en el cajón.
        static let awardIcon: CGFloat = 40, miniAwardIcon: CGFloat = 18, studioLogoHeight: CGFloat = 24, logoTile: CGFloat = 64
        /// Los cuadritos de lo filtrado arriba de los resultados.
        static let summarySquare: CGFloat = 64
        /// La hora de «Que acabe antes de las…»: de las 8 pm a las 3 am, en cuartos de hora.
        static let endsByRange: ClosedRange<Double> = 20...27, endsByStep = 0.25
        /// Lo elegido, en el color del texto (Fernando, 30 oct 2026: lo elegido siempre en blanco, nunca turquesa ni azul).
        static let selectedFill = DS.text.opacity(0.12)   // ds-exception: el velo de la selección (el texto al 12 %)
        static let resultWidth: CGFloat = 104
        /// Las pestañas de texto de `DSKindFilter(tabs:)`: la marca turquesa bajo la elegida.
        static let tabMark: CGFloat = 18, tabMarkHeight: CGFloat = 3
    }
}
