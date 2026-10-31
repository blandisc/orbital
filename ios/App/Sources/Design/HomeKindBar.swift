import SwiftUI

/// La franja bajo la barra de Inicio: Todo · Películas · Series con palabras, al centro (filtra toda la página). En la barra
/// no caben junto al logotipo y sus botones (iOS los mandaba a un «…»). El filtro avanzado ya no va aquí: vive en Buscar
/// (Fernando, 30 oct 2026).
/// Al cambiar el tipo no sale aviso (Fernando, 31 oct 2026): las pestañas ya dicen su nombre.
struct HomeKindBar: View {
    /// "" es todo, «movie» o «series».
    @Binding var kind: String

    var body: some View {
        DSKindFilter(kind: $kind, mark: DS.eyebrow)   // las pestañas de toda la app; Inicio, con su rayita turquesa como estaba (Fernando, 31 oct 2026)
        .accessibilityIdentifier("home-kind-filter")
        .frame(maxWidth: .infinity)
        .padding(.horizontal, DS.Space.gutter)
        .padding(.bottom, DS.Space.s1)
    }
}
