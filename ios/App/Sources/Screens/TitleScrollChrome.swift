import SwiftUI
import OrbitalCore

/// Lo de la ficha que sigue al desplazamiento: lo que sube por debajo de la barra de arriba se desvanece (deja ver el fondo del
/// color del arte) en vez de chocar con el reloj y los botones, y, recogido el arte, el logo (o el nombre) sale en la barra.
/// Guarda el desplazamiento aquí y solo mientras importa (arriba, hasta que todo quedó recogido): así lo que se vuelve a
/// pintar en cada cuadro es esto, no la ficha entera.
struct TitleScrollChrome: ViewModifier {
    let topInset: CGFloat, heroHeight: CGFloat
    let logo: String?, title: String, buttons: Int
    @State private var scrolled: CGFloat = 0

    /// Desde aquí ya no cambia nada (todo desvanecido y el logo entero).
    private var settled: CGFloat { heroHeight * max(DS.TitleAction.fadeAt, DS.TitleAction.titleFrom + DS.TitleAction.titleSpan) }
    /// Qué tan desvanecido va lo de arriba (0 con el arte a la vista, 1 ya recogido).
    private var fade: Double { Double(min(1, max(0, scrolled / max(heroHeight * DS.TitleAction.fadeAt, 1)))) }

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, y in
                let kept = min(max(y, 0), settled).rounded()
                if kept != scrolled { scrolled = kept }
            }
            // Arriba del todo no hay desvanecido: el arte llega hasta la orilla.
            .mask {
                VStack(spacing: 0) {
                    // Toda la barra de arriba desvanecida (nada se trasluce detrás del nombre ni de los botones) y, debajo, la
                    // transición suave hacia el contenido.
                    let total = max(topInset + DS.TitleAction.topFade, 1), kept = 1 - fade
                    LinearGradient(stops: [.init(color: .black.opacity(kept), location: 0),
                                           .init(color: .black.opacity(kept), location: topInset / total),
                                           .init(color: .black, location: 1)], startPoint: .top, endPoint: .bottom)
                        .frame(height: total)
                    Color.black   // ds-exception: es una máscara, solo cuenta qué tan opaca es (no se ve el color)
                }
                .ignoresSafeArea()
            }
            // Se dibuja aquí y no como elemento de la barra (en la barra transparente de la ficha el sistema no lo enseñaba).
            .overlay(alignment: .top) {
                let shown = Double(min(1, max(0, (scrolled - heroHeight * DS.TitleAction.titleFrom) / max(heroHeight * DS.TitleAction.titleSpan, 1))))
                // Entre ‹ y la cápsula de botones (que es más ancha que ‹): el nombre a la izquierda, sin meterse debajo.
                BarLogo(url: logo, title: title)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, DS.TitleAction.barTitleLeading)
                    .padding(.trailing, DS.TitleAction.barGroupPadding + DS.TitleAction.barButton * CGFloat(buttons))
                    .frame(maxWidth: .infinity, minHeight: DS.Size.touchTarget, alignment: .leading)
                    .offset(y: -DS.Size.touchTarget - DS.Space.s2)
                    .opacity(shown)
                    .allowsHitTesting(false)
                    .accessibilityHidden(shown < 1)
            }
    }
}

/// El logo chico de la barra de la ficha (de alto fijo, sin pasarse de su espacio); sin logo, el nombre.
private struct BarLogo: View {
    let url: String?
    let title: String
    var body: some View {
        Group {
            if let u = url.flatMap(URL.init(string:)) {
                RemoteImage(url: u, maxPoints: DS.TitleAction.barLogo * 8) { phase in
                    if case .success(let image) = phase { image.resizable().scaledToFit() } else { name }
                }
            } else { name }
        }
        .frame(height: DS.TitleAction.barLogo, alignment: .leading)
        .accessibilityLabel(Text(verbatim: title))
    }
    private var name: some View { Text(verbatim: title).recipe(.labelLarge, color: DS.text).lineLimit(1).minimumScaleFactor(DS.Size.statScale) }
}
