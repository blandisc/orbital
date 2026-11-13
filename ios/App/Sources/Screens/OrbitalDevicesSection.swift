import SwiftUI
import OrbitalCore
import OrbitalModels

/// K1 · Ajustes › Tu Orbital › «Aparatos conectados» (el mismo nombre en la TV, UX-36). IOS-13, como la TV (`deviceMenu`):
/// en la lista, cada aparato con su chevron; tocarlo abre su hoja con «Quitar» (pregunta antes; no se deshace). Este aparato
/// va aparte, al final: «Desconectar este iPhone». CX5: en el iPad, los demás no se tocan (se quitan desde el iPhone o la TV).
/// En el iPhone, «Conectar tu iPad» (CX4-A). Sin la conexión propia de este aparato no se enseña.
struct OrbitalDevicesSection: View {
    @Environment(AppEnvironment.self) private var env
    @State private var devices = ModelObserver(OrbitalDevicesModel(AppEnvironment.shared.services))
    @State private var opened: OrbitalPairedDevice?
    @State private var confirmingThis = false

    var body: some View {
        let _ = env.services.track()
        if devices.model.isAvailable { list(devices.model) }
    }

    @ViewBuilder private func list(_ model: OrbitalDevicesModel) -> some View {
        let others = model.devices.filter { !$0.isThis }
        let me = model.devices.first(where: \.isThis)
        Section {
            if !model.devices.isEmpty { ForEach(others) { device in row(device, model) } }
            else if case .failed(let why) = model.load {
                DSNotice(verbatim: env.message(why), tone: .warn)
                Button("Reintentar") { Task { await model.refresh() } }
            } else { DSInlineProgress(text: Text("Buscando tus aparatos…")) }
            if let me { thisDeviceLine(me) }
            if let problem = model.problem { DSNotice(verbatim: env.message(problem), tone: .warn) }
            InviteIPadRow()   // CX4-A: solo en el iPhone
        } header: { Text("Aparatos conectados") } footer: {
            env.services.platform == "iphone"
                ? Text("Cada uno está conectado por separado: quitar uno no toca a los demás. No se deshace: tendría que escanear el código otra vez.")
                : Text("Solo tu iPhone o la TV pueden quitar otro aparato.")
        }
        .listRowBackground(DS.surface)
        .task { await model.refresh() }
        .sheet(item: $opened) { device in
            OrbitalDeviceSheet(device: device, detail: detail(device)) { opened = nil; Task { await model.remove(device) } }
        }
        if let me {
            Section {
                Button(role: .destructive) { confirmingThis = true } label: { Text("Desconectar este iPhone") }
                    .accessibilityIdentifier("orbital-device-disconnect-this")
            } footer: { Text("Deja de hablar con tu TV hasta que escanees su código otra vez.") }
            .listRowBackground(DS.surface)
            .confirmationDialog(Text("¿Desconectar este iPhone?"), isPresented: $confirmingThis, titleVisibility: .visible) {   // ds-exception: confirmación de desconectar (sí o no)
                Button("Desconectar", role: .destructive) { Task { await model.remove(me) } }
                Button("Cancelar", role: .cancel) {}
            } message: { Text("Este iPhone deja de hablar con tu TV hasta que escanees su código otra vez. No se deshace.") }
        }
    }

    /// Un aparato: con chevron si se puede abrir (en el iPhone, todos); en el iPad, los demás solo se enseñan (CX5).
    @ViewBuilder private func row(_ device: OrbitalPairedDevice, _ model: OrbitalDevicesModel) -> some View {
        if model.canRemove(device) {
            Button { opened = device } label: {
                HStack(spacing: DS.Space.s3) {
                    label(device)
                    Image(systemName: "chevron.right").font(DS.TextRecipe.footnote.font).foregroundStyle(DS.textFaint).accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("orbital-device")
        } else {
            label(device).accessibilityElement(children: .combine).accessibilityIdentifier("orbital-device")
        }
    }

    /// «Este aparato», en la lista sin acción: se desconecta abajo, aparte.
    private func thisDeviceLine(_ device: OrbitalPairedDevice) -> some View {
        label(device).accessibilityElement(children: .combine).accessibilityIdentifier("orbital-device-this")
    }

    private func label(_ device: OrbitalPairedDevice) -> some View {
        HStack(spacing: DS.Space.s3) {
            Image(systemName: Self.symbol(device.platform)).foregroundStyle(DS.textMuted).frame(width: DS.SettingsLook.rowIcon).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: device.name).foregroundStyle(DS.text).lineLimit(1)
                detail(device).recipe(.footnote, color: DS.textMuted).lineLimit(1)
            }
            Spacer(minLength: DS.Space.s2)
        }
    }

    private func detail(_ device: OrbitalPairedDevice) -> Text {
        let locale = AppEnvironment.shared.uiLocale
        if device.isThis { return Text("Este aparato") }
        if let by = device.invitedBy { return Text("Invitado por \(by)") }   // CX4-A
        if let seen = device.seen { return Text("Lo usaste \(seen.formatted(.relative(presentation: .named).locale(locale)))") }
        return Text("Sin usarse todavía")
    }

    static func symbol(_ platform: String) -> String {
        platform == "ipad" ? "ipad" : "iphone"   // la Mac no se conecta con la TV (CX1-B)
    }
}

/// La hoja de un aparato (como `deviceMenu` de la TV): quién es y «Quitar», que pregunta antes («Cancelar» primero).
private struct OrbitalDeviceSheet: View {
    let device: OrbitalPairedDevice
    let detail: Text
    let remove: () -> Void
    @State private var confirming = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            DSSheetHeader(title: Text(verbatim: device.name), subtitle: detail)
            Text("Tiene su propia conexión con tu TV.").recipe(.secondary, color: DS.textMuted)
            Button(role: .destructive) { confirming = true } label: { Label("Quitar", systemImage: "minus.circle").frame(maxWidth: .infinity) }
                .dsSecondaryButton().controlSize(.large)
                .accessibilityIdentifier("orbital-device-remove")
        }
        .dsSheetContent(bottom: false)   // a la medida: el margen de la barra de inicio ya separa lo último
        .fittedSheet()
        .confirmationDialog(Text("¿Quitar \(device.name)?"), isPresented: $confirming, titleVisibility: .visible) {   // ds-exception: confirmación destructiva corta
            Button("Quitar", role: .destructive, action: remove)
            Button("Cancelar", role: .cancel) {}
        } message: { Text("Deja de hablar con tu TV hasta que lo escanee otra vez. No se deshace.") }
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
                // CX8-A: sin volver a escanear, si la TV lo confirma. «Escanear» se queda como la otra salida. IOS-4: el título no
                // dice «escanear» cuando lo principal es justo no escanear.
                let upgrade = env.services.canUpgradeConnection
                DSProblem(title: upgrade ? Text("Tu TV ya conecta a cada aparato por separado") : Text("Vuelve a escanear el código de tu TV"),
                          detail: upgrade ? Text("Pídele a tu TV que le dé a este iPhone su propia conexión, sin volver a escanear.")
                                          : Text("Tu TV ahora conecta a cada aparato por separado. Escanea su código una vez."),
                          symbol: upgrade ? "link" : "qrcode.viewfinder") {
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
