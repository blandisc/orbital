import Foundation
import OrbitalAddons
import OrbitalCore
import OrbitalModels
import UIKit
@preconcurrency import UserNotifications

/// R10 · el aviso «Ya está T1 E2» cuando Real-Debrid termina un pedido (el título, el episodio y su imagen), con «Ver
/// ahora» y «Ver en la TV» (la TV recibe el título y el episodio, nunca el enlace: los enlaces van atados a quien los
/// pidió). Y R13: «Sigue sin bajar» si un pedido lleva 24 h sin avanzar.
///
/// Cómo se entera: con la app abierta pregunta cada 20 s mientras algo baja (`DebridRequestsModel.follow`); al volver a la
/// app, en cuanto se abre; con la app cerrada, cuando iOS la despierta para la bandeja de la TV (`InboxBackgroundTask`,
/// mejor esfuerzo: puede tardar, y nada si la cerraste a la fuerza). Lo dice la hoja «¿Qué es esto?».
///
/// R11-B (Fernando, 3 nov): sin Actividad en vivo de un pedido por ahora. Con la app cerrada nadie le mandaría el avance y se
/// quedaría quieta; se agrega junto con R14-A (la TV manda el avance por Apple), si se decide.
enum DebridRequestNotifier {
    static let category = "orbital.debrid-ready"
    static let prefix = "debrid."
    static let thread = "real-debrid-pedidos"
    enum Action { static let watch = "debrid.watch", tv = "debrid.tv" }

    /// Los botones del aviso. `tv`: con «Usar con tu Orbital» prendido, «Ver en la TV»; apagado, no sale.
    static func registerCategory(language: String, tv: Bool) {
        let actions = [
            UNNotificationAction(identifier: Action.watch, title: Strings.tr("Ver ahora", language: language), options: [.foreground],
                                 icon: UNNotificationActionIcon(systemImageName: "play.fill")),
            UNNotificationAction(identifier: Action.tv, title: Strings.tr("Ver en la TV", language: language), options: [],
                                 icon: UNNotificationActionIcon(systemImageName: "tv")),
        ].filter { tv || $0.identifier != Action.tv }
        let ready = UNNotificationCategory(identifier: category, actions: actions, intentIdentifiers: [],
                                           hiddenPreviewsBodyPlaceholder: Strings.tr("Real-Debrid terminó tu pedido", language: language), options: [])
        UNUserNotificationCenter.current().getNotificationCategories { existing in
            UNUserNotificationCenter.current().setNotificationCategories(existing.filter { $0.identifier != category }.union([ready]))
        }
    }

    /// ¿Ya se pidió permiso de avisos? (`.notDetermined`: la primera vez que pides algo se explica antes, R10).
    static func permission() async -> UNAuthorizationStatus { await UNUserNotificationCenter.current().notificationSettings().authorizationStatus }

    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Los avisos de la app en Ajustes del iPhone («Avisos apagados · actívalos»).
    @MainActor static func openSystemSettings() {
        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
    }

    /// Conecta los avisos con los pedidos (una vez, al arrancar).
    @MainActor static func connect(_ env: AppEnvironment) {
        let requests = env.services.debridRequests
        requests.onReady = { request in Task { await post(ready: request, language: env.services.appSettings.uiLanguage) } }
        requests.onStalled = { request in Task { await post(stalled: request, language: env.services.appSettings.uiLanguage) } }
    }

    /// Con la app cerrada (iOS la despierta un momento): una sola consulta a Real-Debrid por todos los pedidos en camino.
    @MainActor static func checkInBackground() async {
        let requests = AppEnvironment.shared.services.debridRequests
        guard !requests.active.isEmpty else { return }
        await requests.refresh()
    }

