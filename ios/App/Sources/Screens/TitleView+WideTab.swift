import SwiftUI
import OrbitalCore
import OrbitalModels

/// Las pestañas bajo el arte de la ficha en el iPad y la Mac (FE1/FE2-B, como la TV).
enum WideTab: Hashable {
    case episodes, cast, similar, details

    var title: Text {
        switch self {
        case .episodes: Text("Episodios")
        case .cast: Text("Reparto y equipo")   // PA7-A: el mismo nombre que el iPhone y la TV
        case .similar: Text("Más como esto")
        case .details: Text("Detalles")
        }
    }

    var symbol: String {
        switch self {
        case .episodes: "list.and.film"
        case .cast: "person.2"
        case .similar: "square.stack"
        case .details: "info.circle"
        }
    }

    /// Solo las que tienen algo: Episodios en las series, Reparto y equipo y Más como esto si TMDB los trae; Detalles siempre.
    static func available(series: Bool, extras: TitleExtras?) -> [WideTab] {
        var tabs: [WideTab] = series ? [.episodes] : []
        if let extras, !(extras.crew + extras.cast).isEmpty { tabs.append(.cast) }
        if let extras, extras.collection != nil || !extras.recommendations.isEmpty { tabs.append(.similar) }
        return tabs + [.details]
    }
}

extension VerticalAlignment {
    private enum BandAnchor: AlignmentID { static func defaultValue(in d: ViewDimensions) -> CGFloat { d[.top] } }
    /// M2: la sinopsis de la banda se alinea con la orilla de arriba de «Ver».
    static let bandAnchor = VerticalAlignment(BandAnchor.self)
}
