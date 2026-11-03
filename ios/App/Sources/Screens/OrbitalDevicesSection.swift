import SwiftUI
import OrbitalCore
import OrbitalModels

/// K1 · Ajustes › Tu Orbital › los aparatos emparejados con tu TV, este marcado, cada uno con «Quitar» (pregunta antes; no se
/// deshace). Sin la llave de este aparato no se enseña.
struct OrbitalDevicesSection: View {
    @Environment(AppEnvironment.self) private var env
    @State private var devices = ModelObserver(OrbitalDevicesModel(AppEnvironment.shared.services))
    @State private var removing: OrbitalPairedDevice?

    var body: some View {
        let _ = env.services.track()
        if devices.model.isAvailable { list(devices.model) }
    }

    @ViewBuilder private func list(_ model: OrbitalDevicesModel) -> some View {
        Section {
            if !model.devices.isEmpty { ForEach(model.devices) { device in row(device) } }
            else if case .failed(let why) = model.load {
                DSNotice(verbatim: env.message(why), tone: .warn)
                Button("Reintentar") { Task { await model.refresh() } }
            } else { DSInlineProgress(text: Text("Buscando tus aparatos…")) }
            if let problem = model.problem { DSNotice(verbatim: env.message(problem), tone: .warn) }
        } header: { Text("Aparatos de tu TV") } footer: { Text("Cada uno entra con su propia llave. Quitar uno no se deshace: tendría que escanear el código otra vez.") }
        .listRowBackground(DS.surface)
        .task { await model.refresh() }
        .confirmationDialog(removing.map { Text("¿Quitar \($0.name)?") } ?? Text(verbatim: ""), isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible, presenting: removing) { device in
            Button("Quitar", role: .destructive) { Task { await model.remove(device) } }
            Button("Cancelar", role: .cancel) {}
        } message: { device in
            device.isThis ? Text("Este iPhone deja de hablar con tu TV hasta que escanees su código otra vez. No se deshace.")
                          : Text("Deja de hablar con tu TV hasta que lo escanee otra vez. No se deshace.")
        }
    }

    private func row(_ device: OrbitalPairedDevice) -> some View {
        HStack(spacing: DS.Space.s3) {
            Image(systemName: Self.symbol(device.platform)).foregroundStyle(DS.textMuted).frame(width: DS.SettingsLook.rowIcon).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: device.name).foregroundStyle(DS.text).lineLimit(1)
                detail(device).recipe(.footnote, color: DS.textMuted).lineLimit(1)
            }
            Spacer(minLength: DS.Space.s2)
            Button("Quitar", role: .destructive) { removing = device }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("orbital-device-remove")
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(device.isThis ? "orbital-device-this" : "orbital-device")
    }

    private func detail(_ device: OrbitalPairedDevice) -> Text {
        let locale = AppEnvironment.shared.uiLocale
        if device.isThis { return Text("Este aparato") }
        if let seen = device.seen { return Text("Se usó \(seen.formatted(.relative(presentation: .named).locale(locale)))") }
        return Text("Sin usarse todavía")
    }

    static func symbol(_ platform: String) -> String {
        switch platform { case "ipad": "ipad"; case "mac": "laptopcomputer"; default: "iphone" }
    }
}

/// La frase tranquila con su arreglo, arriba de Tu Orbital y solo cuando pasa: la TV ya usa una llave para cada aparato (o quitó
/// este) y basta con escanear su código.
struct OrbitalRescanProblem: View {
    /// «Escanear»: la hoja de conectar con la cámara.
    let scan: () -> Void
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let _ = env.services.track()
        if env.services.orbitalNeedsRescan { problem(removed: env.services.orbitalAuth.problem == .removed) }
    }

    private func problem(removed: Bool) -> some View {
        Section {
            DSProblem(title: Text("Vuelve a escanear el código de tu TV"),
                      detail: removed ? Text("Tu TV quitó este iPhone de sus aparatos.") : Text("Tu TV ahora le da una llave a cada aparato."),
                      symbol: "qrcode.viewfinder") {
                Button(action: scan) { Label("Escanear", systemImage: "qrcode.viewfinder").frame(maxWidth: .infinity) }
                    .dsProblemFix(primary: true)
                    .accessibilityIdentifier("orbital-rescan")
            }
        }
        .listRowBackground(DS.surface)
    }
}
