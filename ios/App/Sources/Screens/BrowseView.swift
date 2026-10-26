import SwiftUI
import OrbitalCore
import OrbitalModels

/// Un género de «Explora» al que se navega (nombre de Cinemeta, en inglés).
struct GenreRoute: Hashable { var genre: String }

/// «Buscar» (la pestaña de búsqueda nativa de iOS 26): sin escribir, el Top 10 de hoy en carrusel y los géneros para
/// explorar; al escribir, los resultados en cuadrícula.
struct BrowseView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var catalog: ModelObserver<CatalogModel>
    @State private var search: ModelObserver<SearchModel>
    @State private var query = ""
    /// El campo abierto (con el teclado). Un segundo toque en la lupa cae en el campo y lo abre (iOS); si iOS avisa que
    /// tocaste «Buscar» otra vez (RootView), también se abre desde aquí.
    @State private var searching = false
    private let ui = AppEnvironment.shared.ui
    /// La barra de abajo (con el campo) se esconde al bajar y vuelve al subir: iOS no la encoge en la pestaña de búsqueda.
    @State private var barHidden = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Los resultados: todo, solo películas o solo series.
    @State private var kind: String = ""
    /// «Ver todo» de lo más popular hoy.
    @State private var showPopular = false
    @Environment(\.dynamicTypeSize) private var typeSize
    /// Los colores del n.º 1 de hoy: el fondo de la pantalla y las cifras del Top 10 toman su tono (como Inicio).
    @State private var tint: ArtTint
    /// El póster que ilustra cada género (el primero de su catálogo), según van llegando.

    /// Cuántos de lo más popular van en el carrusel con puesto (un Top 10).
    private static let popularCount = 10

    init() {
        let services = AppEnvironment.shared.services
        _catalog = State(wrappedValue: ModelObserver(AppEnvironment.shared.catalog))
        _tint = State(wrappedValue: ArtTint(cachedFor: AppEnvironment.shared.catalog.popular.first?.poster))
        _search = State(wrappedValue: ModelObserver(SearchModel(services)))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Editorial.sectionGap) {
                if query.trimmingCharacters(in: .whitespaces).count >= 2 { results } else { suggestions }
            }
            .padding(.top, DS.Space.s3)   // el mismo aire bajo el título que Inicio y Para ti
            .padding(.bottom, DS.Space.s8)
        }
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { old, y in
            let hide: Bool
            if searching || y <= DS.Size.barScrollHide { hide = false }   // escribiendo o arriba del todo: siempre a la vista
            else if y - old > DS.Size.barScrollHide { hide = true }
            else if old - y > DS.Size.barScrollHide { hide = false }
            else { return }
            if hide != barHidden { withAnimation(DS.Motion.base(reduceMotion)) { barHidden = hide } }
        }
        .onChange(of: searching) { _, open in if open { barHidden = false } }
        .toolbarVisibility(barHidden ? .hidden : .visible, for: .tabBar)
        // El contenido conserva tu tamaño de letra (el de afuera); solo el campo y la barra se topan abajo.
        .environment(\.dynamicTypeSize, typeSize)
        .background(Backdrop(tint: tint.colors))
        .task(id: catalog.model.popular.first?.poster) { await tint.load(catalog.model.popular.first?.poster) }
        .navigationTitle("Buscar").toolbarTitleDisplayMode(.inlineLarge)   // el título grande en el renglón de los botones: no se pierde un renglón arriba
        // La barra siempre a la vista al abrir Buscar (antes, a veces había que bajar para que saliera).
        .searchable(text: $query, isPresented: $searching, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("Películas y series"))
        .onChange(of: ui.focusSearch, initial: true) { _, wants in
            guard wants else { return }
            ui.focusSearch = false
            searching = true
        }
        // Nombres propios: sin autocorrector ni mayúscula automática («Shōgun» no se vuelve «Shotgun»); al deslizar los
        // resultados, el teclado se va para verlos.
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .scrollDismissesKeyboard(.immediately)
        .onChange(of: query) { kind = "" }   // otra búsqueda empieza con «Todo» (un filtro viejo dejaba la pantalla en blanco)
        // El campo vive abajo (pestaña de búsqueda, como Trakt); al escribir, el título se queda arriba y los resultados
        // empiezan bajo él (antes la barra se escondía y lo de arriba chocaba con la hora).
        .searchPresentationToolbarBehavior(.avoidHidingContent)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { ProfileButton() } }
        .titleDestinations()
        .navigationDestination(for: SettingsRoute.self) { _ in SettingsView() }
        .navigationDestination(for: GenreRoute.self) { GenreView(genre: $0.genre, model: catalog.model) }
        .navigationDestination(isPresented: $showPopular) { PopularGridView(model: catalog.model) }
        .task(id: query) {
            if query.count >= 2 { Perf.begin("search") }
            try? await Task.sleep(nanoseconds: DS.Timing.searchDebounce)    // espera a que termines de escribir
            guard !Task.isCancelled else { return }
            await search.model.search(query)
        }
        .task {
            #if DEBUG
            if Demo.isOn, let text = Demo.search { query = text }
            #endif
            async let warm: Void = env.services.cinemeta.warmUp()   // la conexión con Cinemeta lista antes de la primera letra
            if catalog.model.popular.isEmpty { await catalog.model.load() }   // ya se pidió al abrir la app
            await warm
        }
        .refreshable { await catalog.model.load() }
        .onAppear { Perf.mark("stab.appear") }   // con `-perf`: de tocar Buscar a verla (marca `stab.tap` en RootView)
        // ds-exception: el campo de búsqueda del sistema se dibuja vacío con letra de accesibilidad (el texto sí está):
        // se topa en el tamaño más grande que sí pinta.
        .dynamicTypeSize(...DS.Typeface.searchFieldMax)
    }

    // MARK: resultados
    @ViewBuilder private var results: some View {
        let model = search.model
        // «Sin resultados» solo cuando ya contestó la búsqueda de lo que está escrito (no durante la espera de la última letra).
        let answered = !model.isSearching && model.searchedQuery == query.trimmingCharacters(in: .whitespacesAndNewlines)
        if let error = model.error, answered { DSNotice(verbatim: env.message(error), tone: .warn).padding(.horizontal, DS.Space.gutter) }
        else if model.results.isEmpty && answered { DSEmptyState(symbol: "magnifyingglass", title: Text("Sin resultados"), message: Text("Nada con «\(query)». Prueba con otro nombre.")) }
        let shown = kind.isEmpty ? model.results : model.results.filter { $0.kind == kind }
        let movieCount = model.results.filter { $0.kind == "movie" }.count, seriesCount = model.results.filter { $0.kind == "series" }.count
        if model.results.count > 1 || !kind.isEmpty {
            // Todo · Películas · Series (cuántas de cada una): el filtro de toda la app.
            DSKindFilter(kind: $kind, counts: (movieCount, seriesCount)).padding(.horizontal, DS.Space.gutter)
        }
        // El que mejor coincide, en grande (con su arte), como el primer resultado de Apple TV.
        if let top = shown.first, top.metaID.hasPrefix("tt") {
            let route = TitleRoute(kind: top.kind, metaID: top.metaID, title: top.title, poster: top.poster)
            NavigationLink(value: route) {
                CoverCard(art: String(format: ForYou.metahubBackground, top.metaID), logo: Artwork.logoURL(metaID: top.metaID), title: top.title,
                          why: Text("Mejor resultado"), detail: yearAndKind(year: top.year, kind: top.kind), height: DS.Size.searchTopHeight)
            }
            .perfTag("search.top")
            .buttonStyle(.plain).padding(.horizontal, DS.Space.gutter)
            .simultaneousGesture(TapGesture().onEnded { model.remember(query) })
        }
        if answered, !model.results.isEmpty, shown.isEmpty {
            DSEmptyState(symbol: "line.3.horizontal.decrease.circle", title: Text("Nada de ese tipo"), message: Text("Prueba con «Todo»."))
        }
        if !answered && model.results.isEmpty && model.error == nil {
            // Mientras llega: pósters vacíos en su lugar (antes, una ruedita sobre la barra de arriba).
            DSPosterGrid(items: DSPosterSlot.slots(9)) { _, width in
                RoundedRectangle(cornerRadius: DS.Radius.md).fill(DS.fill).frame(width: width).aspectRatio(DS.Poster.aspect, contentMode: .fit)
            }
            .accessibilityHidden(true)
        }
        DSPosterGrid(items: shown.first?.metaID.hasPrefix("tt") == true ? Array(shown.dropFirst()) : shown) { r, width in
            // Con letra de accesibilidad, el año y el tipo en dos renglones (en uno se cortaban).
            TitleLink(route: TitleRoute(kind: r.kind, metaID: r.metaID, title: r.title, poster: r.poster), width: width,
                      detail: yearAndKind(year: r.year, kind: r.kind), detailLines: typeSize.isAccessibilitySize ? 2 : 1)
                .perfTag("search.grid")
                .simultaneousGesture(TapGesture().onEnded { model.remember(query) })
        }
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

    /// Lo que buscaste, en cápsulas bajo el título (un toque lo vuelve a buscar); «Borrar» al final.
    private var recent: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            Text("Buscaste hace poco").recipe(.footnote).padding(.horizontal, DS.Space.gutter)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Space.s2) {
                    ForEach(search.model.recent, id: \.self) { text in
                        PanelChip(title: Text(verbatim: text), selected: false, symbol: "clock.arrow.circlepath") { query = text }
                    }
                    Button("Borrar") { search.model.clearRecent() }
                        .font(DS.TextRecipe.footnote.font).foregroundStyle(DS.textMuted).buttonStyle(.borderless)
                }
            }
            .contentMargins(.horizontal, DS.Space.gutter, for: .scrollContent)
        }
    }

    /// «Lo más popular hoy»: el Top 10 de Stremio en carrusel, con la cifra grande (el mismo lenguaje que los rankings de
    /// tus plataformas). Películas y series alternadas, de Cinemeta.
    private func popular(_ model: CatalogModel) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            DSSectionHead(title: "Lo más popular hoy", action: { showPopular = true }, chevron: true,
                          meta: Text("Lo que más se ve hoy en Stremio, películas y series"), source: .stremio)
                .padding(.horizontal, DS.Space.gutter)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: DS.Space.s3) {
                    ForEach(Array(model.popular.prefix(Self.popularCount).enumerated()), id: \.element.id) { index, item in
                        let route = TitleRoute(kind: item.kind, metaID: item.metaID, title: item.title, poster: item.poster)
                        NavigationLink(value: route) {
                            RankedPosterCard(rank: index + 1, title: item.title, poster: item.poster, tint: tint.colors?.accent).titleZoomSource(route)
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
            DSSectionHead(title: "Por género", meta: Text("Lo más popular de cada uno"))
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
    @Environment(AppEnvironment.self) private var env
    @State private var items: [CatalogItem] = []
    @State private var loaded = false

    var body: some View {
        ScrollView {
            // Con el mismo ordenar y filtrar que todo «Ver todo».
            SortableGrid(listID: "genre:\(genre)", items: items.map(Self.suggestion), loading: !loaded) { s, width in
                TitleLink(route: TitleRoute(kind: s.kind, metaID: s.imdb, title: s.title, poster: s.poster.isEmpty ? nil : s.poster), width: width,
                          detail: yearAndKind(year: s.year.map(String.init) ?? "", kind: s.kind))
            }
            .padding(.top, DS.Space.s3)
            .padding(.bottom, DS.Space.s8)
        }
        .background(Backdrop())
        .navigationTitle(Text(verbatim: Vocabulary.genres([genre], language: env.services.appSettings.uiLanguage).first ?? genre))
        .navigationBarTitleDisplayMode(.inline)   // como toda pantalla de adentro
        .task {
            // Primero lo de Cinemeta (se ve ya); luego los mismos títulos en tu idioma.
            await model.genre(genre) { items = $0; loaded = true }
            loaded = true
        }
    }

    static func suggestion(_ item: CatalogItem) -> Suggestion {
        Suggestion(kind: item.kind, imdb: item.metaID, title: item.title, year: Int(item.year.prefix(4)), poster: item.poster ?? "", wide: "", reason: .popular)
    }
}

/// «Lo más popular hoy» completo (desde su «Ver todo»): con el mismo ordenar y filtrar que toda lista.
struct PopularGridView: View {
    let model: CatalogModel

    var body: some View {
        ScrollView {
            SortableGrid(listID: "popular", items: model.popular.map(GenreView.suggestion), loading: model.isLoading) { s, width in
                TitleLink(route: s.route, width: width, detail: yearAndKind(year: s.year.map(String.init) ?? "", kind: s.kind))
            }
            .padding(.top, DS.Space.s3)
            .padding(.bottom, DS.Space.s8)
        }
        .background(Backdrop())
        .navigationTitle("Lo más popular hoy").navigationBarTitleDisplayMode(.inline)
    }
}
