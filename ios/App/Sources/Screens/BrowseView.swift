import SwiftUI
import OrbitalCore
import OrbitalModels

/// Un género de «Explora» al que se navega (nombre en inglés: `CatalogModel.traktGenre` lo pasa a Trakt).

/// Cuánto se ha bajado en una lista, sin avisar a SwiftUI (no es `@Observable`).
private final class ScrollOffset {
    var y: CGFloat = 0
    /// Dónde cambiaste de dirección por última vez: lo que llevas bajando (o subiendo) se cuenta desde ahí.
    var turn: CGFloat = 0
    /// Tu dedo arrastra o la lista sigue por el impulso: solo eso mueve la barra.
    var byYou = false
    /// Tu dedo está en la pantalla: solo así vuelve la barra (el impulso y el rebote del final no la traen).
    var dragging = false
}

/// Dónde vas en la lista y hasta dónde se puede bajar (cambia cuando la barra se esconde o vuelve).
private struct ScrollSpot: Equatable { var y: CGFloat; var bottom: CGFloat }

/// «Buscar» (la pestaña de búsqueda nativa de iOS 26): sin escribir, solo la puerta del filtro avanzado, lo que buscaste
/// y los géneros (BX, Fernando, 9 nov 2026: lo más popular hoy se fue a Explorar); al escribir, los resultados en cuadrícula.
struct BrowseView: View {
    @Environment(\.titleName) var titleName
    @Environment(AppEnvironment.self) private var env
    @State private var catalog: ModelObserver<CatalogModel>
    @State private var search: ModelObserver<SearchModel>
    @State private var query = ""
    /// El filtro avanzado (el cajón) y el título que abrió desde sus resultados.
    @State private var showFilter = false
    /// El filtro que tocaste en la puerta (el cajón abre ahí); nil, el cajón completo.
    @State private var filterStart: FilterPage?
    /// Los resultados del filtro, en su propia pantalla (se abren al tocar «Ver resultados»).
    @State private var showResults = false
    @State private var openTitle: TitleRoute?
    /// El campo abierto (con el teclado). Un segundo toque en la lupa cae en el campo y lo abre (iOS); si iOS avisa que
    /// tocaste «Buscar» otra vez (RootView), también se abre desde aquí.
    @State private var searching = false
    /// El cursor en el campo. Al bajar, la barra se esconde aunque el campo esté abierto (antes se quedaba fija) y lo
    /// suelta: con el campo vacío, iOS esconde el teclado pero deja el cursor ahí.
    @FocusState private var typing: Bool
    /// Cuánto has bajado: al irse el teclado ya abajo, la barra se esconde sin esperar otro deslizamiento. (En una caja:
    /// cambia en cada cuadro del deslizamiento y no debe volver a pintar la pantalla.)
    @State private var scroll = ScrollOffset()
    private let ui = AppEnvironment.shared.ui
    /// Con el campo abierto, la barra de arriba (título y campo) se esconde al bajar por los resultados y vuelve al subir.
    /// La de pestañas no: siempre completa (2 nov 2026).
    @State private var barHidden = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Los resultados: todo, solo películas o solo series.
    @State private var kind: String = ""
    @Environment(\.dynamicTypeSize) private var typeSize
    /// Los colores del n.º 1 de hoy: el fondo de la pantalla toma su tono (como Inicio).
    @State private var tint: ArtTint

