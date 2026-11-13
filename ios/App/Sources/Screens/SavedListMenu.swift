import SwiftUI
import UIKit
import OrbitalCore
import OrbitalModels

/// El «···» de cada lista tuya (G4-A, Fernando, 10 nov 2026: «Vamos con tus sugerencias»): cambiar nombre, quién la ve,
/// ordenar a mano, duplicar, compartir el enlace y borrar, sin ir a trakt.tv. Mi lista no lo lleva: su «Ordenar a mano» vive
/// en «Ordenar y filtrar». Todo necesita internet; sin él, los botones se ven apagados y el menú dice por qué.
/// docs/producto/live-activity-2026-11-08/gestor-ola2.html
struct SavedListManagement: ViewModifier {
    @Environment(AppEnvironment.self) private var env
    /// Borrada la lista, su pantalla ya no tiene qué enseñar: de vuelta al tablero.
    @Environment(\.dismiss) private var dismiss
    let model: SavedModel
    /// «Ordenar a mano» (también desde «Ordenar y filtrar», en Mi lista).
    @Binding var reordering: Bool
    /// Elegir varios está abierto: el «···» se esconde para no chocar.
    var editing: Bool
    @State private var renaming = false
    @State private var newName = ""
    @State private var deleting = false
    @State private var openToShare = false

    private var listID: String { model.selected }
    private var own: Bool { model.canEdit && listID != SavedModel.watchlist }
    private var privacy: String { model.privacies[listID] ?? "private" }

