import SwiftUI

/// Los íconos de las listas, los mismos de la TV (orbital/web/js/core/icons.js, copiados al catálogo por
/// scripts/list_icons.mjs): trazo de Orbital y la luna de la marca como un punto que dice algo. Vectoriales y de plantilla:
/// toman el color del texto.
enum OrbitalIcon: String, CaseIterable {
    case spark, watching, library, bookmark, series, calendar, list, addon, trend, flame, chart, fresh, trophy

    /// Su nombre en el catálogo (para `Tab(_:image:)`).
    var asset: String { "Icons/" + rawValue }
    var image: Image { Image(asset) }

    /// Su color (`DS.ListTint`): el mismo en cada lugar donde sale.
    var tint: Color {
        switch self {
        case .watching: DS.ListTint.watching
        case .library: DS.ListTint.library
        case .bookmark: DS.ListTint.bookmark
        case .spark: DS.ListTint.spark
        case .calendar, .fresh: DS.ListTint.calendar
        case .series: DS.ListTint.series
        case .trend: DS.ListTint.trend
        case .flame: DS.ListTint.flame
        case .list: DS.ListTint.list
        case .addon: DS.ListTint.addon
        case .chart: DS.ListTint.chart
        case .trophy: DS.ListTint.trophy
        }
    }
}

/// Un ícono de lista junto a un título: solo el trazo, en su color (crece con Dynamic Type).
struct ListIcon: View {
    let icon: OrbitalIcon
    @ScaledMetric(relativeTo: .title3) private var side = DS.Size.listIcon

    var body: some View {
        icon.image.resizable().scaledToFit().frame(width: side, height: side)
            .foregroundStyle(icon.tint)
            .accessibilityHidden(true)
    }
}
