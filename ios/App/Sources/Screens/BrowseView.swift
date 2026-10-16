import SwiftUI
import OrbitalCore
import OrbitalModels

/// «Ver»: buscar películas y series, y lo más popular de Stremio.
struct BrowseView: View {
    @StateObject private var catalog: ModelObserver<CatalogModel>
    @StateObject private var search: ModelObserver<SearchModel>
    @State private var query = ""

    init() {
        let services = AppEnvironment.shared.services
        _catalog = StateObject(wrappedValue: ModelObserver(CatalogModel(services)))
        _search = StateObject(wrappedValue: ModelObserver(SearchModel(services)))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s6) {
                if query.trimmingCharacters(in: .whitespaces).count >= 2 { results } else { suggestions }
            }
            .padding(.bottom, DS.Space.s8)
        }
        .background(Backdrop())
        .navigationTitle("Ver").navigationBarTitleDisplayMode(.large)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("Buscar películas y series"))
        .navigationDestination(for: TitleRoute.self) { TitleView(route: $0) }
        .task(id: query) {
            try? await Task.sleep(nanoseconds: DS.Timing.searchDebounce)    // espera a que termines de escribir
            guard !Task.isCancelled else { return }
            await search.model.search(query)
        }
        .task {
            #if DEBUG
            if Demo.isOn, let text = Demo.search { query = text }
            #endif
            await catalog.model.load()
        }
        .refreshable { await catalog.model.load() }
    }

    @ViewBuilder private var results: some View {
        let model = search.model
        if let error = model.error { DSNotice(text: LocalizedStringKey(error), tone: .warn).padding(.horizontal, DS.Space.gutter) }
        else if model.results.isEmpty && !model.isSearching { DSNotice(text: "No encontré nada con ese nombre.").padding(.horizontal, DS.Space.gutter) }
        LazyVGrid(columns: [GridItem(.adaptive(minimum: DS.Poster.gridMinimum), spacing: DS.Space.s3)], spacing: DS.Space.s4) {
            ForEach(model.results) { r in
                TitleLink(route: TitleRoute(kind: r.kind, metaID: r.metaID, title: r.title, poster: r.poster), width: DS.Poster.gridMinimum,
                          detail: yearAndKind(year: r.year, kind: r.kind))
                    .simultaneousGesture(TapGesture().onEnded { model.remember(query) })
            }
        }
        .padding(.horizontal, DS.Space.gutter)
        .overlay { if model.isSearching && model.results.isEmpty { ProgressView() } }
    }

    @ViewBuilder private var suggestions: some View {
        let model = catalog.model
        if !search.model.recent.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                DSSectionHead(title: "Búsquedas recientes", trailing: "Borrar") { search.model.clearRecent() }
                ForEach(search.model.recent, id: \.self) { text in
                    Button { query = text } label: { Label(text, systemImage: "clock.arrow.circlepath").foregroundStyle(DS.textMuted).font(DS.font(.md)) }
                }
            }
            .padding(.horizontal, DS.Space.gutter)
        }
        if let error = model.error { DSNotice(text: LocalizedStringKey(error), tone: .warn).padding(.horizontal, DS.Space.gutter) }
        if !model.movies.isEmpty { Rail(title: "Películas populares") { ForEach(model.movies) { TitleLink(route: TitleRoute(kind: $0.kind, metaID: $0.metaID, title: $0.title, poster: $0.poster)) } } }
        if !model.series.isEmpty { Rail(title: "Series populares") { ForEach(model.series) { TitleLink(route: TitleRoute(kind: $0.kind, metaID: $0.metaID, title: $0.title, poster: $0.poster)) } } }
        if model.isLoading && model.movies.isEmpty { ProgressView().frame(maxWidth: .infinity) }
    }
}
