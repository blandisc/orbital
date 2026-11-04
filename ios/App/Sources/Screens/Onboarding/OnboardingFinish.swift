import SwiftUI
import OrbitalModels

/// 9 · Todo listo: el resumen y, si tienes TV, dónde
/// conectarla (IOS-18).
struct OnboardingDone: View {
    let finish: () -> Void
    @State private var guide: ModelObserver<OnboardingModel>
    @State private var connectingTV = false
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
                // IOS-18 (como la guía de la TV, que menciona el iPhone como opcional): en el iPad con la invitación de tu
                // iPhone, la tarjeta CX4-A aquí mismo; si no, una línea opcional. Nunca en la Mac (CX1-B).
                if env.services.allowsOrbital {
                    if env.services.pendingInvite != nil {
                        IPadInviteCard { connectingTV = true }
                    } else if !env.services.orbital.isConfigured {
                        Text("¿Tienes Orbital en la TV? Ajustes › Tu Orbital").recipe(.footnote, color: DS.textMuted)
                            .padding(.horizontal, DS.Space.s4)
                            .accessibilityIdentifier("guide-tv-line")
                    }
                }
            }
        }
        .sheet(isPresented: $connectingTV) { OrbitalSetupView() }
    }
}
