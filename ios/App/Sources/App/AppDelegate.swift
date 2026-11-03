import UIKit
import UserNotifications
import WidgetKit   // `ControlCenter`: los botones del Centro de control
import OrbitalCore

/// Lo que iOS le pregunta a la app antes de que exista una vista: arrancar, orientación, avisos y la sesión de descargas.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Se registra antes de que termine de arrancar la app (lo exige iOS).
        ImagePipeline.shared.preconnect()   // lo primero: la conexión con las imágenes, mientras arranca lo demás
        InboxBackgroundTask.register()
        ReleaseNotifier.register()
        OrbitalShortcuts.updateAppShortcutParameters()   // Siri vuelve a leer los títulos que conoce (Los Simpson, siempre)
        OpenRemoteIntent.open = { AppEnvironment.shared.ui.openRemote = true }   // el control del Centro de control abre el control
        OpenSimpsonsIntent.open = { AppEnvironment.shared.ui.openSimpsons = true }   // «Un Simpson al azar» del Centro de control
        // Los botones de los widgets: «Aquí» abre el enlace (reproducir donde ibas) y «En la TV» lo manda a tu Orbital sin abrir la app.
        OpenWidgetLinkIntent.open = { url in Task { await AppEnvironment.shared.handle(url: url) } }
        PlayOnTVIntent.send = { kind, metaID, videoID, name in
            guard ThisDevice.talksToOrbital else { return false }
            do { try await AppEnvironment.shared.services.orbital.play(kind: kind, metaID: metaID, videoID: videoID, title: name); return true }
            catch { return false }
        }
        // Que el Centro de control vuelva a pintar nuestros botones con el ícono de esta versión (su galería guardaba los viejos).
        ControlCenter.shared.reloadAllControls()
        ReleaseNotifier.registerCategory(language: AppEnvironment.shared.services.appSettings.uiLanguage, tv: AppEnvironment.shared.services.orbitalOn)
        DownloadFailureNotifier.registerCategory(language: AppEnvironment.shared.services.appSettings.uiLanguage)
        // «Ya está T1 E2» de tus pedidos a Real-Debrid (R10): sus botones, y quién avisa cuando uno queda listo.
        DebridRequestNotifier.registerCategory(language: AppEnvironment.shared.services.appSettings.uiLanguage, tv: AppEnvironment.shared.services.orbitalOn)
        DebridRequestNotifier.connect(AppEnvironment.shared)
        AppearNotifier.connect(AppEnvironment.shared)   // R15: «Ya apareció…»
        // Los avisos de la app (tu tiempo de juego, la batería de la consola) se ven también con la app abierta.
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // La batería baja ya la dice el aviso de la app: con la app abierta no sale también el de iOS (salían los dos).
        if notification.request.identifier.hasPrefix(CompanionAlerts.batteryPrefix) { return completionHandler([]) }
        completionHandler([.banner, .sound])
    }

    /// Tocar un aviso o uno de sus botones («Ya está para ver»: Ver, Ver en la TV, Descargar; «Ya está T1 E2»: Ver ahora, Ver en la TV).
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        // iOS no marca estos valores como seguros entre hilos; solo se leen una vez en el hilo principal.
        nonisolated(unsafe) let response = response
        nonisolated(unsafe) let completionHandler = completionHandler
        Task { @MainActor in
            if await !DownloadFailureNotifier.handle(response), await !DebridRequestNotifier.handle(response) { await ReleaseNotifier.handle(response) }
            completionHandler()
        }
    }

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask { Orientation.supported }

    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        // Puede llegar antes de que exista ninguna vista: se arma el entorno (que reconecta la sesión de descargas) y se guarda aquí.
        // Solo la sesión de las descargas (la de «Probar la velocidad» se cancela al terminar: no hay nada que entregar).
        guard identifier == BackgroundDownloadTransport.identifier else { return completionHandler() }
        AppEnvironment.shared.transport.backgroundCompletion = completionHandler
    }
}
