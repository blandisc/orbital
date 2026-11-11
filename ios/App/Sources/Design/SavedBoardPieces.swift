import SwiftUI
import OrbitalModels

/// Una tarjeta del tablero de Guardado (G2-A, Fernando, 9 nov 2026): el ícono del estado, cuántos hay, su nombre y unos
/// pósters de lo más reciente. Las cinco pilas (también Historial) se arman igual: ícono y número, nombre y pósters, para que
/// en una fila midan lo mismo (10 nov 2026). El mismo ícono que el botón de estado de la ficha (`TitleView.statusSymbol`).
struct SavedStateTile: View {
    let symbol: String
    let title: Text
    let count: Int?
    let posters: [String]
    /// En lugar de los pósters, lo que distingue a la pila (Historial: cuándo fue la última vez). Revisión del 11 nov:
    /// Historial y Vistas enseñaban los mismos tres pósters.
    var detail: Text? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: symbol).font(DS.TextRecipe.cardTitle.font).foregroundStyle(DS.text)
                Spacer(minLength: DS.Space.s2)
                Group { if let count { Text(count, format: .number) } else { Text(verbatim: "–") } }
                    .font(DS.TextRecipe.section.font.monospacedDigit()).foregroundStyle(DS.text)
                    .contentTransition(.numericText())
            }
            title.recipe(.secondary, color: DS.text).lineLimit(1).minimumScaleFactor(DS.Size.statScale)
            if let detail {
                // Sin reservar el alto de los pósters (aire parejo, 11 nov): en el iPhone Historial va sola en su renglón y le
                // sobraban 20 pt abajo; en una fila (iPad, Mac) la pila ya se estira al alto de las demás.
                detail.recipe(.footnote, color: DS.textMuted).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
            } else { miniPosters }
        }
        .padding(DS.Space.s3)
        // En una fila, todas del mismo ancho y del alto de la más alta.
        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)   // ds-exception: sin `minWidth: 0` la pila de cuatro pósters salía más ancha
        .dsCard(translucent: true)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var miniPosters: some View {
            HStack(spacing: DS.Space.s1) {
                ForEach(Array(posters.prefix(DS.SavedBoard.miniPosters).enumerated()), id: \.offset) { _, url in
                    PosterView(url: url, title: "").frame(width: DS.SavedBoard.miniPoster)
                }
            }
            .frame(maxWidth: .infinity, minHeight: DS.SavedBoard.miniPoster / DS.Poster.aspect,
                   maxHeight: DS.SavedBoard.miniPoster / DS.Poster.aspect, alignment: .leading)
            .clipped()   // en una pila angosta los pósters que no caben se cortan, no la ensanchan
            .accessibilityHidden(true)
    }
}
