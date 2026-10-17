import SwiftUI
import OrbitalCore
import OrbitalModels

/// Los grupos de Para ti › Listas, en el orden del índice de arriba.
enum CollectionSection: CaseIterable, Hashable {
    case forYou, trakt, stremio, platforms, awards, years
    var title: Text {
        switch self {
        case .forYou: Text("Para ti"); case .trakt: Text(verbatim: "Trakt"); case .stremio: Text(verbatim: "Stremio")
        case .platforms: Text("Plataformas"); case .awards: Text("Premios"); case .years: Text("Por año")
        }
    }
}

/// Marca el grupo que cruza la parte de arriba de la pantalla (el índice lo resalta) y le da su id para saltar a él.
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
    enum Kind: Hashable { case award, year, myList }
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
                    DSSegmented(options: [("movie", "Películas"), ("series", "Series")], selection: $kind).padding(.horizontal, DS.Space.gutter)
                }
                if loading && items.isEmpty { ProgressView().frame(maxWidth: .infinity).padding(DS.Space.s10) }
                SortableGrid(listID: "\(route.kind):\(route.id)", items: items, watched: { await collections.model.watchedIDs() }) { s in
                    TitleLink(route: s.route, width: DS.Poster.gridMinimum, detail: detail(s))
                }
            }
            .padding(.bottom, DS.Space.s14)
        }
        .background(Backdrop())
        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        .task(id: kind) {
            guard route.kind == .year, let year = Int(route.id) else { return }
            loading = true
            yearItems = await collections.model.items(year: year, kind: kind)
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
        }
    }

    private var title: Text {
        switch route.kind {
        case .award: award.map { AwardNames.title($0.id) } ?? Text("Premios")
        case .year: Text(verbatim: route.id)
        case .myList: Text("Mi lista")
        }
    }

    /// Bajo cada póster: el año del premio (en un premio) o el año del título.
    private func detail(_ s: Suggestion) -> Text? {
        if route.kind == .award, case .console(let year) = s.reason { return Text(verbatim: year) }
        return s.year.map { Text(verbatim: String($0)) }
    }
}