    func body(content: Content) -> some View {
        content
            .toolbar {
                if own && !editing {
                    ToolbarItem(placement: .topBarTrailing) { menu }
                }
            }
            .alert("Cambiar nombre", isPresented: $renaming) {   // ds-exception: pide un nombre: el campo de texto del sistema
                TextField("Nombre", text: $newName)
                Button("Cancelar", role: .cancel) {}
                Button("Guardar") { let name = newName; run("No pude cambiar el nombre") { try await model.renameList(listID, to: name) } }
                    .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .confirmationDialog(Text("¿Borrar «\(model.selectedName)»?"), isPresented: $deleting, titleVisibility: .visible) {   // ds-exception: confirmación destructiva corta
                Button("Borrar lista", role: .destructive) {
                    let id = listID, name = model.selectedName, dismiss = dismiss
                    run("No pude borrar la lista") {
                        try await model.deleteList(id)
                        env.notify(format: "Borraste «%@»", name, tone: .success)
                        dismiss()
                    }
                }
            } message: { Text("No se puede deshacer. Los títulos siguen en Mi lista y en tus otras listas.") }
            .confirmationDialog(Text("Esta lista es «Solo tú»"), isPresented: $openToShare, titleVisibility: .visible) {   // ds-exception: confirma un cambio de quién la ve (una sola acción)
                Button("Abrir con el enlace y copiarlo") {
                    let id = listID
                    run("No pude cambiar quién la ve") {
                        try await model.setPrivacy(id, "link")
                        copyLink(id)
                    }
                }
            } message: { Text("Para compartirla, quien tenga el enlace podrá verla. Puedes regresarla a «Solo tú» cuando quieras.") }
            .sheet(isPresented: $reordering) {
                ReorderListSheet(title: listID == SavedModel.watchlist ? Text("Mi lista") : Text(verbatim: model.selectedName),
                                 items: model.items) { order in
                    do { try await model.reorder(listID, imdbs: order); return true }
                    catch { env.notify("No pude guardar tu orden", detail: "Revisa tu conexión e inténtalo otra vez.", tone: .warn); return false }
                }
            }
    }

    private var menu: some View {
        let online = env.isOnline
        return Menu {
            if !online {
                Section { Text("Sin internet: cambiar tu lista necesita conexión") }
            }
            Group {
                Button { newName = model.selectedName; renaming = true } label: { Label("Cambiar nombre", systemImage: "pencil") }
                Picker(selection: Binding(get: { privacy }, set: { new in run("No pude cambiar quién la ve") { try await model.setPrivacy(listID, new) } })) {
                    Label("Solo tú", systemImage: "lock").tag("private")
                    Label("Con el enlace", systemImage: "link").tag("link")
                    if privacy == "friends" { Label("Solo amigos", systemImage: "person.2").tag("friends") }
                    Label("Todos en Trakt", systemImage: "globe").tag("public")
                } label: { Label("Quién la ve", systemImage: Self.privacySymbol(privacy)) }
                .pickerStyle(.menu)
                Button { reordering = true } label: { Label("Ordenar a mano", systemImage: "line.3.horizontal") }
                    .disabled(model.items.count < 2)
                Button { duplicate() } label: { Label("Duplicar", systemImage: "plus.square.on.square") }
                if privacy == "private" {
                    Button { openToShare = true } label: { Label("Compartir enlace", systemImage: "square.and.arrow.up") }
                } else if let url = Trakt.listURL(String(listID.dropFirst("list:".count))) {
                    ShareLink(item: url, subject: Text(verbatim: model.selectedName)) { Label("Compartir enlace", systemImage: "square.and.arrow.up") }
                }
                Divider()
                Button(role: .destructive) { deleting = true } label: { Label("Borrar lista", systemImage: "trash") }
            }
            .disabled(!online)
        } label: {
            Label("Más de esta lista", systemImage: "ellipsis.circle")
        }
        .accessibilityIdentifier("saved-list-more")
    }

    static func privacySymbol(_ privacy: String) -> String {
        switch privacy {
        case "link": "link"
        case "friends": "person.2"
        case "public": "globe"
        default: "lock"
        }
    }

    private func duplicate() {
        let id = listID, name = String(format: Strings.tr("Copia de %@", language: env.services.appSettings.uiLanguage), model.selectedName)
        run("No pude duplicar la lista") {
            let made = try await model.duplicateList(id, name: name)
            env.notify(format: "Hice «%@»", name, tone: .success)
            await model.choose(made)
        }
    }

    private func copyLink(_ id: String) {
        guard let url = Trakt.listURL(String(id.dropFirst("list:".count))) else { return }
        UIPasteboard.general.url = url
        env.notify("Enlace copiado", detail: "Quien lo tenga puede ver la lista.", tone: .success)
    }

    /// Lo que se le dice a Fer: el motivo si es claro (sin nombre, sin sesión), si no, que revise la conexión.
    static func reason(_ error: Error) -> String {
        switch error as? TraktError {
        case .invalid(let m), .auth(let m): m
        default: "Revisa tu conexión e inténtalo otra vez."
        }
    }

    private func run(_ failure: String, _ work: @escaping () async throws -> Void) {
        let env = env
        Task {
            do { try await work() }
            catch { env.notify(failure, detail: Self.reason(error), tone: .warn) }
        }
    }
}

/// «Ordenar a mano»: la lista con agarraderas; arrastras y «Guardar» lo deja así en Trakt (y en la TV, cuando recargue).
struct ReorderListSheet: View {
    @Environment(\.titleName) var titleName
    let title: Text
    @State var items: [Suggestion]
    let save: ([String]) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var saving = false

    init(title: Text, items: [Suggestion], save: @escaping ([String]) async -> Bool) {
        self.title = title; self._items = State(initialValue: items); self.save = save
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(items, id: \.imdb) { s in
                    HStack(spacing: DS.Space.s3) {
                        PosterView(url: s.poster, title: titleName(s.title, id: s.imdb, kind: s.kind)).frame(width: DS.Collections.stackPoster).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: DS.Space.s1) {
                            Text(verbatim: titleName(s.title, id: s.imdb, kind: s.kind)).recipe(.cardTitle).lineLimit(1)
                            if let year = s.year { Text(verbatim: String(year)).recipe(.footnote, color: DS.textMuted) }
                        }
                    }
                }
                .onMove { items.move(fromOffsets: $0, toOffset: $1) }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        saving = true
                        Task { if await save(items.map(\.imdb)) { dismiss() }; saving = false }
                    }
                    .disabled(saving)
                }
            }
        }
        .accessibilityIdentifier("saved-reorder")
    }
}
