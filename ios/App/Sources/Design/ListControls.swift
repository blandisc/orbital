import SwiftUI
import OrbitalCore
import OrbitalModels

/// Cómo se ordena una lista abierta.
enum ListSort: String, CaseIterable {
    case added, best, imdb, trakt, letterboxd, newest, oldest, title, shortest
    var label: LocalizedStringKey {
        switch self {
        case .added: "Como viene la lista"; case .best: "Mejor calificadas (IMDb y Trakt)"; case .imdb: "Mejor calificadas en IMDb"; case .trakt: "Mejor calificadas en Trakt"; case .letterboxd: "Mejor calificadas en Letterboxd"
        case .shortest: "Más cortas primero"
        case .newest: "Año (lo más nuevo primero)"; case .oldest: "Año: más viejas"; case .title: "A–Z"
        }
    }
}

/// Lo que se filtra en una lista abierta: series o películas, un género, una calificación mínima, una década y ocultar lo
/// que ya viste (o, donde se sabe cuánto llevas de cada uno, cómo vas: por ver, a medias o vistas). El mismo filtro en todo
/// «Ver todo» y en Biblioteca › Guardado.
struct ListFilter: Equatable {
    var kind: String?
    /// «Por ver», «A medias» o «Vistas» (Biblioteca › Guardado, Fernando, 3 nov 2026: BI3-A).
    var state: WatchState?
    var genre: String?
    /// «De 7 para arriba»: la calificación unida (IMDb y Trakt) mínima.
    var minRating: Double?
    /// «Los 90»: el primer año de la década.
    var decade: Int?
    var hideWatched = false
    var isActive: Bool { kind != nil || state != nil || genre != nil || minRating != nil || decade != nil || hideWatched }

    /// La calificación de un título juntando los servicios que la tengan (el promedio de IMDb y Trakt); nil si ninguno.
    static func rating(_ s: Suggestion, imdb: [String: Double]) -> Double? {
        let found = [imdb[s.imdb], s.traktRating].compactMap { $0 }.filter { $0 > 0 }
        return found.isEmpty ? nil : found.reduce(0, +) / Double(found.count)
    }

    /// ¿Pasa este título? Lo mismo para una lista y para una colección de la repisa (que no trae `Suggestion`).
    func keeps(kind itemKind: String, genres: [String], rating: Double?, year: Int?, watched isWatched: Bool, state itemState: WatchState? = nil) -> Bool {
        (kind == nil || itemKind == kind)
            && (state == nil || (itemState ?? (isWatched ? .watched : .unwatched)) == state)
            && (genre == nil || genres.contains { $0.lowercased() == genre })
            && (minRating == nil || (rating ?? 0) >= minRating!)
            && (decade == nil || year.map { $0 / 10 * 10 == decade } == true)
            && (!hideWatched || !isWatched)
    }

    /// Los géneros más comunes de lo que hay (los del menú), con su nombre de Trakt en minúsculas.
    static func commonGenres(_ all: [[String]]) -> [String] {
        var counts: [String: Int] = [:]
        for genres in all { for g in genres { counts[g.lowercased(), default: 0] += 1 } }
        return counts.sorted { $0.value > $1.value }.prefix(12).map(\.key)
    }

    /// Las décadas que hay, de la más nueva a la más vieja.
    static func decades(_ years: [Int?]) -> [Int] { Array(Set(years.compactMap { $0.map { $0 / 10 * 10 } })).sorted(by: >) }

