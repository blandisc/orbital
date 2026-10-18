import SwiftUI
import OrbitalCore
import OrbitalModels

/// Los grupos de Para ti › Listas, en orden (el menú «Ir a una sección» los lista así).
enum CollectionSection: CaseIterable, Hashable {
    case forYou, platforms, studios, awards, years, airings, trakt, stremio, yourYear
    var title: Text {
        switch self {
        case .forYou: Text("Para ti"); case .trakt: Text("Listas de Trakt"); case .stremio: Text("Listas de Stremio")
        case .platforms: Text("Plataformas"); case .awards: Text("Premios"); case .studios: Text("Estudios"); case .years: Text("Por año")
        case .airings: Text("Próximos estrenos"); case .yourYear: Text("Tu año")
        }
    }

    /// Un ícono por sección en el índice de arriba (más fácil de encontrar de un vistazo).
    var symbol: String {
        switch self {
        case .forYou: "sparkles"; case .platforms: "play.tv"; case .studios: "film.stack"; case .awards: "trophy"
        case .years: "calendar"; case .airings: "calendar.badge.clock"; case .trakt: "list.bullet.rectangle"; case .stremio: "rectangle.stack"
        case .yourYear: "square.grid.3x3.fill"
        }
    }
}

/// Marca el grupo que cruza la parte de arriba de la pantalla (el menú lo palomea) y le da su id para saltar a él.
struct SectionSpy: ViewModifier {
    let section: CollectionSection
    @Binding var active: CollectionSection

    func body(content: Content) -> some View {
        content
            .id(section)
            .onGeometryChange(for: Bool.self) { proxy in
                let frame = proxy.frame(in: .scrollView)
                return frame.minY <= DS.Collections.spyLine && frame.maxY > DS.Collections.spyLine
            } action: { inside in if inside { active = section } }
    }
}

/// Una colección abierta: un premio, un año o Mi lista de Stremio.
struct CollectionRoute: Hashable {
    enum Kind: Hashable { case award, year, myList, studio }
    let kind: Kind
    let id: String
}

/// Una colección en cuadrícula de pósters (con ordenar y filtrar): los ganadores de un premio (con el año del premio), Mi
/// lista de Stremio, o lo más popular de un año (películas o series).
struct CollectionGridView: View {
    @ObservedObject var collections: ModelObserver<CollectionsModel>
    let route: CollectionRoute
    @State private var kind = "movie"
    @State private var yearItems: [Suggestion] = []
    @State private var loading = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                header
                if route.kind == .year {
                    DSKindFilter(kind: $kind, includeAll: false).padding(.horizontal, DS.Space.gutter)
                }
                if loading && items.isEmpty { ProgressView().frame(maxWidth: .infinity).padding(DS.Space.s10) }
                SortableGrid(listID: "\(route.kind):\(route.id)", items: items, watched: { await collections.model.watchedIDs() },
                             imdbRatings: { items in await collections.model.imdbRatings(items.map { ($0.kind, $0.imdb) }) }) { s in
                    TitleLink(route: s.route, width: DS.Poster.gridMinimum, detail: detail(s))
                }
            }
            .padding(.bottom, DS.Space.s14)
        }
        .background(Backdrop())
        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        .task { if route.kind == .studio, let id = Int(route.id) { await collections.model.loadStudio(id) } }
        .task(id: kind) {
            guard route.kind == .year, let year = Int(route.id) else { return }
            loading = true
            let found = await collections.model.items(year: year, kind: kind)
            guard !Task.isCancelled else { return }   // cambiaste de Películas a Series: no se pinta lo del otro
            yearItems = found
            loading = false
        }
    }

    /// El premio: su estatuilla grande con su halo y cuántos ganadores hay.
    @ViewBuilder private var header: some View {
        if route.kind == .award, let award {
            HStack(spacing: DS.Space.s4) {
                AwardEmblem(id: award.id)
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    AwardNames.title(award.id).recipe(.title)
                    AwardNames.category(award.id).recipe(.footnote)
                }
            }
            .padding(.horizontal, DS.Space.gutter).padding(.top, DS.Space.s2)
        }
    }

    private var award: AwardCollection? { collections.model.awards.first { $0.id == route.id } }

    private var items: [Suggestion] {
        switch route.kind {
        case .award: award?.suggestions ?? []
        case .year: yearItems
        case .myList: collections.model.myList
        case .studio: Int(route.id).flatMap { collections.model.studioItems[$0] } ?? []
        }
    }

    private var title: Text {
        switch route.kind {
        case .award: award.map { AwardNames.title($0.id) } ?? Text("Premios")
        case .year: Text(verbatim: route.id)
        case .myList: Text("Mi lista")
        case .studio: Text(verbatim: collections.model.studios.first { String($0.id) == route.id }?.name ?? "")
        }
    }

    /// Bajo cada póster: el año del premio (en un premio) o el año del título.
    private func detail(_ s: Suggestion) -> Text? {
        if route.kind == .award, case .console(let year) = s.reason { return Text(verbatim: year) }
        return s.year.map { Text(verbatim: String($0)) }
    }
}
