import SwiftUI
import OrbitalCore
import OrbitalModels

/// Tres pósters en abanico, el primero al frente y los otros asomando girados detrás («Decide por mí», «La temporada»).
struct PosterFan: View {
    let posters: [String]
    let width: CGFloat
    /// Cuánto asoma cada póster de atrás (la puerta de «Decide por mí» lo lleva más junto: DM-A).
    var shift: CGFloat = DS.ParaTiB.deckShift

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Sin pósters (sin red), la forma del abanico en gris: la tarjeta no cambia de tamaño.
            ForEach(Array((posters.isEmpty ? Array(repeating: "", count: DS.ParaTiB.matchFan) : posters).prefix(DS.ParaTiB.matchFan).enumerated().reversed()), id: \.offset) { i, url in
                PosterView(url: url, title: "")
                    .frame(width: width)
                    .rotationEffect(.degrees(Double(i) * DS.ParaTiB.deckTurn))
                    .offset(x: CGFloat(i) * shift)
                    .opacity(i == 0 ? 1 : DS.ParaTiB.deckBehind)
            }
        }
        .frame(width: width + shift * CGFloat(DS.ParaTiB.matchFan - 1), alignment: .leading)
        .accessibilityHidden(true)
    }
}

/// Un renglón de «Tuyo» (Mi lista, Favoritos, Tus series y tus listas de Trakt): tres pósters encimados, el nombre, qué es y
/// cuántos tiene.
struct ListRow: View {
    let name: String
    let detail: Text
    let posters: [String]
    /// Una puerta grande (la de «Lo que ves» en la Mac y el iPad): pósters y nombre más grandes, más aire. Fernando, 22 nov 2026:
    /// «lo que ves, hazlo también más grande».
    var large = false

    var body: some View {
        let poster = large ? DS.ParaTiB.largePoster : DS.Collections.stackPoster
        let shift = large ? DS.ParaTiB.largeShift : DS.ParaTiB.rowShift
        HStack(spacing: large ? DS.Space.s6 : DS.Space.s2) {
            ZStack(alignment: .leading) {
                ForEach(Array(posters.prefix(DS.ParaTiB.matchFan).enumerated().reversed()), id: \.offset) { i, url in
                    PosterView(url: url, title: "").frame(width: poster)
                        .offset(x: CGFloat(i) * shift)
                        .shadow(DS.Elevation.low.drop(DS.Space.s1))
                }
            }
            .frame(width: poster + shift * CGFloat(DS.ParaTiB.matchFan - 1), alignment: .leading)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text(verbatim: name).recipe(large ? .title : .cardTitle).lineLimit(1)
                detail.recipe(large ? .body : .footnote, color: DS.textMuted).lineLimit(large ? 2 : 1)
            }
            Spacer(minLength: DS.Space.s2)
            Image(systemName: "chevron.right").font(DS.TextRecipe.label.font).foregroundStyle(DS.textFaint)
        }
        .padding(large ? DS.Space.s4 : DS.Space.s2)
        .padding(.trailing, DS.Space.s2)
        .dsCard()
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
