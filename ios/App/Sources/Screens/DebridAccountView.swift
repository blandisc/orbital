import SwiftUI
import OrbitalCore
import OrbitalAddons
import OrbitalModels

/// Ajustes › Cuentas › Real-Debrid (D1): quién eres, Premium hasta cuándo y cuántos días quedan, «Renovar», canjear tus
/// puntos (D4, solo aquí y solo si tienes), tu clave («termina en ••••3F2A · nunca se muestra completa»), «Tus pedidos» (D3)
/// y «¿Qué es Real-Debrid?». Sin clave: el campo para pegarla.
struct DebridAccountView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var debrid: ModelObserver<DebridModel>
    @State private var explaining = false
    @State private var confirmRedeem = false
    @State private var confirmRemove = false

    init(debrid: DebridModel) { _debrid = State(wrappedValue: ModelObserver(debrid)) }

    var body: some View {
        let model = debrid.model
        Form {
            Section {
                Button { explaining = true } label: {
                    TorrentioRowLabel(title: Text("¿Qué es Real-Debrid?"), detail: Text("Por qué arranca al instante y qué cuesta"))
                }
                .accessibilityIdentifier("debrid-explain")
            }
            .listRowBackground(DS.surface)
            if let status = model.status { account(status, model) }
            else if model.hasToken { unknown(model) }   // hay clave, pero Real-Debrid no contestó: nunca el campo vacío
            else { connect(model) }
        }
        .tint(DS.accent)
        .scrollContentBackground(.hidden).background(Backdrop())
        .navigationTitle(Text(verbatim: "Real-Debrid")).navigationBarTitleDisplayMode(.inline)
        .readableListWidth()
        .sheet(isPresented: $explaining) { DebridExplainer(topic: .realDebrid) { explaining = false }.presentationDetents([.medium, .large]) }
        .confirmationDialog("¿Canjear tus puntos?", isPresented: $confirmRedeem, titleVisibility: .visible) {
            Button("Canjear") { Task { await model.redeemPoints() } }
            Button("Cancelar", role: .cancel) {}
        } message: { Text("Real-Debrid cambia tus puntos por días de Premium. No se puede deshacer.") }
        .confirmationDialog("¿Quitar tu clave?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Quitar", role: .destructive) { Task { await model.remove() } }
            Button("Cancelar", role: .cancel) {}
        } message: { Text("Sin ella no hay versiones hasta que pongas otra. Tu cuenta de Real-Debrid no se toca.") }
        .task { await model.load(force: true) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("debrid-account")
    }

    @ViewBuilder private func account(_ status: DebridStatus, _ model: DebridModel) -> some View {
        Section {
            LabeledContent {
                if status.isPremium { Text(verbatim: "Premium").foregroundStyle(DS.textMuted) } else { Text("Sin Premium").foregroundStyle(DS.warning) }
            } label: { Text(verbatim: status.username).foregroundStyle(DS.text) }
            expiry(status).recipe(.footnote, color: Self.isWarning(status) ? DS.warning : DS.textMuted)   // ámbar desde 14 días antes (D1)
            Link(destination: model.renewURL) { Label("Renovar", systemImage: "arrow.up.right") }
            // D4: solo aquí, solo si tienes puntos, y preguntando antes (no se deshace). Nunca en las pruebas: solo la demo.
            if let points = status.points, points > 0 {
                Button { confirmRedeem = true } label: {
                    TorrentioRowLabel(title: Text("Canjear puntos"), detail: Text("\(Strings.count(points, language: env.services.appSettings.uiLanguage)) puntos · días de Premium"))
                }
                .disabled(model.redeem == .working)
                .accessibilityIdentifier("debrid-redeem")
            }
            switch model.redeem {
            case .working: DSInlineProgress(text: Text("Canjeando…"))
            case .done: DSNotice(text: "Listo: tus puntos ya son días de Premium.", tone: .success)
            case .failed(let message): DSNotice(verbatim: env.message(message), tone: .warn)
            case .idle: EmptyView()
            }
        } header: { Text("Tu cuenta") } footer: { Text("Te avisamos 14 días antes, 3 días antes y el día que vence. No se renueva solo.") }
        .listRowBackground(DS.surface)
        // «Tus pedidos» antes que tu clave: «Quitar» (lo destructivo) va al final de la página, como en iOS.
        Section {
            // D3: lo que Real-Debrid está bajando para ti (tus pedidos), con «Cancelar».
            NavigationLink { DebridRequestsView() } label: {
                SettingsRow(title: "Tus pedidos", symbol: "arrow.down.circle", tint: DS.ListTint.calendar, value: requestsValue)
            }
            .accessibilityIdentifier("settings-debrid-requests")
        }
        .listRowBackground(DS.surface)
        keySection(model, verified: true)
    }

    /// Tu clave: conectada (sus últimas 4 letras), cambiarla y quitarla. Lo destructivo, al final.
    /// `verified` false: hay clave, pero no se sabe si sirve (Real-Debrid no contestó): «Guardada», sin la palomita verde.
    @ViewBuilder private func keySection(_ model: DebridModel, verified: Bool) -> some View {
        let tail = model.keyTail ?? "····"
        Section {
            HStack(spacing: DS.Space.s3) {
                TorrentioRowLabel(title: verified ? Text("Conectada") : Text("Guardada"), detail: Text("termina en ••••\(tail) · nunca se muestra completa"))
                Spacer(minLength: DS.Space.s2)
                if verified { Image(systemName: "checkmark.circle.fill").foregroundStyle(DS.success).accessibilityHidden(true) }
            }
            .accessibilityElement(children: .combine)
            if model.keyCameFromImport {
                Text("Tomé tu clave de Real-Debrid de tu Torrentio").recipe(.footnote, color: DS.textMuted)
            }
            NavigationLink { keyPage(model) } label: { Text("Cambiar clave").foregroundStyle(DS.text) }
            Button("Quitar", role: .destructive) { confirmRemove = true }
        } header: { Text("Tu clave") }
        .listRowBackground(DS.surface)
    }

    /// Hay clave guardada pero todavía no se sabe de tu cuenta (sin internet o Real-Debrid no contestó): se dice y se
    /// reintenta; la clave sigue ahí (antes salía el campo para pegarla, como si no tuvieras).
    @ViewBuilder private func unknown(_ model: DebridModel) -> some View {
        Section {
            Label { Text("No pude ver tu cuenta") } icon: { Image(systemName: "wifi.exclamationmark").foregroundStyle(DS.warning) }
                .foregroundStyle(DS.text)
            Button("Reintentar") { Task { await model.load(force: true) } }
                .accessibilityIdentifier("debrid-retry")
        } header: { Text("Tu cuenta") } footer: { Text("Real-Debrid no contestó. Tu clave sigue guardada.") }
        .listRowBackground(DS.surface)
        keySection(model, verified: false)
    }

    @ViewBuilder private func connect(_ model: DebridModel) -> some View {
        Section {
            DebridKeyField(debrid: model)
            Link(destination: model.tokenURL) { Label(String(localized: "Sacar tu clave en real-debrid.com/apitoken"), systemImage: "arrow.up.right") }
        } header: { Text("Tu clave") } footer: { Text("Sale de real-debrid.com/apitoken. Vive en el llavero de este aparato.") }
        .listRowBackground(DS.surface)
    }

    private func keyPage(_ model: DebridModel) -> some View {
        Form { Section { DebridKeyField(debrid: model) }.listRowBackground(DS.surface) }
            .tint(DS.accent)
            .scrollContentBackground(.hidden).background(Backdrop())
            .navigationTitle("Cambiar clave").navigationBarTitleDisplayMode(.inline)
            .readableListWidth()
    }

    /// «Vence el sábado 21 de noviembre · quedan 18 días»; «Vence hoy»; «Venció el …»; sin fecha, lo de siempre.
    private func expiry(_ status: DebridStatus) -> Text {
        let ui = env.services.appSettings.uiLanguage
        guard let expires = status.expires else { return DebridWords.text(status) }
        let day = Strings.date(expires, .weekdayDayMonth, language: ui)
        let (state, days) = DebridModel.summary(status, now: Date())
        switch state {
        case .active, .expiringSoon:
            return days == 0 ? Text("Vence hoy") : days == 1 ? Text("Vence el \(day) · queda 1 día") : Text("Vence el \(day) · quedan \(String(days)) días")
        case .expired: return Text("Venció el \(day)")
        case .free: return Text("Cuenta gratuita")
        }
    }

    static func isWarning(_ status: DebridStatus) -> Bool {
        switch status.state(now: Date()) { case .active: false; default: true }
    }

    /// «2 bajando» o nada.
    private var requestsValue: Text? {
        let requests = env.services.debridRequests
        let _ = requests.track()
        let active = requests.active.count
        return active == 0 ? nil : Text("\(active) bajando")
    }
}
