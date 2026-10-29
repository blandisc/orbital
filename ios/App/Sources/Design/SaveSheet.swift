import SwiftUI
import OrbitalModels

/// El nombre de una de las listas fijas de «Guardar» con su servicio en gris: «Tu watchlist (Trakt)», «Mi lista (Stremio)».
/// Lo comparten el menú de «Guardar» de la ficha y la hoja «Guardar en…».
struct SaveDestinationName: View {
    let destination: SaveDestination

    var body: some View { Self.text(destination) }

    static func text(_ destination: SaveDestination) -> Text {
        switch destination {
        case .traktWatchlist: Text("\(Text("Tu watchlist"))\(Text(verbatim: " (Trakt)").foregroundStyle(DS.textMuted))")
        case .stremioLibrary: Text("\(Text("Mi lista"))\(Text(verbatim: " (Stremio)").foregroundStyle(DS.textMuted))")
        }
    }

    static func symbol(_ destination: SaveDestination) -> String {
        destination == .traktWatchlist ? "bookmark" : "rectangle.stack"
    }

    static func tint(_ destination: SaveDestination) -> Color {
        destination == .traktWatchlist ? DS.ListTint.bookmark : DS.ListTint.library
    }
}

/// El lugar de una lista que todavía no llega: el mismo `CheckRow` (mismo alto, mismo relleno) en modo de marcador, sin
/// interacción. Así, al llegar las listas, cada renglón cambia en su lugar y nada se recorre.
struct CheckRowSkeleton: View {
    var body: some View {
        CheckRow(title: Text(verbatim: "Lista de Trakt"), symbol: "list.bullet", color: DS.textFaint, checked: false) {}
            .redacted(reason: .placeholder)
            .disabled(true)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
