import Foundation
import OrbitalAddons
import OrbitalCore
import OrbitalModels
import UIKit
@preconcurrency import UserNotifications

/// Los avisos de que tu Real-Debrid vence (a 14 días, a 3 días y el día que vence), a las 10 de la mañana. Cada uno se
/// programa una sola vez (`DebridReminderBook`); sin permiso de avisos no se pide nada aquí (lo pide Ajustes).
enum DebridReminderNotifier {
    static let thread = "real-debrid"

    /// Al abrir la app: el estado de tu cuenta (el de hoy o uno nuevo) y los avisos que falten.
    @MainActor static func refresh(_ services: Services) async {
        guard services.debrid.hasToken, let status = await services.debrid.status() else { return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let language = services.appSettings.uiLanguage
        for reminder in services.debridReminders.toSchedule(status, now: Date()) {
            let content = UNMutableNotificationContent()
            content.title = title(reminder.daysLeft, language: language)
            content.body = Strings.tr("Renuévalo para no quedarte sin fuentes. No se renueva solo.", language: language)
            content.threadIdentifier = thread
            content.sound = .default
            let when = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.fireAt)
            try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: reminder.id, content: content,
                                                                                    trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: false)))
        }
    }

    static func title(_ daysLeft: Int, language: String) -> String {
        daysLeft == 0 ? Strings.tr("Tu Real-Debrid vence hoy", language: language)
            : String(format: Strings.tr("Tu Real-Debrid vence en %lld días", language: language), daysLeft)
    }
}
