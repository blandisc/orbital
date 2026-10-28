import SwiftUI

/// El corazón de tus favoritos de Trakt (en la barra de arriba de la ficha, junto a «Ver en la TV» y «Compartir»): vacío si
/// no es favorito, lleno en `DS.Favorites.filled` si lo es. Cambia con el ícono del sistema (el corazón «se llena») y un
/// toque háptico al agregar; VoiceOver dice qué hará.
struct FavoriteButton: View {
    let isFavorite: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isFavorite ? DS.Favorites.symbolFilled : DS.Favorites.symbol)
                .foregroundStyle(isFavorite ? AnyShapeStyle(DS.Favorites.filled) : AnyShapeStyle(.primary))
                .contentTransition(.symbolEffect(.replace))
        }
        .sensoryFeedback(.success, trigger: isFavorite) { _, now in now }
        .accessibilityLabel(isFavorite ? Text("Quitar de favoritos") : Text("Agregar a favoritos"))
        .accessibilityAddTraits(isFavorite ? .isSelected : [])
        .accessibilityIdentifier("title-favorite")
    }
}
