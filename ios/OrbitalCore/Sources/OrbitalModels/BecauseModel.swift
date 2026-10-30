import Foundation
import OrbitalCore

/// «Por lo que viste» (Inicio): el mazo de lo último que viste en Trakt y lo que Trakt relaciona con el de arriba. Sin
/// elegir, cambia solo cada día; al elegir otro, el mazo se mueve ya y sus relacionadas llegan al momento si se trajeron de
/// antemano (las de los vecinos se piden por detrás, de una en una). La misma lógica que tenía Para ti (`ParaTiModel`),
/// aparte para que Inicio no cargue todo Para ti.
@MainActor
public final class BecauseModel: ObservableModel {
    /// El título de arriba y sus relacionadas (nil sin Trakt o sin nada visto con relacionados).
    public private(set) var because: (seed: TraktEntry, items: [Suggestion])? { didSet { changed() } }
    /// Lo último que viste: las cartas del mazo.
    public private(set) var seeds: [TraktEntry] = [] { didSet { if seeds != oldValue { changed() } } }
    /// El título arriba del mazo: cambia en cuanto lo eliges (sus relacionadas llegan en `because`).
    public private(set) var selected: String? { didSet { if selected != oldValue { changed() } } }
    /// Las relacionadas de cada título, traídas de antemano.
    public private(set) var preloaded: [String: [Suggestion]] = [:] { didSet { if preloaded.count != oldValue.count { changed() } } }
    private var preloading: Task<Void, Never>?
    /// El que elegiste (nil: cambia solo cada día).
    private var chosen: String?
    private let services: Services

    public init(_ services: Services) {
        self.services = services
        super.init()
    }

    /// Trae lo último que viste y las relacionadas del de arriba (el que elegiste, o el del día).
    public func load() async {
        let forYou = services.forYou
        let asked = chosen
        async let found = forYou.becauseYouWatched(seed: asked)
        async let recent = forYou.recentSeeds()
        let (top, history) = await (found, recent)
        guard !Task.isCancelled else { return }
        seeds = history
        // Elegiste otro mientras llegaba: se queda tu elección (no la pisa lo que se pidió antes).
        guard chosen == asked else { preload(); return }
        because = top
        if selected == nil || !history.contains(where: { $0.imdb == selected }) { selected = top?.seed.imdb }
        else if selected != top?.seed.imdb, let pick = history.first(where: { $0.imdb == selected }), let ready = preloaded[pick.imdb] {
            because = (pick, ready)   // al recargar seguías en otro título: se queda ese
        }
        preload()
    }

    /// «Porque vi esto»: las relacionadas del que elijas.
    public func choose(_ seed: TraktEntry) async {
        chosen = seed.imdb
        selected = seed.imdb
        if let ready = preloaded[seed.imdb] { because = (seed, ready); return }
        let found = await services.forYou.related(to: seed)
        guard selected == seed.imdb else { return }   // pasaste a otro mientras llegaba
        because = (seed, found?.items ?? [])
        if let items = found?.items { preloaded[seed.imdb] = items }
    }

    /// Pruebas: como si nada se hubiera traído de antemano.
    func forgetPreloadedForTesting() { preloading?.cancel(); preloaded = [:] }

    /// Las relacionadas de los demás títulos, empezando por los vecinos del que se ve: pasar de uno a otro es inmediato.
    private func preload() {
        guard let current = because?.seed.imdb ?? selected else { return }
        if let items = because?.items, !items.isEmpty { preloaded[current] = items }
        guard let at = seeds.firstIndex(where: { $0.imdb == current }) else { return }
        let order = (1..<max(1, seeds.count)).flatMap { d in [seeds[(at + d) % seeds.count], seeds[(at - d + seeds.count) % seeds.count]] }
        var seen = Set([current])
        let queue = order.filter { seen.insert($0.imdb).inserted }
        let forYou = services.forYou
        preloading?.cancel()
        preloading = Task { [weak self] in
            for seed in queue {
                if Task.isCancelled { return }
                if self?.preloaded[seed.imdb] != nil { continue }
                if let found = await forYou.related(to: seed) { self?.preloaded[seed.imdb] = found.items }
            }
        }
    }
}
