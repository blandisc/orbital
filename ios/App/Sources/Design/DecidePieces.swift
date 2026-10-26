import SwiftUI
import OrbitalCore

// Piezas de «¿Qué vemos?»: el mosaico de un género o una época y el renglón de una lista (los filtros de la hoja son
// `DSCapsuleLabel`, las mismas cápsulas de toda la app).

/// Un género o una época en «Más filtros»: un mosaico con su imagen (generada con Grok Imagine, viene con la app: sale al
/// instante y sin red), un velo abajo y el nombre. Con carácter al elegir: el elegido crece un poco con rebote, se enciende un
/// anillo con brillo en el color de Orbital y su ✓; los demás se apagan un poco mientras haya algo elegido. Arriba a la
/// izquierda, cuántas opciones tiene. `era`: el nombre en grande al centro (las décadas).
struct DecideTile: View {
    let title: Text
    /// El nombre de la imagen en `Assets.xcassets/Decide`.
    let image: String
    let selected: Bool
    /// Hay otro elegido y este no: se apaga un poco (lo elegido resalta).
    var dimmed = false
    /// Cuántas opciones hay con eso (nil: aún no se sabe).
    var count: Int?
    let height: CGFloat
    var era = false
    let toggle: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
        Button(action: toggle) {
            ZStack(alignment: era ? .bottom : .bottomLeading) {
                // La imagen llena su celda y se recorta a ella (sin esto su ancho natural estiraba la columna y se encimaban).
                Color.clear.overlay {
                    Image(image).resizable().scaledToFill().accessibilityHidden(true)
                        .saturation(dimmed ? DS.Decide.dimSaturation : 1)
                        .scaleEffect(selected ? DS.Decide.artZoom : 1)   // la imagen se acerca un poco al elegir
                }
                .clipped()
                LinearGradient(colors: [.clear, selected ? DS.scrim : DS.scrimStrong], startPoint: .center, endPoint: .bottom)
                Group {
                    if era { title.font(DS.TextRecipe.title.font.weight(.black)).tracking(DS.Decide.eraTracking) }
                    else { title.font(DS.TextRecipe.footnote.font.weight(.heavy)) }
                }
                .foregroundStyle(DS.paper).lineLimit(1).minimumScaleFactor(DS.Size.statScale)
                .shadow(color: DS.scrimStrong, radius: DS.Decide.labelShadow)
                .padding(.horizontal, DS.Space.s2).padding(.bottom, DS.Space.s1)
            }
            .frame(minWidth: 0, maxWidth: .infinity).frame(height: height)   // ds-exception: mínimo 0 para que la imagen no estire la columna
            .clipShape(shape)
            .overlay(alignment: .topLeading) {
                if let count, !era || !selected {
                    Text(verbatim: "\(count)").font(DS.TextRecipe.caption.font.weight(.bold)).monospacedDigit()
                        .foregroundStyle(DS.paper)
                        .padding(.horizontal, DS.Space.s1)
                        .background(DS.badgeBackground, in: Capsule())
                        .padding(DS.Space.s1)
                        .contentTransition(.numericText())
                }
            }
            .overlay(shape.strokeBorder(selected ? DS.brandMoon : DS.hairline, lineWidth: selected ? DS.Decide.chosenStroke : DS.Size.hairline))
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill").font(DS.TextRecipe.secondary.font.weight(.bold))
                        .foregroundStyle(DS.backdropDeep, DS.brandMoon)
                        .padding(DS.Space.s1)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .shadow(color: selected ? DS.brandMoon.opacity(DS.Decide.glowOpacity) : .clear, radius: DS.Decide.glowRadius)
            .opacity(dimmed ? DS.Decide.otherOpacity : 1)
            .scaleEffect(selected ? DS.Decide.chosenScale : 1)
            .animation(DS.Motion.pop(reduceMotion), value: selected)
            .animation(DS.Motion.base(reduceMotion), value: dimmed)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: selected)
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
