import SwiftUI
import OrbitalCore
import OrbitalModels

/// «Por lo que viste» (Inicio, docs/producto/inicio-benchmark/): el mazo de lo último que viste (`BecauseCard`, el de Para ti)
/// y abajo lo que Trakt relaciona con el de arriba. Cambias el título del mazo y cambian las sugerencias. Con un tipo en la
/// barra (Series o Películas), las sugerencias son solo de ese tipo.
struct HomeBecause: View {
    let model: BecauseModel
    /// "" o nil: todo; «movie» o «series».
    let kind: String?
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let _ = model.track()
        if let because = model.because, !model.seeds.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                DSSectionHead(title: Text("Por lo que viste"), source: .trakt, eyebrow: Text("Cambia lo que viste y cambian las sugerencias"))
                    .padding(.horizontal, DS.Space.gutter)
                card(because)
            }
        }
    }

    private func card(_ because: (seed: TraktEntry, items: [Suggestion])) -> some View {
        let fromHistory = model.seeds.map(seed)
        let seeds = fromHistory.contains { $0.id == because.seed.imdb } ? fromHistory : [seed(because.seed)] + fromHistory
        // El mazo sigue a lo que elegiste al momento; las relacionadas son las del de arriba o, si aún no llegan, su lugar.
        let selected = model.selected ?? because.seed.imdb
        let items = because.items.filter { kind == nil || $0.kind == kind }
        let state: BecauseRelated = because.seed.imdb != selected ? .loading : items.isEmpty ? .none : .ready
        return BecauseCard(seeds: seeds, selected: selected, state: state,
                           choose: { id in if let pick = model.seeds.first(where: { $0.imdb == id }) { Task { await model.choose(pick) } } },
                           artBackdrop: true) {
            ForEach(items) { s in TitleLink(route: s.route, width: DS.Collections.relatedPoster) }
        }
        .padding(.horizontal, DS.Space.gutter)
        // Los pósters de los vecinos (lo siguiente que vas a tocar), de antemano: al cambiar ya están.
        .task(id: "\(selected)-\(model.preloaded.count)") {
            guard let at = seeds.firstIndex(where: { $0.id == selected }), seeds.count > 1 else { return }
            let neighbors = [seeds[(at + 1) % seeds.count].id, seeds[(at - 1 + seeds.count) % seeds.count].id]
            ImagePipeline.shared.prefetchPosters(neighbors.flatMap { (model.preloaded[$0] ?? []).prefix(DS.Collections.relatedPlaceholders + 1).map(\.poster) })
        }
    }

    /// Un título de lo que viste, para el mazo: qué es y de qué año («Serie · 2005»).
    private func seed(_ e: TraktEntry) -> BecauseSeed {
        let language = env.services.appSettings.uiLanguage
        var parts = [Strings.tr(e.kind == "movie" ? "Película" : "Serie", language: language)]
        if let year = e.year { parts.append(String(year)) }
        return BecauseSeed(id: e.imdb, title: e.title, poster: String(format: ForYou.metahubPoster, e.imdb), detail: parts.joined(separator: " · "))
    }
}
