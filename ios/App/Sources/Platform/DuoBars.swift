import SwiftUI

/// DU1 · las barras en el iPhone Duo: en la pantalla de afuera (y en la de adentro acostada) iOS manda la barra de pestañas y la
/// de la hora a una franja al costado. `toolbarVerticalBehavior(.disabled)` (iOS 27.1) las regresa abajo y arriba, como en
/// cualquier iPhone. En los demás aparatos no hace nada. Hasta que Fernando decida DU1, solo con `-demo-duo-bars-below`.
extension View {
    @ViewBuilder func duoBars(below: Bool) -> some View {
        #if compiler(>=6.4)
        if below, #available(iOS 27.1, *) { toolbarVerticalBehavior(.disabled) } else { self }
        #else
        self   // el Xcode de la CI (26.3) no conoce la API: ahí no hay Duo
        #endif
    }
}
