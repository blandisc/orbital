import SwiftUI
import OrbitalCore

/// Lo de la ficha que sigue al desplazamiento: lo que sube por debajo de la barra de arriba se desvanece despacio (deja ver el
/// fondo que de verdad hay detrás, sin franja con orilla; `DS.TitleAction.topFade`) en vez de chocar con el reloj y los botones, y, recogido el arte, el logo (o el nombre) sale en la barra.
/// Guarda el desplazamiento aquí y solo mientras importa (arriba, hasta que todo quedó recogido): así lo que se vuelve a
/// pintar en cada cuadro es esto, no la ficha entera.
struct TitleScrollChrome: ViewModifier {
    let topInset: CGFloat, heroHeight: CGFloat
    let logo: String?, title: String, buttons: Int
    @State private var scrolled: CGFloat = 0
    /// I11 · lo que ocupan ‹ y cada botón de la cápsula crece con la letra (como los botones de verdad), hasta `barGrowth`.
    @ScaledMetric(relativeTo: .body) private var scaledButton = DS.TitleAction.barButton
    private var growth: CGFloat { min(DS.TitleAction.barGrowth, max(1, scaledButton / DS.TitleAction.barButton)) }

    /// Desde aquí ya no cambia nada (todo desvanecido y el logo entero).
    private var settled: CGFloat { heroHeight * max(DS.TitleAction.fadeAt, DS.TitleAction.titleFrom + DS.TitleAction.titleSpan) }
    @Environment(\.colorScheme) private var scheme
    /// Qué tan desvanecido va lo de arriba (0 con el arte a la vista, 1 ya recogido). En claro el arte es una tarjeta que empieza
    /// bajo la barra: lo de la barra se apaga en cuanto algo llega ahí (`topFade`), y no poco a poco con todo el arte (la tarjeta
    /// se quedaba a medias detrás de la barra, un rectángulo gris pálido; AR1, 13 nov 2026).
    private var fade: Double {
        let span = scheme == .light ? DS.TitleAction.topFade : heroHeight * DS.TitleAction.fadeAt
        return Double(min(1, max(0, scrolled / max(span, 1))))
    }

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
                    .padding(.leading, DS.TitleAction.barTitleLeading * growth)
                    .padding(.trailing, DS.TitleAction.barGroupPadding + DS.TitleAction.barButton * growth * CGFloat(buttons) + DS.TitleAction.barLogoGap)
                    .frame(maxWidth: .infinity, minHeight: DS.Size.touchTarget, alignment: .leading)
                    .offset(y: -DS.Size.touchTarget - DS.Space.s2)
                    .opacity(shown)
                    .allowsHitTesting(false)
                    .accessibilityHidden(shown < 1)
            }
    }
}

/// Al abrir una ficha, el arte crece con el zoom desde el póster y lo de abajo (datos, botones, sinopsis) sube un poco con un
/// fundido, un instante después: se lee como una tarjeta que se abre y no como una pantalla que aparece de golpe. Una vez
/// (regresar de una persona o de la saga no lo repite). Con «Reducir movimiento», solo el fundido.
struct TitleEntrance: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : DS.Space.s5)
            .onAppear {
                guard !shown else { return }
                withAnimation((DS.Motion.smooth(reduceMotion) ?? DS.Motion.fade).delay(DesignTokens.Motion.base / 2)) { shown = true }
            }
    }
}

/// El logo chico de la barra de la ficha; sin logo, el nombre. Va recortado de su margen transparente (los de metahub traen
/// ~25 % vacío arriba y abajo) y cabe entero en su lugar: uno ancho se ajusta al espacio entre ‹ y los botones y uno alto
/// al alto de la barra, sin cortarse ni quedar diminuto. Un logo oscuro se pinta claro (si no, no se lee sobre el arte). En
/// claro, sobre el papel, un logo oscuro o de color va tal cual y uno pálido cede su lugar al nombre en el color del texto
/// («INTERSTELLAR» blanco no se leía y pintado de oscuro su brillo lo tapaba; AR1, 13 nov 2026).
private struct BarLogo: View {
    let url: String?
    let title: String
    @Environment(\.colorScheme) private var scheme
    @State private var trimmed: UIImage?
    @State private var failed = false
    @State private var dark = false
    @State private var pale = false

    var body: some View {
        Group {
            if let u = url.flatMap(URL.init(string:)) {
                Group {
                    if scheme == .light, pale { name }
                    else if let trimmed { Image(uiImage: trimmed).resizable().scaledToFit().brightness(dark && scheme != .light ? 1 : 0) }
                    else if failed { name }
                    else { Color.clear }
                }
                .task(id: u) {
                    trimmed = LogoTrim.cached(u)
                    if trimmed == nil { if let found = await LogoTrim.load(u) { trimmed = found } else { failed = true } }
                    dark = await LogoTone.isDark(u)
                    pale = await LogoTone.isPale(u)
                }
            } else { name }
        }
        .frame(maxWidth: .infinity, maxHeight: DS.TitleAction.barLogo, alignment: .leading)
        .frame(height: DS.TitleAction.barLogo)
        .accessibilityLabel(Text(verbatim: title))
    }
    private var name: some View { Text(verbatim: title).recipe(.labelLarge, color: DS.text).lineLimit(1).minimumScaleFactor(DS.Size.statScale) }
}
