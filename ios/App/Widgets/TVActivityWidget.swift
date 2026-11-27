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
            // El póster a todo lo alto a la izquierda (2:3, entero); a su derecha el sello, el nombre, la línea de tiempo con lo que
            // va y lo que falta, y los botones grandes sin cápsula, como «Ahora suena» de Apple (Fernando, 26 nov 2026: «los botones
            // son muy pequeños»). Todo cabe en el alto que deja iOS: el póster manda la altura (6 nov).
            HStack(alignment: .center, spacing: DS.Space.s4) {
                ActivityPoster(file: context.state.poster, width: DS.Widget.tvPoster, placeholder: "tv")
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    HStack(alignment: .firstTextBaseline) {
                        OrbitalSeal(paused: context.state.paused)
                        Spacer(minLength: DS.Space.s2)
                        subtitle(context.state).font(DS.font(.sm)).foregroundStyle(DS.onArtSecondary).lineLimit(1)
                    }
                    Text(verbatim: context.state.title).font(DS.font(.lg, weight: .semibold)).foregroundStyle(DS.paper).lineLimit(1)
                    if !context.state.live { TVTimeline(state: context.state) }
                    TVButtons(state: context.state)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(DS.Space.s4)
            .environment(\.locale, Locale(identifier: context.state.language))
            .environment(\.colorScheme, .dark)
            .activityBackgroundTint(DS.scrim)
            .activitySystemActionForegroundColor(DS.paper)
            .widgetURL(WidgetLink.remoteURL)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ActivityPoster(file: context.state.poster, width: DS.Widget.islandTVPoster, placeholder: "tv").padding(.leading, DS.Space.s1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    OrbitalSeal(paused: context.state.paused, compact: true).padding(.trailing, DS.Space.s1)
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
                    VStack(spacing: DS.Space.s1) {
                        if !context.state.live { TVTimeline(state: context.state) }
                        TVButtons(state: context.state, size: DS.Widget.islandKey)
                    }
                    .padding(.horizontal, DS.Space.s1)
                }
            } compactLeading: {
                OrbitalSeal(paused: context.state.paused, compact: true)
            } compactTrailing: {
                ring(context.state)
            } minimal: {
                OrbitalSeal(paused: context.state.paused, compact: true)
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
        .tint(state.paused ? DS.onArtSecondary : DS.accent)
        .frame(width: DS.Widget.compactRing, height: DS.Widget.compactRing)
    }
}

/// La línea de tiempo: la barra (quieta en pausa; si no, avanza sola) con lo que va a la izquierda y lo que falta a la derecha.
private struct TVTimeline: View {
    var state: TVActivityAttributes.ContentState
    var body: some View {
        let moving = !state.paused && state.end > state.start
        HStack(spacing: DS.Space.s2) {
            Group {
                if moving { Text(timerInterval: state.start...state.end, countsDown: false) } else { Text(verbatim: clock(state.position)) }
            }
            .frame(width: DS.Widget.timerWidth, alignment: .leading)
            Group {
                if moving {
                    ProgressView(timerInterval: state.start...state.end, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                } else {
                    ProgressView(value: state.fraction)
                }
            }
            .tint(state.paused ? DS.onArtSecondary : DS.accent)
            Group {
                if moving { Text(timerInterval: state.start...state.end, countsDown: true) } else { Text(verbatim: clock(max(0, state.duration - state.position))) }
            }
            .frame(width: DS.Widget.timerWidth, alignment: .trailing)
        }
        .font(DS.font(.sm, weight: .medium)).monospacedDigit()
        .foregroundStyle(DS.onArtSecondary)
        .lineLimit(1)
    }

    /// «1:02:11» o «12:03».
    private func clock(_ seconds: Double) -> String {
        let s = Int(seconds.rounded()), h = s / 3600, m = s / 60 % 60, r = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, r) : String(format: "%d:%02d", m, r)
    }
}

/// −10 s, pausa o seguir, +10 s (en vivo, solo pausa): símbolos grandes sin cápsula, como los de Apple; la pausa, en el círculo
/// turquesa de Orbital. Cada uno con su objetivo táctil completo.
private struct TVButtons: View {
    var state: TVActivityAttributes.ContentState
    /// El alto de cada botón y el círculo de la pausa: entero en la pantalla bloqueada, más chico en la isla, que tiene un alto
    /// fijo y cortaba la pausa por abajo (Fernando, 26 nov 2026).
    var size: CGFloat = DS.Widget.tvKey
    var body: some View {
        HStack(spacing: 0) {
            if !state.live { key("gobackward.10", action: "back", label: Text("−10 s")) }
            key(state.paused ? "play.fill" : "pause.fill", action: "toggle", label: state.paused ? Text("Continuar") : Text("Pausa"), solid: true)
            if !state.live { key("goforward.10", action: "forward", label: Text("+10 s")) }
        }
        .frame(maxWidth: .infinity)
        .buttonStyle(.plain)
    }

    private func key(_ symbol: String, action: String, label: Text, solid: Bool = false) -> some View {
        Button(intent: TVControlIntent(action: action)) {
            ZStack {
                if solid { Circle().fill(DS.accent).frame(width: size, height: size) }
                Image(systemName: symbol).font(DS.font(solid || size < DS.Widget.tvKey ? .lg : .xl, weight: .semibold))
                    .foregroundStyle(solid ? DS.backdropDeep : DS.paper)
            }
            .frame(maxWidth: .infinity).frame(height: size)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
    }
}


/// TV3: el sello de Orbital en «Viendo en la TV»: la luna del logo (encendida mientras suena, apagada en pausa) y «En tu TV» en
/// turquesa. `compact`: solo la luna, para la isla.
struct OrbitalSeal: View {
    var paused = false
    var compact = false

    var body: some View {
        HStack(spacing: DS.Space.s1) {
            Image("orbital.mark")
                .font(DS.font(compact ? .md : .sm, weight: .semibold))
                .foregroundStyle(paused ? DS.onArtSecondary : DS.accent)
                .shadow(color: paused ? .clear : DS.accent.opacity(DS.Widget.sealGlow), radius: DS.Space.s1)
            if !compact {
                Text("En tu TV").font(DS.font(.sm, weight: .semibold)).foregroundStyle(paused ? DS.onArtSecondary : DS.accent)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(paused ? Text("En tu TV, en pausa") : Text("En tu TV"))
    }
}
