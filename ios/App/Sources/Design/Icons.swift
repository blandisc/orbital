import SwiftUI

/// Los íconos propios de Orbital (los mismos de la TV: orbital/web/js/core/icons.js, copiados al catálogo por
/// scripts/list_icons.mjs). Regla de íconos del iPhone: las secciones no llevan ícono (el color lo pone el arte); los
/// renglones de ajustes usan símbolos del sistema en su color; los controles, símbolos del sistema en blanco. Los propios
/// quedan solo como marca (la pestaña «Para ti»).
enum OrbitalIcon: String, CaseIterable {
    case spark, watching, library, bookmark, series, calendar, list, addon, trend, flame, chart, fresh, trophy

    /// Su nombre en el catálogo (para `Tab(_:image:)`).
    var asset: String { "Icons/" + rawValue }
}
