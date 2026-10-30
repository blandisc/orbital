import SwiftUI
import OrbitalCore
import OrbitalModels

/// Los grupos de Para ti › Listas, en orden (el menú «Ir a una sección» los lista así).
enum CollectionSection: CaseIterable, Hashable {
    case forYou, platforms, studios, seasons, genres, awards, years, airings, trakt, addons, yourYear
    var title: Text {
        switch self {
        case .forYou: Text("Para ti"); case .trakt: Text("Listas de Trakt"); case .addons: Text("De tus complementos")
        case .platforms: Text("Plataformas"); case .awards: Text("Premios"); case .studios: Text("Estudios"); case .years: Text("Por año")
        case .seasons: Text("Temporadas"); case .genres: Text("Lo mejor del género")
        case .airings: Text("Próximos estrenos"); case .yourYear: Text("Tu año")
        }
    }

    /// Un ícono por sección en el índice de arriba (más fácil de encontrar de un vistazo).
    var symbol: String {
        switch self {
        case .forYou: "sparkles"; case .platforms: "play.tv"; case .studios: "film.stack"; case .awards: "trophy"
        case .seasons: "leaf"; case .genres: "medal"
        case .years: "calendar"; case .airings: "calendar.badge.clock"; case .trakt: "list.bullet.rectangle"; case .addons: "puzzlepiece.extension"
        case .yourYear: "square.grid.3x3.fill"
        }
    }
}

/// Marca el grupo que cruza la parte de arriba de la pantalla (el menú lo palomea) y le da su id para saltar a él.
struct SectionSpy: ViewModifier {
    let section: CollectionSection
    @Binding var active: CollectionSection

    func body(content: Content) -> some View {
        content
            .id(section)
            .onGeometryChange(for: Bool.self) { proxy in
                let frame = proxy.frame(in: .scrollView)
                return frame.minY <= DS.Collections.spyLine && frame.maxY > DS.Collections.spyLine
            } action: { inside in if inside { active = section } }
    }
}

/// Una colección abierta: un premio, un año, Mi lista de Stremio, un estudio, una temporada o un género (su slug).
struct CollectionRoute: Hashable {
    enum Kind: Hashable { case award, year, myList, studio, season, genre }
    let kind: Kind
    let id: String
}

