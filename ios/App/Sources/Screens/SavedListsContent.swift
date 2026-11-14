import SwiftUI
import OrbitalCore
import OrbitalModels

/// «Listas» en Guardado (GD2, Fernando, 13 nov 2026): Favoritos y tus listas de Trakt en mosaico, cada una con su portada (sus
/// primeros pósters), su nombre y cuántos títulos tiene; dos columnas en el iPhone, las que quepan en el iPad y la Mac. «Nueva
/// lista» es el ＋ del renglón, en el mismo lugar que en toda Guardado (R1, 13 nov); mientras no tienes listas tuyas, también
/// un mosaico que invita. Nace «Solo tú» y necesita internet (sin él, lo dice). Tocar
/// una la abre en la misma pantalla de lista de siempre (`SavedListScreen`). Antes vivían en renglones abajo del tablero, a
/// pantalla y media de distancia, y Favoritos no aparecía en Guardado.
struct SavedListsContent: View {
    @Environment(AppEnvironment.self) private var env
    var observer: ModelObserver<SavedModel>
    var header: AnyView? = nil
    /// «Nueva lista» (G4-A): el nombre que escribes.
    @State private var naming = false
    @State private var newListName = ""
    private var model: SavedModel { observer.model }

    var body: some View {
        let own = model.lists.filter { $0.id != SavedModel.watchlist }
        let columns = DS.Saved.listColumns(forWidth: WindowMetrics.column.width)
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Layout.titleToContent) {
                if let header { header }
                controls
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.s3, alignment: .top), count: columns),
                          alignment: .leading, spacing: DS.Space.s5) {
                    NavigationLink(value: SavedListRoute(id: SavedModel.favorites)) {
                        SavedListTile(name: Text("Favoritos"), detail: detail(SavedModel.favorites, empty: Text("Desde «Guardar en…»")),
                                      posters: model.listPosters[SavedModel.favorites] ?? [], symbol: DS.Favorites.symbolFilled)
                    }
                    .accessibilityIdentifier("saved-list-favorites")
                    ForEach(own) { list in
                        NavigationLink(value: SavedListRoute(id: list.id)) {
                            SavedListTile(name: Text(verbatim: list.name), detail: detail(list.id, empty: Text("Lista de Trakt")),
                                          posters: model.listPosters[list.id] ?? [])
                        }
                    }
                    if own.isEmpty {
                        Button { newListName = ""; naming = true } label: { SavedNewListTile(online: env.isOnline) }
                            .disabled(!env.isOnline)
                            .accessibilityIdentifier("saved-new-list-tile")
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, DS.Space.gutter)
            }
            .refreshOrbitHost()
            .padding(.top, DS.Space.s2)
            .padding(.bottom, DS.Layout.screenBottom)
        }
        .scrollBounceBehavior(.basedOnSize)
        .orbitalRefreshable { [model] in await model.load() }
        .alert("Nueva lista", isPresented: $naming) {   // ds-exception: pide un nombre: el campo de texto del sistema
            TextField("Nombre", text: $newListName)
            Button("Cancelar", role: .cancel) {}
            Button("Crear") { createList(newListName) }
                .disabled(newListName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: { Text("Nace «Solo tú». Puedes cambiar quién la ve en su «···».") }
    }

    /// El renglón de controles de Listas: ＋ crea una lista nueva (sin tipo ni filtros: aquí no aplican).
    private var controls: some View {
        HStack(spacing: DS.Space.s2) {
            Spacer(minLength: 0)
            Button { newListName = ""; naming = true } label: { ListBarIcon(symbol: "plus") }
                .buttonStyle(.plain)
                .disabled(!env.isOnline)
                .keyboardShortcut("n", modifiers: .command)
                .accessibilityLabel(Text("Nueva lista"))
                .accessibilityHint(env.isOnline ? Text(verbatim: "") : Text("Necesita internet"))
                .accessibilityIdentifier("saved-new-list")
        }
        .padding(.horizontal, DS.Space.gutter)
    }

    /// «12 títulos» (o qué es, mientras llega o si está vacía).
    private func detail(_ id: String, empty: Text) -> Text {
        guard let count = model.listCounts[id], count > 0 else { return empty }
        return count == 1 ? Text("1 título") : Text("\(count) títulos")
    }

    private func createList(_ name: String) {
        let model = model, env = env
        Task {
            switch await model.createList(named: name) {
            case .success: env.notify(format: "Hice «%@»", name.trimmingCharacters(in: .whitespacesAndNewlines), tone: .success)
            case .failure(let error): env.notify("No pude hacer la lista", detail: SavedListManagement.reason(error), tone: .warn)
            }
        }
    }
}
