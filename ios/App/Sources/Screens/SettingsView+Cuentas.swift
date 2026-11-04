import SwiftUI
import OrbitalModels

/// Ajustes › Cuentas (maqueta 11): cada cuenta con su papel dicho en el título. Real-Debrid (de ahí salen los videos),
/// Trakt · principal (lo tuyo entre aparatos) y Stremio · respaldo (la copia, el único lugar donde dice Stremio). Tu Orbital
/// vive aparte, en Ajustes › Orbital en la TV.
extension SettingsView {
    /// Lo que dice el renglón «Cuentas»: cuánto le queda a tu Real-Debrid, o que falta.
    var debridValue: Text {
        guard let status = debrid.model.status else { return Text("Falta Real-Debrid") }
        // IOS-17: «143 días» no dice de qué; «Real-Debrid · 143 días».
        let value = DebridModel.summary(status, now: Date()).state == .free ? Text("Cuenta gratuita") : DebridWords.short(status)
        return Text("\(Text(verbatim: "Real-Debrid")) · \(value)")
    }

    @ViewBuilder func accounts(_ model: SettingsModel) -> some View {
        debridSection
        Section {
            // La sesión de Trakt siempre es la de este iPhone (la de la consola ya no se presta): se abre, se ve y se desconecta aquí.
            NavigationLink { page("Trakt") { traktSection(model) } } label: {
                SettingsRow(title: "Trakt", symbol: "checkmark.seal", tint: DS.ListTint.chart, value: traktValue(model))
            }
        } header: { Text("Trakt · principal") } footer: { Text("Guarda dónde te quedaste, lo que viste y Mi lista, para todos tus aparatos.") }
        .listRowBackground(DS.surface)
        Section {
            NavigationLink { LetterboxdSettings() } label: {
                SettingsRow(title: "Letterboxd", symbol: "star.bubble", tint: DS.Letterboxd.leaf, value: letterboxdValue)
            }
        } header: { Text("Letterboxd · tus reseñas") } footer: { Text("Solo se lee: tus reseñas salen en Lo que ves y en cada ficha, y tus listas en Explorar.") }
        .listRowBackground(DS.surface)
    }

    private var letterboxdValue: Text {
        let model = AppEnvironment.shared.letterboxd
        let _ = model.track()
        if let user = model.user { return Text(verbatim: "@\(user)") }
        return model.importedAt != nil ? Text("Tu archivo") : Text("No conectado")
    }

    /// Real-Debrid: un renglón con cuánto le queda (ámbar desde 14 días antes) que lleva a su página (D1).
    @ViewBuilder private var debridSection: some View {
        let model = debrid.model
        Section {
            NavigationLink { DebridAccountView(debrid: model) } label: {
                SettingsRow(title: "Real-Debrid", symbol: "externaldrive.badge.checkmark",
                            tint: model.status.map(DebridAccountView.isWarning) == true ? DS.warning : DS.ListTint.calendar,
                            value: model.status.map { DebridWords.short($0) } ?? Text("Falta tu clave"))
            }
            .accessibilityIdentifier("settings-debrid")
        } footer: { Text("De ahí salen los videos. Tu cuenta, tu clave y tus pedidos.") }
        .listRowBackground(DS.surface)
        .task { await model.load(force: true) }
    }
}
