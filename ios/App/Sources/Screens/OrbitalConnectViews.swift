import SwiftUI
import OrbitalCore
import OrbitalModels

/// CX7-A · «¿Cómo se llama este aparato?», ya escrito con la sugerencia («iPad de Fernando»), hasta 60 letras: así en la lista
/// de la TV sabes cuál es cuál (iOS ya no le dice a la app el nombre real del aparato).
struct DeviceNameField: View {
    @Binding var name: String

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            Text("¿Cómo se llama este aparato?").recipe(.footnote, color: DS.textMuted)
            TextField("Nombre", text: Binding(get: { name }, set: { name = String($0.prefix(Services.deviceNameLimit)) }))
                .textInputAutocapitalization(.words).autocorrectionDisabled()
                .accessibilityIdentifier("orbital-device-name")
        }
    }
}

/// CX8-A · «Darle su propia conexión» sin volver a escanear: el nombre, «Confirma en tu TV» mientras la TV pregunta y lo que
/// contestó. Si dice que no o no contesta, en palabras y con «Escanear».
struct OrbitalUpgradeSheet: View {
    let scan: () -> Void
    @State private var upgrade = ModelObserver(OrbitalUpgradeModel(AppEnvironment.shared.services))
    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let model = upgrade.model
        NavigationStack {
            Form {
                switch model.stage {
                case .naming:
                    Section {
                        DeviceNameField(name: Binding(get: { model.name }, set: { model.name = $0 }))
                    } footer: { Text("Tu TV te pregunta en su pantalla. Una vez por aparato.") }
                    .listRowBackground(DS.surface)
                    Section {
                        Button { Task { await model.start() } } label: { Text("Pedírsela a tu TV").frame(maxWidth: .infinity) }
                            .dsPrimaryButton(size: .large)
                            .accessibilityIdentifier("orbital-upgrade-start")
                    }
                    .listRowBackground(Color.clear)
                case .waiting:
                    Section {
                        DSInlineProgress(text: Text("Confirma en tu TV"))
                        Text("Tu TV pregunta en su pantalla «¿Darle su propia conexión a \(model.name)?». Elige «Darle su propia conexión» con el control. La pregunta dura 3 minutos.").recipe(.footnote, color: DS.textMuted)
                        // AU3-A (Fernando, 3 nov): la TV no pausa lo que ves para preguntar; se dice aquí, con la salida de siempre.
                        Text("Si estás viendo algo en la TV, ciérralo para contestar.").recipe(.footnote, color: DS.textMuted)
                            .accessibilityIdentifier("orbital-upgrade-close-video")
                        Button(action: scan) { Label("Escanear en su lugar", systemImage: "qrcode.viewfinder") }
                            .accessibilityIdentifier("orbital-upgrade-scan-instead")
                    }
                    .listRowBackground(DS.surface)
                    .accessibilityIdentifier("orbital-upgrade-waiting")
                case .done:
                    Section {
                        Label { Text("Listo: este iPhone ya tiene su propia conexión") } icon: { Image(systemName: "checkmark.circle.fill").foregroundStyle(DS.success) }
                            .accessibilityIdentifier("orbital-upgrade-done")
                    }
                    .listRowBackground(DS.surface)
                case .denied: answer(Text("Tu TV dijo que no"), Text("Nada cambió. Si fue un error, pídeselo otra vez o escanea su código."), model)
                case .timedOut: answer(Text("Tu TV no contestó a tiempo"), Text("Revisa que esté prendida y pídeselo otra vez, o escanea su código."), model)
                case .failed(let why): answer(Text(verbatim: env.message(why)), nil, model)
                }
            }
            .tint(DS.accent)
            .scrollContentBackground(.hidden).background(Backdrop())
            .navigationTitle("Darle su propia conexión").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(model.stage == .done ? "Listo" : "Cancelar") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(model.stage == .waiting)
        #if DEBUG
        .task { if Demo.isOn, Demo.cx?.hasPrefix("upgrade") == true { await model.start() } }
        #endif
    }

