import SwiftUI
import OrbitalCore
import OrbitalModels

/// Los resultados del filtro avanzado, en su propia pantalla dentro de Buscar (a pantalla completa, y una ficha se abre
/// encima sin cerrar nada): arriba lo filtrado en cuadritos con ícono (tocar uno reabre el cajón en ese filtro; mantenerlo
/// presionado lo quita) y «＋ Filtro»; el orden en la barra; la cuadrícula de pósters con su calificación, año y duración,
/// por páginas al bajar.
struct FilterResultsView: View {
    @Environment(\.titleName) var titleName
    let model: AdvancedFilterModel
    /// Reabre el cajón (en ese filtro, o sin nada abierto).
    let edit: (FilterPage?) -> Void
    @Environment(AppEnvironment.self) private var env
    @State private var openTitle: TitleRoute?

    var body: some View {
        let _ = model.track()
        let language = env.services.appSettings.uiLanguage
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Layout.titleToContent) {
                if let count = model.count {
                    // Opción A (Fernando, 2 nov 2026): la cifra al frente y, debajo, cuántas películas y cuántas series.
                    ResultCountHeader(count: count, beforeWatched: model.filter.hideWatched && model.filter.awards.isEmpty, language: language)
                        .padding(.horizontal, DS.Space.gutter)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DS.Space.s2) {
                        ForEach(squares(language), id: \.id) { s in
                            FilterSummarySquare(symbol: s.symbol, title: s.title, hue: s.hue, edit: { edit(s.page) }, remove: s.remove)   // no-es-título: el resumen de un filtro
                                .accessibilityIdentifier("filter-square-\(s.id)")
                        }
                        FilterSummarySquare(symbol: "plus", title: Text("Filtro"), edit: { edit(nil) }).accessibilityIdentifier("filter-edit")
                    }
                    .padding(.horizontal, DS.Space.gutter)
                }
                .scrollClipDisabled()
                if !model.filter.awards.isEmpty {
                    Text("Con premios cuentan el formato, la época y lo que ya viste.").recipe(.caption, color: DS.textMuted)
                        .padding(.horizontal, DS.Space.gutter)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: DS.Filter.resultWidth), spacing: DS.Space.s3)], spacing: DS.Space.s4) {
                    ForEach(model.results) { s in
                        Button { openTitle = s.route } label: { cell(s) }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("filter-result")
                            .onAppear { if s.id == model.results.last?.id { Task { await model.more() } } }
                    }
                }
                .padding(.horizontal, DS.Space.gutter)
                if model.isLoading { DSLoadingState() }
            }
            .padding(.bottom, DS.Space.s4)
        }
        .overlay {
            // Los premios vienen con la app: sin la clave de TMDB sí cargan, y el aviso de la clave ya no los tapa.
            if !model.available, model.filter.awards.isEmpty {
                DSEmptyState(symbol: "key", title: Text("Falta la clave de TMDB"), message: Text("Agrégala en Ajustes › Avanzado para buscar con filtros."))
            } else if model.letterboxdDown, model.results.isEmpty {
                DSEmptyState(symbol: "wifi.slash", title: Text("Letterboxd no contestó. Intenta de nuevo en un momento."), message: Text("Quita las estrellas de Letterboxd para ver los resultados de TMDB."))
            } else if model.failed {
                DSEmptyState(symbol: "wifi.slash", title: Text("No se pudo cargar"), message: Text("Revisa tu conexión e intenta de nuevo."))
            } else if let nothing = model.filter.nothing {
                // No se buscó nada, y se dice por qué (antes, «Nada con esos filtros»).
                switch nothing {
                case .noMovieFits:
                    DSEmptyState(symbol: "clock", title: Text("No cabe ninguna película antes de esa hora"), message: Text("Elige una hora más tarde o busca series."))
                case .seriesGenres(let titles):
                    DSEmptyState(symbol: "line.3.horizontal.decrease", title: Text("TMDB no tiene \(ListFormatter.localizedString(byJoining: titles)) en series"),
                                 message: Text("Busca películas o elige otro género."))
                }
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
                        Label("Mejor calificadas en Letterboxd", systemImage: "star.bubble").tag(AdvancedFilter.Sort.letterboxd)
                        Label("Más nuevas", systemImage: "calendar").tag(AdvancedFilter.Sort.newest)
                    } label: { EmptyView() }
                } label: { Label("Ordenar", systemImage: "arrow.up.arrow.down") }
                .accessibilityIdentifier("filter-sort")
            }
        }
        .openingTitles(item: $openTitle)
        .task { await model.search() }
        .onChange(of: model.filter.withoutClock) { Task { await model.search() } }   // quitaste un filtro o cambiaste el orden: otra vez desde la primera página
    }

    private func cell(_ s: Suggestion) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            PosterView(url: s.poster, title: titleName(s.title, id: s.imdb, kind: s.kind))
                .overlay(alignment: .bottomLeading) {
                    // Con Letterboxd, su promedio (en su verde); si no, el de TMDB.
                    if let r = s.letterboxdRating ?? s.tmdbRating {
                        Label { Text(verbatim: FilterText.number((r * 10).rounded() / 10)) } icon: { Image(systemName: "star.fill") }
                            .recipe(.badge, color: s.letterboxdRating != nil ? DS.Letterboxd.leaf : DS.paper)
                            .padding(.horizontal, DS.Space.s2).padding(.vertical, DS.Space.s1 / 2)
                            .background(DS.badgeBackground, in: Capsule())
                            .padding(DS.Space.s1)
                    }
                }
            Text(verbatim: titleName(s.title, id: s.imdb, kind: s.kind)).recipe(.footnote).lineLimit(1)
            facts(s).recipe(.caption, color: DS.textMuted).lineLimit(1)
        }
    }

    /// «2018 · 2 h 7 min» (lo que falte, no se dice).
    private func facts(_ s: Suggestion) -> Text {
        var parts: [String] = []
        if let y = s.year { parts.append(String(y)) }
        if let m = s.runtime, m > 0 { parts.append(Strings.duration(m)) }
        return Text(verbatim: parts.joined(separator: " · "))
    }

    private struct Square { let id: String; let page: FilterPage?; let symbol: String; let title: Text; let remove: () -> Void; var hue: Color { page?.hue ?? DS.text } }

    /// Lo puesto, un cuadrito por filtro, con cómo quitarlo.
    private func squares(_ language: String) -> [Square] {
        let f = model.filter
        let context = FilterContext(filter: f, platforms: model.platforms, language: language)
        var out: [Square] = []
        if let t = FilterText.format(f) {
            out.append(Square(id: "format", page: nil, symbol: KindGlyph.symbol(f.format == .movie ? "movie" : "series"), title: t) {
                model.filter.format = .all; model.filter.seriesStatus = .any
            })
        }
        for page in FilterPage.main + FilterPage.more {
            guard let t = FilterText.value(page, context) else { continue }
            out.append(Square(id: page.rawValue, page: page, symbol: page.symbol, title: t) { remove(page) })
        }
        // «Mejor calificadas en Letterboxd» con «Todo» deja solo películas: se ve, y tocarlo regresa a «Más populares».
        if f.sort == .letterboxd, f.format == .all {
            out.append(Square(id: "letterboxd-sort", page: nil, symbol: "film", title: Text("Solo películas: Letterboxd")) { model.filter.sort = .popular })
        }
        if f.hideWatched {
            out.append(Square(id: "hide-watched", page: nil, symbol: "eye.slash", title: Text("Sin vistas")) { model.filter.hideWatched = false })
        }
        return out
    }

    private func remove(_ page: FilterPage) {
        switch page {
        case .genre: model.filter.genres = []; model.filter.excluded = []
        case .era: model.filter.years = nil; model.filter.spread = false
        case .length: model.filter.length = .any
        case .rating: model.filter.minRating = nil; model.filter.minLetterboxd = nil
        case .fame: model.filter.fame = .any
        case .place: model.filter.providers = []
        case .origin: model.filter.countries = []
        case .awards: model.filter.awards = []
        case .studio: model.filter.studios = []
        }
    }
}
