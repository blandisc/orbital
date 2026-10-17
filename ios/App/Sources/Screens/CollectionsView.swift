import SwiftUI
import OrbitalCore
import OrbitalModels

/// Los grupos de Colecciones (Para ti › Listas), en el orden del índice de arriba.
enum CollectionSection: CaseIterable, Hashable {
    case platforms, awards, lists, years
    var title: Text {
        switch self { case .platforms: Text("Plataformas"); case .awards: Text("Premios"); case .lists: Text("Tus listas"); case .years: Text("Por año") }
    }
}

/// Una colección abierta: un premio, una de tus listas o un año.
struct CollectionRoute: Hashable {
    enum Kind: Hashable { case award, list, year }
    let kind: Kind
    let id: String
}

/// Una colección en cuadrícula de pósters: los ganadores de un premio (con el año del premio), tu lista, o lo más
/// popular de un año (películas o series).
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
                LazyVGrid(columns: [GridItem(.adaptive(minimum: DS.Poster.gridMinimum), spacing: DS.Space.s3)], spacing: DS.Space.s4) {
                    ForEach(items) { s in
                        TitleLink(route: s.route, width: DS.Poster.gridMinimum, detail: detail(s))
                    }
                }
                .padding(.horizontal, DS.Space.gutter)
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
        case .list: collections.model.items(ofList: route.id)
        case .year: yearItems
        }
    }

    private var title: Text {
        switch route.kind {
        case .award: award.map { AwardNames.title($0.id) } ?? Text("Premios")
        case .list: Text(verbatim: collections.model.lists.first { $0.id == route.id }?.name ?? "")
        case .year: Text(verbatim: route.id)
        }
    }

    /// Bajo cada póster: el año del premio (en un premio) o el año del título.
    private func detail(_ s: Suggestion) -> Text? {
        if route.kind == .award, case .console(let year) = s.reason { return Text(verbatim: year) }
        return s.year.map { Text(verbatim: String($0)) }
    }
}