    private func answer(_ title: Text, _ detail: Text?, _ model: OrbitalUpgradeModel) -> some View {
        Section {
            DSProblem(title: title, detail: detail, symbol: "tv") {
                Button { model.reset() } label: { Text("Pedírsela otra vez").frame(maxWidth: .infinity) }
                    .dsProblemFix(primary: true)
                Button(action: scan) { Label("Escanear", systemImage: "qrcode.viewfinder").frame(maxWidth: .infinity) }
                    .dsProblemFix(primary: false)
                    .accessibilityIdentifier("orbital-upgrade-scan")
            }
            .accessibilityIdentifier("orbital-upgrade-answer")
        }
        .listRowBackground(DS.surface)
    }
}

/// CX4-A · en el iPhone conectado: «Conectar tu iPad». La invitación viaja por tu llavero de iCloud y el iPad la acepta con
/// un toque (nunca sola: si la familia comparte cuenta de Apple, nadie queda conectado sin querer).
struct InviteIPadRow: View {
    @State private var invite = ModelObserver(OrbitalInviteModel(AppEnvironment.shared.services))
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let model = invite.model
        let _ = env.services.track()
        if model.canInvite {
            Button { Task { await model.inviteIPad() } } label: {
                TorrentioRowLabel(title: Text("Conectar tu iPad"), detail: Text("La invitación sale al abrir Orbital en el iPad. Llega por tu llavero de iCloud."), action: true)
            }
            .disabled(model.state == .working)
            .accessibilityIdentifier("orbital-invite-ipad")
            switch model.state {
            case .working: DSInlineProgress(text: Text("Hablando con tu TV…"))
            case .sent(let sent):
                DSNotice(text: "Listo: abre Orbital en tu iPad. Vale hasta el \(Strings.date(sent.expires, .weekdayDayMonth, language: env.services.appSettings.uiLanguage)).", tone: .success)
            case .failed(let why): DSNotice(verbatim: env.message(why), tone: .warn)
            case .idle, .joined: EmptyView()
            }
        }
    }
}

/// CX4-A · en el iPad que todavía no está conectado y ve la invitación de tu iPhone: una tarjeta, un toque. Vencida o ya
/// usada: «Abre Orbital en tu iPhone» o «Escanear». La Mac nunca la ve (CX1-B).
struct IPadInviteCard: View {
    let scan: () -> Void
    @State private var invite = ModelObserver(OrbitalInviteModel(AppEnvironment.shared.services))
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let model = invite.model
        let _ = env.services.track()
        if let pending = model.invite, model.state != .joined {
            Section {
                if model.inviteIsValid {
                    VStack(alignment: .leading, spacing: DS.Space.s3) {
                        IconBeside(symbol: "ipad.and.iphone", color: DS.accent) {
                            Text("¿Conectar con \(pending.tvName)?").recipe(.labelLarge, color: DS.text)
                            Text("Tu iPhone te invita. Este iPad tendrá su propia conexión.").recipe(.footnote, color: DS.textMuted)
                        }
                        DeviceNameField(name: Binding(get: { model.name }, set: { model.name = $0 })).textFieldStyle(.roundedBorder)
                        Button { Task { await model.accept() } } label: { Text("Conectar").frame(maxWidth: .infinity) }
                            .dsPrimaryButton(size: .large)
                            .disabled(model.state == .working)
                            .accessibilityIdentifier("orbital-invite-accept")
                        if model.state == .working { DSInlineProgress(text: Text("Conectando…")) }
                        if case .failed(let why) = model.state { DSNotice(verbatim: env.message(why), tone: .warn) }
                    }
                    .padding(.vertical, DS.Space.s2)
                } else {
                    DSProblem(title: Text("Esta invitación ya venció"), detail: Text("Abre Orbital en tu iPhone para que llegue otra, o escanea el código de tu TV."),
                              symbol: "ipad.and.iphone") {
                        Button(action: scan) { Label("Escanear", systemImage: "qrcode.viewfinder").frame(maxWidth: .infinity) }
                            .dsProblemFix(primary: true)
                    }
                }
            }
            .listRowBackground(DS.surface)
            .accessibilityIdentifier("orbital-invite-card")
        }
    }
}
