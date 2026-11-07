import SwiftUI
import OrbitalCore
import OrbitalModels

/// Biblioteca › Guardado (Fernando, 3 nov 2026: BI1-A y BI3-A, «que sea como mi biblioteca de guardado»): tu referencia
/// rápida. Mi lista de Trakt y, con un toque en «Mi lista ⌃⌄», cualquiera de tus listas (las mismas de Para ti); Todo ·
/// Películas · Series (`DSKindFilter`) y el mismo «Ordenar y filtrar» de toda lista abierta (`SortableGrid`), con «Estado»:
/// Por ver · A medias · Vistas. Cada póster lleva su barra de avance y abre su ficha. Sin Trakt, el vacío con «Conectar
/// Trakt»; una lista vacía, con «Explorar».
struct LibrarySavedView: View {
    @Environment(AppEnvironment.self) private var env
    var observer: ModelObserver<SavedModel>
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
                if model.traktLinked {
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
        .task { await model.load() }
        .onAppear { model.refreshProgress() }   // viste algo y regresaste: la barra al día
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
                TitleLink(route: s.route, progress: model.progress(of: s), width: width, detail: s.year.map { Text(verbatim: String($0)) })
                    .listEditable(editing: editing, listName: listName, remove: model.canEdit ? { remove(s) } : nil)
            }
            .id(model.selected)   // otra lista: su propio orden y sus filtros
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
