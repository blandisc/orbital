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
                WatchingCard(stats: week, genres: (week?.genres ?? []).map { WatchingText.genre($0.name, language: language) })
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
/// calificas y lo que más viste. Arriba, el botón grande de tu Wrapped.
struct WatchingView: View {
    let onOpenTitle: (TitleRoute) -> Void
    @Environment(AppEnvironment.self) private var env
    @State private var wrapped: WatchingStats.Period?

    var body: some View {
        let model = env.watching
        let _ = model.track()
        let _ = env.ratings.track()
        let s = model.stats()
        let language = env.services.appSettings.uiLanguage
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Editorial.sectionGap) {
                DSSegmented(labeled: WatchingStats.Period.allCases.map { ($0, WatchingText.period($0)) },
                            selection: Binding(get: { model.period }, set: { model.period = $0 }))
                .accessibilityIdentifier("watching-period")

                if model.period != .all {
                    Button { wrapped = model.period } label: {
                        Label { Text("Ver tu Wrapped") } icon: { Image(systemName: "sparkles.rectangle.stack") }.frame(maxWidth: .infinity)
                    }
                    .dsSolidPrimaryButton().controlSize(.large)
                    .disabled(s.isEmpty)
                    .accessibilityIdentifier("watching-wrapped")
                }

                if !model.loaded { DSLoadingState() }
                // No llegó el historial y no hay nada guardado: es un error, no «nada en este periodo».
                else if model.failed { DSErrorState(offline: !env.isOnline) { Task { await model.load(full: true, force: true) } } }
                else if s.isEmpty { DSEmptyState(symbol: "popcorn", title: Text("Nada en este periodo"), message: Text("Lo que veas aquí o en Trakt aparece solo.")) }
                else { content(s, model, language) }
            }
            .padding(.horizontal, DS.Space.gutter)
            .padding(.bottom, DS.Space.s8)
        }
        .background(Backdrop())
        .navigationTitle(Text("Lo que ves"))
        .task { await model.load(full: true) }   // aquí sí, los diez años (la tarjeta solo pidió la semana)
        .refreshable { await model.load(full: true, force: true) }
        .fullScreenCover(item: $wrapped) { p in WrappedView(stats: model.stats(p), language: language) { wrapped = nil } }
    }

    @ViewBuilder private func content(_ s: WatchingStats, _ model: WatchingModel, _ language: String) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: DS.Space.s2), GridItem(.flexible(), spacing: DS.Space.s2)], spacing: DS.Space.s2) {
            WatchingStat(value: Text("\(s.hours) h"), label: Text("frente a la pantalla"))
            WatchingStat(value: Text(verbatim: "\(s.titles)"), label: Text("títulos distintos"))
            WatchingStat(value: Text(verbatim: "\(s.movies)"), label: Text("películas"))
            WatchingStat(value: Text(verbatim: "\(s.episodes)"), label: Text("capítulos"))
            WatchingStat(value: Text("\(s.longestStreak) días"), label: Text("tu mejor racha"))
            WatchingStat(value: Text("\(s.currentStreak) días"), label: Text("racha de hoy"))
        }
        section(Text("Día por día")) {
            WatchingDayGrid(start: s.start, end: s.end, days: s.days)
            HStack(spacing: DS.Space.s4) {
                legend(DS.YearMap.movies, Text("Películas")); legend(DS.YearMap.series, Text("Series")); legend(DS.YearMap.both, Text("Las dos"))
            }
        }
        // «Tu año» vive aquí adentro: el mapa del año completo con lo que viste cada día.
        NavigationLink { YearView() } label: {
            HStack(spacing: DS.Space.s3) {
                Image(systemName: "square.grid.3x3.fill").font(DS.TextRecipe.title.font).foregroundStyle(DS.YearMap.both)
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    Text("Tu año, día por día").recipe(.cardTitle)
                    Text("El mapa de todo el año y lo que viste cada día").recipe(.footnote, color: DS.textMuted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(DS.textMuted)
            }
            .padding(DS.Space.s3)
            .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("watching-year")
        section(Text("Cuándo ves")) { WatchingBars(values: s.buckets.map(\.minutes), labels: s.buckets.map { label($0.start, s.period) }) }
        if !s.genres.isEmpty { section(Text("Tus géneros")) { WatchingGenres(genres: s.genres) { WatchingText.genre($0, language: language) } } }
        ratings
        section(Text("Lo que más viste")) {
            ForEach(Array(s.top.prefix(5).enumerated()), id: \.element.imdb) { i, t in
                Button { onOpenTitle(TitleRoute(kind: t.kind, metaID: t.imdb, title: t.title, poster: t.poster)) } label: {
                    HStack(spacing: DS.Space.s3) {
                        Text(verbatim: "\(i + 1)").recipe(.title, color: DS.textMuted).monospacedDigit().frame(width: DS.Space.s6)
                        PosterView(url: t.poster, title: t.title).frame(width: DS.Repisa.nextPoster)
                        VStack(alignment: .leading, spacing: DS.Space.s1) {
                            Text(verbatim: t.title).recipe(.cardTitle).lineLimit(1)
                            Text(t.kind == "movie" ? "\(t.minutes / 60) h" : "\(t.plays) capítulos · \(t.minutes / 60) h").recipe(.footnote, color: DS.textMuted)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Cómo calificas: cuántas de cada número de estrellas (tus calificaciones de Trakt).
    @ViewBuilder private var ratings: some View {
        let all = env.ratings.ratings.filter { RatingKey.parseEpisode($0.key) == nil }.values
        if !all.isEmpty {
            section(Text("Cómo calificas")) {
                let counts = (1...5).map { star in all.filter { Int((RatingScale.stars(trakt: $0)).rounded(.up)) == star }.count }
                WatchingBars(values: counts, labels: (1...5).map { "\($0)★" })
                Text("Tu promedio: \(String(format: "%.1f", all.map { RatingScale.stars(trakt: $0) }.reduce(0, +) / Double(all.count))) estrellas")
                    .recipe(.footnote, color: DS.textMuted)
            }
        }
    }

    private func section(_ title: Text, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) { DSSectionHead(title: title, level: .section); content() }
    }

    private func legend(_ color: Color, _ text: Text) -> some View {
        HStack(spacing: DS.Space.s1) { RoundedRectangle(cornerRadius: DS.YearMap.radius).fill(color).frame(width: DS.Watching.cell, height: DS.Watching.cell); text.recipe(.caption, color: DS.textMuted) }
    }

    private func label(_ d: Date, _ p: WatchingStats.Period) -> String {
        let style: Strings.DateStyle = switch p { case .week: .weekdayInitial; case .month: .dayNumber; case .year: .monthInitial; case .all: .yearShort }
        return Strings.date(d, style, language: env.services.appSettings.uiLanguage)
    }
}

extension WatchingStats.Period: @retroactive Identifiable { public var id: String { rawValue } }

/// «Lo que ves» desde Ajustes: lo que más viste abre su ficha en esa misma pila.
struct WatchingFromSettings: View {
    @State private var route: TitleRoute?
    var body: some View { WatchingView { route = $0 }.openingTitles(item: $route) }
}