    init() {
        let services = AppEnvironment.shared.services
        _catalog = State(wrappedValue: ModelObserver(AppEnvironment.shared.catalog))
        _tint = State(wrappedValue: ArtTint(cachedFor: AppEnvironment.shared.catalog.popular.first?.poster))
        _search = State(wrappedValue: ModelObserver(SearchModel(services)))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Layout.betweenSections) {
                if query.trimmingCharacters(in: .whitespaces).count >= 2 { results } else { suggestions }
            }
            // Al poner el primer filtro (o quitar el último) los mosaicos de la puerta crecen o se encogen: lo de abajo (el Top 10,
            // los géneros) se recorre con el mismo resorte, sin brincar (Fernando, 2 nov 2026, K5).
            .animation(DS.Motion.smooth(reduceMotion), value: FilterTile.compact(FilterContext(filter: env.advancedFilter.filter)))
            .refreshOrbitHost()   // la luna de tirar para actualizar
            .padding(.top, DS.Space.s3)   // el mismo aire bajo el título que Inicio y Para ti
            .padding(.bottom, DS.Layout.screenBottom)
        }
        // Solo el desplazamiento de verdad: el rebote al final de la página (que se pasa y regresa) no cuenta como subir.
        .onScrollGeometryChange(for: ScrollSpot.self) { g in
            let bottom = max(g.contentSize.height + g.contentInsets.top + g.contentInsets.bottom - g.containerSize.height, 0)
            return ScrollSpot(y: min(g.contentOffset.y + g.contentInsets.top, bottom), bottom: bottom)
        } action: { before, now in
            let old = before.y, y = now.y
            scroll.y = y
            // Si iOS reacomoda al esconder o mostrar la barra, no cuenta: antes, al llegar al final, la barra se
            // escondía, el contenido se reacomodaba y volvía a salir.
            // Arriba del todo, siempre a la vista (también al volver arriba tocando la hora).
            if y <= DS.Size.barScrollHide {
                scroll.turn = y
                if barHidden { withAnimation(DS.Motion.base(reduceMotion)) { barHidden = false } }
                return
            }
            // Cambió el alto de la pantalla (la barra se fue o volvió) o no lo moviste tú: no cuenta.
            guard scroll.byYou, before.bottom == now.bottom else { scroll.turn = y; return }
            // Lo recorrido desde el último cambio de dirección, no de un cuadro al otro: a 120 cuadros por segundo
            // (ProMotion) cada cuadro avanza poco y la barra nunca se iba.
            if (y > old) != (old > scroll.turn) { scroll.turn = old }
            let hide: Bool
            if y - scroll.turn > DS.Size.barScrollHide { hide = true; typing = false }   // al bajar se va, con el campo abierto o no
            else if typing { return }   // con el teclado arriba, el campo no se mueve
            // Vuelve solo si tu dedo sube la lista: al llegar al final, el rebote regresa unos puntos y la barra se
            // quedaba brincando entre salir y esconderse.
            else if scroll.dragging, scroll.turn - y > DS.Size.barScrollHide { hide = false }
            else { return }
            if hide != barHidden { withAnimation(DS.Motion.base(reduceMotion)) { barHidden = hide } }
        }
        // El campo regresa con la barra al subir: con el borde suave, los filtros y los mosaicos se veían a través de él,
        // como si el campo estuviera encima (Fernando, 13 nov 2026). Con el borde firme, lo que pasa por debajo se tapa,
        // como en Inicio. Regla «Una barra que flota sobre contenido lo tapa».
        .scrollEdgeEffectStyle(.hard, for: .top)
        .onScrollPhaseChange { _, phase in
            scroll.byYou = phase == .interacting || phase == .decelerating
            scroll.dragging = phase == .interacting
        }
        .onChange(of: searching) { _, open in if open { barHidden = false } }
        .onChange(of: typing) { _, up in
            let hide = !up && scroll.y > DS.Size.barScrollHide   // el teclado se fue al deslizar hacia abajo
            if hide != barHidden { withAnimation(DS.Motion.base(reduceMotion)) { barHidden = hide } }
        }
        // La barra de pestañas ya no se esconde al bajar: siempre completa, como en toda la app (2 nov 2026).
        // Con el campo abierto, iOS 27 lo deja fijo arriba: al bajar por los resultados se va también la barra de arriba
        // (título y campo) y vuelve al subir, con lo escrito.
        .toolbarVisibility(barHidden && searching ? .hidden : .visible, for: .navigationBar)
        // El contenido conserva tu tamaño de letra (el de afuera); solo el campo y la barra se topan abajo.
        .environment(\.dynamicTypeSize, typeSize)
        .background(Backdrop(tint: tint.colors))
        .task(id: catalog.model.popular.first?.poster) { await tint.load(catalog.model.popular.first?.poster) }
        .navigationTitle("Buscar").toolbarTitleDisplayMode(.inlineLarge)   // el título grande en el renglón de los botones: no se pierde un renglón arriba
        // Siempre a la vista (revisión del 11 nov): con `.automatic`, en iOS 27 el campo solo salía al jalar hacia abajo y,
        // ya con texto, no se veía qué buscaste. Al bajar por los resultados se va con la barra de arriba y vuelve al subir.
        .searchable(text: $query, isPresented: $searching, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("Películas y series"))
        .searchFocused($typing)
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
        // Al tocar el campo, iOS sube el campo bajo la hora y esconde el título (como en las apps de Apple). Antes se pedía
        // `.searchPresentationToolbarBehavior(.avoidHidingContent)` para dejar el título, y en iOS 27 la lupa y el texto
        // brincaban de lugar al abrir el campo.
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { ProfileButton() }
        }
        .advancedFilter(isPresented: $showFilter, start: filterStart) { showResults = true }
        .learnCoach(.advancedSearch, title: "Búsqueda avanzada", detail: "Junta filtros: comedias de los 90, en Netflix, con más de 7.",
                    used: env.advancedFilter.count != nil)
        .onChange(of: env.ui.openAdvancedFilter, initial: true) { _, open in
            guard open else { return }
            env.ui.openAdvancedFilter = false; filterStart = nil; showFilter = true
        }
        .navigationDestination(isPresented: $showResults) {
            FilterResultsView(model: env.advancedFilter) { page in
                filterStart = page
                showFilter = true
            }
        }
        .openingTitles(item: $openTitle)
        .titleDestinations()
        .navigationDestination(for: SettingsRoute.self) { _ in SettingsView() }
        .task(id: query) {
            if query.count >= 2 { Perf.begin("search") }
            try? await Task.sleep(nanoseconds: DS.Timing.searchDebounce)    // espera a que termines de escribir
            guard !Task.isCancelled else { return }
            await search.model.search(query)
        }
        .task {
            #if DEBUG
            if Demo.isOn, let text = Demo.search { query = text }
            // `-demo-filter series|awards`: un filtro ya puesto, para capturar los mosaicos encendidos.
            if Demo.isOn, let sample = Demo.value(after: "-demo-filter") {
                var f = AdvancedFilter()
                if sample == "awards" { f.awards = ["oscar", "palm"]; f.years = 1990...1999; f.format = .movie }
                else if sample == "recent" { f.years = f.releases; f.format = .movie }
                else if sample == "rating" { f.format = .movie; f.minRating = 7.5; f.minLetterboxd = 3.8 }   // las dos opiniones
                else if sample == "rating-lb" { f.minLetterboxd = 4.2 }   // solo los cinéfilos
                else { f.format = .series; f.seriesStatus = .airing; f.genres = ["crimen", "drama"]; f.years = 2010...2019; f.minRating = 7.5; f.fame = .gems; f.countries = ["KR", "JP"]; f.length = .before }
                env.advancedFilter.filter = f
            }
            if Demo.isOn, Demo.open == "filter-results" { showResults = true }   // `-demo-open filter-results`: los resultados
            else if Demo.isOn, let open = Demo.open, open.hasPrefix("filter") {   // `-demo-open filter` (o filter-genre…): el cajón
                Task { try? await Task.sleep(for: .seconds(3)); filterStart = FilterPage(door: open == "filter" ? nil : String(open.dropFirst(7))); showFilter = true }   // Demo: espera a que cargue Buscar
            }
            #endif
            async let warm: Void = env.services.cinemeta.warmUp()   // la conexión con Cinemeta lista antes de la primera letra
            if catalog.model.popular.isEmpty { await catalog.model.load() }   // ya se pidió al abrir la app
            await warm
        }
        .orbitalRefreshable { await catalog.model.load() }
        .onAppear { Perf.mark("stab.appear") }   // con `-perf`: de tocar Buscar a verla (marca `stab.tap` en RootView)
        // ds-exception: el campo de búsqueda del sistema se dibuja vacío con letra de accesibilidad (el texto sí está):
        // se topa en el tamaño más grande que sí pinta.
        .dynamicTypeSize(...DS.Typeface.searchFieldMax)
    }

    // MARK: resultados
    @ViewBuilder private var results: some View {
        let model = search.model
        // El modelo dice en qué va lo escrito: una búsqueda siempre termina (con resultados, sin ellos o con «Reintentar»).
        let status = model.status(for: query)
        let answered = status != .waiting
        switch status {
        case .failed(let error):
            DSEmptyState(symbol: "exclamationmark.triangle", title: Text("No se pudo buscar"), message: Text(verbatim: env.message(error))) {
                Button("Reintentar", systemImage: "arrow.clockwise") { Task { await model.search(query) } }
            }
        case .empty:
            DSEmptyState(symbol: "magnifyingglass", title: Text("Sin resultados"),
                         message: Text("Nada con «\(query.trimmingCharacters(in: .whitespaces))». Revisa cómo se escribe o prueba con el nombre original.")) {
                Button("Búsqueda avanzada", systemImage: "slider.horizontal.3") { filterStart = nil; showFilter = true }
            }
        default: EmptyView()
        }
        let shown = kind.isEmpty ? model.results : model.results.filter { $0.kind == kind }
        let movieCount = model.results.filter { $0.kind == "movie" }.count, seriesCount = model.results.filter { $0.kind == "series" }.count
        if model.results.count > 1 || !kind.isEmpty {
            // Todo · Películas · Series (cuántas de cada una): el filtro de toda la app.
            DSKindFilter(kind: $kind, counts: (movieCount, seriesCount)).padding(.horizontal, DS.Space.gutter)
        }
        // El que mejor coincide, en grande (con su arte), como el primer resultado de Apple TV.
        if let top = shown.first, top.metaID.hasPrefix("tt") {
            let route = TitleRoute(kind: top.kind, metaID: top.metaID, title: top.title, poster: top.poster)
            TitleNavigationLink(route: route) {
                CoverCard(art: String(format: ForYou.metahubBackground, top.metaID), logo: Artwork.logoURL(metaID: top.metaID), title: titleName(top.title, id: top.metaID, kind: top.kind),
                          why: Text("Mejor resultado"), detail: yearAndKind(year: top.year, kind: top.kind), height: DS.Size.searchTopHeight)
            }
            .perfTag("search.top")
            .buttonStyle(.plain).padding(.horizontal, DS.Space.gutter)
            .simultaneousGesture(TapGesture().onEnded { model.remember(query) })
        }
        if answered, !model.results.isEmpty, shown.isEmpty {
            DSEmptyState(symbol: "line.3.horizontal.decrease.circle", title: Text("Nada de ese tipo"), message: Text("Prueba con «Todo»."))
        }
        if status == .waiting && model.results.isEmpty {
            // Mientras llega: pósters vacíos en su lugar (antes, una ruedita sobre la barra de arriba).
            DSPosterGrid(items: DSPosterSlot.slots(9)) { _, width in
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).fill(DS.fill).frame(width: width).aspectRatio(DS.Poster.aspect, contentMode: .fit)
            }
            .accessibilityHidden(true)
        }
        DSPosterGrid(items: shown.first?.metaID.hasPrefix("tt") == true ? Array(shown.dropFirst()) : shown) { r, width in
            // Con letra de accesibilidad, el año y el tipo en dos renglones (en uno se cortaban).
            TitleLink(route: TitleRoute(kind: r.kind, metaID: r.metaID, title: r.title, poster: r.poster), width: width,
                      detail: yearAndKind(year: r.year, kind: r.kind), detailLines: typeSize.isAccessibilitySize ? 2 : 1,
                      fallbackPoster: r.fallbackPoster)
                .perfTag("search.grid")
                .simultaneousGesture(TapGesture().onEnded { model.remember(query) })
        }
        // Los pósters de los primeros resultados, todos a la vez en cuanto llegan (antes cada celda pedía el suyo hasta
        // aparecer, de a poco).
        .task(id: shown.prefix(DS.Size.searchPrefetch).map(\.metaID)) {
            ImagePipeline.shared.prefetchPosters(shown.prefix(DS.Size.searchPrefetch).compactMap(\.poster))
        }
    }

    // MARK: sin escribir
    @ViewBuilder private var suggestions: some View {
        let model = catalog.model
        // Lo que buscaste arriba y, debajo, la puerta del filtro (Fernando, 13 nov 2026: «pon búsquedas recientes arriba de
        // búsqueda avanzada»); juntas, sin el aire entre secciones.
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            if !search.model.recent.isEmpty { recent }
            filterDoor
        }
        if let degraded = model.degraded {
            DegradedNotice(state: degraded) { Task { await model.load() } }.padding(.horizontal, DS.Space.gutter)
        }
    }

    /// La puerta del filtro avanzado, bajo «Buscaste hace poco» (entrada A del 31 oct; abajo de lo reciente desde el 13 nov): los mosaicos del cajón en chiquito.
    private var filterDoor: some View {
        let model = env.advancedFilter
        let _ = model.track()
        let context = FilterContext(filter: model.filter, platforms: model.platforms, language: env.services.appSettings.uiLanguage)
        return FilterDoor(context: context, count: model.count, open: { page in
            filterStart = page
            showFilter = true
        }, clear: { withAnimation(DS.Motion.base(reduceMotion)) { model.clear() } })
        .coachAnchor("advanced-search")   // F3: el aviso con foco de Buscar señala la puerta del filtro
        .padding(.horizontal, DS.Space.gutter)
    }

    /// Lo que buscaste, en cápsulas bajo el título (un toque lo vuelve a buscar); «Borrar» al final.
    private var recent: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            // El mismo encabezado de subsección que «Por género» (y que la TV en su caja vacía), no una nota gris.
            DSSectionHead(title: Text("Buscaste hace poco")).padding(.horizontal, DS.Space.gutter)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Space.s2) {
                    ForEach(search.model.recent, id: \.self) { text in
                        PanelChip(title: Text(verbatim: text), selected: false, symbol: "clock.arrow.circlepath") { query = text }
                    }
                    Button("Borrar") { search.model.clearRecent() }
                        .font(DS.TextRecipe.footnote.font).foregroundStyle(DS.textMuted).buttonStyle(.borderless)
                }
            }
            .scrollClipDisabled()   // lo que crece al picarlo (o al dejarlo apretado) no se corta en la orilla del listón
            .contentMargins(.horizontal, DS.Space.gutter, for: .scrollContent)
        }
    }
}

/// «Lo más popular hoy» completo (desde el «Ver todo» de su franja en Explorar): con el mismo ordenar y filtrar que toda lista.
struct PopularGridView: View {
    let model: CatalogModel
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        ScrollView {
            SortableGrid(listID: "popular", items: model.popular.map(Self.suggestion), collections: env.collections, loading: model.isLoading) { s, width in
                TitleLink(route: s.route, width: width, detail: yearAndKind(year: s.year.map(String.init) ?? "", kind: s.kind))
            }
            .padding(.top, DS.Space.s3)
            .padding(.bottom, DS.Layout.screenBottom)
        }
        .background(Backdrop())
        .navigationTitle("Lo más popular hoy").navigationBarTitleDisplayMode(.inline)
    }

    static func suggestion(_ item: CatalogItem) -> Suggestion {
        Suggestion(kind: item.kind, imdb: item.metaID, title: item.title, year: Int(item.year.prefix(4)), poster: item.poster ?? "", wide: "", reason: .popular)
    }
}
