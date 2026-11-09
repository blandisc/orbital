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
            // El póster a todo lo alto a la izquierda (2:3, entero); a su derecha el nombre, la barra y los botones (Fernando,
            // 6 nov: con los botones en su propio renglón la actividad pasaba del alto que deja iOS y se comía el póster).
            HStack(alignment: .center, spacing: DS.Space.s3) {
                ActivityPoster(file: context.state.poster, width: DS.Widget.tvPoster)
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    // TV3 (Fernando, 8 nov): el sello de Orbital (la luna, encendida mientras suena) y el turquesa solo en lo de
                    // Orbital: el sello, el botón principal y el avance. El póster sigue mandando.
                    HStack(alignment: .firstTextBaseline) {
                        OrbitalSeal(paused: context.state.paused)
                        Spacer(minLength: DS.Space.s2)
                        subtitle(context.state).font(DS.font(.xs)).foregroundStyle(DS.onArtSecondary).lineLimit(1)
                    }
                    Text(verbatim: context.state.title).font(DS.font(.md, weight: .semibold)).foregroundStyle(DS.paper).lineLimit(1)
                    if !context.state.live { bar(context.state).tint(context.state.paused ? DS.onArtSecondary : DS.accent) }
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
                    ActivityPoster(file: context.state.poster, width: DS.Widget.islandPoster).padding(.leading, DS.Space.s1)
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
                    VStack(spacing: DS.Space.s2) {
                        if !context.state.live { bar(context.state).tint(context.state.paused ? DS.onArtSecondary : DS.accent) }
                        TVButtons(state: context.state)
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
        .tint(state.paused ? DS.onArtSecondary : DS.accent)
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
                .frame(maxWidth: DS.Widget.tvKey).frame(height: DS.Widget.button)
                .background(Capsule().fill(solid ? DS.accent : DS.fillStrong))
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
                Text("En tu TV").font(DS.font(.xs, weight: .bold)).foregroundStyle(paused ? DS.onArtSecondary : DS.accent)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(paused ? Text("En tu TV, en pausa") : Text("En tu TV"))
    }
}
