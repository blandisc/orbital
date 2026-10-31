import SwiftUI

/// La franja bajo la barra de Inicio: Todo · Películas · Series con palabras, al centro (filtra toda la página). En la barra
/// no caben junto al logotipo y sus botones (iOS los mandaba a un «…»). El filtro avanzado ya no va aquí: vive en Buscar
/// (Fernando, 30 oct 2026).
/// Al cambiar el tipo, su nombre sale un momento en el aviso de abajo (`onPicked`): los íconos solos se entienden menos que
/// una palabra, y debajo de la franja tapaba el botón de la portada.
struct HomeKindBar: View {
    /// "" es todo, «movie» o «series».
    @Binding var kind: String
    /// Solo cuando lo cambias tú: el nombre del tipo elegido.
    let onPicked: (String) -> Void

    var body: some View {
        DSKindFilter(kind: Binding(get: { kind }, set: { new in
            kind = new
            onPicked(new)
        }), tabs: true)   // pestañas de texto: los íconos solos no se entendían y la cápsula gris no gustaba
        .accessibilityIdentifier("home-kind-filter")
        .frame(maxWidth: .infinity)
        .padding(.horizontal, DS.Space.gutter)
        .padding(.bottom, DS.Space.s1)
    }
}
