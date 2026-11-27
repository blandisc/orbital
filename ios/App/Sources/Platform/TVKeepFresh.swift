import UIKit
import OrbitalModels

/// Al salir de la app con algo sonando en la TV, el sondeo sigue lo que iOS deja en segundo plano (unos 30 s) y luego se
/// para. Así la actividad en vivo sigue a la TV si cambias de capítulo justo después de salir (26 nov 2026). Para que siga
/// sola todo el tiempo hace falta que la TV la empuje por APNs (decisión LA, docs/producto/control-en-vivo-2026-11-26.html).
@MainActor
enum TVKeepFresh {
    private static var task: UIBackgroundTaskIdentifier = .invalid
    private static var timer: Task<Void, Never>?
    static let seconds: Double = 25

    static func start(_ tv: TVNowModel) {
        stop()
        let app = UIApplication.shared
        task = app.beginBackgroundTask(withName: "orbital.tvNow") { stop(); tv.setActive(false) }
        timer = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            tv.setActive(false)
            stop()
        }
    }

    static func stop() {
        timer?.cancel(); timer = nil
        guard task != .invalid else { return }
        UIApplication.shared.endBackgroundTask(task)
        task = .invalid
    }
}
