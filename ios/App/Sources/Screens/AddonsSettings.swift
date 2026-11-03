import SwiftUI
import OrbitalCore
import OrbitalAddons
import OrbitalModels

/// Ajustes › Complementos (C1): «Se preguntan en este orden» (con «Ordenar» se arrastran), cada uno con qué aporta y cómo le
/// va en este aparato («Contesta en 0,6 s», «No contesta desde el sábado · se salta»). Tocar uno abre su página: qué aporta,
/// prenderlo, «Configurar» (C3) y quitarlo (C7). Si hay dos Torrentio, se pregunta con cuál quedarse (C5). Ya no se agregan
/// complementos pegando su dirección (Fernando, 3 nov 2026, C9); los que ya tenías se quedan.
struct AddonsSettings: View {
    @Environment(AppEnvironment.self) private var env
    @State private var addons = ModelObserver(AddonsModel(AppEnvironment.shared.services))
    @State private var editMode: EditMode = .inactive
    /// El que se va a quitar (se confirma diciendo qué se pierde).
    @State private var removing: InstalledAddon?
    @State private var explaining = false

    var body: some View {
        let model = addons.model
        Form {
            Section {
                Button { explaining = true } label: { Label("¿Qué es esto?", systemImage: "questionmark.circle") }
                    .accessibilityIdentifier("addons-explain")
            }
            .listRowBackground(DS.surface)
            if !model.torrentioChoice.isEmpty { torrentioChoice(model) }
            Section {
                ForEach(model.items) { addon in
                    NavigationLink { AddonDetail(addons: addons, id: addon.id) { remove($0, model) } } label: {
                        AddonRowLabel(addon: addon, health: model.health(addon), english: env.services.appSettings.uiLanguage.hasPrefix("en"))
                    }
                    // Solo los traídos de Stremio se quitan; los que vienen con Orbital solo se apagan (C7). Con el dedo se desliza;
                    // con el mouse o el trackpad (Mac, iPad), el menú del clic secundario.
                    .swipeActions { if model.canRemove(addon) { Button("Quitar", role: .destructive) { removing = addon }.tint(DS.danger) } }   // rojo, como en iOS
                    .contextMenu { if model.canRemove(addon) { Button("Quitar complemento", systemImage: "trash", role: .destructive) { removing = addon } } }
                    .accessibilityIdentifier("addon-row-\(addon.id)")
                }
                .onMove { from, to in Task { await model.move(fromOffsets: from, toOffset: to) } }
                if model.items.isEmpty { Text("Sin complementos: vuelve a traer los de tu Stremio.").foregroundStyle(DS.textMuted) }
            } header: { Text("Se preguntan en este orden") } footer: {
                Text("Toca uno para ver qué aporta, configurarlo o quitarlo. «Ordenar» cambia el orden.")
            }
            .listRowBackground(DS.surface)
            if env.session.state == .signedIn {
                Section {
                    Button { Task { await model.importAgain() } } label: { Label("Volver a traer", systemImage: "arrow.down.circle") }
                        .disabled(model.working)
                        .accessibilityIdentifier("addons-reimport")
                } header: { Text("Traídos de tu Stremio") } footer: { Text("Tu Stremio no se toca. Lo que quitaste no regresa solo.") }
                .listRowBackground(DS.surface)
            }
            if let error = model.error {
                Section { Text(verbatim: env.message(error)).foregroundStyle(DS.danger).font(DS.TextRecipe.footnote.font) }.listRowBackground(DS.surface)
            }
        }
        .tint(DS.accent)
        .scrollContentBackground(.hidden).background(Backdrop())
        .navigationTitle("Complementos").navigationBarTitleDisplayMode(.inline)
        .readableListWidth()
        .toolbar {
            if !model.missingRecommended.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Menu("Agregar", systemImage: "plus") {
                        Section("Vienen con Orbital") {
                            ForEach(model.missingRecommended) { t in Button(t.name) { Task { await model.add(t) } } }
                        }
                    }
                    .accessibilityIdentifier("addons-add")
                }
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
        .sheet(isPresented: $explaining) { DebridExplainer(topic: .addons) { explaining = false }.presentationDetents([.medium, .large]) }
        .environment(\.editMode, $editMode)
        .task { await model.prepare() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("addons-settings")
    }

    /// C5: dos Torrentio (el de Orbital y el de tu Stremio, o dos traídos): cuál se queda, con lo que trae cada uno.
    @ViewBuilder private func torrentioChoice(_ model: AddonsModel) -> some View {
        let ui = env.services.appSettings.uiLanguage
        Section {
            ForEach(model.torrentioChoice) { candidate in
                Button { Task { await model.keepTorrentio(candidate) } } label: {
                    TorrentioRowLabel(title: candidate.addonID == nil ? Text("Quedarme con el de Orbital") : Text("Quedarme con el de tu Stremio"),
                                      detail: TorrentioWords.summary(candidate.options, uiLanguage: ui))
                }
                .accessibilityIdentifier("addons-keep-\(candidate.id)")
            }
        } header: { Text("Tienes \(model.torrentioChoice.count) Torrentio") } footer: {
            Text("Se queda uno, con tu clave de Real-Debrid de Cuentas. El otro se quita de este iPhone; tu Stremio no se toca.")
        }
        .listRowBackground(DS.surface)
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
