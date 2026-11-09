import SwiftUI
import OrbitalModels

/// Más subtítulos (opcional): tu cuenta gratuita de OpenSubtitles, con su enlace para crearla. «Ahora no» siempre a la mano;
/// después se conecta en Ajustes › Cuentas.
struct OnboardingSubtitles: View {
    let step: (current: Int, total: Int)
    let back: (() -> Void)?
    let next: () -> Void
    let skip: () -> Void
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let model = env.openSubtitles
        let _ = model.track()
        GuidePage(title: Text("Más subtítulos"),
                  message: Text("Más subtítulos y de tu copia exacta. Conecta tu cuenta gratuita de OpenSubtitles."),
                  step: step, primary: model.connected ? Text("Seguir") : Text("Ahora no"), next: next, skipGuide: skip, back: back) {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                if let account = model.account {
                    GuidePiece(symbol: "checkmark.circle.fill", tint: DS.success, title: Text("Conectado como \(account.username)"))
                } else {
                    OpenSubtitlesForm(model: model)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
    }
}
