import SwiftUI
import OrbitalCore
import OrbitalModels

/// Ajustes: tu perfil arriba (el avatar se toca) y los renglones que llevan a su página, cada uno con cómo está ahora. PA1-A
/// (23 nov 2026): el mismo esqueleto que la TV; primero lo de las dos apps (Idiomas, Reproducción, Avisos, Cuentas,
/// Complementos) y abajo «En este aparato» (Apariencia, Descargas, tu Orbital en el iPhone, Diagnóstico y Aprende).
struct SettingsView: View {
    /// Una frase de «Lo que puedes decir» tocada desde Ajustes: va a la TV como si la dijeras en el control, y lo que
    /// contesta sale de aviso (aquí no hay renglón de voz).
    private func sayFromSettings(_ phrase: String) {
        Task { @MainActor in
            let outcome = await VoiceAssistant(services: env.services, tvNow: env.tvNow).handle(phrase)
            let text = outcome.speech.isEmpty ? (outcome.ok ? "Listo." : "No llegó a tu Orbital") : outcome.speech
            env.notify(text, tone: outcome.ok ? .success : .warn)
        }
    }

    @Environment(AppEnvironment.self) var env
    @State var settings: ModelObserver<SettingsModel>
    @State var session: ModelObserver<SessionModel>
    /// Tu Real-Debrid (Ajustes › Cuentas).
    @State var debrid: ModelObserver<DebridModel>
    /// Lo que no llegó a Trakt (Ajustes › Cuentas, solo si hay algo).
    @State var discards: ModelObserver<TraktDiscardsModel>
    @State var tmdbKey = ""
    @AppStorage("scare-marks") private var scareMarks = true
    @State private var confirmUnlink = false
    @State private var editingAvatar = false
    @State private var showsYear = false
    @State private var showsTrakt = false
    @State private var showsDiscards = false
    @State private var showsFollowed = false
    @State private var showsPlayback = false
    @State private var showsOrbital = false
    @State private var showsDemoPage = false
    @State private var showsDiagnostics = false
    /// Ajustes › Tus idiomas abierta desde otro lado (`AppUI.openLanguages`: la guía, la página de Torrentio).
    @State var showsLanguages = false
    /// «Usar con tu Orbital»: la hoja de conectar (y luego el tutorial), o solo el tutorial ya conectada.
    @State var orbitalSetup: OrbitalSetupStart?
    @State private var confirmOrbitalOff = false
    /// La página abierta a la derecha en la Mac (MA1); de entrada, «Idiomas», el primer renglón.
    @State var macPage: SettingsPage = .languages
    /// MA2: lo que se abrió desde la página de la derecha en la Mac (Trakt, Real-Debrid…), arriba de ella.
    @State var macStack: [SettingsSubPage] = []

    init() {
        let services = AppEnvironment.shared.services
        _settings = State(wrappedValue: ModelObserver(SettingsModel(services)))
        _session = State(wrappedValue: ModelObserver(AppEnvironment.shared.session))
        _debrid = State(wrappedValue: ModelObserver(DebridModel(services)))
        _discards = State(wrappedValue: ModelObserver(TraktDiscardsModel(services)))
    }

    // En partes: el compilador de la CI (Xcode 26.3) no alcanzaba a revisar todo el formulario de una vez.
    private func settingsForm(_ model: SettingsModel, _ s: AppSettings) -> some View {
        let entries = env.services.settingsEntries   // D1-B: qué renglones existen en esta versión
        return Form {
            Section {
                ProfileCard(avatar: s.avatar, title: s.displayName.isEmpty ? Text("Tu perfil") : Text(verbatim: s.displayName), detail: connections(model)) { editingAvatar = true }
                // «Lo que ves» ya no está aquí: vive en Explorar (Fernando, 2 nov 2026: «ya tenemos otro acceso en Explorar»).
            }
            .listRowBackground(DS.surface)
            // PA1-A (Fernando, 23 nov 2026): el mismo esqueleto que la TV. Primero lo que se usa en las dos apps, en el orden de la
            // TV (Idiomas, Reproducción, Avisos, Cuentas, Complementos); abajo, «En este aparato».
            sharedSection(model, s)
            deviceSection(model, s)
            // La app es de una sola pieza: lo de la consola sale solo con esto prendido (solo el iPhone habla con la TV, PA5-A).
            if entries.orbital { orbitalSettings(model) }
            moreSection(model)
        }
        .tint(DS.accent)   // interruptores, selectores y botones del formulario: el acento (lo interactivo)
        .scrollContentBackground(.hidden).background(Backdrop())
        // Sin el hueco grande de arriba del primer grupo y con aire abajo: el último grupo no queda bajo la barra flotante.
        .contentMargins(.top, DS.Space.s2, for: .scrollContent)
        .contentMargins(.bottom, DS.Space.s12, for: .scrollContent)
        .dsInlineTitle("Ajustes")
        .readableListWidth()   // iPad y Mac: los renglones al centro
    }

