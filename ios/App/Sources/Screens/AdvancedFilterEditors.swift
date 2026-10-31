import SwiftUI
import OrbitalCore
import OrbitalModels

/// El control de cada filtro, dentro del panel que se abre bajo su mosaico: lo que eliges se guarda al instante (sin
/// «Aplicar»). Arriba, qué se elige y «Quitar» cuando hay algo.
struct FilterEditor: View {
    let page: FilterPage
    let model: AdvancedFilterModel
    let context: FilterContext
    @Environment(AppEnvironment.self) private var env
    /// En Género: si lo que tocas es lo que quieres o lo que no.
    @State private var excluding = false

    private var filter: AdvancedFilter { model.filter }
    private func edit(_ change: (inout AdvancedFilter) -> Void) { var f = model.filter; change(&f); model.filter = f }

    var body: some View {
        HStack {
            prompt.recipe(.footnote, color: DS.textMuted).fontWeight(.semibold)
            Spacer()
            if FilterText.value(page, context) != nil {
                Button { clear() } label: { Text("Quitar").recipe(.footnote, color: DS.text).fontWeight(.semibold) }.buttonStyle(.borderless)
                    .accessibilityIdentifier("filter-clear-\(page.rawValue)")
            }
        }
        content
    }

    private var prompt: Text {
        switch page {
        case .genre: Text("Toca para elegir"); case .era: Text("Arrastra la ventana o toca una década"); case .length: Text("¿Cuánto tiempo tienes?")
        case .rating: Text("La calificación de TMDB, de 0 a 10"); case .fame: Text("Arriba lo mejor calificado; a la derecha, lo más famoso")
        case .place: Text("Tus plataformas en tu país"); case .origin: Text("Primero la región, luego el país")
        case .awards: Text("Sus ganadores"); case .studio: Text("Toca los que quieras")
        }
    }

