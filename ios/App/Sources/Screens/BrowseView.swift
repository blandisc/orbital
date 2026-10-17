import SwiftUI
import OrbitalCore
import OrbitalModels

/// Un género de «Explora» al que se navega (nombre de Cinemeta, en inglés).
struct GenreRoute: Hashable { var genre: String }

/// «Buscar» (la pestaña de búsqueda nativa de iOS 26): sin escribir, lo más popular hoy con su puesto y los géneros para
/// explorar; al escribir, los resultados en cuadrícula.
struct BrowseView: View {
    @EnvironmentObject private var env: AppEnvironment
    @StateObject private var catalog: ModelObserver<CatalogModel>
    @StateObject private var search: ModelObserver<SearchModel>
    @State private var query = ""
    /// El póster que ilustra cada género (el primero de su catálogo), según van llegando.
    @State private var genreArt: [String: String] = [:]

    /// Cuántos de lo más popular van en la lista con puesto.
    private static let popularCount = 5
    /// Cuántas películas de cada género se consideran para su arte (para no repetir la de otro género).
    private static let genreArtCandidates = 6

    init() {
        let services = AppEnvironment.shared.services
        _catalog = StateObject(wrappedValue: ModelObserver(CatalogModel(services)))
        _search = StateObject(wrappedValue: ModelObserver(SearchModel(services)))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s8) {
                if query.trimmingCharacters(in: .whitespaces).count >= 2 { results } else { suggestions }
            }
            .padding(.bottom, DS.Space.s8)
        }
        .background(Backdrop())
        .navigationTitle("Buscar").toolbarTitleDisplayMode(.inlineLarge)   // el título grande en el renglón de los botones: no se pierde un renglón arriba
        .searchable(text: $query, prompt: Text("Películas y series"))
        .titleDestinations()
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
        .task { await loadGenreArt() }
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
            ForEach(model.results) { r in
                TitleLink(route: TitleRoute(kind: r.kind, metaID: r.metaID, title: r.title, poster: r.poster), width: DS.Poster.gridMinimum,
                          detail: yearAndKind(year: r.year, kind: r.kind))
                    .simultaneousGesture(TapGesture().onEnded { model.remember(query) })
            }
        }
        .padding(.horizontal, DS.Space.gutter)
        .overlay { if !answered && model.results.isEmpty && model.error == nil { ProgressView() } }
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

    /// «Lo más popular hoy»: renglones con su puesto (películas y series alternadas, de Cinemeta).
    private func popular(_ model: CatalogModel) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            DSSectionHead(title: "Lo más popular hoy")
            let shown = Array(model.popular.prefix(Self.popularCount))
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, item in
                NavigationLink(value: TitleRoute(kind: item.kind, metaID: item.metaID, title: item.title, poster: item.poster)) {
                    RankedRow(rank: index + 1, title: item.title, poster: item.poster, detail: yearAndKind(year: item.year, kind: item.kind))
                }
                .buttonStyle(.plain)
                if index < shown.count - 1 { Divider().overlay(DS.hairline) }
            }
        }
        .padding(.horizontal, DS.Space.gutter)
    }

    /// «Explora»: los géneros en mosaicos con el arte de su título más popular.
    private var explore: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            DSSectionHead(title: "Explora")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: DS.Space.s3), GridItem(.flexible(), spacing: DS.Space.s3)], spacing: DS.Space.s3) {
                ForEach(CatalogModel.exploreGenres, id: \.self) { genre in
                    NavigationLink(value: GenreRoute(genre: genre)) { ArtTile(title: Text(verbatim: genreName(genre)), art: genreArt[genre]) }
                        .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, DS.Space.gutter)
    }

    private func genreName(_ genre: String) -> String { Vocabulary.genres([genre], language: env.services.appSettings.uiLanguage).first ?? genre }

    /// El arte de cada género: el fondo de su película más popular que no use ya otro género (un mismo título es drama y
    /// suspenso a la vez; sin esto, dos mosaicos salían con la misma imagen). Todos a la vez; la fila de imágenes hace el resto.
    private func loadGenreArt() async {
        let cinemeta = env.services.cinemeta, perGenre = Self.genreArtCandidates
        var candidates: [String: [String]] = [:]
        await withTaskGroup(of: (String, [String]).self) { group in
            for genre in CatalogModel.exploreGenres {
                group.addTask {
                    let ids = ((try? await cinemeta.catalog("movie", genre: genre)) ?? []).prefix(perGenre).compactMap { $0["id"]?.string }
                    return (genre, ids)
                }
            }
            for await (genre, ids) in group { candidates[genre] = ids }
        }
        var used = Set<String>()
        for genre in CatalogModel.exploreGenres {
            guard let ids = candidates[genre], let id = ids.first(where: { !used.contains($0) }) ?? ids.first else { continue }
            used.insert(id)
            genreArt[genre] = String(format: ForYou.metahubBackground, id)
        }
    }
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
            items = await model.genre(genre)
            loaded = true
        }
    }
}
