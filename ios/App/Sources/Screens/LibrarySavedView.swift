import SwiftUI
import OrbitalCore
import OrbitalModels

/// Las cuatro pestañas de Guardado, en el orden de la TV (GD2).
enum SavedTab: String, CaseIterable, Hashable { case myList, watching, watched, lists }
/// Lo que se ve dentro de «Vistas»: lo que terminaste o lo que dejaste (VS2: se elige en ⊜; el Historial abre su pantalla con
/// el reloj del renglón).
enum SavedWatchedView: String, Hashable { case watched, dropped }

/// Biblioteca › Guardado en pestañas (GD2, Fernando, 13 nov 2026: «Pestañas, como la tele»; reemplaza el tablero de pilas
/// G2-A del 9 nov). Arriba, **Mi lista · Viendo · Vistas · Listas** en el selector de Orbital con ícono, cifra y nombre (SG1,
/// 13 nov: `DSSelector` completo, para que no se confunda con las pestañas subrayadas de la Biblioteca); al entrar ya ves los
/// pósters de la primera, sin un índice antes. Debajo, un renglón de controles (R1): el orden, el tipo, ⊜, ＋ y elegir varios.
/// «Vistas» (VS2) elige «Las dejé» dentro de ⊜ y abre el Historial con su reloj; «Listas», Favoritos y tus listas de Trakt en
/// mosaico con portada, y ＋ crea una lista nueva. La pestaña elegida se recuerda en este aparato. Sin Trakt, qué es y «Conectar Trakt»; sin internet, lo dice con
/// «Reintentar» (nunca como si no tuvieras nada); una cuenta nueva, cómo se guarda.
/// En la TV: las mismas pestañas con cifra (`saved-commands.js`); Historial dentro de Vistas y «Listas» como pestaña quedan
/// pendientes allá (registro de paridad). En el iPad, lo mismo con más columnas.
struct LibrarySavedView: View {
    @Environment(\.titleName) var titleName
    @Environment(AppEnvironment.self) private var env
    var observer: ModelObserver<SavedModel>
    @State private var tab: SavedTab = LibrarySavedView.lastTab
    @State private var watchedView: SavedWatchedView = LibrarySavedView.lastWatchedView
    private var model: SavedModel { observer.model }
    static let tabKey = "library.saved.tab", watchedKey = "library.saved.watched"

    /// La que dejaste en este aparato; la primera vez, Mi lista. En la demostración, `-demo-saved-tab` (o `-demo-open history` /
    /// `vistas`, que abren Vistas).
    private static var lastTab: SavedTab {
        #if DEBUG
        if Demo.isOn {
            if Demo.open == "history" || Demo.open == "vistas" { return .watched }
            return Demo.value(after: "-demo-saved-tab").flatMap(SavedTab.init(rawValue:)) ?? .myList
        }
        #endif
        return UserDefaults.standard.string(forKey: tabKey).flatMap(SavedTab.init(rawValue:)) ?? .myList
    }

    private static var lastWatchedView: SavedWatchedView {
        #if DEBUG
        if Demo.isOn {
            return Demo.value(after: "-demo-saved-view").flatMap(SavedWatchedView.init(rawValue:)) ?? .watched
        }
        #endif
        return UserDefaults.standard.string(forKey: watchedKey).flatMap(SavedWatchedView.init(rawValue:)) ?? .watched
    }

    var body: some View {
        let follow = env.follow
        let _ = follow.track()
        let board = currentBoard
        Group {
            if !model.traktLinked {
                SavedMessage(model: model) { noTrakt }
            } else if model.unreachable {
                // Sin internet (o Trakt sin contestar) no se ve como «no tengo nada»: lo dice y ofrece «Reintentar».
                SavedMessage(model: model) { DSErrorState(offline: !env.isOnline) { reload() } }
            } else if isNew(board) {
                SavedMessage(model: model) { newAccount }
            } else {
                content(board)
            }
        }
        // «¿Qué tal…?» flota sobre la barra: se le aparta su lugar abajo para que nunca tape la última fila (GD2).
        .contentMargins(.bottom, env.ui.ratingReminderHeight, for: .scrollContent)
        .perfTag("saved")
        .task {
            await model.load(list: SavedModel.watchlist)
            if follow.available { await follow.loadSeries() }
            announce(model.takeAutomaticChanges(currentBoard))
        }
        .onAppear { model.refreshProgress() }
        .onChange(of: tab) { _, new in remember(new.rawValue, Self.tabKey) }
        .onChange(of: watchedView) { _, new in remember(new.rawValue, Self.watchedKey) }
    }

    @ViewBuilder private func content(_ board: SavedBoard) -> some View {
        let header = AnyView(self.header(board))
        Group {
            switch tab {
            case .myList: SavedListContent(observer: observer, listID: SavedModel.watchlist, header: header)
            case .watching: SavedPileContent(observer: observer, status: .watching, header: header)
            case .watched:
                SavedPileContent(observer: observer, status: shownWatchedView(board) == .dropped ? .dropped : .watched, header: header,
                                 watchedView: $watchedView, hasDropped: !board.dropped.isEmpty)
            case .lists: SavedListsContent(observer: observer, header: header)
            }
        }
        .transition(.opacity)
    }

