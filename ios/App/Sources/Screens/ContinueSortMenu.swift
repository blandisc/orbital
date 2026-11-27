import SwiftUI
import OrbitalModels

/// «Ordenar y filtrar» de «Seguir viendo» completo (Inicio › «Ver todo»): el orden y si se ven películas, series o todo. El
/// estado vive en `HomeView`; salió de `HomeView.swift` (27 nov 2026) para que no pasara de su tope de líneas.
struct ContinueSortMenu: View {
    @Binding var sort: ListSort
    @Binding var kind: String

    var body: some View {
        Menu {
            Picker("Ordenar", selection: $sort) {
                Text("Lo último que viste").tag(ListSort.added)
                Text("A–Z").tag(ListSort.title)
            }
            Picker("Mostrar", selection: $kind) {
                Text("Todo").tag("")
                Text("Películas").tag("movie")
                Text("Series").tag("series")
            }
        } label: { Image(systemName: "line.3.horizontal.decrease") }   // ds-exception: en la barra de arriba el sistema le da los 44
        .accessibilityLabel(Text("Ordenar y filtrar"))
    }
}
