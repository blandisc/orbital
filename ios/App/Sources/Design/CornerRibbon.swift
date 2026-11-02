import SwiftUI

/// El listón de la esquina, aparte porque también lo usa el widget «Lo nuevo de lo tuyo» (la extensión no compila el resto
/// del catálogo). Con él va `dsCaps`, que el listón necesita.
extension View {
    /// La única manera de escribir en mayúsculas (rótulos, sellos, listones): el texto se escribe normal y se traduce normal.
    func dsCaps() -> some View { textCase(.uppercase) }
}

/// Lo que acaba de salir, en la esquina de arriba a la izquierda de un póster: un listón en diagonal que cruza la esquina,
/// verde con un brillo arriba y el texto en mayúsculas. Va en `.overlay(alignment: .topLeading)` del póster, sin padding:
/// la caja recorta la banda y su orilla de afuera queda lejos de la curva del póster. `compact`: el de los pósters chicos
/// del widget (50 pt de ancho), con su letra y su caja más chicas.
struct DSCornerRibbon: View {
    let text: LocalizedStringKey
    var compact = false

    var body: some View {
        let size = compact ? DS.Ribbon.compact : DS.Ribbon.regular
        Text(text).dsCaps().font(compact ? DS.font(.xs, weight: .bold) : DS.TextRecipe.badge.font).tracking(size.tracking)   // ds-exception: el compacto (pósters de 50 pt del widget) va un punto abajo de la placa o «Nuevo» no cabe en la esquina
            .foregroundStyle(DS.onSuccess).lineLimit(1)
            .padding(.vertical, DS.Space.s1 / 2)
            .frame(width: size.length)
            .background {
                DS.success.overlay(LinearGradient(colors: [DS.paper.opacity(DS.Ribbon.shine), .clear], startPoint: .top, endPoint: .center))
            }
            .overlay(alignment: .top) { Rectangle().fill(DS.paper.opacity(DS.Ribbon.shine)).frame(height: DS.Size.hairline) }
            .shadow(DS.Elevation.low)
            .rotationEffect(.degrees(DS.Ribbon.angle))
            .position(x: size.center, y: size.center)
            .frame(width: size.corner, height: size.corner)
            .clipped()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(text))
    }
}
