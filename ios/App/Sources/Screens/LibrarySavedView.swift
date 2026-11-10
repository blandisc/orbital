import SwiftUI
import OrbitalCore
import OrbitalModels

/// Una lista de Guardado abierta (Fernando, 3 nov 2026: BI1-A y BI3-A, «que sea como mi biblioteca de guardado»): tu referencia
/// rápida. Mi lista de Trakt y, con un toque en «Mi lista ⌃⌄», cualquiera de tus listas (las mismas de Para ti); Todo ·
/// Películas · Series (`DSKindFilter`) y el mismo «Ordenar y filtrar» de toda lista abierta (`SortableGrid`), con «Estado»:
/// Por ver · Viendo · Vistas. Cada póster lleva su barra de avance y abre su ficha. Sin Trakt, el vacío con «Conectar
/// Trakt»; una lista vacía, con «Explorar».
struct SavedListScreen: View {
    @Environment(AppEnvironment.self) private var env
    var observer: ModelObserver<SavedModel>
    /// La lista que abriste desde el tablero (Mi lista o una tuya); el menú de arriba deja cambiarla.
    let listID: String
    /// Las calificaciones de IMDb y Letterboxd que usa «Ordenar y filtrar» (las mismas de toda la app).
    @State private var collections = ModelObserver(AppEnvironment.shared.collections)
    /// "" es todo, «movie» o «series».
    @State private var kind = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// «Editar» (6 nov 2026): cada póster con su «−»; «+» busca qué agregar. Mi lista y tus listas de Trakt son tuyas.
    @State private var editing = false
    @State private var adding = false
    private var model: SavedModel { observer.model }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Layout.titleToContent) {
                if model.traktLinked {   // (llega desde el tablero: con Trakt)
                    // FG1-A (Fernando, 4 nov 2026): un solo renglón, «Mi lista ⌃⌄» a la izquierda y, a la derecha, Todo · Películas
                    // · Series y el botón de ordenar y filtrar (el de toda lista abierta). Debajo, solo lo filtrado, en cápsulas que
                    // se quitan con un toque. Con la lista vacía o sin respuesta, el renglón sin lo que no aplica.
                    if !showsGrid { bar(menu: nil) }
                    content
                } else {
                    noTrakt
                }
            }
            .refreshOrbitHost()
            .padding(.top, DS.Space.s2)
            .padding(.bottom, DS.Layout.screenBottom)
        }
        .scrollBounceBehavior(.basedOnSize)
        .orbitalRefreshable { [model] in await model.load() }
        .perfTag("saved")
        .task { await model.choose(listID) }
        .onAppear { model.refreshProgress() }   // viste algo y regresaste: la barra al día
        .navigationBarTitleDisplayMode(.inline)   // el nombre ya va grande en «Mi lista ⌃⌄»
        .toolbar { if model.canEdit { ListEditToolbar(editing: $editing) { adding = true } } }
        .sheet(isPresented: $adding) { addSheet }
        .onChange(of: model.selected) { editing = false }
    }

    private var listName: Text { model.selected == SavedModel.watchlist ? Text("Mi lista") : Text(verbatim: model.selectedName) }

    /// Quitar con un toque (el «−», el menú): sale ya y el aviso trae «Deshacer»; si Trakt no acepta, regresa y lo dice.
    private func remove(_ s: Suggestion) {
        let model = model, env = env, list = model.selected, name = model.selectedName
        Task {
            if await model.remove(s) {
                env.notifyListEdit(s, list: list, name: name, added: false) { Task { if model.selected == list { await model.add(s) } } }
            } else {
                env.notify(format: "No pude cambiar «%@»", env.listName(list, name: name), tone: .warn)
            }
        }
    }

    /// «Agregar a …»: un toque agrega (o quita, si ya estaba) y la cuadrícula cambia al instante.
    private var addSheet: some View {
        let model = model, env = env
        return AddToListSheet(listName: listName, search: { await env.titles.searchTitles($0) },
                              contains: { id in model.items.contains { $0.imdb == id } }) { r in
            let s = TitleActions.suggestion(r, listID: model.selected)
            let list = model.selected, name = model.selectedName
            let wasIn = model.items.contains { $0.imdb == s.imdb }
            let ok = wasIn ? await model.remove(s) : await model.add(s)
            if !ok { env.notify(format: "No pude cambiar «%@»", env.listName(list, name: name), tone: .warn) }
        }
    }

    /// «Mi lista ⌃⌄»: Mi lista o una de tus listas de Trakt, con un toque.
    private var listMenu: some View {
        DSChoiceMenu(options: model.lists.map { list in
            list.id == SavedModel.watchlist ? .init(id: list.id, title: Text("Mi lista"), symbol: "bookmark")
                : .init(id: list.id, title: Text(verbatim: list.name), symbol: "list.bullet")
        }, selection: Binding(get: { model.selected }, set: { id in Task { await model.choose(id) } }), label: Text("Lista"), style: .title)
        .accessibilityIdentifier("saved-list-menu")
    }

    @ViewBuilder private var content: some View {
        let items = kind.isEmpty ? model.items : model.items.filter { $0.kind == kind }
        if model.failed {
            DSEmptyState(symbol: "exclamationmark.triangle", title: Text("No pude traer tu lista"),
                         message: Text("Trakt no contestó.")) {
                Button("Reintentar") { Task { await model.load() } }
            }
        } else if isEmpty {
            // La lista no tiene nada: su única salida, ir a buscar qué guardar.
            DSEmptyState(symbol: "bookmark", title: Text("Nada guardado todavía"), message: Text("En una ficha, toca Guardar y aparece aquí.")) {
                if model.canEdit { Button("Agregar") { adding = true }.accessibilityIdentifier("saved-empty-add") }
                Button("Explorar") { env.openTab = AppEnvironment.exploreTab }.accessibilityIdentifier("saved-empty-explore")
            }
        } else {
            SortableGrid(listID: "saved:\(model.selected)", items: items, collections: collections.model, showsKindFilter: false,
                         loading: model.loading || !model.loadedOnce, states: model.states, bar: { AnyView(bar(menu: $0)) }) { s, width in
                poster(s, width: width)
            }
            .id(model.selected)   // otra lista: su propio orden y sus filtros
        }
    }

    /// Cada póster: en Mi lista, mantener el dedo trae «Mover a…» (G2-A); en tus listas, «Quitar de esta lista».
    @ViewBuilder private func poster(_ s: Suggestion, width: CGFloat) -> some View {
        let link = TitleLink(route: s.route, progress: model.progress(of: s), width: width, detail: s.year.map { Text(verbatim: String($0)) })
        if model.selected == SavedModel.watchlist {
            link.listEditable(editing: editing, listName: listName, menu: false, remove: model.canEdit ? { remove(s) } : nil)
                .contextMenu { SavedMoveMenu(suggestion: s, from: .inList, model: model) }
        } else {
            link.listEditable(editing: editing, listName: listName, remove: model.canEdit ? { remove(s) } : nil)
        }
    }

    /// La cuadrícula (con su renglón de arriba) está a la vista: ni vacía ni sin respuesta.
    private var showsGrid: Bool { !model.failed && !isEmpty }

    /// «Mi lista ⌃⌄» · Todo · Películas · Series · ordenar y filtrar.
    private func bar(menu: ListFilterMenu?) -> some View {
        HStack(alignment: .center, spacing: DS.Space.s3) {
            if model.lists.count > 1 { listMenu }
            Spacer(minLength: 0)
            if showsGrid {   // sin nada en la lista, no hay qué filtrar (mientras llega, sí: no brinca)
                DSKindFilter(kind: Binding(get: { kind }, set: { new in withAnimation(DS.Motion.base(reduceMotion)) { kind = new } }), compact: true)
            }
            if let menu {
                menu.font(DS.TextRecipe.section.font).foregroundStyle(DS.text)
                    .frame(minWidth: DS.Size.touchTarget, minHeight: DS.Size.touchTarget)
            }
        }
        .padding(.horizontal, DS.Space.gutter)
    }

    /// Ya llegó y no trae nada.
    private var isEmpty: Bool { model.loadedOnce && !model.loading && model.items.isEmpty }

    /// Sin Trakt no hay Mi lista ni tus listas: qué es y su única salida.
    private var noTrakt: some View {
        DSEmptyState(symbol: "bookmark", title: Text("Lo que guardas vive en Trakt"),
                     message: Text("Conéctalo y aquí ves Mi lista y tus listas, con cuánto llevas de cada título.")) {
            NavigationLink(value: SettingsRoute()) { Text("Conectar Trakt") }.accessibilityIdentifier("saved-connect-trakt")
        }
    }
}

