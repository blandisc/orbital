import SwiftUI
import OrbitalModels

/// Ajustes › «Usar con tu Orbital» (maquetas 2–7 de https://claude.ai/artifact/FwxKwFe1Y19tTu6LLv3Vhw): primero conectar con la
/// consola (el código de la TV, leído dentro de la app, o a mano) y luego un mini tutorial de tres páginas. «Ahora no» la deja
/// apagada; «Ya lo sé» se salta el tutorial.
struct OrbitalSetupView: View {
    @State private var setup: ModelObserver<OrbitalSetupModel>
    @State private var scanning = false
    @State private var byHand = false
    @State private var address = ""
    @State private var token = ""
    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var env

    init(tutorialOnly: Bool = false) {
        _setup = State(wrappedValue: ModelObserver(OrbitalSetupModel(AppEnvironment.shared.services, tutorialOnly: tutorialOnly)))
    }

    var body: some View {
        NavigationStack {
            page.toolbar {
                if setup.model.stage == .connect {
                    ToolbarItem(placement: .cancellationAction) { Button("Ahora no") { dismiss() }.accessibilityIdentifier("orbital-setup-cancel") }
                }
            }
        }
        .tint(DS.accent)
        .interactiveDismissDisabled(setup.model.connecting)
        .fullScreenCover(isPresented: $scanning) {
            QRScanner(prompt: Text("Apunta al código de la TV"), found: { code in
                scanning = false
                Task { await setup.model.scanned(code) }
            }, fallback: { byHand = true })
        }
        #if DEBUG
        // `-demo-open orbital-setup -demo-scan`: lee un código de mentira, para recorrer la hoja sin cámara.
        .task { if Demo.isOn, CommandLine.arguments.contains("-demo-scan") { await setup.model.scanned("orbital-ios://pair?u=https%3A%2F%2Ftv.demo.invalid&t=demo") } }
        #endif
    }

    @ViewBuilder private var page: some View {
        let model = setup.model
        switch model.stage {
        case .connect: connect(model)
        case .connected:
            GuidePage(title: Text("Ya se conocen"), message: Text("Tu iPhone y tu Orbital quedaron conectados."), step: (0, 2),
                      primary: Text("Ver qué puedes hacer"), secondary: Text("Ya lo sé"), next: { _ = model.advance() }, skip: { dismiss() }) {
                GuidePiece(symbol: "checkmark.circle.fill", tint: DS.success, title: Text("Tu Orbital"), tag: Text(verbatim: model.host))
                Text("Tu Trakt, tu Real-Debrid y tu país se quedan como los tienes aquí.").font(DS.TextRecipe.secondary.font).foregroundStyle(DS.textMuted)
            }
        case .tutorial(let number): tutorial(number, model)
        }
    }

    @ViewBuilder private func connect(_ model: OrbitalSetupModel) -> some View {
        GuidePage(title: Text("Conecta tu Orbital"), message: Text("El iPhone y la TV se reconocen una vez y ya."), step: (0, 2),
                  primary: Text("Escanear el código"), primaryEnabled: !model.connecting, secondary: Text("Conectar a mano"),
                  next: { scanning = true }, skip: { byHand.toggle() }) {
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                GuideNumberedStep(number: 1, text: Text("En la TV abre Ajustes › Cuentas › iPhone. Aparece un código.")) { EmptyView() }
                GuideNumberedStep(number: 2, text: Text("Toca «Escanear el código» y apúntale.")) { EmptyView() }
                if model.connecting { HStack(spacing: DS.Space.s2) { ProgressView(); Text("Conectando…").foregroundStyle(DS.textMuted) } }
                if let problem = model.problem { DSNotice(verbatim: env.message(problem), tone: .error) }
                if byHand {
                    VStack(alignment: .leading, spacing: DS.Space.s3) {
                        TextField("Dirección (orbital.tudominio.com)", text: $address)
                            .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL).textContentType(.URL)
                        SecureField("Token (el mismo de Alexa)", text: $token).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Button("Conectar") { Task { await model.connectByHand(address: address, token: token) } }
                            .buttonStyle(.glass).disabled(model.connecting)
                    }
                    .textFieldStyle(.roundedBorder)
                    .padding(DS.Space.s4)
                    .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.Radius.lg))
                }
            }
        }
    }

    @ViewBuilder private func tutorial(_ number: Int, _ model: OrbitalSetupModel) -> some View {
        let last = number == OrbitalSetupModel.tutorialPages
        let next = { if model.advance() == nil { dismiss() } }
        switch number {
        case 1:
            GuidePage(title: Text("Pásalo a la TV"),
                      message: Text("En cualquier película o serie toca «Ver en la TV»: empieza en la sala justo donde ibas. Lo que veas allá sale arriba de la barra, en «En la TV»."),
                      step: (1, 2), primary: Text("Siguiente"), secondary: Text("Saltar"), next: next, skip: { dismiss() }) {
                GuideArt(symbol: "tv", tint: DS.ListTint.series) {
                    HStack(spacing: DS.Space.s2) {
                        Label("Ver", systemImage: "play.fill").frame(maxWidth: .infinity).padding(DS.Space.s2).background(DS.fill, in: Capsule())
                        Label("Ver en la TV", systemImage: "tv").frame(maxWidth: .infinity).padding(DS.Space.s2).background(DS.fillStrong, in: Capsule())
                    }
                    .font(DS.TextRecipe.secondary.font.weight(.semibold)).foregroundStyle(DS.text)
                }
            }
        case 2:
            GuidePage(title: Text("Tu iPhone es el control"),
                      message: Text("Toca «En la TV» y luego el control: muévete por los menús, pausa y sube el volumen sin buscar el mando. También está en el Centro de control."),
                      step: (1, 2), primary: Text("Siguiente"), secondary: Text("Saltar"), next: next, skip: { dismiss() }) {
                GuideArt(symbol: "appletvremote.gen4", tint: DS.accent) { EmptyView() }
            }
        default:
            GuidePage(title: Text("Y también"), message: Text("Lo encuentras cuando lo necesites; no hay que aprenderlo ahora."),
                      step: (1, 2), primary: last ? Text("Listo") : Text("Siguiente"), next: next) {
                VStack(spacing: DS.Space.s3) {
                    GuidePiece(symbol: "waveform", tint: DS.ListTint.bookmark, title: Text("Háblale"),
                               detail: Text("«Oye Siri, pon Dune en Orbital» o «pausa la tele». Las frases, en Ajustes › Voz y Siri."))
                    GuidePiece(symbol: "tray.and.arrow.down", tint: DS.ListTint.library, title: Text("Desde la TV"),
                               detail: Text("Lo que mandes desde la sala al iPhone llega a Inicio, para verlo en la cama."))
                    GuidePiece(symbol: "gamecontroller", tint: DS.ListTint.watching, title: Text("Mientras juegas"),
                               detail: Text("Si abres un juego en la consola, el iPhone te muestra su guía, tus notas y un temporizador."))
                }
            }
        }
    }
}
