import SwiftUI
import OrbitalCore
import OrbitalModels
import UserNotifications

/// R15 · «Nadie lo tiene todavía en internet» deja de ser un callejón: «Avisarme cuando aparezca» toma el lugar de «Ver»;
/// ya pedido, «Te aviso cuando aparezca» con hasta qué día se revisa y «Ya no avisarme». IOS-8: la primera vez, la misma
/// explicación de los avisos que al pedir algo (P4-A); sin permiso no se promete avisar; y ya activado, tocarlo abre su hoja.
extension TitleView {
    func appearContinueAction(_ model: TitleModel) -> ContinueAction? {
        guard model.unavailableCause == .nobodyHasIt, model.sourceCheck == .none, let videoID = model.continueVideoID else { return nil }
        let watch = env.services.appearWatch
        let _ = watch.track()
        let ui = env.services.appSettings.uiLanguage
        if let entry = watch.entry(kind: model.kind, videoID: videoID) {
            let until = Strings.date(entry.until, .dayMonth, language: ui)
            let notifies = DebridRequestNotifier.canNotify
            let stop: (title: Text, symbol: String, action: () -> Void) = (Text("Ya no avisarme"), "bell.slash", { watch.stop(kind: model.kind, videoID: videoID) })
            // Sin permiso no se promete: el renglón lo dice y la salida de al lado es «Ajustes» («Ya no avisarme», en la hoja).
            let opensNotificationSettings: (title: Text, symbol: String, action: () -> Void) = (Text("Ajustes"), "gear", { DebridRequestNotifier.openSystemSettings() })
            return ContinueAction(title: notifies ? Text("Te aviso cuando aparezca") : Text("Lo reviso cada día"), symbol: notifies ? "bell.fill" : "bell.slash",
                                  version: notifies ? Text("Reviso una vez al día, hasta el \(until)") : Text("Avisos apagados · actívalos"), play: { debridSheet = .appear },
                                  aside: notifies ? stop : opensNotificationSettings, warn: !notifies, tint: artAccent)
        }
        return ContinueAction(title: Text("Avisarme cuando aparezca"), symbol: "bell",
                              version: Text("Nadie lo tiene todavía en internet"),
                              play: { watchForIt(model) }, tint: artAccent)
    }

    private func watchForIt(_ model: TitleModel) {
        Task {
            let permission = await DebridRequestNotifier.permission()
            if permission == .notDetermined { debridSheet = .notifyAppear; return }   // P4-A: primero para qué son
            startWatching(model, permission: permission)
        }
    }

    /// Lo anota (se revisa una vez al día durante 14 días) y dice la verdad: con permiso, «Te aviso…»; sin él, que está
    /// apagado y su arreglo; con «Ahora no», que se revisa pero no hay aviso.
    func startWatching(_ model: TitleModel, permission: UNAuthorizationStatus) {
        guard let videoID = model.continueVideoID else { return }
        env.services.appearWatch.watch(kind: model.kind, metaID: model.metaID, videoID: videoID, title: model.title.isEmpty ? model.originalTitle : model.title)
        if permission == .denied {
            env.notify("Avisos apagados · actívalos", detail: "Lo reviso una vez al día; sin avisos no te puedo decir cuando aparezca.", tone: .warn,
                       actionTitle: "Ajustes") { DebridRequestNotifier.openSystemSettings() }
        } else if DebridRequestNotifier.allows(permission) {
            env.notify("Te aviso cuando aparezca", detail: "Reviso una vez al día durante 14 días", tone: .success)
        } else {
            env.notify("Lo reviso una vez al día", detail: "Ábrelo aquí para ver si ya apareció", tone: .info)
        }
    }

    /// La hoja de «Te aviso cuando aparezca»: hasta cuándo, los avisos si están apagados y «Ya no avisarme».
    @ViewBuilder func appearSheet(_ model: TitleModel) -> some View {
        if let videoID = model.continueVideoID, let entry = env.services.appearWatch.entry(kind: model.kind, videoID: videoID) {
            let until = Strings.date(entry.until, .dayMonth, language: env.services.appSettings.uiLanguage)
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                DSSheetHeader(title: DebridRequestNotifier.canNotify ? Text("Te aviso cuando aparezca") : Text("Lo reviso cada día"),
                              subtitle: Text("Reviso una vez al día, hasta el \(until)"), close: { debridSheet = nil })
                if !DebridRequestNotifier.canNotify {
                    Button { DebridRequestNotifier.openSystemSettings() } label: {
                        Label("Avisos apagados · actívalos", systemImage: "bell.slash").frame(maxWidth: .infinity)
                    }
                    .dsSecondaryButton().controlSize(.large).tint(DS.warning)
                }
                Button(role: .destructive) { env.services.appearWatch.stop(kind: model.kind, videoID: videoID); debridSheet = nil } label: {
                    Label("Ya no avisarme", systemImage: "bell.slash").frame(maxWidth: .infinity)
                }
                .dsSecondaryButton().controlSize(.large)
                .accessibilityIdentifier("appear-stop")
            }
            .dsSheetContent()
            .fittedSheet()
        }
    }
}
