import SwiftUI

/// La franja bajo la barra de Inicio: Todo · Películas · Series en tres íconos al centro (filtra toda la página) y, a la
/// derecha, la puerta del filtro avanzado. En la barra no caben junto al logotipo y sus botones (iOS los mandaba a un «…»).
/// Al cambiar el tipo, su nombre aparece un momento debajo: los íconos solos se entienden menos que una palabra.
struct HomeKindBar: View {
    /// "" es todo, «movie» o «series».
    @Binding var kind: String
    let onFilters: () -> Void
    @State private var tip: LocalizedStringKey?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        DSKindFilter(kind: Binding(get: { kind }, set: { new in
            kind = new
            tip = switch new { case "movie": "Películas"; case "series": "Series"; default: "Todo" }   // solo si lo cambiaste tú
        }), icons: true)
        .accessibilityIdentifier("home-kind-filter")
        .frame(maxWidth: .infinity)
        .overlay(alignment: .trailing) {
            Button(action: onFilters) { Image(systemName: "slider.horizontal.3") }
                .buttonStyle(.glass).buttonBorderShape(.circle)
                .accessibilityLabel(Text("Filtros de búsqueda"))
                .accessibilityIdentifier("home-filters")
        }
        .overlay(alignment: .bottom) {
            if let tip {
                DSCapsuleLabel(title: Text(tip), symbol: KindGlyph.symbol(kind), selected: true)
                    .alignmentGuide(.bottom) { $0[.top] - DS.Space.s2 }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .accessibilityHidden(true)
            }
        }
        .animation(DS.Motion.enter(reduceMotion), value: tip != nil)
        .task(id: kind) {
            guard tip != nil else { return }
            try? await Task.sleep(for: DS.HomeKind.tipHold)
            tip = nil
        }
        .padding(.horizontal, DS.Space.gutter)
        .padding(.bottom, DS.Space.s2)
    }
}
