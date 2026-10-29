import SwiftUI
import OrbitalCore
import OrbitalModels

/// Qué título es, para buscar su póster sin texto (`TallArt`).
struct TallArtKey: Hashable, Sendable {
    let imdb: String
    let kind: String
}

/// Cómo se pregunta por el póster sin texto: lo pone la raíz (`RootView`); sin él (previsualizaciones, el widget) va el fondo.
struct TallArtLookup: Sendable {
    var known: @Sendable (TallArtKey) -> TallArt.Answer
    var fetch: @Sendable (TallArtKey) async -> String?

    init(_ art: TallArt) {
        known = { art.known(imdb: $0.imdb, kind: $0.kind) }
        fetch = { await art.poster(imdb: $0.imdb, kind: $0.kind) }
    }
}

extension EnvironmentValues {
    @Entry var tallArt: TallArtLookup? = nil
}

/// El arte de un marco: si el marco es alto (`ArtFit.tallBelow`) y el título tiene póster sin texto, ese (encaja entero, como
/// en Netflix o Apple TV en el teléfono); si no, el de siempre (`wide`, recortado hacia el sujeto). Mientras pregunta por
/// primera vez no pinta nada (el degradado del marco): así no sale el fondo y luego cambia al póster. Lo que decide, se queda.
struct TallArtPicker<Content: View>: View {
    let key: TallArtKey?
    let wide: String?
    /// nil: aún no se midió el marco (se espera, por lo mismo).
    let tallBox: Bool?
    @ViewBuilder let content: (_ url: String?, _ fallback: String?) -> Content
    @Environment(\.tallArt) private var lookup
    private enum Decision: Equatable { case wide, tall(String) }
    @State private var decision: Decision?

    var body: some View {
        let choice = choose()
        content(choice.url, choice.fallback)
            .task(id: asking) {
                guard let key = asking, let lookup else { return }
                let found = await lookup.fetch(key)
                if decision == nil { decision = found.map(Decision.tall) ?? .wide }
            }
            .task(id: asking) {
                guard asking != nil else { return }
                try? await Task.sleep(for: DS.Image.tallWait)
                if decision == nil { decision = .wide }   // TMDB tarda: va el fondo, y ya no se cambia
            }
    }

    /// El título por el que hay que preguntar (nil: ya se sabe, o no aplica).
    private var asking: TallArtKey? {
        guard decision == nil, tallBox == true, let key, let lookup, lookup.known(key) == .unknown else { return nil }
        return key
    }

    private func choose() -> (url: String?, fallback: String?) {
        guard let key, let lookup, tallBox != false else { return (wide, nil) }
        switch decision {
        case .tall(let url): return (url, wide)
        case .wide: return (wide, nil)
        case nil: break
        }
        guard tallBox == true else { return (nil, nil) }   // midiendo
        switch lookup.known(key) {
        case .poster(let url): return (url, wide)
        case .none: return (wide, nil)
        case .unknown: return (nil, nil)
        }
    }
}

extension DS.Image {
    /// Lo más que se espera la primera vez a saber si hay póster sin texto antes de mostrar el fondo.
    static let tallWait: Duration = .milliseconds(1500)
}
