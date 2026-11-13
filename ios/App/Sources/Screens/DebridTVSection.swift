import SwiftUI
import OrbitalCore
import OrbitalModels

/// K1 · Ajustes › Cuentas › Real-Debrid › «Tu TV». IOS-6 (canvas de Conectar, «se compara la cuenta, no la clave»): primero
/// qué cuenta usa tu TV. Si es la misma, una línea con la palomita y nada que hacer; si son distintas, la pregunta con sus tres
/// salidas («Pasar la de este iPhone · Usar la de la TV · Dejar cada una»); si la TV no tiene, «Pasar a la TV». Solo con la
/// conexión propia de este aparato y una TV que la da (`DebridModel.canShareWithTV`); en Plus o sin TV no aparece. La clave
/// nunca se enseña: solo la cuenta y sus últimas letras.
struct DebridTVSection: View {
    @State private var debrid: ModelObserver<DebridModel>
    @Environment(AppEnvironment.self) private var env

    init(debrid: DebridModel) { _debrid = State(wrappedValue: ModelObserver(debrid)) }

    var body: some View {
        let model = debrid.model
        let _ = env.services.track()
        if model.canShareWithTV {
            Section {
                DebridTVCompare(debrid: model)
            } header: { Text("Tu TV") } footer: { Text("Real-Debrid revisa la clave antes de guardarla. Nunca se muestra completa.") }
            .listRowBackground(DS.surface)
            .onAppear { model.resetTVShare() }
            .task { await model.compareWithTV() }
        }
    }
}

/// La comparación y sus salidas, en renglones (va en «Tu TV» de Real-Debrid y en «Ya se conocen» al conectar).
struct DebridTVCompare: View {
    @State private var observer: ModelObserver<DebridModel>
    private var debrid: DebridModel { observer.model }
    @State private var confirmPass = false
    @State private var confirmUse = false
    @Environment(AppEnvironment.self) private var env

    init(debrid: DebridModel) { _observer = State(wrappedValue: ModelObserver(debrid)) }

    var body: some View {
        let model = debrid
        Group {
            switch model.tvAccount {
            case .unknown, .checking: DSInlineProgress(text: Text("Revisando la cuenta de tu TV…"))
            case .unreachable:
                line("tv.slash", DS.warning, Text("Tu TV no contestó"), Text("No pude ver qué cuenta usa."))
                Button("Reintentar") { Task { await model.compareWithTV() } }
            case .same(let user):
                line("checkmark.circle.fill", DS.success, Text("Tu TV usa la cuenta \(user)"), Text("La misma que este iPhone."))
                    .accessibilityIdentifier("debrid-tv-same")
            case .tvHasNone:
                line("tv.and.mediabox", DS.textMuted, Text("Tu TV todavía no tiene Real-Debrid"), nil)
                if model.hasToken { passButton(Text("Pasar a la TV"), Text("Tu TV usará la cuenta de este iPhone")) }
            case .tvKeyBroken:
                line("exclamationmark.triangle", DS.warning, Text("Tu TV no pudo confirmar su cuenta"), Text("Real-Debrid no reconoce su clave o no contestó."))
                if model.hasToken { passButton(Text("Pasar a la TV"), Text("Tu TV usará la cuenta de este iPhone")) }
            case .onlyTV(let user):
                line("tv.and.mediabox", DS.textMuted, Text("Tu TV usa la cuenta \(user)"), nil)
                useButton(Text("Usar la de la TV"), Text("Este iPhone usará la cuenta \(user)"))
            case .different(let tv, let mine, let apart):
                line("person.2", apart ? DS.textMuted : DS.warning, Text("Tu TV usa la cuenta \(tv)"),
                     apart ? Text("Cada uno usa la suya.") : Text("Este iPhone usa \(mine). ¿Cuál quieres en los dos?"))
                    .accessibilityIdentifier("debrid-tv-different")
                passButton(Text("Pasar la de este iPhone"), Text("Tu TV usará \(mine)"))
                useButton(Text("Usar la de la TV"), Text("Este iPhone usará \(tv)"))
                if !apart {
                    Button { model.keepAccountsApart() } label: { actionLabel(Text("Dejar cada una"), Text("No se vuelve a preguntar"), "equal.circle") }
                        .accessibilityIdentifier("debrid-tv-apart")
                }
            }
            result(model)
        }
        .confirmationDialog(passTitle(model), isPresented: $confirmPass, titleVisibility: .visible) {   // ds-exception: confirma reemplazar la clave de la TV (una sola acción)
            Button("Pasar a la TV") { Task { await model.passToTV() } }
            Button("Cancelar", role: .cancel) {}
        } message: { Text("Si Real-Debrid no la reconoce, tu TV se queda con la que tenía.") }
        .confirmationDialog(useTitle(model), isPresented: $confirmUse, titleVisibility: .visible) {   // ds-exception: confirma reemplazar la clave del iPhone (una sola acción)
            Button("Usar la de la TV") { Task { await model.useTVKey() } }
            Button("Cancelar", role: .cancel) {}
        } message: { Text("Reemplaza la de este iPhone si Real-Debrid la acepta con Premium.") }
    }

