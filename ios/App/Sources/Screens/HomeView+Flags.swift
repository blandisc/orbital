import SwiftUI

// Lo que Inicio decide una vez por aparato o sistema (salió de `HomeView.swift` el 27 nov 2026, por su tope de líneas).
extension HomeView {
    /// En la Mac Inicio se arma entero (26 nov 2026): la baraja de pestañas ya lo tiene armado y escondido, y perezoso armaba
    /// cada fila al entrar deslizando (128 ms atrasados por segundo al bajar; entero, 27–48). En el iPhone y el iPad, perezoso.
    static var lazyPage: Bool {
        #if MAC_DRIVE
        if MacDrive.lazy { return true }
        #endif
        return !ThisDevice.isMac
    }

    /// La barra de pestañas trae su accesorio (lo que suena en la TV) desde iOS 26.1.
    static var hasTabAccessory: Bool { if #available(iOS 26.1, *) { true } else { false } }
}
