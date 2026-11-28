import SwiftUI

/// La pestaña «Juegos» (Ultra, P1–P3): lo reciente aquí o en la TV, tus consolas y tus favoritos, como en la TV.
/// Cada consola abre su rejilla con los órdenes de la TV (P2) y cada juego su ficha (`GameDetailView`).
struct GamesTab: View {
    /// Solo en Ultra y en el iPhone; mientras se aprueban las pantallas, además con `-demo-games`.
    @MainActor static var isOn: Bool { ThisDevice.capabilities.emulation && ThisDevice.platform == "iphone" && Demo.has("-demo-games") }
    @State private var catalog = GamesCatalog.demo()
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            GamesHome()
                .navigationDestination(for: GameConsoleRoute.self) { GameConsoleView(console: $0.console) }
                .navigationDestination(for: GameRoute.self) { GameDetailView(id: $0.id) }
                .navigationDestination(for: GameSavesRoute.self) { GameSavesView(id: $0.id) }
                .navigationDestination(for: GamesSettingsRoute.self) { GamesSettingsRoute.view($0) }
        }
        .tint(DS.primary)
        .environment(catalog)
        .onAppear(perform: openDemo)
    }

    /// `-demo-game <id>` abre la ficha de un juego; `-demo-games-console <id>` una consola; `-demo-games-empty` la TV sin catálogo.
    private func openDemo() {
        if Demo.has("-demo-games-empty") { catalog.games = []; catalog.reachable = false }
        if let id = Demo.value(after: "-demo-games-console"), let console = GameConsole.all.first(where: { $0.id == id }) {
            path.append(GameConsoleRoute(console: console))
        }
        if let id = Demo.value(after: "-demo-game") { path.append(GameRoute(id: id)) }
        if let id = Demo.value(after: "-demo-game-saves") { path.append(GameRoute(id: id)); path.append(GameSavesRoute(id: id)) }
        if let raw = Demo.value(after: "-demo-games-settings") {
            path.append(GamesSettingsRoute.main)
            if let page = GamesSettingsRoute(rawValue: raw), page != .main { path.append(page) }
        }
    }
}

struct GameRoute: Hashable { let id: String }
struct GameConsoleRoute: Hashable { let console: GameConsole }

private struct GamesHome: View {
    @Environment(GamesCatalog.self) private var catalog

    var body: some View {
        ScrollView {
            if catalog.games.isEmpty {
                DSEmptyState(symbol: "tv", title: Text("Tus juegos viven en la TV"),
                             message: Text("Prende Orbital en la TV y conéctate a la misma wifi para ver tu catálogo.")) {
                    Button("Buscar de nuevo") { catalog.reachable = true; catalog.games = GamesCatalog.demo().games }
                }
                .padding(.top, DS.Space.s16)
            } else {
                VStack(alignment: .leading, spacing: DS.Layout.betweenSections) {
                    if !catalog.recent.isEmpty {
                        section(DSSectionHead(title: Text("Recientes"), eyebrow: Text("Aquí o en la TV"))) {
                            ForEach(catalog.recent) { game in
                                NavigationLink(value: GameRoute(id: game.id)) { GameRecentCover(game: game) }.buttonStyle(.plain)
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: DS.Layout.titleToContent) {
                        DSSectionHead(title: Text("Tus consolas"))
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: DS.Games.consoleMin), spacing: DS.Space.s2)], spacing: DS.Space.s2) {
                            ForEach(GameConsole.all) { console in
                                NavigationLink(value: GameConsoleRoute(console: console)) {
                                    ConsoleDoor(console: console, games: catalog.games(of: console))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, DS.Space.gutter)
                    if !catalog.favorites.isEmpty {
                        section(DSSectionHead(title: Text("Favoritos"))) {
                            ForEach(catalog.favorites) { game in
                                NavigationLink(value: GameRoute(id: game.id)) { GameBox(game: game).frame(width: DS.Games.boxWidth) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.top, DS.Layout.screenTop)
                .padding(.bottom, DS.Layout.screenBottom)
            }
        }
        .dsNavigationTitle("Juegos")
        .navigationSubtitle(catalog.games.isEmpty ? Text(verbatim: "") : Text("\(catalog.onPhone.count) en tu iPhone"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink(value: GamesSettingsRoute.main) { Label("Ajustes de juegos", systemImage: "gearshape") }
            }
        }
    }

    /// Un encabezado y su tira que se desliza de orilla a orilla.
    private func section<Content: View>(_ head: DSSectionHead, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DS.Layout.titleToContent) {
            head.padding(.horizontal, DS.Space.gutter)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: DS.Space.s2) { content() }.scrollTargetLayout()
            }
            .rowEdge(.bleeds)   // lo que crece al picarlo no se corta en la orilla del listón
            .contentMargins(.horizontal, DS.Space.gutter, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .pagingArrows()   // C4: ‹ › con el puntero
            .edgeBump()
        }
    }
}

/// Una consola con sus juegos (P2): los órdenes de la TV y, solo aquí, «En tu iPhone». Lo que todavía no corre se ve apagado
/// con ⊘ (E6-A), pero se puede abrir su ficha (P4).
struct GameConsoleView: View {
    let console: GameConsole
    @Environment(GamesCatalog.self) private var catalog
    @State private var order = GameOrder.recent

    var body: some View {
        let games = order.apply(catalog.games(of: console))
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Layout.titleToContent) {
                DSSelector(options: GameOrder.allCases.map { .init(id: $0, title: Text($0.title)) }, selection: $order)
                if games.isEmpty {
                    Text(order == .onPhone ? "Todavía no bajas juegos de esta consola." : "Nada por aquí.")
                        .recipe(.footnote, color: DS.textMuted)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: DS.Games.gridMin), spacing: DS.Space.s2, alignment: .top)],
                              spacing: DS.Space.s4) {
                        ForEach(games) { game in
                            NavigationLink(value: GameRoute(id: game.id)) { GameBox(game: game) }.buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, DS.Space.gutter)
            .padding(.top, DS.Layout.screenTop)
            .padding(.bottom, DS.Layout.screenBottom)
        }
        .navigationTitle(Text(console.name))
        .navigationSubtitle(GameConsole.countText(catalog.games(of: console).count))
    }
}

