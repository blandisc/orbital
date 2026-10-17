import SwiftUI
import OrbitalCore

/// Cómo se ordena una lista abierta.
enum ListSort: String, CaseIterable {
    case added, newest, oldest, title
    var label: LocalizedStringKey {
        switch self { case .added: "Como viene la lista"; case .newest: "Año: más nuevas"; case .oldest: "Año: más viejas"; case .title: "A–Z" }
    }
}

/// Lo que se filtra en una lista abierta: series o películas, un género, y ocultar lo que ya viste.
struct ListFilter: Equatable {
    var kind: String?
    var genre: String?
    var hideWatched = false
    var isActive: Bool { kind != nil || genre != nil || hideWatched }

    func apply(_ items: [Suggestion], sort: ListSort, watched: Set<String>) -> [Suggestion] {
        let kept = items.filter { s in
            (kind == nil || s.kind == kind)
                && (genre == nil || s.genres.contains { $0.lowercased() == genre })
                && (!hideWatched || !watched.contains(s.imdb))
        }
        switch sort {
        case .added: return kept
        case .newest: return kept.sorted { ($0.year ?? 0) > ($1.year ?? 0) }
        case .oldest: return kept.sorted { ($0.year ?? Int.max) < ($1.year ?? Int.max) }
        case .title: return kept.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
    }
}

/// El nombre de un género de Trakt («science-fiction») en el idioma de la app.
@MainActor func genreName(_ slug: String) -> String {
    let english = slug == "science-fiction" ? "Sci-Fi" : slug.split(separator: "-").map { $0.capitalized }.joined(separator: " ")
    return Vocabulary.genres([english], language: AppEnvironment.shared.services.appSettings.uiLanguage).first ?? english
}

/// Una lista abierta en cuadrícula de pósters, con el botón de ordenar y filtrar arriba a la derecha y lo filtrado en
/// cápsulas que se quitan con ✕. Cada lista recuerda su orden.
struct SortableGrid<Cell: View>: View {
    let listID: String
    let items: [Suggestion]
    /// Lo que ya viste (para «Ocultar lo que ya vi»); nil si no hay Trakt.
    var watched: (() async -> Set<String>)?
    @ViewBuilder var cell: (Suggestion) -> Cell
    @State private var sort: ListSort
    @State private var filter = ListFilter()
    @State private var seen: Set<String> = []

    init(listID: String, items: [Suggestion], watched: (() async -> Set<String>)? = nil, @ViewBuilder cell: @escaping (Suggestion) -> Cell) {
        self.listID = listID; self.items = items; self.watched = watched; self.cell = cell
        _sort = State(initialValue: UserDefaults.standard.string(forKey: "list-sort.\(listID)").flatMap(ListSort.init(rawValue:)) ?? .added)
    }

    var body: some View {
        let shown = filter.apply(items, sort: sort, watched: seen)
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            if filter.isActive { activeChips }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: DS.Poster.gridMinimum), spacing: DS.Space.s3)], spacing: DS.Space.s4) {
                ForEach(shown) { s in cell(s) }
            }
            .padding(.horizontal, DS.Space.gutter)
            if shown.isEmpty, !items.isEmpty { DSNotice(text: "Nada con estos filtros.").padding(.horizontal, DS.Space.gutter) }
        }
        .toolbar { ToolbarItem(placement: .topBarTrailing) { menu } }
        .onChange(of: sort) { _, new in UserDefaults.standard.set(new.rawValue, forKey: "list-sort.\(listID)") }
        .task(id: filter.hideWatched) { if filter.hideWatched, let watched { seen = await watched() } }
    }

    private var genres: [String] {
        var counts: [String: Int] = [:]
        for s in items { for g in s.genres { counts[g.lowercased(), default: 0] += 1 } }
        return counts.sorted { $0.value > $1.value }.prefix(12).map(\.key)
    }

    private var kinds: Set<String> { Set(items.map(\.kind)) }

    private var menu: some View {
        Menu {
            Picker(selection: $sort) {
                ForEach(ListSort.allCases, id: \.self) { Text($0.label).tag($0) }
            } label: { Label("Ordenar", systemImage: "arrow.up.arrow.down") }
            .pickerStyle(.menu)
            if kinds.count > 1 {
                Picker(selection: $filter.kind) {
                    Text("Todo").tag(String?.none)
                    Text("Series").tag(String?.some("series"))
                    Text("Películas").tag(String?.some("movie"))
                } label: { Label("Series o películas", systemImage: "film.stack") }
                .pickerStyle(.menu)
            }
            if !genres.isEmpty {
                Picker(selection: $filter.genre) {
                    Text("Todos").tag(String?.none)
                    ForEach(genres, id: \.self) { Text(verbatim: genreName($0)).tag(String?.some($0)) }
                } label: { Label("Género", systemImage: "theatermasks") }
                .pickerStyle(.menu)
            }
            if watched != nil { Toggle(isOn: $filter.hideWatched) { Label("Ocultar lo que ya vi", systemImage: "eye.slash") } }
        } label: {
            Image(systemName: filter.isActive || sort != .added ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel(Text("Ordenar y filtrar"))
        .accessibilityIdentifier("list-controls")
    }

    private var activeChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Space.s2) {
                if let kind = filter.kind { chip(kind == "movie" ? Text("Películas") : Text("Series")) { filter.kind = nil } }
                if let genre = filter.genre { chip(Text(verbatim: genreName(genre))) { filter.genre = nil } }
                if filter.hideWatched { chip(Text("Sin lo que ya vi")) { filter.hideWatched = false } }
            }
        }
        .contentMargins(.horizontal, DS.Space.gutter, for: .scrollContent)
    }

    private func chip(_ title: Text, remove: @escaping () -> Void) -> some View {
        Button(action: remove) {
            HStack(spacing: DS.Space.s1) { title; Image(systemName: "xmark").font(DS.TextRecipe.caption.font.weight(.bold)) }
                .font(DS.TextRecipe.footnote.font).foregroundStyle(DS.backdropDeep)
                .padding(.horizontal, DS.Space.s3).padding(.vertical, DS.Space.s2)
                .background(DS.paper, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