    func apply(_ items: [Suggestion], sort: ListSort, watched: Set<String>, imdb: [String: Double] = [:], letterboxd: [String: Double] = [:],
               states: [String: WatchState] = [:]) -> [Suggestion] {
        let kept = items.filter { s in
            keeps(kind: s.kind, genres: s.genres, rating: Self.rating(s, imdb: imdb), year: s.year, watched: watched.contains(s.imdb), state: states[s.imdb])
        }
        switch sort {
        case .added: return kept
        case .best: return kept.sorted { (Self.rating($0, imdb: imdb) ?? 0) > (Self.rating($1, imdb: imdb) ?? 0) }
        case .shortest: return kept.sorted { ($0.runtime ?? Int.max) < ($1.runtime ?? Int.max) }
        case .imdb: return kept.sorted { (imdb[$0.imdb] ?? 0) > (imdb[$1.imdb] ?? 0) }
        case .trakt: return kept.sorted { ($0.traktRating ?? 0) > ($1.traktRating ?? 0) }
        case .letterboxd: return kept.sorted { (letterboxd[$0.imdb] ?? 0) > (letterboxd[$1.imdb] ?? 0) }   // las series (sin Letterboxd), al final
        case .newest: return kept.sorted { ($0.year ?? 0) > ($1.year ?? 0) }
        case .oldest: return kept.sorted { ($0.year ?? Int.max) < ($1.year ?? Int.max) }
        case .title: return kept.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
    }
}

/// El nombre de un género de Trakt («science-fiction») en el idioma de la app.
@MainActor func genreName(_ slug: String, language: String) -> String {
    let english = ["science-fiction", "science fiction", "sci-fi"].contains(slug) ? "Sci-Fi" : slug.split(separator: "-").map { $0.capitalized }.joined(separator: " ")
    return Vocabulary.genres([english], language: language).first ?? english
}

/// Una lista abierta en cuadrícula de pósters, con el botón de ordenar y filtrar arriba a la derecha y lo filtrado en
/// cápsulas que se quitan con ✕. Cada lista recuerda su orden. Es el único «Ver todo»: lo visto y las calificaciones de
/// IMDb salen solos de las colecciones de la app, así que toda lista tiene los mismos órdenes y filtros.
struct SortableGrid<Cell: View>: View {
    let listID: String
    let items: [Suggestion]
    /// Lo que ya viste (para «Ocultar lo que ya vi»); nil si no hay Trakt.
    var watched: (() async -> Set<String>)?
    /// Las calificaciones de IMDb (se piden al elegir ese orden).
    var imdbRatings: (([Suggestion]) async -> [String: Double])?
    /// Sin «Series o películas» en el menú: la pantalla ya trae su propio `DSKindFilter` (un año de «Por año»).
    var showsKindFilter = true
    /// La lista todavía viene en camino: la ruedita al centro en lugar del vacío.
    var loading = false
    /// Cómo vas con cada título (por IMDb), donde se sabe: el menú ofrece «Estado» (Por ver · A medias · Vistas) en lugar de
    /// «Ocultar lo que ya vi» (Biblioteca › Guardado).
    var states: [String: WatchState]?
    /// El renglón de arriba de la pantalla, con el botón de ordenar y filtrar adentro en vez de en la barra (Guardado, FG1-A:
    /// «Mi lista ⌃⌄» a la izquierda y Todo · Películas · Series y el botón a la derecha; Fernando, 4 nov 2026). Debajo, solo
    /// lo filtrado en cápsulas. nil: el botón va arriba a la derecha, en la barra, como en toda lista abierta.
    var bar: ((ListFilterMenu) -> AnyView)?   // ds-exception: el renglón lo arma la pantalla
    /// Cada póster recibe el ancho de su columna (`DSPosterGrid`).
    @ViewBuilder var cell: (Suggestion, CGFloat) -> Cell
    @State private var sort: ListSort
    @State private var filter = ListFilter()
    @State private var seen: Set<String> = []
    @State private var imdb: [String: Double] = [:]
    /// Los promedios de Letterboxd (se piden al elegir ese orden; solo películas).
    @State private var letterboxd: [String: Double] = [:]
    private let letterboxdRatings: ([Suggestion]) async -> [String: Double]
    @State private var rating = false
    /// «Ocultar lo que ya vi» solo con Trakt (lo visto sale de ahí).
    private let hideWatchedAvailable: Bool

    init(listID: String, items: [Suggestion], collections: CollectionsModel, watched: (() async -> Set<String>)? = nil,
         imdbRatings: (([Suggestion]) async -> [String: Double])? = nil, showsKindFilter: Bool = true, loading: Bool = false,
         states: [String: WatchState]? = nil, bar: ((ListFilterMenu) -> AnyView)? = nil, @ViewBuilder cell: @escaping (Suggestion, CGFloat) -> Cell) {
        let shared = collections
        self.states = states; self.bar = bar
        self.hideWatchedAvailable = collections.traktLinked && states == nil
        self.listID = listID; self.items = items; self.cell = cell
        self.showsKindFilter = showsKindFilter; self.loading = loading
        self.watched = watched ?? { await shared.watchedIDs() }
        self.imdbRatings = imdbRatings ?? { items in await shared.imdbRatings(items.map { ($0.kind, $0.imdb) }) }
        self.letterboxdRatings = { items in await shared.letterboxdRatings(items.filter { $0.kind == "movie" }.map(\.imdb)) }
        _sort = State(initialValue: UserDefaults.standard.string(forKey: "list-sort.\(listID)").flatMap(ListSort.init(rawValue:)) ?? .added)
    }

