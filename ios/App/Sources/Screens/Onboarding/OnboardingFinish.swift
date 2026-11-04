import SwiftUI
import OrbitalCore
import OrbitalModels

/// 6 · Tu TV (solo donde hay TV y solo si dijiste que la tienes): conectarla ahora o después, en Ajustes › Tu Orbital.
struct OnboardingTV: View {
    let step: (current: Int, total: Int)
    let back: (() -> Void)?
    let next: () -> Void
    let skip: () -> Void
    @State private var connecting = false
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        GuidePage(title: Text("Tu iPhone, control de tu TV"), message: Text("Mándale lo que veas y sigue aquí lo que suena allá."),
                  step: step, primary: env.services.orbital.isConfigured ? Text("Continuar") : Text("Conectar tu TV"),
                  secondary: Text("Después"),
                  next: { if env.services.orbital.isConfigured { next() } else { connecting = true } },
                  skip: next, skipGuide: skip, back: back) {
            VStack(spacing: DS.Space.s4) {
                StorySceneView(scene: .sendToTV, tint: DS.ListTint.series)   // G6: el póster vuela a la TV
                    .frame(height: DS.GuideScene.sceneHeight).accessibilityHidden(true)
                // IOS-18: en el iPad con la invitación de tu iPhone, su tarjeta aquí mismo (CX4-A).
                if env.services.pendingInvite != nil { IPadInviteCard { connecting = true } }
            }
        }
        .sheet(isPresented: $connecting, onDismiss: { if env.services.orbital.isConfigured { next() } }) { OrbitalSetupView() }
    }
}

/// 7 · Listo (G7): lo que elegiste baja y arma tu Inicio en miniatura («Porque te gustó…», «Nuevo en tus plataformas»); al
/// tocar «Ir a Inicio», ese Inicio crece a pantalla completa y se vuelve el de verdad. Sin resumen de piezas (Q4).
struct OnboardingDone: View {
    let finish: () -> Void
    @State private var guide: ModelObserver<OnboardingModel>
    @State private var grow = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(guide: OnboardingModel, finish: @escaping () -> Void) {
        _guide = State(wrappedValue: ModelObserver(guide)); self.finish = finish
    }

    var body: some View {
        let model = guide.model
        let liked = model.candidates.filter { model.liked.contains($0.imdb) }
        let more = model.candidates.filter { !model.liked.contains($0.imdb) }
        let logos = model.platforms.filter { model.chosenPlatforms.contains($0.brand) }.compactMap(\.logo)
        GuidePage(title: Text("Tu Orbital ya está lista."), message: Text("Te armé Inicio con lo que te gusta."),
                  primary: Text("Ir a Inicio"), next: go) {
            GuideMiniHome(liked: liked.isEmpty ? Array(more.prefix(3)) : liked, more: Array(more.dropFirst(liked.isEmpty ? 3 : 0)), logos: logos, grow: grow)
        }
        .sensoryFeedback(.success, trigger: grow)
    }

    /// El Inicio en miniatura crece y se desvanece; luego, el de verdad.
    private func go() {
        guard !reduceMotion else { return finish() }
        withAnimation(DS.Motion.enter(reduceMotion)) { grow = true }
        Task { try? await Task.sleep(for: .seconds(DesignTokens.Motion.enter)); finish() }
    }
}
