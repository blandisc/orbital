import SwiftUI
import OrbitalCore
import OrbitalModels

extension View {
    /// El filtro avanzado como hoja (Inicio, Para ti y Buscar lo montan igual): el cajón de dos alturas, cada filtro se abre
    /// dentro de él y «Ver resultados» trae la cuadrícula ahí mismo. Tocar un título cierra la hoja y avisa con `onOpenTitle`.
    func advancedFilter(isPresented: Binding<Bool>, start: FilterPage? = nil, onOpenTitle: @escaping (TitleRoute) -> Void) -> some View {
        sheet(isPresented: isPresented) {
            AdvancedFilterSheet(start: start) { route in
                isPresented.wrappedValue = false
                onOpenTitle(route)
            }
        }
    }
}

/// Las páginas que se abren dentro del cajón.
enum FilterPage: Hashable {
    case format, genre, era, length, rating, fame, origin, studio, results
    /// La opción tocada en la puerta de Buscar; «Dónde verla» (y nil) abren el cajón completo, donde van las plataformas.
    init?(door id: String?) {
        switch id {
        case "genre": self = .genre; case "rating": self = .rating; case "era": self = .era
        case "length": self = .length; case "fame": self = .fame
        default: return nil
        }
    }
}

/// El cajón del filtro avanzado: seis filtros principales y «Ver más» (origen y estudios). Corto mientras eliges; crece al
/// abrir un filtro o los resultados.
struct AdvancedFilterSheet: View {
    /// El filtro que se abre de entrada (lo tocado en la puerta de Buscar).
    var start: FilterPage?
    let onOpenTitle: (TitleRoute) -> Void
    @Environment(AppEnvironment.self) private var env
    @State private var path: [FilterPage] = []
    @State private var detent: PresentationDetent = AdvancedFilterSheet.short
    @State private var more = false

    var body: some View {
        let model = env.advancedFilter
        let _ = model.track()
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s3) {
                    // Dónde verla: tus plataformas (las que hay en tu país). Sin ninguna elegida, en cualquiera.
                    if !model.platforms.isEmpty {
                        PanelGroupTitle(title: "Dónde verla")
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: DS.Space.s2) {
                                ForEach(model.platforms) { p in
                                    PanelChip(title: Text(verbatim: p.name), selected: model.filter.providers.contains(p.id), symbol: "play.tv") {
                                        if model.filter.providers.contains(p.id) { model.filter.providers.remove(p.id) } else { model.filter.providers.insert(p.id) }
                                    }
                                    .accessibilityIdentifier("filter-platform-\(p.brand)")
                                }
                            }
                        }
                        .scrollClipDisabled()
                    }
                    Toggle(isOn: Binding(get: { model.filter.hideWatched }, set: { model.filter.hideWatched = $0 })) {
                        Label("Ocultar lo que ya vi", systemImage: "eye.slash").recipe(.footnote, color: DS.text).fontWeight(.semibold)
                    }
                    .padding(.horizontal, DS.Space.s3).frame(minHeight: DS.Size.touchTarget)
                    .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
                    .accessibilityIdentifier("filter-hide-watched")
                    PanelGroupTitle(title: "Qué buscas")
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: DS.Space.s2), GridItem(.flexible(), spacing: DS.Space.s2)], spacing: DS.Space.s2) {
                        tile(.format, "square.grid.2x2", Text("Formato"), FilterText.format(model.filter))
                        tile(.genre, "theatermasks", Text("Género"), FilterText.genres(model.filter))
                        tile(.era, "calendar", Text("Época"), FilterText.years(model.filter))
                        tile(.length, "clock", Text("Tiempo"), FilterText.length(model.filter))
                        tile(.rating, "star", Text("Calificación"), FilterText.rating(model.filter))
                        tile(.fame, "sparkles", Text("Qué tan conocida"), FilterText.fame(model.filter))
                        if more {
                            tile(.origin, "globe.americas", Text("Origen"), FilterText.countries(model.filter))
                            tile(.studio, "building.2", Text("Estudios"), FilterText.studios(model.filter))
                        }
                    }
                    Button { withAnimation(DS.Motion.base(false)) { more.toggle() } } label: {
                        Label(more ? "Ver menos" : "Ver más", systemImage: more ? "chevron.up" : "chevron.down").recipe(.footnote).fontWeight(.semibold)
                    }
                    .buttonStyle(.borderless)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("filter-more")
                }
                .padding(.horizontal, DS.Space.gutter)
                .padding(.bottom, DS.Space.s4)
            }
            .safeAreaInset(edge: .bottom) { actions(model) }
            .navigationTitle(Text("Filtros"))
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: FilterPage.self) { page in
                Group {
                    if page == .results { FilterResults(model: model, onOpenTitle: onOpenTitle, edit: { path.removeAll() }) }
                    else { FilterEditor(page: page, filter: Binding(get: { model.filter }, set: { model.filter = $0 })) }
                }
                .onAppear { detent = .large }
            }
        }
        .task { await model.loadPlatforms() }
        .onAppear { if let start, path.isEmpty { path = [start]; detent = .large } }   // abre en el filtro tocado en Buscar
        .presentationDetents([Self.short, .large], selection: $detent)
        .onChange(of: path) { _, new in if new.isEmpty { detent = Self.short } }
        .accessibilityElement(children: .contain)   // cada pieza de adentro conserva su identificador
        .accessibilityIdentifier("advanced-filter")
    }

    /// La altura corta: lo justo para los seis filtros y «Ver resultados» sin taparse (en una pantalla baja, la grande).
    static var short: PresentationDetent { WindowMetrics.size.height < DS.Filter.shortScreen ? .large : .fraction(DS.Filter.shortFraction) }

    private func tile(_ page: FilterPage, _ symbol: String, _ title: Text, _ value: Text?) -> some View {
        FilterTile(symbol: symbol, title: title, value: value) { path.append(page) }
            .accessibilityIdentifier("filter-\(page)")
    }

    private func actions(_ model: AdvancedFilterModel) -> some View {
        HStack(spacing: DS.Space.s3) {
            if !model.filter.isEmpty {
                Button("Limpiar") { model.clear() }.buttonStyle(.glass).buttonBorderShape(.capsule).controlSize(.large)
            }
            Button { path.append(.results) } label: {
                Text(model.filter.isEmpty ? "Ver resultados" : "Ver resultados · \(model.filter.activeCount)").frame(maxWidth: .infinity)
            }
            .dsSolidPrimaryButton().controlSize(.large)   // el principal sólido de la app: se lee siempre
            .accessibilityIdentifier("filter-results")
        }
        .padding(.horizontal, DS.Space.gutter)
        .padding(.vertical, DS.Space.s2)
    }
}

