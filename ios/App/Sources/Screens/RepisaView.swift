import SwiftUI
import OrbitalCore
import OrbitalModels

/// Abrir Colecciones (la repisa) desde Para ti: `.navigationDestination(for: RepisaRoute.self) { RepisaView(onOpenTitle:) }`.
struct RepisaRoute: Hashable {}

/// La tarjeta de Colecciones para Para ti, ya conectada: al tocarla empuja `RepisaRoute`.
struct CollectionsCardLoader: View {
    @Environment(AppEnvironment.self) private var env
    var body: some View {
        let model = env.repisa
        let _ = model.track()
        let shelves = model.collections.filter { $0.family == .list }.map { c in
            CollectionsCard.Entry(id: c.id, name: CanonNames.title(c.id), posters: c.items.prefix(DS.ParaTiB.matchFan).map(\.poster))
        }
        NavigationLink(value: RepisaRoute()) { CollectionsCard(shelves: shelves) }
            .buttonStyle(.plain)
            .task { if !model.loaded { await model.load() } }
    }
}

/// Los nombres de cada colección del canon.
enum CanonNames {
    static func title(_ id: String) -> Text {
        switch id {
        case "palm": Text("Palma de Oro"); case "criterion": Text(verbatim: "Criterion"); case "top250": Text("Top 250")
        default: AwardNames.title(id)
        }
    }
    static func category(_ id: String) -> Text {
        switch id {
        case "criterion": Text("Colección Criterion"); case "top250": Text("Top 250 de IMDb"); default: AwardNames.category(id)
        }
    }
}

