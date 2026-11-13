import SwiftUI
import OrbitalCore
import OrbitalModels
import UserNotifications

/// Real-Debrid en el reproductor: «Pedirlo y avisarme» al rendirse (R7) y «Avisarme» en la tarjeta del siguiente episodio
/// (R8). El aviso sale arriba, sobre el video (abajo están los controles).
extension PlayerScreen {
    private var ui: String { env.services.appSettings.uiLanguage }

    /// Los avisos del modelo que no caben en `PlayerScreen`: el subtítulo que no se bajó y «No está en latino al instante»
    /// (13 nov, la ruleta de Los Simpson): tu idioma existe, pero hay que pedirlo; «Versión» lleva a donde se pide.
    func otherNotice(_ value: OrbitalModels.PlayerNotice?, _ ui: String) -> PlayerNotice? {
        switch value {
        case .openSubtitles(let why)?:
            return PlayerNotice(title: Strings.tr("Ese subtítulo no se pudo bajar", language: ui), detail: why, tone: .warn)
        case .yoursOnlyByRequest(let code)?:
            let name = VersionText.inline(code == "es" ? VersionText.spanish(ui) : Streams.versionLanguageName(code, in: ui), ui)
            return PlayerNotice(title: String(format: Strings.tr("No está en %@ al instante", language: ui), name),
                                detail: Strings.tr("Se puede pedir a la nube", language: ui), tone: .info, opensVersion: true)
        default: return nil
        }
    }

    /// «Pedir a la nube» de «Hay latino, pero hay que pedirlo a la nube» en «Versión» del reproductor.
    func requestYoursFromPlayer(_ model: PlayerModel) async {
        await withNotifications { off in await sendFromPlayer(model, off: off, notifies: DebridRequestNotifier.canNotify, yours: true) }
    }

    /// R7: lo pide (la versión «por bajar» que ya se abrió, o el mejor torrent que exista) y dice qué contestó Real-Debrid. La
    /// primera vez, antes de la pregunta de iOS, la misma explicación que en la ficha (P4-A).
    func requestFromPlayer(_ model: PlayerModel) async {
        await withNotifications { off in await sendFromPlayer(model, off: off, notifies: DebridRequestNotifier.canNotify) }
    }

    /// `notifies` (IOS-8): con «Ahora no» no se promete «Te aviso cuando esté listo».
    private func sendFromPlayer(_ model: PlayerModel, off: Bool, notifies: Bool, yours: Bool = false) async {
        guard let outcome = await model.requestFromDebrid(yours: yours) else { return }
        let tr = { (key: String) in Strings.tr(key, language: ui) }
        switch outcome {
        case .requested(let request):
            let warn = [.refused, .tooMany].contains(request.state)
            // PT24: la pantalla del pedido deja de preguntar y dice lo que va a pasar (sin prometer si no hay permiso).
            if !warn, let videoID = model.request?.videoID {
                notices.notifyAnswer = off ? (videoID, .off) : notifies ? (videoID, .promised) : nil
            }
            // P5-A: «Avisos apagados» trae su arreglo, «Ajustes», como en la ficha.
            show(PlayerNotice(title: DebridRequestWords.title(request, tr),
                              detail: off && !warn ? tr("Avisos apagados · actívalos") : DebridRequestWords.detail(request, now: Date(), notifies: notifies, tr),
                              tone: warn || off ? .warn : .success, opensNotificationSettings: off && !warn))
        case .failed(let cause?, _): show(PlayerNotice(title: cause.title(tr), detail: cause.detail(tr), tone: .warn))
        case .failed(nil, let error): show(PlayerNotice(title: error.words(tr), detail: nil, tone: .warn))
        case .nobodyHasIt: show(PlayerNotice(title: UnavailableCause.nobodyHasIt.title(tr), detail: UnavailableCause.nobodyHasIt.detail(tr), tone: .info))
        }
    }

    /// R8 · «Avisarme» en la tarjeta del siguiente episodio: ya está pedido; solo falta el permiso de avisos (si no se dio).
    /// Con «Ahora no» no se promete avisar.
    func notifyWhenReady() async {
        await withNotifications(silentIfNotNow: true) { off in
            show(PlayerNotice(title: Strings.tr(off ? "Avisos apagados · actívalos" : "Te aviso cuando esté listo", language: ui), detail: nil,
                              tone: off ? .warn : .success, opensNotificationSettings: off))
        }
    }

    /// Los avisos antes de seguir: la primera vez (iOS no ha preguntado), la explicación y luego la pregunta (P4-A, R10);
    /// después, lo que ya se sabe. `then` recibe si están apagados.
    private func withNotifications(silentIfNotNow: Bool = false, then: @escaping @MainActor (_ off: Bool) async -> Void) async {
        switch await DebridRequestNotifier.permission() {
        case .notDetermined:
            notices.askNotify = PlayerNoticeState.NotifyAsk { answer in
                if silentIfNotNow, answer == .notDetermined { return }
                await then(answer == .denied)
            }
        case .denied: await then(true)
        default: await then(false)
        }
    }

    #if DEBUG
    /// `-demo-player rd-notify-off`: el aviso de «Avisos apagados» con su arreglo, como si iOS los tuviera apagados.
    func demoNotificationsOff() {
        let tr = { (key: String) in Strings.tr(key, language: ui) }
        show(PlayerNotice(title: UnavailableCause.downloading(percent: 63).title(tr), detail: tr("Avisos apagados · actívalos"), tone: .warn, opensNotificationSettings: true))
    }
    #endif
}