    var body: some View {
        let shown = filter.apply(items, sort: sort, watched: seen, imdb: imdb, letterboxd: letterboxd, states: states ?? [:])
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            if let bar { bar(menu) }
            if filter.isActive { ListFilterChips(filter: $filter) }
            // Letterboxd se pregunta película por película: en una lista larga solo las primeras; se dice (antes una muy bien
            // calificada que estaba abajo nunca subía, sin saber por qué).
            let movies = items.filter { $0.kind == "movie" }.count
            if sort == .letterboxd, movies > CollectionsModel.letterboxdLimit {
                Text("Se ordenaron \(CollectionsModel.letterboxdLimit) de \(movies) por Letterboxd").recipe(.caption, color: DS.textMuted)
            }
            if items.isEmpty {
                // Mientras llega, la ruedita al centro; ya llegada y sin nada, el vacío de la app (no una pantalla en blanco).
                if loading { DSLoadingState() }
                else { DSEmptyState(symbol: "tray", title: Text("Nada por aquí por ahora"), message: Text("Esta lista todavía no tiene títulos.")) }
            } else if shown.isEmpty {
                DSEmptyState(symbol: "line.3.horizontal.decrease.circle", title: Text("Nada con estos filtros"), message: Text("Cambia el orden o lo que ocultas."))
            } else {
                DSPosterGrid(items: shown) { s, width in cell(s, width) }
            }
        }
        .toolbar {
            if bar == nil { ToolbarItem(placement: .topBarTrailing) { menu } }
        }
        .onChange(of: sort) { _, new in UserDefaults.standard.set(new.rawValue, forKey: "list-sort.\(listID)") }
        .task(id: filter.hideWatched) { if filter.hideWatched, let watched { seen = await watched() } }
        // También cuando llega la lista: si entraste con el orden de IMDb guardado, la lista todavía venía vacía.
        .task(id: needsIMDb ? items.count : -1) {
            guard needsIMDb, let imdbRatings, !items.isEmpty else { rating = false; return }
            rating = true
            defer { rating = false }
            imdb = await imdbRatings(items)
        }
        .task(id: sort == .letterboxd ? items.count : -1) {
            guard sort == .letterboxd, !items.isEmpty else { return }
            rating = true
            defer { rating = false }
            letterboxd = await letterboxdRatings(items)
        }
    }

    private var menu: ListFilterMenu {
        ListFilterMenu(sort: $sort, filter: $filter, sorts: sorts, genres: genres, decades: decades, showsKindFilter: showsKindFilter,
                       showsStateFilter: states != nil, hideWatchedAvailable: hideWatchedAvailable, loading: rating)
    }

    /// IMDb se pide solo si el orden o la calificación mínima la usan.
    private var needsIMDb: Bool { sort == .best || sort == .imdb || filter.minRating != nil }

    private var decades: [Int] { ListFilter.decades(items.map(\.year)) }

    private var genres: [String] { ListFilter.commonGenres(items.map(\.genres)) }

    /// Los órdenes que tienen sentido aquí: IMDb si se puede pedir; Trakt si la lista trae su calificación.
    private var sorts: [ListSort] {
        ListSort.allCases.filter { s in
            switch s {
            case .imdb: imdbRatings != nil
            case .trakt: items.contains { $0.traktRating != nil }
            case .letterboxd: items.contains { $0.kind == "movie" }   // Letterboxd califica películas
            case .shortest: items.contains { $0.runtime != nil }
            // Como la TV: sin «Como viene» (sin orden elegido, la lista va como llega) ni «más viejas».
            case .added, .oldest: false
            default: true
            }
        }
    }
}

/// El botón de ordenar y filtrar de una lista abierta (arriba a la derecha): el mismo en todo «Ver todo» y en las colecciones
/// de la repisa. Sin órdenes (`sorts` vacío), solo filtra.
struct ListFilterMenu: View {
    @Binding var sort: ListSort
    @Binding var filter: ListFilter
    var sorts: [ListSort]
    var genres: [String]
    var decades: [Int]
    var showsKindFilter = true
    /// «Estado»: Por ver · A medias · Vistas (donde se sabe cuánto llevas de cada título).
    var showsStateFilter = false
    var hideWatchedAvailable = true
    /// Mientras llegan las calificaciones o los géneros: la ruedita en el botón.
    var loading = false
    @Environment(\.locale) private var locale
    private var language: String { locale.language.languageCode?.identifier ?? "es" }

