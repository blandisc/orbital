import SwiftUI
import OrbitalCore

extension PosterQuick {
    /// RP2: ▶ y ＋ sobre un póster en la Mac, conectados con la app: ver donde ibas (o desde el principio) y guardar en Mi lista,
    /// con su aviso que se deshace. Lo pone `RootView`.
    @MainActor static func app(_ env: AppEnvironment) -> PosterQuick {
        return PosterQuick(id: ObjectIdentifier(env))
    }

    private static func suggestion(_ r: TitleRoute) -> Suggestion {
        Suggestion(kind: r.kind, imdb: r.metaID, title: r.title, poster: r.poster ?? "", wide: "", reason: .popular)
    }
    @MainActor func play(_ r: TitleRoute) { let env = AppEnvironment.shared; Task { await env.play(Self.suggestion(r)) } }
    @MainActor func save(_ r: TitleRoute) { let env = AppEnvironment.shared; Task { await env.save(Self.suggestion(r)) } }
}