/// Una puerta de «Tus consolas»: el nombre y cuántos juegos tiene, como en la TV.
private struct ConsoleDoor: View {
    let console: GameConsole
    let games: [GameItem]

    var body: some View {
        DSCard {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text(console.name).recipe(.cardTitle)
                GameConsole.countText(games.count).recipe(.data, color: DS.textMuted)
            }
            .frame(maxWidth: .infinity, minHeight: DS.Games.consoleHeight, alignment: .bottomLeading)
        }
        .contentShape(.rect)
    }
}

/// La portada de un juego. Mientras no llega el arte de la TV, un degradado del color del título (como `PosterStandIn`).
struct GameArt: View {
    let title: String
    var showsTitle = true

    var body: some View {
        let hue = DS.Poster.missingHue(title)
        ZStack(alignment: .bottomLeading) {
            EllipticalGradient(colors: [hue.opacity(DS.Poster.missingGlow), hue.opacity(DS.Poster.missingBase)],
                               center: UnitPoint(x: 0.25, y: 0.15), startRadiusFraction: 0, endRadiusFraction: 1)
                .background(DS.backdropDeep)
            if showsTitle {
                Text(title).recipe(.cardTitle, color: DS.paper).lineLimit(3).padding(DS.Space.s2)
            }
        }
        .accessibilityHidden(true)
    }
}

/// La caja de un juego en una rejilla o tira: portada 3:4 y su nombre. Apagada con ⊘ si todavía no corre (E6-A).
struct GameBox: View {
    let game: GameItem

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            GameArt(title: game.title, showsTitle: false)
                .aspectRatio(DS.Games.boxAspect, contentMode: .fit)
                .clipShape(.rect(cornerRadius: DS.Radius.md, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if !game.playable {
                        Image(systemName: "nosign").font(DS.TextRecipe.label.font).foregroundStyle(DS.paper).padding(DS.Space.s2)
                    }
                }
                .opacity(game.playable ? 1 : DS.Games.unavailable)
            Text(game.title).recipe(.caption, color: DS.text).lineLimit(2)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(game.title))
        .accessibilityHint(game.playable ? Text("") : Text("Todavía no corre en el iPhone"))
    }
}

/// La tarjeta ancha de «Recientes»: portada 16:10 con el nombre encima y dónde lo jugaste.
private struct GameRecentCover: View {
    let game: GameItem

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            GameArt(title: game.title)
                .aspectRatio(DS.Games.wideAspect, contentMode: .fit)
                .clipShape(.rect(cornerRadius: DS.Radius.md, style: .continuous))
            game.lastPlayedText.recipe(.caption, color: DS.textMuted)
        }
        .frame(width: DS.Games.wideWidth)
        .contentShape(.rect)
    }
}

extension GameConsole {
    /// «1 juego», «5 juegos».
    static func countText(_ n: Int) -> Text { n == 1 ? Text("1 juego") : Text("\(n) juegos") }
}

extension GameItem {
    /// «Hoy», «Hace 3 días».
    var lastPlayedText: Text {
        switch lastPlayedDays {
        case nil: Text("Sin jugar")
        case 0?: Text("Hoy")
        case 1?: Text("Ayer")
        case let days?: Text("Hace \(Int(days)) días")
        }
    }
    /// «9 h 40 min», «45 min».
    var playedText: Text {
        let h = minutesPlayed / 60, m = minutesPlayed % 60
        if h == 0 { return Text("\(m) min") }
        return m == 0 ? Text("\(h) h") : Text("\(h) h \(m) min")
    }
    /// «7.1 GB», «16 MB».
    var sizeText: String {
        let bytes = Int64(gigabytes * 1_000_000_000)
        return bytes.formatted(.byteCount(style: .file))
    }
}
