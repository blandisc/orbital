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
        static let tileHeight: CGFloat = 96, choiceHeight: CGFloat = 84, genreTile: CGFloat = 64
        /// La puerta A de Buscar (Fernando, 31 oct 2026): los mismos mosaicos del cajón en chiquito, tres por renglón.
        static let miniTileHeight: CGFloat = 70
        /// Sin ningún filtro puesto, los mosaicos sin renglón de valor (Fernando, 2 nov 2026, K5): más bajos, en la puerta y
        /// en el cajón.
        static let miniTileCompact: CGFloat = 52, tileCompact: CGFloat = 76
        /// El dibujo arriba de cada mosaico (regla, logos, cuadro) en el cajón y en la puerta.
        static let artHeight: CGFloat = 30, miniArtHeight: CGFloat = 20
        /// La flechita del panel que se abre bajo su mosaico.
        static let notch: CGFloat = 14
        /// La regla de años: su alto, la ventana, las orillas que se arrastran y las rayitas (año, cada 5, cada 10).
        static let rulerHeight: CGFloat = 64, rulerWindow: CGFloat = 46, handleWidth: CGFloat = 12, handleHeight: CGFloat = 30
        static let tickYear: CGFloat = 8, tickFive: CGFloat = 14, tickDecade: CGFloat = 24, rulerBase: CGFloat = 16
        static let decadeButton: CGFloat = 40
        /// El color de cada filtro (Fernando, 31 oct 2026, dirección A; el arcoíris, 2 nov): solo en detalles (el ícono, un puntito
        /// cuando tiene algo y el control abierto); lo elegido sigue en blanco. Son el arcoíris del azul de Orbital
        /// (`design/tokens.json` › rainbow: oklch 0.804 0.11 girado), los mismos de la TV; sobre el papel, oklch 0.52 0.12 (4.5:1).
        static let coral = DS.adaptive(dark: "#fea39b", light: "#a34945"), amber = DS.adaptive(dark: "#f0b070", light: "#975800")
        static let lime = DS.adaptive(dark: "#c3c56f", light: "#6e6e00"), meadow = DS.adaptive(dark: "#8ad399", light: "#287c42")
        static let sky = DS.adaptive(dark: "#66cef4", light: "#00769c"), lavender = DS.adaptive(dark: "#a3bcff", light: "#4e63ae")
        /// El velo y el brillo ámbar de la ventana de Época.
        static let amberFill = amber.opacity(0.16), amberGlow = amber.opacity(0.35)   // ds-exception: velo y brillo del ámbar de la regla
        static let dot: CGFloat = 7
        /// Lo más angosto de la ventana de la regla chiquita (un año o dos se leen igual).
        static let miniWindow: CGFloat = 12, windowMin: CGFloat = 32
        /// «Fama»: el alto de cada cuadrante y el velo verde del elegido. Género: cuántos géneros caben en su mosaico.
        static let quadrantCell: CGFloat = 96, genreMosaicMax = 6
        static let meadowFill = meadow.opacity(0.2)   // ds-exception: el velo del cuadrante elegido, en el verde de este filtro
        /// El logo de TMDB en el mosaico de Calificación (chico: el número manda).
        static let tmdbMark: CGFloat = 11
        /// Calificación: el velo lima del nivel elegido (los niveles, en `RatingLevels`).
        static let limeFill = lime.opacity(0.18)   // ds-exception: el velo del atajo elegido, en el lima de Calificación
        /// Los deslizadores de Calificación (`RatingRulerSlider`, `RatingStarSlider`): el alto de la regla, dónde va su línea (y su
        /// grosor), dónde empiezan las rayitas y sus números, la perilla, y el tamaño de cada estrella y su hueco.
        static let ratingRuler: CGFloat = 60, trackY: CGFloat = 18, track: CGFloat = 4, tickY: CGFloat = 32, rulerNumberY: CGFloat = 50
        static let thumbWidth: CGFloat = 44, thumbHeight: CGFloat = 26, star: CGFloat = 40
        static let starGap = DS.Space.s2
        /// La puerta de «Búsqueda avanzada» en Buscar: el círculo de su ícono.
        static let doorIcon: CGFloat = 36
        /// Al cambiar de filtro: la pausa entre cerrar el de antes y abrir el nuevo, y cuándo se sube la lista para que se vea.
        static let switchPause: Duration = .milliseconds(180), revealAfter: Duration = .milliseconds(320)
        static let tickFaint = DS.text.opacity(0.22), tickMid = DS.text.opacity(0.36), tickStrong = DS.text.opacity(0.62)   // ds-exception: las rayitas de la regla, de tenue a firme
        /// Un premio (su estatuilla), un estudio (su logo) y una bandera en el cajón.
        static let awardIcon: CGFloat = 40, studioLogoHeight: CGFloat = 24, logoTile: CGFloat = 64
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
