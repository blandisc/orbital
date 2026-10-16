import ActivityKit
import Foundation
import OrbitalCore

/// Arranca, actualiza y termina la actividad en vivo de las descargas según la cola. iOS limita cuántas
/// actualizaciones acepta: se manda una cuando cambia el título, el estado o avanza al menos un punto.
@MainActor
final class DownloadLiveActivityController {
    private var activity: Activity<DownloadActivityAttributes>?
    private var last: DownloadActivityAttributes.ContentState?
    /// El idioma de la app (Ajustes), para los textos de la actividad.
    var language: () -> String = { "es" }

    func follow(_ downloads: Downloads) async {
        // Si iOS cerró la app con una actividad viva (las descargas siguen en segundo plano), se retoma esa en vez de
        // pedir otra; las de más se terminan. Sin esto, la vieja se quedaba en la pantalla bloqueada con el avance congelado.
        // Solo las vivas: una terminada («Listo», que sigue a la vista un rato) ya no acepta cambios y se deja como está.
        let live = Activity<DownloadActivityAttributes>.activities.filter { $0.activityState == .active || $0.activityState == .stale }
        activity = live.first
        for extra in live.dropFirst() { await extra.end(nil, dismissalPolicy: .immediate) }
        for await items in downloads.makeUpdates() { await update(items) }
    }

    func update(_ items: [DownloadItem]) async {
        let pending = items.filter { $0.state == .downloading || $0.state == .queued || $0.state == .paused }
        guard !pending.isEmpty else { return await finish(items) }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let current = pending.first { $0.state == .downloading } ?? pending[0]
        let written = pending.reduce(Int64(0)) { $0 + $1.writtenBytes }
        let expected = pending.reduce(Int64(0)) { $0 + max($1.expectedBytes ?? 0, $1.writtenBytes) }
        let state = DownloadActivityAttributes.ContentState(
            title: current.subtitle.isEmpty ? current.title : "\(current.title) · \(current.subtitle)",
            fraction: expected > 0 ? min(1, Double(written) / Double(expected)) : 0,
            remaining: pending.count, waiting: !pending.contains { $0.state == .downloading }, language: language())
        if let last, last.title == state.title, last.remaining == state.remaining, last.waiting == state.waiting, last.language == state.language,
           abs(last.fraction - state.fraction) < 0.01 { return }
        last = state
        let content = ActivityContent(state: state, staleDate: nil)
        if let current = activity, current.activityState == .ended || current.activityState == .dismissed { activity = nil }   // la terminó iOS (8 h): otra
        if let activity { await activity.update(content) }
        else { activity = try? Activity.request(attributes: DownloadActivityAttributes(), content: content) }
    }

    /// Ya no hay nada bajando: la actividad dice «Listo» un momento y se va.
    private func finish(_ items: [DownloadItem]) async {
        guard let activity else { return }
        let done = items.filter { $0.state == .done }.max { ($0.finishedAt ?? 0) < ($1.finishedAt ?? 0) }
        let final = DownloadActivityAttributes.ContentState(title: done?.title ?? last?.title ?? "", fraction: 1, remaining: 0, waiting: false, language: language())
        await activity.end(ActivityContent(state: final, staleDate: nil), dismissalPolicy: .default)
        self.activity = nil; last = nil
    }
}
