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
    private var model: SavedModel { observer.model }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Layout.titleToContent) {
                if model.traktLinked {
                    if model.lists.count > 1 { listMenu.padding(.horizontal, DS.Space.gutter) }
                    if !isEmpty && !model.failed {   // sin nada en la lista, no hay qué filtrar (mientras llega, sí: no brinca)
                        DSKindFilter(kind: Binding(get: { kind }, set: { new in withAnimation(DS.Motion.base(reduceMotion)) { kind = new } }))
                            .padding(.horizontal, DS.Space.gutter)
                    }
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
    }

    /// «Mi lista ⌃⌄»: Mi lista o una de tus listas de Trakt, con un toque.
    private var listMenu: some View {
        DSChoiceMenu(options: model.lists.map { list in
            list.id == SavedModel.watchlist ? .init(id: list.id, title: Text("Mi lista"), symbol: "bookmark")
                : .init(id: list.id, title: Text(verbatim: list.name), symbol: "list.bullet")
        }, selection: Binding(get: { model.selected }, set: { id in Task { await model.choose(id) } }), label: Text("Lista"))
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
                Button("Explorar") { env.openTab = AppEnvironment.exploreTab }.accessibilityIdentifier("saved-empty-explore")
            }
        } else {
            SortableGrid(listID: "saved:\(model.selected)", items: items, collections: collections.model, showsKindFilter: false,
                         loading: model.loading || !model.loadedOnce, states: model.states) { s, width in
                TitleLink(route: s.route, progress: model.progress(of: s), width: width, detail: s.year.map { Text(verbatim: String($0)) })
            }
            .id(model.selected)   // otra lista: su propio orden y sus filtros
        }
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
