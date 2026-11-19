import SwiftUI
import OrbitalCore
import OrbitalModels

/// 5 · Trakt (Fernando, 18 nov 2026: TK-V2, TK-C3, TK-L2; prototipo en `docs/producto/guia-trabajos-2026-11-18/onboarding/`).
/// Arriba, tu serie viaja de un aparato al otro (`GuideTraktScene`). «Conectar Trakt» abre el código para trakt.tv/activate
/// (entrar sin salir de la app, TK-C3, queda para cuando se compruebe que Trakt lo permite; el código es su respaldo).
/// Al aprobar, te reconoce: tu inicial, «Listo, <nombre>» y lo que se trajo (vistas, en Mi lista, series que sigues); una
/// cuenta nueva no enseña ceros. «Ahora no» siempre a la mano.
struct OnboardingTrakt: View {
    let step: (current: Int, total: Int)
    let back: (() -> Void)?
    let next: () -> Void
    let skip: () -> Void
    @State private var guide: ModelObserver<OnboardingModel>
    @State private var settings: ModelObserver<SettingsModel>
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsCode = false
    @State private var shown = false

    init(guide: OnboardingModel, step: (current: Int, total: Int), back: (() -> Void)?, next: @escaping () -> Void, skip: @escaping () -> Void) {
        _guide = State(wrappedValue: ModelObserver(guide)); _settings = State(wrappedValue: ModelObserver(guide.settings))
        self.step = step; self.back = back; self.next = next; self.skip = skip
    }

    var body: some View {
        let model = guide.model
        let linked = settings.model.traktLinked
        GuidePage(title: nil, step: step,
                  primary: linked ? Text("Continuar") : Text("Conectar Trakt"),
                  secondary: linked ? nil : Text("Ahora no"),
                  next: { if linked { next() } else { showsCode = true } },
                  skip: next, skipGuide: skip, back: back) {
            if linked { done(model) } else { ask(model) }
        }
        .sheet(isPresented: $showsCode) { TraktCodeSheet(settings: settings.model) }
        .onChange(of: linked) { _, now in
            if now { showsCode = false; Task { await model.traktLinked() } }
        }
        .task { if linked, model.brought == nil { await model.traktLinked() } }
    }

    // MARK: antes de conectar

    @ViewBuilder private func ask(_ model: OnboardingModel) -> some View {
        let caps = env.services.capabilities
        let receiver: GuideTraktScene.Receiver = ThisDevice.platform != "iphone" ? .mac : caps.console ? .tv : .iPad
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            GuideTraktScene(receiver: receiver, watches: caps.instantStreams)
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                (caps.instantStreams ? Text("Sigue donde te quedaste, en cualquier aparato") : Text("Tus series y tus listas, en todos tus aparatos"))
                    .recipe(.display, color: DS.text).fixedSize(horizontal: false, vertical: true)
                Text("Trakt guarda lo que ves y tus listas, y Orbital te recomienda según eso. Es gratis.")
                    .font(DS.Welcome.lead).foregroundStyle(DS.textMuted).fixedSize(horizontal: false, vertical: true)
            }
            .opacity(shown ? 1 : 0).offset(y: shown ? 0 : DS.Welcome.rise)
            if case .failed(let message) = settings.model.trakt {
                DSNotice(verbatim: AppEnvironment.shared.message(message), tone: .warn)
            }
            if case .off = settings.model.trakt {
                DSNotice(text: "Esta copia de la app no trae la aplicación de Trakt: conéctalo después en Ajustes.", tone: .warn)
            }
            Text(ThisDevice.platform != "iphone"
                 ? "Sin Trakt, lo tuyo queda en este iPad. Lo conectas cuando quieras desde Inicio o Ajustes."
                 : "Sin Trakt, lo tuyo queda en este iPhone. Lo conectas cuando quieras desde Inicio o Ajustes.")
                .recipe(.caption, color: DS.textMuted).fixedSize(horizontal: false, vertical: true)
                .opacity(shown ? 1 : 0)
        }
        .task { withAnimation(DS.Motion.enter(reduceMotion)?.delay(0.12)) { shown = true } }
    }

    // MARK: ya conectado: te reconoce (TK-L2)

    @ViewBuilder private func done(_ model: OnboardingModel) -> some View {
        TraktRecognized(name: model.traktName, brought: model.brought)
    }
}

/// TK-C3, respaldo: el código para trakt.tv/activate en una hoja, con «Copiar y abrir Trakt». Se cierra sola al aprobar.
struct TraktCodeSheet: View {
    @State private var settings: ModelObserver<SettingsModel>
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    init(settings: SettingsModel) { _settings = State(wrappedValue: ModelObserver(settings)) }

    var body: some View {
        let open: (code: String, url: URL)? = {
            if case .linking(let code, let url) = settings.model.trakt, let url = URL(string: url) { return (code, url) }
            return nil
        }()
        VStack(spacing: DS.Space.s5) {
            DSSheetHeader(title: Text("Conecta con un código"))
            switch settings.model.trakt {
            case .linking(let code, let url):
                DeviceCodeCard(service: "Trakt", code: code, url: URL(string: url), showsOpen: false)
            case .failed(let message):
                DSNotice(verbatim: AppEnvironment.shared.message(message), tone: .warn)
                Button("Reintentar") { Task { await settings.model.linkTrakt() } }.dsGlassButton()
            default:
                DSLoadingState()
            }
            VStack(spacing: DS.Space.s2) {
                Button { if let open { DeviceCodeCard.copyAndOpen(open.code, open.url, openURL) } } label: {
                    Text("Copiar y abrir Trakt").frame(maxWidth: .infinity)
                }
                .dsPrimaryButton().dsControlSize(.large).disabled(open == nil)
                .accessibilityIdentifier("trakt-code-open")
                Button { dismiss() } label: { Text("Cancelar").frame(maxWidth: .infinity) }.dsGlassButton().dsControlSize(.large)
            }
        }
        .dsSheetContent()
        .fittedSheet()
        .task { if case .unlinked = settings.model.trakt { await settings.model.linkTrakt() } else if case .failed = settings.model.trakt { await settings.model.linkTrakt() } }
    }
}
