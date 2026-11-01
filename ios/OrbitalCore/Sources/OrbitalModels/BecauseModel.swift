import Foundation
import OrbitalCore

/// «Por lo que viste» (Inicio): el mazo de lo último que viste en Trakt y lo que Trakt relaciona con el de arriba. Sin
/// elegir, cambia solo cada día; al elegir otro, el mazo se mueve ya y sus relacionadas llegan al momento si se trajeron de
/// antemano (las de los vecinos se piden por detrás, de una en una). La misma lógica que tenía Para ti (`ParaTiModel`),
/// aparte para que Inicio no cargue todo Para ti.
@MainActor
public final class BecauseModel: ObservableModel {
    /// El título de arriba y sus relacionadas (nil sin Trakt o sin nada visto con relacionados).
    public private(set) var because: (seed: TraktEntry, items: [Suggestion])? {
        didSet { if oldValue?.seed != because?.seed || oldValue?.items != because?.items { changed() } }   // volver a Inicio lo vuelve a pedir: sin cambios, no se repinta
    }
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

    /// «No recomendar por esta» (mantener el dedo sobre el mazo): el título sale del mazo y ya no se usa para recomendar.
    /// Si era el de arriba, pasa al siguiente. `resumeSeeding` lo regresa.
    public func stopSeeding(_ seed: TraktEntry) async {
        let forYou = services.forYou
        await forYou.stopSeeding(seed.imdb)
        let at = seeds.firstIndex { $0.imdb == seed.imdb } ?? 0
        seeds.removeAll { $0.imdb == seed.imdb }
        preloaded[seed.imdb] = nil
        guard selected == seed.imdb || because?.seed.imdb == seed.imdb else { return }
        if seeds.isEmpty { because = nil; selected = nil; chosen = nil; return }
        await choose(seeds[min(at, seeds.count - 1)])
    }

    /// Deshace «No recomendar por esta»: vuelve al mazo y arriba.
    public func resumeSeeding(_ seed: TraktEntry) async {
        await services.forYou.resumeSeeding(seed.imdb)
        seeds = await services.forYou.recentSeeds()
        await choose(seed)
    }

    /// Pruebas: como si nada se hubiera traído de antemano.
    func forgetPreloadedForTesting() { preloading?.cancel(); preloaded = [:] }

    /// Las relacionadas de los demás títulos, empezando por los vecinos del que se ve: pasar de uno a otro es inmediato.
    private func preload() {
        guard let current = because?.seed.imdb ?? selected else { return }
        if let items = because?.items, !items.isEmpty { preloaded[current] = items }
        guard let at = seeds.firstIndex(where: { $0.imdb == current }) else { return }
        // Alternando a cada lado del que se ve (siguiente, anterior, el que sigue…). En un ciclo con tipos explícitos: la
        // misma expresión en una línea hacía que el compilador de la CI se rindiera (31 oct 2026).
        let count: Int = seeds.count
        var order: [TraktEntry] = []
        for d in 1..<max(1, count) {
            let after: Int = (at + d) % count
            let before: Int = (at - d + count) % count
            order.append(seeds[after]); order.append(seeds[before])
        }
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
