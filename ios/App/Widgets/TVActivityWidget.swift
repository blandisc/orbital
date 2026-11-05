import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit
import OrbitalCore

/// «Viendo en la TV» en la pantalla bloqueada y en la isla: qué pone tu Orbital, cuánto va (la barra avanza sola), a qué hora
/// termina, y pausa y ±10 s sin desbloquear. Tocarla abre el control.
struct TVLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TVActivityAttributes.self) { context in
            // Póster, nombre y barra arriba; los botones en su renglón abajo (antes iban los cuatro apilados junto al
            // póster y se veía apretado).
            VStack(spacing: DS.Space.s3) {
                HStack(alignment: .center, spacing: DS.Space.s3) {
                    ActivityPoster(file: context.state.poster, width: DS.Widget.activityPoster)
                    VStack(alignment: .leading, spacing: DS.Space.s2) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(verbatim: context.state.title).font(DS.font(.md, weight: .semibold)).foregroundStyle(DS.paper).lineLimit(1)
                            Spacer(minLength: DS.Space.s2)
                            Label { Text("En la TV") } icon: { Image(systemName: "tv") }
                                .font(DS.font(.xs, weight: .semibold)).foregroundStyle(DS.onArtSecondary).labelStyle(.titleAndIcon)
                        }
                        subtitle(context.state).font(DS.font(.sm)).foregroundStyle(DS.onArtSecondary).lineLimit(1)
                        if !context.state.live { bar(context.state).tint(DS.paper) }
                    }
                }
                TVButtons(state: context.state)
            }
            .padding()
            .environment(\.locale, Locale(identifier: context.state.language))
            .environment(\.colorScheme, .dark)
            .activityBackgroundTint(DS.scrim)
            .activitySystemActionForegroundColor(DS.paper)
            .widgetURL(WidgetLink.remoteURL)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ActivityPoster(file: context.state.poster, width: DS.Widget.islandPoster).padding(.leading, DS.Space.s1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Image(systemName: context.state.paused ? "pause.fill" : "tv").font(DS.font(.lg, weight: .semibold)).padding(.trailing, DS.Space.s1)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: context.state.title).font(DS.font(.md, weight: .semibold)).lineLimit(1)
                        subtitle(context.state).font(DS.font(.sm)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .environment(\.locale, Locale(identifier: context.state.language))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: DS.Space.s2) {
                        if !context.state.live { bar(context.state) }
                        TVButtons(state: context.state)
                    }
                    .padding(.horizontal, DS.Space.s1)
                }
            } compactLeading: {
                ActivityPoster(file: context.state.poster, width: DS.Space.s5)
            } compactTrailing: {
                ring(context.state)
            } minimal: {
                Image(systemName: context.state.paused ? "pause.fill" : "tv").font(DS.font(.sm, weight: .bold)).foregroundStyle(DS.paper)
            }
            .widgetURL(WidgetLink.remoteURL)
        }
    }

    /// «T1 · E4 · termina a las 23:21», «En pausa» o el canal en vivo.
    private func subtitle(_ state: TVActivityAttributes.ContentState) -> Text {
        let parts = state.detail.isEmpty ? Text("") : Text(verbatim: state.detail + " · ")
        if state.paused { return Text("\(parts)En pausa") }
        if state.live { return Text("\(parts)En vivo") }
        let time = state.end.formatted(Date.FormatStyle(locale: Locale(identifier: state.language)).hour().minute())
        return Text("\(parts)termina a las \(time)")
    }

    /// La barra: en pausa, quieta; si no, avanza sola entre el inicio y el fin.
    @ViewBuilder private func bar(_ state: TVActivityAttributes.ContentState) -> some View {
        if state.paused || state.end <= state.start {
            ProgressView(value: state.fraction)
        } else {
            ProgressView(timerInterval: state.start...state.end, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
        }
    }

    /// En la isla cerrada: un anillo chico que se llena solo.
    @ViewBuilder private func ring(_ state: TVActivityAttributes.ContentState) -> some View {
        Group {
            if state.paused || state.live || state.end <= state.start {
                ProgressView(value: state.live ? 1 : state.fraction)
            } else {
                ProgressView(timerInterval: state.start...state.end, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
            }
        }
        .progressViewStyle(.circular)
        .tint(DS.paper)
        .frame(width: DS.Widget.compactRing, height: DS.Widget.compactRing)
    }
}

/// −10 s, pausa o seguir, +10 s (en vivo, solo pausa).
private struct TVButtons: View {
    var state: TVActivityAttributes.ContentState
    var body: some View {
        HStack(spacing: DS.Space.s3) {
            if !state.live { key("gobackward.10", action: "back", label: Text("−10 s")) }
            key(state.paused ? "play.fill" : "pause.fill", action: "toggle", label: state.paused ? Text("Continuar") : Text("Pausa"), solid: true)
            if !state.live { key("goforward.10", action: "forward", label: Text("+10 s")) }
        }
        .frame(maxWidth: .infinity)
        .buttonStyle(.plain)
    }

    private func key(_ symbol: String, action: String, label: Text, solid: Bool = false) -> some View {
        Button(intent: TVControlIntent(action: action)) {
            Image(systemName: symbol).font(DS.font(.md, weight: .bold))
                .foregroundStyle(solid ? DS.backdropDeep : DS.paper)
                .frame(width: DS.Widget.tvKey, height: DS.Widget.button)
                .background(Capsule().fill(solid ? DS.paper : DS.fillStrong))
        }
        .accessibilityLabel(label)
    }
}
