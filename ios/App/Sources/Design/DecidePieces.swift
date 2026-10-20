import SwiftUI
import OrbitalCore

// Piezas de «¿Qué vemos?»: el mosaico de un género o una época y el renglón de una lista (los filtros de la hoja son
// `DSCapsuleLabel`, las mismas cápsulas de toda la app).

/// Un género o una época en «Más filtros»: un mosaico con el arte de una de tus sugerencias de eso, un velo abajo y el nombre;
/// elegido, con borde y ✓. Sin arte todavía, el fondo liso de las tarjetas. `centered`: el nombre al centro (las épocas).
struct DecideTile: View {
    let title: Text
    let art: String?
    let selected: Bool
    let height: CGFloat
    var centered = false
    let toggle: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
        Button(action: toggle) {
            ZStack(alignment: centered ? .bottom : .bottomLeading) {
                if let art { PosterView(url: art, title: "", aspect: nil, bleed: true, maxPoints: DS.Decide.tileArt) } else { DS.surfaceRaised }
                LinearGradient(colors: [.clear, DS.scrimStrong], startPoint: .center, endPoint: .bottom)
                title.font(DS.TextRecipe.footnote.font.weight(.bold)).foregroundStyle(DS.paper).lineLimit(1).minimumScaleFactor(DS.Size.statScale)
                    .padding(.horizontal, DS.Space.s2).padding(.bottom, DS.Space.s1)
            }
            .frame(maxWidth: .infinity).frame(height: height)
            .clipShape(shape)
            .overlay(shape.strokeBorder(selected ? DS.text : DS.hairline, lineWidth: selected ? DS.Decide.chosenStroke : DS.Size.hairline))
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill").font(DS.TextRecipe.secondary.font).foregroundStyle(DS.paper, DS.backdropDeep)
                        .padding(DS.Space.s1)
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

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
