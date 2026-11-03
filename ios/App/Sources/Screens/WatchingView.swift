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
        // Con Trakt la tarjeta siempre está (antes, una sola falla, sin red al abrir, la quitaba hasta reiniciar la app y no
        // había cómo entrar); su carga va afuera para que se reintente al volver a Explorar.
        Group {
            if model.linked {
                // Del primer periodo con algo (Fernando, 1 nov 2026: el domingo la semana empieza vacía y la tarjeta decía «Aún nada»).
                let period = model.firstPeriodWithData() ?? .week
                let shown = model.loaded && !model.failed ? model.stats(period) : nil
                let language = env.services.appSettings.uiLanguage
                NavigationLink(value: WatchingRoute()) {
                    WatchingCard(stats: shown, name: Strings.tr("Lo que ves", language: language), genres: (shown?.genres ?? []).map { WatchingText.genre($0.name, language: language) },
                                 period: period, lastTitle: model.lastPlay?.title)
                }
                .buttonStyle(.plain)
            }
        }
        .task { await model.load() }
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
    /// La barra de «Cómo calificas» que tocaste (1…5): debajo, el carrusel de lo que calificaste con ese número.
    @State private var pickedStars: Int?
    /// Lo que viste en Letterboxd y Trakt no tiene («Pasarlas a Trakt»).
    @State private var notInTrakt: [LetterboxdEntry] = []
    /// Ya se cayó en el primer periodo con algo (una vez por visita: si después eliges uno vacío, se queda ahí).
    @State private var picked = false
    @State private var passing = false

    var body: some View {
        let model = env.watching
        let _ = model.track()
        let _ = env.ratings.track()
        let s = model.stats()
        let language = env.services.appSettings.uiLanguage
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Layout.betweenSubsections) {
                // Las pestañas y la portada son un solo bloque: 12 entre ellas y 24 hasta la primera sección (Fernando, 31 oct
                // 2026: con 40 arriba y abajo de la portada quedaba espacio muerto).
                VStack(alignment: .leading, spacing: DS.Layout.titleToContent) {
                    // La portada: el arte de lo que más viste en el periodo, de orilla a orilla, con tus horas encima (como la
                    // portada de Inicio). Las pestañas arriba de lo que cambian.
                    DSTextTabs(options: WatchingStats.Period.allCases.map { .init(id: $0, title: WatchingText.period($0)) },
                               selection: Binding(get: { model.period }, set: { model.period = $0 }))
                    .accessibilityIdentifier("watching-period")
                    if model.loaded, !model.failed, !s.isEmpty { hero(s) }
                }
                VStack(alignment: .leading, spacing: DS.Layout.betweenSections) {
                    if !model.loaded { DSLoadingState() }
                    // No llegó el historial y no hay nada guardado: es un error, no «nada en este periodo».
                    else if model.failed { DSErrorState(offline: !env.isOnline) { Task { await model.load(full: true, force: true) } } }
                    else if s.isEmpty { emptyPeriod(model, language) }
                    else { content(s, model, language) }
                    letterboxdSection
                }
            }
            .refreshOrbitHost()   // la luna de tirar para actualizar
            .padding(.horizontal, DS.Space.gutter)
            .padding(.bottom, DS.Layout.screenBottom)
        }
        #if DEBUG
        .modifier(DemoScroll())   // `-demo-scroll N`: abre ya desplazado (capturas)
        #endif
        .background(Backdrop())
        .navigationTitle(Text("Lo que ves"))
        .onAppear { pickFirstWithData(model) }   // con lo guardado: sin parpadear en el periodo vacío
        .task { await model.load(full: true); pickFirstWithData(model) }   // aquí sí, los diez años (la tarjeta solo pidió la semana)
        .orbitalRefreshable { await model.load(full: true, force: true) }
        .onChange(of: env.watchedSomething) { Task { await model.load(full: true, force: true) } }   // terminaste de ver algo: al día
        .task(id: env.letterboxd.entries.count) {
            let letterboxd = env.letterboxd
            await letterboxd.load()
            guard env.services.trakt?.linked == true else { notInTrakt = []; return }
            notInTrakt = letterboxd.missingInTrakt(watched: await env.collections.watchedIDs())
        }
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
                periodPhrase(s.period).recipe(.label, color: DS.onArtSecondary).lineLimit(1)
                Text(s.minutes >= 60 ? "\(s.hours) h" : "\(s.minutes) min").font(DS.TextRecipe.stat.font).foregroundStyle(DS.text)
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
            DSSectionHead(title: Text("Lo que más viste"), level: .section, symbol: "flame")
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
        section(Text("Día por día"), symbol: "calendar") {
            WatchingZoomMap(plays: model.plays, locale: env.uiLocale)
        }
        // «Cuándo ves», fuera (Fernando, 31 oct 2026): repetía lo del calendario.
        if !s.genres.isEmpty { section(Text("Tus géneros"), symbol: "theatermasks") { WatchingGenres(genres: s.genres) { WatchingText.genre($0, language: language) } } }
        ratings
        // El Wrapped, apagado por ahora (Fernando, 31 oct 2026): `WrappedView` sigue lista para volver.
    }


    /// Cómo calificas (Fernando, 31 oct 2026): solo la gráfica y, arriba, un carrusel con lo que calificaste con el número
    /// elegido (al abrir, 5 estrellas). Tocar otra barra cambia el carrusel; «Ver todo», todo lo que calificaste.
    @ViewBuilder private var ratings: some View {
        let mine = env.ratings.ratings.filter { RatingKey.parseEpisode($0.key) == nil }
        let all = Array(mine.values)
        if !all.isEmpty {
            let counts = (1...5).map { star in all.filter { Int((RatingScale.stars(trakt: $0)).rounded(.up)) == star }.count }
            let star = pickedStars ?? 5
            let items = ratedItems().filter { $0.stars == star }.map {
                WatchingFiveStars.Item(id: $0.id, title: $0.title, kind: $0.kind, poster: String(format: ForYou.metahubPoster, $0.id))
            }
            VStack(alignment: .leading, spacing: DS.Layout.titleToContent) {
                DSSectionHead(title: Text("Cómo calificas"), action: { rated = RatedRoute(stars: 0) }, chevron: true, level: .section, symbol: "star")
                (items.isEmpty ? Text("Nada con \(star) estrellas en tu historial") : Text("Con \(star) estrellas · \(items.count)"))
                    .recipe(.footnote, color: DS.textMuted).contentTransition(.numericText())
                if !items.isEmpty {
                    WatchingFiveStars(items: items) { onOpenTitle(TitleRoute(kind: $0.kind, metaID: $0.id, title: $0.title, poster: $0.poster)) }
                        .id(star)
                        .transition(.opacity)
                        .accessibilityIdentifier("watching-rated-carousel")
                }
                WatchingBars(values: counts, labels: (1...5).map { "\($0)★" }, highlighted: star - 1) { i in
                    withAnimation(DS.Motion.fade) { pickedStars = i + 1 }
                }
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

    /// Al abrir, el primer periodo con algo (Fernando, 1 nov 2026): el domingo la semana empieza vacía y se veía «nada».
    private func pickFirstWithData(_ model: WatchingModel) {
        guard !picked, model.loaded, !model.plays.isEmpty else { return }
        picked = true
        if model.stats().isEmpty, let first = model.firstPeriodWithData() { model.period = first }
    }

    /// Un periodo sin nada: por qué (cuándo empezó y qué fue lo último que viste) y un atajo al primero que sí tiene algo.
    private func emptyPeriod(_ model: WatchingModel, _ language: String) -> some View {
        let start = Text(verbatim: Strings.date(model.start(of: model.period), .weekdayDayMonth, language: language))
        let why: Text = switch model.period {
        case .week: Text("La semana empezó el \(start) y todavía no ves nada.")
        case .month: Text("El mes empezó el \(start) y todavía no ves nada.")
        case .year: Text("El año empezó el \(start) y todavía no ves nada.")
        case .all: Text("Lo que veas aquí o en Trakt aparece solo.")
        }
        let last: Text? = model.lastPlay.map { p in
            Text("Lo último que viste fue \(Text(verbatim: p.title)), el \(Text(verbatim: Strings.date(p.at, .weekdayDayMonth, language: language))).")
        }
        let first = model.firstPeriodWithData()
        return DSEmptyState(symbol: "popcorn", title: Text("Aún nada \(WatchingCard.phrase(model.period))"),
                            message: last.map { Text("\(why) \($0)") } ?? why) {
            if let first, first != model.period {
                Button { model.period = first } label: { Text("Ver \(WatchingCard.phrase(first))") }
                    .accessibilityIdentifier("watching-first-with-data")
            }
        }
    }

    /// «Tus reseñas» (Letterboxd): lo último que calificaste o reseñaste y, si viste algo que Trakt no tiene, el aviso para
    /// pasarlo (con el día y tus estrellas). Solo con Letterboxd conectado.
    @ViewBuilder private var letterboxdSection: some View {
        let letterboxd = env.letterboxd
        let _ = letterboxd.track()
        if letterboxd.connected, !letterboxd.reviews.isEmpty {
            section(Text("Tus reseñas"), symbol: "star.bubble") {
                VStack(alignment: .leading, spacing: DS.Space.s4) {
                    if let average = letterboxd.averageRating {
                        HStack(spacing: DS.Space.s2) {
                            LetterboxdMark()
                            Text("Tu promedio en Letterboxd: \(Text(average, format: .number.precision(.fractionLength(1))))").recipe(.footnote, color: DS.textMuted)
                        }
                    }
                    if !notInTrakt.isEmpty { passCard }
                    ForEach(letterboxd.reviews.prefix(DS.Letterboxd.shown)) { e in
                        Button {
                            if let imdb = e.imdb { onOpenTitle(TitleRoute(kind: e.kind, metaID: imdb, title: e.title, poster: String(format: ForYou.metahubPoster, imdb))) }
                        } label: { LetterboxdReviewRow(entry: e, watched: watchedOn(e)) }
                        .buttonStyle(.plain)
                        .disabled(e.imdb == nil)
                        .accessibilityIdentifier("letterboxd-row")
                    }
                }
            }
        }
    }

    /// «Viste 3 en Letterboxd que no están en Trakt · Pasarlas»: solo con tu toque.
    private var passCard: some View {
        HStack(spacing: DS.Space.s3) {
            LetterboxdMark()
            (notInTrakt.count == 1 ? Text("Viste 1 en Letterboxd que no está en Trakt") : Text("Viste \(notInTrakt.count) en Letterboxd que no están en Trakt"))
                .recipe(.footnote).frame(maxWidth: .infinity, alignment: .leading)
            Button {
                passing = true
                Task {
                    let items = notInTrakt
                    if let n = await env.letterboxd.passToTrakt(items) {
                        notInTrakt = []
                        env.collections.forgetWatched()
                        env.notify(n == 1 ? "1 película pasó a Trakt" : "\(n) películas pasaron a Trakt", detail: "Con el día que las viste y tus estrellas", tone: .success)
                    } else { env.notify("Trakt no las aceptó", detail: "Intenta de nuevo en un momento", tone: .error) }
                    passing = false
                }
            } label: { if passing { ProgressView() } else { Text("Pasarlas") } }   // ds-exception: la ruedita en el lugar del botón mientras sube
            .dsPrimaryButton(size: .small).buttonBorderShape(.capsule)
            .disabled(passing)
            .accessibilityIdentifier("letterboxd-pass")
        }
        .dsCard(.row)
    }

    private func watchedOn(_ e: LetterboxdEntry) -> Text? { LetterboxdWords.watched(e, language: env.services.appSettings.uiLanguage) }

    private func section(_ title: Text, symbol: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: DS.Layout.titleToContent) { DSSectionHead(title: title, level: .section, symbol: symbol); content() }
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
            VStack(alignment: .leading, spacing: DS.Layout.betweenSections) {
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
            .padding(.horizontal, DS.Space.gutter).padding(.bottom, DS.Layout.screenBottom)
        }
        .background(Backdrop())
        .navigationTitle(stars == 0 ? Text("Lo que calificaste") : Text("Con \(stars) estrellas"))
    }
}

extension WatchingStats.Period: @retroactive Identifiable { public var id: String { rawValue } }


