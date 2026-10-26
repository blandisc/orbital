import Foundation
import UIKit
import UserNotifications
import OrbitalCore

/// Una descarga que se detuvo con la app cerrada: un aviso de iOS («Se detuvo «Dune» · Iba en 62 %») con «Reintentar» y la ficha
/// para elegir otra fuente. Antes no se decía nada: la actividad en vivo solo desaparecía. Con la app abierta no hace falta: se ve en
/// Descargas. Cada falla se avisa una vez (se recuerda aunque iOS cierre y vuelva a abrir la app para terminar las descargas).
@MainActor
enum DownloadFailureNotifier {
    static let category = "orbital.download.failed"
    enum Action { static let retry = "download.retry", title = "download.title" }
    private static let notifiedKey = "download-failed-notified"

    /// Los botones del aviso (se registran una vez, al arrancar).
    static func registerCategory(language: String) {
        let actions = [
            UNNotificationAction(identifier: Action.retry, title: Strings.tr("Reintentar", language: language), options: [],
                                 icon: UNNotificationActionIcon(systemImageName: "arrow.clockwise")),
            UNNotificationAction(identifier: Action.title, title: Strings.tr("Otra versión", language: language), options: [.foreground],
                                 icon: UNNotificationActionIcon(systemImageName: "list.bullet")),
        ]
        let failed = UNNotificationCategory(identifier: category, actions: actions, intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().getNotificationCategories { existing in
            UNUserNotificationCenter.current().setNotificationCategories(existing.filter { $0.identifier != category }.union([failed]))
        }
    }

    /// Cada cambio de la cola: las que pasaron a «falló» desde la última vez se avisan si la app no está a la vista.
    static func observe(_ items: [DownloadItem], language: String) {
        let defaults = UserDefaults.standard
        let notified = Set(defaults.stringArray(forKey: notifiedKey) ?? [])
        let failed = items.filter { $0.state == .failed }
        // Se recuerdan solo las que siguen fallidas: si la reintentas y vuelve a fallar, se avisa otra vez.
        defaults.set(failed.map(\.id), forKey: notifiedKey)
        guard UIApplication.shared.applicationState != .active else { return }
        for item in failed where !notified.contains(item.id) { post(item, language: language) }
    }

    private static func post(_ item: DownloadItem, language: String) {
        let content = UNMutableNotificationContent()
        content.title = String(format: Strings.tr("Se detuvo «%@»", language: language), item.title)
        if !item.subtitle.isEmpty { content.subtitle = item.subtitle }
        if let progress = item.progress, progress > 0 {
            content.body = String(format: Strings.tr("Iba en %lld %%. Puedes reintentar o elegir otra versión.", language: language), Int64(progress * 100))
        } else {
            content.body = Strings.tr("No pudo empezar. Puedes reintentar o elegir otra versión.", language: language)
        }
        content.categoryIdentifier = category
        content.threadIdentifier = "descargas"
        content.sound = .default
        content.userInfo = ["download": item.id, "kind": item.kind, "id": item.metaID]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "download-failed.\(item.id)", content: content, trigger: nil))
    }

    /// Tocar el aviso o uno de sus botones. false: no era de una descarga.
    static func handle(_ response: UNNotificationResponse) async -> Bool {
        let info = response.notification.request.content.userInfo
        guard response.notification.request.identifier.hasPrefix("download-failed."), let download = info["download"] as? String else { return false }
        let env = AppEnvironment.shared
        switch response.actionIdentifier {
        case Action.retry:
            await env.services.downloads.resume(download)
        case Action.title:
            guard let kind = info["kind"] as? String, let id = info["id"] as? String else { break }
            let link: URL? = WidgetLink.title(kind: kind, id: id)   // la ficha, donde eliges otra fuente
            if let link { await env.handle(url: link) }
        default:   // tocar el aviso: Descargas, donde está con su «Reintentar»
            env.openTab = AppEnvironment.downloadsTab
        }
        return true
    }
}