    /// Las cuatro partes de Guardado en el selector de Orbital, completo (SG1).
    private func header(_ board: SavedBoard) -> some View {
        DSSelector(options: tabs(board), selection: $tab, size: .full)
            .padding(.horizontal, DS.Space.gutter)
            .accessibilityIdentifier("saved-tabs")
    }

    private func tabs(_ board: SavedBoard) -> [DSSelector<SavedTab>.Option] {
        let ready = model.boardReady
        let lists = model.lists.count   // Mi lista ya no va en «Listas»: en su lugar, Favoritos
        return [
            .init(id: .myList, title: Text("Mi lista"), symbol: DS.Symbol.saved, count: .some(ready ? board.inList.count : nil), identifier: "saved-tab-mylist"),
            .init(id: .watching, title: Text("Viendo"), symbol: TitleView.statusSymbol(.watching), count: .some(ready ? board.watching.count : nil), identifier: "saved-tab-watching"),
            .init(id: .watched, title: Text("Vistas"), symbol: TitleView.statusSymbol(.watched), count: .some(ready ? board.watched.count : nil), identifier: "saved-tab-watched"),
            .init(id: .lists, title: Text("Listas"), symbol: "list.bullet.rectangle.portrait.fill", count: .some(ready ? lists : nil), identifier: "saved-tab-lists"),
        ]
    }

    /// «Las dejé» en cero no ocupa lugar: Vistas muestra lo que terminaste.
    private func shownWatchedView(_ board: SavedBoard) -> SavedWatchedView {
        watchedView == .dropped && board.dropped.isEmpty && model.boardReady ? .watched : watchedView
    }

    private var currentBoard: SavedBoard {
        let follow = env.follow
        return model.board(hidden: follow.hidden, hiddenNames: Dictionary(follow.hiddenSeries.map { ($0.imdb, $0.title) }, uniquingKeysWith: { a, _ in a }))
    }

    /// Una cuenta recién hecha: nada en ninguna pestaña ni en tus listas (no cinco ceros: una guía).
    private func isNew(_ board: SavedBoard) -> Bool {
        model.boardReady && !model.failed && board.inList.isEmpty && board.watching.isEmpty && board.stale.isEmpty
            && board.watched.isEmpty && board.dropped.isEmpty && model.lists.count <= 1 && (model.listCounts[SavedModel.favorites] ?? 0) == 0
    }

    private func reload() { Task { await model.load(list: SavedModel.watchlist) } }

    private func remember(_ value: String, _ key: String) {
        #if DEBUG
        if Demo.isOn { return }
        #endif
        UserDefaults.standard.set(value, forKey: key)
    }

    /// «Dune pasó a Vistas»: lo que cambió solo desde la última vez (lo terminaste en la TV, o una serie vista estrenó).
    private func announce(_ changes: [SavedChange]) {
        guard let first = changes.first else { return }
        let language = env.services.appSettings.uiLanguage
        let where_ = Strings.tr(first.to == .watched ? "Vistas" : "Viendo", language: language)
        if changes.count == 1 {
            env.notify(format: "%@ pasó a %@", first.title, where_, tone: .info)
        } else {
            env.notify(format: "%@ y %d más cambiaron de estado", first.title, changes.count - 1, detail: "Lo viste en otro aparato o salió algo nuevo", tone: .info)
        }
    }

    /// Un vacío enseña qué hacer: cómo se guarda y a dónde ir a buscar (GD2).
    private var newAccount: some View {
        DSEmptyState(symbol: DS.Symbol.save, title: Text("Aquí vive lo que guardas"),
                     message: Text("En una ficha, toca Guardar. Lo que guardes, lo que estés viendo y lo que termines aparece aquí, como en la TV.")) {
            Button("Explorar") { env.openTab = AppEnvironment.exploreTab }.accessibilityIdentifier("saved-empty-explore")
        }
        .accessibilityElement(children: .contain).accessibilityIdentifier("saved-new-account")
    }

    private var noTrakt: some View {
        DSEmptyState(symbol: DS.Symbol.save, title: Text("Lo que guardas vive en Trakt"),
                     message: Text("Conéctalo y aquí ves Mi lista, lo que estás viendo, lo que viste y tus listas.")) {
            NavigationLink(value: SettingsRoute()) { Text("Conectar Trakt") }.accessibilityIdentifier("saved-connect-trakt")
        }
    }

    static func name(_ status: TitleStatus) -> Text {
        switch status {
        case .inList: Text("Mi lista")
        case .watching: Text("Viendo")
        case .watched: Text("Vistas")
        case .dropped: Text("Las dejé")
        case .none: Text(verbatim: "")
        }
    }
}

/// Lo que ocupa Guardado entero (sin Trakt, sin conexión, una cuenta nueva): arriba, donde empezaría la lista, y se puede jalar
/// para volver a pedir.
private struct SavedMessage<Content: View>: View {
    let model: SavedModel
    @ViewBuilder let content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Layout.titleToContent) { content }
                .refreshOrbitHost()
                .padding(.top, DS.Space.s2)
                .padding(.bottom, DS.Layout.screenBottom)
        }
        .scrollBounceBehavior(.basedOnSize)
        .orbitalRefreshable { [model] in await model.load(list: SavedModel.watchlist) }
    }
}

/// Una de tus listas (o Favoritos), abierta desde «Listas».
struct SavedListRoute: Hashable { let id: String }
/// El Historial (el diario con fecha), desde el reloj del renglón de Vistas (VS2).
struct DiaryRoute: Hashable {}
