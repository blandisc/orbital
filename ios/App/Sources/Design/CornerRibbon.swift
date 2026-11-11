import SwiftUI

/// El puntito de «Nuevo», aparte porque también lo usa el widget «Lo nuevo de lo tuyo» (la extensión no compila el resto
/// del catálogo). Con él va `dsCaps` (la única forma de escribir en mayúsculas).
extension View {
    /// La única manera de escribir en mayúsculas (rótulos, sellos, listones): el texto se escribe normal y se traduce normal.
    func dsCaps() -> some View { textCase(.uppercase) }
}

/// «Nuevo» sobre un póster: el puntito turquesa del logo (`DS.fresh`) en la esquina de arriba a la izquierda, con un aro
/// oscuro para que se vea sobre cualquier arte. Antes era un listón en diagonal que tapaba el arte; la TV lo cambió el 11 nov
/// y el iPhone la sigue (revisión 2). VoiceOver dice la palabra («Nuevo»). Va en `.overlay(alignment: .topLeading)` del
/// póster. `compact`: el de los pósters chicos del widget (50 pt de ancho).
struct DSNewDot: View {
    let text: LocalizedStringKey
    var compact = false

    var body: some View {
        let size = compact ? DS.NewDot.compact : DS.NewDot.regular
        Circle().fill(DS.fresh)
            .frame(width: size, height: size)
            .overlay { Circle().strokeBorder(DS.backdropDeep.opacity(DS.NewDot.ring), lineWidth: DS.Stroke.regular) }
            .shadow(DS.Elevation.low)
            .padding(compact ? DS.Space.s1 : DS.Space.s2)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(text))
    }
}
