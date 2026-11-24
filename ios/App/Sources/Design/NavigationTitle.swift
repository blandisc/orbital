import SwiftUI

/// El título de la barra de arriba, en el idioma de la app aunque cambie con la pantalla abierta (TN1, 25 nov 2026: «idiomas
/// se llama idiomas» con la app en inglés). Con `navigationTitle("Idiomas")` SwiftUI no vuelve a traducirlo al cambiar el
/// idioma: la clave es la misma y la barra se queda con el texto viejo. Aquí se traduce con el idioma del momento y, al
/// cambiar, el texto es otro y la barra se actualiza. `testNavigationTitlesFollowTheLanguage` lo cuida.
private struct DSNavigationTitle: ViewModifier {
    let key: String
    @Environment(\.locale) private var locale

    func body(content: Content) -> some View {
        content.navigationTitle(Text(verbatim: Strings.tr(key, language: locale.language.languageCode?.identifier ?? "es")))
    }
}

extension View {
    /// Receta: el título de una pantalla (una clave del catálogo, en español).
    func dsNavigationTitle(_ key: String) -> some View { modifier(DSNavigationTitle(key: key)) }
}