/// Lo que dice cada filtro en su mosaico (nil: cualquiera).
enum FilterText {
    static func format(_ f: AdvancedFilter) -> Text? {
        switch (f.format, f.seriesStatus) {
        case (.all, _): return nil
        case (.movie, _): return Text("Películas")
        case (.series, .airing): return Text("Series en emisión")
        case (.series, .ended): return Text("Series terminadas")
        case (.series, .any): return Text("Series")
        }
    }
    static func genres(_ f: AdvancedFilter) -> Text? {
        let yes = Tmdb.genres.filter { f.genres.contains($0.slug) }.map(\.title)
        let no = Tmdb.genres.filter { f.excluded.contains($0.slug) }.map(\.title)
        if yes.isEmpty && no.isEmpty { return nil }
        if yes.isEmpty { return Text("Sin \(no.joined(separator: ", "))") }
        return Text(verbatim: yes.joined(separator: ", "))
    }
    static func years(_ f: AdvancedFilter) -> Text? {
        guard let y = f.years else { return nil }
        if y.lowerBound % 10 == 0, y.upperBound == y.lowerBound + 9 { return Text("Los \(String(y.lowerBound % 100 == 0 ? y.lowerBound : y.lowerBound % 100))") }
        return Text(verbatim: "\(y.lowerBound)–\(y.upperBound)")
    }
    static func length(_ f: AdvancedFilter) -> Text? {
        switch f.length { case .any: nil; case .short: Text("Corta"); case .regular: Text("Normal"); case .long: Text("Larga") }
    }
    static func rating(_ f: AdvancedFilter) -> Text? { f.minRating.map { Text("\($0.formatted(.number.precision(.fractionLength(1)))) o más") } }
    static func fame(_ f: AdvancedFilter) -> Text? {
        switch f.fame { case .any: nil; case .gems: Text("Joyas ocultas"); case .classics: Text("Las de siempre"); case .niche: Text("Para pocos"); case .blockbusters: Text("Taquilleras") }
    }
    static func countries(_ f: AdvancedFilter) -> Text? {
        f.countries.isEmpty ? nil : Text(verbatim: FilterEditor.countries.filter { f.countries.contains($0.code) }.map(\.name).joined(separator: ", "))
    }
    static func studios(_ f: AdvancedFilter) -> Text? {
        f.studios.isEmpty ? nil : Text(verbatim: Tmdb.studios.filter { f.studios.contains($0.id) }.map(\.name).joined(separator: ", "))
    }
}

/// Los resultados dentro del cajón: arriba lo que tienes puesto (la ✕ lo quita ahí mismo) y «＋ Filtro»; el orden en la
/// barra; la cuadrícula de pósters con su calificación, año y duración, por páginas al bajar.
struct FilterResults: View {
    let model: AdvancedFilterModel
    let onOpenTitle: (TitleRoute) -> Void
    /// Regresa al cajón para cambiar los filtros.
    let edit: () -> Void

