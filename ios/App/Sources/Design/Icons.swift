import SwiftUI

/// Los íconos de las listas, los mismos de la TV (orbital/web/js/core/icons.js, copiados al catálogo por
/// scripts/list_icons.mjs): trazo de Orbital y la luna de la marca como un punto que dice algo. Vectoriales y de plantilla:
/// toman el color del texto.
enum OrbitalIcon: String, CaseIterable {
    case spark, watching, library, bookmark, series, calendar, list, addon, trend, flame, chart, fresh, trophy

    /// Su nombre en el catálogo (para `Tab(_:image:)`).
    var asset: String { "Icons/" + rawValue }
    var image: Image { Image(asset) }
}

/// Un ícono de lista junto a un título: del alto de la letra que lo acompaña (crece con Dynamic Type).
struct ListIcon: View {
    let icon: OrbitalIcon
    @ScaledMetric(relativeTo: .title3) private var side = DS.Size.listIcon

    var body: some View {
        icon.image.resizable().scaledToFit().frame(width: side, height: side).accessibilityHidden(true)
    }
}
