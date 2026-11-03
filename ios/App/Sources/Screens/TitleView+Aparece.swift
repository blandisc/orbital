import SwiftUI
import OrbitalCore
import OrbitalModels

/// R15 · «Nadie lo tiene todavía en internet» deja de ser un callejón: «Avisarme cuando aparezca» toma el lugar de «Ver»;
/// ya pedido, «Te aviso cuando aparezca» con hasta qué día se revisa y «Ya no avisarme».
extension TitleView {
    func appearContinueAction(_ model: TitleModel) -> ContinueAction? {
        guard model.unavailableCause == .nobodyHasIt, model.sourceCheck == .none, let videoID = model.continueVideoID else { return nil }
        let watch = env.services.appearWatch
        let _ = watch.track()
        let ui = env.services.appSettings.uiLanguage
        if let entry = watch.entry(kind: model.kind, videoID: videoID) {
            return ContinueAction(title: Text("Te aviso cuando aparezca"), symbol: "bell.fill",
                                  version: Text("Reviso una vez al día, hasta el \(Strings.date(entry.until, .dayMonth, language: ui))"),
                                  play: {}, aside: (Text("Ya no avisarme"), "bell.slash", { watch.stop(kind: model.kind, videoID: videoID) }), tint: artAccent)
        }
        return ContinueAction(title: Text("Avisarme cuando aparezca"), symbol: "bell",
                              version: Text("Nadie lo tiene todavía en internet"),
                              play: { watchForIt(model, videoID: videoID) }, tint: artAccent)
    }

    private func watchForIt(_ model: TitleModel, videoID: String) {
        Task {
            if await DebridRequestNotifier.permission() == .notDetermined { _ = await DebridRequestNotifier.requestPermission() }
            env.services.appearWatch.watch(kind: model.kind, metaID: model.metaID, videoID: videoID, title: model.title.isEmpty ? model.originalTitle : model.title)
            if await DebridRequestNotifier.permission() == .denied {
                env.notify("Te aviso cuando aparezca", detail: "Avisos apagados · actívalos", tone: .warn, actionTitle: "Ajustes") { DebridRequestNotifier.openSystemSettings() }
            } else {
                env.notify("Te aviso cuando aparezca", detail: "Reviso una vez al día durante 14 días", tone: .success)
            }
        }
    }
}