    /// Lo que vale en la TV y aquí, en el orden de la TV (PA1-A): Idiomas, Reproducción, Avisos, Cuentas y Complementos.
    @ViewBuilder private func sharedSection(_ model: SettingsModel, _ s: AppSettings) -> some View {
        let entries = env.services.settingsEntries
        Section {
            // Idiomas y subtítulos, arriba (N4-A, Fernando, 4 nov: «que sea fácil configurar los subtítulos y los idiomas»).
            languagesRow(model)
            SettingsLink(.playback) { destination(.playback, model) } label: {
                SettingsRow(title: "Reproducción", symbol: "play.circle", tint: DS.ListTint.list, value: Text(verbatim: s.quality))
            }
            SettingsLink(.alerts) { destination(.alerts, model) } label: {
                SettingsRow(title: "Avisos", symbol: "bell.badge", tint: DS.ListTint.flame, value: s.releaseAlerts ? Text("Estrenos") : Text("Apagados"))
            }
            // Tu nube, Trakt, OneDrive, Letterboxd, OpenSubtitles y las claves de Explorar, cada una con su papel (como la TV).
            SettingsLink(.accounts) { destination(.accounts, model) } label: {
                SettingsRow(title: "Cuentas", symbol: "person.2.circle", tint: DS.ListTint.chart, value: entries.realDebrid ? debridValue : traktValue(model))
            }
            if entries.addons {
                SettingsLink(.addons) { destination(.addons, model) } label: {
                    SettingsRow(title: "Complementos", symbol: "puzzlepiece.extension", tint: DS.ListTint.addon,  // edición: dentro de `entries.addons`
                                value: addonsValue)
                }
            }
        }
        .listRowBackground(DS.surface)
    }

    /// AJ-A, PA1-A: lo que vale solo aquí (cómo se ve y qué se guarda en este aparato); su título dice qué hay adentro.
    @ViewBuilder private func deviceSection(_ model: SettingsModel, _ s: AppSettings) -> some View {
        Section {
            SettingsLink(.appearance) { destination(.appearance, model) } label: {
                SettingsRow(title: "Apariencia", symbol: "circle.lefthalf.filled", tint: DS.ListTint.spark, value: appearanceName(s.appearance))
            }
            SettingsLink(.downloads) { destination(.downloads, model) } label: {
                SettingsRow(title: "Descargas", symbol: "arrow.down.circle", tint: DS.ListTint.calendar, value: s.wifiOnlyDownloads ? Text("Solo con Wi‑Fi") : Text("Siempre"))
            }
            // De qué temporadas sale la dona de Inicio: de vuelta en Ajustes (Fernando, 25 nov 2026), además de junto a los canales.
            if env.services.settingsEntries.simpsons {
                SettingsLink(.simpsons) { destination(.simpsons, model) } label: {
                    SettingsRow(title: "Un Simpson al azar", symbol: DS.Symbol.simpsonsDonut, tint: DS.ListTint.bookmark,
                                value: SimpsonsSeasonsSection.summary(s.simpsonsSeasons), custom: true)
                }
                .accessibilityIdentifier("settings-simpsons-seasons")
            }
        } header: { Text("En este aparato") }
        .listRowBackground(DS.surface)
    }

