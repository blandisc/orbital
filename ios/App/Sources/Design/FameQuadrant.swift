import SwiftUI
import OrbitalCore

/// «Qué tan conocida»: el cuadro fama × calificación, como cuadrantes (Fernando, 31 oct 2026: «más que cuatro botones,
/// cuadrantes»). Arriba lo bien calificado, a la derecha lo famoso; las cuatro esquinas van pegadas, con una rayita entre
/// ellas como ejes. La elegida se pinta en el verde de este filtro; tocarla otra vez la quita.
struct FameQuadrant: View {
    let selected: AdvancedFilter.Fame
    let pick: (AdvancedFilter.Fame) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            Label("Mejor calificada", systemImage: "arrow.up").recipe(.caption, color: DS.textMuted)
            Grid(horizontalSpacing: DS.Stroke.regular, verticalSpacing: DS.Stroke.regular) {
                GridRow {
                    cell(.gems, "sparkles", Text("Joyas ocultas"), Text("Muy buenas, poco vistas"))
                    cell(.classics, "crown", Text("Las de siempre"), Text("Muy buenas y famosas"))
                }
                GridRow {
                    cell(.niche, "eye.slash", Text("Para pocos"), Text("Rarezas y culto"))
                    cell(.blockbusters, "ticket", Text("Taquilleras"), Text("Las que llenaron salas"))
                }
            }
            .background(DS.hairline)   // la rayita entre cuadrantes: los ejes
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
            HStack {
                Text("Menos conocida").recipe(.caption, color: DS.textMuted)
                Spacer()
                HStack(spacing: DS.Space.s1) {
                    Text("Más famosa").recipe(.caption, color: DS.textMuted)
                    Image(systemName: "arrow.right").font(DS.TextRecipe.caption.font).foregroundStyle(DS.textMuted).accessibilityHidden(true)
                }
            }
        }
    }

    private func cell(_ fame: AdvancedFilter.Fame, _ symbol: String, _ title: Text, _ detail: Text) -> some View {
        let on = selected == fame
        return Button { pick(on ? .any : fame) } label: {
            VStack(spacing: DS.Space.s1) {
                Image(systemName: symbol).font(DS.TextRecipe.section.font).foregroundStyle(on ? DS.Filter.meadow : DS.textMuted)
                title.recipe(.label, color: DS.text).lineLimit(1).minimumScaleFactor(DS.Size.statScale)
                detail.recipe(.caption, color: DS.textMuted).lineLimit(1).minimumScaleFactor(DS.Size.statScale)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, DS.Space.s2).padding(.vertical, DS.Space.s3)
            .frame(maxWidth: .infinity, minHeight: DS.Filter.quadrantCell)
            .background(on ? DS.Filter.meadowFill : DS.surface)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dsFeedback(.selection, trigger: on)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("filter-fame-\(fame.rawValue)")
    }
}

/// El cuadro chiquito de «Fama»: cuatro esquinas, la elegida en su verde.
struct MiniQuadrant: View {
    let selected: AdvancedFilter.Fame
    var body: some View {
        Grid(horizontalSpacing: DS.Stroke.selected, verticalSpacing: DS.Stroke.selected) {
            GridRow { cell(.gems); cell(.classics) }
            GridRow { cell(.niche); cell(.blockbusters) }
        }
        .aspectRatio(DS.Poster.aspect * 2, contentMode: .fit)
    }
    private func cell(_ fame: AdvancedFilter.Fame) -> some View {
        RoundedRectangle(cornerRadius: DS.Radius.xs, style: .continuous).fill(selected == fame ? DS.Filter.meadow : DS.fillStrong)
    }
}
