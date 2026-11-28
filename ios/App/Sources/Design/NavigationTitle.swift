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

/// El título de una pantalla que se abre encima (Ajustes, una lista, una colección): en el iPhone, siempre a la izquierda junto
/// a «‹» (TD1, Fernando, 27 nov 2026: «siempre a la izquierda en todos iPhones… más fácil mantener»). iOS lo centraba si cabía y
/// si no lo mandaba a la izquierda, así que dos páginas seguidas se veían distintas. En el iPad y la Mac, el del sistema.
/// `navigationTitle` se queda para «‹ Atrás», VoiceOver y el menú de pantallas anteriores.
private struct DSInlineTitle: ViewModifier {
    let title: Text

    func body(content: Content) -> some View {
        if ThisDevice.isPhone {
            // El del sistema se quita de la barra (queda para «‹» y VoiceOver) y el mismo texto va justo después de «‹».
            content.navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                .toolbar(removing: .title)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        title.recipe(.cardTitle).lineLimit(1).fixedSize().accessibilityAddTraits(.isHeader)
                    }
                    .sharedBackgroundVisibility(.hidden)
                }
        } else {
            content.navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        }
    }
}

extension View {
    /// Receta: el título de una pantalla que se abre encima, ya traducido (`Text`).
    func dsInlineTitle(_ title: Text) -> some View { modifier(DSInlineTitle(title: title)) }
    /// Receta: lo mismo con una clave del catálogo, en el idioma de la app aunque cambie con la pantalla abierta.
    func dsInlineTitle(_ key: String) -> some View { modifier(DSInlineTitleKey(key: key)) }
}

private struct DSInlineTitleKey: ViewModifier {
    let key: String
    @Environment(\.locale) private var locale

    func body(content: Content) -> some View {
        content.dsInlineTitle(Text(verbatim: Strings.tr(key, language: locale.language.languageCode?.identifier ?? "es")))
    }
}
