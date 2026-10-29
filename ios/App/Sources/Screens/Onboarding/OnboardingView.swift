import SwiftUI
import OrbitalModels

/// La guía de la primera vez (maquetas 1–10 de `docs/producto/desacoplar-stremio/maquetas.html`): un paso empuja al
/// siguiente; Real-Debrid y Trakt no dejan avanzar sin quedar conectados; la TV y Stremio tienen «Ahora no».
struct OnboardingView: View {
    typealias Step = OnboardingModel.Step
    @Environment(AppEnvironment.self) private var env
    @State private var guide: ModelObserver<OnboardingModel>
    @State private var path: [Step] = []
    let done: () -> Void

    init(done: @escaping () -> Void) {
        _guide = State(wrappedValue: ModelObserver(OnboardingModel(AppEnvironment.shared.services)))
        self.done = done
    }

    var body: some View {
        NavigationStack(path: $path) {
            OnboardingWelcome { go(from: .welcome) }
                .navigationDestination(for: Step.self) { step in page(step) }
        }
        .tint(DS.accent)
        .interactiveDismissDisabled()
    }

    @ViewBuilder private func page(_ step: Step) -> some View {
        let model = guide.model
        let position = (current: step.rawValue - 1, total: Step.allCases.count - 1)
        switch step {
        case .welcome: EmptyView()
        case .howItWorks: OnboardingHowItWorks(step: position, showsTV: env.services.allowsOrbital) { go(from: step) }
        case .debridIntro: OnboardingDebridIntro(step: position, signUp: model.debrid.renewURL) { go(from: step) }
        case .debridKey: OnboardingDebridKey(debrid: model.debrid, step: position) { go(from: step) }
        case .addons: OnboardingAddons(addons: model.addons, step: position) { go(from: step) }
        case .trakt: OnboardingTrakt(guide: model, step: position) { go(from: step) }
        case .traktDone: OnboardingTraktDone(guide: model, step: position) { go(from: step) }
        case .tv: OnboardingTV(step: position) { go(from: step) }
        case .done: OnboardingDone(guide: model) { model.finish(); done() }
        }
    }

    /// El paso que sigue (en la Mac, sin el de la TV: ahí la app no se conecta con tu Orbital).
    private func go(from step: Step) {
        guard var next = guide.model.next(after: step) else { return }
        if next == .tv, !env.services.allowsOrbital, let after = guide.model.next(after: .tv) { next = after }
        path.append(next)
    }
}
