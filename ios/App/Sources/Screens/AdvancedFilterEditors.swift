import SwiftUI
import OrbitalCore

/// Cada filtro abierto dentro del cajón: lo que eliges se guarda al instante (sin «Aplicar»); se regresa con la flecha.
struct FilterEditor: View {
    let page: FilterPage
    @Binding var filter: AdvancedFilter
    /// En Género: si lo que tocas es lo que quieres o lo que no.
    @State private var excluding = false

    static let countries: [(code: String, name: String)] = [
        ("MX", "México"), ("US", "Estados Unidos"), ("ES", "España"), ("GB", "Reino Unido"), ("FR", "Francia"),
        ("KR", "Corea del Sur"), ("JP", "Japón"), ("IT", "Italia"), ("AR", "Argentina"), ("DE", "Alemania"),
        ("CO", "Colombia"), ("IN", "India"), ("BR", "Brasil"), ("SE", "Suecia"), ("DK", "Dinamarca"),
    ]
    static let decades = [1980, 1990, 2000, 2010, 2020]
    static let genreArt = ["accion": "action", "aventura": "action", "animacion": "animation", "comedia": "comedy", "crimen": "crime",
                           "documental": "documentary", "drama": "drama", "familia": "animation", "fantasia": "fantasy", "terror": "horror",
                           "misterio": "mystery", "romance": "romance", "ciencia-ficcion": "scifi", "suspenso": "thriller"]

    var body: some View {
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
    }

    private var title: Text {
        switch page {
        case .format: Text("Formato"); case .genre: Text("Género"); case .era: Text("Época"); case .length: Text("Tiempo")
        case .rating: Text("Calificación"); case .fame: Text("Qué tan conocida"); case .origin: Text("Origen"); case .studio: Text("Estudios")
        case .results: Text("Resultados")
        }
    }

    @ViewBuilder private var content: some View {
        switch page {
        case .origin: checklist(Self.countries.map { ($0.code, Text(verbatim: "\(Self.flag($0.code)) \($0.name)")) }, selected: filter.countries) { filter.countries = $0 }
        case .studio: checklist(Tmdb.studios.map { (String($0.id), Text(verbatim: $0.name)) }, selected: Set(filter.studios.map(String.init))) { filter.studios = Set($0.compactMap(Int.init)) }
        default: ScrollView { VStack(alignment: .leading, spacing: DS.Space.s4) { scrolling }.padding(DS.Space.gutter) }
        }
    }

    @ViewBuilder private var scrolling: some View {
        switch page {
        case .format: format
        case .genre: genre
        case .era: era
        case .length: length
        case .rating: rating
        case .fame:
            Text("Arriba lo mejor calificado; a la derecha, lo más famoso.").recipe(.footnote, color: DS.textMuted)
            FameQuadrant(selected: filter.fame) { filter.fame = $0 }
        default: EmptyView()
        }
    }

