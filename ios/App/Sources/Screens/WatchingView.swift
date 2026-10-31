import SwiftUI
import OrbitalCore
import OrbitalModels

/// Abrir «Lo que ves» desde Para ti: `.navigationDestination(for: WatchingRoute.self) { _ in WatchingView(onOpenTitle:) }`.
struct WatchingRoute: Hashable {}

/// La tarjeta de Lo que ves para Para ti, ya conectada (la semana): al tocarla empuja `WatchingRoute`.
struct WatchingCardLoader: View {
    @Environment(AppEnvironment.self) private var env
    var body: some View {
        let model = env.watching
        let _ = model.track()
        if model.linked, !model.failed {   // sin historial (falló), la tarjeta no ocupa lugar en Para ti
            let week = model.loaded ? model.stats(.week) : nil
            let language = env.services.appSettings.uiLanguage
            NavigationLink(value: WatchingRoute()) {
                WatchingCard(stats: week, name: Strings.tr("Lo que ves", language: language), genres: (week?.genres ?? []).map { WatchingText.genre($0.name, language: language) })
            }
                .buttonStyle(.plain)
                .task { await model.load() }
        }
    }
}

/// Los nombres de los géneros de Trakt en tu idioma.
enum WatchingText {
    static func genre(_ trakt: String, language: String) -> String {
        let map = ["science-fiction": "Sci-Fi", "drama": "Drama", "comedy": "Comedy", "action": "Action", "thriller": "Thriller", "horror": "Horror",
                   "romance": "Romance", "animation": "Animation", "crime": "Crime", "documentary": "Documentary", "fantasy": "Fantasy",
                   "adventure": "Adventure", "mystery": "Mystery", "family": "Family"]
        let english = map[trakt] ?? trakt.capitalized
        return Vocabulary.genres([english], language: language).first ?? english
    }
    static func period(_ p: WatchingStats.Period) -> Text {
        switch p { case .week: Text("Semana"); case .month: Text("Mes"); case .year: Text("Año"); case .all: Text("Siempre") }
    }
}

/// «Lo que ves»: tus números del periodo (semana, mes, año o siempre), el mapa día por día, las barras, tus géneros, cómo
/// calificas y lo que más viste. (El Wrapped, apagado por ahora.)
struct WatchingView: View {
    let onOpenTitle: (TitleRoute) -> Void
    @Environment(AppEnvironment.self) private var env
    @State private var wrapped: WatchingStats.Period?
    /// Lo que calificaste: todo (0) o con un número de estrellas (1…5).
    @State private var rated: RatedRoute?

