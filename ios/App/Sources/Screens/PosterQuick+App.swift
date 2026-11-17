import SwiftUI
import OrbitalCore

extension PosterQuick {
    /// RP2: ▶ y ＋ sobre un póster en la Mac, conectados con la app: ver donde ibas (o desde el principio) y guardar en Mi lista,
    /// con su aviso que se deshace. Lo pone `RootView`.
    @MainActor static func app(_ env: AppEnvironment) -> PosterQuick {
        func suggestion(_ r: TitleRoute) -> Suggestion {
            Suggestion(kind: r.kind, imdb: r.metaID, title: r.title, poster: r.poster ?? "", wide: "", reason: .popular)
        }
        return PosterQuick(id: ObjectIdentifier(env), play: { r in Task { await env.play(suggestion(r)) } }, save: { r in Task { await env.save(suggestion(r)) } })
    }
}
