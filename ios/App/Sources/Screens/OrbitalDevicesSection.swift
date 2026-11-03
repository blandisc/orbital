import SwiftUI
import OrbitalCore
import OrbitalModels

/// K1 · Ajustes › Tu Orbital › «Aparatos conectados» (el mismo nombre en la TV, UX-36), este marcado. CX5: en el iPhone,
/// «Quitar» en todos; en el iPad, solo en sí mismo (los demás se quitan desde el iPhone o la TV). Pregunta antes; no se deshace.
/// En el iPhone, «Conectar tu iPad» (CX4-A). Sin la conexión propia de este aparato no se enseña.
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
            if !model.devices.isEmpty { ForEach(model.devices) { device in row(device, model) } }
            else if case .failed(let why) = model.load {
                DSNotice(verbatim: env.message(why), tone: .warn)
                Button("Reintentar") { Task { await model.refresh() } }
            } else { DSInlineProgress(text: Text("Buscando tus aparatos…")) }
            if let problem = model.problem { DSNotice(verbatim: env.message(problem), tone: .warn) }
            InviteIPadRow()   // CX4-A: solo en el iPhone
        } header: { Text("Aparatos conectados") } footer: {
            env.services.platform == "iphone"
                ? Text("Cada uno está conectado por separado: quitar uno no toca a los demás. No se deshace: tendría que escanear el código otra vez.")
                : Text("Solo tu iPhone o la TV pueden quitar otro aparato.")
        }
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

    private func row(_ device: OrbitalPairedDevice, _ model: OrbitalDevicesModel) -> some View {
        HStack(spacing: DS.Space.s3) {
            Image(systemName: Self.symbol(device.platform)).foregroundStyle(DS.textMuted).frame(width: DS.SettingsLook.rowIcon).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: device.name).foregroundStyle(DS.text).lineLimit(1)
                detail(device).recipe(.footnote, color: DS.textMuted).lineLimit(1)
            }
            Spacer(minLength: DS.Space.s2)
            if model.canRemove(device) {   // CX5: el iPad solo se quita a sí mismo
                Button("Quitar", role: .destructive) { removing = device }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("orbital-device-remove")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(device.isThis ? "orbital-device-this" : "orbital-device")
    }

    private func detail(_ device: OrbitalPairedDevice) -> Text {
        let locale = AppEnvironment.shared.uiLocale
        if device.isThis { return Text("Este aparato") }
        if let by = device.invitedBy { return Text("Invitado por \(by)") }   // CX4-A
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
    @State private var upgrading = false

    var body: some View {
        let _ = env.services.track()
        Group { if let reason = env.services.rescanReason { problem(reason) } }
            // Fuera del problema: al quedar conectado el problema se va, y la hoja se queda para decir «Listo».
            .sheet(isPresented: $upgrading) { OrbitalUpgradeSheet(scan: { upgrading = false; scan() }) }
    }

    @ViewBuilder private func problem(_ reason: Services.RescanReason) -> some View {
        Section {
            switch reason {
            case .newTV:   // TEC-30: no «te quitó» (asusta y es falso)
                DSProblem(title: Text("Tu TV es nueva: vuelve a escanear su código"), detail: Text("Se reinstaló o es otra consola. Tus aparatos se conectan otra vez, uno por uno."),
                          symbol: "qrcode.viewfinder") { scanButton(primary: true) }
            case .removed:
                DSProblem(title: Text("Vuelve a escanear el código de tu TV"), detail: Text("Tu TV quitó este iPhone de sus aparatos."),
                          symbol: "qrcode.viewfinder") { scanButton(primary: true) }
            case .needsOwnConnection:
                // CX8-A: sin volver a escanear, si la TV lo confirma. «Escanear» se queda como la otra salida.
                DSProblem(title: Text("Vuelve a escanear el código de tu TV"), detail: Text("Tu TV ahora conecta a cada aparato por separado. Puedes pedírselo desde aquí."),
                          symbol: "qrcode.viewfinder") {
                    if env.services.canUpgradeConnection {
                        Button { upgrading = true } label: { Label("Darle su propia conexión", systemImage: "link").frame(maxWidth: .infinity) }
                            .dsProblemFix(primary: true)
                            .accessibilityIdentifier("orbital-upgrade")
                    }
                    scanButton(primary: !env.services.canUpgradeConnection)
                }
            }
        }
        .listRowBackground(DS.surface)
        #if DEBUG
        .task { if Demo.isOn, Demo.cx?.hasPrefix("upgrade") == true { upgrading = true } }
        #endif
    }

    private func scanButton(primary: Bool) -> some View {
        Button(action: scan) { Label("Escanear", systemImage: "qrcode.viewfinder").frame(maxWidth: .infinity) }
            .dsProblemFix(primary: primary)
            .accessibilityIdentifier("orbital-rescan")
    }
}
