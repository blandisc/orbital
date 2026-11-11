import SwiftUI
import OrbitalCore
import OrbitalModels

/// Abrir Colecciones (la repisa) desde Para ti: `.navigationDestination(for: RepisaRoute.self) { RepisaView(onOpenTitle:) }`.
struct RepisaRoute: Hashable {}

/// Abrir una colección (su repisa de películas) directo desde la vitrina de Para ti.
struct RepisaCollectionRoute: Hashable { let id: String }

/// La vitrina de Colecciones para Para ti, ya conectada (Fernando, 31 oct 2026, decisión 5A): cada objeto con cuánto llevas;
/// tocar uno abre su colección y «Ver todas», la repisa completa. Debajo, la que estás más cerca de completar.
struct CollectionsCardLoader: View {
    @Environment(AppEnvironment.self) private var env
    var body: some View {
        let model = env.repisa
        let _ = model.track()
        let entries = model.collections.map { c in
            CollectionsShowcase<RepisaCollectionRoute, RepisaRoute>.Entry(id: c.id, name: CanonNames.title(c.id), seen: c.seen(model.watched), total: max(c.total, c.items.count))
        }
        CollectionsShowcase(entries: entries, hint: nil, route: { RepisaCollectionRoute(id: $0) }, all: RepisaRoute())
        .task { if !model.loaded { await model.load() } }
    }
}

/// Los nombres de cada colección del canon.
enum CanonNames {
    static func title(_ id: String) -> Text {
        switch id {
        case "palm": Text("Palma de Oro"); case "criterion": Text(verbatim: "Criterion"); case "top250": Text("Top 250")
        case "nyt-movies": Text("NYT · Películas"); case "nyt-series": Text("NYT · Series")
        default: AwardNames.title(id)
        }
    }
    /// El nombre completo de una colección: el premio con su categoría o la lista con su autor.
    static func fullTitle(_ id: String) -> Text {
        switch id {
        case "oscar": Text("Óscar a Mejor película"); case "globe": Text("Globo de Oro a Mejor película dramática")
        case "bafta": Text("BAFTA a Mejor película"); case "emmy": Text("Emmy a Mejor serie de drama"); case "palm": Text("Palma de Oro de Cannes")
        case "ariel": Text("Ariel a Mejor película"); case "criterion": Text("Colección Criterion"); case "top250": Text("Top 250 de IMDb")
        case "nyt-movies": Text("Las 100 mejores películas del siglo"); case "nyt-series": Text("Las 100 mejores series del siglo")
        default: title(id)
        }
    }
    /// Qué trae: «Todas las ganadoras desde 2000» (premios) o de dónde sale la lista.
    static func explain(_ id: String, since year: Int?) -> Text {
        switch id {
        case "criterion": Text("Clásicos y cine de autor restaurados por Criterion")
        case "top250": Text("Las mejor calificadas por el público de IMDb")
        case "nyt-movies", "nyt-series": Text("Según The New York Times, votadas por más de 500 creadores")
        default: year.map { Text("Todas las ganadoras desde \(String($0))") } ?? Text("Todas las ganadoras")
        }
    }
}

