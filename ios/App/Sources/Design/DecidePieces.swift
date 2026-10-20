import SwiftUI
import OrbitalCore

// Piezas de «¿Qué vemos?»: el renglón de una lista (los filtros son `DSCapsuleLabel`, las mismas cápsulas de toda la app).

/// Una lista en «De qué listas»: sus carteles apilados, el nombre, de dónde es y cuántos títulos tiene, y la marca de elegida.
struct DecideListRow: View {
    let name: String
    let detail: String
    let posters: [String]
    let selected: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: DS.Space.s3) {
                ZStack(alignment: .leading) {
                    ForEach(Array(posters.prefix(2).enumerated().reversed()), id: \.offset) { index, poster in
                        PosterView(url: poster, title: "", maxPoints: DS.Decide.listPoster)
                            .frame(width: DS.Decide.listPoster * DS.Poster.aspect)
                            .offset(x: CGFloat(index) * DS.Space.s2)
                    }
                    if posters.isEmpty {
                        RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous).fill(DS.fill)
                            .frame(width: DS.Decide.listPoster * DS.Poster.aspect, height: DS.Decide.listPoster)
                    }
                }
                .frame(width: DS.Decide.listPoster, height: DS.Decide.listPoster, alignment: .leading)
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    Text(verbatim: name).recipe(.secondary, color: DS.text).fontWeight(.semibold).lineLimit(1)
                    if !detail.isEmpty { Text(verbatim: detail).recipe(.caption).lineLimit(1) }
                }
                Spacer(minLength: DS.Space.s2)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(DS.TextRecipe.section.font).foregroundStyle(selected ? DS.text : DS.textFaint)
            }
            .padding(.vertical, DS.Space.s1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
