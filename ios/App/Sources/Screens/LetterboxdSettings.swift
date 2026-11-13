import SwiftUI
import UniformTypeIdentifiers
import OrbitalCore
import OrbitalModels

/// Ajustes › Cuentas › Letterboxd: tu usuario (tu diario público: sin contraseña y sin cambiar nada en tu cuenta) y, una
/// vez, tu archivo de exportación para traer todo lo de antes. Orbital solo lee de Letterboxd.
struct LetterboxdSettings: View {
    @Environment(AppEnvironment.self) private var env
    @State private var typed = ""
    @State private var problem: String?
    @State private var importing = false
    @State private var confirmDisconnect = false

    var body: some View {
        let model = env.letterboxd
        let _ = model.track()
        Form {
            Section {
                if let user = model.user {
                    LabeledContent {
                        Text("\(model.entries.count) películas").foregroundStyle(DS.textMuted)
                    } label: {
                        HStack(spacing: DS.Space.s2) { LetterboxdMark(); Text(verbatim: "@\(user)").foregroundStyle(DS.text) }
                    }
                    if let url = URL(string: "\(Letterboxd.site)/\(user)/") { Link(destination: url) { Label("Ver tu perfil", systemImage: "arrow.up.right") } }
                } else {
                    TextField("Tu usuario", text: $typed)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.go)
                        .onSubmit { connect(model) }
                        .accessibilityIdentifier("letterboxd-user")
                    Button { connect(model) } label: {
                        if model.loading { ProgressView() } else { Text("Conectar") }   // ds-exception: la ruedita en el lugar del botón mientras revisa
                    }
                    .disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty || model.loading)
                    .accessibilityIdentifier("letterboxd-connect")
                }
                if let problem { Text(verbatim: problem).recipe(.footnote, color: DS.danger) }
            } header: { Text("Tu usuario") } footer: {
                Text("Solo tu usuario: Letterboxd publica tu diario. No pide contraseña y no cambia nada en tu cuenta.")
            }
            Section {
                Button { importing = true } label: {
                    SettingsRow(title: "Traer todo tu historial", symbol: "square.and.arrow.down", tint: DS.Letterboxd.sky,
                                value: model.importedAt.map { Text(verbatim: Strings.date($0, .dayMonthShort, language: env.services.appSettings.uiLanguage)) })
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("letterboxd-import")
                if let url = URL(string: "\(Letterboxd.site)/settings/data/") { Link(destination: url) { Label("Bajar tu archivo de Letterboxd", systemImage: "arrow.up.right") } }
            } header: { Text("Tu archivo, una vez") } footer: {
                Text("En Letterboxd › Ajustes › Datos › Exportar. Trae tu diario completo, tus calificaciones, tus reseñas y tus listas (también las privadas).")
            }
            if model.connected {
                Section {
                    Button("Desconectar Letterboxd", role: .destructive) { confirmDisconnect = true }
                } footer: { Text("Se borra de este iPhone lo que se trajo de Letterboxd. Tu cuenta de Letterboxd no cambia.") }
            }
        }
        .tint(DS.accent)
        .scrollContentBackground(.hidden).background(Backdrop())
        .navigationTitle(Text(verbatim: "Letterboxd")).navigationBarTitleDisplayMode(.inline)
        .readableListWidth()
        .fileImporter(isPresented: $importing, allowedContentTypes: [.zip, .commaSeparatedText], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            let files: [(name: String, data: Data)] = urls.compactMap { url in
                let open = url.startAccessingSecurityScopedResource()
                defer { if open { url.stopAccessingSecurityScopedResource() } }
                return (try? Data(contentsOf: url)).map { (url.lastPathComponent, $0) }
            }
            Task {
                if let why = await model.importArchive(files) { problem = why }
                else { problem = nil; env.notify("Tu historial de Letterboxd ya está en Orbital", detail: "\(model.entries.count) películas", tone: .success) }
            }
        }
        .confirmationDialog("¿Desconectar Letterboxd?", isPresented: $confirmDisconnect, titleVisibility: .visible) {   // ds-exception: confirmación de desconectar (sí o no)
            Button("Desconectar", role: .destructive) { model.disconnect(); typed = "" }
        }
    }

    private func connect(_ model: LetterboxdModel) {
        let user = typed
        Task {
            problem = await model.connect(user)
            if problem == nil { env.notify("Letterboxd conectado", detail: "\(model.entries.count) películas de tu diario", tone: .success) }
        }
    }
}