    private var format: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            HStack(spacing: DS.Space.s2) {
                FilterChoice(symbol: KindGlyph.all, title: Text("Todo"), selected: filter.format == .all) { filter.format = .all }
                FilterChoice(symbol: KindGlyph.movie, title: Text("Películas"), selected: filter.format == .movie) { filter.format = .movie }
                FilterChoice(symbol: KindGlyph.series, title: Text("Series"), selected: filter.format == .series) { filter.format = .series }
            }
            // Series: en emisión o terminadas aparece aquí mismo (no es otro filtro).
            if filter.format == .series {
                Text("¿Cuáles series?").recipe(.footnote, color: DS.textMuted)
                HStack(spacing: DS.Space.s2) {
                    FilterChoice(symbol: "infinity", title: Text("Todas"), selected: filter.seriesStatus == .any) { filter.seriesStatus = .any }
                    FilterChoice(symbol: "dot.radiowaves.left.and.right", title: Text("En emisión"), selected: filter.seriesStatus == .airing) { filter.seriesStatus = .airing }
                    FilterChoice(symbol: "checkmark.seal", title: Text("Terminadas"), selected: filter.seriesStatus == .ended) { filter.seriesStatus = .ended }
                }
            }
        }
    }

    private var genre: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            DSSegmented(options: [(false, "Quiero"), (true, "Quitar")], selection: $excluding)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: DS.Space.s2), GridItem(.flexible(), spacing: DS.Space.s2)], spacing: DS.Space.s2) {
                ForEach(Tmdb.genres, id: \.slug) { g in
                    let on = excluding ? filter.excluded.contains(g.slug) : filter.genres.contains(g.slug)
                    let other = excluding ? filter.genres.contains(g.slug) : filter.excluded.contains(g.slug)
                    DecideTile(title: excluding && on ? Text("Sin \(g.title)") : Text(verbatim: g.title), image: "decide-genre-\(Self.genreArt[g.slug] ?? "drama")",
                               selected: on, dimmed: other, height: DS.Filter.genreTile) {
                        // Un género está en «quiero» o en «quitar», nunca en los dos.
                        if excluding { filter.genres.remove(g.slug); filter.excluded.formSymmetricDifference([g.slug]) }
                        else { filter.excluded.remove(g.slug); filter.genres.formSymmetricDifference([g.slug]) }
                    }
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
            Text("Toca una década; toca otra para hacer un rango.").recipe(.footnote, color: DS.textMuted)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: DS.Space.s2), GridItem(.flexible(), spacing: DS.Space.s2)], spacing: DS.Space.s2) {
                FilterChoice(symbol: "film.stack", title: Text("Clásicas"), detail: Text("Antes de 1980"), selected: filter.years == 1900...1979) {
                    filter.years = filter.years == 1900...1979 ? nil : 1900...1979
                }
                ForEach(Self.decades, id: \.self) { d in
                    DecideTile(title: Text(verbatim: "\(d % 100 == 0 ? "2000" : String(format: "%02d", d % 100))s"), image: "decide-era-\(d)",
                               selected: filter.years.map { $0.lowerBound <= d && d + 9 <= $0.upperBound } ?? false, height: DS.Filter.eraTile, era: true) {
                        filter.years = Self.toggle(decade: d, in: filter.years)
                    }
                }
            }
        }
    }

    /// Una década sola; otra fuera del rango lo estira hasta ella; la única elegida, otra vez, lo quita; una de adentro deja
    /// solo esa.
    static func toggle(decade d: Int, in years: ClosedRange<Int>?) -> ClosedRange<Int>? {
        let one = d...(d + 9)
        guard let years, years.lowerBound >= 1980 else { return one }
        if years == one { return nil }
        if years.lowerBound <= d && d + 9 <= years.upperBound { return one }
        return min(years.lowerBound, d)...max(years.upperBound, d + 9)
    }

    private var length: some View {
        HStack(spacing: DS.Space.s2) {
            FilterChoice(symbol: "hare", title: Text("Corta"), detail: filter.format == .series ? Text("≤ 30 min") : Text("≤ 1 h 35"), selected: filter.length == .short) { filter.length = filter.length == .short ? .any : .short }
            FilterChoice(symbol: "clock", title: Text("Normal"), detail: filter.format == .series ? Text("30–50 min") : Text("1 h 30 – 2 h 10"), selected: filter.length == .regular) { filter.length = filter.length == .regular ? .any : .regular }
            FilterChoice(symbol: "tortoise", title: Text("Larga"), detail: filter.format == .series ? Text("50 min o más") : Text("2 h 10 o más"), selected: filter.length == .long) { filter.length = filter.length == .long ? .any : .long }
        }
    }

    private var rating: some View {
        let value = Binding(get: { filter.minRating ?? 0 }, set: { filter.minRating = $0 < 1 ? nil : $0 })
        return VStack(alignment: .leading, spacing: DS.Space.s3) {
            HStack {
                Image(systemName: "star.fill").foregroundStyle(DS.Rating.filled).accessibilityHidden(true)
                (filter.minRating.map { Text("\($0.formatted(.number.precision(.fractionLength(1)))) o más") } ?? Text("Cualquiera")).recipe(.title)
            }
            Slider(value: value, in: 0...9, step: 0.5) { Text("Calificación mínima") }
                .tint(DS.brandMoon)
                .accessibilityIdentifier("filter-rating")
            Text("La calificación de la comunidad de TMDB, de 0 a 10.").recipe(.footnote, color: DS.textMuted)
        }
    }

    private func checklist(_ items: [(String, Text)], selected: Set<String>, set: @escaping (Set<String>) -> Void) -> some View {
        List(items, id: \.0) { id, label in
            Button {
                var now = selected
                if now.contains(id) { now.remove(id) } else { now.insert(id) }
                set(now)
            } label: {
                HStack {
                    label.recipe(.body, color: DS.text)
                    Spacer()
                    if selected.contains(id) { Image(systemName: "checkmark").foregroundStyle(DS.brandMoon) }
                }
            }
            .accessibilityAddTraits(selected.contains(id) ? .isSelected : [])
        }
    }

    /// La bandera de un país («MX» → 🇲🇽).
    static func flag(_ code: String) -> String {
        String(String.UnicodeScalarView(code.uppercased().unicodeScalars.compactMap { Unicode.Scalar(127_397 + $0.value) }))
    }
}
