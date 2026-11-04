import SwiftUI
import OrbitalModels

/// La guía de la primera vez, versión 2 (`docs/producto/guia-aprende/propuesta.md`; Fernando, 3 nov 2026): bienvenida (el
/// planeta atrapa siete pósters), lo que te gusta, «¿Qué ya tienes?» y, según lo que contestes, Real-Debrid, Trakt y la TV;
/// luego «Listo». Nada es obligatorio y «Saltar» siempre está arriba. Un paso empuja al siguiente con una sola transición
/// (lo que sale se encoge y se desvanece, lo que entra sube); la luna avanza por el arco de arriba. Si cierras la app a
/// medias, al volver (antes de 24 h) sigues donde ibas.
struct OnboardingView: View {
    typealias Step = OnboardingModel.Step
    @State private var guide: ModelObserver<OnboardingModel>
    @State private var step: Step = .welcome
    @State private var history: [Step] = []
    /// Cuántas veces ha viajado la luna (cada paso hacia adelante).
    @State private var flights = 0
    /// Lo que la guía te explicó: su historia de «Aprende» ya cuenta como vista.
    @State private var explained: Set<OnboardingModel.Piece> = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let done: () -> Void

    init(done: @escaping () -> Void) {
        _guide = State(wrappedValue: ModelObserver(OnboardingModel(AppEnvironment.shared.services)))
        self.done = done
    }

    var body: some View {
        ZStack {
            page(step)
                .id(step)
                .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: DS.Welcome.rise)),
                                        removal: .opacity.combined(with: .scale(scale: DS.Motion.leaveScale))))
        }
        .animation(DS.Motion.enter(reduceMotion) ?? DS.Motion.fade, value: step)
        // El hilo: la luna sale del botón y viaja a su marca del arco (aproximada: el arco ocupa la parte izquierda de arriba).
        .overlay {
            let p = guide.model.position(step)
            GuideMoonFlight(trigger: flights, to: DS.GuideScene.arcStart + DS.GuideScene.arcSpan * Double(p.current) / Double(max(p.total - 1, 1)))
        }
        .tint(DS.accent)
        .interactiveDismissDisabled()
        .task { if let resume = guide.model.resumeStep { step = resume } }
        .onChange(of: step) { _, now in guide.model.reached(now) }
    }

    @ViewBuilder private func page(_ step: Step) -> some View {
        let model = guide.model
        let position = model.position(step)
        let back: (() -> Void)? = history.isEmpty ? nil : { goBack() }
        switch step {
        case .welcome: OnboardingWelcome(guide: model, next: { go(from: step) }, skip: finish)
        case .likes: OnboardingLikes(guide: model, step: position, back: back, next: { go(from: step) }, skip: finish)
        case .have: OnboardingHave(guide: model, step: position, back: back, next: { go(from: step) }, skip: finish)
        case .debrid:
            OnboardingSeeHere(guide: model, step: position, back: back, next: { explained.insert(.debrid); go(from: step) }, skip: finish)
        case .trakt:
            OnboardingTrakt(guide: model, step: position, back: back, next: { explained.insert(.trakt); go(from: step) }, skip: finish)
        case .tv: OnboardingTV(step: position, back: back, next: { go(from: step) }, skip: finish)
        case .done: OnboardingDone(guide: model, finish: finish)
        }
    }

    private func go(from current: Step) {
        guard let next = guide.model.next(after: current) else { return finish() }
        history.append(current)
        step = next
        flights += 1
    }

    private func goBack() {
        guard let previous = history.popLast() else { return }
        step = previous
    }

    private func finish() {
        guide.model.finish(explained: explained)
        done()
    }
}