/// Biblioteca › Guardado como tablero (G2-A, Fernando, 9 nov 2026: «G2-A, check. Déjalo como guardado en la pestaña»): lo tuyo
/// en cuatro estados con su cifra (En Mi lista · Viendo · Vistas · Las dejé, las mismas reglas del botón de la ficha) y,
/// abajo, tus listas de Trakt. Cada tarjeta abre su montón completo. Sin Trakt, el vacío con «Conectar Trakt».
/// En la TV: «Guardado» sigue siendo la fila «Mi lista» (BI-TV-A); el tablero queda pendiente en el registro de paridad.
struct LibrarySavedView: View {
    @Environment(AppEnvironment.self) private var env
    var observer: ModelObserver<SavedModel>
    private var model: SavedModel { observer.model }

    var body: some View {
        let follow = env.follow
        let _ = follow.track()
        let board = currentBoard
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Layout.betweenSections) {
                if model.traktLinked {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.s2), count: DS.SavedBoard.columns), spacing: DS.Space.s2) {
                        NavigationLink(value: SavedListRoute(id: SavedModel.watchlist)) {
                            tile(.inList, Text("En Mi lista"), board, ready: model.loadedOnce)
                        }
                        ForEach([TitleStatus.watching, .watched, .dropped], id: \.self) { status in
                            NavigationLink(value: SavedStateRoute(status: status.rawValue)) { tile(status, Self.name(status), board, ready: model.loadedOnce) }
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, DS.Space.gutter)
                    .accessibilityElement(children: .contain).accessibilityIdentifier("saved-board")
                    lists
                } else {
                    noTrakt
                }
            }
            .refreshOrbitHost()
            .padding(.top, DS.Space.s2)
            .padding(.bottom, DS.Layout.screenBottom)
        }
        .scrollBounceBehavior(.basedOnSize)
        .orbitalRefreshable { [model] in await model.load() }
        .perfTag("saved")
        .task {
            await model.load()
            if follow.available { await follow.loadSeries() }
            announce(model.takeAutomaticChanges(currentBoard))
        }
        .onAppear { model.refreshProgress() }
    }

    private var currentBoard: SavedBoard {
        let follow = env.follow
        return model.board(hidden: follow.hidden, hiddenNames: Dictionary(follow.hiddenSeries.map { ($0.imdb, $0.title) }, uniquingKeysWith: { a, _ in a }))
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

    static func name(_ status: TitleStatus) -> Text {
        switch status {
        case .inList: Text("En Mi lista")
        case .watching: Text("Viendo")
        case .watched: Text("Vistas")
        case .dropped: Text("Las dejé")
        case .none: Text(verbatim: "")
        }
    }

    private func tile(_ status: TitleStatus, _ title: Text, _ board: SavedBoard, ready: Bool) -> some View {
        let items = board.items(status)
        return SavedStateTile(symbol: TitleView.statusSymbol(status == .inList ? .none : status), title: title,
                              count: ready ? items.count : nil, posters: items.map(\.poster))
    }

    /// Tus listas de Trakt, cada una con sus pósters; un toque la abre.
    @ViewBuilder private var lists: some View {
        let own = model.lists.filter { $0.id != SavedModel.watchlist }
        if !own.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                DSSectionHead(title: Text("Tus listas"), level: .section)
                ForEach(own) { list in
                    NavigationLink(value: SavedListRoute(id: list.id)) {
                        ListRow(name: list.name, detail: model.listCounts[list.id].map { $0 == 1 ? Text("1 título") : Text("\($0) títulos") } ?? Text("Lista de Trakt"),
                                posters: model.listPosters[list.id] ?? [])
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DS.Space.gutter)
        }
    }

    private var noTrakt: some View {
        DSEmptyState(symbol: "bookmark", title: Text("Lo que guardas vive en Trakt"),
                     message: Text("Conéctalo y aquí ves Mi lista, lo que estás viendo, lo que viste y tus listas.")) {
            NavigationLink(value: SettingsRoute()) { Text("Conectar Trakt") }.accessibilityIdentifier("saved-connect-trakt")
        }
    }
}

