import SwiftUI
import OrbitalCore
import OrbitalModels

/// Ajustes › Tu Orbital (auditoría IOS-2, IOS-3, IOS-5, IOS-14): lo que dice de tu TV es verdad al abrirla. Primero el
/// problema de «Escanear», si lo hay; si no, se le pregunta a la TV y solo si contesta dice «Conectada a <nombre> ✓» (como la
/// TV, que solo dice «✓ Conectado» de un aparato que habló hace menos de 2 min). Sin TV, «Escanear el código» es el botón
/// principal. Sin «Avanzado › Conectar a mano» (TEC-35; Fernando, 3 nov, probando la 1729): con la llave por aparato (K1) el
/// token de la consola ya solo abre Alexa, así que a mano no se llegaba a nada.
extension SettingsView {
    /// El valor del renglón en Ajustes: el problema, «Revisando…», «Conectada», «No contesta» o «Sin conectar».
    var orbitalValue: Text {
        let services = env.services
        if services.orbitalNeedsRescan { return Text("Vuelve a escanear") }
        guard services.orbital.isConfigured else { return Text("Sin conectar") }
        switch services.tvLinkNow {
        case .answered: return Text("Conectada")
        case .silent: return Text("No contesta")
        case .unknown, .checking: return Text("Revisando…")
        }
    }

    @ViewBuilder func orbitalSection(_ model: SettingsModel) -> some View {
        let services = env.services
        let _ = services.track()
        OrbitalRescanProblem { orbitalSetup = .connect }   // K1: «Vuelve a escanear…», solo cuando pasa
        if services.orbital.isConfigured {
            // Con un problema de «Escanear» arriba, nunca «Conectada ✓» debajo (la página se contradecía).
            if services.rescanReason == nil { OrbitalLinkSection(model: model) }
        } else {
            Section {
                // Lo fácil primero: el código de la TV, leído aquí mismo.
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    Label("En la TV: Ajustes › Cuentas › Conectar un aparato", systemImage: "qrcode").recipe(.labelLarge, color: DS.text)
                    Text("Aparece un código. Escanéalo aquí; también sirve la cámara del iPhone.").recipe(.footnote, color: DS.textMuted)
                }
                .padding(.vertical, DS.Space.s1)
                Button { orbitalSetup = .connect } label: { Label("Escanear el código", systemImage: "qrcode.viewfinder").frame(maxWidth: .infinity) }
                    .dsPrimaryButton(size: .large)
                    .accessibilityIdentifier("orbital-scan")
            } header: { Text("Tu TV") } footer: {
                Text("Con tu Orbital conectada, «Ver en la TV» pone en la consola lo que ves aquí, donde ibas. Trakt se conecta aparte en cada uno.")
            }
            .listRowBackground(DS.surface)
        }
        OrbitalDevicesSection()   // K1: los aparatos de tu TV
    }
}

/// IOS-2 · cómo está tu TV, preguntándole al abrir: «Revisando…», «Conectada a Orbital de la sala ✓» o «Tu TV no contesta» con
/// «Reintentar». Lo que se trajo de ella («TMDB y Trakt»), debajo.
private struct OrbitalLinkSection: View {
    let model: SettingsModel
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let services = env.services
        let _ = services.track()
        Group {
            switch services.tvLinkNow {
            case .silent:
                Section {
                    DSProblem(title: env.isOnline ? Text("Tu TV no contesta") : Text("Tu iPhone no tiene internet"),
                              detail: env.isOnline ? Text("Puede estar dormida o apagada. Prende la tele y vuelve a intentar.")
                                                   : Text("Conéctalo al Wi-Fi de tu casa y vuelve a intentar."),
                              symbol: env.isOnline ? "tv.slash" : "wifi.slash") {
                        Button { Task { await check(force: true) } } label: { Text("Reintentar").frame(maxWidth: .infinity) }
                            .dsProblemFix(primary: true)
                            .accessibilityIdentifier("orbital-retry")
                    }
                }
                .listRowBackground(DS.surface)
                .accessibilityIdentifier("orbital-silent")
            case .answered:
                Section {
                    Label { Text("Conectada a \(Self.name(services.tvName))") } icon: {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(DS.success)   // IOS-17: la misma palomita que Real-Debrid
                    }
                    .accessibilityIdentifier("orbital-connected")
                    if !model.importedFromOrbital.isEmpty {
                        Label("Traje de tu Orbital: \(imported). No hay que escribirlo aquí.", systemImage: "arrow.down.doc")
                            .recipe(.footnote, color: DS.textMuted)
                    }
                } header: { Text("Tu TV") } footer: {
                    Text("Con tu Orbital conectada, «Ver en la TV» pone en la consola lo que ves aquí, donde ibas. Trakt se conecta aparte en cada uno.")
                }
                .listRowBackground(DS.surface)
            case .unknown, .checking:
                Section { DSInlineProgress(text: Text("Revisando…")) } header: { Text("Tu TV") }
                    .listRowBackground(DS.surface)
            }
        }
        .task { await check(force: false) }
    }

    private func check(force: Bool) async {
        await env.services.checkTV(force: force)
        if env.services.tvLinkNow != .silent, model.importedFromOrbital.isEmpty { await model.importFromOrbital() }
    }

    private var imported: String {
        model.importedFromOrbital.joined(separator: env.services.appSettings.uiLanguage == "en" ? " and " : " y ")
    }

    /// El nombre que dio la TV al conectar; sin él (o si es una dirección), «tu TV»: nunca el servidor (IOS-2).
    static func name(_ saved: String) -> String {
        let looksLikeHost = saved.contains(".") || saved.contains(":") || saved.isEmpty
        return looksLikeHost ? Strings.tr("tu TV", language: AppEnvironment.shared.services.appSettings.uiLanguage) : saved
    }
}
