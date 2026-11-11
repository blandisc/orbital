import SwiftUI

/// L3 (`VersionRowStyle.split`) · «Ver» partido en dos: a la izquierda (la mayor) reproduce; a la derecha, más angosta, la
/// versión («🇲🇽 1080p ⌄») abre «Versión». Una sola forma con una división fina; cada lado es un botón nativo con su propia
/// pulsación (se hunde solo el que tocas). Si el nombre de «Ver» no cabe en un renglón (iPhone SE, letra grande), la derecha
/// se queda con la bandera y la flechita; el nombre de «Ver» nunca se corta.
struct SplitPlayButton<Title: View>: View {
    let title: Title
    let summary: VersionSummary
    let enabled: Bool
    let play: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(summary.compact)
            row(summary.mark)
        }
    }

    private func row(_ version: Text) -> some View {
        HStack(spacing: 0) {
            Button(action: play) { title.frame(maxHeight: .infinity) }
                .dsSolidPrimaryButton(shape: .roundedRectangle(radius: .zero)).disabled(!enabled)
                .accessibilityIdentifier("title-play")
                .coachAnchor("title-play")   // F3: el aviso con foco de la ficha señala este lado
            Button(action: summary.open) {
                HStack(spacing: DS.Space.s1) {
                    version.font(DS.TextRecipe.label.font).lineLimit(1)
                    Image(systemName: "chevron.down").font(DS.TextRecipe.caption.font).accessibilityHidden(true)
                }
                .fixedSize()
                .frame(minWidth: DS.Size.touchTarget, maxHeight: .infinity)
            }
            .dsSolidPrimaryButton(shape: .roundedRectangle(radius: .zero))
            .versionRowBehavior(summary)
            // La división: fina, del color de la letra del botón, sin tocar las orillas de arriba y abajo.
            .overlay(alignment: .leading) {
                Rectangle().fill(DS.onSolidPrimary.opacity(DS.Opacity.faint)).frame(width: DS.Stroke.regular).padding(.vertical, DS.Space.s3)
                    .accessibilityHidden(true)
            }
        }
        .fixedSize(horizontal: false, vertical: true)   // los dos lados, del mismo alto
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
    }
}
