import SwiftUI
import OrbitalCore
import OrbitalModels

extension View {
    /// El filtro avanzado como hoja (Inicio, Para ti y Buscar lo montan igual): el cajón de dos alturas, cada filtro se abre
    /// dentro de él y «Ver resultados» trae la cuadrícula ahí mismo. Tocar un título cierra la hoja y avisa con `onOpenTitle`.
    func advancedFilter(isPresented: Binding<Bool>, onOpenTitle: @escaping (TitleRoute) -> Void) -> some View {
        sheet(isPresented: isPresented) {
            AdvancedFilterSheet { route in
                isPresented.wrappedValue = false
                onOpenTitle(route)
            }
        }
    }
}

/// Las páginas que se abren dentro del cajón.
enum FilterPage: Hashable { case format, genre, era, length, rating, fame, origin, studio, results }

/// El cajón del filtro avanzado: seis filtros principales y «Ver más» (origen y estudios). Corto mientras eliges; crece al
/// abrir un filtro o los resultados.
struct AdvancedFilterSheet: View {
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
                    if page == .results { FilterResults(model: model, onOpenTitle: onOpenTitle) }
                    else { FilterEditor(page: page, filter: Binding(get: { model.filter }, set: { model.filter = $0 })) }
                }
                .onAppear { detent = .large }
            }
        }
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
            .buttonStyle(.borderedProminent).buttonBorderShape(.capsule).controlSize(.large)
            .tint(DS.solidPrimary).foregroundStyle(DS.onSolidPrimary)   // el principal sólido de la app: se lee siempre
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

/// Los resultados dentro del cajón: la cuadrícula de pósters, por páginas al bajar.
struct FilterResults: View {
    let model: AdvancedFilterModel
    let onOpenTitle: (TitleRoute) -> Void

    var body: some View {
        let _ = model.track()
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: DS.Filter.resultWidth), spacing: DS.Space.s3)], spacing: DS.Space.s4) {
                ForEach(model.results) { s in
                    Button { onOpenTitle(s.route) } label: {
                        VStack(alignment: .leading, spacing: DS.Space.s1) {
                            PosterView(url: s.poster, title: s.title)
                            Text(s.title).recipe(.footnote).lineLimit(1)
                            if let year = s.year { Text(verbatim: String(year)).recipe(.caption, color: DS.textMuted) }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("filter-result")
                    .onAppear { if s.id == model.results.last?.id { Task { await model.more() } } }
                }
            }
            .padding(.horizontal, DS.Space.gutter)
            if model.isLoading { ProgressView().padding(DS.Space.s6) }
        }
        .overlay {
            if !model.available {
                ContentUnavailableView("Falta la clave de TMDB", systemImage: "key", description: Text("Agrégala en Ajustes › Avanzado para buscar con filtros."))
            } else if model.failed {
                ContentUnavailableView("No se pudo cargar", systemImage: "wifi.slash", description: Text("Revisa tu conexión e intenta de nuevo."))
            } else if model.results.isEmpty, !model.isLoading {
                ContentUnavailableView("Nada con esos filtros", systemImage: "line.3.horizontal.decrease", description: Text("Quita alguno para ver más opciones."))
            }
        }
        .navigationTitle(Text("Resultados"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.search() }
    }
}