/// Una colección en cuadrícula de pósters (con ordenar y filtrar): los ganadores de un premio (con el año del premio), Mi
/// lista de Stremio, o lo más popular de un año (películas o series).
struct CollectionGridView: View {
    var collections: ModelObserver<CollectionsModel>
    let route: CollectionRoute
    @State private var kind = "movie"
    @State private var yearItems: [Suggestion] = []
    @State private var loading = false
    @State private var loadedOnce = false
    @State private var settled = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                header
                if route.kind == .year {
                    DSKindFilter(kind: $kind, includeAll: false).padding(.horizontal, DS.Space.gutter)
                }
                if route.kind == .genre {
                    rankedGrid   // un Top: en su orden, con el puesto (como la TV), sin ordenar ni filtrar
                } else {
                    // Un año ya trae su Películas · Series arriba: el menú no repite ese filtro.
                    SortableGrid(listID: "\(route.kind):\(route.id)", items: items, collections: collections.model, watched: { await collections.model.watchedIDs() },
                                 imdbRatings: { items in await collections.model.imdbRatings(items.map { ($0.kind, $0.imdb) }) },
                                 showsKindFilter: route.kind != .year, loading: isLoading) { s, width in
                        TitleLink(route: s.route, width: width, detail: detail(s))
                    }
                }
            }
            .padding(.bottom, DS.Space.s14)
        }
        .background(Backdrop())
        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        .task {
            // Un estudio se pide aquí; un premio llega con las colecciones. Si al final no hay nada (falló o tardó
            // demasiado), el vacío en lugar de la ruedita para siempre.
            if route.kind == .studio, let id = Int(route.id) { await collections.model.loadStudio(id) }
            else if route.kind == .season { await collections.model.loadSeason(route.id) }
            else if route.kind == .genre { await collections.model.loadGenre(route.id) }
            else { try? await Task.sleep(nanoseconds: DS.Timing.listGiveUp) }
            settled = true
        }
        .task(id: kind) {
            guard route.kind == .year, let year = Int(route.id) else { return }
            loading = true
            let found = await collections.model.items(year: year, kind: kind)
            guard !Task.isCancelled else { return }   // cambiaste de Películas a Series: no se pinta lo del otro
            yearItems = found
            loading = false
            loadedOnce = true
        }
    }

    /// El premio: su estatuilla grande con su halo y cuántos ganadores hay.
    @ViewBuilder private var header: some View {
        if route.kind == .award, let award {
            HStack(spacing: DS.Space.s4) {
                AwardEmblem(id: award.id)
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    AwardNames.title(award.id).recipe(.title)
                    AwardNames.category(award.id).recipe(.footnote)
                }
            }
            .padding(.horizontal, DS.Space.gutter).padding(.top, DS.Space.s2)
        } else if let heading {
            // Una temporada o un género: su ícono con el halo de su color, el título de la lista y su renglón.
            HStack(spacing: DS.Space.s4) {
                CollectionIconEmblem(slug: route.id, name: "", size: DS.Collections.iconHeader, glow: heading.tint)
                    .padding(DS.Space.s3)
                    .background(heading.tint, in: RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    heading.title.recipe(.title).fixedSize(horizontal: false, vertical: true)
                    if let meta = heading.meta { meta.recipe(.footnote) }
                }
            }
            .padding(.horizontal, DS.Space.gutter).padding(.top, DS.Space.s2)
        }
    }

    private var language: String { AppEnvironment.shared.services.appSettings.uiLanguage }

    /// El encabezado de una temporada (su nombre y su frase) o de un género: «Lo mejor de Terror en 2026» con el año de verdad
    /// y, abajo, si alcanzó la nota o de dónde salió (`_genre_heading` de la TV).
    private var heading: (title: Text, meta: Text?, tint: Color)? {
        switch route.kind {
        case .season:
            guard let season = Tmdb.seasons.first(where: { $0.slug == route.id }) else { return nil }
            return (Text(verbatim: Strings.tr(season.title, language: language)), Text(verbatim: Strings.tr(season.blurb, language: language)),
                    DS.Collections.season(season.slug))
        case .genre:
            guard let genre = Tmdb.genres.first(where: { $0.slug == route.id }) else { return nil }
            let name = Strings.tr(genre.title, language: language)
            guard let chart = collections.model.genreCharts[genre.slug] else { return (Text(verbatim: name), nil, DS.Collections.studio) }
            let asked = String(chart.asked), used = String(chart.year)
            let meta: Text = switch chart.basis {
            case .votes: Text("Las mejor calificadas del año")
            case .popular: Text("Las más populares de \(used)")
            case .previous: Text("Pocas de \(asked): las mejor calificadas de \(used)")
            case .previousPopular: Text("Pocas de \(asked): lo más visto en \(used)")
            }
            return (Text("Lo mejor de \(name) en \(used)"), meta, DS.Collections.studio)
        default: return nil
        }
    }

    /// El Top de un género: de dos en dos, con la cifra grande detrás del póster (como los rankings de una plataforma).
    @ViewBuilder private var rankedGrid: some View {
        if items.isEmpty {
            if isLoading { ProgressView().frame(maxWidth: .infinity).padding(.vertical, DS.Space.s14) }
            else { DSEmptyState(symbol: "tray", title: Text("Nada por aquí por ahora"), message: Text("Esta lista todavía no tiene títulos.")) }
        } else {
            LazyVGrid(columns: DS.Poster.pairColumns(spacing: DS.Space.s3), spacing: DS.Space.s5) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, s in
                    TitleNavigationLink(route: s.route) {
                        RankedPosterCard(rank: s.rank ?? index + 1, title: s.title, poster: s.poster).titleZoomSource(s.route)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DS.Space.gutter)
        }
    }

    /// Todavía viene en camino (un año que se pide, un estudio o un premio sin cargar).
    private var isLoading: Bool {
        switch route.kind {
        case .year: loading || yearItems.isEmpty && !loadedOnce
        case .studio: !settled && Int(route.id).flatMap { collections.model.studioItems[$0] } == nil
        case .season: !settled && collections.model.seasonItems[route.id] == nil
        case .genre: !settled && collections.model.genreCharts[route.id] == nil
        case .award: !settled && award == nil
        case .myList: false
        }
    }

    private var award: AwardCollection? { collections.model.awards.first { $0.id == route.id } }

    private var items: [Suggestion] {
        switch route.kind {
        case .award: award?.suggestions ?? []
        case .year: yearItems
        case .myList: collections.model.myList
        case .studio: Int(route.id).flatMap { collections.model.studioItems[$0] } ?? []
        case .season: collections.model.seasonItems[route.id] ?? []
        case .genre: collections.model.genreCharts[route.id]?.items ?? []
        }
    }

    private var title: Text {
        switch route.kind {
        case .award: award.map { AwardNames.title($0.id) } ?? Text("Premios")
        case .year: Text(verbatim: route.id)
        case .myList: Text("Mi lista")
        case .studio: Text(verbatim: collections.model.studios.first { String($0.id) == route.id }?.name ?? "")
        case .season: Text(verbatim: Tmdb.seasons.first { $0.slug == route.id }.map { Strings.tr($0.title, language: language) } ?? "")
        case .genre: Text(verbatim: Tmdb.genres.first { $0.slug == route.id }.map { Strings.tr($0.title, language: language) } ?? "")
        }
    }

    /// Bajo cada póster: el año del premio (en un premio) o el año del título.
    private func detail(_ s: Suggestion) -> Text? {
        if route.kind == .award, case .console(let year) = s.reason { return Text(verbatim: year) }
        return s.year.map { Text(verbatim: String($0)) }
    }
}