    var body: some View {
        let model = env.watching
        let _ = model.track()
        let _ = env.ratings.track()
        let s = model.stats()
        let language = env.services.appSettings.uiLanguage
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Editorial.sectionGap) {
                // La portada: el arte de lo que más viste en el periodo, de orilla a orilla, con tus horas encima (como la
                // portada de Inicio). Fernando, 30 oct 2026: que no se viera genérica.
                // Las pestañas arriba de lo que cambian (antes quedaban debajo de la portada y lo que cambiaba se veía arriba).
                DSTextTabs(options: WatchingStats.Period.allCases.map { .init(id: $0, title: WatchingText.period($0)) },
                           selection: Binding(get: { model.period }, set: { model.period = $0 }))
                .accessibilityIdentifier("watching-period")
                if model.loaded, !model.failed, !s.isEmpty { hero(s) }

                if !model.loaded { DSLoadingState() }
                // No llegó el historial y no hay nada guardado: es un error, no «nada en este periodo».
                else if model.failed { DSErrorState(offline: !env.isOnline) { Task { await model.load(full: true, force: true) } } }
                else if s.isEmpty { DSEmptyState(symbol: "popcorn", title: Text("Nada en este periodo"), message: Text("Lo que veas aquí o en Trakt aparece solo.")) }
                else { content(s, model, language) }
            }
            .padding(.horizontal, DS.Space.gutter)
            .padding(.bottom, DS.Space.s8)
        }
        #if DEBUG
        .modifier(DemoScroll())   // `-demo-scroll N`: abre ya desplazado (capturas)
        #endif
        .background(Backdrop())
        .navigationTitle(Text("Lo que ves"))
        .task { await model.load(full: true) }   // aquí sí, los diez años (la tarjeta solo pidió la semana)
        .refreshable { await model.load(full: true, force: true) }
        .onChange(of: env.watchedSomething) { Task { await model.load(full: true, force: true) } }   // terminaste de ver algo: al día
        .navigationDestination(item: $rated) { r in WatchingRatedView(stars: r.stars, items: ratedItems(), onOpenTitle: onOpenTitle) }
        .fullScreenCover(item: $wrapped) { p in WrappedView(stats: model.stats(p), language: language) { wrapped = nil } }
    }

    /// La portada del periodo: el arte de lo que más viste, con su velo; el periodo en turquesa, tus horas en grande y una
    /// línea con lo demás (títulos, películas, capítulos, racha).
    private func hero(_ s: WatchingStats) -> some View {
        ZStack(alignment: .bottomLeading) {
            if let top = s.top.first {
                PosterView(url: String(format: ForYou.metahubBackground, top.imdb), title: top.title, aspect: nil, bleed: true, maxPoints: DS.Image.wide)
                    .frame(maxWidth: .infinity, maxHeight: .infinity).clipped().accessibilityHidden(true)
            }
            ArtVeil(at: DS.Watching.veilFrom, strength: .deep)
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                // Solo tus horas en azul (Fernando, 31 oct 2026); el periodo, en el gris del arte.
                periodPhrase(s.period).recipe(.footnote, color: DS.onArtSecondary).fontWeight(.semibold).lineLimit(1)
                Text(s.minutes >= 60 ? "\(s.hours) h" : "\(s.minutes) min").font(DS.TextRecipe.display.font.weight(.heavy)).foregroundStyle(DS.orbitalBlue)
                    .lineLimit(1).minimumScaleFactor(DS.Size.statScale).contentTransition(.numericText())
                heroFacts(s).recipe(.footnote, color: DS.onArtSecondary).lineLimit(2)
            }
            .padding(DS.Space.gutter)
            .onArt()
        }
        .frame(height: DS.Watching.heroHeight)
        .padding(.horizontal, -DS.Space.gutter)   // de orilla a orilla
    }

    private func periodPhrase(_ p: WatchingStats.Period) -> Text {
        switch p { case .week: Text("Esta semana"); case .month: Text("Este mes"); case .year: Text("Este año"); case .all: Text("Desde siempre") }
    }

    /// «6 títulos · 5 películas · 25 capítulos · 2 días seguidos» (lo que sea cero no se dice).
    private func heroFacts(_ s: WatchingStats) -> Text {
        var parts: [Text] = []
        if s.movies > 0 { parts.append(s.movies == 1 ? Text("1 película") : Text("\(s.movies) películas")) }
        if s.episodes > 0 { parts.append(s.episodes == 1 ? Text("1 capítulo") : Text("\(s.episodes) capítulos")) }
        if parts.isEmpty { parts.append(s.titles == 1 ? Text("1 título") : Text("\(s.titles) títulos")) }
        if s.currentStreak >= DS.Watching.streakShown { parts.append(Text("\(s.currentStreak) días seguidos")) }   // una racha de 2 no presume nada
        return parts.dropFirst().reduce(parts[0]) { Text("\($0) · \($1)") }
    }

    @ViewBuilder private func content(_ s: WatchingStats, _ model: WatchingModel, _ language: String) -> some View {
        // Lo que más viste, como el Top 10 de la app: su número grande detrás del póster.
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            DSSectionHead(title: Text("Lo que más viste"), level: .section)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: DS.Space.s3) {
                    ForEach(Array(s.top.prefix(DS.Watching.topCount).enumerated()), id: \.element.imdb) { i, t in
                        Button { onOpenTitle(TitleRoute(kind: t.kind, metaID: t.imdb, title: t.title, poster: t.poster)) } label: {
                            VStack(alignment: .leading, spacing: DS.Space.s1) {
                                RankedPosterCard(rank: i + 1, title: t.title, poster: t.poster)
                                Text(t.kind == "movie" ? "\(t.minutes / 60) h" : "\(t.plays) capítulos · \(t.minutes / 60) h").recipe(.caption, color: DS.textMuted).lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, DS.Space.gutter)
            }
            .padding(.horizontal, -DS.Space.gutter)
            .scrollClipDisabled()
        }
        // Un solo mapa con zoom: año → mes → día (Fernando, 31 oct 2026, Z1). «Tu año» vive aquí adentro.
        section(Text("Día por día")) {
            WatchingZoomMap(plays: model.plays, startLevel: model.period == .week || model.period == .month ? .month : .year, locale: env.uiLocale)
        }
        // «Cuándo ves», fuera (Fernando, 31 oct 2026): repetía lo del calendario.
        if !s.genres.isEmpty { section(Text("Tus géneros")) { WatchingGenres(genres: s.genres) { WatchingText.genre($0, language: language) } } }
        ratings
        // El Wrapped, apagado por ahora (Fernando, 31 oct 2026): `WrappedView` sigue lista para volver.
    }


    /// Cómo calificas (Fernando, 31 oct 2026, opción R1): primero «Tus 5 estrellas», los pósters de lo que más te gustó;
    /// debajo cuántas de cada número de estrellas y tu promedio (tus calificaciones de Trakt).
    @ViewBuilder private var ratings: some View {
        let mine = env.ratings.ratings.filter { RatingKey.parseEpisode($0.key) == nil }
        let all = Array(mine.values)
        if !all.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                // A la derecha, todo lo que calificaste (Fernando, 31 oct 2026); tocar una barra, los de ese número.
                DSSectionHead(title: Text("Cómo calificas"), action: { rated = RatedRoute(stars: 0) }, chevron: true, level: .section)
                let five = fiveStars(mine)
                if !five.isEmpty {
                    DSSectionHead(title: Text("Tus 5 estrellas"), count: five.count, eyebrow: Text("Lo que más te gustó"))
                    WatchingFiveStars(items: five) { onOpenTitle(TitleRoute(kind: $0.kind, metaID: $0.id, title: $0.title, poster: $0.poster)) }
                        .accessibilityIdentifier("watching-five-stars")
                }
                let counts = (1...5).map { star in all.filter { Int((RatingScale.stars(trakt: $0)).rounded(.up)) == star }.count }
                WatchingBars(values: counts, labels: (1...5).map { "\($0)★" }) { i in rated = RatedRoute(stars: i + 1) }
                    .accessibilityIdentifier("watching-rating-bars")
                Text("Tu promedio: \(String(format: "%.1f", all.map { RatingScale.stars(trakt: $0) }.reduce(0, +) / Double(all.count))) estrellas")
                    .recipe(.footnote, color: DS.textMuted)
            }
        }
    }

    /// Todo lo que calificaste y está en tu historial (de ahí salen su nombre y si es serie), con sus estrellas.
    private func ratedItems() -> [WatchingRatedView.Item] {
        let mine = env.ratings.ratings.filter { RatingKey.parseEpisode($0.key) == nil }
        var seen = Set<String>(), out: [WatchingRatedView.Item] = []
        for play in env.watching.plays.sorted(by: { $0.at > $1.at }) where seen.insert(play.imdb).inserted {
            guard let trakt = mine[play.imdb] else { continue }
            out.append(.init(id: play.imdb, title: play.title, kind: play.kind, stars: Int(RatingScale.stars(trakt: trakt).rounded(.up))))
        }
        return out
    }

    /// Lo que calificaste con 5 y está en tu historial (de ahí salen su nombre y si es serie), de lo más reciente a lo más viejo.
    private func fiveStars(_ mine: [String: Int]) -> [WatchingFiveStars.Item] {
        var seen = Set<String>(), out: [WatchingFiveStars.Item] = []
        for play in env.watching.plays.sorted(by: { $0.at > $1.at }) where (mine[play.imdb] ?? 0) >= DS.Watching.fiveStars && seen.insert(play.imdb).inserted {
            out.append(.init(id: play.imdb, title: play.title, kind: play.kind, poster: String(format: ForYou.metahubPoster, play.imdb)))
        }
        return out
    }

    private func section(_ title: Text, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) { DSSectionHead(title: title, level: .section); content() }
    }


    private func label(_ d: Date, _ p: WatchingStats.Period) -> String {
        let style: Strings.DateStyle = switch p { case .week: .weekdayInitial; case .month: .dayNumber; case .year: .monthInitial; case .all: .yearShort }
        return Strings.date(d, style, language: env.services.appSettings.uiLanguage)
    }
}

