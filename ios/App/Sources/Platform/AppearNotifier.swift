import Foundation
import OrbitalCore
import OrbitalModels
@preconcurrency import UserNotifications

/// R15 · el aviso «Ya apareció Nocturne» cuando algo que nadie tenía ya tiene una versión (se revisa una vez al día durante
/// 14 días, `AppearWatch`). Va con los avisos de los pedidos (mismo hilo; tocarlo abre la ficha, `DebridRequestNotifier.handle`)
/// y se revisa cuando iOS despierta la app (`InboxBackgroundTask`) y al volver a ella.
enum AppearNotifier {
    /// Conecta el aviso (una vez, al arrancar).
    @MainActor static func connect(_ env: AppEnvironment) {
        env.services.appearWatch.onAppeared = { entry in await post(entry, language: env.services.appSettings.uiLanguage) }
    }

    /// Revisa lo que toca hoy (al volver a la app o con la app cerrada).
    @MainActor static func check() async { await AppEnvironment.shared.services.appearWatch.check() }

    @MainActor static func post(_ entry: AppearWatch.Entry, language: String) async {
        let status = await DebridRequestNotifier.permission()
        guard status == .authorized || status == .provisional else { return }
        let content = UNMutableNotificationContent()
        content.title = String(format: Strings.tr("Ya apareció %@", language: language), entry.title)
        content.body = Strings.tr("Alguien ya lo comparte · ábrelo para verlo o pedirlo", language: language)
        content.threadIdentifier = DebridRequestNotifier.thread
        content.sound = .default
        content.userInfo = ["kind": entry.kind, "id": entry.metaID, "title": entry.title, "open": "title"]
        let id = DebridRequestNotifier.prefix + "appear." + entry.id
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }
}
