import SwiftUI

/// DU1 · las barras en el iPhone Duo: en la pantalla de afuera (y en la de adentro acostada) iOS manda la barra de pestañas y la
/// de la hora a una franja al costado. `toolbarVerticalBehavior(.disabled)` (iOS 27.1) las regresa abajo y arriba, como en
/// cualquier iPhone. En los demás aparatos no hace nada. La decisión vive en `DuoBars.below`.
enum DuoBars {
    /// ¿Van las barras abajo y arriba (DU1-B)? Hasta que Fernando decida DU1, solo en Debug con `-demo-duo-bars-below`.
    static var below: Bool {
        #if DEBUG
        Demo.isOn && Demo.has("-demo-duo-bars-below")
        #else
        false
        #endif
    }
}

extension View {
    /// UIKit le pregunta la preferencia a lo que está hasta arriba de cada presentación (la ventana, cada hoja, cada pantalla
    /// completa), no a quien la abrió: la raíz (`TabBarFirst`), `appSheet` y cada `fullScreenCover` la declaran. Si una hoja no
    /// lo hace, con DU1-B regresa la franja del costado y deja un hueco de ~90 puntos a la derecha (27 nov 2026, el control
    /// de la TV en el Duo cerrado). Lo cuida `DesignRulesTests+Covers`.
    func duoBars() -> some View { duoBars(below: DuoBars.below) }

    @ViewBuilder func duoBars(below: Bool) -> some View {
        #if compiler(>=6.4)
        if below, #available(iOS 27.1, *) { toolbarVerticalBehavior(.disabled) } else { self }
        #else
        self   // el Xcode de la CI (26.3) no conoce la API: ahí no hay Duo
        #endif
    }
}
