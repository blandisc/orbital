import SwiftUI
import OrbitalCore
import OrbitalModels

/// Una de las partes de Guardado en pantalla completa, desde su fila en Biblioteca de la Mac («Mi lista ›»).
struct LibrarySavedRoute: Hashable { let tab: SavedTab }

/// Biblioteca en la Mac y el iPad ancho (BI-A, 22 nov 2026: «replanteamiento completo de biblioteca porque se ve muy mal»): sin la columna de la
/// izquierda, que se comía un cuarto de la ventana, y con filas como Inicio y Explorar (mismo margen, mismo desvanecido). Arriba
/// Descargas y Mi media; luego lo que estás viendo, Mi lista, Vistas y tus listas. El encabezado de cada fila abre su
/// pantalla completa (la cuadrícula con su orden, su buscador y sus pestañas de siempre).
/// En el iPhone (y el iPad angosto), Biblioteca sigue con sus pestañas arriba; la TV no tiene Biblioteca.
struct LibraryHome: View {
    @Environment(\.titleName) var titleName
    @Environment(AppEnvironment.self) private var env
    var saved: ModelObserver<SavedModel>
    /// Cuántas descargas van (en el aparato y en la nube).
    let downloading: Int
    let open: (DownloadsView.Part) -> Void
    private var model: SavedModel { saved.model }

    var body: some View {
        let follow = env.follow
        let _ = follow.track()
        let board = model.board(hidden: follow.hidden,
                                hiddenNames: Dictionary(follow.hiddenSeries.map { ($0.imdb, $0.title) }, uniquingKeysWith: { a, _ in a }))
        let ready = model.boardReady
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Layout.betweenSections) {
                places   // arriba: lo que bajaste y tu nube, a la mano (Fernando, 22 nov 2026)
                if model.traktLinked {
                    row(Text("Viendo"), eyebrow: Text("Lo que tienes a medias"), tab: .watching, items: board.watching, ready: ready, progress: true)
                    row(Text("Mi lista"), eyebrow: Text("Lo que dejaste pendiente"), tab: .myList, items: board.inList, ready: ready)
                    row(Text("Vistas"), eyebrow: Text("Lo más reciente primero"), tab: .watched, items: board.watched, ready: ready)
                    lists
                }
            }
            .padding(.top, DS.Layout.betweenSubsections)   // aire bajo la barra de la Mac, como el primer estante de Inicio
            .padding(.bottom, DS.Layout.screenBottom)
        }
        .scrollBounceBehavior(.basedOnSize)
        .contentMargins(.bottom, env.ui.ratingReminderHeight, for: .scrollContent)
        .orbitalRefreshable { [model] in await model.load(list: SavedModel.watchlist) }
        .perfTag("library")
        .task {
            await model.load(list: SavedModel.watchlist)
            if follow.available { await follow.loadSeries() }
        }
        .onAppear { model.refreshProgress() }
    }

    /// Una fila de lo tuyo: su nombre con cuántos hay y, al tocarlo, su pantalla completa. Vacía, no ocupa lugar.
    @ViewBuilder private func row(_ title: Text, eyebrow: Text, tab: SavedTab, items: [Suggestion], ready: Bool, progress: Bool = false) -> some View {
        if !ready || !items.isEmpty {
            Shelf(title: title, loading: !ready && items.isEmpty, eyebrow: eyebrow, trailing: ready ? titles(items.count) : nil,
                  destination: LibrarySavedRoute(tab: tab)) {
                ForEach(items.prefix(DS.Mac.libraryRow)) { s in
                    TitleLink(route: s.route, progress: progress ? model.progress(of: s) : nil)
                }
            }
            .accessibilityIdentifier("library-row-\(tab.rawValue)")
        }
    }

    /// Favoritos y tus listas de Trakt, en sus mosaicos.
    private var lists: some View {
        let own = model.lists.filter { $0.id != SavedModel.watchlist }
        return Shelf(title: Text("Tus listas"), eyebrow: Text("Favoritos y las que armaste en Trakt"), trailing: model.boardReady ? (own.isEmpty ? Text("1 lista") : Text("\(own.count + 1) listas")) : nil,
                     destination: LibrarySavedRoute(tab: .lists)) {
            NavigationLink(value: SavedListRoute(id: SavedModel.favorites)) {
                SavedListTile(name: Text("Favoritos"), detail: detail(SavedModel.favorites, empty: Text("Desde «Guardar en…»")),
                              posters: model.listPosters[SavedModel.favorites] ?? [], symbol: DS.Favorites.symbolFilled)
            }
            .frame(width: DS.Saved.listTileMin)
            ForEach(own) { list in
                NavigationLink(value: SavedListRoute(id: list.id)) {
                    SavedListTile(name: Text(verbatim: list.name), detail: detail(list.id, empty: Text("Lista de Trakt")), posters: model.listPosters[list.id] ?? [])
                }
                .frame(width: DS.Saved.listTileMin)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("library-row-lists")
    }

    /// Lo que vive fuera de Trakt: lo que bajas y tu nube.
    private var places: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            DSSectionHead(title: Text("Para ver sin internet y en tu nube"), level: .section, symbol: "externaldrive")
            HStack(alignment: .top, spacing: DS.Space.s2) {
                place(.phone, symbol: "arrow.down.circle", tint: DS.primary, title: Text("Descargas"),
                      detail: downloading > 0 ? Text("\(downloading) bajando") : Text("Lo que bajaste y lo que pediste a la nube"))
                place(.media, symbol: "folder", tint: DS.warning, title: Text("Mi media"), detail: Text("Tus películas y series de OneDrive"))
            }
        }
        .padding(.horizontal, DS.Space.gutter)
    }

    private func place(_ part: DownloadsView.Part, symbol: String, tint: Color, title: Text, detail: Text) -> some View {
        Button { open(part) } label: {
            DSCard {
                HStack(spacing: DS.Space.s4) {
                    DSIconTile(symbol: symbol, tint: tint)
                    VStack(alignment: .leading, spacing: DS.Space.s1) {
                        title.recipe(.cardTitle)
                        detail.recipe(.footnote, color: DS.textMuted).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.forward").font(DS.TextRecipe.footnote.font).foregroundStyle(DS.textMuted)
                }
            }
            .contentShape(Rectangle())
            .pointerHover(.lift)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("library-place-\(part.rawValue)")
    }

    private func titles(_ count: Int) -> Text { count == 1 ? Text("1 título") : Text("\(count) títulos") }

    private func detail(_ id: String, empty: Text) -> Text {
        guard let count = model.listCounts[id], count > 0 else { return empty }
        return count == 1 ? Text("1 título") : Text("\(count) títulos")
    }
}
