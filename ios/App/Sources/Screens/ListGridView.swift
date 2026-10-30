import SwiftUI
import OrbitalCore
import OrbitalModels

/// Una lista abierta completa (cuadrícula), «Próximos estrenos» y los rankings de una plataforma.

/// La lista completa de un estante, en cuadrícula (el mismo título y logo del encabezado que se tocó).
struct ListGridView: View {
    var observer: ModelObserver<ParaTiModel>
    var collections: ModelObserver<CollectionsModel>
    let shelfID: String
    private var model: ParaTiModel { observer.model }

    private func poster(_ s: Suggestion, _ plan: ShelfPlan, width: CGFloat) -> some View {
        PlanPoster(suggestion: s, plan: plan, model: model, style: plan.style == .top10 ? .platform : plan.style, width: width)
    }

    var body: some View {
        ScrollView {
            if let plan = model.shelves.first(where: { $0.id == shelfID }) {
                VStack(alignment: .leading, spacing: DS.Space.s4) {
                    HStack(spacing: DS.Space.s3) {
                        if plan.style != .plain, let logo = plan.list.logo { DSPlatformLogo(url: logo) }
                        if let meta = shelfMeta(plan) { meta.font(DS.TextRecipe.footnote.font).foregroundStyle(DS.textMuted).lineLimit(2) }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, DS.Space.gutter)
                    let items = model.items(for: plan)
                    if items.isEmpty && !model.isLoading(shelf: plan) {
                        DSEmptyState(symbol: "tray", title: Text("Nada por aquí por ahora"))
                    } else if plan.style == .top10 {
                        // Un ranking se lee en su orden: sin ordenar ni filtrar.
                        DSPosterGrid(items: items) { s, width in poster(s, plan, width: width) }
                    } else {
                        SortableGrid(listID: plan.id, items: items, collections: collections.model, watched: { await collections.model.watchedIDs() },
                             imdbRatings: { items in await collections.model.imdbRatings(items.map { ($0.kind, $0.imdb) }) },
                                     loading: model.isLoading(shelf: plan)) { s, width in poster(s, plan, width: width) }
                    }
                }
                .padding(.bottom, DS.Space.s14)
                .navigationTitle(shelfTitle(plan))
            }
        }
        .background(Backdrop())
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A dónde lleva una tarjeta de «Tus plataformas».
struct PlatformRoute: Hashable { var brand: String }

/// Los rankings de una plataforma: su logo con su brillo arriba y, por ranking (Top 10 de Netflix, tendencia de JustWatch;
/// series y películas), los pósters con su número grande en el color de la plataforma. Tocar uno abre su ficha.
struct PlatformRankingsView: View {
    var observer: ModelObserver<ParaTiModel>
    let hub: PlatformHub
    private var model: ParaTiModel { observer.model }
    /// «Series» o «Películas» (pestañas grandes) y cuál de sus listas (pestañas de texto con el subrayado de la marca).
    @State private var kind: String?
    @State private var source: PlatformRanking.Source?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var kinds: [String] { ["series", "movie"].filter { k in hub.rankings.contains { $0.kind == k } } }
    private var currentKind: String { kind ?? kinds.first ?? "series" }
    private var sources: [PlatformRanking.Source] {
        var seen = Set<String>()
        return hub.rankings.filter { $0.kind == currentKind }.map(\.source).filter { seen.insert($0.rawValue).inserted }
    }
    private var current: PlatformRanking? {
        let wanted = source.flatMap { s in sources.contains(s) ? s : nil } ?? sources.first
        return hub.rankings.first { $0.kind == currentKind && $0.source == wanted }
    }

    var body: some View {
        let tint = DS.PlatformTint.color(hub.brand)
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s5) {
                HStack(spacing: DS.Space.s4) {
                    PlatformLogoTile(url: hub.logo, name: hub.name, size: DS.PlatformFan.headerLogo, radius: DS.Radius.lg, tint: tint,
                                     glow: DS.PlatformFan.headerGlow)
                    VStack(alignment: .leading, spacing: DS.Space.s1) {
                        if let current { rankingSource(current).recipe(.footnote, color: DS.textMuted) }
                        Text(verbatim: hub.name).recipe(.title)
                    }
                }
                .padding(.horizontal, DS.Space.gutter)
                // Películas · Series: el filtro de toda la app.
                if kinds.count > 1 {
                    DSKindFilter(kind: Binding(get: { currentKind }, set: { new in withAnimation(DS.Motion.base(reduceMotion)) { kind = new } }), includeAll: false)
                        .padding(.horizontal, DS.Space.gutter)
                }
                // Sus listas, como pestañas de texto con el subrayado en el color de la plataforma.
                if sources.count > 1, let current {
                    HStack(spacing: DS.Space.s5) {
                        ForEach(sources, id: \.rawValue) { src in
                            Button { withAnimation(DS.Motion.base(reduceMotion)) { source = src } } label: {
                                VStack(spacing: DS.Space.s2) {
                                    sourceName(src).recipe(.secondary, color: src == current.source ? DS.text : DS.textMuted).fontWeight(.semibold)
                                    Capsule().fill(src == current.source ? tint : .clear).frame(height: DS.PlatformFan.tabUnderline)
                                }
                                .fixedSize()
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(src == current.source ? .isSelected : [])
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, DS.Space.gutter)
                }
                if let current { grid(current, tint: tint) }
            }
            .padding(.vertical, DS.Space.s4)
            .padding(.bottom, DS.Space.s14)
        }
        .background(Backdrop())
        .navigationTitle(Text(verbatim: hub.name)).navigationBarTitleDisplayMode(.inline)
        .task { await model.loadRankings(hub) }
    }

    /// La lista en cuadrícula de dos, con el número grande en el color de la plataforma y su brillo (como hoy).
    @ViewBuilder private func grid(_ ranking: PlatformRanking, tint: Color) -> some View {
        let items = model.items(for: ranking)
        LazyVGrid(columns: DS.Poster.pairColumns(spacing: DS.Space.s3), spacing: DS.Space.s5) {
            if items.isEmpty && model.isLoading(ranking: ranking) { ShelfSkeleton() }
            ForEach(Array(items.enumerated()), id: \.element.id) { index, s in
                TitleNavigationLink(route: s.route) {
                    RankedPosterCard(rank: s.rank ?? index + 1, title: s.title, poster: s.poster, movement: s.movement, isNew: s.isNew, tint: tint)
                        .titleZoomSource(s.route)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, DS.Space.gutter)
        .id(ranking.id)
        .transition(.opacity)
    }

    private func sourceName(_ source: PlatformRanking.Source) -> Text {
        switch source { case .netflixTop10: Text("Top 10"); case .justWatch: Text("Tendencia"); case .popular: Text("Lo más popular") }
    }

    private func rankingSource(_ ranking: PlatformRanking) -> Text {
        switch ranking.source {
        case .netflixTop10: Text("Netflix · esta semana")
        case .justWatch: Text("JustWatch · hoy")
        case .popular: Text("TMDB")
        }
    }
}
