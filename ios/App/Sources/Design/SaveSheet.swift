import SwiftUI
import OrbitalModels

/// El nombre de la lista fija de «Guardar»: «Mi lista» (vive en el teléfono y es tu watchlist de Trakt). Lo comparten el menú
/// de «Guardar» de la ficha y la hoja «Guardar en…».
struct SaveDestinationName: View {
    let destination: SaveDestination

    var body: some View { Self.text(destination) }

    static func text(_ destination: SaveDestination) -> Text { Text("Mi lista") }

    static func symbol(_ destination: SaveDestination) -> String { "bookmark" }

    static func tint(_ destination: SaveDestination) -> Color { DS.ListTint.bookmark }
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