    var body: some View {
        let _ = model.track()
        ScrollView {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Space.s2) {
                    ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in ActiveFilterChip(title: chip.title) { chip.remove() } }
                    PanelChip(title: Text("Filtro"), selected: false, symbol: "plus", action: edit).accessibilityIdentifier("filter-edit")
                }
                .padding(.horizontal, DS.Space.gutter)
            }
            .scrollClipDisabled()
            .padding(.bottom, DS.Space.s3)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: DS.Filter.resultWidth), spacing: DS.Space.s3)], spacing: DS.Space.s4) {
                ForEach(model.results) { s in
                    Button { onOpenTitle(s.route) } label: {
                        VStack(alignment: .leading, spacing: DS.Space.s1) {
                            PosterView(url: s.poster, title: s.title)
                                .overlay(alignment: .bottomLeading) {
                                    if let r = s.tmdbRating {
                                        Label { Text(verbatim: r.formatted(.number.precision(.fractionLength(1)))) } icon: { Image(systemName: "star.fill") }
                                            .recipe(.caption, color: DS.paper).fontWeight(.bold)
                                            .padding(.horizontal, DS.Space.s2).padding(.vertical, DS.Space.s1 / 2)
                                            .background(DS.badgeBackground, in: Capsule())
                                            .padding(DS.Space.s1)
                                    }
                                }
                            Text(s.title).recipe(.footnote).lineLimit(1)
                            facts(s).recipe(.caption, color: DS.textMuted).lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("filter-result")
                    .onAppear { if s.id == model.results.last?.id { Task { await model.more() } } }
                }
            }
            .padding(.horizontal, DS.Space.gutter)
            if model.isLoading { DSLoadingState() }
        }
        .overlay {
            if !model.available {
                DSEmptyState(symbol: "key", title: Text("Falta la clave de TMDB"), message: Text("Agrégala en Ajustes › Avanzado para buscar con filtros."))
            } else if model.failed {
                DSEmptyState(symbol: "wifi.slash", title: Text("No se pudo cargar"), message: Text("Revisa tu conexión e intenta de nuevo."))
            } else if model.results.isEmpty, !model.isLoading {
                DSEmptyState(symbol: "line.3.horizontal.decrease", title: Text("Nada con esos filtros"), message: Text("Quita alguno de arriba para ver más opciones."))
            }
        }
        .navigationTitle(Text("Resultados"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker(selection: Binding(get: { model.filter.sort }, set: { model.filter.sort = $0 })) {
                        Label("Más populares", systemImage: "flame").tag(AdvancedFilter.Sort.popular)
                        Label("Mejor calificadas", systemImage: "star").tag(AdvancedFilter.Sort.rating)
                        Label("Más nuevas", systemImage: "calendar").tag(AdvancedFilter.Sort.newest)
                    } label: { EmptyView() }
                } label: { Label("Ordenar", systemImage: "arrow.up.arrow.down") }
                .accessibilityIdentifier("filter-sort")
            }
        }
        .task { await model.search() }
        .onChange(of: model.filter) { Task { await model.search() } }   // quitaste un filtro o cambiaste el orden: otra vez desde la primera página
    }

    /// «2018 · 2 h 7 min» (lo que falte, no se dice).
    private func facts(_ s: Suggestion) -> Text {
        var parts: [Text] = []
        if let y = s.year { parts.append(Text(verbatim: String(y))) }
        if let m = s.runtime, m > 0 { parts.append(m < 60 ? Text("\(m) min") : m % 60 == 0 ? Text("\(m / 60) h") : Text("\(m / 60) h \(m % 60) min")) }
        return parts.isEmpty ? Text(verbatim: "") : parts.dropFirst().reduce(parts[0]) { Text("\($0) · \($1)") }
    }

    /// Lo puesto, uno por pastilla, con cómo quitarlo.
    private var chips: [(title: Text, remove: () -> Void)] {
        let f = model.filter
        var out: [(Text, () -> Void)] = []
        if let t = FilterText.format(f) { out.append((t, { model.filter.format = .all; model.filter.seriesStatus = .any })) }
        if let t = FilterText.genres(f) { out.append((t, { model.filter.genres = []; model.filter.excluded = [] })) }
        if let t = FilterText.years(f) { out.append((t, { model.filter.years = nil })) }
        if let t = FilterText.length(f) { out.append((t, { model.filter.length = .any })) }
        if let t = FilterText.rating(f) { out.append((t, { model.filter.minRating = nil })) }
        if let t = FilterText.fame(f) { out.append((t, { model.filter.fame = .any })) }
        if let t = FilterText.countries(f) { out.append((t, { model.filter.countries = [] })) }
        if let t = FilterText.studios(f) { out.append((t, { model.filter.studios = [] })) }
        if !f.providers.isEmpty {
            let names = model.platforms.filter { f.providers.contains($0.id) }.map(\.name).joined(separator: ", ")
            out.append((Text(verbatim: names.isEmpty ? "Tus plataformas" : names), { model.filter.providers = [] }))
        }
        if f.hideWatched { out.append((Text("Sin lo que ya vi"), { model.filter.hideWatched = false })) }
        return out
    }
}
