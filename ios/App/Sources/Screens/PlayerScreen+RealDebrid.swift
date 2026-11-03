import SwiftUI
import OrbitalCore
import OrbitalModels
import UserNotifications

/// Real-Debrid en el reproductor: «Pedirlo y avisarme» al rendirse (R7) y «Avisarme» en la tarjeta del siguiente episodio
/// (R8). El aviso sale arriba, sobre el video (abajo están los controles).
extension PlayerScreen {
    private var ui: String { env.services.appSettings.uiLanguage }

    /// R7: lo pide (la versión «por bajar» que ya se abrió, o el mejor torrent que exista) y dice qué contestó Real-Debrid.
    func requestFromPlayer(_ model: PlayerModel) async {
        let off = await askForNotifications()
        guard let outcome = await model.requestFromDebrid() else { return }
        let tr = { (key: String) in Strings.tr(key, language: ui) }
        switch outcome {
        case .requested(let request):
            let warn = [.refused, .tooMany].contains(request.state)
            show(PlayerNotice(title: DebridRequestWords.title(request, tr),
                              detail: off && !warn ? tr("Avisos apagados · actívalos") : DebridRequestWords.detail(request, now: Date(), tr),
                              tone: warn || off ? .warn : .success))
        case .failed(let cause?, _): show(PlayerNotice(title: cause.title(tr), detail: cause.detail(tr), tone: .warn))
        case .failed(nil, let error): show(PlayerNotice(title: error.words(tr), detail: nil, tone: .warn))
        case .nobodyHasIt: show(PlayerNotice(title: UnavailableCause.nobodyHasIt.title(tr), detail: UnavailableCause.nobodyHasIt.detail(tr), tone: .info))
        }
    }

    /// R8 · «Avisarme» en la tarjeta del siguiente episodio: ya está pedido; solo falta el permiso de avisos (si no se dio).
    func notifyWhenReady() async {
        let off = await askForNotifications()
        show(PlayerNotice(title: Strings.tr(off ? "Avisos apagados · actívalos" : "Te aviso cuando esté listo", language: ui), detail: nil, tone: off ? .warn : .success))
    }

    /// Pide permiso de avisos la primera vez (R10). true si están apagados.
    private func askForNotifications() async -> Bool {
        switch await DebridRequestNotifier.permission() {
        case .notDetermined: return !(await DebridRequestNotifier.requestPermission())
        case .denied: return true
        default: return false
        }
    }
}