    var body: some View {
        Menu {
            // Elegir otra vez el orden activo lo quita (la lista vuelve a ir como llega).
            if !sorts.isEmpty {
                Menu {
                    ForEach(sorts, id: \.self) { option in
                        Button { sort = sort == option ? .added : option } label: {
                            if sort == option { Label(option.label, systemImage: "checkmark") } else { Text(option.label) }
                        }
                    }
                } label: { Label("Ordenar", systemImage: "arrow.up.arrow.down") }
            }
            if showsKindFilter {
                Picker(selection: $filter.kind) {
                    Label("Todo", systemImage: KindGlyph.all).tag(String?.none)
                    Label("Películas", systemImage: KindGlyph.movie).tag(String?.some("movie"))
                    Label("Series", systemImage: KindGlyph.series).tag(String?.some("series"))
                } label: { Label("Series o películas", systemImage: KindGlyph.symbol(filter.kind)) }
                .pickerStyle(.menu)
            }
            if showsStateFilter {
                Picker(selection: $filter.state) {
                    Text("Todos").tag(WatchState?.none)
                    ForEach(WatchState.allCases, id: \.self) { state in
                        Label { WatchStateName.text(state) } icon: { Image(systemName: WatchStateName.symbol(state)) }.tag(WatchState?.some(state))
                    }
                } label: { Label("Estado", systemImage: WatchStateName.symbol(filter.state)) }
                .pickerStyle(.menu)
            }
            if !genres.isEmpty {
                Picker(selection: $filter.genre) {
                    Text("Todos").tag(String?.none)
                    ForEach(genres, id: \.self) { Text(verbatim: genreName($0, language: language)).tag(String?.some($0)) }
                } label: { Label("Género", systemImage: "theatermasks") }
                .pickerStyle(.menu)
            }
            Picker(selection: $filter.minRating) {
                Text("Cualquiera").tag(Double?.none)
                ForEach([6.0, 7.0, 8.0], id: \.self) { ratingName($0).tag(Double?.some($0)) }
            } label: { Label("Calificación", systemImage: "star") }
            .pickerStyle(.menu)
            if decades.count > 1 {
                Picker(selection: $filter.decade) {
                    Text("Todas").tag(Int?.none)
                    ForEach(decades, id: \.self) { decadeName($0).tag(Int?.some($0)) }
                } label: { Label("Década", systemImage: "calendar") }
                .pickerStyle(.menu)
            }
            if hideWatchedAvailable { Toggle(isOn: $filter.hideWatched) { Label("Ocultar lo que ya vi", systemImage: "eye.slash") }.toggleStyle(.automatic) }   // en el menú, la palomita del sistema
        } label: {
            // Mientras llegan las calificaciones de IMDb, la ruedita va en el botón (la cuadrícula no se mueve).
            if loading { ProgressView() }   // ds-exception: la ruedita ocupa el lugar del ícono del menú (la cuadrícula no se mueve)
            else { Image(systemName: filter.isActive || sort != .added ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle") }
        }
        .accessibilityLabel(Text("Ordenar y filtrar"))
        .accessibilityIdentifier("list-controls")
    }

    private func decadeName(_ d: Int) -> Text { ListFilterChips.decadeName(d) }
    private func ratingName(_ r: Double) -> Text { ListFilterChips.ratingName(r) }
}

/// Lo filtrado en cápsulas que se quitan con ✕ (bajo el título de la lista o de la colección).
struct ListFilterChips: View {
    @Binding var filter: ListFilter
    @Environment(\.locale) private var locale
    private var language: String { locale.language.languageCode?.identifier ?? "es" }

    static func decadeName(_ d: Int) -> Text { Text(verbatim: d >= 2000 ? "\(d)s" : "\(d % 100)s") }
    static func ratingName(_ r: Double) -> Text { Text("De \(Int(r)) para arriba") }
    private func decadeName(_ d: Int) -> Text { Self.decadeName(d) }
    private func ratingName(_ r: Double) -> Text { Self.ratingName(r) }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Space.s2) {
                if let kind = filter.kind { chip(Text("\(Text(Image(systemName: KindGlyph.symbol(kind))))\(Text(verbatim: " "))\((kind == "movie" ? Text("Películas") : Text("Series")))")) { filter.kind = nil } }
                if let state = filter.state { chip(Text("\(Text(Image(systemName: WatchStateName.symbol(state))))\(Text(verbatim: " "))\(WatchStateName.text(state))")) { filter.state = nil } }
                if let genre = filter.genre { chip(Text(verbatim: genreName(genre, language: language))) { filter.genre = nil } }
                if let min = filter.minRating { chip(ratingName(min)) { filter.minRating = nil } }
                if let decade = filter.decade { chip(decadeName(decade)) { filter.decade = nil } }
                if filter.hideWatched { chip(Text("Sin lo que ya vi")) { filter.hideWatched = false } }
            }
        }
        .contentMargins(.horizontal, DS.Space.gutter, for: .scrollContent)
    }

    private func chip(_ title: Text, remove: @escaping () -> Void) -> some View {
        // El principal chico de siempre, en el papel de la acción principal (no `DS.paper`, que en claro es el mismo papel del
        // fondo y se perdía); antes una cápsula pintada a mano (D9).
        Button(action: remove) {
            HStack(spacing: DS.Space.s1) {
                title
                Image(systemName: "xmark").font(DS.TextRecipe.badge.font)   // ds-exception: la ✕ dice que tocar la ficha quita el filtro (no es cerrar)
            }
            .font(DS.TextRecipe.footnote.font)
        }
        .dsPrimaryButton(size: .small)
        .buttonBorderShape(.capsule)
    }
}