    @ViewBuilder private func moreSection(_ model: SettingsModel) -> some View {
        // Lo que casi no se toca: qué falla y cómo se arregla (PA6-A, como Ajustes › Sistema › Diagnóstico de la TV) y Aprende.
        Section {
            SettingsLink(.diagnostics) { destination(.diagnostics, model) } label: {
                SettingsRow(title: "Diagnóstico", symbol: "stethoscope", tint: diagnosticsIssues(model) > 0 ? DS.warning : DS.ListTint.series,
                            value: diagnosticsValue(model))
            }
            .accessibilityIdentifier("settings-diagnostics")
            // «Aprende»: una sola entrada con las historias, la guía otra vez, los avisos desde cero y lo que se puede hacer con
            // la TV (revisión del 11 nov: eran cuatro renglones casi iguales, dos con el mismo destello).
            SettingsLink(.learn) { destination(.learn, model) } label: {
                SettingsRow(title: "Aprende", symbol: DS.Symbol.learn, tint: DS.ListTint.spark, value: Text("\(LessonCatalog.all.count) lecciones"))
            }
            .accessibilityIdentifier("settings-learn")
        }
        .listRowBackground(DS.surface)
    }

    private var profileSheet: some View {
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
                .dsInlineTitle("Tu perfil")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { editingAvatar = false } } }
        }
        .presentationDetents([.medium])
    }

    var body: some View {
        let model = settings.model
        let s = model.settings
        // En partes: el compilador de la CI (Xcode 26.3) no alcanzaba a revisar todo Ajustes de una vez.
        withDemoPages(withDialogs(macSplit(settingsForm(model, s), model), s), model)
        .task { await model.loadTraktName(); await debrid.model.load() }
        .navigationDestination(isPresented: $showsLanguages) { destination(.languages, model) }   // la única página de idiomas (ID-A): la app, los títulos, el audio y los subtítulos
        .onChange(of: env.ui.openLanguages, initial: true) { _, open in
            guard open else { return }
            env.ui.openLanguages = false
            showsLanguages = true
        }
    }

    /// Las hojas y preguntas de Ajustes: conectar tu Orbital, apagarla, los avisos, desconectar Trakt y tu perfil.
    private func withDialogs(_ content: some View, _ s: AppSettings) -> some View {
        content
            .appSheet(item: $orbitalSetup) { start in OrbitalSetupView(tutorialOnly: start == .tutorial) }
            .confirmationDialog("¿Dejar de usar tu Orbital?", isPresented: $confirmOrbitalOff, titleVisibility: .visible) {   // ds-exception: confirmación de desconectar (sí o no)
                Button("Apagar", role: .destructive) { env.services.turnOffOrbital(); ReleaseNotifier.registerCategory(language: s.uiLanguage, tv: false) }
                Button("Dejarla conectada", role: .cancel) {}
            } message: { Text("Se esconden «Ver en la TV», el control y la voz. Lo que viste se queda: viaja por Trakt.") }
            .confirmationDialog("¿Desconectar Trakt?", isPresented: $confirmUnlink, titleVisibility: .visible) {   // ds-exception: confirmación de desconectar (sí o no)
                Button("Desconectar", role: .destructive) { Task { await settings.model.unlinkTrakt() } }
                Button("Dejarla conectada", role: .cancel) {}
            } message: { Text("Dejan de salir Mi lista, tus listas y lo que sigues; lo que veas ya no se marca en Trakt.") }
            .appSheet(isPresented: $editingAvatar) { profileSheet }
    }

    /// `-demo-open` y `-demo-settings-page`: abrir una página de Ajustes para las capturas (solo en Debug).
    @ViewBuilder private func withDemoPages(_ content: some View, _ model: SettingsModel) -> some View {
        #if DEBUG
        content
            .navigationDestination(isPresented: $showsYear) { YearView() }   // `-demo-open year`: para las capturas
            .task { if Demo.isOn, Demo.open == "settings-avatar" { editingAvatar = true }; if Demo.isOn, Demo.open == "year" { showsYear = true } }
            // `-demo-open orbital-setup`: «Conecta tu Orbital» (Escanear el código), para capturas; con `-demo-scan [v2]`, ya conectada.
            .task { if Demo.isOn, Demo.open == "orbital-setup" { orbitalSetup = .connect } }
            .navigationDestination(isPresented: $showsTrakt) { page("Trakt") { traktSection(model) } }   // `-demo-settings-page trakt`: capturas
            .task { if Demo.isOn, Demo.value(after: "-demo-settings-page") == "trakt" { showsTrakt = true } }
            // `-demo-settings-page trakt-discards` (con `-demo-trakt-discards`): lo que no llegó a Trakt.
            .navigationDestination(isPresented: $showsDiscards) { TraktDiscardsView(model: discards.model) }
            .task { if Demo.isOn, Demo.value(after: "-demo-settings-page") == "trakt-discards" { showsDiscards = true } }
            .navigationDestination(isPresented: $showsFollowed) { FollowedSeriesView() }   // `-demo-settings-page series`: capturas
            .task { if Demo.isOn, Demo.value(after: "-demo-settings-page") == "series" { showsFollowed = true } }
            // `-demo-settings-page requests`: Tus pedidos (D3), que viven en Descargas › Lo que pediste (RX1-A).
            .task { if Demo.isOn, Demo.value(after: "-demo-settings-page") == "requests" { env.openTab = AppEnvironment.downloadsTab } }
            .navigationDestination(isPresented: $showsPlayback) { page("Reproducción") { playback(model) } }   // `-demo-settings-page playback`
            .task { if Demo.isOn, Demo.value(after: "-demo-settings-page") == "playback" { showsPlayback = true } }
            .task { if Demo.isOn, Demo.value(after: "-demo-settings-page") == "languages" { showsLanguages = true } }   // N4-A
            .navigationDestination(isPresented: $showsOrbital) { page("Tu Orbital") { orbitalSection(model) } }   // `-demo-settings-page orbital` (K1)
            .task { if Demo.isOn, Demo.value(after: "-demo-settings-page") == "orbital" { showsOrbital = true } }
            // `-demo-settings-page diagnostics|accounts`: Diagnóstico (PA6-A) y Cuentas (con OneDrive y TMDB, PA1-A).
            .navigationDestination(isPresented: $showsDiagnostics) {
                Demo.value(after: "-demo-settings-page") == "accounts" ? destination(.accounts, model) : destination(.diagnostics, model)
            }
            .task { if Demo.isOn, ["diagnostics", "accounts"].contains(Demo.value(after: "-demo-settings-page") ?? "") { showsDiagnostics = true } }
            // `-demo-settings-page torrentio|addons|realdebrid`: Complementos, Torrentio y tu cuenta de Real-Debrid (Fase 3).
            .navigationDestination(isPresented: $showsDemoPage) { DemoSettingsPage(name: Demo.value(after: "-demo-settings-page") ?? "", debrid: debrid.model) }
            .task { if Demo.isOn, ["torrentio", "addons", "realdebrid"].contains(Demo.value(after: "-demo-settings-page") ?? "") { showsDemoPage = true } }
        #else
        content
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
                SettingsLink(.orbital) { destination(.orbital, model) } label: {
                    SettingsRow(title: "Tu Orbital", symbol: "tv.and.mediabox", tint: env.services.orbitalNeedsRescan || env.services.tvLinkNow == .silent ? DS.warning : DS.ListTint.series,
                                value: orbitalValue)
                }
                .task { await env.services.checkTV() }   // IOS-2: «Conectada» solo si la TV contestó
                SettingsLink(.voice) { destination(.voice, model) } label: {
                    SettingsRow(title: "Voz y Siri", symbol: "waveform", tint: DS.ListTint.bookmark, value: Text("Qué puedes decir"))
                }
            }
        } footer: {   // PA1-A: dentro de «En este aparato», sin título propio
            on ? Text("Apágalo cuando quieras: la app vuelve a ser solo del iPhone. Lo que viste sigue en Trakt.")
               : Text("¿Tienes la consola Orbital en tu TV? Prende esto para mandarle lo que ves, usar el iPhone de control y hablarle.")   // edición: la sección solo existe con `settingsEntries.orbital` (console)
        }
        .listRowBackground(DS.surface)
        .onChange(of: on) { _, now in ReleaseNotifier.registerCategory(language: model.settings.uiLanguage, tv: now) }
    }

    /// La página de cada renglón de la lista: la misma en iPhone y iPad (empujada) y en la Mac (a la derecha, MA1).
    /// Borrada a `AnyView`: con su tipo de verdad (las 15 páginas en un `switch`) cada uno de los ~13 renglones lo cargaba y
    /// la primera vez que abrías Ajustes Swift armaba ese tipo gigante (~0.25 s trabado en el iPad; 17 nov 2026).
    func destination(_ page: SettingsPage, _ model: SettingsModel) -> AnyView {   // ds-exception: borrar el tipo es el arreglo
        AnyView(pageContent(page, model))
    }

    @ViewBuilder private func pageContent(_ page: SettingsPage, _ model: SettingsModel) -> some View {
        switch page {
        case .languages: self.page("Idiomas") { languagesPage(model) }
        case .appearance: self.page("Apariencia") { appearance(model) }
        case .playback: self.page("Reproducción") { playback(model) }
        case .alerts: self.page("Avisos") { alerts(model) }
        case .downloads: self.page("Descargas") { downloads(model) }
        case .simpsons: SimpsonsSeasonsPage()
        case .accounts: self.page("Cuentas") { accounts(model) }
        case .addons: AddonsSettings()
        case .orbital: self.page("Tu Orbital") { orbitalSection(model) }
        // La voz le da órdenes a tu Orbital; tocar una frase la manda a la TV, como en el control.
        case .voice: VoiceGuideView(hints: env.tvNow.hints, nowTitle: env.tvNow.now?.title) { phrase in sayFromSettings(phrase) }
        case .diagnostics: self.page("Diagnóstico") { diagnostics(model) }
        case .learn: LearnView(tvTutorial: env.services.settingsEntries.orbital && model.settings.orbitalEnabled ? { orbitalSetup = .tutorial } : nil)
        }
    }

    /// Una página de Ajustes: el mismo formulario y fondo.
    func page<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        Form { content() }
            .tint(DS.accent)
            .scrollContentBackground(.hidden).background(Backdrop())
            .dsInlineTitle(title)
            .readableListWidth()
    }

    /// «Conectado a Orbital · falta Trakt»: lo que conectaste bajo tu avatar y, si algo falta, cuál (AJ-A, 20 nov 2026: decir
    /// qué falta, no solo lo que está). Stremio, el respaldo, solo en Cuentas.
    private func connections(_ model: SettingsModel) -> Text {
        var parts: [String] = [], missing: [String] = []
        if case .linked = model.trakt { parts.append("Trakt") } else { missing.append("Trakt") }
        if env.services.settingsEntries.realDebrid {   // edición: solo con `settingsEntries.realDebrid`
            if debrid.model.hasToken { parts.append(debrid.model.service.name) } else { missing.append(debrid.model.service.name) }
        }
        if env.services.settingsEntries.orbital, env.services.orbital.isConfigured { parts.append("Orbital") }   // PA5-A: solo el iPhone
        if parts.isEmpty { return Text("Sin cuentas conectadas") }
        let names = parts.joined(separator: ", ")
        return missing.isEmpty ? Text("Conectado a \(names)") : Text("Conectado a \(names) · falta \(missing.joined(separator: ", "))")
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
        Section {   // un renglón con su nombre y el selector a la derecha (`SettingsChoiceRow`), como «Idiomas»
            SettingsChoiceRow(title: "Modo", symbol: "circle.lefthalf.filled", tint: DS.ListTint.spark, options: [.init(id: "system", title: Text("Como el iPhone")), .init(id: "light", title: Text("Claro")),
                                                       .init(id: "dark", title: Text("Oscuro"))],
                              selection: Binding(get: { model.settings.appearance }, set: { v in model.update { $0.appearance = v } }))
        }
        .listRowBackground(DS.surface)
        // En la Mac el ícono no se puede cambiar (la app del iPad no tiene íconos alternos ahí): no se ofrece.
        if !ThisDevice.isMac { Section("Ícono de la app") { AppIconPicker() }.listRowBackground(DS.surface) }
    }

    @ViewBuilder private func playback(_ model: SettingsModel) -> some View {
        let s = model.settings
        Section("Calidad") {
            SettingsChoiceRow(title: "Con Wi‑Fi", symbol: "wifi", tint: DS.ListTint.series, options: qualityChoices,
                              selection: Binding(get: { s.quality }, set: { v in model.update { $0.quality = v } }))
            // En la Mac no hay datos móviles: un solo renglón («En esta Mac», su versión del catálogo).
            if !ThisDevice.isMac {
                SettingsChoiceRow(title: "Con datos móviles", symbol: "antenna.radiowaves.left.and.right", tint: DS.ListTint.trend, options: qualityChoices,
                                  selection: Binding(get: { s.cellularQuality }, set: { v in model.update { $0.cellularQuality = v } }))
            }
        }
        .listRowBackground(DS.surface)
        Section {
            SettingsRow(title: "Motor", symbol: "cpu", tint: DS.ListTint.chart,
                        value: Text(verbatim: PlayerEngines.aetherAvailable ? "AetherEngine" : "AVPlayer"), linked: false)
            DSToggleRow("Abrir siempre en Infuse", symbol: "arrow.up.forward.app", tint: DS.ListTint.calendar,
                        isOn: Binding(get: { s.preferInfuse }, set: { v in model.update { $0.preferInfuse = v } }))
            DSToggleRow("Marcar los sustos en la barra", symbol: "bolt.heart", tint: DS.ListTint.flame, isOn: $scareMarks)
                .accessibilityIdentifier("settings-scare-marks")
        } header: { Text("Reproductor") } footer: {
            Text("En las películas de terror, puntos rojos (fuertes) y ámbar (leves) en la barra de avance, de Where's The Jump.")
        }
        .listRowBackground(DS.surface)
        // R8, R9-B: el mismo nombre y el mismo momento que en la TV (Ajustes › Ver › «Pedir solo el siguiente episodio»).
        // Solo donde hay nube (D1-B: Orbital, de la App Store, no pide a Real-Debrid).
        if env.services.capabilities.instantStreams { Section {
            DSToggleRow("Pedir solo el siguiente episodio", detail: "Si la nube aún no lo tiene, se lo pide 3 min antes del final del que ves.",
                        symbol: "forward.end", tint: DS.ListTint.series, isOn: Binding(get: { s.autoRequestNextEpisode }, set: { v in model.update { $0.autoRequestNextEpisode = v } }))
                .accessibilityIdentifier("settings-auto-request-next")
        } header: { Text(verbatim: env.services.debrid.service.name) }   // edición: solo con instantStreams
        .listRowBackground(DS.surface) }
    }

    @ViewBuilder private func downloads(_ model: SettingsModel) -> some View {
        let s = model.settings
        Section {
            // Los mismos tres interruptores que Descargas › Descarga inteligente, con los mismos nombres.
            if !ThisDevice.isMac {   // en la Mac no hay datos móviles que cuidar
                DSToggleRow("Solo con Wi‑Fi", symbol: "wifi", tint: DS.ListTint.series, isOn: Binding(get: { s.wifiOnlyDownloads }, set: { v in model.update { $0.wifiOnlyDownloads = v } }))
            }
            DSToggleRow("Bajar el siguiente episodio", detail: "Cuando acabas de ver uno", symbol: "arrow.down.circle", tint: DS.ListTint.trend, isOn: Binding(get: { s.autoNextDownload }, set: { v in model.update { $0.autoNextDownload = v } }))
            DSToggleRow("Borrar al terminar de verlo", symbol: "trash", tint: DS.ListTint.flame,
                        isOn: Binding(get: { s.deleteWhenWatched }, set: { v in model.update { $0.deleteWhenWatched = v } }))
        }
        .listRowBackground(DS.surface)
        // La prueba mide a Real-Debrid: solo donde hay nube (D1-B).
        if env.services.capabilities.instantStreams {
            Section {
                PaneLink(Text("Probar la velocidad")) { DownloadSpeedTestView() } label: { SettingsRow(title: "Probar la velocidad", symbol: "speedometer", tint: DS.ListTint.chart) }
                    .accessibilityIdentifier("speed-test")
            } footer: {
                Text("Si las descargas van lentas: mide tu internet, Real-Debrid y la forma en que baja la app.", cloud: env.services.debrid.service, locale: env.uiLocale)   // edición: solo con instantStreams
            }
            .listRowBackground(DS.surface)
        }
    }

    /// «Ya salió»: un aviso en cuanto sale un episodio de lo que sigues en Trakt (tenga o no ya fuente en Real-Debrid).
    @ViewBuilder private func alerts(_ model: SettingsModel) -> some View {
        let s = model.settings
        Section {
            DSToggleRow("Cuando sale un estreno", symbol: "bell.badge", tint: DS.ListTint.flame, isOn: Binding(get: { s.releaseAlerts }, set: { v in
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
            if env.services.capabilities.instantStreams {
                Text("De las series que sigues en Trakt. Te avisa en cuanto sale, aunque Real-Debrid todavía no lo tenga, con botones para verlo aquí, en la TV o bajarlo. De las 23 a las 8 el aviso espera a la mañana; cada episodio llega en su propio aviso.", cloud: env.services.debrid.service, locale: env.uiLocale)   // edición: solo con instantStreams
            } else {
                Text("De las series que sigues en Trakt. Te avisa en cuanto sale. De las 23 a las 8 el aviso espera a la mañana; cada episodio llega en su propio aviso.")
            }
        }
        .listRowBackground(DS.surface)
        // Lo que cuenta es tu sesión de Trakt en el iPhone. Antes se pedía el Client ID de Ajustes, que quedó vacío desde que
        // viene incluido en la app: con Trakt conectado decía «Conecta Trakt» y no dejaba prender los avisos.
        .disabled(!model.traktLinked)
        if model.traktLinked {
            // Cuáles sigues y cuáles ya no, en una lista (antes solo desde la ficha de cada serie).
            Section {
                PaneLink(Text("Series que sigues")) { FollowedSeriesView() } label: {
                    SettingsRow(title: "Series que sigues", symbol: "bell", tint: DS.ListTint.flame, value: Text("Elige de cuáles te aviso"))
                }
                .accessibilityIdentifier("followed-series")
            }
            .listRowBackground(DS.surface)
        } else {
            Section { Text("Conecta Trakt para saber qué series sigues.").recipe(.footnote) }.listRowBackground(DS.surface)
        }
    }

    @ViewBuilder var languageOptions: some View {
        (Text("\(Text.flag("es"))\(Text("Español"))")).tag("es"); (Text("\(Text.flag("en"))\(Text("English"))")).tag("en")
    }

    private var qualityChoices: [DSSelector<String>.Option] {
        ["4K", "1080p", "720p"].map { .init(id: $0, title: Text(verbatim: $0)) }
    }

    // MARK: Trakt
    @ViewBuilder func traktSection(_ model: SettingsModel) -> some View {
        Section {   // sin «Trakt» encima: la página ya se llama así (en la Mac salía dos veces, 17 nov 2026)
            switch model.trakt {
            case .off:
                Text("Falta la aplicación de Trakt. Si usas la tuya, pega su Client ID en Avanzado.").font(DS.TextRecipe.footnote.font).foregroundStyle(DS.textMuted)
            case .unlinked:
                // Un solo botón: el código y la página que manda Trakt (hoy auth.trakt.tv/activate). La sesión es de este iPhone; tu Orbital tiene la suya.
                Button("Conectar Trakt") { Task { await model.linkTrakt() } }
                Text("Aparece un código para escribir en la página de Trakt que se indica. La sesión es solo de este iPhone: se avisa de lo que ves, sigues donde ibas en tus otros aparatos y salen Mi lista y tus listas.").font(DS.TextRecipe.caption.font).foregroundStyle(DS.textFaint)
            case .linking(let code, let url):
                DeviceCodeCard(service: "Trakt", code: code, url: URL(string: url))
                Button("Cancelar", role: .cancel) { model.cancelLinking() }
            case .linked(let name):
                (name.isEmpty ? Label("Trakt conectado", systemImage: "checkmark.seal") : Label("Trakt: \(name)", systemImage: "checkmark.seal"))
                Button("Desconectar Trakt", role: .destructive) { confirmUnlink = true }
                scrobbleRow(model)
            case .failed(let message):
                DSNotice(verbatim: env.message(message), tone: .error)
                Button("Reintentar") { Task { await model.linkTrakt() } }
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

    /// «Lo último que le contaste a Trakt» (así la TV): lo último que se le contó a Trakt (o por qué no se pudo), para comprobarlo en trakt.tv › Historial.
    @ViewBuilder
    func scrobbleRow(_ model: SettingsModel) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            Text("Lo último que le contaste a Trakt").font(DS.TextRecipe.footnote.font).foregroundStyle(DS.textMuted)
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
                        Text.withFlagImages(row.line).recipe(.footnote)
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
        .dsNavigationTitle("Lo que recuerda cada título")
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