/// Colecciones: la repisa con las estatuillas completas (premios) y los objetos de las listas famosas, cada uno con cuántas
/// llevas. Tocar uno abre su repisa de películas.
struct RepisaView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    let onOpenTitle: (TitleRoute) -> Void
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let model = env.repisa
        let _ = model.track()
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Layout.betweenSections) {
                (model.seenTotal == 0 ? Text("Empieza tus colecciones: lo que veas del canon se pinta aquí") : Text("\(model.seenTotal) del canon en tus colecciones"))
                    .recipe(.secondary, color: DS.textMuted)
                shelf(Text("Premios"), symbol: "trophy", model.collections.filter { $0.family == .award }, model)
                shelf(Text("Listas famosas"), symbol: "list.star", model.collections.filter { $0.family == .list }, model)
            }
            .refreshOrbitHost()   // la luna de tirar para actualizar
            .padding(.horizontal, DS.Space.gutter)
            .padding(.bottom, DS.Layout.screenBottom)
        }
        .background(Backdrop())
        .navigationTitle(Text("Colecciones"))
        .navigationDestination(for: String.self) { id in RepisaCollectionView(id: id, onOpenTitle: onOpenTitle) }
        .task { await model.load() }
        .orbitalRefreshable { await model.load() }
    }

    private func shelf(_ title: Text, symbol: String, _ items: [CanonCollection], _ model: RepisaModel) -> some View {
        VStack(alignment: .leading, spacing: DS.Layout.titleToContent) {
            DSSectionHead(title: title, level: .section, symbol: symbol)
            // Tres por repisa en el iPhone y seis en el iPad y la Mac (con tres quedaban muy separados); si son menos, centrados.
            let perRow = min(sizeClass == .regular ? DS.Repisa.shelfWide : DS.Repisa.shelf, max(1, items.count))
            ForEach(Array(stride(from: 0, to: items.count, by: perRow)), id: \.self) { i in
                ShelfLedge {
                    HStack(alignment: .bottom, spacing: DS.Space.s3) {
                        ForEach(items[i..<min(i + perRow, items.count)]) { c in
                            NavigationLink(value: c.id) {
                                VStack(spacing: DS.Space.s2) {
                                    ShelfEmblem(id: c.id, height: c.family == .list ? DS.Repisa.listEmblem : DS.Repisa.emblem)
                                    CanonNames.title(c.id).recipe(.label, color: DS.text).lineLimit(1)
                                    Text(verbatim: "\(c.seen(model.watched)) / \(Strings.count(c.total, language: env.services.appSettings.uiLanguage))").recipe(.caption, color: DS.textMuted).monospacedDigit()
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("repisa-\(c.id)")
                        }
                        if items.count - i < perRow { ForEach(0..<(perRow - (items.count - i)), id: \.self) { _ in Color.clear.frame(maxWidth: .infinity) } }
                    }
                    .padding(.top, DS.Space.s4)
                }
            }
        }
    }
}

/// La repisa de una colección: sus títulos por década (o de diez en diez), en gris los que te faltan y a color los que viste;
/// abajo, «La siguiente». Tocar uno abre su ficha rápida; «Ya la vi» lo pone en la repisa.
struct RepisaCollectionView: View {
    @Environment(\.titleName) var titleName
    let id: String
    let onOpenTitle: (TitleRoute) -> Void
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var newestFirst = true
    @State private var picked: CanonCollection.Item?
    @State private var placed: CanonCollection.Item?
    /// «Ya la vi» pregunta cuándo (como Trakt) antes de ponerla en la repisa.
    @State private var asking: Suggestion?
    /// La que espera a que la ficha rápida termine de cerrarse (dos hojas a la vez, iOS no muestra la segunda).
    @State private var askNext: Suggestion?
    /// El mismo filtro que las listas (series o películas, género, calificación, década, sin lo que ya viste).
    @State private var filter = ListFilter()
    /// La calificación de IMDb y los géneros de cada título (de Cinemeta): los de la colección no los traen.
    @State private var ratings: [String: Double] = [:]
    @State private var genres: [String: [String]] = [:]
    @State private var loadingFacts = false

    var body: some View {
        let model = env.repisa
        let _ = model.track()
        let _ = env.ratings.track()
        if let c = model.collection(id) {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Layout.betweenSubsections) {
                    header(c, model)
                    if filter.isActive { ListFilterChips(filter: $filter).padding(.horizontal, -DS.Space.gutter) }
                    if c.items.isEmpty {
                        // La lista no llegó (sin red o MDBList caído) y no había copia: «Reintentar», no cargar para siempre.
                        if model.failedLists.contains(c.id) { DSErrorState(offline: !env.isOnline) { Task { await model.load() } } }
                        else { DSLoadingState() }
                    }
                    let shown = filtered(c, model)
                    if !c.items.isEmpty, shown.items.isEmpty {
                        DSEmptyState(symbol: "line.3.horizontal.decrease.circle", title: Text("Nada con estos filtros"), message: Text("Quita alguno de arriba para ver más."))
                    }
                    ForEach(shown.groups(newestFirst: newestFirst || c.grouping == .rank), id: \.title) { group in
                        VStack(alignment: .leading, spacing: DS.Space.s3) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(verbatim: group.title).recipe(.cardTitle)   // no-es-título: un grupo de la colección
                                Spacer()
                                Text(verbatim: "\(group.items.filter { model.watched.contains($0.imdb) }.count) / \(group.items.count)").recipe(.caption, color: DS.textMuted).monospacedDigit()
                            }
                            ForEach(Array(stride(from: 0, to: group.items.count, by: DS.Repisa.columns)), id: \.self) { i in
                                ShelfLedge { row(Array(group.items[i..<min(i + DS.Repisa.columns, group.items.count)]), c, model) }
                            }
                        }
                    }
                }
                .padding(.horizontal, DS.Space.gutter)
                .padding(.bottom, DS.Layout.screenBottom)
            }
            .background(Backdrop())
            .navigationTitle(CanonNames.title(c.id))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    // Sin «Ordenar»: la repisa ya va por década (o por lugar) y tiene su botón de más recientes o antiguas.
                    ListFilterMenu(sort: .constant(.added), filter: $filter, sorts: [], genres: ListFilter.commonGenres(c.items.map { genres[$0.imdb] ?? [] }),
                                   decades: ListFilter.decades(c.items.map(\.year)), showsKindFilter: Set(c.items.map(\.kind)).count > 1,
                                   loading: loadingFacts)
                }
            }
            // Calificaciones y géneros, una vez que llegan los títulos (se recuerdan: volver a la colección no los pide).
            .task(id: c.items.count) {
                guard !c.items.isEmpty else { return }
                loadingFacts = true
                defer { loadingFacts = false }
                let facts = await env.collections.imdbFacts(c.items.map { ($0.kind, $0.imdb) })
                ratings = facts.ratings; genres = facts.genres
            }
            // La que sigue sale de lo que pasa el filtro (antes, de la colección entera: «Anora» con «Drama · 2010s»).
            .safeAreaInset(edge: .bottom) { if let next = filtered(c, model).next(model.watched) { nextBar(next, c) } }
            .sheet(item: $picked, onDismiss: { asking = askNext; askNext = nil }) { item in quick(item, c, model).presentationDetents([.height(DS.Repisa.quickHeight)]) }
            .askingWhenWatched($asking) { s, date in place(s, at: date, model) }
            .overlay { if let placed { moment(placed, c, model) } }
            .task { if !model.loaded { await model.load() } }   // entrando directo a una colección (sin pasar por la repisa)
            .animation(DS.Motion.enter(reduceMotion), value: placed?.id)
        }
    }

    /// La colección con solo lo que pasa el filtro (el encabezado sigue contando la colección entera).
    private func filtered(_ c: CanonCollection, _ model: RepisaModel) -> CanonCollection {
        guard filter.isActive else { return c }
        var shown = c
        shown.items = c.items.filter {
            filter.keeps(kind: $0.kind, genres: genres[$0.imdb] ?? [], rating: ratings[$0.imdb], year: $0.year, watched: model.watched.contains($0.imdb))
        }
        return shown
    }

    /// Qué es, de dónde y cuánto llevas (Fernando, 31 oct 2026, decisión 6A): «Óscar a Mejor película», «Todas las
    /// ganadoras desde 2000» y «5 de 26 vistas» con su barra.
    private func header(_ c: CanonCollection, _ model: RepisaModel) -> some View {
        let seen = c.seen(model.watched), total = max(c.total, c.items.count)
        return VStack(alignment: .leading, spacing: DS.Space.s3) {
            HStack(alignment: .center, spacing: DS.Space.s4) {
                ShelfEmblem(id: c.id, height: DS.Repisa.header)
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    CanonNames.fullTitle(c.id).recipe(.section).lineLimit(2)
                    CanonNames.explain(c.id, since: c.items.compactMap(\.year).min()).recipe(.footnote, color: DS.textMuted).lineLimit(2)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                Text(verbatim: "\(seen)").recipe(.title).monospacedDigit().contentTransition(.numericText())
                Text("de \(Strings.count(total, language: env.services.appSettings.uiLanguage)) vistas").recipe(.footnote, color: DS.textMuted)
                Spacer()
                if c.grouping != .rank {
                    Button { newestFirst.toggle() } label: {
                        Label(newestFirst ? "Más recientes" : "Más antiguas", systemImage: "arrow.up.arrow.down").recipe(.label)
                            .lineLimit(1).fixedSize()
                    }
                    .dsSecondaryButton()
                    .accessibilityIdentifier("repisa-order")
                }
            }
            Capsule().fill(DS.fillStrong)
                .overlay(alignment: .leading) {
                    GeometryReader { geo in Capsule().fill(DS.warning).frame(width: geo.size.width * CGFloat(seen) / CGFloat(max(total, 1))) }
                }
                .frame(height: DS.Repisa.showcaseBar)
                .accessibilityHidden(true)
        }
    }

    private func row(_ items: [CanonCollection.Item], _ c: CanonCollection, _ model: RepisaModel) -> some View {
        HStack(alignment: .bottom, spacing: DS.Space.s2) {
            ForEach(items) { item in
                Button { picked = item } label: {
                    CanonPoster(url: item.poster, title: titleName(item.title, id: item.imdb, kind: item.kind), label: label(item, c), seen: model.watched.contains(item.imdb),
                                favorite: (env.ratings.stars(item.imdb) ?? 0) >= 5, rank: c.grouping == .rank ? item.rank : nil)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(model.watched.contains(item.imdb) ? "repisa-item-seen" : "repisa-item")
            }
            ForEach(0..<(DS.Repisa.columns - items.count), id: \.self) { _ in Color.clear.frame(maxWidth: .infinity) }
        }
    }

    private func label(_ item: CanonCollection.Item, _ c: CanonCollection) -> String {
        guard let year = item.year else { return "" }
        if let last = item.lastYear, last != year { return String(format: "%d–%02d", year, last % 100) }
        return String(year)
    }

    private func why(_ c: CanonCollection, _ item: CanonCollection.Item) -> Text {
        switch c.grouping {
        case .rank: Text("La n.º \(item.rank ?? 0) de la lista")
        case .releaseDecade: Text("La más clásica que te falta")
        case .awardDecade: Text("La más reciente que te falta")
        }
    }

    private func nextBar(_ item: CanonCollection.Item, _ c: CanonCollection) -> some View {
        HStack(spacing: DS.Space.s3) {
            PosterView(url: item.poster, title: titleName(item.title, id: item.imdb, kind: item.kind)).frame(width: DS.Repisa.nextPoster)
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                why(c, item).recipe(.badge, color: DS.eyebrow)
                Text(verbatim: titleName(item.title, id: item.imdb, kind: item.kind)).recipe(.cardTitle).lineLimit(1)
            }
            Spacer(minLength: 0)
            // «Ver» la reproduce; tocar el resto del renglón abre su ficha (Fernando, 31 oct 2026).
            Button { Task { await env.play(suggestion(item)) } } label: { Label("Ver", systemImage: "play.fill").fontWeight(.semibold) }
                .dsSolidPrimaryButton(shape: .capsule)   // en línea, dentro de un renglón: cápsula
        }
        .contentShape(Rectangle())
        .onTapGesture { onOpenTitle(route(item)) }
        .padding(.horizontal, DS.Space.s3).padding(.vertical, DS.Space.s2)
        .glassEffect(.regular.tint(DS.Rating.glassTint).interactive(), in: RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
        .padding(.horizontal, DS.Space.gutter).padding(.bottom, DS.Space.s2)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("repisa-next")
    }

    private func quick(_ item: CanonCollection.Item, _ c: CanonCollection, _ model: RepisaModel) -> some View {
        let seen = model.watched.contains(item.imdb)
        let others = model.others(item.imdb, besides: c.id)
        return VStack(alignment: .leading, spacing: DS.Space.s4) {
            // El póster y el título abren su ficha (Fernando, 31 oct 2026: antes solo se podía ver o marcar como vista).
            Button { picked = nil; onOpenTitle(route(item)) } label: {
            HStack(alignment: .top, spacing: DS.Space.s4) {
                PosterView(url: item.poster, title: titleName(item.title, id: item.imdb, kind: item.kind)).frame(width: DS.Filter.resultWidth)
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    Text(verbatim: titleName(item.title, id: item.imdb, kind: item.kind)).recipe(.title).lineLimit(3)
                    Text(verbatim: label(item, c)).recipe(.footnote, color: DS.textMuted)
                    if !others.isEmpty {
                        Text("También en \(Text(verbatim: others.map { Self.plainName($0) }.joined(separator: ", ")))").recipe(.footnote, color: DS.textMuted)
                    }
                    if seen, let stars = env.ratings.stars(item.imdb) { RatingStars(value: stars, size: DS.Rating.starInline) { _ in } .allowsHitTesting(false) }
                    HStack(spacing: DS.Space.s1) { Text("Ver la ficha"); Image(systemName: "chevron.forward") }
                        .font(DS.TextRecipe.label.font).foregroundStyle(DS.text)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("repisa-open-title")
            HStack(spacing: DS.Space.s3) {
                Button { picked = nil; Task { await env.play(suggestion(item)) } } label: { Label("Ver", systemImage: "play.fill").fontWeight(.semibold).frame(maxWidth: .infinity) }
                    .dsSolidPrimaryButton().controlSize(.large)
                if !seen {
                    Button { askNext = suggestion(item); picked = nil } label: { Text("Ya la vi").frame(maxWidth: .infinity) }
                        .dsGlassButton().buttonBorderShape(.capsule).controlSize(.large)
                        .accessibilityIdentifier("repisa-seen")
                }
            }
        }
        .padding(DS.Space.gutter)
    }

    private func suggestion(_ item: CanonCollection.Item) -> Suggestion {
        Suggestion(kind: item.kind, imdb: item.imdb, title: item.title, year: item.year, poster: item.poster,
                   wide: String(format: ForYou.metahubBackground, item.imdb), reason: .popular)
    }

    /// «Ya la vi», ya con su fecha: se marca en Trakt (ese día), se pinta al momento y sale el momento de ponerla en la repisa.
    private func place(_ s: Suggestion, at date: Date, _ model: RepisaModel) {
        guard let c = model.collection(id), let item = c.items.first(where: { $0.imdb == s.imdb }) else { return }
        model.markSeen(item.imdb)
        placed = item
        Task { try? await env.titles.markWatched(s, at: date); env.collections.forgetWatched() }
    }

    /// El momento de ponerla en la repisa (`ShelfMoment`): cuántas llevas y lo que sigue en su década.
    private func moment(_ item: CanonCollection.Item, _ c: CanonCollection, _ model: RepisaModel) -> some View {
        let group = c.groups().first { g in g.items.contains { $0.imdb == item.imdb } }
        let missing = group.map { g in g.items.filter { !model.watched.contains($0.imdb) }.count } ?? 0
        // Solo el logro («Completaste Los 2010»); lo que falta ya no se dice (Fernando, 31 oct 2026).
        let next: Text? = group.flatMap { g in missing == 0 ? Text("Completaste \(g.title)") : nil }   // no-es-título: un grupo de la colección
        return ShelfMoment(poster: item.poster, backdrop: String(format: ForYou.metahubBackground, item.imdb), title: titleName(item.title, id: item.imdb, kind: item.kind), emblem: c.id,
                           seen: c.seen(model.watched), total: max(c.total, c.items.count), next: next, completed: group != nil && missing == 0) {
            if placed?.id == item.id { placed = nil }
        }
        .accessibilityIdentifier("repisa-moment")
    }

    private func route(_ item: CanonCollection.Item) -> TitleRoute { TitleRoute(kind: item.kind, metaID: item.imdb, title: item.title, poster: item.poster) }

    static func plainName(_ id: String) -> String {
        switch id {
        case "oscar": "Óscar"; case "palm": "Palma de Oro"; case "globe": "Globos de Oro"; case "bafta": "BAFTA"; case "emmy": "Emmy"
        case "ariel": "Ariel"; case "criterion": "Criterion"; case "top250": "Top 250"
        case "nyt-movies": "NYT · Películas"; case "nyt-series": "NYT · Series"; default: id
        }
    }
}
