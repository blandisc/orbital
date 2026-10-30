import BackgroundTasks
import Foundation
import OrbitalCore
import OrbitalModels
import UIKit
@preconcurrency import UserNotifications

/// El aviso «Ya está para ver» en iOS: uno por episodio, siempre (antes tres o más se juntaban en una lista sin botones de cada
/// uno, 30 oct). La serie arriba, el episodio y su nombre debajo, y la imagen del episodio (o el fondo de la serie, o su póster)
/// que se ve en grande al mantenerlo presionado; sus tres botones: Ver, Ver en la TV y Descargar. Los de una misma serie se
/// apilan juntos. Se revisa al abrir la app y en segundo plano (mejor esfuerzo de iOS).
enum ReleaseNotifier {
    /// Debe coincidir con `BGTaskSchedulerPermittedIdentifiers` de `project.yml`.
    static let identifier = "mx.iracheta.orbital.releases"
    static let category = "orbital.release"
    /// La de antes para varios juntos: ya no se manda, pero se quita al registrar (los avisos viejos no se quedan con sus botones).
    static let oldGroupCategory = "orbital.release.group"
    /// La pila de cada serie: «estrenos.tt…».
    static func thread(_ metaID: String) -> String { "estrenos.\(metaID)" }
    enum Action { static let watch = "release.watch", tv = "release.tv", download = "release.download" }

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            nonisolated(unsafe) let task = task   // BGTask no está marcado seguro entre hilos; se usa solo desde el hilo principal
            schedule()
            let work = Task { @MainActor in
                await check(origin: "ios-estrenos")
                task.setTaskCompleted(success: !Task.isCancelled)
            }
            task.expirationHandler = { work.cancel() }
        }
    }

    /// La siguiente revisión: cada media hora o, si antes sale algo de tu calendario, un rato después de que salga (iOS decide
    /// la hora exacta; esto es lo más pronto que puede ser).
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = nextCheck(now: Date(), nextAiring: UserDefaults.standard.object(forKey: nextAiringKey) as? Date)
        try? BGTaskScheduler.shared.submit(request)
    }

    static func nextCheck(now: Date, nextAiring: Date?) -> Date {
        let regular = now.addingTimeInterval(DS.Timing.releaseRefresh)
        guard let nextAiring else { return regular }
        return min(regular, max(now.addingTimeInterval(DS.Timing.releaseSoonest), nextAiring.addingTimeInterval(DS.Timing.releaseAfterAiring)))
    }
    static let nextAiringKey = "release-next-airing"

    /// La bitácora de las revisiones (`Library/Application Support/release-checks.txt`, se lee desde la Mac con `devicectl … copy
    /// from`): cuándo y desde dónde se revisó, qué faltaba avisar, qué ya tenía fuente, qué no contestó a tiempo y qué se avisó.
    static let logFile = AppFiles.support.appendingPathComponent("release-checks.txt")
    @MainActor private static func log(_ origin: String, _ parts: [String]) {
        let state = switch UIApplication.shared.applicationState { case .active: "abierta"; case .inactive: "inactiva"; default: "fuera" }
        DownloadTimeline.append(([ISO8601DateFormatter().string(from: Date()), origin, state] + parts).joined(separator: " ") + "\n", to: logFile)
    }
    /// Una revisión a la vez (al abrir la app y en segundo plano podían cruzarse y avisar dos veces).
    @MainActor private static var checking = false

    /// Los botones del aviso (se registran una vez, al arrancar).
    /// `tv`: con «Usar con tu Orbital» prendido, el botón «Ver en la TV»; apagado, no sale.
    static func registerCategory(language: String, tv: Bool) {
        let actions = [
            UNNotificationAction(identifier: Action.watch, title: Strings.tr("Ver", language: language), options: [.foreground], icon: UNNotificationActionIcon(systemImageName: "play.fill")),
            UNNotificationAction(identifier: Action.tv, title: Strings.tr("Ver en la TV", language: language), options: [], icon: UNNotificationActionIcon(systemImageName: "tv")),
            UNNotificationAction(identifier: Action.download, title: Strings.tr("Descargar", language: language), options: [], icon: UNNotificationActionIcon(systemImageName: "arrow.down.circle")),
        ].filter { tv || $0.identifier != Action.tv }
        let release = UNNotificationCategory(identifier: category, actions: actions, intentIdentifiers: [],
                                             hiddenPreviewsBodyPlaceholder: Strings.tr("Un estreno ya está para ver", language: language), options: [])
        UNUserNotificationCenter.current().getNotificationCategories { existing in
            UNUserNotificationCenter.current().setNotificationCategories(existing.filter { $0.identifier != category && $0.identifier != oldGroupCategory }.union([release]))
        }
    }

    /// Pide permiso (al encender el aviso en Ajustes). false: no lo diste.
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Revisa y avisa lo que ya se puede ver. `origin`: quién la pidió (para la bitácora).
    @MainActor static func check(origin: String = "app") async {
        let env = AppEnvironment.shared
        guard env.services.appSettings.releaseAlerts else { return }
        guard !checking else { return log(origin, ["ya había una revisión en curso"]) }
        checking = true
        defer { checking = false }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return log(origin, ["sin permiso de avisos"]) }
        let alerts = ReleaseAlerts(env.services)
        let due = await alerts.due()
        let report = alerts.report
        if let next = report.nextAiring { UserDefaults.standard.set(next, forKey: nextAiringKey) } else { UserDefaults.standard.removeObject(forKey: nextAiringKey) }
        // Aunque iOS ya esté por cortar, lo que tiene fuente se avisa (sin la imagen, que es lo que tarda).
        let cut = Task.isCancelled
        if !due.isEmpty {
            await post(due, language: env.services.appSettings.uiLanguage, images: !cut)
            alerts.markSent(due.map(\.id))
        }
        log(origin, [String(format: "%.1fs", report.seconds), "pendientes=\(report.pending)", "con-fuente=\(report.found)",
                     "sin-respuesta=\(report.timedOut)", "avisados=\(due.map(\.id))", cut ? "iOS-cortó" : "",
                     report.nextAiring.map { "siguiente=\(ISO8601DateFormatter().string(from: $0))" } ?? ""].filter { !$0.isEmpty })
    }

    @MainActor static func post(_ due: [ReleaseAlerts.Alert], language: String, images: Bool = true) async {
        let when = ReleaseAlerts.deliverAt(now: Date())
        let trigger = when.map { UNCalendarNotificationTrigger(dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: $0), repeats: false) }
        // Las imágenes a la vez: de una en una, con varios episodios se comían el tiempo que da iOS en segundo plano.
        var art: [String: UNNotificationAttachment] = [:]
        if images {
            await withTaskGroup(of: (String, UNNotificationAttachment?).self) { group in
                for alert in due { group.addTask { (alert.id, await attachment(alert)) } }
                for await (id, image) in group { if let image { art[id] = image } }
            }
        }
        for alert in due {
            let content = UNMutableNotificationContent()
            content.title = alert.show
            let episode = Strings.episode(season: alert.season, episode: alert.episode, language: language)
            content.subtitle = alert.episodeTitle.isEmpty ? episode : "\(episode) · \(alert.episodeTitle)"
            // «Al instante» ya no: todo lo que se avisa se ve al instante (sin eso no se avisa), y era jerga.
            let facts = [alert.quality, alert.minutes.map { "\($0) min" }].compactMap { $0 }
            content.body = ([Strings.tr("Ya está para ver", language: language)] + facts).joined(separator: " · ")
            content.threadIdentifier = thread(alert.metaID)
            content.summaryArgument = alert.show
            content.categoryIdentifier = category
            content.sound = .default
            content.userInfo = ["kind": "series", "id": alert.metaID, "video": alert.id, "title": alert.show]
            if let image = art[alert.id] { content.attachments = [image] }
            try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "release.\(alert.id)", content: content, trigger: trigger))
        }
    }

    /// La imagen del aviso, la primera que se pueda bajar: la del episodio, el fondo de la serie o su póster (a dos avisos de
    /// Avatar les faltó la imagen el 30 oct, que no llegó a tiempo en segundo plano).
    private static func attachment(_ alert: ReleaseAlerts.Alert) async -> UNNotificationAttachment? {
        for url in [alert.still, alert.art, alert.poster].compactMap({ $0 }).filter({ !$0.isEmpty }) {
            if let image = await attachment(url, id: alert.id) { return image }
        }
        return nil
    }

    /// La imagen del aviso: se baja a un archivo temporal (iOS la copia a su lado).
    private static func attachment(_ url: String, id: String) async -> UNNotificationAttachment? {
        guard let link = URL(string: url) else { return nil }
        guard let (data, response) = try? await URLSession.shared.data(for: URLRequest(url: link, timeoutInterval: DS.Timing.releaseImageTimeout)),
              (response as? HTTPURLResponse)?.statusCode ?? 0 < 400, !data.isEmpty else { return nil }
        // Siempre como JPEG y reducida: metahub manda algunas en WebP (que el aviso no enseña) y en 1920 px (de más).
        guard let jpeg = ImagePipeline.downsample(data, maxPixel: DS.Image.notification)?.jpegData(compressionQuality: DS.Image.notificationQuality) else { return nil }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("release-\(id.replacingOccurrences(of: ":", with: "-"))-\(UUID().uuidString).jpg")
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
        default:   // «Ver» o tocar el aviso: ese episodio (antes tocarlo abría la ficha de la serie y había que buscarlo)
            let link: URL? = WidgetLink.play(kind: kind, id: id, video: video)
            if let link { await env.handle(url: link) }
        }
    }
}
