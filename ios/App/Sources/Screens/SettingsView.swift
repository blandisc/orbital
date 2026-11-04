import SwiftUI
import OrbitalCore
import OrbitalModels

/// Ajustes: tu perfil arriba (el avatar se toca) y dos grupos de renglones que llevan a su página, cada uno con cómo
/// está ahora: lo tuyo (apariencia, Un Simpson al azar, idioma, reproducción, descargas) y las conexiones (Orbital, Trakt…).
struct SettingsView: View {
    @Environment(AppEnvironment.self) var env
    @State var settings: ModelObserver<SettingsModel>
    @State var session: ModelObserver<SessionModel>
    /// Tu Real-Debrid (Ajustes › Cuentas).
    @State var debrid: ModelObserver<DebridModel>
    @State private var tmdbKey = ""
    @AppStorage("scare-marks") private var scareMarks = true
    @State private var confirmUnlink = false
    @State private var editingAvatar = false
    @State private var showsYear = false
    @State private var showsTrakt = false
    @State private var showsFollowed = false
    @State private var showsPlayback = false
    @State private var showsOrbital = false
    @State private var showsDemoPage = false
    /// Ajustes › Tus idiomas abierta desde otro lado (`AppUI.openLanguages`: la guía, la página de Torrentio).
    @State var showsLanguages = false
    /// «Usar con tu Orbital»: la hoja de conectar (y luego el tutorial), o solo el tutorial ya conectada.
    @State var orbitalSetup: OrbitalSetupStart?
    @State private var confirmOrbitalOff = false

    init() {
        let services = AppEnvironment.shared.services
        _settings = State(wrappedValue: ModelObserver(SettingsModel(services)))
        _session = State(wrappedValue: ModelObserver(AppEnvironment.shared.session))
        _debrid = State(wrappedValue: ModelObserver(DebridModel(services)))
    }

