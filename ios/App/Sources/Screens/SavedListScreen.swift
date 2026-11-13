import SwiftUI
import OrbitalCore
import OrbitalModels

/// Una de tus listas de Trakt o Favoritos, abierta desde la pestaña «Listas» (GD2): la misma pantalla de Mi lista, con el
/// mismo cielo de Guardado (antes se abría en negro liso) y su nombre arriba.
struct SavedListScreen: View {
    var observer: ModelObserver<SavedModel>
    let listID: String

    var body: some View {
        SavedListContent(observer: observer, listID: listID)
            .scrollContentBackground(.hidden)
            .background(Backdrop())   // el cielo del resto de Guardado (GD2)
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
    }

    private var title: Text {
        switch listID {
        case SavedModel.watchlist: Text("Mi lista")
        case SavedModel.favorites: Text("Favoritos")
        default: Text(verbatim: observer.model.lists.first { $0.id == listID }?.name ?? "")
        }
    }
}

/// Una lista de Guardado en cuadrícula (Mi lista en su pestaña, o una de «Listas»): el renglón de controles —a la izquierda el
/// orden elegido; a la derecha Todo · Películas · Series, filtrar, elegir varios y agregar— y debajo los pósters, cada uno con
/// su barra de avance. Mantener el dedo en un póster de Mi lista ofrece «Mover a…» (con la vista previa del sistema); en tus
/// listas, «Quitar de esta lista». Vacía, cómo se llena; sin respuesta, «Reintentar».
struct SavedListContent: View {
    @Environment(\.titleName) var titleName
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    var observer: ModelObserver<SavedModel>
    let listID: String
    /// Las pestañas de Guardado, arriba de todo (nil: una lista abierta desde «Listas»).
    var header: AnyView? = nil
    @State private var collections = ModelObserver(AppEnvironment.shared.collections)
    /// "" es todo, «movie» o «series».
    @State private var kind = ""
    /// «Editar» (G3-A): elegir varios y la barra de abajo; «+» busca qué agregar.
    @State private var selection = ListSelection()
    @State private var adding = false
    /// «Ordenar a mano» (G4-A): desde el «···» o, en Mi lista, desde el orden.
    @State private var reordering = false
    private var model: SavedModel { observer.model }
    /// Lo que se ve es esta lista (mientras cambia, la de antes no se pinta aquí).
    private var current: Bool { model.selected == listID }
    private var items: [Suggestion] { current ? model.items : [] }
    private var shownItems: [Suggestion] { kind.isEmpty ? items : items.filter { $0.kind == kind } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Layout.titleToContent) {
                if let header { header }
                if !showsGrid { bar(nil) }
                content
            }
            .refreshOrbitHost()
            .padding(.top, DS.Space.s2)
            .padding(.bottom, DS.Layout.screenBottom)
            .selectionDrag(selection)
        }
        .scrollBounceBehavior(.basedOnSize)
        .orbitalRefreshable { [model] in await model.load() }
        .safeAreaInset(edge: .bottom) {
            if selection.editing {
                SavedSelectionBar(model: model, selection: selection, listID: listID, pile: nil, items: shownItems)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        // Al volver de una lista a Mi lista (o al revés), la que toca; lo que ya llegó de ella sale al instante.
        .onAppear { model.refreshProgress(); Task { await model.choose(listID) } }
        .sheet(isPresented: $adding) { addSheet }
        .modifier(SavedListManagement(model: model, reordering: $reordering, editing: selection.editing))
        .onChange(of: model.selected) { selection.editing = false }
    }

    private var listName: Text {
        switch listID {
        case SavedModel.watchlist: Text("Mi lista")
        case SavedModel.favorites: Text("Favoritos")
        default: Text(verbatim: model.selectedName)
        }
    }

    @ViewBuilder private var content: some View {
        if current && model.failed && items.isEmpty {
            DSErrorState(offline: !env.isOnline) { Task { await model.load() } }
        } else if isEmpty {
            empty
        } else {
            SortableGrid(listID: "saved:\(listID)", items: shownItems, collections: collections.model, showsKindFilter: false,
                         loading: !current || model.loading || !model.loadedOnce, states: model.states, bar: { AnyView(bar($0)) },
                         manualOrder: model.canEdit && listID == SavedModel.watchlist && items.count > 1 ? { reordering = true } : nil) { s, width in
                poster(s, width: width)
            }
            .id(listID)   // otra lista: su propio orden y sus filtros
        }
    }

    /// Un vacío enseña qué hacer: cómo se llena esta lista y a dónde ir.
    private var empty: some View {
        DSEmptyState(symbol: listID == SavedModel.favorites ? DS.Favorites.symbol : DS.Symbol.save,
                     title: listID == SavedModel.watchlist ? Text("Mi lista está vacía") : Text("Esta lista está vacía"),
                     message: listID == SavedModel.favorites ? Text("En una ficha, toca Guardar y luego Favoritos.")
                                                              : Text("En una ficha, toca Guardar y aparece aquí.")) {
            if model.canEdit && current { Button("Agregar") { adding = true }.accessibilityIdentifier("saved-empty-add") }
            Button("Explorar") { env.openTab = AppEnvironment.exploreTab }.accessibilityIdentifier("saved-empty-explore")
        }
    }

    /// Cada póster: en Mi lista, mantener el dedo trae «Mover a…» (G2-A) con la vista previa del sistema; en tus listas,
    /// «Quitar de esta lista».
    @ViewBuilder private func poster(_ s: Suggestion, width: CGFloat) -> some View {
        let link = TitleLink(route: s.route, progress: model.progress(of: s), width: width, detail: s.year.map { Text(verbatim: String($0)) })
        if listID == SavedModel.watchlist {
            link.contextMenu { if !selection.editing { SavedMoveMenu(suggestion: s, from: .inList, model: model) } }
                .accessibilityHint(Text("Mantén presionado para moverlo"))
                .selectable(selection, id: s.imdb, title: titleName(s.title, id: s.imdb, kind: s.kind))
        } else {
            link.listEditable(editing: false, listName: listName, remove: model.canEdit && !selection.editing ? { remove(s) } : nil)
                .selectable(selection, id: s.imdb, title: titleName(s.title, id: s.imdb, kind: s.kind))
        }
    }

    /// La cuadrícula (con su renglón de arriba) está a la vista: ni vacía ni sin respuesta.
    private var showsGrid: Bool { !(current && model.failed && items.isEmpty) && !isEmpty }

    /// Ya llegó y no trae nada.
    private var isEmpty: Bool { current && model.loadedOnce && !model.loading && model.items.isEmpty }

    /// El renglón bajo las pestañas (GD2): a la izquierda el orden elegido; a la derecha Todo · Películas · Series, filtrar,
    /// elegir varios y agregar, todos con ícono.
    private func bar(_ parts: ListBarParts?) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            controls(parts)
            // «Editar»: cuántas van y «Todas», debajo del renglón que lo abrió.
            if selection.editing && showsGrid { SelectionHeader(selection: selection, all: shownItems.map(\.imdb)) }
        }
    }

    /// Con letra de accesibilidad no caben en un renglón: Todo · Películas · Series baja al suyo (nada se encima).
    private func controls(_ parts: ListBarParts?) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            HStack(alignment: .center, spacing: DS.Space.s2) {
                if let parts { parts.sort }
                Spacer(minLength: 0)
                if showsGrid && !typeSize.isAccessibilitySize { kindFilter }
                if let parts {
                    parts.filters.font(DS.TextRecipe.section.font).foregroundStyle(DS.text)
                        .frame(minWidth: DS.Size.touchTarget, minHeight: DS.Size.touchTarget)
                }
                if model.canEdit && current && (showsGrid || selection.editing) {
                    ListSelectButtons(selection: selection, add: { adding = true }, all: shownItems.map(\.imdb))
                }
            }
            if showsGrid && typeSize.isAccessibilitySize { kindFilter }
        }
        .padding(.horizontal, DS.Space.gutter)
    }

    private var kindFilter: some View {
        DSKindFilter(kind: Binding(get: { kind }, set: { new in withAnimation(DS.Motion.base(reduceMotion)) { kind = new } }))
    }

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
}
