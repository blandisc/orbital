import BackgroundTasks
import Foundation
import OrbitalCore
import OrbitalModels
import UserNotifications

/// El aviso «Ya está para ver» en iOS: la notificación compacta (la serie y el episodio, «ya está para ver» y sus datos, con
/// el arte del episodio que se ve en grande al mantenerla presionada) y sus tres botones: Ver, Ver en la TV y Descargar.
/// Varios el mismo día se juntan en uno. Se revisa al abrir la app y en segundo plano (mejor esfuerzo de iOS).
enum ReleaseNotifier {
    /// Debe coincidir con `BGTaskSchedulerPermittedIdentifiers` de `project.yml`.
    static let identifier = "mx.iracheta.orbital.releases"
    static let category = "orbital.release"
    static let thread = "estrenos"
    enum Action { static let watch = "release.watch", tv = "release.tv", download = "release.download" }
    /// Tres o más a la vez: uno solo con la lista.
    static let groupFrom = 3

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            schedule()
            let work = Task { @MainActor in
                await check()
                task.setTaskCompleted(success: !Task.isCancelled)
            }
            task.expirationHandler = { work.cancel() }
        }
    }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: DS.Timing.releaseRefresh)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Los botones del aviso (se registran una vez, al arrancar).
    static func registerCategory(language: String) {
        let actions = [
            UNNotificationAction(identifier: Action.watch, title: Strings.tr("Ver", language: language), options: [.foreground], icon: UNNotificationActionIcon(systemImageName: "play.fill")),
            UNNotificationAction(identifier: Action.tv, title: Strings.tr("Ver en la TV", language: language), options: [], icon: UNNotificationActionIcon(systemImageName: "tv")),
            UNNotificationAction(identifier: Action.download, title: Strings.tr("Descargar", language: language), options: [], icon: UNNotificationActionIcon(systemImageName: "arrow.down.circle")),
        ]
        let release = UNNotificationCategory(identifier: category, actions: actions, intentIdentifiers: [],
                                             hiddenPreviewsBodyPlaceholder: Strings.tr("Un estreno ya está para ver", language: language), options: [])
        UNUserNotificationCenter.current().getNotificationCategories { existing in
            UNUserNotificationCenter.current().setNotificationCategories(existing.filter { $0.identifier != category }.union([release]))
        }
    }

    /// Pide permiso (al encender el aviso en Ajustes). false: no lo diste.
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Revisa y avisa lo que ya se puede ver.
    @MainActor static func check() async {
        let env = AppEnvironment.shared
        guard env.services.appSettings.releaseAlerts else { return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let alerts = ReleaseAlerts(env.services)
        let due = await alerts.due()
        guard !due.isEmpty, !Task.isCancelled else { return }
        await post(due, language: env.services.appSettings.uiLanguage)
        alerts.markSent(due.map(\.id))
    }

    @MainActor static func post(_ due: [ReleaseAlerts.Alert], language: String) async {
        let when = ReleaseAlerts.deliverAt(now: Date())
        let trigger = when.map { UNCalendarNotificationTrigger(dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: $0), repeats: false) }
        if due.count >= groupFrom {
            let content = UNMutableNotificationContent()
            content.title = String(format: Strings.tr("%lld estrenos ya para ver", language: language), due.count)
            content.body = due.map { "\($0.show) · " + Strings.episode(season: $0.season, episode: $0.episode, language: language) }.joined(separator: "\n")
            content.threadIdentifier = thread
            content.sound = .default
            content.userInfo = ["kind": "series", "id": due[0].metaID, "video": due[0].id, "title": due[0].show]
            if let image = await attachment(due[0].art, id: "group") { content.attachments = [image] }
            try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "release.group.\(due.map(\.id).joined(separator: ","))", content: content, trigger: trigger))
            return
        }
        for alert in due {
            let content = UNMutableNotificationContent()
            content.title = "\(alert.show) · " + Strings.episode(season: alert.season, episode: alert.episode, language: language)
            let what = alert.episodeTitle.isEmpty ? Strings.tr("Ya está para ver", language: language)
                : String(format: Strings.tr("Ya está para ver · «%@»", language: language), alert.episodeTitle)
            let facts = [alert.instant ? Strings.tr("Al instante", language: language) : nil, alert.quality, alert.minutes.map { "\($0) min" }].compactMap { $0 }
            content.body = ([what] + (facts.isEmpty ? [] : [facts.joined(separator: " · ")])).joined(separator: "\n")
            content.threadIdentifier = thread
            content.categoryIdentifier = category
            content.sound = .default
            content.userInfo = ["kind": "series", "id": alert.metaID, "video": alert.id, "title": alert.show]
            // El arte del episodio: chico en el aviso, grande al mantenerlo presionado.
            if let image = await attachment(alert.art, id: alert.id) { content.attachments = [image] }
            try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "release.\(alert.id)", content: content, trigger: trigger))
        }
    }

    /// La imagen del aviso: se baja a un archivo temporal (iOS la copia a su lado).
    private static func attachment(_ url: String, id: String) async -> UNNotificationAttachment? {
        guard let link = URL(string: url) else { return nil }
        guard let (data, response) = try? await URLSession.shared.data(from: link), (response as? HTTPURLResponse)?.statusCode ?? 0 < 400, !data.isEmpty else { return nil }
        // Siempre como JPEG y reducida: metahub manda algunas en WebP (que el aviso no enseña) y en 1920 px (de más).
        guard let jpeg = ImagePipeline.downsample(data, maxPixel: DS.Image.notification)?.jpegData(compressionQuality: DS.Image.notificationQuality) else { return nil }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("release-\(id.replacingOccurrences(of: ":", with: "-")).jpg")
        guard (try? jpeg.write(to: file)) != nil else { return nil }
        return try? UNNotificationAttachment(identifier: id, url: file, options: [UNNotificationAttachmentOptionsTypeHintKey: "public.jpeg"])
    }

    /// Tocar el aviso o uno de sus botones.
    @MainActor static func handle(_ response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        guard response.notification.request.identifier.hasPrefix("release."), let kind = info["kind"] as? String, let id = info["id"] as? String else { return }
        let video = info["video"] as? String
        let title = info["title"] as? String ?? ""
        let env = AppEnvironment.shared
        switch response.actionIdentifier {
        case Action.tv:
            await env.playOnTV(kind: kind, metaID: id, videoID: video, title: title)
        case Action.download:
            _ = await env.services.queueDownload(kind: kind, metaID: id, videoID: video ?? id, title: title, originalTitle: title, subtitle: "",
                                                 poster: String(format: ForYou.metahubPoster, id))
        case Action.watch:
            let link: URL? = WidgetLink.play(kind: kind, id: id, video: video)
            if let link { await env.handle(url: link) }
        default:   // tocar el aviso: la ficha
            let link: URL? = WidgetLink.title(kind: kind, id: id)
            if let link { await env.handle(url: link) }
        }
    }
}
