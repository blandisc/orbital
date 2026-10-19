import SwiftUI
import OrbitalCore
import OrbitalModels

/// Ajustes: tu perfil arriba (el avatar se toca) y dos grupos de renglones que llevan a su página, cada uno con cómo
/// está ahora: lo tuyo (apariencia, Inicio, idioma, reproducción, descargas) y las conexiones (Orbital, Trakt…).
struct SettingsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @StateObject private var settings: ModelObserver<SettingsModel>
    @StateObject private var session: ModelObserver<SessionModel>
    @State private var tmdbKey = ""
    @State private var newAddon = ""
    @State private var secret = ""
    @State private var confirmSignOut = false
    @State private var confirmUnlink = false
    @State private var orbitalToken = ""
    @State private var editingAvatar = false
    @State private var showsYear = false

    init() {
        let services = AppEnvironment.shared.services
        _settings = StateObject(wrappedValue: ModelObserver(SettingsModel(services)))
        _session = StateObject(wrappedValue: ModelObserver(AppEnvironment.shared.session))
    }

    var body: some View {
        let model = settings.model
        let s = model.settings
        Form {
            Section {
                ProfileCard(avatar: s.avatar, title: s.displayName.isEmpty ? Text("Tu perfil") : Text(verbatim: s.displayName), detail: connections(model)) { editingAvatar = true }
                // Tu año: lo que viste, del historial de Trakt.
                NavigationLink { YearView() } label: {
                    SettingsRow(title: "Tu año", symbol: "calendar", tint: DS.ListTint.calendar, value: Text("Lo que viste"))
                }
            }
            .listRowBackground(DS.surface)
            // Lo tuyo: cómo se ve y cómo se reproduce.
            Section {
                NavigationLink { page("Apariencia") { appearance(model) } } label: {
                    SettingsRow(title: "Apariencia", symbol: "circle.lefthalf.filled", tint: DS.ListTint.spark, value: appearanceName(s.appearance))
                }
                NavigationLink { page("Inicio y Para ti") { home(model) } } label: {
                    SettingsRow(title: "Inicio y Para ti", symbol: "house", tint: DS.ListTint.watching, value: s.homeDeck == DeckStyle.fan.rawValue ? Text("Abanico") : Text("Coverflow"))
                }
                NavigationLink { page("Idioma y subtítulos") { language(model) } } label: {
                    SettingsRow(title: "Idioma y subtítulos", symbol: "captions.bubble", tint: DS.ListTint.library, value: s.uiLanguage == "en" ? Text(verbatim: "English") : Text(verbatim: "Español"))
                }
                NavigationLink { page("Reproducción") { playback(model) } } label: {
                    SettingsRow(title: "Reproducción", symbol: "play.circle", tint: DS.ListTint.list, value: Text(verbatim: s.quality))
                }
                NavigationLink { page("Avisos") { alerts(model) } } label: {
                    SettingsRow(title: "Avisos", symbol: "bell.badge", tint: DS.ListTint.flame, value: s.releaseAlerts ? Text("Estrenos") : Text("Apagados"))
                }
                NavigationLink { page("Descargas") { downloads(model) } } label: {
                    SettingsRow(title: "Descargas", symbol: "arrow.down.circle", tint: DS.ListTint.calendar, value: s.wifiOnlyDownloads ? Text("Solo con Wi‑Fi") : Text("Siempre"))
                }
            }
            .listRowBackground(DS.surface)
            // Con qué se conecta.
            Section {
                NavigationLink { page("Tu Orbital") { orbitalSection(model) } } label: {
                    SettingsRow(title: "Tu Orbital", symbol: "tv", tint: DS.ListTint.series, value: env.services.orbital.isConfigured ? Text("Conectada") : Text("Sin conectar"))
                }
                if traktFromOrbital(model) {
                    // Trakt llega de tu Orbital: aquí no hay nada que configurar.
                    SettingsRow(title: "Trakt", symbol: "checkmark.seal", tint: DS.ListTint.chart, value: Text("Desde tu Orbital"))
                } else {
                    NavigationLink { page("Trakt") { traktSection(model) } } label: {
                        SettingsRow(title: "Trakt", symbol: "checkmark.seal", tint: DS.ListTint.chart, value: traktValue(model))
                    }
                }
                // Tus películas y series de OneDrive como una fuente más (como en la TV).
                NavigationLink { OneDriveSettings() } label: {
                    SettingsRow(title: "OneDrive", symbol: "cloud", tint: DS.ListTint.library,
                                value: env.services.oneDrive.linked ? Text("Conectado") : Text("Sin conectar"))
                }
                NavigationLink { VoiceGuideView() } label: {
                    SettingsRow(title: "Voz y Siri", symbol: "waveform", tint: DS.ListTint.bookmark)
                }
            } header: { Text("Conexiones") }
            .listRowBackground(DS.surface)
            // Lo que casi no se toca: complementos, la clave de TMDB y el país.
            Section {
                NavigationLink { page("Avanzado") { advanced(model) } } label: {
                    SettingsRow(title: "Avanzado", symbol: "slider.horizontal.3", tint: DS.ListTint.addon, value: Text("Complementos, TMDB, país"))
                }
            }
            .listRowBackground(DS.surface)
            Section {
                Label("Stremio conectado", systemImage: "person.crop.circle.badge.checkmark")
                Button("Cerrar sesión", role: .destructive) { confirmSignOut = true }
            } header: { Text("Cuenta") }
            .listRowBackground(DS.surface)
        }
        .tint(DS.accent)   // interruptores, selectores y botones del formulario: el acento (lo interactivo)
        .scrollContentBackground(.hidden).background(Backdrop())
        .navigationTitle("Ajustes").navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("¿Cerrar sesión de Stremio?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Cerrar sesión", role: .destructive) { Task { await session.model.signOut() } }
        } message: { Text("Se borra lo que tenías pendiente de subir y tus búsquedas recientes. Tus descargas se quedan en el iPhone.") }
        .confirmationDialog("¿Desconectar Trakt?", isPresented: $confirmUnlink, titleVisibility: .visible) {
            Button("Desconectar", role: .destructive) { Task { await settings.model.unlinkTrakt() } }
        } message: { Text("Dejan de salir tu watchlist, tus listas y lo que sigues; lo que veas ya no se marca en Trakt.") }
        .sheet(isPresented: $editingAvatar) {
            NavigationStack {
                Form {
                    Section("Cómo te llamamos") {
                        TextField("Tu nombre", text: Binding(get: { settings.model.settings.displayName }, set: { v in settings.model.update { $0.displayName = v } }))
                            .textInputAutocapitalization(.words).autocorrectionDisabled()
                    }
                    .listRowBackground(DS.surface)
                    Section("Tu avatar") {
                        AvatarPicker(selection: Binding(get: { settings.model.settings.avatar }, set: { v in settings.model.update { $0.avatar = v } }))
                    }
                    .listRowBackground(DS.surface)
                }
                    .scrollContentBackground(.hidden).background(Backdrop())
                    .navigationTitle("Tu perfil").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { editingAvatar = false } } }
            }
            .presentationDetents([.medium])
        }
        .task { await model.loadTraktName(); await session.model.loadAddons() }
        #if DEBUG
        .navigationDestination(isPresented: $showsYear) { YearView() }   // `-demo-open year`: para las capturas
        .task { if Demo.isOn, Demo.open == "settings-avatar" { editingAvatar = true }; if Demo.isOn, Demo.open == "year" { showsYear = true } }
        #endif
    }

    /// Una página de Ajustes: el mismo formulario y fondo.
    private func page<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        Form { content() }
            .tint(DS.accent)
            .scrollContentBackground(.hidden).background(Backdrop())
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
    }

    /// Trakt conectado con la sesión que copió tu Orbital (no se configura aquí).
    private func traktFromOrbital(_ model: SettingsModel) -> Bool {
        guard case .linked = model.trakt else { return false }
        return env.services.orbital.isConfigured
    }

    /// «Avanzado»: complementos, y el país y la clave de TMDB de las sugerencias.
    @ViewBuilder private func advanced(_ model: SettingsModel) -> some View {
        Section {
            NavigationLink { page("Complementos") { addons } } label: {
                SettingsRow(title: "Complementos", symbol: "puzzlepiece.extension", tint: DS.ListTint.addon, value: Text(verbatim: "\(session.model.addons.count)"))
            }
        }
        .listRowBackground(DS.surface)
        suggestions(model)
    }

    /// «Stremio · Trakt · Orbital»: qué está conectado, bajo tu avatar.
    private func connections(_ model: SettingsModel) -> Text {
        var parts = ["Stremio"]
        if case .linked = model.trakt { parts.append("Trakt") }
        if env.services.orbital.isConfigured { parts.append("Orbital") }
        return Text("Conectado: \(parts.joined(separator: " · "))")
    }

    private func appearanceName(_ value: String) -> Text {
        switch value { case "light": Text("Claro"); case "dark": Text("Oscuro"); default: Text("Como el iPhone") }
    }

    private func traktValue(_ model: SettingsModel) -> Text {
        switch model.trakt {
        case .linked(let name): name.isEmpty ? Text("Conectado") : Text(verbatim: name)
        case .linking: Text("Conectando…")
        default: Text("Sin conectar")
        }
    }

    // MARK: páginas
    @ViewBuilder private func appearance(_ model: SettingsModel) -> some View {
        Section("Modo") {
            Picker("Modo", selection: Binding(get: { model.settings.appearance }, set: { v in model.update { $0.appearance = v } })) {
                Text("Como el iPhone").tag("system"); Text("Claro").tag("light"); Text("Oscuro").tag("dark")
            }
            .pickerStyle(.segmented)
        }
        .listRowBackground(DS.surface)
        Section("Ícono de la app") { AppIconPicker() }.listRowBackground(DS.surface)
    }

    /// Inicio: cada estilo se elige viéndolo (el carrusel se mueve solo; cuánto falta, sobre una tarjeta).
    @ViewBuilder private func home(_ model: SettingsModel) -> some View {
        let s = model.settings
        Section {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: DS.Space.s3), GridItem(.flexible(), spacing: DS.Space.s3)], spacing: DS.Space.s3) {
                StyleOption(label: "Coverflow", selected: s.homeDeck != DeckStyle.fan.rawValue, action: { model.update { $0.homeDeck = DeckStyle.coverflow.rawValue } }) { DeckStylePreview(style: .coverflow) }
                StyleOption(label: "Abanico", selected: s.homeDeck == DeckStyle.fan.rawValue, action: { model.update { $0.homeDeck = DeckStyle.fan.rawValue } }) { DeckStylePreview(style: .fan) }
            }
            .padding(.vertical, DS.Space.s2)
            .accessibilityIdentifier("deck-options")
        } header: { Text("Carrusel") } footer: { Text("Cómo se acomodan las tarjetas de «Seguir viendo».") }
        .listRowBackground(DS.surface)
        Section {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: DS.Space.s3), GridItem(.flexible(), spacing: DS.Space.s3)], spacing: DS.Space.s3) {
                ForEach(TimeStyle.allCases, id: \.self) { style in
                    StyleOption(label: timeName(style), selected: s.homeTime == style.rawValue, action: { model.update { $0.homeTime = style.rawValue } }) { TimeStylePreview(style: style) }
                }
            }
            .padding(.vertical, DS.Space.s2)
        } header: { Text("Cuánto falta") } footer: { Text("Cómo te dice la tarjeta lo que te queda por ver.") }
        .listRowBackground(DS.surface)
        .sensoryFeedback(.selection, trigger: s.homeDeck + s.homeTime)
    }

    private func timeName(_ style: TimeStyle) -> LocalizedStringKey {
        switch style { case .pill: "Píldora de vidrio"; case .edge: "El borde avanza"; case .fill: "Botón que se llena"; case .arc: "Arco orbital" }
    }

    @ViewBuilder private func language(_ model: SettingsModel) -> some View {
        let s = model.settings
        Section {
            Picker("Idioma de la app y de las fichas", selection: Binding(get: { s.uiLanguage }, set: { v in model.update { $0.uiLanguage = v } })) {
                Text("Español").tag("es"); Text("English").tag("en")
            }
            // «Español latino» es español, prefiriendo la pista latina cuando el video trae las dos.
            Picker("Audio", selection: Binding(get: { s.audio == "es" && s.latinSpanish ? "es-419" : s.audio },
                                               set: { v in model.update { $0.audio = v == "es-419" ? "es" : v; $0.latinSpanish = v == "es-419" } })) {
                Text("Español").tag("es"); Text("Español latino").tag("es-419"); Text("English").tag("en")
            }
        }
        .listRowBackground(DS.surface)
        Section("Subtítulos") {
            Picker("Subtítulos", selection: Binding(get: { s.subtitles }, set: { v in model.update { $0.subtitles = v } })) { languageOptions; Text("Sin subtítulos").tag("") }
            Toggle("Solo subtítulos forzados", isOn: Binding(get: { s.onlyForcedSubtitles }, set: { v in model.update { $0.onlyForcedSubtitles = v } }))
            Picker("Tamaño de subtítulos", selection: Binding(get: { s.subtitleSize }, set: { v in model.update { $0.subtitleSize = v } })) {
                Text("Chico").tag("small"); Text("Mediano").tag("medium"); Text("Grande").tag("large")
            }
        }
        .listRowBackground(DS.surface)
    }

    @ViewBuilder private func playback(_ model: SettingsModel) -> some View {
        let s = model.settings
        Section("Calidad") {
            Picker("Con Wi‑Fi", selection: Binding(get: { s.quality }, set: { v in model.update { $0.quality = v } })) { qualityOptions }
            Picker("Con datos móviles", selection: Binding(get: { s.cellularQuality }, set: { v in model.update { $0.cellularQuality = v } })) { qualityOptions }
        }
        .listRowBackground(DS.surface)
        Section("Reproductor") {
            LabeledContent("Motor", value: PlayerEngines.aetherAvailable ? "AetherEngine" : "AVPlayer")
            Toggle("Abrir siempre en Infuse", isOn: Binding(get: { s.preferInfuse }, set: { v in model.update { $0.preferInfuse = v } }))
        }
        .listRowBackground(DS.surface)
    }

    @ViewBuilder private func downloads(_ model: SettingsModel) -> some View {
        let s = model.settings
        Section {
            Toggle("Descargar solo con Wi‑Fi", isOn: Binding(get: { s.wifiOnlyDownloads }, set: { v in model.update { $0.wifiOnlyDownloads = v } }))
            Toggle("Bajar el siguiente episodio al terminar uno", isOn: Binding(get: { s.autoNextDownload }, set: { v in model.update { $0.autoNextDownload = v } }))
            Toggle("Borrar al terminar de verlo", isOn: Binding(get: { s.deleteWhenWatched }, set: { v in model.update { $0.deleteWhenWatched = v } }))
        }
        .listRowBackground(DS.surface)
    }

    /// «Ya está para ver»: un aviso cuando un episodio de lo que sigues en Trakt ya tiene fuente (no a la hora en que sale).
    @ViewBuilder private func alerts(_ model: SettingsModel) -> some View {
        let s = model.settings
        Section {
            Toggle("Cuando un estreno ya está para ver", isOn: Binding(get: { s.releaseAlerts }, set: { v in
                model.update { $0.releaseAlerts = v }
                guard v else { return }
                Task {
                    if await ReleaseNotifier.requestPermission() { await ReleaseNotifier.check() }
                    else { model.update { $0.releaseAlerts = false }; env.notify("Activa los avisos de Orbital en Ajustes del iPhone.", tone: .warn) }
                }
            }))
            .tint(DS.switchOn)
            .accessibilityIdentifier("release-alerts")
        } footer: {
            Text("De las series que sigues en Trakt. Te avisa cuando ya hay fuente en Real-Debrid, con botones para verlo aquí, en la TV o bajarlo. De las 23 a las 8 el aviso espera a la mañana; varios el mismo día llegan juntos.")
        }
        .listRowBackground(DS.surface)
        .disabled(!env.services.appSettings.traktEnabled)
        if !env.services.appSettings.traktEnabled {
            Section { Text("Conecta Trakt para saber qué series sigues.").recipe(.footnote) }.listRowBackground(DS.surface)
        }
    }

    @ViewBuilder private func suggestions(_ model: SettingsModel) -> some View {
        let s = model.settings
        Section {
            Picker("País (para lo popular en plataformas)", selection: Binding(get: { s.region }, set: { v in model.update { $0.region = v } })) {
                ForEach(["MX", "US", "ES", "AR", "CO", "CL", "PE"], id: \.self) { Text(verbatim: env.uiLocale.localizedString(forRegionCode: $0) ?? $0).tag($0) }
            }
            SecureField(LocalizedStringKey(model.hasTMDBKey ? "Clave de TMDB guardada" : "Clave de TMDB"), text: $tmdbKey).textInputAutocapitalization(.never).autocorrectionDisabled()
            if !tmdbKey.isEmpty { Button("Guardar clave de TMDB") { model.setTMDBKey(tmdbKey); tmdbKey = "" } }
        } footer: { Text("TMDB pone las fichas en español y busca lo popular en Netflix, Disney+ y HBO Max.") }
        .listRowBackground(DS.surface)
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
                    Text(redact(addon.url)).font(DS.TextRecipe.caption.font).foregroundStyle(DS.textFaint)   // solo el servidor: la ruta lleva tu clave
                }
                .swipeActions { if session.model.ownAddonURLs.contains(addon.url) { Button("Quitar", role: .destructive) { Task { await session.model.removeAddon(url: addon.url) } }.tint(DS.danger) } }   // rojo, como en iOS
            }
            if let error = session.model.addonError { Text(verbatim: env.message(error)).foregroundStyle(DS.danger).font(DS.TextRecipe.footnote.font) }
            TextField("Pegar la dirección de un complemento", text: $newAddon).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
            if !newAddon.isEmpty { Button("Agregar complemento") { Task { await session.model.addAddon(newAddon); if session.model.addonError == nil { newAddon = "" } } } }
        }
        .listRowBackground(DS.surface)
    }

    // MARK: tu Orbital (la TV)
    private func imported(_ model: SettingsModel) -> String {
        model.importedFromOrbital.joined(separator: env.services.appSettings.uiLanguage == "en" ? " and " : " y ")
    }

    @ViewBuilder private func orbitalSection(_ model: SettingsModel) -> some View {
        let connected = env.services.orbital.isConfigured
        Section {
            if connected {
                Label {
                    Text("Conectada a \(env.services.orbital.base?.host ?? "")")
                } icon: { Image(systemName: "checkmark.circle.fill").foregroundStyle(DS.good) }
                Button { Task { await model.checkOrbital() } } label: {
                    HStack { Text("Probar conexión"); Spacer(); if model.checkingOrbital { ProgressView() } }
                }
                if let problem = model.orbitalCheck, !problem.isEmpty { Text(verbatim: env.message(problem)).font(DS.TextRecipe.footnote.font).foregroundStyle(DS.danger) }
                if !model.importedFromOrbital.isEmpty {
                    Label("Traje de tu Orbital: \(imported(model)). No hay que escribirlo aquí.", systemImage: "arrow.down.doc")
                        .font(DS.TextRecipe.footnote.font).foregroundStyle(DS.good)
                }
            } else {
                // Lo fácil primero: un código en la TV, la cámara del iPhone y listo.
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    Label("En la TV: Ajustes › Cuentas › iPhone", systemImage: "qrcode").font(DS.TextRecipe.secondary.font.weight(.semibold)).foregroundStyle(DS.text)
                    Text("Aparece un código. Apúntale con la cámara del iPhone y toca «Abrir en Orbital»: queda conectada, sin escribir nada.")
                        .font(DS.TextRecipe.footnote.font).foregroundStyle(DS.textMuted)
                }
                .padding(.vertical, DS.Space.s1)
            }
            DisclosureGroup(connected ? "Cambiar a mano" : "Conectar a mano") {
                TextField("Dirección (orbital.tudominio.com)", text: Binding(get: { model.settings.orbitalAddress }, set: { v in model.update { $0.orbitalAddress = v.trimmingCharacters(in: .whitespaces) } }))
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL).textContentType(.URL)
                SecureField(LocalizedStringKey(model.hasOrbitalToken ? "Token guardado" : "Token (el mismo de Alexa)"), text: $orbitalToken)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                if !orbitalToken.isEmpty { Button("Guardar token") { model.setOrbitalToken(orbitalToken); orbitalToken = ""; Task { await model.checkOrbital() } } }
            }
        } header: { Label { Text("Tu Orbital (la TV)") } icon: { OrbitalMark(size: DS.Size.markSmall) } } footer: {
            Text("Con tu Orbital conectada, «Ver en la TV» pone en la consola lo que ves aquí, donde ibas, y tu Trakt y las claves de Para ti salen de ella.")
        }
        .listRowBackground(DS.surface)
    }

    // MARK: Trakt
    @ViewBuilder private func traktSection(_ model: SettingsModel) -> some View {
        Section("Trakt") {
            switch model.trakt {
            case .off:
                Text("Conecta tu Orbital (arriba) y Trakt se configura solo. Si no, crea una aplicación en developer.trakt.tv y pega aquí su Client ID.").font(DS.TextRecipe.footnote.font).foregroundStyle(DS.textMuted)
                TextField("Client ID de tu aplicación de Trakt", text: Binding(get: { model.settings.traktClientID }, set: { v in model.update { $0.traktClientID = v.trimmingCharacters(in: .whitespaces) } }))
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                DisclosureGroup("Aplicación anterior (con secreto)") {
                    SecureField("Client Secret", text: $secret).textInputAutocapitalization(.never)
                    if !secret.isEmpty { Button("Guardar secreto") { model.setTraktSecret(secret); secret = "" } }
                }
            case .unlinked:
                Button("Conectar Trakt") { Task { await model.linkTrakt() } }
                Text("Aparece un código para escribir en trakt.tv/activate. Con Trakt conectado se avisa de lo que ves y salen tu watchlist y tus listas.").font(DS.TextRecipe.caption.font).foregroundStyle(DS.textFaint)
            case .linking(let code, let url):
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    Text("Escribe este código en \(url):").font(DS.TextRecipe.footnote.font).foregroundStyle(DS.textMuted)
                    Text(code).font(DS.TextRecipe.display.font.weight(.bold)).foregroundStyle(DS.text).textSelection(.enabled).monospaced()
                    HStack { ProgressView(); Text("Esperando…").font(DS.TextRecipe.footnote.font).foregroundStyle(DS.textMuted) }
                }
                Button("Cancelar", role: .cancel) { model.cancelLinking() }
            case .linked(let name):
                (name.isEmpty ? Label("Trakt conectado", systemImage: "checkmark.seal") : Label("Trakt: \(name)", systemImage: "checkmark.seal"))
                if env.services.trakt?.borrowed == true {
                    Text("Con la sesión de tu Orbital: no hay nada que conectar aquí.").font(DS.TextRecipe.caption.font).foregroundStyle(DS.textFaint)
                    Button("Dejar de usar Trakt en el iPhone", role: .destructive) { confirmUnlink = true }
                } else {
                    Button("Desconectar Trakt", role: .destructive) { confirmUnlink = true }
                }
                scrobbleRow(model)
            case .failed(let message):
                DSNotice(verbatim: env.message(message), tone: .error)
                Button("Volver a intentar") { Task { await model.linkTrakt() } }
            }
        }
        .listRowBackground(DS.surface)
        .onAppear { model.refreshScrobble() }
    }

    /// «Último scrobble»: lo último que se le contó a Trakt (o por qué no se pudo), para comprobarlo en trakt.tv › Historial.
    @ViewBuilder
    private func scrobbleRow(_ model: SettingsModel) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            Text("Último scrobble").font(DS.TextRecipe.footnote.font).foregroundStyle(DS.textMuted)
            if let last = model.scrobble.last {
                Text(verbatim: last.title).font(DS.TextRecipe.footnote.font).foregroundStyle(DS.text)
                HStack(spacing: DS.Space.s1) {
                    Text(Self.actionLabel(last.action))
                    Text(verbatim: "·")
                    Text(verbatim: Self.ago(last.at, language: model.settings.uiLanguage, now: env.services.now()))
                }
                .font(DS.TextRecipe.caption.font).foregroundStyle(DS.textFaint)
            } else {
                Text("Todavía nada: aparece cuando veas algo en el iPhone.").font(DS.TextRecipe.caption.font).foregroundStyle(DS.textFaint)
            }
            if let error = model.scrobble.error { DSNotice(verbatim: env.message(error), tone: .warn) }
        }
    }

    private static func actionLabel(_ action: ScrobbleAction) -> LocalizedStringKey {
        switch action { case .start: "Viendo"; case .pause: "En pausa"; case .stop: "Cerrado" }
    }

    /// «hace 3 min» / «3 min ago», en el idioma de la app.
    private static func ago(_ date: Date, language: String, now: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: language)
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
