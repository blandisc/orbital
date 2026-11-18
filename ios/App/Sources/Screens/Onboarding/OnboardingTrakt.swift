import SwiftUI
import OrbitalModels

/// 5 · Trakt (opcional; G5 de la revisión): la escena del avance que viaja del iPhone al iPad, y el código grande para
/// trakt.tv/activate. Al aprobar, lo que se trajo sube con sus números. Si también tienes la TV, va aquí mismo (Q3: una sola
/// pantalla de «tus aparatos»). «Ahora no» siempre a la mano.
struct OnboardingTrakt: View {
    let step: (current: Int, total: Int)
    let back: (() -> Void)?
    let next: () -> Void
    let skip: () -> Void
    @State private var guide: ModelObserver<OnboardingModel>
    @State private var settings: ModelObserver<SettingsModel>
    @Environment(AppEnvironment.self) private var env
    @State private var connectingTV = false
    @Environment(\.openURL) private var openURL

    init(guide: OnboardingModel, step: (current: Int, total: Int), back: (() -> Void)?, next: @escaping () -> Void, skip: @escaping () -> Void) {
        _guide = State(wrappedValue: ModelObserver(guide)); _settings = State(wrappedValue: ModelObserver(guide.settings))
        self.step = step; self.back = back; self.next = next; self.skip = skip
    }

    var body: some View {
        let model = guide.model
        let linked = settings.model.traktLinked
        // G5-B (Fernando, 18 nov 2026): con el código a la vista, el botón grande es «Copiar y abrir Trakt»; «Ahora no» abajo.
        let open: (code: String, url: URL)? = {
            if case .linking(let code, let url) = settings.model.trakt, let url = URL(string: url) { return (code, url) }
            return nil
        }()
        GuidePage(title: Text("Sigue donde te quedaste"),
                  message: Text("Trakt guarda lo que ves en todos tus aparatos. Es gratis."),
                  step: step, primary: linked ? Text("Seguir") : open != nil ? Text("Copiar y abrir Trakt") : Text("Ahora no"),
                  secondary: !linked && open != nil ? Text("Ahora no") : nil,
                  next: { if !linked, let open { DeviceCodeCard.copyAndOpen(open.code, open.url, openURL) } else { next() } },
                  skip: next, skipGuide: skip, back: back) {
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                StorySceneView(scene: .handoff, tint: DS.ListTint.calendar)
                    .frame(height: DS.GuideScene.sceneHeight * DS.Explainer.restScale)
                    .accessibilityHidden(true)
                switch settings.model.trakt {
                case .linking(let code, let url):
                    DeviceCodeCard(service: "Trakt", code: code, url: URL(string: url), showsOpen: false)
                case .linked(let name):
                    GuidePiece(symbol: "checkmark.circle.fill", tint: DS.success, title: Text("Conectado como \(name)"))
                    if let brought = model.brought {
                        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                            Text(verbatim: "\(brought.watched)").recipe(.display, color: DS.text).contentTransition(.numericText())
                            Text("vistos").recipe(.body, color: DS.textMuted)
                            Text(verbatim: "\(brought.listed)").recipe(.display, color: DS.text).contentTransition(.numericText())
                            Text("en tu lista").recipe(.body, color: DS.textMuted)
                        }
                    } else { DSInlineProgress(text: Text("Trayendo lo tuyo…")) }
                case .failed(let message):
                    DSNotice(verbatim: AppEnvironment.shared.message(message), tone: .warn)
                    Button("Reintentar") { Task { await settings.model.linkTrakt() } }.dsGlassButton()
                case .unlinked:
                    DSLoadingState()
                case .off:
                    DSNotice(text: "Esta copia de la app no trae la aplicación de Trakt: conéctalo después en Ajustes.", tone: .warn)
                }
                // Q3: con la TV también, en esta misma pantalla.
                if model.traktWithTV {
                    VStack(alignment: .leading, spacing: DS.Space.s2) {
                        Text("Y tu TV").recipe(.cardTitle, color: DS.text)
                        Button(env.services.orbital.isConfigured ? "Conectada" : "Conectar tu TV", systemImage: "tv.and.mediabox") { connectingTV = true }
                            .dsGlassButton().disabled(env.services.orbital.isConfigured)
                    }
                }
            }
        }
        .sheet(isPresented: $connectingTV) { OrbitalSetupView() }
        .task { if case .unlinked = settings.model.trakt { await settings.model.linkTrakt() } }
        .onChange(of: linked) { _, now in if now { Task { await model.traktLinked() } } }
    }
}
