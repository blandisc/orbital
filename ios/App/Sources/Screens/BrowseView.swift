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
    /// Los resultados: todo, solo películas o solo series.
    @State private var kind: String = ""
    /// «Ver todo» de lo más popular hoy.
    @State private var showPopular = false
    @Environment(\.dynamicTypeSize) private var typeSize
    /// Los colores del n.º 1 de hoy: el fondo de la pantalla y las cifras del Top 10 toman su tono (como Inicio).
    @State private var tint: ArtTint
    /// El póster que ilustra cada género (el primero de su catálogo), según van llegando.

    // BOCETO (exp/explorar-genero-temporada): «Lo mejor del género» y «Por temporada». Ver docs/bocetos/explorar-genero-temporada.md.
    /// El género elegido en «Lo mejor del género» (nombre de Cinemeta) y sus mejor calificados.
    @State private var topGenre = BrowseChip(id: CatalogModel.exploreGenres[0])
    @State private var topRated: [CatalogItem] = []
    @State private var topLoaded = false
    /// Las temporadas, la de hoy (o la siguiente) primero, y la elegida.
    @State private var seasons = Seasons.ordered(on: Date())
    @State private var season = BrowseChip(id: "")

    /// Cuántos de lo más popular van en el carrusel con puesto (un Top 10).
    private static let popularCount = 10

    init() {
        let services = AppEnvironment.shared.services
        _catalog = State(wrappedValue: ModelObserver(AppEnvironment.shared.catalog))
        _tint = State(wrappedValue: ArtTint(cachedFor: AppEnvironment.shared.catalog.popular.first?.poster))
        _search = State(wrappedValue: ModelObserver(SearchModel(services)))
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Editorial.sectionGap) {
                    if query.trimmingCharacters(in: .whitespaces).count >= 2 { results } else { suggestions }
                }
                .padding(.top, DS.Space.s3)   // el mismo aire bajo el título que Inicio y Para ti
                .padding(.bottom, DS.Space.s8)
            }
            .task { await demoScroll(proxy) }
        }
        // El contenido conserva tu tamaño de letra (el de afuera); solo el campo y la barra se topan abajo.
        .environment(\.dynamicTypeSize, typeSize)
        .background(Backdrop(tint: tint.colors))
        .task(id: catalog.model.popular.first?.poster) { await tint.load(catalog.model.popular.first?.poster) }
        .navigationTitle("Buscar").toolbarTitleDisplayMode(.inlineLarge)   // el título grande en el renglón de los botones: no se pierde un renglón arriba
        .searchable(text: $query, prompt: Text("Películas y series"))
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
            if Demo.isOn, let genre = Demo.genreTop, CatalogModel.exploreGenres.contains(genre) { topGenre = BrowseChip(id: genre) }
            if Demo.isOn, let forced = Demo.season { seasons = Seasons.ordered(on: Date(), forced: forced) }
            #endif
            if season.id.isEmpty { season = BrowseChip(id: seasons.first?.id ?? "") }
            async let warm: Void = env.services.cinemeta.warmUp()   // la conexión con Cinemeta lista antes de la primera letra
            if catalog.model.popular.isEmpty { await catalog.model.load() }   // ya se pidió al abrir la app
            await warm
        }
        .task(id: topGenre) {
            topLoaded = false
            let items = await catalog.model.topRated(genre: topGenre.id)
            guard !Task.isCancelled else { return }
            topRated = items; topLoaded = true
        }
        .refreshable { await catalog.model.load() }
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
        seasonal.id(BrowseAnchor.season)
        genreTop.id(BrowseAnchor.genre)
        explore
    }

    // MARK: boceto — «Por temporada» y «Lo mejor del género»

    /// «Por temporada»: colecciones de Halloween, Navidad, San Valentín…, la de hoy primero (`Seasons.ordered`).
    /// BOCETO: los títulos de cada temporada son una lista de ejemplo escrita a mano (`Seasons.all`), no una API.
    @ViewBuilder private var seasonal: some View {
        let shown = seasons.first { $0.id == season.id } ?? seasons.first
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            DSSectionHead(title: "Por temporada", meta: shown.map { Text(LocalizedStringKey($0.blurb)) })
                .padding(.horizontal, DS.Space.gutter)
            DSChipRow(items: seasons.map { BrowseChip(id: $0.id) }, label: { chip in
                let s = seasons.first { $0.id == chip.id }
                Label(LocalizedStringKey(s?.title ?? chip.id), systemImage: s?.symbol ?? "calendar")
            }, selection: $season)
            if let shown {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: DS.Space.s3) {
                        ForEach(shown.picks, id: \.metaID) { pick in
                            TitleLink(route: TitleRoute(kind: pick.kind, metaID: pick.metaID, title: pick.title, poster: pick.poster))
                        }
                    }
                    .scrollTargetLayout()
                    .environment(\.posterCaptions, false)
                }
                .contentMargins(.horizontal, DS.Space.gutter, for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
                .id(shown.id)   // otra temporada empieza desde su primer póster
            }
        }
    }

    /// «Lo mejor del género»: un selector de géneros y los 10 mejor calificados (IMDb, vía Cinemeta) con su puesto.
    private var genreTop: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            DSSectionHead(title: "Lo mejor del género", meta: Text("Los mejor calificados en IMDb, películas y series"), source: .stremio)
                .padding(.horizontal, DS.Space.gutter)
            DSChipRow(items: CatalogModel.exploreGenres.map { BrowseChip(id: $0) }, label: { Text(verbatim: genreName($0.id)) }, selection: $topGenre)
            if topLoaded && topRated.isEmpty {
                DSNotice(verbatim: Strings.tr("No pude leer este género. Revisa tu conexión.", language: env.services.appSettings.uiLanguage), tone: .warn)
                    .padding(.horizontal, DS.Space.gutter)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: DS.Space.s3) {
                        if !topLoaded { ShelfSkeleton() }
                        else {
                            ForEach(Array(topRated.enumerated()), id: \.element.id) { index, item in
                                let route = TitleRoute(kind: item.kind, metaID: item.metaID, title: item.title, poster: item.poster)
                                NavigationLink(value: route) {
                                    RankedPosterCard(rank: index + 1, title: item.title, poster: item.poster, tint: tint.colors?.accent).titleZoomSource(route)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.horizontal, DS.Space.gutter, for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
                .id(topGenre.id)   // otro género empieza desde el n.º 1
            }
        }
    }

    /// Modo demostración (`-demo-browse-scroll genero|temporada`): baja hasta esa fila al abrir, para las capturas.
    private func demoScroll(_ proxy: ScrollViewProxy) async {
        #if DEBUG
        guard Demo.isOn, let id = Demo.browseScroll else { return }
        try? await Task.sleep(for: .seconds(2))
        proxy.scrollTo(id == "temporada" ? BrowseAnchor.season : BrowseAnchor.genre, anchor: .top)
        #endif
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

/// Una opción de los filtros del boceto de Buscar (un género de Cinemeta o el id de una temporada).
struct BrowseChip: Hashable, Identifiable { var id: String }

/// Las filas del boceto a las que salta `-demo-browse-scroll`.
enum BrowseAnchor { static let genre = "browse-genero", season = "browse-temporada" }

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