/// Cómo se llama y qué ícono lleva cada estado (el menú y la cápsula de lo filtrado): un círculo vacío, a medias o con ✓.
enum WatchStateName {
    static func text(_ state: WatchState) -> Text {
        switch state { case .unwatched: Text("Por ver"); case .inProgress: Text("A medias"); case .watched: Text("Vistas") }
    }
    /// nil: cualquier estado.
    static func symbol(_ state: WatchState?) -> String {
        switch state { case .unwatched: "circle"; case .inProgress: "circle.lefthalf.filled"; case .watched: "checkmark.circle"; case nil: "circle.dashed" }
    }
}

/// La cuadrícula de pósters de toda la app: columnas fijas que llenan el ancho (3; 4 en pantallas anchas; 2 con letra de
/// accesibilidad), separadas por `DS.Space.s3` y con los bordes en el margen de la pantalla. Cada celda recibe el ancho de su
/// columna para que el póster (2:3) la llene: antes, `.adaptive` con celdas fijas de 100 dejaba huecos de 27 y los pósters
/// metidos del margen.
struct DSPosterGrid<Data: RandomAccessCollection, Cell: View>: View where Data.Element: Identifiable {
    let items: Data
    var rowSpacing: CGFloat = DS.Space.s4
    @ViewBuilder var cell: (Data.Element, CGFloat) -> Cell
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var width: CGFloat = 0

    private var columns: Int {
        if typeSize.isAccessibilitySize { return DS.Poster.gridColumnsLarge }
        return DS.Poster.gridColumns(for: width)
    }

    private var cellWidth: CGFloat {
        let inner = width - DS.Space.gutter * 2 - DS.Space.s3 * CGFloat(columns - 1)
        return max(0, (inner / CGFloat(columns)).rounded(.down))
    }

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.s3, alignment: .topLeading), count: columns),
                  alignment: .leading, spacing: rowSpacing) {
            if width > 0 { ForEach(items) { cell($0, cellWidth) } }
        }
        .padding(.horizontal, DS.Space.gutter)
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}

/// Un lugar vacío de `DSPosterGrid` mientras llegan los resultados.
struct DSPosterSlot: Identifiable {
    let id: Int
    static func slots(_ count: Int) -> [DSPosterSlot] { (0..<count).map(DSPosterSlot.init) }
}

/// Una lista agrupada con el rótulo de cada sección como su primer renglón (Descargas): el rótulo al ras de las tarjetas, a
/// 20 pt de la suya, y unos 40 entre una sección y la siguiente (Fernando, 2 nov 2026, I2: antes 34 y 67, mucho aire). La
/// regla de toda lista con rótulos así: `listHeadRow()` en el rótulo y `listHeadRows()` en la lista.
extension View {
    /// El rótulo como renglón: sin fondo, sin sangría ni separador, y su aire hasta la tarjeta (`DS.ListSection.headPad` más
    /// el espacio entre renglones y el del propio rótulo: unos 20 pt). Baja `cornerClear`: con aire entre renglones cada uno
    /// es su propia celda redondeada y su esquina le cortaba el ícono y la primera letra al rótulo.
    func listHeadRow() -> some View {
        padding(.top, DS.ListSection.cornerClear)
            .padding(.bottom, DS.ListSection.headPad)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    /// La lista: sin el alto mínimo de renglón del sistema (44 pt), que dejaba aire arriba y abajo del rótulo.
    func listHeadRows() -> some View { environment(\.defaultMinListRowHeight, 0) }
}
