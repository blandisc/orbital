import SwiftUI
import OrbitalModels

/// Ajustes › Cuentas (maqueta 11): cada cuenta con su papel dicho en el título. Real-Debrid (de ahí salen los videos),
/// Trakt · principal (lo tuyo entre aparatos), Stremio · respaldo (la copia, el único lugar donde dice Stremio) y tu Orbital.
extension SettingsView {
    /// Lo que dice el renglón «Cuentas»: cuánto le queda a tu Real-Debrid, o que falta.
    var debridValue: Text {
        guard let status = debrid.model.status else { return Text("Falta Real-Debrid") }
        return DebridModel.summary(status, now: Date()).state == .free ? Text("Cuenta gratuita") : DebridWords.short(status)
    }

    @ViewBuilder func accounts(_ model: SettingsModel) -> some View {
        debridSection
        Section {
            if traktFromOrbital(model) {
                SettingsRow(title: "Trakt", symbol: "checkmark.seal", tint: DS.ListTint.chart, value: Text("Desde tu Orbital"), linked: false)
            } else {
                NavigationLink { page("Trakt") { traktSection(model) } } label: {
                    SettingsRow(title: "Trakt", symbol: "checkmark.seal", tint: DS.ListTint.chart, value: traktValue(model))
                }
            }
        } header: { Text("Trakt · principal") } footer: { Text("Guarda dónde te quedaste, lo que viste y Mi lista, para todos tus aparatos.") }
        .listRowBackground(DS.surface)
        Section {
            if session.model.state == .signedIn {
                Label("Conectado", systemImage: "person.crop.circle.badge.checkmark")
                Button("Cerrar sesión de Stremio", role: .destructive) { confirmSignOut = true }
            } else {
                NavigationLink { LoginView(session: session.model) } label: {
                    SettingsRow(title: "Conectar", symbol: "arrow.triangle.2.circlepath", tint: DS.ListTint.addon, value: Text("No conectado"))
                }
            }
        } header: { Text("Stremio · respaldo") } footer: { Text("Lo que ves también se guarda ahí, como copia.") }
        .listRowBackground(DS.surface)
        // La Mac no se conecta con tu Orbital (`Services.allowsOrbital`): ahí no hay nada que configurar.
        if env.services.allowsOrbital {
            Section {
                NavigationLink { page("Tu Orbital") { orbitalSection(model) } } label: {
                    SettingsRow(title: "Tu Orbital", symbol: "tv", tint: DS.ListTint.series, value: env.services.orbital.isConfigured ? Text("Conectada") : Text("Sin conectar"))
                }
            } header: { Text("Tu Orbital") }
            .listRowBackground(DS.surface)
        }
    }

    /// Real-Debrid: cómo está (días, vencimiento), «Renovar», «Cambiar clave» y «Quitar»; sin clave, el campo para pegarla.
    @ViewBuilder private var debridSection: some View {
        let model = debrid.model
        Section {
            if let status = model.status {
                LabeledContent {
                    DebridWords.text(status).font(DS.TextRecipe.footnote.font).foregroundStyle(DS.textMuted)
                } label: {
                    Text(verbatim: status.isPremium ? "\(status.username) · Premium" : status.username).foregroundStyle(DS.text)
                }
                Link(destination: model.renewURL) { Label("Renovar", systemImage: "arrow.up.right") }
                NavigationLink { page("Cambiar clave") { Section { DebridKeyField(debrid: model) }.listRowBackground(DS.surface) } } label: {
                    Text("Cambiar clave")
                }
                Button("Quitar", role: .destructive) { Task { await model.remove() } }
            } else {
                DebridKeyField(debrid: model)
                Link(destination: model.tokenURL) { Label(String(localized: "Sacar tu clave en real-debrid.com/apitoken"), systemImage: "arrow.up.right") }
            }
        } header: { Text(verbatim: "Real-Debrid") } footer: { Text("Te avisamos 14 días antes, 3 días antes y el día que vence. No se renueva solo.") }
        .listRowBackground(DS.surface)
        .task { await model.load(force: true) }
    }
}
