import SwiftUI
import OrbitalCore
import OrbitalModels

/// «Guardar en…»: en qué listas va un título, varias a la vez — Mi lista (Stremio), tu watchlist y tus listas de Trakt
/// (las mismas que ves en la TV y en «Tus listas»); abajo, una lista nueva.
struct SaveView: View {
    @ObservedObject var observer: ModelObserver<TitleModel>
    @State private var naming = false
    @State private var newName = ""

    var body: some View {
        let m = observer.model
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    Text("Guardar en…").recipe(.title)
                    Text(verbatim: m.title).recipe(.footnote).lineLimit(1)
                }
                .padding(.bottom, DS.Space.s2)
                CheckRow(title: Text("Mi lista"), symbol: "rectangle.stack", color: DS.ListTint.library, checked: m.inLibrary) { Task { await m.toggleLibrary() } }
                if m.traktAvailable {
                    CheckRow(title: Text("Tu watchlist"), symbol: "bookmark", color: DS.ListTint.bookmark, checked: m.inWatchlist) { Task { await m.toggleWatchlist() } }
                    PanelGroupTitle(title: "Tus listas de Trakt")
                    if let lists = m.lists {
                        ForEach(lists) { list in
                            CheckRow(title: Text(verbatim: list.name), symbol: "list.bullet", color: DS.ListTint.list, checked: list.contains) { Task { await m.toggleList(list.id) } }
                        }
                    } else {
                        ProgressView().frame(maxWidth: .infinity).padding(DS.Space.s3)
                    }
                    Button { naming = true } label: { Label("Nueva lista…", systemImage: "plus") }
                        .buttonStyle(.glass).controlSize(.large).padding(.top, DS.Space.s2)
                }
                if let message = m.message { DSNotice(verbatim: message, tone: .error) }
            }
            .padding(DS.Space.gutter)
        }
        .scrollBounceBehavior(.basedOnSize)
        .task { if m.lists == nil { await m.loadLists() } }
        .alert("Nueva lista", isPresented: $naming) {
            TextField("Nombre", text: $newName)
            Button("Crear") { let name = newName; newName = ""; Task { await m.createList(named: name) } }
            Button("Cancelar", role: .cancel) { newName = "" }
        } message: { Text("Se crea en Trakt (privada) y este título entra en ella.") }
    }
}
