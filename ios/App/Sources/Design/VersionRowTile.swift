import SwiftUI

/// L2 (`VersionRowStyle.tile`) · la versión como una tarjeta a todo lo ancho, de la familia de Guardar · Descargar · Tráiler:
/// su mismo fondo, su esquina y su orilla fina, con el mismo aire arriba y abajo (regla «Aire parejo»). A la izquierda lo
/// que va a sonar («🇲🇽 Latino · 1080p»); a la derecha «Cambiar» con su flechita, atenuado. Va justo encima de esas tarjetas
/// y a la misma distancia que hay entre ellas.
struct VersionRowTile: View {
    let summary: VersionSummary
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
        Button(action: summary.open) {
            // Con letra grande «Cambiar» baja bajo la versión: la versión entera manda.
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: DS.Space.s1))
                                                      : AnyLayout(HStackLayout(spacing: DS.Space.s3))
            layout {
                summary.full.recipe(.label, color: DS.text).lineLimit(2)
                if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
                HStack(spacing: DS.Space.s1) {
                    Text("Cambiar").recipe(.footnote, color: DS.textMuted)
                    Image(systemName: "chevron.forward").font(DS.TextRecipe.caption.font).foregroundStyle(DS.textMuted)
                }
                .fixedSize()
                .accessibilityHidden(true)
            }
            .padding(.horizontal, DS.Space.s4)
            .padding(.vertical, DS.Space.s3)
            .frame(maxWidth: .infinity, minHeight: DS.Size.touchTarget, alignment: .leading)
            .dsCard(translucent: true)
            .overlay(shape.strokeBorder(DS.hairline, lineWidth: DS.Size.hairline))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .versionRowBehavior(summary)
    }
}
