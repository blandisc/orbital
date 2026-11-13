import SwiftUI
import OrbitalCore
import OrbitalModels

/// Ajustes › Cuentas › OpenSubtitles: tu cuenta gratuita para tener muchos más subtítulos (y los de tu copia exacta).
/// La contraseña solo viaja al conectar; en el iPhone queda tu usuario y un token, en el llavero.
struct OpenSubtitlesSettings: View {
    @Environment(AppEnvironment.self) private var env
    @State private var confirmDisconnect = false

    var body: some View {
        let model = env.openSubtitles
        let _ = model.track()
        Form {
            Section {
                if let account = model.account {
                    OpenSubtitlesConnected(account: account)
                } else {
                    OpenSubtitlesForm(model: model) { env.notify("OpenSubtitles conectado", detail: "Ya salen muchos más subtítulos", tone: .success) }
                }
            } header: { Text("Tu cuenta") } footer: {
                Text("Más subtítulos y de tu copia exacta. La cuenta es gratis y da unos 20 subtítulos al día.")
            }
            if model.connected, model.hasTV {
                Section {
                    Button("Pasar a tu TV", systemImage: "tv") {
                        Task {
                            if let why = await model.sendToTV() { env.notify(why, tone: .warn) }
                            else { env.notify("Tu TV ya tiene tu cuenta de OpenSubtitles", tone: .success) }
                        }
                    }
                    .accessibilityIdentifier("opensubtitles-to-tv")
                } footer: { Text("Tu TV usa la misma cuenta, sin escribir la contraseña con el control.") }
            }
            if model.connected {
                Section {
                    Button("Desconectar OpenSubtitles", role: .destructive) { confirmDisconnect = true }
                } footer: {
                    if env.services.capabilities.instantStreams { Text("Sin tu cuenta, los subtítulos vuelven a salir del complemento de siempre (menos opciones).") }   // edición: solo con instantStreams
                    else { Text("Sin tu cuenta, los subtítulos vuelven a salir de los de siempre (menos opciones).") }
                }
            }
        }
        .tint(DS.accent)
        .scrollContentBackground(.hidden).background(Backdrop())
        .navigationTitle(Text(verbatim: "OpenSubtitles")).navigationBarTitleDisplayMode(.inline)
        .readableListWidth()
        .task { await model.refresh() }
        .confirmationDialog("¿Desconectar OpenSubtitles?", isPresented: $confirmDisconnect, titleVisibility: .visible) {   // ds-exception: confirmación de desconectar (sí o no)
            Button("Desconectar", role: .destructive) { model.disconnect() }
        }
    }
}

/// Conectado: tu usuario y lo que te queda hoy.
struct OpenSubtitlesConnected: View {
    let account: OpenSubtitlesAccount
    var body: some View {
        LabeledContent {
            if let left = account.remaining { Text("\(left) hoy").foregroundStyle(left > 0 ? DS.textMuted : DS.warning) }
        } label: {
            Label { Text(verbatim: account.username).foregroundStyle(DS.text) } icon: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(DS.success)
            }
        }
        .accessibilityIdentifier("opensubtitles-connected")
    }
}

/// Usuario, contraseña y «Conectar» (Ajustes y la bienvenida usan el mismo).
struct OpenSubtitlesForm: View {
    let model: OpenSubtitlesModel
    var connected: () -> Void = {}
    @State private var user = ""
    @State private var password = ""

    var body: some View {
        let _ = model.track()
        TextField("Tu usuario", text: $user)
            .textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
            .accessibilityIdentifier("opensubtitles-user")
        SecureField("Tu contraseña", text: $password)
            .textContentType(.password).submitLabel(.go).onSubmit(connect)
            .accessibilityIdentifier("opensubtitles-password")
        Button(action: connect) {
            if model.loading { ProgressView() } else { Text("Conectar") }   // ds-exception: la ruedita en el lugar del botón mientras revisa
        }
        .disabled(user.trimmingCharacters(in: .whitespaces).isEmpty || password.isEmpty || model.loading)
        .accessibilityIdentifier("opensubtitles-connect")
        if let error = model.error { Text(verbatim: error).recipe(.footnote, color: DS.danger) }
        Link(destination: OpenSubtitlesAPI.signUp) { Label("Crear una cuenta gratis", systemImage: "arrow.up.right") }
    }

    private func connect() {
        let (u, p) = (user, password)
        Task {
            if await model.connect(username: u, password: p) == nil { password = ""; connected() }
        }
    }
}
