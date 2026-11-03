import SwiftUI
import OrbitalModels
import OrbitalAddons

/// Ajustes › Complementos (maqueta 12): se preguntan en este orden (con «Ordenar» se arrastran), cada uno con su interruptor,
/// qué aporta y si usa tu Real-Debrid. «Agregar»: los recomendados que falten y volver a traer los de Stremio. Ya no se
/// agregan complementos pegando su dirección (Fernando, 3 nov 2026, C9); los que ya tenías se quedan.
struct AddonsSettings: View {
    @Environment(AppEnvironment.self) private var env
    @State private var addons = ModelObserver(AddonsModel(AppEnvironment.shared.services))
    @State private var editMode: EditMode = .inactive
    /// El que se va a quitar (se confirma diciendo qué se pierde).
    @State private var removing: InstalledAddon?
    /// Tu última fuente prendida, que vas a apagar (se confirma: te quedas sin versiones).
    @State private var turningOffLast: InstalledAddon?

    var body: some View {
        let model = addons.model
        Form {
            Section {
                ForEach(model.items) { addon in
                    let what = AddonsModel.summary(addon)
                    Toggle(isOn: Binding(get: { addon.enabled }, set: { on in
                        // La última fuente: antes de apagarla se avisa (C7).
                        if !on, model.isLastSource(addon.id) { turningOffLast = addon } else { Task { await model.setEnabled(addon.id, on) } }
                    })) {
                        AddonLabel(name: addon.name, usesDebrid: what.usesDebrid, subtitles: what.subtitles, imported: what.imported)
                    }
                    // Solo los traídos de Stremio se quitan; los que vienen con Orbital solo se apagan (C7). Con el dedo se desliza;
                    // con el mouse o el trackpad (Mac, iPad), el menú del clic secundario.
                    .swipeActions { if model.canRemove(addon) { Button("Quitar", role: .destructive) { removing = addon }.tint(DS.danger) } }   // rojo, como en iOS
                    .contextMenu { if model.canRemove(addon) { Button("Quitar complemento", systemImage: "trash", role: .destructive) { removing = addon } } }
                }
                .onMove { from, to in Task { await model.move(fromOffsets: from, toOffset: to) } }
                if model.items.isEmpty { Text("Sin complementos: agrega uno para tener fuentes.").foregroundStyle(DS.textMuted) }
            } footer: {
                Text("Se preguntan en este orden. Toca «Ordenar» y arrastra para cambiarlo. Vienen con Orbital: Torrentio, Comet y OpenSubtitles; se prenden y se apagan. Traídos de tu Stremio: se quitan deslizando.")
            }
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
                    if env.session.state == .signedIn {
                        Button("Volver a traer", systemImage: "arrow.down.circle") { Task { await model.importAgain() } }   // sin los que quitaste
                    }
                }
                .accessibilityIdentifier("addons-add")
            }
            ToolbarItem(placement: .topBarLeading) {
                Button(editMode.isEditing ? "Listo" : "Ordenar") { editMode = editMode.isEditing ? .inactive : .active }
            }
        }
        .confirmationDialog(Text(verbatim: removing.map { String(format: Strings.tr("¿Quitar «%@»?", language: env.services.appSettings.uiLanguage), $0.name) } ?? ""),
                            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible, presenting: removing) { addon in
            Button(model.isLastSource(addon.id) ? "Quitar de todos modos" : "Quitar complemento", role: .destructive) { remove(addon, model) }
            Button("Cancelar", role: .cancel) {}
        } message: { addon in
            model.isLastSource(addon.id)
                ? Text("Es tu última fuente de video: sin ella no habrá versiones. Se borra su dirección de este iPhone, con su configuración; «Volver a traer» no lo regresa.")
                : Text("Se borra su dirección de este iPhone, con su configuración; «Volver a traer» no lo regresa.")
        }
        .confirmationDialog(Text("¿Apagar tu última fuente?"), isPresented: Binding(get: { turningOffLast != nil }, set: { if !$0 { turningOffLast = nil } }),
                            titleVisibility: .visible, presenting: turningOffLast) { addon in
            Button("Apagar de todos modos", role: .destructive) { Task { await model.setEnabled(addon.id, false) } }
            Button("Cancelar", role: .cancel) {}
        } message: { _ in Text("Sin ella no habrá versiones para ver hasta que prendas otra.") }
        .environment(\.editMode, $editMode)
        .task { await model.prepare() }
    }

    /// Quita y ofrece «Deshacer» mientras dura el aviso (lo regresa con su dirección y su lugar).
    private func remove(_ addon: InstalledAddon, _ model: AddonsModel) {
        Task {
            guard await model.remove(addon.id) else { return }
            env.notify("Quitaste el complemento", detail: addon.name, tone: .info, actionTitle: "Deshacer", actionSymbol: "arrow.uturn.backward") {
                Task { await model.undoRemove(addon.id) }
            }
        }
    }
}
