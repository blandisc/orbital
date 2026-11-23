import SwiftUI
import OrbitalCore
import OrbitalAddons
import OrbitalModels

/// Ajustes › En este aparato › Diagnóstico (PA6-A, Fernando, 23 nov 2026): un solo lugar que dice qué falla y cómo se arregla,
/// como Ajustes › Sistema › Diagnóstico de la TV. Antes estaba repartido («Probar la velocidad» en Descargas, lo que no llegó a
/// Trakt y el último scrobble en Cuentas). Cada renglón dice cómo está y, si falla, su arreglo con verbo y cosa («Conectar
/// Trakt», «Renovar»). Reúsa lo de cada página (el scrobble, la cola de Trakt, tu nube, la salud de los complementos y el
/// diagnóstico del control); no repite su lógica. Cada grupo sale solo en la versión que lo trae (`Capabilities`).
extension SettingsView {
    @ViewBuilder func diagnostics(_ model: SettingsModel) -> some View {
        let entries = env.services.settingsEntries
        traktDiagnosis(model)
        if entries.realDebrid { cloudDiagnosis }
        if entries.addons { DiagnosisAddons() }
        if env.services.capabilities.instantStreams { speedDiagnosis }
        // Solo el iPhone habla con la TV (PA5-A), y solo con «Usar con tu Orbital» prendido.
        if entries.orbital, model.settings.orbitalEnabled {
            DiagnosisTV(value: orbitalValue) { AnyView(page("Tu Orbital") { orbitalSection(model) }) }
        }
    }

    /// Cuántas cosas hay que revisar (el valor del renglón «Diagnóstico»): lo mismo que la página enseña en ámbar.
    func diagnosticsIssues(_ model: SettingsModel) -> Int {
        let services = env.services, entries = services.settingsEntries
        var count = 0
        if !model.traktLinked { count += 1 }
        if discards.model.count > 0 { count += 1 }
        if entries.realDebrid, !debrid.model.hasToken || debrid.model.status.map(DebridAccountView.isWarning) == true { count += 1 }
        if entries.addons { count += DiagnosisAddons.down(services).count }
        if entries.orbital, model.settings.orbitalEnabled,
           services.orbitalNeedsRescan || !services.orbital.isConfigured || services.tvLinkNow == .silent { count += 1 }
        return count
    }

    func diagnosticsValue(_ model: SettingsModel) -> Text {
        let issues = diagnosticsIssues(model)
        return issues == 0 ? Text("Todo bien") : issues == 1 ? Text("1 cosa que revisar") : Text("\(issues) cosas que revisar")
    }

    // MARK: Trakt

    @ViewBuilder private func traktDiagnosis(_ model: SettingsModel) -> some View {
        Section {
            PaneLink(Text(verbatim: "Trakt")) { page("Trakt") { traktSection(model) } } label: {
                if model.traktLinked {
                    SettingsRow(title: "Trakt", symbol: "checkmark.seal", tint: DS.success, value: traktValue(model))
                } else {
                    SettingsRow(title: "Conectar Trakt", symbol: "checkmark.seal", tint: DS.warning, value: traktValue(model))
                }
            }
            .accessibilityIdentifier("diagnostics-trakt")
            if model.traktLinked { scrobbleRow(model) }
            traktDiscardsRow   // «N cosas no se pudieron guardar en Trakt», solo si hay algo
        } footer: {   // sin título: el renglón ya dice «Trakt»
            Text("Guarda dónde te quedaste y lo que viste. Si algo no llegó, ábrelo para ver qué fue y por qué.")
        }
        .listRowBackground(DS.surface)
        .onAppear { discards.model.reload(); model.refreshScrobble() }
    }

    // MARK: Tu nube

    /// Cuál usas y cuánto le queda; vencida, gratuita o por vencer, su arreglo aquí mismo («Renovar», «Hacerla Premium»).
    @ViewBuilder private var cloudDiagnosis: some View {
        let model = debrid.model
        Section {
            PaneLink(Text("Tu nube")) { DebridAccountView(debrid: model) } label: {
                if model.hasToken, let status = model.status {
                    SettingsRow(title: "Tu nube", symbol: "externaldrive.badge.checkmark",
                                tint: DebridAccountView.isWarning(status) ? DS.warning : DS.success,
                                value: Text("\(Text(verbatim: model.service.name)) · \(DebridWords.short(status))"))
                } else if model.hasToken {
                    SettingsRow(title: "Tu nube", symbol: "externaldrive.badge.checkmark", tint: DS.ListTint.calendar, value: Text("Revisando…"))
                } else {
                    SettingsRow(title: "Conectar tu nube", symbol: "externaldrive.badge.checkmark", tint: DS.warning, value: Text("Falta tu nube"))
                }
            }
            .accessibilityIdentifier("diagnostics-cloud")
            if model.hasToken, let status = model.status, DebridAccountView.isWarning(status) {
                let free = DebridModel.summary(status, now: Date()).state == .free
                Link(destination: model.renewURL) {
                    SettingsRow(title: free ? "Hacerla Premium" : "Renovar", symbol: "arrow.up.right", tint: DS.accent, linked: false)
                }
                .accessibilityIdentifier("diagnostics-renew")
            }
        } footer: { Text("De ahí salen los videos. Te avisamos 14 días antes de que venza.") }
        .listRowBackground(DS.surface)
        .task { await model.load(force: true) }
    }

