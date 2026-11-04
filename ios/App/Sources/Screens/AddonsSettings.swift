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
    /// Tu lista y la de tu TV (S6): solo en Ultra con una TV emparejada (S4).
    @State private var tv = ModelObserver(AppEnvironment.shared.services.addonSync)
    @State private var editMode: EditMode = .inactive
    /// El que se va a quitar (se confirma diciendo qué se pierde).
    @State private var removing: InstalledAddon?
    @State private var explaining = false

    var body: some View {
        let model = addons.model
        Form {
            // IOS-9: lo que falla va primero, en ámbar (antes, abajo y en rojo); la explicación, después.
            if let error = model.error {
                Section { DSNotice(verbatim: env.message(error), tone: .warn) }.listRowBackground(DS.surface)
            }
            if tv.model.status != .off {
                Section { AddonTVStatus(status: tv.model.status, waitingForKeys: tv.model.waitingForKeys) { Task { await tv.model.refresh() } } }
                    .listRowBackground(DS.surface)
            }
            Section {
                Button { explaining = true } label: { Label("¿Qué es esto?", systemImage: "questionmark.circle") }
                    .accessibilityIdentifier("addons-explain")
            }
            .listRowBackground(DS.surface)
            if !model.torrentioChoice.isEmpty { torrentioChoice(model) }
            Section {
                ForEach(model.items) { addon in
                    NavigationLink { AddonDetail(addons: addons, id: addon.id) { remove($0, model) } } label: {
                        AddonRowLabel(addon: addon, health: model.health(addon), english: env.services.appSettings.uiLanguage.hasPrefix("en"),
                                      torrents: model.onlyTorrents(addon), tv: env.services.orbitalOn)
                    }
                    // Solo los traídos de Stremio se quitan; los que vienen con Orbital solo se apagan (C7). Con el dedo se desliza;
                    // con el mouse o el trackpad (Mac, iPad), el menú del clic secundario.
                    // Sin `role: .destructive`: con él, iOS borraba la fila al momento y la regresaba mientras preguntaba «¿Quitar…?»
                    // (Fernando, 3 nov: «se traba… lo quita y lo vuelve a poner»). El rojo lo da el tinte; se quita al confirmar.
                    .swipeActions { if model.canRemove(addon) { Button("Quitar") { removing = addon }.tint(DS.danger) } }
                    .contextMenu { if model.canRemove(addon) { Button("Quitar complemento", systemImage: "trash", role: .destructive) { removing = addon } } }
                    .accessibilityIdentifier("addon-row-\(addon.id)")
                }
                .onMove { from, to in Task { await model.move(fromOffsets: from, toOffset: to) } }
                if model.items.isEmpty {
                    // Sin sesión de Stremio no hay «Volver a traer»: se dice la salida que sí está («Agregar», arriba).
                    (env.session.state == .signedIn ? Text("Sin complementos: vuelve a traer los de tu Stremio.")
                                                    : Text("Sin complementos: agrega los que vienen con Orbital con «Agregar», arriba."))
                        .foregroundStyle(DS.textMuted)
                }
            } header: { Text("Se preguntan en este orden") } footer: {
                Text("Toca uno para ver qué aporta, configurarlo o quitarlo. «Ordenar» cambia el orden.")
            }
            .listRowBackground(DS.surface)
            if tv.model.status != .off, !tv.model.tvOnly.isEmpty {
                Section {
                    ForEach(tv.model.tvOnly, id: \.id) { AddonTVOnlyRow(addon: $0) }
                } header: { Text("En tu TV") } footer: { Text("Viven en tu TV; este iPhone no los usa.") }
                .listRowBackground(DS.surface)
            }
            if env.session.state == .signedIn {
                Section {
                    Button { Task { await model.importAgain() } } label: { Label("Volver a traer", systemImage: "arrow.down.circle") }
                        .disabled(model.working)
                        .accessibilityIdentifier("addons-reimport")
                } header: { Text("Traídos de tu Stremio") } footer: { Text("Tu Stremio no se toca. Lo que quitaste no regresa solo.") }
                .listRowBackground(DS.surface)
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
            if model.items.count > 1 || editMode.isEditing {   // con uno o ninguno no hay qué ordenar
                // IOS-17: a la derecha, junto a «Agregar» (a la izquierda empujaba el título).
                ToolbarItem(placement: .topBarTrailing) {
                    Button(editMode.isEditing ? "Listo" : "Ordenar") { editMode = editMode.isEditing ? .inactive : .active }
                }
            }
        }
        .confirmationDialog(Text(verbatim: removing.map { String(format: Strings.tr("¿Quitar «%@»?", language: env.services.appSettings.uiLanguage), $0.name) } ?? ""),
                            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible, presenting: removing) { addon in
            Button(model.isLastSource(addon.id) ? "Quitar de todos modos" : "Quitar complemento", role: .destructive) { remove(addon, model) }
            Button("Cancelar", role: .cancel) {}
        } message: { addon in
            AddonRemoveMessage(last: model.isLastSource(addon.id), tv: env.services.orbital.isConfigured)
        }
        .sheet(isPresented: $explaining) { DebridExplainer(topic: .addons) { explaining = false } }
        .environment(\.editMode, $editMode)
        .task {
            await model.prepare()
            await model.syncWithTV()
            env.announceAddonClash()
        }
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
                                      detail: TorrentioWords.summary(candidate.options, uiLanguage: ui), action: true)
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

extension AppEnvironment {
    /// S3: tus opciones y las de tu TV cambiaron en lo mismo; se quedó la de la TV y se ofrece la tuya.
    func announceAddonClash() {
        let sync = services.addonSync
        guard let clash = sync.clash else { return }
        sync.clearClash()
        let ui = services.appSettings.uiLanguage
        // «Se quedó la de la TV (9:40) · Usar la de este iPhone» no cabe en el aviso: la hora pasa abajo, con lo que chocó.
        let when = clash.at.map { Strings.clock($0, language: ui) }
        let detail = (clash.options.map { Strings.tr($0, language: ui) } + [when].compactMap { $0 }).joined(separator: " · ")
        notify("Se quedó la de la TV", detail: detail, tone: .info, actionTitle: "Usar la mía", actionSymbol: "iphone") {
            Task { await sync.useMine() }
        }
    }
}
