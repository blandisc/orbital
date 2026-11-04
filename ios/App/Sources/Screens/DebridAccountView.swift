import SwiftUI
import OrbitalCore
import OrbitalAddons
import OrbitalModels

/// Ajustes › Cuentas › Real-Debrid (D1): quién eres, Premium hasta cuándo y cuántos días quedan, «Renovar», canjear tus
/// puntos (D4, solo aquí y solo si tienes), tu clave («termina en ••••3F2A · nunca se muestra completa»), «Tus pedidos» (D3, un atajo a Descargas › En la nube, RX1-A)
/// y «¿Qué es Real-Debrid?». Sin clave: el campo para pegarla.
struct DebridAccountView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var debrid: ModelObserver<DebridModel>
    @State private var explaining = false
    @State private var confirmRedeem = false
    @State private var confirmRemove = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var changingKey = false
    /// Ya se le preguntó a Real-Debrid en esta visita: al volver de «Tus pedidos» o «Cambiar clave» no se pregunta otra vez
    /// (antes «Conectada ✓» parpadeaba a «Guardada · Revisando…»).
    @State private var checked = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Cómo está tu clave en la página (P6-A).
    enum KeyState { case confirmed, checking, saved, rejected }

    init(debrid: DebridModel) { _debrid = State(wrappedValue: ModelObserver(debrid)) }

    var body: some View {
        let model = debrid.model
        Form {
            DebridSharedPrompt(debrid: model)   // CX2-A: otra cuenta en tus aparatos Apple, solo cuando pasa
            // P6-A: lo que dice la página es verdad al abrirla. Se le pregunta a Real-Debrid si tu clave sirve; mientras, lo
            // último que se supo sin la palomita; nunca «Conectada ✓» de algo que no se confirmó en esta visita.
            if !model.hasToken { connect(model) }
            else {
                switch model.keyCheck {
                case .rejected: rejected(model)
                case .unreachable: unknown(model)   // hay clave, pero Real-Debrid no contestó: nunca el campo vacío
                case .confirmed, .checking:
                    if let status = model.status { account(status, model, key: model.keyCheck == .confirmed ? .confirmed : .checking) }
                    else if model.keyCheck == .checking { checking(model) }
                    else { unknown(model) }
                }
            }
            // IOS-9, IOS-15: la explicación va al final; el problema, si hay, es lo primero que se ve al abrir.
            Section {
                Button { explaining = true } label: {
                    if typeSize.isAccessibilitySize { Text("¿Qué es Real-Debrid?").foregroundStyle(DS.text) }
                    else { TorrentioRowLabel(title: Text("¿Qué es Real-Debrid?"), detail: Text("Por qué arranca al instante y qué cuesta")) }
                }
                .accessibilityIdentifier("debrid-explain")
            }
            .listRowBackground(DS.surface)
        }
        .tint(DS.accent)
        .scrollContentBackground(.hidden).background(Backdrop())
        .navigationTitle(Text(verbatim: "Real-Debrid")).navigationBarTitleDisplayMode(.inline)
        .readableListWidth()
        .sheet(isPresented: $explaining) { DebridExplainer(topic: .realDebrid) { explaining = false } }
        .sheet(isPresented: $confirmRedeem) {   // D4: en su hoja, no en una pregunta del sistema (3 nov, la 1729)
            DebridRedeemSheet(points: Strings.count(model.status?.points ?? 0, language: env.services.appSettings.uiLanguage),
                              redeem: { confirmRedeem = false; Task { await model.redeemPoints() } }, close: { confirmRedeem = false })
        }
        .animation(DS.Motion.base(reduceMotion), value: model.keyCheck)
        .navigationDestination(isPresented: $changingKey) { DebridChangeKeyPage(debrid: model) }
        .sensoryFeedback(.success, trigger: model.redeem) { _, new in new == .done }
        .task { await model.checkShared() }   // CX2-A: la copia de tus aparatos Apple, cada vez que se abre
        .task { guard !checked else { return }; checked = true; await model.recheck() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await model.checkShared() } } }   // TEC-6
        #if DEBUG
        .task { if Demo.isOn, Demo.cx == "remove-choice" { try? await Task.sleep(for: .seconds(1)); confirmRemove = true } }
        .task { if Demo.isOn, Demo.cx == "explain" { try? await Task.sleep(for: .seconds(1)); explaining = true } }
        .task { if Demo.isOn, Demo.cx == "redeem" { try? await Task.sleep(for: .seconds(1)); confirmRedeem = true } }
        #endif
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("debrid-account")
    }

    @ViewBuilder private func account(_ status: DebridStatus, _ model: DebridModel, key: KeyState) -> some View {
        let (state, days) = DebridModel.summary(status, now: Date())
        let usable = Self.canPlay(state)
        // IOS-1 (P1-A, P6-A): vencida o sin Premium, el problema va arriba con su arreglo; nunca «Conectada ✓» debajo.
        accountProblem(status, model, state: state, days: days)
        Section {
            LabeledContent {
                if status.isPremium { Text(verbatim: "Premium").foregroundStyle(DS.textMuted) } else { Text("Sin Premium").foregroundStyle(DS.warning) }
            } label: { Text(verbatim: status.username).foregroundStyle(DS.text) }
            expiry(status).recipe(.footnote, color: Self.isWarning(status) ? DS.warning : DS.textMuted)   // ámbar desde 14 días antes (D1)
            if usable && !Self.isUrgent(state, days) {   // con problema, «Renovar» ya está arriba
                Link(destination: model.renewURL) { Label("Renovar", systemImage: "arrow.up.right") }
            }
            // D4: solo aquí, solo si tienes puntos, y preguntando antes (no se deshace). Nunca en las pruebas: solo la demo.
            if let points = status.points, points > 0, usable && !Self.isUrgent(state, days) { redeemRow(points, model) }
            redeemResult(model)
        } header: { Text("Tu cuenta") } footer: { Text("Te avisamos 14 días antes, 3 días antes y el día que vence. No se renueva solo.") }
        .listRowBackground(DS.surface)
        requestsSection()
        DebridTVSection(debrid: model)   // K1: «Pasar a la TV» y «Usar la de la TV», solo con llave y una TV que las reparte
        keySection(model, usable ? key : .saved, playable: usable)
    }

    /// Vencida, gratuita o a 3 días o menos de vencer: el bloque de problema (P1-A), con «Renovar» o «Hacerla Premium» y, si
    /// tienes puntos, «Canjear puntos». Las palabras son las de la TV (`DEBRID_PROBLEMS`) y del vocabulario (causas 4 y 5).
    @ViewBuilder private func accountProblem(_ status: DebridStatus, _ model: DebridModel, state: DebridStatus.State, days: Int) -> some View {
        let ui = env.services.appSettings.uiLanguage
        let points = status.points ?? 0
        if !Self.canPlay(state) || Self.isUrgent(state, days) {
            Section {
                switch state {
                case .expired:
                    DSProblem(title: Text(verbatim: UnavailableCause.debridExpired.title { Strings.tr($0, language: ui) }), detail: expiry(status)) {
                        renewButton(Text("Renovar"), model)
                        if points > 0 { redeemButton(points) }
                    }
                case .free:
                    DSProblem(title: Text(verbatim: UnavailableCause.noPremium.title { Strings.tr($0, language: ui) }),
                              detail: Text("Sin Premium no arranca nada al instante.")) {
                        renewButton(Text("Hacerla Premium"), model)
                        if points > 0 { redeemButton(points) }
                    }
                case .active, .expiringSoon:   // quedan 3 días o menos: el mismo bloque, tranquilo
                    DSProblem(title: expiry(status), detail: Text("No se renueva solo."), symbol: "calendar.badge.clock") {
                        renewButton(Text("Renovar"), model)
                        if points > 0 { redeemButton(points) }
                    }
                }
            }
            .listRowBackground(DS.surface)
            .accessibilityIdentifier("debrid-account-problem")
        }
    }

    private func renewButton(_ title: Text, _ model: DebridModel) -> some View {
        Link(destination: model.renewURL) { Label { title } icon: { Image(systemName: "arrow.up.right") }.frame(maxWidth: .infinity) }
            .dsProblemFix(primary: true)
            .accessibilityIdentifier("debrid-renew")
    }

    private func redeemButton(_ points: Int) -> some View {
        Button { confirmRedeem = true } label: { Label("Canjear puntos", systemImage: "gift").frame(maxWidth: .infinity) }
            .dsProblemFix(primary: false)
            .accessibilityIdentifier("debrid-redeem")
    }

    /// «Canjear puntos»: un botón del sistema de diseño (no el renglón azul de iOS) con cuántos tienes; abre su hoja (3 nov).
    private func redeemRow(_ points: Int, _ model: DebridModel) -> some View {
        Button { confirmRedeem = true } label: {
            Label { Text("Canjear \(Strings.count(points, language: env.services.appSettings.uiLanguage)) puntos") } icon: { Image(systemName: "gift") }
                .frame(maxWidth: .infinity)
        }
        .dsSecondaryButton().controlSize(.large)
        .disabled(model.redeem == .working)
        .accessibilityIdentifier("debrid-redeem")
    }

    @ViewBuilder private func redeemResult(_ model: DebridModel) -> some View {
        switch model.redeem {
        case .working: DSInlineProgress(text: Text("Canjeando…"))
        case .done: DSNotice(text: "Listo: tus puntos ya son días de Premium.", tone: .success)
        case .failed(let message): DSNotice(verbatim: env.message(message), tone: .warn)
        case .idle: EmptyView()
        }
    }

    /// ¿Sirve para ver? Vencida o gratuita, no: la clave se queda «Guardada», nunca «Conectada ✓».
    static func canPlay(_ state: DebridStatus.State) -> Bool {
        switch state { case .active, .expiringSoon: true; case .expired, .free: false }
    }

    /// A 3 días o menos de vencer (D1: el aviso de 3 días).
    static func isUrgent(_ state: DebridStatus.State, _ days: Int) -> Bool {
        if case .expiringSoon = state { return days <= 3 }
        return false
    }

    /// «Tus pedidos» antes que tu clave: «Quitar» (lo destructivo) va al final de la página, como en iOS.
    private func requestsSection() -> some View {
        Section {
            // D3 y RX1-A: tus pedidos viven en Descargas › En la nube; aquí queda el atajo de siempre, que lleva ahí.
            Button { env.openTab = AppEnvironment.downloadsTab } label: {
                SettingsRow(title: "Tus pedidos", symbol: "icloud.and.arrow.down", tint: DS.ListTint.calendar, value: requestsValue, linked: false)
            }
            .accessibilityIdentifier("settings-debrid-requests")
        } footer: { Text("Están en Descargas › En la nube.") }
        .listRowBackground(DS.surface)
    }

    /// Tu clave: cómo está (sus últimas 4 letras), cambiarla y quitarla. Lo destructivo, al final. Solo `confirmed` (Real-Debrid
    /// la aceptó en esta visita) dice «Conectada» con la palomita verde; mientras pregunta o sin respuesta, «Guardada»; si ya no
    /// la acepta, «No sirve».
    @ViewBuilder private func keySection(_ model: DebridModel, _ key: KeyState, playable: Bool = true) -> some View {
        let tail = model.keyTail ?? "····"
        Section {
            HStack(spacing: DS.Space.s3) {
                switch key {
                case .confirmed: TorrentioRowLabel(title: Text("Conectada"), detail: Text("termina en ••••\(tail) · nunca se muestra completa"))
                case .checking, .saved:
                    TorrentioRowLabel(title: playable ? Text("Guardada") : Text("Guardada · sin Premium"),
                                      detail: Text("termina en ••••\(tail) · nunca se muestra completa"))
                case .rejected: TorrentioRowLabel(title: Text("No sirve"), detail: Text("termina en ••••\(tail) · Real-Debrid ya no la acepta"))
                }
                Spacer(minLength: DS.Space.s2)
                switch key {
                case .confirmed: Image(systemName: "checkmark.circle.fill").foregroundStyle(DS.success).accessibilityHidden(true)
                case .checking: DSInlineProgress(text: Text("Revisando…")).foregroundStyle(DS.textMuted)
                case .rejected: Image(systemName: "xmark.circle").foregroundStyle(DS.warning).accessibilityHidden(true)
                case .saved: EmptyView()
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("debrid-key-state")
            if model.keyCameFromImport {
                Text("Tomé tu clave de Real-Debrid de tu Torrentio").recipe(.footnote, color: DS.textMuted)
            }
            if key != .rejected {   // rechazada, «Cambiar clave» ya es el arreglo de arriba
                NavigationLink { DebridChangeKeyPage(debrid: model) } label: { Text("Cambiar clave").foregroundStyle(DS.text) }
            }
            Button("Quitar", role: .destructive) { confirmRemove = true }
                // CX3-A: solo de este aparato o de todos tus aparatos Apple (los que usaban esta misma clave la quitan al abrir
                // Orbital). IOS-17: en el botón, para que en el iPad la pregunta salga junto a «Quitar» y no pegada arriba.
                .confirmationDialog("¿Quitar tu clave?", isPresented: $confirmRemove, titleVisibility: .visible) {
                    Button(role: .destructive) { Task { await model.remove() } } label: { DeviceWords.text("Solo de este iPhone", mac: "Solo de esta Mac") }
                        .accessibilityIdentifier("debrid-remove-here")
                    Button("De todos tus aparatos Apple", role: .destructive) { Task { await model.remove(everywhere: true) } }
                        .accessibilityIdentifier("debrid-remove-everywhere")
                    Button("Cancelar", role: .cancel) {}
                } message: { Text("Sin ella no hay versiones hasta que pongas otra. Tu cuenta de Real-Debrid no se toca.") }
        } header: { Text("Tu clave") } footer: { Self.keyFooter }
        .listRowBackground(DS.surface)
    }

    /// UX-4, TEC-18 · dónde vive, sin prometer lo que iCloud no asegura.
    @MainActor static var keyFooter: Text {
        DeviceWords.text("Sale de real-debrid.com/apitoken. Se guarda en este iPhone y, si usas el llavero de iCloud, también lo ven tus otros aparatos Apple.",
                         mac: "Sale de real-debrid.com/apitoken. Se guarda en esta Mac y, si usas el llavero de iCloud, también lo ven tus otros aparatos Apple.")
    }

    /// P6-A · Real-Debrid ya no acepta tu clave (la cambiaste en real-debrid.com): se dice arriba, con su arreglo.
    @ViewBuilder private func rejected(_ model: DebridModel) -> some View {
        Section {
            DSProblem(title: Text(verbatim: UnavailableCause.reconnectDebrid.title { Strings.tr($0, language: env.services.appSettings.uiLanguage) }),
                      detail: Text("Tu clave ya no sirve. Pega la nueva de real-debrid.com/apitoken.")) {
                // Un botón (no NavigationLink: en una lista, el enlace ignora el estilo y no se veía).
                Button { changingKey = true } label: { Label("Cambiar clave", systemImage: "key").frame(maxWidth: .infinity) }
                    .dsProblemFix(primary: true)
                    .accessibilityIdentifier("debrid-change-key")
            }
            .accessibilityIdentifier("debrid-reconnect")
        }
        .listRowBackground(DS.surface)
        requestsSection()
        keySection(model, .rejected)
    }

    /// Hay clave y todavía no se sabía nada de tu cuenta: se está preguntando.
    @ViewBuilder private func checking(_ model: DebridModel) -> some View {
        Section {
            DSInlineProgress(text: Text("Revisando tu clave…"))
        } header: { Text("Tu cuenta") }
        .listRowBackground(DS.surface)
        keySection(model, .checking)
    }

    /// Hay clave guardada pero todavía no se sabe de tu cuenta (sin internet o Real-Debrid no contestó): se dice y se
    /// reintenta; la clave sigue ahí (antes salía el campo para pegarla, como si no tuvieras).
    @ViewBuilder private func unknown(_ model: DebridModel) -> some View {
        Section {
            Label { Text("No pude ver tu cuenta") } icon: { Image(systemName: "wifi.exclamationmark").foregroundStyle(DS.warning) }
                .foregroundStyle(DS.text)
            Button("Reintentar") { Task { await model.recheck() } }
                .accessibilityIdentifier("debrid-retry")
        } header: { Text("Tu cuenta") } footer: { Text("Real-Debrid no contestó. Tu clave sigue guardada.") }
        .listRowBackground(DS.surface)
        keySection(model, .saved)
    }

    @ViewBuilder private func connect(_ model: DebridModel) -> some View {
        Section {
            DebridKeyField(debrid: model)
            Link(destination: model.tokenURL) { Label("Sacar tu clave en real-debrid.com/apitoken", systemImage: "arrow.up.right") }
            DebridSharedOffer(debrid: model)   // CX2-A: junto a «Pega tu clave», nunca en su lugar
        } header: { Text("Tu clave") } footer: { Self.keyFooter }
        .listRowBackground(DS.surface)
        DebridTVSection(debrid: model)   // K1: sin clave aquí, «Usar la de la TV»
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

/// «Cambiar clave»: el campo siempre empieza vacío (la clave nunca se muestra completa, ni la que pegaste la vez pasada) y,
/// en cuanto Real-Debrid acepta la nueva, regresa a tu cuenta, que ya dice «Conectada ✓».
private struct DebridChangeKeyPage: View {
    @State private var observer: ModelObserver<DebridModel>
    @Environment(\.dismiss) private var dismiss

    init(debrid: DebridModel) { _observer = State(wrappedValue: ModelObserver(debrid)) }

    var body: some View {
        let model = observer.model
        Form {
            Section {
                DebridKeyField(debrid: model)
                Link(destination: model.tokenURL) { Label("Sacar tu clave en real-debrid.com/apitoken", systemImage: "arrow.up.right") }
            } footer: { DebridAccountView.keyFooter }
            .listRowBackground(DS.surface)
        }
        .tint(DS.accent)
        .scrollContentBackground(.hidden).background(Backdrop())
        .navigationTitle("Cambiar clave").navigationBarTitleDisplayMode(.inline)
        .readableListWidth()
        .onAppear { model.token = "" }
        .sensoryFeedback(.success, trigger: model.check) { _, new in if case .ok = new { true } else { false } }
        .onChange(of: model.check) { _, new in if case .ok = new { dismiss() } }
    }
}
