import SwiftUI
import UIKit

/// C1 (Fernando, 18 nov 2026): en el iPad con espacio, una sola barra arriba, como en la Mac: el logo, «Buscar», las
/// pestañas al centro, «Todo ▾» y tu foto en el mismo renglón (antes, la barra de pestañas del sistema y debajo otra con el
/// logo, ~70 pt menos de arte). Angosto (Split View, Slide Over), la barra del sistema de siempre.
@MainActor enum TopRow {
    /// En el iPad (no la Mac ni el iPhone): aquí, en Platform/, el único lugar que pregunta por el aparato.
    static let isPad = UIDevice.current.userInterfaceIdiom == .pad
    static var tabsInLogoRow: Bool {
        ThisDevice.isMac || (isPad && WindowMetrics.size.width >= DS.HomeHero.wideFrom)   // ds-exception: la barra la decide la ventana (con el control abierto sigue siendo la misma)
    }
}

