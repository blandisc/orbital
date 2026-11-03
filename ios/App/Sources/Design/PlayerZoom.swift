import SwiftUI

// MARK: Tarjeta → reproductor con la transición de zoom nativa

/// De qué tarjeta nace el reproductor: el título y el lugar («continue», «title»). Un título puede estar a la vez en Inicio y en
/// su ficha (abierta encima): con solo el título, el zoom podía salir de la tarjeta que no se tocó.
struct PlayerZoomID: Hashable {
    let metaID: String
    let slot: String
}

extension EnvironmentValues {
    /// El espacio del zoom del reproductor (lo pone la raíz, que presenta el reproductor).
    @Entry var playerZoom: Namespace.ID? = nil
}

private struct PlayerZoomSource: ViewModifier {
    let id: PlayerZoomID
    @Environment(\.playerZoom) private var zoom

    func body(content: Content) -> some View {
        if let zoom {
            // Con la esquina de la tarjeta: el video crece desde ella y, al cerrar, se encoge de vuelta a ella.
            content.matchedTransitionSource(id: id, in: zoom) { source in
                source.clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            }
        } else { content }
    }
}

extension View {
    /// Esta tarjeta es el origen del reproductor cuando se toca para ver.
    func playerZoomSource(_ id: PlayerZoomID) -> some View { modifier(PlayerZoomSource(id: id)) }

    /// El reproductor crece desde la tarjeta que se tocó (`source`); sin tarjeta (Siri, un aviso, la ruleta), entra como siempre.
    /// El zoom de iOS deja cerrarlo arrastrando o pellizcando: se apaga, solo se sale con la ✕ (Fernando, 3 nov 2026: «está
    /// excesivamente sensible… te saca del reproductor», y el pellizco de los modos de imagen lo cerraba).
    @ViewBuilder func playerZoom(from source: PlayerZoomID?, in zoom: Namespace.ID) -> some View {
        if let source { navigationTransition(.zoom(sourceID: source, in: zoom)).interactiveDismissDisabled() } else { interactiveDismissDisabled() }
    }
}