    private func clear() {
        edit { f in
            switch page {
            case .genre: f.genres = []; f.excluded = []
            case .era: f.years = nil; f.spread = false
            case .length: f.length = .any
            case .rating: f.minRating = nil
            case .fame: f.fame = .any
            case .place: f.providers = []
            case .origin: f.countries = []
            case .awards: f.awards = []
            case .studio: f.studios = []
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch page {
        case .genre: genre
        case .era: era
        case .length: length
        case .rating: rating
        case .fame: FameQuadrant(selected: filter.fame) { fame in edit { $0.fame = fame } }
        case .place: places
        case .origin: origin
        case .awards: awards
        case .studio: studios
        }
    }

    private var genre: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            DSSegmented(options: [(false, "Quiero"), (true, "No quiero")], selection: $excluding)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.s2), count: 3), spacing: DS.Space.s2) {
                ForEach(Tmdb.genres, id: \.slug) { g in
                    let on = excluding ? filter.excluded.contains(g.slug) : filter.genres.contains(g.slug)
                    let other = excluding ? filter.genres.contains(g.slug) : filter.excluded.contains(g.slug)
                    DecideTile(title: excluding && on ? Text("Sin \(g.title)") : Text(verbatim: g.title), image: FilterCatalog.genreImage(g.slug),
                               selected: on, dimmed: other, height: DS.Filter.genreTile) {
                        // Un género está en «quiero» o en «no quiero», nunca en los dos.
                        edit { f in
                            if excluding { f.genres.remove(g.slug); f.excluded.formSymmetricDifference([g.slug]) }
                            else { f.excluded.remove(g.slug); f.genres.formSymmetricDifference([g.slug]) }
                        }
                    }
                    .accessibilityIdentifier("filter-genre-\(g.slug)")
                }
            }
            // TMDB no tiene Terror, Romance, Suspenso ni Aventura para series: lo dice en vez de traer series de otro género.
            let onlyMovies = filter.moviesOnlyGenres
            if filter.format != .movie, !onlyMovies.isEmpty {
                Text("\(onlyMovies.map(\.title).joined(separator: ", ")) solo filtra películas").recipe(.footnote, color: DS.textMuted)
            }
        }
    }

    private var era: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            VStack(alignment: .leading, spacing: 0) {
                (FilterText.years(filter) ?? Text("Cualquier año")).recipe(.title).monospacedDigit()
                eraDetail.recipe(.caption, color: DS.textMuted)
            }
            YearRuler(years: Binding(get: { filter.years }, set: { y in edit { $0.years = y } }), first: AdvancedFilter.firstYear, last: filter.currentYear)
            HStack(spacing: DS.Space.s2) {
                FilterChoice(symbol: "bolt", title: Text("Estrenos"), detail: Text("Este año y el pasado"), selected: filter.years == filter.releases) {
                    edit { $0.years = $0.years == $0.releases ? nil : $0.releases }
                }
                FilterChoice(symbol: "film.stack", title: Text("Clásicos"), detail: Text("Antes de 1990"), selected: filter.years == AdvancedFilter.classics) {
                    edit { $0.years = $0.years == AdvancedFilter.classics ? nil : AdvancedFilter.classics }
                }
            }
            Toggle(isOn: Binding(get: { filter.spread }, set: { on in edit { $0.spread = on } })) {
                Label { VStack(alignment: .leading, spacing: 0) {
                    Text("Repartido por décadas").recipe(.footnote, color: DS.text).fontWeight(.semibold)
                    Text("Una de cada época, no solo lo reciente").recipe(.caption, color: DS.textMuted)
                } } icon: { Image(systemName: "dice") }
            }
            .padding(.horizontal, DS.Space.s3).frame(minHeight: DS.Filter.choiceHeight * 0.75)
            .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
            .accessibilityIdentifier("filter-spread")
        }
    }

    private var eraDetail: Text {
        guard let y = filter.years else { return filter.spread ? Text("Una de cada década, de 1950 a hoy") : Text("De 1950 a hoy") }
        return y.lowerBound == y.upperBound ? Text("Un año") : Text("\(y.upperBound - y.lowerBound + 1) años")
    }

    private var length: some View {
        let series = filter.format == .series
        return VStack(alignment: .leading, spacing: DS.Space.s3) {
            HStack(spacing: DS.Space.s2) {
                lengthChoice(.short, "hare", Text("Cortita"), series ? Text("≤ 30 min") : Text("< 1 h 35"))
                lengthChoice(.regular, "clock", Text("Normal"), series ? Text("30–50 min") : Text("1 h 30 – 2 h 10"))
                lengthChoice(.long, "tortoise", Text("Para echarse"), series ? Text("50 min o más") : Text("2 h 10 o más"))
            }
            FilterChoice(symbol: "moon.zzz", title: Text("Que acabe antes de las \(FilterText.clock(filter.endsBy, language: context.language))"),
                         detail: Text("Caben \(Strings.duration(filter.minutesLeft))"), selected: filter.length == .before) {
                model.refreshClock()
                edit { $0.length = $0.length == .before ? .any : .before }
            }
            .accessibilityIdentifier("filter-ends-by")
            if filter.length == .before {
                Slider(value: Binding(get: { filter.endsBy < 12 ? filter.endsBy + 24 : filter.endsBy },
                                      set: { h in edit { $0.endsBy = h >= 24 ? h - 24 : h } }),
                       in: DS.Filter.endsByRange, step: DS.Filter.endsByStep) { Text("Hora a la que quieres terminar") }
                    .tint(DS.text)
                    .accessibilityValue(Text(verbatim: FilterText.clock(filter.endsBy, language: context.language)))
                    .accessibilityIdentifier("filter-ends-by-slider")
            }
        }
    }

    private func lengthChoice(_ value: AdvancedFilter.Length, _ symbol: String, _ title: Text, _ detail: Text) -> some View {
        FilterChoice(symbol: symbol, title: title, detail: detail, selected: filter.length == value) {
            edit { $0.length = $0.length == value ? .any : value }
        }
    }

    /// Una sola calificación (Fernando, 31 oct 2026): la de TMDB, que es de donde salen los resultados.
    private var rating: some View {
        let value = Binding(get: { filter.minRating ?? 0 }, set: { v in edit { $0.minRating = v < 1 ? nil : v } })
        return VStack(alignment: .leading, spacing: DS.Space.s3) {
            HStack(spacing: DS.Space.s2) {
                Image("rating-tmdb").resizable().scaledToFit().frame(height: DS.Filter.studioLogoHeight).accessibilityHidden(true)
                (filter.minRating.map { Text("\(FilterText.number($0)) o más") } ?? Text("Cualquiera")).recipe(.title).monospacedDigit()
            }
            Slider(value: value, in: 0...9, step: 0.5) { Text("Calificación mínima") }
                .tint(DS.text)
                .accessibilityIdentifier("filter-rating")
        }
    }

    @ViewBuilder private var places: some View {
        if model.platforms.isEmpty {
            Text("Aún no llegan tus plataformas.").recipe(.footnote, color: DS.textMuted)
        } else {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.s2), count: 3), spacing: DS.Space.s2) {
                ForEach(model.platforms) { p in
                    FilterLogoChoice(title: Text(verbatim: p.name), selected: filter.providers.contains(p.id)) {
                        edit { $0.providers.formSymmetricDifference([p.id]) }
                    } logo: { DSPlatformLogo(url: p.logo) }
                    .accessibilityIdentifier("filter-platform-\(p.brand)")
                }
            }
        }
    }

    private var origin: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            HStack(spacing: DS.Space.s2) {
                ForEach(FilterCatalog.regions, id: \.id) { region in
                    let all = Set(region.codes)
                    FilterLogoChoice(title: Text(region.title), selected: all.isSubset(of: filter.countries)) {
                        edit { f in if all.isSubset(of: f.countries) { f.countries.subtract(all) } else { f.countries.formUnion(all) } }
                    } logo: {
                        Text(verbatim: region.codes.prefix(3).map(FilterCatalog.flag).joined()).font(DS.TextRecipe.title.font)
                    }
                    .accessibilityIdentifier("filter-region-\(region.id)")
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.s2), count: 4), spacing: DS.Space.s2) {
                ForEach(FilterCatalog.countries, id: \.code) { c in
                    FilterLogoChoice(title: Text(verbatim: c.name), selected: filter.countries.contains(c.code)) {
                        edit { $0.countries.formSymmetricDifference([c.code]) }
                    } logo: { Text(verbatim: FilterCatalog.flag(c.code)).font(DS.TextRecipe.title.font) }
                    .accessibilityIdentifier("filter-country-\(c.code)")
                }
            }
        }
    }

    /// Cada premio con su estatuilla (las de Colecciones). Los ganadores vienen con la app: con premios, el resto de los
    /// filtros que no son formato ni época no aplica, y se dice.
    private var awards: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.s2), count: 3), spacing: DS.Space.s2) {
                ForEach(FilterCatalog.awards, id: \.self) { id in
                    FilterLogoChoice(title: AwardNames.title(id), selected: filter.awards.contains(id)) {
                        edit { $0.awards.formSymmetricDifference([id]) }
                    } logo: { Image("Awards/" + id).resizable().scaledToFit() }
                    .accessibilityIdentifier("filter-award-\(id)")
                }
            }
            if !filter.awards.isEmpty {
                Text("Con premios cuentan el formato, la época y lo que ya viste.").recipe(.caption, color: DS.textMuted)
            }
        }
    }

    /// Cada estudio con su logo de TMDB (los mismos de Colecciones › Estudios); sin logo todavía, su nombre.
    private var studios: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.s2), count: 2), spacing: DS.Space.s2) {
            ForEach(Tmdb.studios, id: \.id) { s in
                FilterLogoChoice(title: Text(verbatim: s.name), selected: filter.studios.contains(s.id)) {
                    edit { $0.studios.formSymmetricDifference([s.id]) }
                } logo: { StudioLogo(name: s.name, logo: context.studioLogos[s.id], symbolFallback: true) }
                .accessibilityIdentifier("filter-studio-\(s.id)")
            }
        }
        .task { for s in Tmdb.studios { await env.collections.loadStudioLogo(s.id) } }
    }
}
