import SwiftUI

/// El velo bajo el texto que va sobre arte (lenguaje de diseño: «texto sobre imagen, siempre con velo»). Una sola pieza en
/// toda la app: el texto se lee sobre cualquier póster o fotograma, claro u oscuro. `DesignTests` no deja armar el degradado a
/// mano en las pantallas ni en las piezas.
struct ArtVeil: View {
    enum Kind {
        /// De claro arriba a oscuro abajo (lo más común: el título y los datos al pie).
        case bottom
        /// De oscuro arriba a claro abajo (lo que va arriba del arte: la barra del reproductor).
        case top
        /// Oscuro arriba y abajo, claro en medio (los controles del reproductor, la tarjeta de la TV).
        case both
        /// Parejo en todo el arte, un poco más firme abajo (un fondo desenfocado con texto encima).
        case full
        /// Oscuro a la izquierda (el texto va a la izquierda, sobre pósters a la derecha).
        case leading
    }
    /// Qué tan oscuro: `strong` bajo un título, `soft` para un fondo que solo apaga, `deep` hasta el fondo de la sala.
    enum Strength { case soft, strong, deep }

    var kind: Kind = .bottom
    /// `bottom`: dónde empieza a oscurecer (0 arriba, 1 abajo). `top`: dónde se acaba. `both`: dónde queda claro.
    var at: Double = 0.5
    /// `bottom`: dónde llega a su color pleno (1: hasta abajo; menos, si el texto ocupa más alto).
    var until: Double = 1
    var strength: Strength = .strong

    var body: some View {
        switch kind {
        case .bottom:
            LinearGradient(stops: [.init(color: .clear, location: at), .init(color: color, location: until), .init(color: color, location: 1)],
                           startPoint: .top, endPoint: .bottom)
        case .top:
            LinearGradient(stops: [.init(color: color, location: 0), .init(color: .clear, location: at)], startPoint: .top, endPoint: .bottom)
        case .both:
            LinearGradient(stops: [.init(color: DS.scrim, location: 0), .init(color: .clear, location: at), .init(color: color, location: 1)],   // ds-exception: la pieza del velo
                           startPoint: .top, endPoint: .bottom)
        case .full:
            LinearGradient(colors: [DS.scrim, color], startPoint: .top, endPoint: .bottom)   // ds-exception: la pieza del velo
        case .leading:
            LinearGradient(colors: [color, .clear], startPoint: .leading, endPoint: .trailing)
        }
    }

    private var color: Color {
        switch strength { case .soft: DS.scrim; case .strong: DS.scrimStrong; case .deep: DS.backdropDeep }
    }
}