/// Abrir lo que calificaste: `stars` 0 es todo; 1…5, solo con ese número.
struct RatedRoute: Hashable, Identifiable { let stars: Int; var id: Int { stars } }

/// Lo que calificaste, en pósters, del 5 al 1 (o solo un número de estrellas). Tocar uno abre su ficha.
struct WatchingRatedView: View {
    struct Item: Identifiable { let id: String; let title: String; let kind: String; let stars: Int }
    let stars: Int
    let items: [Item]
    let onOpenTitle: (TitleRoute) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Editorial.sectionGap) {
                ForEach((stars == 0 ? Array((1...5).reversed()) : [stars]), id: \.self) { star in
                    let group = items.filter { $0.stars == star }
                    if !group.isEmpty {
                        VStack(alignment: .leading, spacing: DS.Space.s3) {
                            DSSectionHead(title: Text(verbatim: String(repeating: "★", count: star)), count: group.count, level: .section)
                            DSPosterGrid(items: group) { item, width in
                                Button {
                                    onOpenTitle(TitleRoute(kind: item.kind, metaID: item.id, title: item.title, poster: String(format: ForYou.metahubPoster, item.id)))
                                } label: {
                                    PosterView(url: String(format: ForYou.metahubPoster, item.id), title: item.title).frame(width: width)
                                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(Text(verbatim: item.title))
                            }
                        }
                    }
                }
                if items.filter({ stars == 0 || $0.stars == stars }).isEmpty {
                    DSEmptyState(symbol: "star", title: Text("Nada con esa calificación"), message: Text("Lo que califiques en Trakt aparece aquí."))
                }
            }
            .padding(.horizontal, DS.Space.gutter).padding(.bottom, DS.Space.s14)
        }
        .background(Backdrop())
        .navigationTitle(stars == 0 ? Text("Lo que calificaste") : Text("Con \(stars) estrellas"))
    }
}

extension WatchingStats.Period: @retroactive Identifiable { public var id: String { rawValue } }

/// «Lo que ves» desde Ajustes: lo que más viste abre su ficha en esa misma pila.
struct WatchingFromSettings: View {
    @State private var route: TitleRoute?
    var body: some View { WatchingView { route = $0 }.openingTitles(item: $route) }
}
