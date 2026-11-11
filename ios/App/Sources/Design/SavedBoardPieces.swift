import SwiftUI
import OrbitalModels

/// Una tarjeta del tablero de Guardado (G2-A, Fernando, 9 nov 2026): el ícono del estado, cuántos hay, su nombre y unos
/// pósters de lo más reciente. El mismo ícono que el botón de estado de la ficha (`TitleView.statusSymbol`).
struct SavedStateTile: View {
    let symbol: String
    let title: Text
    let count: Int?
    let posters: [String]
    /// Una pila sin número (Historial): una línea que dice qué hay en vez de cuántos.
    var detail: Text? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: symbol).font(DS.TextRecipe.cardTitle.font).foregroundStyle(DS.text)
                Spacer(minLength: DS.Space.s2)
                if detail == nil {
                    Group { if let count { Text(count, format: .number) } else { Text(verbatim: "–") } }
                        .font(DS.TextRecipe.section.font.monospacedDigit()).foregroundStyle(DS.text)
                        .contentTransition(.numericText())
                }
            }
            title.recipe(.secondary, color: DS.text).lineLimit(1).minimumScaleFactor(DS.Size.statScale)
            if let detail { detail.recipe(.caption, color: DS.textMuted).lineLimit(2) }
            HStack(spacing: DS.Space.s1) {
                ForEach(Array(posters.prefix(DS.SavedBoard.miniPosters).enumerated()), id: \.offset) { _, url in
                    PosterView(url: url, title: "").frame(width: DS.SavedBoard.miniPoster)
                }
            }
            .frame(height: DS.SavedBoard.miniPoster / DS.Poster.aspect, alignment: .leading)
            .accessibilityHidden(true)
        }
        .padding(DS.Space.s3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)   // en una fila, todas del alto de la más alta
        .dsCard(translucent: true)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
