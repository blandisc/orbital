import SwiftUI
import OrbitalCore
import OrbitalModels

/// Ajustes: cuenta de Stremio, complementos, Trakt, idiomas, calidad, descargas y reproductor.
struct SettingsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @StateObject private var settings: ModelObserver<SettingsModel>
    @StateObject private var session: ModelObserver<SessionModel>
    @State private var tmdbKey = ""
    @State private var newAddon = ""
    @State private var secret = ""
    @State private var confirmSignOut = false
    @State private var orbitalToken = ""

    init() {
        let services = AppEnvironment.shared.services
        _settings = StateObject(wrappedValue: ModelObserver(SettingsModel(services)))
        _session = StateObject(wrappedValue: ModelObserver(AppEnvironment.shared.session))
    }

    var body: some View {
        let model = settings.model
        let s = model.settings
        Form {
            Section("Cuenta") {
                Label("Stremio conectado", systemImage: "person.crop.circle.badge.checkmark")
                Button("Cerrar sesión", role: .destructive) { confirmSignOut = true }
            }
            .listRowBackground(DS.fill)
            addons
            traktSection(model)
            Section("Idioma") {
                Picker("Idioma de la app y de las fichas", selection: Binding(get: { s.uiLanguage }, set: { v in model.update { $0.uiLanguage = v } })) {
                    Text("Español").tag("es"); Text("English").tag("en")
                }
                Picker("Audio", selection: Binding(get: { s.audio }, set: { v in model.update { $0.audio = v } })) { languageOptions }
                Picker("Subtítulos", selection: Binding(get: { s.subtitles }, set: { v in model.update { $0.subtitles = v } })) { languageOptions; Text("Sin subtítulos").tag("") }
                Toggle("Solo subtítulos forzados", isOn: Binding(get: { s.onlyForcedSubtitles }, set: { v in model.update { $0.onlyForcedSubtitles = v } }))
                Picker("Tamaño de subtítulos", selection: Binding(get: { s.subtitleSize }, set: { v in model.update { $0.subtitleSize = v } })) {
                    Text("Chico").tag("small"); Text("Mediano").tag("medium"); Text("Grande").tag("large")
                }
            }
            .listRowBackground(DS.fill)
            Section("Calidad") {
                Picker("Con Wi‑Fi", selection: Binding(get: { s.quality }, set: { v in model.update { $0.quality = v } })) { qualityOptions }
                Picker("Con datos móviles", selection: Binding(get: { s.cellularQuality }, set: { v in model.update { $0.cellularQuality = v } })) { qualityOptions }
            }
            .listRowBackground(DS.fill)
            Section("Descargas") {
                Toggle("Descargar solo con Wi‑Fi", isOn: Binding(get: { s.wifiOnlyDownloads }, set: { v in model.update { $0.wifiOnlyDownloads = v } }))
                Toggle("Bajar el siguiente episodio al terminar uno", isOn: Binding(get: { s.autoNextDownload }, set: { v in model.update { $0.autoNextDownload = v } }))
                Toggle("Borrar al terminar de verlo", isOn: Binding(get: { s.deleteWhenWatched }, set: { v in model.update { $0.deleteWhenWatched = v } }))
            }
            .listRowBackground(DS.fill)
            Section("Reproductor") {
                LabeledContent("Motor", value: PlayerEngines.aetherAvailable ? "AetherEngine" : "AVPlayer")
                Toggle("Abrir siempre en Infuse", isOn: Binding(get: { s.preferInfuse }, set: { v in model.update { $0.preferInfuse = v } }))
            }
            .listRowBackground(DS.fill)
            orbitalSection(model)
            Section("Sugerencias") {
                Picker("País (para lo popular en plataformas)", selection: Binding(get: { s.region }, set: { v in model.update { $0.region = v } })) {
                    ForEach(["MX", "US", "ES", "AR", "CO", "CL", "PE"], id: \.self) { Text(verbatim: env.uiLocale.localizedString(forRegionCode: $0) ?? $0).tag($0) }
                }
                SecureField(LocalizedStringKey(model.hasTMDBKey ? "Clave de TMDB guardada" : "Clave de TMDB"), text: $tmdbKey).textInputAutocapitalization(.never).autocorrectionDisabled()
                if !tmdbKey.isEmpty { Button("Guardar clave de TMDB") { model.setTMDBKey(tmdbKey); tmdbKey = "" } }
                Text("TMDB pone las fichas en español y busca lo popular en Netflix, Disney+ y HBO Max.").font(DS.font(.xs)).foregroundStyle(DS.textFaint)
            }
            .listRowBackground(DS.fill)
        }
        .scrollContentBackground(.hidden).background(TintedBackground())
        .navigationTitle("Ajustes").navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("¿Cerrar sesión de Stremio?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Cerrar sesión", role: .destructive) { Task { await session.model.signOut() } }
        }
        .task { await model.loadTraktName(); await session.model.loadAddons() }
    }

    @ViewBuilder private var languageOptions: some View {
        Text("Español").tag("es"); Text("English").tag("en")
    }

    @ViewBuilder private var qualityOptions: some View {
        Text("4K").tag("4K"); Text("1080p").tag("1080p"); Text("720p").tag("720p")
    }

    // MARK: complementos
    private var addons: some View {
        Section("Complementos") {
            ForEach(session.model.addons, id: \.url) { addon in
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    Text(addon.name).foregroundStyle(DS.text)
                    Text(redact(addon.url)).font(DS.font(.xs)).foregroundStyle(DS.textFaint)   // solo el servidor: la ruta lleva tu clave
                }
                .swipeActions { if session.model.ownAddonURLs.contains(addon.url) { Button("Quitar", role: .destructive) { Task { await session.model.removeAddon(url: addon.url) } } } }
            }
            if let error = session.model.addonError { Text(LocalizedStringKey(error)).foregroundStyle(DS.danger).font(DS.font(.sm)) }
            TextField("Pegar la dirección de un complemento", text: $newAddon).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
            if !newAddon.isEmpty { Button("Agregar complemento") { Task { await session.model.addAddon(newAddon); if session.model.addonError == nil { newAddon = "" } } } }
        }
        .listRowBackground(DS.fill)
    }

    // MARK: tu Orbital (la TV)
    private func imported(_ model: SettingsModel) -> String {
        model.importedFromOrbital.joined(separator: env.services.appSettings.uiLanguage == "en" ? " and " : " y ")
    }

    @ViewBuilder private func orbitalSection(_ model: SettingsModel) -> some View {
        Section {
            TextField("Dirección (orbital.tudominio.com)", text: Binding(get: { model.settings.orbitalAddress }, set: { v in model.update { $0.orbitalAddress = v.trimmingCharacters(in: .whitespaces) } }))
                .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL).textContentType(.URL)
            SecureField(LocalizedStringKey(model.hasOrbitalToken ? "Token guardado" : "Token (el mismo de Alexa)"), text: $orbitalToken)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            if !orbitalToken.isEmpty { Button("Guardar token") { model.setOrbitalToken(orbitalToken); orbitalToken = ""; Task { await model.checkOrbital() } } }
            if !model.settings.orbitalAddress.isEmpty && model.hasOrbitalToken {
                Button { Task { await model.checkOrbital() } } label: {
                    HStack {
                        Text("Probar conexión")
                        Spacer()
                        if model.checkingOrbital { ProgressView() }
                        else if model.orbitalCheck == "" { Label("Conectada", systemImage: "checkmark.circle.fill").foregroundStyle(DS.good) }
                    }
                }
                if let problem = model.orbitalCheck, !problem.isEmpty { Text(LocalizedStringKey(problem)).font(DS.font(.sm)).foregroundStyle(DS.danger) }
                if !model.importedFromOrbital.isEmpty {
                    Label("Traje de tu Orbital: \(imported(model)). No hay que escribirlo aquí.", systemImage: "arrow.down.doc")
                        .font(DS.font(.sm)).foregroundStyle(DS.good)
                }
            }
        } header: { Text("Tu Orbital (la TV)") } footer: {
            Text("Con tu Orbital conectada, «Ver en la TV» pone en la consola lo que ves aquí, donde ibas, y las claves de TMDB y Trakt se toman de ella. Usa la dirección del túnel de Alexa y su token.")
        }
        .listRowBackground(DS.fill)
    }

    // MARK: Trakt
    @ViewBuilder private func traktSection(_ model: SettingsModel) -> some View {
        Section("Trakt") {
            switch model.trakt {
            case .off:
                Text("Crea una aplicación en developer.trakt.tv y pega aquí su Client ID (las nuevas ya no dan secreto).").font(DS.font(.sm)).foregroundStyle(DS.textMuted)
                TextField("Client ID de tu aplicación de Trakt", text: Binding(get: { model.settings.traktClientID }, set: { v in model.update { $0.traktClientID = v.trimmingCharacters(in: .whitespaces) } }))
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                DisclosureGroup("Aplicación anterior (con secreto)") {
                    SecureField("Client Secret", text: $secret).textInputAutocapitalization(.never)
                    if !secret.isEmpty { Button("Guardar secreto") { model.setTraktSecret(secret); secret = "" } }
                }
                .font(DS.font(.sm)).foregroundStyle(DS.textMuted)
            case .unlinked:
                Button("Conectar Trakt") { Task { await model.linkTrakt() } }
                Text("Aparece un código para escribir en trakt.tv/activate. Con Trakt conectado se avisa de lo que ves y salen tu watchlist y tus listas.").font(DS.font(.xs)).foregroundStyle(DS.textFaint)
            case .linking(let code, let url):
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    Text("Escribe este código en \(url):").font(DS.font(.sm)).foregroundStyle(DS.textMuted)
                    Text(code).font(DS.font(.display, weight: .bold)).foregroundStyle(DS.text).textSelection(.enabled).monospaced()
                    HStack { ProgressView(); Text("Esperando…").font(DS.font(.sm)).foregroundStyle(DS.textMuted) }
                }
                Button("Cancelar", role: .cancel) { model.cancelLinking() }
            case .linked(let name):
                (name.isEmpty ? Label("Trakt conectado", systemImage: "checkmark.seal") : Label("Trakt: \(name)", systemImage: "checkmark.seal"))
                Button("Desconectar Trakt", role: .destructive) { Task { await model.unlinkTrakt() } }
            case .failed(let message):
                DSNotice(text: LocalizedStringKey(message), tone: .error)
                Button("Volver a intentar") { Task { await model.linkTrakt() } }
            }
        }
        .listRowBackground(DS.fill)
    }
}
