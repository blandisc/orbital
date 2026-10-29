import SwiftUI
import OrbitalModels

/// 9 · Tu TV (opcional): cómo conectar tu Orbital con la cámara del iPhone, y una salida clara.
struct OnboardingTV: View {
    let step: (current: Int, total: Int)
    let next: () -> Void
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let connected = env.services.orbital.isConfigured
        GuidePage(title: Text("Tu Orbital en la TV"), message: Text("Conéctala para mandarle lo que ves y usar el iPhone de control."), step: step,
                  primary: connected ? Text("Continuar") : Text("Ya la conecté"), secondary: Text("Ahora no"), next: next, skip: next) {
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                if connected {
                    GuidePiece(symbol: "checkmark.circle.fill", tint: DS.success, title: Text("Tu Orbital está conectada"))
                } else {
                    GuideNumberedStep(number: 1, text: Text("En la TV: Ajustes › iPhone › Conectar")) { EmptyView() }
                    GuideNumberedStep(number: 2, text: Text("Abre la cámara del iPhone y apunta al código de la TV")) { EmptyView() }
                    GuideNumberedStep(number: 3, text: Text("Toca el aviso de Orbital que aparece")) { EmptyView() }
                }
            }
        }
    }
}

/// 10 · Todo listo: el resumen y, aparte y en tono bajo, la invitación a conectar Stremio (opcional).
struct OnboardingDone: View {
    let finish: () -> Void
    @State private var guide: ModelObserver<OnboardingModel>
    @State private var connectingStremio = false
    @Environment(AppEnvironment.self) private var env

    init(guide: OnboardingModel, finish: @escaping () -> Void) {
        _guide = State(wrappedValue: ModelObserver(guide)); self.finish = finish
    }

    var body: some View {
        let model = guide.model
        GuidePage(title: Text("Todo listo"), message: Text("Ya puedes ver lo que quieras."), primary: Text("Empezar a ver"), next: finish) {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                GuidePiece(symbol: "bolt.horizontal.circle", tint: DS.ListTint.flame, title: Text(verbatim: "Real-Debrid"),
                           detail: model.debrid.status.map { DebridWords.text($0) })
                GuidePiece(symbol: "checkmark.seal", tint: DS.ListTint.chart, title: Text(verbatim: "Trakt"),
                           tag: model.traktName.map { Text(verbatim: $0) } ?? Text("Sin conectar"))
                if env.services.allowsOrbital {
                    GuidePiece(symbol: "tv", tint: DS.ListTint.series, title: Text("TV"),
                               tag: env.services.orbital.isConfigured ? Text("Conectada") : Text("No conectada"))
                }
                if env.session.state != .signedIn {
                    VStack(alignment: .leading, spacing: DS.Space.s2) {
                        Text("¿Usas Stremio?").font(DS.TextRecipe.cardTitle.font).foregroundStyle(DS.text)
                        Text("Conéctalo para traer tu historial y que siga al día mientras probamos. Es opcional.")
                            .font(DS.TextRecipe.secondary.font).foregroundStyle(DS.textMuted)
                        Button("Conectar Stremio") { connectingStremio = true }.buttonStyle(.glass)
                    }
                    .padding(DS.Space.s4)
                    .padding(.top, DS.Space.s4)
                }
            }
        }
        .sheet(isPresented: $connectingStremio) { NavigationStack { LoginView(session: env.session) } }
    }
}
