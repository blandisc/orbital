import SwiftUI
import AuthenticationServices
import OrbitalCore
import OrbitalAddons
import OrbitalModels

/// La página de un complemento (C3, C7): qué aporta, cómo le va aquí, prenderlo, «Configurar» (Torrentio abre su página en
/// la app, T1; uno traído con página propia la abre dentro de Orbital, M4) y, abajo y en rojo, quitarlo (solo los traídos).
struct AddonDetail: View {
    let addons: ModelObserver<AddonsModel>
    let id: String
    let remove: (InstalledAddon) -> Void
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Environment(\.webAuthenticationSession) private var webAuth
    @State private var confirmRemove = false
    @State private var turningOffLast = false
    @State private var configuring = false

    var body: some View {
        let model = addons.model
        if let addon = model.items.first(where: { $0.id == id }) {
            content(addon, model)
        } else {
            DSEmptyState(symbol: "puzzlepiece.extension", title: Text("Ya no está"), message: Text("Este complemento se quitó."))
        }
    }

    @ViewBuilder private func content(_ addon: InstalledAddon, _ model: AddonsModel) -> some View {
        Form {
            Section {
                LabeledContent { Text(addon.isBuiltIn ? "Viene con Orbital" : "Traído de tu Stremio").foregroundStyle(DS.textMuted) } label: {
                    AddonWhat(addon: addon).foregroundStyle(DS.text)
                }
                if addon.enabled, model.health(addon) != .unknown {
                    LabeledContent("Estado") { AddonHealthLine(state: model.health(addon), english: env.services.appSettings.uiLanguage.hasPrefix("en")) }
                }
                Toggle(isOn: Binding(get: { addon.enabled }, set: { on in
                    // La última fuente: antes de apagarla se avisa (C7).
                    if !on, model.isLastSource(addon.id) { turningOffLast = true } else { Task { await model.setEnabled(addon.id, on) } }
                })) { Text("Prendido").foregroundStyle(DS.text) }
                .accessibilityIdentifier("addon-enabled")
            } footer: {
                if addon.enabled, case .down(_, true) = model.health(addon) {
                    Text("Tras dos fallos seguidos ya no se le espera; se vuelve a probar solo, hasta cada hora.")
                }
            }
            .listRowBackground(DS.surface)
            switch model.configure(addon) {
            case .torrentio?:
                Section {
                    NavigationLink { TorrentioSettings() } label: { Label("Configurar", systemImage: "slider.horizontal.3").foregroundStyle(DS.text) }
                        .accessibilityIdentifier("addon-configure")
                } footer: { Text("Idiomas, calidades y qué versiones te enseña.") }
                .listRowBackground(DS.surface)
            case .page(let url)?:
                Section {
                    Button { configure(addon, url, model) } label: { Label("Configurar", systemImage: "slider.horizontal.3") }
                        .disabled(configuring)
                        .accessibilityIdentifier("addon-configure")
                } footer: { Text("Abre su propia página. Al tocar «Install» ahí, se guarda en este mismo complemento.") }
                .listRowBackground(DS.surface)
            case nil: EmptyView()
            }
            if model.canRemove(addon) {
                Section {
                    Button("Quitar complemento", role: .destructive) { confirmRemove = true }
                        .accessibilityIdentifier("addon-remove")
                } footer: { Text("Dejarás de ver lo que aporta. «Volver a traer» no lo regresa solo.") }
                .listRowBackground(DS.surface)
            }
        }
        .tint(DS.accent)
        .scrollContentBackground(.hidden).background(Backdrop())
        .navigationTitle(Text(verbatim: addon.name)).navigationBarTitleDisplayMode(.inline)
        .readableListWidth()
        .confirmationDialog(Text("¿Quitar «\(addon.name)»?"), isPresented: $confirmRemove, titleVisibility: .visible) {
            Button(model.isLastSource(addon.id) ? "Quitar de todos modos" : "Quitar complemento", role: .destructive) { dismiss(); remove(addon) }
            Button("Cancelar", role: .cancel) {}
        } message: {
            model.isLastSource(addon.id)
                ? Text("Es tu última fuente de video: sin ella no habrá versiones. Se borra su dirección de este iPhone, con su configuración; «Volver a traer» no lo regresa.")
                : Text("Se borra su dirección de este iPhone, con su configuración; «Volver a traer» no lo regresa.")
        }
        .confirmationDialog(Text("Te quedarás sin fuentes"), isPresented: $turningOffLast, titleVisibility: .visible) {
            Button("Apagar de todos modos", role: .destructive) { Task { await model.setEnabled(addon.id, false) } }
            Button("Cancelar", role: .cancel) {}
        } message: { Text("Es tu único complemento de video prendido. Apagado, no podrás ver nada hasta prenderlo. Tu configuración se queda.") }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("addon-detail")
    }

    /// M4: su página de configuración dentro de la app; «Install» devuelve un enlace `stremio://…/manifest.json` que se guarda
    /// en este mismo complemento (nunca agrega otro).
    private func configure(_ addon: InstalledAddon, _ url: URL, _ model: AddonsModel) {
        configuring = true
        Task {
            defer { configuring = false }
            guard let back = try? await webAuth.authenticate(using: url, callbackURLScheme: "stremio", preferredBrowserSession: .ephemeral) else { return }
            if await model.saveConfiguration(addon.id, url: back.absoluteString) {
                env.notify("Guardé su nueva configuración", detail: addon.name, tone: .success)
            } else {
                env.notify("No se guardó", detail: "La página dio la dirección de otro complemento", tone: .warn)
            }
        }
    }
}
