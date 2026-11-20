import SwiftUI
import OrbitalCore

/// La receta de la ficha ancha (escenario y banda M2), aparte de `Tokens+Screens.swift` para que no pase su tope de líneas.
extension DS.TitleAction {
    /// La receta de la ficha ancha (iPad, Mac; Fernando, 17 nov 2026: «replantea con una receta»), ver `WideStage`.
    static let stageAspect: CGFloat = 2.4, portraitBelow: CGFloat = 1.15, stageMarginShare: CGFloat = 0.05, stageEdgeFade: CGFloat = 0.12
    /// Los lados del escenario (`StageSides`): difuminados y oscurecidos a la mitad; con el velo de siempre (~90 %) se
    /// veían como barras negras con un corte (revisión del 17 nov 2026).
    static let stageSideBlur: CGFloat = 50, stageSideDim: Double = 0.3
    /// El margen tope de la columna y cuánto crecen columna y logo con un escenario grande (desde `stageGrowFrom`, hasta
    /// `stageGrowMax`): en 2580 pt la columna era una cuarta parte de la pantalla, con el logo casi ilegible.
    static let stageMarginMax: CGFloat = 160, stageGrowFrom: CGFloat = 1440, stageGrowMax: CGFloat = 1.5
    /// M2 (Fernando, 18 nov 2026: «vamos de acuerdo a tu sugerencia… considera iPad acostado»): desde este ancho de
    /// ventana (Mac, iPad acostado), la banda a dos columnas: lo que se hace a la izquierda, la sinopsis a la derecha. El
    /// arte baja a `bandHeroShare` para que la primera fila se asome; la sinopsis a un ancho de lectura y hasta
    /// `bandSynopsisLines` renglones.
    static let bandFrom: CGFloat = 1100, bandHeroShare: CGFloat = 0.72, bandSynopsisLines = 4
    static var bandGap: CGFloat { DS.Mac.sized(DS.Space.s16) }
    /// La sinopsis de la banda: de 360 a 640 pt (~75 letras por renglón; en 2580 pt llegaba a 1000 y se leía mal).
    static let bandReading: CGFloat = 640, bandSynopsisMin: CGFloat = 360
}
