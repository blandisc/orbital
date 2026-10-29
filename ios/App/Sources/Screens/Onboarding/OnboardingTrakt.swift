import SwiftUI
import OrbitalModels

/// 7 · Conecta Trakt: el código grande para escribir en trakt.tv/activate (o abrirlo aquí mismo). Se avanza solo al aprobar.
struct OnboardingTrakt: View {
    let step: (current: Int, total: Int)
    let next: () -> Void
    @State private var guide: ModelObserver<OnboardingModel>
    @State private var settings: ModelObserver<SettingsModel>
    @Environment(\.openURL) private var openURL

    init(guide: OnboardingModel, step: (current: Int, total: Int), next: @escaping () -> Void) {
        _guide = State(wrappedValue: ModelObserver(guide)); _settings = State(wrappedValue: ModelObserver(guide.settings))
        self.step = step; self.next = next
    }

    var body: some View {
        let model = guide.model
        GuidePage(title: Text("Conecta Trakt"),
                  message: Text("Guarda dónde te quedaste, lo que ya viste y tu lista, para que todos tus aparatos sepan lo mismo. Es gratis."),
                  step: step, primaryEnabled: model.canContinue(.trakt), next: next) {
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                switch settings.model.trakt {
                case .linking(let code, let url):
                    GuideCode(code: code)
                    Text("Entra a trakt.tv/activate y escribe este código.").font(DS.TextRecipe.secondary.font).foregroundStyle(DS.textMuted)
                    HStack(spacing: DS.Space.s2) { ProgressView(); Text("Esperando a que lo apruebes…").foregroundStyle(DS.textMuted) }
                    if let link = URL(string: url) { Button("Abrir Trakt", systemImage: "arrow.up.right") { openURL(link) }.buttonStyle(.glass) }
                case .linked(let name):
                    GuidePiece(symbol: "checkmark.circle.fill", tint: DS.success, title: Text("Conectado como \(name)"))
                case .failed(let message):
                    DSNotice(verbatim: AppEnvironment.shared.message(message), tone: .error)
                    Button("Intentar de nuevo") { Task { await settings.model.linkTrakt() } }.buttonStyle(.glass)
                case .unlinked:
                    ProgressView()
                case .off:
                    DSNotice(text: "Esta copia de la app no trae la aplicación de Trakt: conéctalo después en Ajustes.", tone: .warn)
                }
            }
        }
        .task { if case .unlinked = settings.model.trakt { await settings.model.linkTrakt() } }
        .onChange(of: settings.model.traktLinked) { _, linked in if linked { next() } }
    }
}

/// 8 · Trakt conectado: la cuenta y lo que se trajo, para que se note que funcionó.
struct OnboardingTraktDone: View {
    let step: (current: Int, total: Int)
    let next: () -> Void
    @State private var guide: ModelObserver<OnboardingModel>

    init(guide: OnboardingModel, step: (current: Int, total: Int), next: @escaping () -> Void) {
        _guide = State(wrappedValue: ModelObserver(guide)); self.step = step; self.next = next
    }

    var body: some View {
        let model = guide.model
        GuidePage(title: Text("Conectado como \(model.traktName ?? "Trakt")"), step: step, next: next) {
            if let brought = model.brought {
                Text("Trajimos \(String(brought.watched)) vistos y \(String(brought.listed)) en tu lista.").font(DS.TextRecipe.body.font).foregroundStyle(DS.textMuted)
            } else {
                HStack(spacing: DS.Space.s2) { ProgressView(); Text("Trayendo lo tuyo…").foregroundStyle(DS.textMuted) }
            }
        }
        .task { await model.traktLinked() }
    }
}
