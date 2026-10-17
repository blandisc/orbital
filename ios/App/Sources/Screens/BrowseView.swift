import SwiftUI
import OrbitalCore
import OrbitalModels

/// Un género de «Explora» al que se navega (nombre de Cinemeta, en inglés).
struct GenreRoute: Hashable { var genre: String }

/// «Buscar» (la pestaña de búsqueda nativa de iOS 26): sin escribir, el Top 10 de hoy en carrusel y los géneros para
/// explorar; al escribir, los resultados en cuadrícula.
struct BrowseView: View {
    @EnvironmentObject private var env: AppEnvironment
    @StateObject private var catalog: ModelObserver<CatalogModel>
    @StateObject private var search: ModelObserver<SearchModel>
    @State private var query = ""
    /// El póster que ilustra cada género (el primero de su catálogo), según van llegando.

    /// Cuántos de lo más popular van en el carrusel con puesto (un Top 10).
    private static let popularCount = 10

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
        .navigationTitle("Buscar").toolbarTitleDisplayMode(.inlineLarge)   // el título grande en el renglón de los botones: no se pierde un renglón arriba
        .searchable(text: $query, prompt: Text("Películas y series"))
        // El campo vive abajo (pestaña de búsqueda, como Trakt); al escribir, el título se queda arriba y los resultados
        // empiezan bajo él (antes la barra se escondía y lo de arriba chocaba con la hora).
        .searchPresentationToolbarBehavior(.avoidHidingContent)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { ProfileButton() } }
        .titleDestinations()
        .navigationDestination(for: SettingsRoute.self) { _ in SettingsView() }
        .navigationDestination(for: GenreRoute.self) { GenreView(genre: $0.genre, model: catalog.model) }
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

    // MARK: resultados
    @ViewBuilder private var results: some View {
        let model = search.model
        // «Sin resultados» solo cuando ya contestó la búsqueda de lo que está escrito (no durante la espera de la última letra).
        let answered = !model.isSearching && model.searchedQuery == query.trimmingCharacters(in: .whitespacesAndNewlines)
        if let error = model.error, answered { DSNotice(verbatim: env.message(error), tone: .warn).padding(.horizontal, DS.Space.gutter) }
        else if model.results.isEmpty && answered { ContentUnavailableView.search(text: query) }
        LazyVGrid(columns: [GridItem(.adaptive(minimum: DS.Poster.gridMinimum), spacing: DS.Space.s3)], spacing: DS.Space.s4) {
            if !answered && model.results.isEmpty && model.error == nil {
                // Mientras llega: pósters vacíos en su lugar (antes, una ruedita sobre la barra de arriba).
                ForEach(0..<9, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: DS.Radius.md).fill(DS.fill).aspectRatio(DS.Poster.aspect, contentMode: .fit)
                }
                .accessibilityHidden(true)
            }
            ForEach(model.results) { r in
                TitleLink(route: TitleRoute(kind: r.kind, metaID: r.metaID, title: r.title, poster: r.poster), width: DS.Poster.gridMinimum,
                          detail: yearAndKind(year: r.year, kind: r.kind))
                    .simultaneousGesture(TapGesture().onEnded { model.remember(query) })
            }
        }
        .padding(.horizontal, DS.Space.gutter)
    }

    // MARK: sin escribir
    @ViewBuilder private var suggestions: some View {
        let model = catalog.model
        if !search.model.recent.isEmpty { recent }
        if let error = model.error { DSNotice(verbatim: env.message(error), tone: .warn).padding(.horizontal, DS.Space.gutter) }
        if !model.popular.isEmpty { popular(model) }
        else if model.isLoading { ProgressView().frame(maxWidth: .infinity) }
        explore
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            DSSectionHead(title: "Búsquedas recientes", trailing: "Borrar") { search.model.clearRecent() }
            ForEach(search.model.recent, id: \.self) { text in
                Button { query = text } label: { Label(text, systemImage: "clock.arrow.circlepath").recipe(.body, color: DS.textMuted) }
                    .frame(minHeight: DS.Size.touchTarget)
            }
        }
        .padding(.horizontal, DS.Space.gutter)
    }

    /// «Lo más popular hoy»: el Top 10 de Stremio en carrusel, con la cifra grande (el mismo lenguaje que los rankings de
    /// tus plataformas). Películas y series alternadas, de Cinemeta.
    private func popular(_ model: CatalogModel) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            DSSectionHead(title: "Lo más popular hoy", trailing: "Stremio", icon: .flame).padding(.horizontal, DS.Space.gutter)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: DS.Space.s3) {
                    ForEach(Array(model.popular.prefix(Self.popularCount).enumerated()), id: \.element.id) { index, item in
                        let route = TitleRoute(kind: item.kind, metaID: item.metaID, title: item.title, poster: item.poster)
                        NavigationLink(value: route) {
                            RankedPosterCard(rank: index + 1, title: item.title, poster: item.poster).titleZoomSource(route)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, DS.Space.gutter, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
        }
    }

    /// «Por género»: los géneros en mosaicos con su arte, bajo un encabezado igual al de arriba (una sola pantalla, no dos).
    private var explore: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            DSSectionHead(title: "Por género", icon: .spark)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: DS.Space.s3), GridItem(.flexible(), spacing: DS.Space.s3)], spacing: DS.Space.s3) {
                ForEach(CatalogModel.exploreGenres, id: \.self) { genre in
                    NavigationLink(value: GenreRoute(genre: genre)) { ArtTile(title: Text(verbatim: genreName(genre)), asset: Self.genreAsset(genre)) }
                        .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, DS.Space.gutter)
    }

    private func genreName(_ genre: String) -> String { Vocabulary.genres([genre], language: env.services.appSettings.uiLanguage).first ?? genre }

    /// El arte fijo de cada género (Grok Imagine, en el catálogo de la app): se ve al instante, sin red.
    static func genreAsset(_ genre: String) -> String { "genre-" + genre.lowercased().filter { $0.isLetter || $0.isNumber } }
}

/// Un género de Explora: lo más popular de ese género, películas y series, en cuadrícula.
struct GenreView: View {
    let genre: String
    let model: CatalogModel
    @EnvironmentObject private var env: AppEnvironment
    @State private var items: [CatalogItem] = []
    @State private var loaded = false

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: DS.Poster.gridMinimum), spacing: DS.Space.s3)], spacing: DS.Space.s4) {
                ForEach(items) { item in
                    TitleLink(route: TitleRoute(kind: item.kind, metaID: item.metaID, title: item.title, poster: item.poster), width: DS.Poster.gridMinimum,
                              detail: yearAndKind(year: item.year, kind: item.kind))
                }
            }
            .padding(.horizontal, DS.Space.gutter).padding(.bottom, DS.Space.s8)
            .overlay { if !loaded { ProgressView() } }
        }
        .background(Backdrop())
        .navigationTitle(Text(verbatim: Vocabulary.genres([genre], language: env.services.appSettings.uiLanguage).first ?? genre))
        .toolbarTitleDisplayMode(.inlineLarge)   // el título grande en el renglón de los botones: no se pierde un renglón arriba
        .task {
            // Primero lo de Cinemeta (se ve ya); luego los mismos títulos en tu idioma.
            await model.genre(genre) { items = $0; loaded = true }
            loaded = true
        }
    }
}