    /// «Ya está T1 E2» (o «Ya está Nocturne»): Real-Debrid terminó de bajarlo.
    @MainActor static func post(ready request: DebridRequest, language: String) async {
        guard await allowed() else { return }
        let content = UNMutableNotificationContent()
        let what = episodeName(request, language: language) ?? request.title
        content.title = String(format: Strings.tr("Ya está %@", language: language), what)
        if request.kind == "series" { content.subtitle = request.title }
        content.body = Strings.tr("Real-Debrid terminó de bajarlo · ábrelo para verlo", language: language)
        content.threadIdentifier = thread
        content.categoryIdentifier = category
        content.sound = .default
        content.userInfo = ["kind": request.kind, "id": request.metaID, "video": request.videoIDs.first ?? request.metaID, "title": request.title]
        if let image = await attachment(request) { content.attachments = [image] }
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: prefix + request.hash, content: content, trigger: nil))
    }

    /// «Sigue sin bajar · ¿probar otra versión?» (R13): una vez, a las 24 h sin avance. Tocarlo abre la ficha.
    @MainActor static func post(stalled request: DebridRequest, language: String) async {
        guard await allowed() else { return }
        let content = UNMutableNotificationContent()
        content.title = [request.title, episodeName(request, language: language)].compactMap { $0 }.joined(separator: " · ")
        content.body = Strings.tr("Sigue sin bajar · ¿probar otra versión?", language: language)
        content.threadIdentifier = thread
        content.userInfo = ["kind": request.kind, "id": request.metaID, "title": request.title, "open": "title"]
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: prefix + "stalled." + request.hash, content: content, trigger: nil))
    }

    /// Tocar el aviso o uno de sus botones. false si no es de los pedidos.
    @MainActor static func handle(_ response: UNNotificationResponse) async -> Bool {
        let info = response.notification.request.content.userInfo
        guard response.notification.request.identifier.hasPrefix(prefix), let kind = info["kind"] as? String, let id = info["id"] as? String else { return false }
        let video = info["video"] as? String
        let title = info["title"] as? String ?? ""
        let env = AppEnvironment.shared
        if response.actionIdentifier == Action.tv {
            // La TV busca su propio enlace: solo el título y el episodio.
            await env.playOnTV(kind: kind, metaID: id, videoID: video, title: title)
        } else if info["open"] as? String == "title" || video == nil {
            if let link = WidgetLink.title(kind: kind, id: id) as URL? { await env.handle(url: link) }
        } else if let link = WidgetLink.play(kind: kind, id: id, video: video) as URL? {
            await env.handle(url: link)
        }
        return true
    }

    private static func allowed() async -> Bool {
        let status = await permission()
        return status == .authorized || status == .provisional
    }

    /// «T1 E2» si es un episodio.
    static func episodeName(_ request: DebridRequest, language: String) -> String? {
        guard request.kind == "series", let episode = request.episode else { return nil }
        return Strings.episode(season: request.season, episode: episode, language: language)
    }

    /// La imagen del aviso: el fondo del título (o su póster), reducida a JPEG.
    private static func attachment(_ request: DebridRequest) async -> UNNotificationAttachment? {
        for format in [ForYou.metahubBackground, ForYou.metahubPoster] {
            guard let link = URL(string: String(format: format, request.metaID)),
                  let (data, response) = try? await URLSession.shared.data(for: URLRequest(url: link, timeoutInterval: DS.Timing.releaseImageTimeout)),
                  (response as? HTTPURLResponse)?.statusCode ?? 0 < 400, !data.isEmpty,
                  let jpeg = ImagePipeline.downsample(data, maxPixel: DS.Image.notification)?.jpegData(compressionQuality: DS.Image.notificationQuality) else { continue }
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("debrid-\(request.hash)-\(UUID().uuidString).jpg")
            guard (try? jpeg.write(to: file)) != nil else { continue }
            return try? UNNotificationAttachment(identifier: request.hash, url: file, options: [UNNotificationAttachmentOptionsTypeHintKey: "public.jpeg"])
        }
        return nil
    }
}