    /// «Tu TV usará la cuenta fernando»: se dice la cuenta, no las letras de la clave (IOS-6).
    private func passTitle(_ model: DebridModel) -> Text {
        if let mine = model.status?.username, model.hasToken { return Text("Tu TV usará la cuenta \(mine)") }
        return Text("Tu TV usará esta clave")
    }

    private func useTitle(_ model: DebridModel) -> Text {
        switch model.tvAccount {
        case .onlyTV(let user), .different(let user, _, _): Text("Este iPhone usará la cuenta \(user)")
        default: Text("Este iPhone usará la clave de tu TV")
        }
    }

    private func line(_ symbol: String, _ tint: Color, _ title: Text, _ detail: Text?) -> some View {
        IconBeside(symbol: symbol, color: tint) {
            title.recipe(.body, color: DS.text)
            if let detail { detail.recipe(.footnote, color: DS.textMuted) }
        }
        .accessibilityElement(children: .combine)
    }

    private func passButton(_ title: Text, _ detail: Text) -> some View {
        Button { confirmPass = true } label: { actionLabel(title, detail, "arrow.up.forward.app") }
            .disabled(debrid.tvShare == .working)
            .accessibilityIdentifier("debrid-pass-to-tv")
    }

    private func useButton(_ title: Text, _ detail: Text) -> some View {
        Button { if debrid.hasToken { confirmUse = true } else { Task { await debrid.useTVKey() } } } label: { actionLabel(title, detail, "arrow.down.app") }
            .disabled(debrid.tvShare == .working)
            .accessibilityIdentifier("debrid-use-tv")
    }

    /// Un renglón que se toca se ve como tal (IOS-17): el color de lo interactivo, con su ícono.
    private func actionLabel(_ title: Text, _ detail: Text, _ symbol: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 0) {
                title.foregroundStyle(DS.accent)
                detail.recipe(.footnote, color: DS.textMuted)
            }
        } icon: { Image(systemName: symbol).foregroundStyle(DS.accent) }
    }

    @ViewBuilder private func result(_ model: DebridModel) -> some View {
        switch model.tvShare {
        case .idle: EmptyView()
        case .working: DSInlineProgress(text: Text("Hablando con tu TV…"))
        case .passed(let tv):
            DSNotice(text: tv.premium ? "Tu TV ya usa tu clave · termina en \(tv.tail) · Premium" : "Tu TV ya usa tu clave · termina en \(tv.tail)", tone: .success)
                .accessibilityIdentifier("debrid-tv-result")
        case .used: DSNotice(text: "Listo: este iPhone ya usa la clave de tu TV", tone: .success).accessibilityIdentifier("debrid-tv-result")
        case .failed(let why): DSNotice(verbatim: env.message(why), tone: .warn).accessibilityIdentifier("debrid-tv-result")
        }
    }
}