    // MARK: Velocidad

    @ViewBuilder private var speedDiagnosis: some View {
        Section {
            PaneLink(Text("Probar la velocidad")) { DownloadSpeedTestView() } label: {
                SettingsRow(title: "Probar la velocidad", symbol: "speedometer", tint: DS.ListTint.chart)
            }
            .accessibilityIdentifier("diagnostics-speed")
        } footer: {
            Text("Si las descargas van lentas: mide tu internet, Real-Debrid y la forma en que baja la app.", cloud: env.services.debrid.service, locale: env.uiLocale)   // edición: solo con instantStreams
        }
        .listRowBackground(DS.surface)
    }
}

/// Diagnóstico › los complementos que se preguntan: cómo le fue a cada uno la última vez desde este aparato (la misma
/// `AddonHealthLine` de Ajustes › Complementos). Uno que no contesta va en ámbar; tocar abre Complementos para apagarlo.
private struct DiagnosisAddons: View {   // edición: solo con `settingsEntries.addons`
    @Environment(AppEnvironment.self) private var env
    @State private var addons = ModelObserver(AddonsModel(AppEnvironment.shared.services))

    /// Los prendidos que no contestan (cuentan en el valor del renglón «Diagnóstico»).
    static func down(_ services: Services) -> [InstalledAddon] {
        services.addonList.installed.filter { addon in
            guard addon.enabled, !addon.isOpenSubtitles, let url = services.addonList.resolvedURL(addon) else { return false }
            if case .down = services.addonHealth.status(url) { return true }
            return false
        }
    }

    var body: some View {
        let model = addons.model
        let english = env.services.appSettings.uiLanguage.hasPrefix("en")
        let on = model.items.filter(\.enabled)
        Section {
            ForEach(on) { addon in
                let health = model.health(addon)
                LabeledContent {
                    if health == .unknown { Text("Sin probar todavía").recipe(.footnote, color: DS.textMuted) }
                    else { AddonHealthLine(state: health, english: english) }
                } label: {
                    Label {
                        Text(verbatim: addon.name).foregroundStyle(DS.text)
                    } icon: {
                        Image(systemName: "puzzlepiece.extension").font(DS.TextRecipe.cardTitle.font)
                            .foregroundStyle(Self.isDown(health) ? DS.warning : DS.ListTint.addon).frame(width: DS.SettingsLook.rowIcon)
                    }
                }
            }
            if on.isEmpty { Text("Ninguno prendido: sin ellos no hay de dónde ver.").recipe(.footnote, color: DS.textMuted) }
            PaneLink(Text("Complementos")) { AddonsSettings() } label: {   // edición: solo con `settingsEntries.addons`
                SettingsRow(title: "Revisar complementos", symbol: "slider.horizontal.3", tint: DS.ListTint.addon)   // edición: solo con `settingsEntries.addons`
            }
            .accessibilityIdentifier("diagnostics-addons")
        } header: { Text("Complementos") } footer: {   // edición: solo con `settingsEntries.addons`
            Text("Cuánto tardó cada uno la última vez desde aquí. El que no contesta se salta solo hasta que vuelva.")
        }
        .listRowBackground(DS.surface)
    }

    private static func isDown(_ state: AddonHealth.State) -> Bool { if case .down = state { true } else { false } }
}

/// Diagnóstico › tu TV (solo el iPhone con consola): se le pregunta al abrir; si no contesta, qué tramo falló (el mismo
/// diagnóstico del control, `diagnoseConnection`) y «Probar otra vez». Tocar el renglón abre Tu Orbital.
private struct DiagnosisTV: View {
    let value: Text
    let page: () -> AnyView
    @Environment(AppEnvironment.self) private var env
    @State private var issue: ConnectionIssue?
    @State private var checking = false

    var body: some View {
        let services = env.services
        let _ = services.track()
        Section {
            PaneLink(Text("Tu Orbital")) { page() } label: {
                SettingsRow(title: "Tu TV", symbol: "tv.and.mediabox", tint: tint(services), value: value)
            }
            .accessibilityIdentifier("diagnostics-tv")
            if checking {
                DSInlineProgress(text: Text("Revisando…"))
            } else if services.orbital.isConfigured, services.tvLinkNow == .silent {
                DSProblem(title: Text("Tu TV no contesta"), detail: issue.map(ConnectionTrail.message), symbol: "tv.slash") {
                    Button { Task { await check() } } label: { Text("Probar otra vez").frame(maxWidth: .infinity) }
                        .dsProblemFix(primary: true)
                        .accessibilityIdentifier("diagnostics-tv-retry")
                }
            }
        } footer: { Text("Para «Ver en la TV», el control y la voz.") }
        .listRowBackground(DS.surface)
        .task { await check() }
    }

    private func tint(_ services: Services) -> Color {
        if services.orbitalNeedsRescan || !services.orbital.isConfigured || services.tvLinkNow == .silent { return DS.warning }
        if case .answered = services.tvLinkNow { return DS.success }
        return DS.ListTint.series
    }

    private func check() async {
        guard env.services.orbital.isConfigured, !checking else { return }
        checking = true
        await env.services.checkTV(force: true)
        issue = env.services.tvLinkNow == .silent ? await env.tvNow.diagnoseConnection() : nil
        checking = false
    }
}