/// Mi lista o una de tus listas, abierta desde el tablero.
struct SavedListRoute: Hashable { let id: String }
/// Un estado del tablero (Viendo, Vistas, Las dejé), abierto completo.
struct SavedStateRoute: Hashable { let status: String }

/// Un montón del tablero completo: Viendo y Las dejé en cuadrícula (con «Ordenar y filtrar»); Vistas por mes, lo más reciente
/// arriba.
struct SavedStateScreen: View {
    @Environment(AppEnvironment.self) private var env
    var observer: ModelObserver<SavedModel>
    let status: TitleStatus
    @State private var collections = ModelObserver(AppEnvironment.shared.collections)
    private var model: SavedModel { observer.model }

    var body: some View {
        let follow = env.follow
        let _ = follow.track()
        let board = model.board(hidden: follow.hidden, hiddenNames: Dictionary(follow.hiddenSeries.map { ($0.imdb, $0.title) }, uniquingKeysWith: { a, _ in a }))
        let items = board.items(status)
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Layout.titleToContent) {
                if status == .watched, !items.isEmpty {
                    ForEach(months(items, board), id: \.0) { month, group in
                        VStack(alignment: .leading, spacing: DS.Space.s3) {
                            DSSectionHead(title: Text(verbatim: month), count: group.count, level: .subsection)
                            DSPosterGrid(items: group) { s, width in
                                TitleLink(route: s.route, width: width, detail: s.year.map { Text(verbatim: String($0)) })
                                    .contextMenu { SavedMoveMenu(suggestion: s, from: status, model: model) }
                            }
                        }
                        .padding(.horizontal, DS.Space.gutter)
                    }
                } else {
                    if !items.isEmpty || board.stale.isEmpty || status != .watching {
                        SortableGrid(listID: "saved-state:\(status.rawValue)", items: items, collections: collections.model,
                                     loading: !model.loadedOnce, states: nil) { s, width in
                            TitleLink(route: s.route, progress: model.progress(of: s), width: width, detail: s.year.map { Text(verbatim: String($0)) })
                                .contextMenu { SavedMoveMenu(suggestion: s, from: status, model: model) }
                        }
                        .padding(.horizontal, DS.Space.gutter)
                    }
                    if status == .watching, !board.stale.isEmpty { stale(board.stale) }
                }
            }
            .padding(.top, DS.Space.s2)
            .padding(.bottom, DS.Layout.screenBottom)
        }
        .navigationTitle(LibrarySavedView.name(status)).navigationBarTitleDisplayMode(.inline)
        .task { if !model.loadedOnce { await model.load() } }
    }

    /// «¿Las dejaste?»: las series a medias que no ves hace más de seis meses ya no cuentan en Viendo; un toque las deja todas
    /// (o una por una, manteniendo el dedo), y si no, siguen aquí.
    private func stale(_ shows: [Suggestion]) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            DSSectionHead(title: Text("¿Las dejaste?"), count: shows.count, eyebrow: Text("Hace más de seis meses que no las ves"))
            DSPosterGrid(items: shows) { s, width in
                TitleLink(route: s.route, progress: model.progress(of: s), width: width, detail: s.year.map { Text(verbatim: String($0)) })
                    .contextMenu { SavedMoveMenu(suggestion: s, from: .watching, model: model) }
            }
            Button { Task { await dropAll(shows) } } label: { Label("Sí, las dejé", systemImage: "eye.slash") }
                .dsSecondaryButton()
                .accessibilityIdentifier("saved-stale-drop")
        }
        .padding(.horizontal, DS.Space.gutter)
        .accessibilityElement(children: .contain).accessibilityIdentifier("saved-stale")
    }

    private func dropAll(_ shows: [Suggestion]) async {
        let follow = env.follow
        var done: [String] = []
        for s in shows {
            if let problem = await follow.hide(s.imdb) { env.notify(problem, tone: .error); break }
            await ReleaseNotifier.forget(s.imdb)
            done.append(s.imdb)
        }
        guard !done.isEmpty else { return }
        env.notify(done.count == 1 ? "La dejaste" : "Las dejaste", detail: done.count == 1 ? shows.first?.title : nil, tone: .info,
                   actionTitle: "Deshacer", actionSymbol: "arrow.uturn.backward") {
            Task { for imdb in done { _ = await follow.unhide(imdb, following: false) } }
        }
    }

    /// «Noviembre», «Octubre»… (con el año si no es este): solo la primera letra en mayúscula.
    private func month(_ date: Date, language: String) -> String {
        let thisYear = Calendar.current.isDate(date, equalTo: Date(), toGranularity: .year)
        let text = thisYear ? date.formatted(.dateTime.month(.wide).locale(Locale(identifier: language)))
                            : Strings.date(date, .monthYear, language: language)
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    /// Cada vista bajo el mes en que la viste por última vez.
    private func months(_ items: [Suggestion], _ board: SavedBoard) -> [(String, [Suggestion])] {
        let language = env.services.appSettings.uiLanguage
        var out: [(String, [Suggestion])] = []
        for s in items {
            let key = board.lastWatched[s.imdb].map { month($0, language: language) } ?? Strings.tr("Sin fecha", language: language)
            if out.last?.0 == key { out[out.count - 1].1.append(s) } else { out.append((key, [s])) }
        }
        return out
    }
}
