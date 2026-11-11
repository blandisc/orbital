import SwiftUI

/// L1 (`VersionRowStyle.centered`) · la versión con los datos del título: bajo las calificaciones y al centro, justo arriba de
/// «Ver». Se lee como un dato más (la misma letra que la línea de datos), pero se nota que se toca: en el color del texto
/// principal y con su flechita hacia abajo, frente a los datos atenuados. Del alto de un dedo.
struct VersionRowCentered: View {
    let summary: VersionSummary
    /// A la izquierda (la ficha ancha del iPad y la Mac, donde los datos también van a la izquierda).
    var leading = false

    var body: some View {
        Button(action: summary.open) {
            HStack(spacing: DS.Space.s1) {
                summary.full.recipe(.label, color: DS.text).lineLimit(2).multilineTextAlignment(leading ? .leading : .center)
                Image(systemName: "chevron.down").font(DS.TextRecipe.caption.font).foregroundStyle(DS.textMuted)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, DS.Space.s3)
            .frame(minHeight: DS.Size.touchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .versionRowBehavior(summary)
        .frame(maxWidth: .infinity, alignment: leading ? .leading : .center)
        .padding(.horizontal, leading ? -DS.Space.s3 : 0)   // a la izquierda, la letra a ras de los datos (el aire es solo para el dedo)
    }
}
