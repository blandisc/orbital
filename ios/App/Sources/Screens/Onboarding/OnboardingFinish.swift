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
        GuidePage(title: Text("Tu TV"), message: Text("Con Orbital en la TV, tu iPhone es su control: mándale lo que veas y sigue aquí lo que suena allá."),
                  step: step, primary: env.services.orbital.isConfigured ? Text("Continuar") : Text("Conectar tu TV"),
                  secondary: Text("Después"),
                  next: { if env.services.orbital.isConfigured { next() } else { connecting = true } },
                  skip: next, skipGuide: skip, back: back) {
            VStack(spacing: DS.Space.s4) {
                GuideArt(symbol: "tv", tint: DS.ListTint.series) { EmptyView() }
                // IOS-18: en el iPad con la invitación de tu iPhone, su tarjeta aquí mismo (CX4-A).
                if env.services.pendingInvite != nil { IPadInviteCard { connecting = true } }
            }
        }
        .sheet(isPresented: $connecting, onDismiss: { if env.services.orbital.isConfigured { next() } }) { OrbitalSetupView() }
    }
}

/// 7 · Listo: los pósters que elegiste bajan a su lugar uno tras otro, con un toque de éxito. «Ir a Inicio».
struct OnboardingDone: View {
    let finish: () -> Void
    @State private var guide: ModelObserver<OnboardingModel>
    @State private var landed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(guide: OnboardingModel, finish: @escaping () -> Void) {
        _guide = State(wrappedValue: ModelObserver(guide)); self.finish = finish
    }

    var body: some View {
        let model = guide.model
        let chosen = model.candidates.filter { model.liked.contains($0.imdb) }
        GuidePage(title: Text("Tu Orbital ya está lista."), message: Text("Te armé Inicio con lo que te gusta. Arriba vas a ver círculos: son historias cortas para conocer cada parte."),
                  primary: Text("Ir a Inicio"), next: finish) {
            VStack(alignment: .leading, spacing: DS.Space.s5) {
                if !chosen.isEmpty {
                    HStack(spacing: DS.Space.s2) {
                        ForEach(Array(chosen.prefix(DS.Welcome.posters).enumerated()), id: \.element.imdb) { i, item in
                            PosterView(url: item.poster, title: item.title, maxPoints: DS.Welcome.posterHeight)
                                .frame(height: DS.Welcome.posterHeight)
                                .offset(y: landed ? 0 : -DS.Welcome.fallFrom / 4)
                                .opacity(landed ? 1 : 0)
                                .animation(DS.Motion.spring(reduceMotion)?.delay(Double(i) * DS.Motion.entranceStep), value: landed)
                        }
                    }
                }
                VStack(spacing: DS.Space.s3) {
                    ForEach(model.pieces, id: \.self) { piece in
                        let words = OnboardingHave.words(piece)
                        GuidePiece(symbol: words.symbol, tint: words.tint, title: Text(words.title),
                                   tag: model.isConnected(piece) ? Text("Conectado") : Text("Después, en Ajustes"))
                    }
                }
            }
        }
        .sensoryFeedback(.success, trigger: landed)
        .task { landed = true }
    }
}
