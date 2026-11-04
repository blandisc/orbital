import SwiftUI
import OrbitalModels

/// 5 · Trakt (opcional): dos renglones de qué es y el código grande para escribir en trakt.tv/activate (o abrirlo aquí mismo).
/// Al aprobar, dice quién eres y lo que se trajo. «Ahora no» siempre a la mano.
struct OnboardingTrakt: View {
    let step: (current: Int, total: Int)
    let back: (() -> Void)?
    let next: () -> Void
    let skip: () -> Void
    @State private var guide: ModelObserver<OnboardingModel>
    @State private var settings: ModelObserver<SettingsModel>
    @Environment(\.openURL) private var openURL

    init(guide: OnboardingModel, step: (current: Int, total: Int), back: (() -> Void)?, next: @escaping () -> Void, skip: @escaping () -> Void) {
        _guide = State(wrappedValue: ModelObserver(guide)); _settings = State(wrappedValue: ModelObserver(guide.settings))
        self.step = step; self.back = back; self.next = next; self.skip = skip
    }

    var body: some View {
        let model = guide.model
        let linked = settings.model.traktLinked
        GuidePage(title: Text("Conecta Trakt"),
                  message: Text("Guarda lo que ves en todos tus aparatos: dónde te quedaste, lo que ya viste y tu lista. Es gratis."),
                  step: step, primary: linked ? Text("Continuar") : Text("Ahora no"), next: next, skipGuide: skip, back: back) {
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                switch settings.model.trakt {
                case .linking(let code, let url):
                    GuideCode(code: code)
                    Text("Entra a trakt.tv/activate y escribe este código.").recipe(.secondary, color: DS.textMuted)
                    DSInlineProgress(text: Text("Esperando a que lo apruebes…"))
                    if let link = URL(string: url) { Button("Abrir Trakt", systemImage: "arrow.up.right") { openURL(link) }.dsGlassButton() }
                case .linked(let name):
                    GuidePiece(symbol: "checkmark.circle.fill", tint: DS.success, title: Text("Conectado como \(name)"),
                               detail: model.brought.map { Text("Trajimos \(String($0.watched)) vistos y \(String($0.listed)) en tu lista.") })
                    if model.brought == nil { DSInlineProgress(text: Text("Trayendo lo tuyo…")) }
                case .failed(let message):
                    DSNotice(verbatim: AppEnvironment.shared.message(message), tone: .warn)
                    Button("Reintentar") { Task { await settings.model.linkTrakt() } }.dsGlassButton()
                case .unlinked:
                    DSLoadingState()
                case .off:
                    DSNotice(text: "Esta copia de la app no trae la aplicación de Trakt: conéctalo después en Ajustes.", tone: .warn)
                }
            }
        }
        .task { if case .unlinked = settings.model.trakt { await settings.model.linkTrakt() } }
        .onChange(of: linked) { _, now in if now { Task { await model.traktLinked() } } }
    }
}
