@preconcurrency import ActivityKit   // `Activity` no está marcado seguro entre hilos en el SDK; sus métodos sí lo son
import Foundation
import UIKit
import OrbitalCore

/// Arranca, actualiza y termina la actividad en vivo de las descargas según la cola. iOS limita cuántas
/// actualizaciones acepta: se manda una cuando cambia el título, el estado o avanza al menos un punto.
@MainActor
final class DownloadLiveActivityController {
    private var activity: Activity<DownloadActivityAttributes>?
    private var last: DownloadActivityAttributes.ContentState?
    /// El idioma de la app (Ajustes), para los textos de la actividad.
    var language: () -> String = { "es" }
    /// Quitaste la actividad de la pantalla bloqueada: no se vuelve a pedir mientras sigan estas descargas.
    private var dismissedByUser = false
    /// Cómo estaba la actividad la última vez que se actualizó (para distinguir si la quitaste tú o iOS).
    private var seenState: ActivityState?
    /// Cuándo empezó la tanda de ahora (para decir «Descargado» solo de lo que terminó en ella).
    private var batchStarted: Double?
    /// La velocidad (bytes/s, suavizada) y la última muestra, para estimar cuándo termina con la app en segundo plano.
    private var rate: Double = 0
    private var sample: (bytes: Int64, at: Date)?
    private var backgrounded = false
    private var latest: [DownloadItem] = []

    /// La app se va a segundo plano (o vuelve): iOS no la deja mandar avances mientras tanto, así que la barra pasa a avanzar
    /// sola hasta la hora estimada; al volver, los avances de verdad.
    func setBackgrounded(_ value: Bool) async {
        backgrounded = value
        last = nil
        await update(latest)
    }

    func follow(_ downloads: Downloads) async {
        // Si iOS cerró la app con una actividad viva (las descargas siguen en segundo plano), se retoma esa en vez de
        // pedir otra; las de más se terminan. Sin esto, la vieja se quedaba en la pantalla bloqueada con el avance congelado.
        // Solo las vivas: una terminada («Listo», que sigue a la vista un rato) ya no acepta cambios y se deja como está.
        let live = Activity<DownloadActivityAttributes>.activities.filter { $0.activityState == .active || $0.activityState == .stale }
        activity = live.first
        for extra in live.dropFirst() { await extra.end(nil, dismissalPolicy: .immediate) }
        for await items in downloads.makeUpdates() { await update(items) }
    }

    /// Mientras corre la tarea continua de iOS, iOS enseña su propia actividad de la descarga: la de Orbital se quita para no
    /// ver dos (vuelve cuando esa tarea se acaba; si se acaba con la app cerrada, al volver a abrirla).
    private var suppressed = false

    func setSuppressed(_ value: Bool) async {
        guard suppressed != value else { return }
        suppressed = value
        if value, let activity {
            await activity.end(nil, dismissalPolicy: .immediate)
            self.activity = nil; last = nil
        } else if !value {
            await update(latest)
        }
    }

    func update(_ items: [DownloadItem]) async {
        latest = items
        if suppressed { return }
        let pending = items.filter { $0.state == .downloading || $0.state == .queued || $0.state == .paused }
        guard !pending.isEmpty else { return await finish(items) }
        if batchStarted == nil { batchStarted = Date().timeIntervalSince1970 }
        guard ThisDevice.supportsLiveActivities, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let current = pending.first { $0.state == .downloading } ?? pending[0]
        let written = pending.reduce(Int64(0)) { $0 + $1.writtenBytes }
        let expected = pending.reduce(Int64(0)) { $0 + max($1.expectedBytes ?? 0, $1.writtenBytes) }
        let now = Date()
        if !backgrounded {
            if let s = sample, now.timeIntervalSince(s.at) >= 2 {
                let r = max(0, Double(written - s.bytes) / now.timeIntervalSince(s.at))
                rate = rate == 0 ? r : rate * 0.6 + r * 0.4
                sample = (written, now)
            } else if sample == nil || written < sample!.bytes { sample = (written, now) }
        }
        var state = DownloadActivityAttributes.ContentState(
            title: current.title,
            fraction: expected > 0 ? min(1, Double(written) / Double(expected)) : 0,
            remaining: pending.count, waiting: !pending.contains { $0.state == .downloading && !$0.waitingForNetwork }, language: language(),
            detail: current.subtitle, poster: await posterFile(current))
        if backgrounded, rate > 0, expected > written, pending.contains(where: { $0.state == .downloading }) {
            state.estimateStart = now.addingTimeInterval(-Double(written) / rate)
            state.estimateEnd = now.addingTimeInterval(Double(expected - written) / rate)
        }
        if let last, last.title == state.title, last.detail == state.detail, last.poster == state.poster, last.remaining == state.remaining,
           last.waiting == state.waiting, last.language == state.language, abs(last.fraction - state.fraction) < 0.01,
           (last.estimateEnd == nil) == (state.estimateEnd == nil) { return }
        last = state
        let content = ActivityContent(state: state, staleDate: nil)
        if let current = activity {
            switch current.activityState {
            case .ended: activity = nil                                  // la terminó iOS (8 h): se pide otra
            case .dismissed:
                // Viva la última vez y ahora quitada: la quitaste tú (no vuelve hasta la próxima tanda). Si ya había terminado
                // (las 8 h de iOS) y luego iOS la retiró, se pide otra.
                dismissedByUser = seenState == .active || seenState == .stale
                activity = nil
            default: break
            }
        }
        guard !dismissedByUser else { return }
        if let activity { await activity.update(content) }
        else { activity = try? Activity.request(attributes: DownloadActivityAttributes(), content: content) }
        seenState = activity?.activityState
    }

    /// Ya no hay nada bajando: la actividad dice «Listo» un momento y se va.
    private func finish(_ items: [DownloadItem]) async {
        dismissedByUser = false
        seenState = nil
        let started = batchStarted ?? 0
        batchStarted = nil
        guard let activity else { return }
        // «Descargado» solo si algo de esta tanda terminó de verdad; si la borraste o falló, la actividad se va sin decir que sí.
        guard let done = items.filter({ $0.state == .done && ($0.finishedAt ?? 0) >= started }).max(by: { ($0.finishedAt ?? 0) < ($1.finishedAt ?? 0) }) else {
            await activity.end(nil, dismissalPolicy: .immediate)
            self.activity = nil; last = nil
            return
        }
        var final = DownloadActivityAttributes.ContentState(title: done.title, fraction: 1, remaining: 0, waiting: false, language: language(),
                                                           detail: done.subtitle, poster: last?.poster, done: true)
        final.poster = await posterFile(done) ?? final.poster
        await activity.end(ActivityContent(state: final, staleDate: nil), dismissalPolicy: .default)
        self.activity = nil; last = nil
    }

    /// El póster de lo que baja, reducido y guardado en el App Group (la actividad no puede bajar imágenes): una vez por título.
    private func posterFile(_ item: DownloadItem) async -> String? {
        guard let poster = item.poster, let url = URL(string: poster) else { return nil }
        let name = "activity-\(item.metaID.replacingOccurrences(of: "/", with: "-")).jpg"
        guard let target = WidgetStore.imageURL(name) else { return nil }
        if FileManager.default.fileExists(atPath: target.path) { return name }
        guard let image = await ImagePipeline.shared.image(url, maxPixel: DS.Widget.activityPosterPixels),
              let data = image.jpegData(compressionQuality: DesignTokens.Widget.jpegQuality) else { return nil }
        return (try? data.write(to: target, options: .atomic)) != nil ? name : nil
    }
}