    var body: some View {
        let model = settings.model
        let s = model.settings
        Form {
            // CX4-A, IOS-10: la invitación de tu iPhone, lo primero de Ajustes (solo en un iPad sin conectar; nunca en la Mac).
            if env.services.allowsOrbital { IPadInviteCard { orbitalSetup = .connect } }
            Section {
                ProfileCard(avatar: s.avatar, title: s.displayName.isEmpty ? Text("Tu perfil") : Text(verbatim: s.displayName), detail: connections(model)) { editingAvatar = true }
                // «Lo que ves» ya no está aquí: vive en Explorar (Fernando, 2 nov 2026: «ya tenemos otro acceso en Explorar»).
            }
            .listRowBackground(DS.surface)
            // Idiomas y subtítulos, arriba y juntos (N4-A, Fernando, 4 nov: «que sea fácil configurar los subtítulos y los
            // idiomas»; los mismos cuatro que la TV en Ajustes › Ver).
            languagesSection(model)
            // Lo tuyo: cómo se ve y cómo se reproduce.
            Section {
                NavigationLink { page("Apariencia") { appearance(model) } } label: {
                    SettingsRow(title: "Apariencia", symbol: "circle.lefthalf.filled", tint: DS.ListTint.spark, value: appearanceName(s.appearance))
                }
                NavigationLink { page("Un Simpson al azar") { SimpsonsSeasonsSection { seasons in model.update { $0.simpsonsSeasons = seasons } } } } label: {
                    SettingsRow(title: "Un Simpson al azar", symbol: "dice", tint: DS.ListTint.watching, value: SimpsonsSeasonsSection.summary(s.simpsonsSeasons))
                }
                NavigationLink { page("Idioma de la app") { appLanguage(model) } } label: {
                    SettingsRow(title: "Idioma de la app", symbol: "character.bubble", tint: DS.ListTint.library, value: s.uiLanguage == "en" ? Text(verbatim: "English") : Text(verbatim: "Español"))
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
                // Real-Debrid, Trakt · principal, Stremio · respaldo y tu Orbital, cada una con su papel.
                NavigationLink { page("Cuentas") { accounts(model) } } label: {
                    SettingsRow(title: "Cuentas", symbol: "person.2.circle", tint: DS.ListTint.chart, value: debridValue)
                }
                NavigationLink { AddonsSettings() } label: {
                    SettingsRow(title: "Complementos", symbol: "puzzlepiece.extension", tint: DS.ListTint.addon,
                                value: addonsValue)
                }
                // Tus películas y series de OneDrive como una fuente más (como en la TV).
                NavigationLink { OneDriveSettings() } label: {
                    SettingsRow(title: "OneDrive", symbol: "folder", tint: DS.ListTint.library,
                                value: env.services.oneDrive.linked ? Text("Conectado") : Text("Sin conectar"))
                }
            } header: { Text("Conexiones") }
            .listRowBackground(DS.surface)
            // La app es de una sola pieza: lo de la consola sale solo con esto prendido (en la Mac no hay consola).
            if env.services.allowsOrbital { orbitalSettings(model) }
            // Lo que casi no se toca: complementos, la clave de TMDB y el país.
            Section {
                NavigationLink { page("Avanzado") { suggestions(model) } } label: {
                    SettingsRow(title: "Avanzado", symbol: "slider.horizontal.3", tint: DS.ListTint.addon, value: Text("TMDB, país"))
                }
                // Las historias, la guía otra vez y los avisos desde cero (G3).
                NavigationLink { LearnView() } label: {
                    SettingsRow(title: "Aprende Orbital", symbol: "sparkles", tint: DS.ListTint.spark)
                }
                .accessibilityIdentifier("settings-learn")
                // Vivir otra vez la guía de bienvenida (Fernando, 4 nov: «que el onboarding sea accesible a través de ajustes»).
                Button { env.ui.showingGuide = true } label: {
                    SettingsRow(title: "Ver la guía de bienvenida", symbol: "play.circle", tint: DS.ListTint.spark, linked: false)
                }
                .accessibilityIdentifier("settings-welcome")
            }
            .listRowBackground(DS.surface)
        }
        .tint(DS.accent)   // interruptores, selectores y botones del formulario: el acento (lo interactivo)
        .scrollContentBackground(.hidden).background(Backdrop())
        // Sin el hueco grande de arriba del primer grupo y con aire abajo: el último grupo no queda bajo la barra flotante.
        .contentMargins(.top, DS.Space.s2, for: .scrollContent)
        .contentMargins(.bottom, DS.Space.s10, for: .scrollContent)
        .navigationTitle("Ajustes").navigationBarTitleDisplayMode(.inline)
        .readableListWidth()   // iPad y Mac: los renglones al centro
        .sheet(item: $orbitalSetup) { start in OrbitalSetupView(tutorialOnly: start == .tutorial) }
        .confirmationDialog("¿Dejar de usar tu Orbital?", isPresented: $confirmOrbitalOff, titleVisibility: .visible) {
            Button("Apagar", role: .destructive) { env.services.turnOffOrbital(); ReleaseNotifier.registerCategory(language: s.uiLanguage, tv: false) }
        } message: { Text("Se esconden «Ver en la TV», el control y la voz. Lo que viste se queda: viaja por Trakt.") }
        .confirmationDialog("¿Desconectar Trakt?", isPresented: $confirmUnlink, titleVisibility: .visible) {
            Button("Desconectar", role: .destructive) { Task { await settings.model.unlinkTrakt() } }
        } message: { Text("Dejan de salir Mi lista, tus listas y lo que sigues; lo que veas ya no se marca en Trakt.") }
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
                .readableListWidth()   // iPad y Mac: al centro, no estirada a todo lo ancho
                    .scrollContentBackground(.hidden).background(Backdrop())
                    .navigationTitle("Tu perfil").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { editingAvatar = false } } }
            }
            .presentationDetents([.medium])
        }
        .task { await model.loadTraktName(); await debrid.model.load() }
        .navigationDestination(isPresented: $showsLanguages) { YourLanguagesView(settings: settings) }
        .onChange(of: env.ui.openLanguages, initial: true) { _, open in
            guard open else { return }
            env.ui.openLanguages = false
            showsLanguages = true
        }
        #if DEBUG
        .navigationDestination(isPresented: $showsYear) { YearView() }   // `-demo-open year`: para las capturas
        .task { if Demo.isOn, Demo.open == "settings-avatar" { editingAvatar = true }; if Demo.isOn, Demo.open == "year" { showsYear = true } }
        .navigationDestination(isPresented: $showsTrakt) { page("Trakt") { traktSection(model) } }   // `-demo-settings-page trakt`: capturas
        .task { if Demo.isOn, Demo.value(after: "-demo-settings-page") == "trakt" { showsTrakt = true } }
        .navigationDestination(isPresented: $showsFollowed) { FollowedSeriesView() }   // `-demo-settings-page series`: capturas
        .task { if Demo.isOn, Demo.value(after: "-demo-settings-page") == "series" { showsFollowed = true } }
        // `-demo-settings-page requests`: Tus pedidos (D3), que viven en Descargas › Real-Debrid · bajando para ti (RX1-A).
        .task { if Demo.isOn, Demo.value(after: "-demo-settings-page") == "requests" { env.openTab = AppEnvironment.downloadsTab } }
        .navigationDestination(isPresented: $showsPlayback) { page("Reproducción") { playback(model) } }   // `-demo-settings-page playback`
        .task { if Demo.isOn, Demo.value(after: "-demo-settings-page") == "playback" { showsPlayback = true } }
        .task { if Demo.isOn, Demo.value(after: "-demo-settings-page") == "languages" { showsLanguages = true } }   // N4-A
        .navigationDestination(isPresented: $showsOrbital) { page("Tu Orbital") { orbitalSection(model) } }   // `-demo-settings-page orbital` (K1)
        .task { if Demo.isOn, Demo.value(after: "-demo-settings-page") == "orbital" { showsOrbital = true } }
        // `-demo-settings-page torrentio|addons|realdebrid`: Complementos, Torrentio y tu cuenta de Real-Debrid (Fase 3).
        .navigationDestination(isPresented: $showsDemoPage) { DemoSettingsPage(name: Demo.value(after: "-demo-settings-page") ?? "", debrid: debrid.model) }
        .task { if Demo.isOn, ["torrentio", "addons", "realdebrid"].contains(Demo.value(after: "-demo-settings-page") ?? "") { showsDemoPage = true } }
        #endif
    }

    /// Ajustes › Orbital en la TV (maquetas 1 y 8): el interruptor y, prendido, tu Orbital, la voz y el tutorial otra vez.
    @ViewBuilder private func orbitalSettings(_ model: SettingsModel) -> some View {
        let on = model.settings.orbitalEnabled
        Section {
            Toggle(isOn: Binding(get: { on || orbitalSetup == .connect }, set: { want in
                if want { orbitalSetup = .connect } else { confirmOrbitalOff = true }
            })) {
                Label { Text("Usar con tu Orbital").foregroundStyle(DS.text) } icon: {
                    OrbitalMark(size: DS.Size.markSmall).frame(width: DS.SettingsLook.rowIcon)
                }
            }
            .accessibilityIdentifier("settings-orbital")
            if on {
                NavigationLink { page("Tu Orbital") { orbitalSection(model) } } label: {
                    SettingsRow(title: "Tu Orbital", symbol: "tv", tint: env.services.orbitalNeedsRescan || env.services.tvLinkNow == .silent ? DS.warning : DS.ListTint.series,
                                value: orbitalValue)
                }
                .task { await env.services.checkTV() }   // IOS-2: «Conectada» solo si la TV contestó
                NavigationLink { VoiceGuideView() } label: {   // la voz le da órdenes a tu Orbital
                    SettingsRow(title: "Voz y Siri", symbol: "waveform", tint: DS.ListTint.bookmark)
                }
                Button { orbitalSetup = .tutorial } label: {
                    SettingsRow(title: "Qué puedes hacer con la TV", symbol: "sparkles", tint: DS.ListTint.spark, linked: false)
                }
            }
        } header: { Text("Orbital en la TV") } footer: {
            on ? Text("Apágalo cuando quieras: la app vuelve a ser solo del iPhone. Lo que viste sigue en Trakt.")
               : Text("¿Tienes la consola Orbital en tu TV? Prende esto para mandarle lo que ves, usar el iPhone de control y hablarle.")
        }
        .listRowBackground(DS.surface)
        .onChange(of: on) { _, now in ReleaseNotifier.registerCategory(language: model.settings.uiLanguage, tv: now) }
    }

    /// Una página de Ajustes: el mismo formulario y fondo.
    func page<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        Form { content() }
            .tint(DS.accent)
            .scrollContentBackground(.hidden).background(Backdrop())
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .readableListWidth()
    }

    /// «Trakt · Real-Debrid · Orbital»: solo lo que conectaste, bajo tu avatar (Stremio, el respaldo, solo en Cuentas).
    private func connections(_ model: SettingsModel) -> Text {
        var parts: [String] = []
        if case .linked = model.trakt { parts.append("Trakt") }
        if debrid.model.hasToken { parts.append("Real-Debrid") }
        if env.services.orbital.isConfigured { parts.append("Orbital") }
        if parts.isEmpty { return Text("Sin cuentas conectadas") }
        return Text("Conectado: \(parts.joined(separator: " · "))")
    }

    /// IOS-17: un estado, no un verbo: «3 prendidos» o «Sin configurar».
    private var addonsValue: Text {
        let list = env.services.addonList
        guard list.isConfigured else { return Text("Sin configurar") }
        let on = list.installed.filter(\.enabled).count
        return on == 1 ? Text("1 prendido") : Text("\(String(on)) prendidos")
    }

    private func appearanceName(_ value: String) -> Text {
        switch value { case "light": Text("Claro"); case "dark": Text("Oscuro"); default: Text("Como el iPhone") }
    }

    func traktValue(_ model: SettingsModel) -> Text {
        switch model.trakt {
        case .linked(let name): name.isEmpty ? Text("Conectado") : Text(verbatim: name)
        case .linking: Text("Conectando…")
        default: Text("Sin conectar")
        }
    }

    // MARK: páginas
    @ViewBuilder private func appearance(_ model: SettingsModel) -> some View {
        Section("Modo") {
            DSSegmented(options: [("system", "Como el iPhone"), ("light", "Claro"), ("dark", "Oscuro")],
                        selection: Binding(get: { model.settings.appearance }, set: { v in model.update { $0.appearance = v } }))
        }
        .listRowBackground(DS.surface)
        Section("Ícono de la app") { AppIconPicker() }.listRowBackground(DS.surface)
    }

    @ViewBuilder private func playback(_ model: SettingsModel) -> some View {
        let s = model.settings
        Section("Calidad") {
            Picker("Con Wi‑Fi", selection: Binding(get: { s.quality }, set: { v in model.update { $0.quality = v } })) { qualityOptions }
            Picker("Con datos móviles", selection: Binding(get: { s.cellularQuality }, set: { v in model.update { $0.cellularQuality = v } })) { qualityOptions }
        }
        .listRowBackground(DS.surface)
        Section {
            LabeledContent("Motor", value: PlayerEngines.aetherAvailable ? "AetherEngine" : "AVPlayer")
            Toggle("Abrir siempre en Infuse", isOn: Binding(get: { s.preferInfuse }, set: { v in model.update { $0.preferInfuse = v } }))
            Toggle("Marcar los sustos en la barra", isOn: $scareMarks)
                .accessibilityIdentifier("settings-scare-marks")
        } header: { Text("Reproductor") } footer: {
            Text("En las películas de terror, puntos rojos (fuertes) y ámbar (leves) en la barra de avance, de Where's The Jump.")
        }
        .listRowBackground(DS.surface)
        // R8, R9-B: el mismo nombre y el mismo momento que en la TV (Ajustes › Ver › «Pedir solo el siguiente episodio»).
        Section {
            DSToggleRow("Pedir solo el siguiente episodio", detail: "Si la nube aún no lo tiene, se lo pide 3 min antes del final del que ves.",
                        isOn: Binding(get: { s.autoRequestNextEpisode }, set: { v in model.update { $0.autoRequestNextEpisode = v } }))
                .accessibilityIdentifier("settings-auto-request-next")
        } header: { Text(verbatim: "Real-Debrid") }
        .listRowBackground(DS.surface)
    }

    @ViewBuilder private func downloads(_ model: SettingsModel) -> some View {
        let s = model.settings
        Section {
            // Los mismos tres interruptores que Descargas › Descarga inteligente, con los mismos nombres.
            DSToggleRow("Solo con Wi‑Fi", isOn: Binding(get: { s.wifiOnlyDownloads }, set: { v in model.update { $0.wifiOnlyDownloads = v } }))
            DSToggleRow("Bajar el siguiente episodio", detail: "Cuando acabas de ver uno", isOn: Binding(get: { s.autoNextDownload }, set: { v in model.update { $0.autoNextDownload = v } }))
            Toggle("Borrar al terminar de verlo", isOn: Binding(get: { s.deleteWhenWatched }, set: { v in model.update { $0.deleteWhenWatched = v } }))
        }
        .listRowBackground(DS.surface)
        Section {
            NavigationLink { DownloadSpeedTestView() } label: { Label("Probar la velocidad", systemImage: "speedometer") }
                .accessibilityIdentifier("speed-test")
        } footer: {
            Text("Si las descargas van lentas: mide tu internet, Real-Debrid y la forma en que baja la app.")
        }
        .listRowBackground(DS.surface)
    }

    /// «Ya salió»: un aviso en cuanto sale un episodio de lo que sigues en Trakt (tenga o no ya fuente en Real-Debrid).
    @ViewBuilder private func alerts(_ model: SettingsModel) -> some View {
        let s = model.settings
        Section {
            Toggle("Cuando sale un estreno", isOn: Binding(get: { s.releaseAlerts }, set: { v in
                model.update { $0.releaseAlerts = v }
                guard v else { return }
                Task {
                    if await ReleaseNotifier.requestPermission() { await ReleaseNotifier.check() }
                    else { model.update { $0.releaseAlerts = false }; env.notify("Los avisos están apagados", detail: "Actívalos en Ajustes del iPhone", tone: .warn, actionTitle: "Abrir Ajustes") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
                    } }
                }
            }))
            .accessibilityIdentifier("release-alerts")
        } footer: {
            Text("De las series que sigues en Trakt. Te avisa en cuanto sale, aunque Real-Debrid todavía no lo tenga, con botones para verlo aquí, en la TV o bajarlo. De las 23 a las 8 el aviso espera a la mañana; cada episodio llega en su propio aviso.")
        }
        .listRowBackground(DS.surface)
        // Lo que cuenta es tu sesión de Trakt en el iPhone. Antes se pedía el Client ID de Ajustes, que quedó vacío desde que
        // viene incluido en la app: con Trakt conectado decía «Conecta Trakt» y no dejaba prender los avisos.
        .disabled(!model.traktLinked)
        if model.traktLinked {
            // Cuáles sigues y cuáles ya no, en una lista (antes solo desde la ficha de cada serie).
            Section {
                NavigationLink { FollowedSeriesView() } label: {
                    SettingsRow(title: "Series que sigues", symbol: "bell", tint: DS.ListTint.flame, value: Text("Elige de cuáles te aviso"))
                }
                .accessibilityIdentifier("followed-series")
            }
            .listRowBackground(DS.surface)
        } else {
            Section { Text("Conecta Trakt para saber qué series sigues.").recipe(.footnote) }.listRowBackground(DS.surface)
        }
    }

    @ViewBuilder private func suggestions(_ model: SettingsModel) -> some View {
        let s = model.settings
        Section {
            Picker("País (para lo popular en plataformas)", selection: Binding(get: { s.region }, set: { v in model.update { $0.region = v; $0.regionChosen = true } })) {
                ForEach(["MX", "US", "ES", "AR", "CO", "CL", "PE"], id: \.self) { Text(verbatim: env.uiLocale.localizedString(forRegionCode: $0) ?? $0).tag($0) }
            }
            SecureField(LocalizedStringKey(model.hasTMDBKey ? "Clave de TMDB guardada" : "Clave de TMDB"), text: $tmdbKey).textInputAutocapitalization(.never).autocorrectionDisabled()
            if !tmdbKey.isEmpty { Button("Guardar clave de TMDB") { model.setTMDBKey(tmdbKey); tmdbKey = "" } }
        } footer: {
            env.services.usesBuiltInTMDBKey
                ? Text("Ya viene incluida: fichas y sinopsis en español, temporadas y lo popular en Netflix, Disney+ y HBO Max. Pon la tuya solo si quieres.")
                : Text("TMDB pone las fichas en español y busca lo popular en Netflix, Disney+ y HBO Max.")
        }
        .listRowBackground(DS.surface)
    }

    @ViewBuilder var languageOptions: some View {
        (Text("\(Text.flag("es"))\(Text("Español"))")).tag("es"); (Text("\(Text.flag("en"))\(Text("English"))")).tag("en")
    }

    @ViewBuilder private var qualityOptions: some View {
        Text("4K").tag("4K"); Text("1080p").tag("1080p"); Text("720p").tag("720p")
    }

    // MARK: Trakt
    @ViewBuilder func traktSection(_ model: SettingsModel) -> some View {
        Section("Trakt") {
            switch model.trakt {
            case .off:
                Text("Falta la aplicación de Trakt. Si usas la tuya, pega su Client ID en Avanzado.").font(DS.TextRecipe.footnote.font).foregroundStyle(DS.textMuted)
            case .unlinked:
                // Un solo botón: el código y la página que manda Trakt (hoy auth.trakt.tv/activate). La sesión es de este iPhone; tu Orbital tiene la suya.
                Button("Conectar Trakt") { Task { await model.linkTrakt() } }
                Text("Aparece un código para escribir en la página de Trakt que se indica. La sesión es solo de este iPhone: se avisa de lo que ves, sigues donde ibas en tus otros aparatos y salen Mi lista y tus listas.").font(DS.TextRecipe.caption.font).foregroundStyle(DS.textFaint)
            case .linking(let code, let url):
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    Text("Escribe este código en \(url):").font(DS.TextRecipe.footnote.font).foregroundStyle(DS.textMuted)
                    Text(code).font(DS.TextRecipe.display.font).foregroundStyle(DS.text).textSelection(.enabled).monospaced()
                    DSInlineProgress(text: Text("Esperando…"))
                }
                Button("Cancelar", role: .cancel) { model.cancelLinking() }
            case .linked(let name):
                (name.isEmpty ? Label("Trakt conectado", systemImage: "checkmark.seal") : Label("Trakt: \(name)", systemImage: "checkmark.seal"))
                Button("Desconectar Trakt", role: .destructive) { confirmUnlink = true }
                scrobbleRow(model)
            case .failed(let message):
                DSNotice(verbatim: env.message(message), tone: .error)
                Button("Volver a intentar") { Task { await model.linkTrakt() } }
            }
            // Fuera del switch: escribir el Client ID cambia el estado (sin app → por conectar) sin perder el foco del campo.
            switch model.trakt {
            case .off, .unlinked, .failed:
                DisclosureGroup("Avanzado") {
                    TextField("Client ID de tu aplicación de Trakt", text: Binding(get: { model.settings.traktClientID }, set: { v in model.update { $0.traktClientID = v.trimmingCharacters(in: .whitespaces) } }))
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text("Solo si usas tu propia aplicación (developer.trakt.tv). Vacío: la de Orbital.").font(DS.TextRecipe.caption.font).foregroundStyle(DS.textFaint)
                }
            default: EmptyView()
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

/// Lo que recuerda cada título: el audio (latino, castellano…) y los subtítulos que elegiste viéndolo; vale aquí y en tu
/// Orbital. Deslizar lo olvida (vuelve a lo de Ajustes, en los dos lados).
struct RememberedTitlesView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var rows: [Row] = []
    @State private var names: [String: String] = [:]

    struct Row: Identifiable, Equatable { let id: String; let line: String }

    var body: some View {
        List {
            Section {
                if rows.isEmpty {
                    Text("Ningún título recuerda nada todavía").recipe(.secondary)
                }
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: DS.Space.s1) {
                        Text(verbatim: names[row.id] ?? row.id).recipe(.body)
                        Text(verbatim: row.line).recipe(.footnote)
                    }
                    .swipeActions { Button("Olvidar", role: .destructive) { forget(row.id) } }
                }
            } footer: {
                Text("Lo que elegiste viendo cada uno; vale aquí y en tu Orbital. Desliza para olvidarlo.")
            }
            .listRowBackground(DS.surface)
        }
        .readableListWidth()   // iPad y Mac: al centro, no estirada a todo lo ancho
        .scrollContentBackground(.hidden).background(Backdrop())
        .navigationTitle(Text("Lo que recuerda cada título"))
        .task { reload(); await loadNames() }
    }

    private func reload() {
        let ui = env.services.appSettings.uiLanguage
        rows = env.services.titlePrefs.remembered().map { id, value in
            var parts: [String] = []
            if let audio = value.audio {
                let code = audio == "es" ? (value.spanish ?? "es") : audio
                parts.append(LanguageFlags.flagged(code == "es" ? Strings.tr("Español", language: ui) : Streams.versionLanguageName(code, in: ui), code))
            }
            if let subs = value.subtitles {
                parts.append(subs.isEmpty ? Strings.tr("Sin subtítulos", language: ui)
                             : String(format: Strings.tr("Subtítulos: %@", language: ui), LanguageFlags.flagged(Streams.versionLanguageName(subs, in: ui), subs)))
            }
            return Row(id: id, line: parts.joined(separator: " · "))
        }
        .sorted { $0.id < $1.id }
    }

    /// El nombre de cada título (Cinemeta, de caché casi siempre); sin él, su id.
    private func loadNames() async {
        for row in rows where names[row.id] == nil {
            let cinemeta = env.services.cinemeta
            var meta = try? await cinemeta.meta(kind: "series", id: row.id)
            if meta?["name"]?.string == nil { meta = try? await cinemeta.meta(kind: "movie", id: row.id) }
            if let name = meta?["name"]?.string { names[row.id] = name }
        }
    }

    private func forget(_ id: String) {
        env.services.titlePrefs.forget(metaID: id)
        reload()
    }
}


/// Cómo se abre la hoja de «Usar con tu Orbital»: a conectar (al prender el interruptor) o solo el tutorial.
enum OrbitalSetupStart: Identifiable {
    case connect, tutorial
    var id: Self { self }
}
