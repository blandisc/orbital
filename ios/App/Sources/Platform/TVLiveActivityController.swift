@preconcurrency import ActivityKit   // `Activity` no está marcado seguro entre hilos en el SDK; sus métodos sí lo son
import Foundation
import UIKit
import OrbitalCore
import OrbitalModels

/// «Viendo en la TV»: arranca, actualiza y termina la actividad en vivo de lo que reproduce tu Orbital, siguiendo lo que la
/// app sabe de la TV (`TVNowModel`). La barra avanza sola en la pantalla bloqueada; solo se manda una actualización cuando
/// cambia el título, la pausa o la posición se aleja de lo esperado (iOS limita cuántas acepta).
@MainActor
final class TVLiveActivityController {
    private var activity: Activity<TVActivityAttributes>?
    private var last: TVActivityAttributes.ContentState?
    private var subscription: ObservableModel.Subscription?
    /// La quitaste de la pantalla bloqueada: no vuelve hasta que la TV ponga otra cosa.
    private var dismissedTitle: String?
    var language: () -> String = { "es" }

    func follow(_ tv: TVNowModel) {
        // Si iOS cerró la app con una viva, se retoma esa; las de más se terminan.
        let live = Activity<TVActivityAttributes>.activities.filter { $0.activityState == .active || $0.activityState == .stale }
        activity = live.first
        Task { for extra in live.dropFirst() { await extra.end(nil, dismissalPolicy: .immediate) } }
        subscription = tv.onChange { [weak self, weak tv] in
            guard let self, let tv else { return }
            Task { await self.update(tv.now, tv: tv) }
        }
        TVControlIntent.run = { [weak tv] action in
            guard let tv, ThisDevice.capabilities.console else { return }
            switch action {
            case "back": await tv.control("skip", delta: -DesignTokens.Widget.tvSkip)
            case "forward": await tv.control("skip", delta: DesignTokens.Widget.tvSkip)
            default: await tv.control("toggle")
            }
        }
    }

    private func update(_ now: OrbitalRemote.NowPlaying?, tv: TVNowModel) async {
        guard let now, now.duration > 0 || now.live else { return await end() }
        guard ThisDevice.supportsLiveActivities, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        if let title = dismissedTitle, title == now.title { return }
        dismissedTitle = nil
        let detail = now.live ? (now.channel ?? "") : AppEnvironment.shared.services.tvEpisodeLabel(now.season, now.episode, now.episodeLabel)
        var state = TVActivityAttributes.ContentState(title: now.title, detail: detail, poster: last?.poster, position: now.position,
                                                      duration: now.duration, measuredAt: tv.fetchedAt, paused: now.paused, live: now.live,
                                                      language: language())
        if let last, last.title == state.title, last.detail == state.detail, last.paused == state.paused, last.live == state.live,
           last.language == state.language, abs(last.end.timeIntervalSince(state.end)) < DesignTokens.Widget.tvDrift,
           state.paused == false || abs(last.position - state.position) < DesignTokens.Widget.tvDrift { return }
        if last?.title != state.title || state.poster == nil { state.poster = await posterFile(now) }
        last = state
        let content = ActivityContent(state: state, staleDate: state.paused || state.live ? nil : state.end)
        if let current = activity {
            switch current.activityState {
            case .ended: activity = nil
            case .dismissed: dismissedTitle = now.title; activity = nil; return
            default: break
            }
        }
        if let activity { await activity.update(content) }
        else { activity = try? Activity.request(attributes: TVActivityAttributes(), content: content) }
    }

    /// La TV ya no reproduce nada: la actividad se va.
    private func end() async {
        last = nil
        dismissedTitle = nil
        guard let activity else { return }
        await activity.end(nil, dismissalPolicy: .immediate)
        self.activity = nil
    }

    /// El póster (o el logo del canal) reducido en el App Group: la actividad no baja imágenes.
    private func posterFile(_ now: OrbitalRemote.NowPlaying) async -> String? {
        guard let art = now.art, let url = URL(string: art) else { return nil }
        let name = "tv-" + WidgetLists.imageFileName(for: now.metaID ?? now.title)
        guard let target = WidgetStore.imageURL(name) else { return nil }
        if FileManager.default.fileExists(atPath: target.path) { return name }
        guard let image = await ImagePipeline.shared.image(url, maxPixel: DS.Widget.activityPosterPixels),
              let data = image.jpegData(compressionQuality: DesignTokens.Widget.jpegQuality) else { return nil }
        return (try? data.write(to: target, options: .atomic)) != nil ? name : nil
    }
}
