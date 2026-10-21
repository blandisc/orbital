import BackgroundTasks
import Foundation

/// Mejor esfuerzo: iOS despierta la app de vez en cuando (cuando él quiere, no cuando se le pide) y ahí se mira lo que la TV
/// dejó para el iPhone («Descargar en el iPhone») para encolarlo en la sesión de descargas de fondo. Lo seguro es abrir la app:
/// el sondeo normal de «Viendo en la TV» atiende la bandeja al momento.
enum InboxBackgroundTask {
    /// Debe coincidir con `BGTaskSchedulerPermittedIdentifiers` de `project.yml`.
    static let identifier = "mx.iracheta.orbital.inbox"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            schedule()   // la siguiente vez, pase lo que pase
            let work = Task { @MainActor in
                // De paso, los estrenos: iOS da pocas oportunidades en segundo plano y cada una cuenta.
                async let releases: Void = ReleaseNotifier.check(origin: "ios-buzon")
                await AppEnvironment.shared.checkTVInbox()
                await releases
                task.setTaskCompleted(success: !Task.isCancelled)
            }
            task.expirationHandler = { work.cancel() }
        }
    }

    /// Pide la siguiente ejecución (al pasar a segundo plano y al terminar cada una).
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: DS.Timing.inboxRefresh)
        try? BGTaskScheduler.shared.submit(request)
    }
}
