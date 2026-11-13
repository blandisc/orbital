import SwiftUI
import OrbitalCore
import OrbitalModels

// Piezas de «Decide por mí»: el mosaico de un género o una época, los tres carteles y el renglón de una lista (los filtros
// de la hoja son `DSFilterIcon`, en `Buttons.swift`).

/// Un género o una época en «Afinar»: un mosaico con su imagen (generada con Grok Imagine, viene con la app: sale al
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
    /// F13: sin nada que dejar (y sin estar puesto) no se toca: gris y apagado (nunca «Documental · 0» tocable).
    var enabled = true
    let toggle: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View { bodyContent.pointerHover(.lift).disabled(!enabled) }
    @ViewBuilder private var bodyContent: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
        Button(action: toggle) {
            ZStack(alignment: era ? .bottom : .bottomLeading) {
                // La imagen llena su celda y se recorta a ella (sin esto su ancho natural estiraba la columna y se encimaban).
                Color.clear.overlay {
                    Image(image).resizable().scaledToFill().accessibilityHidden(true)
                        .saturation(dimmed || !enabled ? DS.Decide.dimSaturation : 1)
                        .scaleEffect(selected ? DS.Decide.artZoom : 1)   // la imagen se acerca un poco al elegir
                }
                .clipped()
                ArtVeil(strength: selected ? .soft : .strong)
                Group {
                    if era { title.font(DS.TextRecipe.title.font).tracking(DS.Decide.eraTracking) }
                    else { title.font(DS.TextRecipe.label.font) }
                }
                .foregroundStyle(DS.paper).lineLimit(1).minimumScaleFactor(DS.Size.statScale)
                .shadow(DS.Elevation.low.color(DS.scrimStrong))
                .padding(.horizontal, DS.Space.s2).padding(.bottom, DS.Space.s1)
            }
            .frame(minWidth: 0, maxWidth: .infinity).frame(height: height)   // ds-exception: mínimo 0 para que la imagen no estire la columna
            .clipShape(shape)
            .overlay(alignment: .topLeading) {
                if let count, !era || !selected {
                    Text(verbatim: "\(count)").font(DS.TextRecipe.badge.font).monospacedDigit()
                        .foregroundStyle(DS.paper)
                        .padding(.horizontal, DS.Space.s1)
                        .background(DS.badgeBackground, in: Capsule())
                        .padding(DS.Space.s1)
                        .contentTransition(.numericText())
                }
            }
            .overlay(shape.strokeBorder(selected ? .clear : DS.hairline, lineWidth: DS.Stroke.hairline))
            .dsSelectionRing(selected, in: shape)   // lo elegido en el color del texto, nunca turquesa (D5)
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill").font(DS.TextRecipe.labelLarge.font)
                        .foregroundStyle(DS.bg, DS.text)
                        .padding(DS.Space.s1)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .glow(selected ? DS.text.opacity(DS.Decide.glowOpacity) : .clear)
            .opacity(dimmed || !enabled ? DS.Opacity.dimmed : 1)
            .scaleEffect(selected ? DS.Decide.chosenScale : 1)
            .animation(DS.Motion.pop(reduceMotion), value: selected)
            .animation(DS.Motion.base(reduceMotion), value: dimmed)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .dsFeedback(.selection, trigger: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Los carteles de «Tres que caben», un solo juego: cada uno mide un tercio del renglón aunque sean uno o dos, van centrados
/// (F4, 13 nov 2026: antes dos dejaban un hueco a la derecha y uno, dos huecos) y sobre la misma base (pulido de DE2).
struct DecideTrioLayout: Layout {
    var spacing: CGFloat = DS.Space.s3
    /// Tres lugares, como `DecideModel.trio` (aquí fijo: el Layout no vive en el actor principal).
    private let slots: CGFloat = 3

    private func slot(_ width: CGFloat) -> CGFloat { max(0, (width - spacing * (slots - 1)) / slots) }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        let w = slot(width)
        let height = subviews.map { $0.sizeThatFits(ProposedViewSize(width: w, height: nil)).height }.max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let w = slot(bounds.width)
        let used = w * CGFloat(subviews.count) + spacing * CGFloat(max(0, subviews.count - 1))
        var x = bounds.minX + (bounds.width - used) / 2
        for view in subviews {
            // Sobre la misma base: si un póster llega más bajo, no flota a media altura.
            view.place(at: CGPoint(x: x, y: bounds.maxY), anchor: .bottomLeading, proposal: ProposedViewSize(width: w, height: nil))
            x += w + spacing
        }
    }
}

/// Una lista en «De qué listas»: sus carteles apilados, el nombre, de dónde es y cuántos títulos tiene, y la marca de elegida.
struct DecideListRow: View {
    let name: String
    let detail: String
    let posters: [String]
    let selected: Bool
    let toggle: () -> Void

    var body: some View { bodyContent.pointerHover(.highlight) }
    @ViewBuilder private var bodyContent: some View {
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
                    Text(verbatim: name).recipe(.labelLarge, color: DS.text).lineLimit(1)
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
