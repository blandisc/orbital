import SwiftUI
import OrbitalModels

/// Ajustes › Complementos (maqueta 12): se preguntan en este orden (con «Ordenar» se arrastran), cada uno con su interruptor,
/// qué aporta y si usa tu Real-Debrid. «Agregar»: los recomendados que falten o pegar una dirección. Deslizar quita.
struct AddonsSettings: View {
    @Environment(AppEnvironment.self) private var env
    @State private var addons = ModelObserver(AddonsModel(AppEnvironment.shared.services))
    @State private var pasting = false
    @State private var address = ""
    @State private var editMode: EditMode = .inactive

    var body: some View {
        let model = addons.model
        Form {
            Section {
                ForEach(model.items) { addon in
                    let what = AddonsModel.summary(addon)
                    Toggle(isOn: Binding(get: { addon.enabled }, set: { on in Task { await model.setEnabled(addon.id, on) } })) {
                        AddonLabel(name: addon.name, usesDebrid: what.usesDebrid, subtitles: what.subtitles, imported: what.imported)
                    }
                    .swipeActions { Button("Quitar", role: .destructive) { Task { await model.remove(addon.id) } }.tint(DS.danger) }   // rojo, como en iOS
                }
                .onMove { from, to in Task { await model.move(fromOffsets: from, toOffset: to) } }
                if model.items.isEmpty { Text("Sin complementos: agrega uno para tener fuentes.").foregroundStyle(DS.textMuted) }
            } footer: { Text("Se preguntan en este orden. Toca «Ordenar» y arrastra para cambiarlo.") }
            .listRowBackground(DS.surface)
            if let error = model.error {
                Section { Text(verbatim: env.message(error)).foregroundStyle(DS.danger).font(DS.TextRecipe.footnote.font) }.listRowBackground(DS.surface)
            }
        }
        .tint(DS.accent)
        .scrollContentBackground(.hidden).background(Backdrop())
        .navigationTitle("Complementos").navigationBarTitleDisplayMode(.inline)
        .readableListWidth()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu("Agregar", systemImage: "plus") {
                    if !model.missingRecommended.isEmpty {
                        Section("Recomendados") {
                            ForEach(model.missingRecommended) { t in Button(t.name) { Task { await model.add(t) } } }
                        }
                    }
                    Button("Pegar dirección", systemImage: "doc.on.clipboard") { address = ""; model.clearError(); pasting = true }
                    if env.session.state == .signedIn {
                        Button("Volver a importar", systemImage: "arrow.down.circle") { Task { await model.importAgain() } }
                    }
                }
                .accessibilityIdentifier("addons-add")
            }
            ToolbarItem(placement: .topBarLeading) {
                Button(editMode.isEditing ? "Listo" : "Ordenar") { editMode = editMode.isEditing ? .inactive : .active }
            }
        }
        .alert("Pegar dirección", isPresented: $pasting) {
            TextField(String(localized: "https://…/manifest.json"), text: $address).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
            Button("Agregar") { Task { await model.add(address: address) } }
            Button("Cancelar", role: .cancel) {}
        } message: { Text("La dirección completa del complemento.") }
        .environment(\.editMode, $editMode)
        .task { await model.prepare() }
    }
}
