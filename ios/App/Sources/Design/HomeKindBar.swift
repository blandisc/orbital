import SwiftUI

/// La franja bajo la barra de Inicio: Todo · Películas · Series en tres íconos al centro (filtra toda la página) y, a la
/// derecha, la puerta del filtro avanzado. En la barra no caben junto al logotipo y sus botones (iOS los mandaba a un «…»).
/// Al cambiar el tipo, su nombre sale un momento en el aviso de abajo (`onPicked`): los íconos solos se entienden menos que
/// una palabra, y debajo de la franja tapaba el botón de la portada.
struct HomeKindBar: View {
    /// "" es todo, «movie» o «series».
    @Binding var kind: String
    let onFilters: () -> Void
    /// Solo cuando lo cambias tú: el nombre del tipo elegido.
    let onPicked: (String) -> Void

    var body: some View {
        DSKindFilter(kind: Binding(get: { kind }, set: { new in
            kind = new
            onPicked(new)
        }), icons: true)
        .accessibilityIdentifier("home-kind-filter")
        .frame(maxWidth: .infinity)
        .overlay(alignment: .trailing) {
            Button(action: onFilters) { Image(systemName: "slider.horizontal.3") }
                .buttonStyle(.glass).buttonBorderShape(.circle)
                .accessibilityLabel(Text("Filtros de búsqueda"))
                .accessibilityIdentifier("home-filters")
        }
        .padding(.horizontal, DS.Space.gutter)
        .padding(.bottom, DS.Space.s2)
    }
}
