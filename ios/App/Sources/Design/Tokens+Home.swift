import SwiftUI

/// Tokens del Inicio nuevo y de Para ti B (docs/producto/inicio-benchmark/): la portada, «Lo nuevo de lo tuyo», Canales, la
/// franja del tipo y las piezas de Para ti. Los del cielo, en Tokens+Sky.
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
        static let markLine: CGFloat = 2
        static let soonOpacity: Double = 0.62
        /// Dónde queda HOY al abrir (de 0 a 1 en el ancho): lo de antes a la izquierda y un poco de lo que viene.
        static let todayAnchor: CGFloat = 0.62
    }

    /// Canales: el ancho de cada canal, su logo, el velo, cada cuánto se recalcula, el acercamiento lento de la imagen del
    /// capítulo (el «cachito») y la hoja para elegir.
    enum HomeChannels {
        static let width: CGFloat = 268, addWidth: CGFloat = 150
        static let logoWidth: CGFloat = 96, logoHeight: CGFloat = 30
        static let veilStart: Double = 0.4
        static let tick: TimeInterval = 30
        static let drift: Double = 14, driftScale: CGFloat = 1.1
        static let driftAnimation = Animation.easeInOut(duration: drift)
        static let searchDelay: Duration = .milliseconds(350)
        static let gridColumns = 4, resultPoster: CGFloat = 44
    }

    /// Para ti B: los círculos del índice, la portada del mosaico (su muro inclinado y el velo) y la tarjeta de «¿Qué vemos hoy?».
    enum ParaTiB {
        /// El botón del mosaico sobre el muro de Para ti (blanco, redondo, abajo a la derecha).
        static let walkButton: CGFloat = 52
        static let coverHeight: CGFloat = 300, coverWall: CGFloat = 620, coverColumns = 6, coverPosters = 72, coverTilt: Double = -10
        static let coverClearAt: Double = 0.25, coverBaseVeil: Double = 0.8, coverBaseAt: Double = 0.6
        /// Cuánto sube el muro (hasta la orilla de la pantalla, detrás del título y la barra: sin corte) y cuánto baja bajo los
        /// círculos; qué tanto se ve hasta arriba y el velo que deja leer el título encima.
        static let coverBleedUp: CGFloat = 900, coverTitleZone: CGFloat = 260, coverBleedDown: CGFloat = 72, coverUnderBar: Double = 0.85, coverTitleVeil: Double = 0.55
        /// El vaivén del muro: un renglón sobre su diagonal, ida en 40 s y vuelta en otros 40; corre solo con la portada a la vista.
        static let coverDrift: CGFloat = 150, coverDriftX: CGFloat = 26, coverVisibleFrom: Double = 0.1
        static let coverDriftAnimation = Animation.easeInOut(duration: 40)
        static let deckPoster: CGFloat = 84, deckShift: CGFloat = 10, deckTurn: Double = 5, deckBehind: Double = 0.6
        /// Cuántos pósters lleva el abanico de «¿Qué vemos hoy?» (y cuántos de la portada se saltan para no repetirlos).
        static let matchFan = 3
        /// «La temporada»: el ancho de sus pósters y cuánto la tiñe su color. Un renglón de «Tuyo»: cuánto asoma cada póster.
        static let seasonPoster: CGFloat = 76, seasonGlow: Double = 0.35, rowShift: CGFloat = 14
    }
}