/// Colecciones: la repisa con las estatuillas completas (premios) y los objetos de las listas famosas, cada uno con cuántas
/// llevas. Tocar uno abre su repisa de películas.
struct RepisaView: View {
    let onOpenTitle: (TitleRoute) -> Void
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let model = env.repisa
        let _ = model.track()
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Editorial.sectionGap) {
                (model.seenTotal == 0 ? Text("Empieza tus colecciones: lo que veas del canon se pinta aquí") : Text("\(model.seenTotal) del canon en tus colecciones"))
                    .recipe(.secondary, color: DS.textMuted)
                shelf(Text("Premios"), model.collections.filter { $0.family == .award }, model)
                shelf(Text("Listas famosas"), model.collections.filter { $0.family == .list }, model)
            }
            .padding(.horizontal, DS.Space.gutter)
            .padding(.bottom, DS.Space.s8)
        }
        .background(Backdrop())
        .navigationTitle(Text("Colecciones"))
        .navigationDestination(for: String.self) { id in RepisaCollectionView(id: id, onOpenTitle: onOpenTitle) }
        .task { await model.load() }
        .refreshable { await model.load() }
    }

    private func shelf(_ title: Text, _ items: [CanonCollection], _ model: RepisaModel) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            DSSectionHead(title: title, level: .section)
            // Tres por repisa; si son dos (las listas), dos centrados.
            let perRow = min(3, max(1, items.count))
            ForEach(Array(stride(from: 0, to: items.count, by: perRow)), id: \.self) { i in
                ShelfLedge {
                    HStack(alignment: .bottom, spacing: DS.Space.s3) {
                        ForEach(items[i..<min(i + perRow, items.count)]) { c in
                            NavigationLink(value: c.id) {
                                VStack(spacing: DS.Space.s2) {
                                    ShelfEmblem(id: c.id, height: c.family == .list ? DS.Repisa.listEmblem : DS.Repisa.emblem)
                                    CanonNames.title(c.id).recipe(.footnote, color: DS.text).fontWeight(.semibold).lineLimit(1)
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
    let id: String
    let onOpenTitle: (TitleRoute) -> Void
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var newestFirst = true
    @State private var picked: CanonCollection.Item?
    @State private var placed: CanonCollection.Item?

    var body: some View {
        let model = env.repisa
        let _ = model.track()
        let _ = env.ratings.track()
        if let c = model.collection(id) {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s5) {
                    header(c, model)
                    if c.items.isEmpty {
                        // La lista no llegó (sin red o MDBList caído) y no había copia: «Reintentar», no cargar para siempre.
                        if model.failedLists.contains(c.id) { DSErrorState(offline: !env.isOnline) { Task { await model.load() } } }
                        else { DSLoadingState() }
                    }
                    ForEach(c.groups(newestFirst: newestFirst || c.grouping == .rank), id: \.title) { group in
                        VStack(alignment: .leading, spacing: DS.Space.s3) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(verbatim: group.title).recipe(.cardTitle)
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
                .padding(.bottom, DS.Space.s14)
            }
            .background(Backdrop())
            .navigationTitle(CanonNames.title(c.id))
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) { if let next = c.next(model.watched) { nextBar(next, c) } }
            .sheet(item: $picked) { item in quick(item, c, model).presentationDetents([.height(DS.Repisa.quickHeight)]) }
            .overlay { if let placed { moment(placed, c, model) } }
            .task { if !model.loaded { await model.load() } }   // entrando directo a una colección (sin pasar por la repisa)
            .animation(DS.Motion.enter(reduceMotion), value: placed?.id)
        }
    }

    private func header(_ c: CanonCollection, _ model: RepisaModel) -> some View {
        HStack(alignment: .bottom, spacing: DS.Space.s4) {
            ShelfEmblem(id: c.id, height: DS.Repisa.header)
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                CanonNames.category(c.id).recipe(.footnote, color: DS.textMuted)
                Text("\(c.seen(model.watched)) de \(Strings.count(c.total, language: env.services.appSettings.uiLanguage))").recipe(.title).monospacedDigit()
            }
            Spacer()
            if c.grouping != .rank {
                Button { newestFirst.toggle() } label: {
                    Label(newestFirst ? "Más recientes" : "Más antiguas", systemImage: "arrow.up.arrow.down").recipe(.footnote).fontWeight(.semibold)
                        .lineLimit(1).fixedSize()
                }
                .dsSecondaryButton()
                .accessibilityIdentifier("repisa-order")
            }
        }
    }

    private func row(_ items: [CanonCollection.Item], _ c: CanonCollection, _ model: RepisaModel) -> some View {
        HStack(alignment: .bottom, spacing: DS.Space.s2) {
            ForEach(items) { item in
                Button { picked = item } label: {
                    CanonPoster(url: item.poster, title: item.title, label: label(item, c), seen: model.watched.contains(item.imdb),
                                favorite: (env.ratings.stars(item.imdb) ?? 0) >= 5, rank: c.grouping == .rank ? item.rank : nil)
                }
                .buttonStyle(.plain)
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
            PosterView(url: item.poster, title: item.title).frame(width: DS.Repisa.nextPoster)
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                why(c, item).recipe(.caption, color: DS.eyebrow).fontWeight(.semibold)
                Text(verbatim: item.title).recipe(.cardTitle).lineLimit(1)
            }
            Spacer(minLength: 0)
            Button { onOpenTitle(route(item)) } label: { Label("Ver", systemImage: "play.fill").fontWeight(.semibold) }
                .dsSolidPrimaryButton(shape: .capsule)   // en línea, dentro de un renglón: cápsula
        }
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
            HStack(alignment: .top, spacing: DS.Space.s4) {
                PosterView(url: item.poster, title: item.title).frame(width: DS.Filter.resultWidth)
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    Text(verbatim: item.title).recipe(.title).lineLimit(3)
                    Text(verbatim: label(item, c)).recipe(.footnote, color: DS.textMuted)
                    if !others.isEmpty {
                        Text("También en \(Text(verbatim: others.map { Self.plainName($0) }.joined(separator: ", ")))").recipe(.footnote, color: DS.textMuted)
                    }
                    if seen, let stars = env.ratings.stars(item.imdb) { RatingStars(value: stars, size: DS.Rating.starInline) { _ in } .allowsHitTesting(false) }
                }
            }
            HStack(spacing: DS.Space.s3) {
                Button { picked = nil; onOpenTitle(route(item)) } label: { Label("Ver", systemImage: "play.fill").fontWeight(.semibold).frame(maxWidth: .infinity) }
                    .dsSolidPrimaryButton().controlSize(.large)
                if !seen {
                    Button { place(item, model) } label: { Text("Ya la vi").frame(maxWidth: .infinity) }
                        .buttonStyle(.glass).buttonBorderShape(.capsule).controlSize(.large)
                        .accessibilityIdentifier("repisa-seen")
                }
            }
        }
        .padding(DS.Space.gutter)
    }

    /// «Ya la vi»: se marca en Trakt, se pinta al momento y sale el momento de ponerla en la repisa.
    private func place(_ item: CanonCollection.Item, _ model: RepisaModel) {
        picked = nil
        model.markSeen(item.imdb)
        placed = item
        let s = Suggestion(kind: item.kind, imdb: item.imdb, title: item.title, year: item.year, poster: item.poster,
                           wide: String(format: ForYou.metahubBackground, item.imdb), reason: .popular)
        Task { try? await env.titles.markWatched(s); env.collections.forgetWatched() }
    }

    /// El momento: la película baja a su lugar en la repisa y el número sube. Sin chispas ni confeti. Tocar cierra.
    private func moment(_ item: CanonCollection.Item, _ c: CanonCollection, _ model: RepisaModel) -> some View {
        VStack(spacing: DS.Space.s3) {
            Text("A tus colecciones").recipe(.footnote, color: DS.textMuted)
            ShelfLedge { PosterView(url: item.poster, title: item.title).frame(width: DS.Repisa.momentPoster).transition(.move(edge: .top).combined(with: .opacity)) }
            Text(verbatim: item.title).recipe(.title).multilineTextAlignment(.center)
            ShelfEmblem(id: c.id, height: DS.Repisa.header)
            Text("\(c.seen(model.watched)) de \(Strings.count(c.total, language: env.services.appSettings.uiLanguage))").recipe(.cardTitle).monospacedDigit().contentTransition(.numericText())
        }
        .padding(DS.Space.s8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.bg.opacity(DS.Repisa.momentVeil).ignoresSafeArea())
        .contentShape(Rectangle())
        .onTapGesture { placed = nil }
        .sensoryFeedback(.success, trigger: placed?.id)
        .task(id: item.id) { try? await Task.sleep(for: DS.Repisa.momentHold); if placed?.id == item.id { placed = nil } }
        .accessibilityAddTraits(.isModal)
        .accessibilityElement(children: .contain)   // cada pieza de adentro conserva su identificador
        .accessibilityIdentifier("repisa-moment")
    }

    private func route(_ item: CanonCollection.Item) -> TitleRoute { TitleRoute(kind: item.kind, metaID: item.imdb, title: item.title, poster: item.poster) }

    static func plainName(_ id: String) -> String {
        switch id {
        case "oscar": "Óscar"; case "palm": "Palma de Oro"; case "globe": "Globos de Oro"; case "bafta": "BAFTA"; case "emmy": "Emmy"
        case "ariel": "Ariel"; case "criterion": "Criterion"; case "top250": "Top 250"; default: id
        }
    }
}
