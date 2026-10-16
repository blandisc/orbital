import ActivityKit
import SwiftUI
import WidgetKit

@main
struct OrbitalWidgets: WidgetBundle {
    var body: some Widget {
        NextUpWidget()
        DownloadLiveActivity()
    }
}

/// Las descargas en la pantalla bloqueada y en la Dynamic Island: qué baja, cuánto lleva y cuántas faltan.
struct DownloadLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DownloadActivityAttributes.self) { context in
            HStack(spacing: DS.Space.s3) {
                Image(systemName: "arrow.down.circle.fill").font(DS.font(.xl)).foregroundStyle(DS.paper)
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    HStack {
                        Text(context.state.title).font(DS.font(.md, weight: .semibold)).foregroundStyle(DS.paper).lineLimit(1)
                        Spacer()
                        Text(context.state.fraction, format: .percent.precision(.fractionLength(0))).font(DS.font(.md)).monospacedDigit().foregroundStyle(DS.paper)
                    }
                    ProgressView(value: context.state.fraction).tint(DS.paper)
                    Text(subtitle(context.state)).font(DS.font(.sm)).foregroundStyle(DS.onArtSecondary)
                }
            }
            .padding()
            .environment(\.locale, Locale(identifier: context.state.language))   // el idioma de la app, no el del sistema
            .environment(\.colorScheme, .dark)   // el fondo es el velo oscuro en los dos modos: letra clara siempre
            .activityBackgroundTint(DS.scrim)
            .activitySystemActionForegroundColor(DS.paper)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Image(systemName: "arrow.down.circle.fill").font(DS.font(.xl)) }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.fraction, format: .percent.precision(.fractionLength(0))).font(DS.font(.xl)).monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: DS.Space.s1) {
                        Text(context.state.title).font(DS.font(.md, weight: .semibold)).lineLimit(1)
                        ProgressView(value: context.state.fraction)
                        Text(subtitle(context.state)).font(DS.font(.sm)).foregroundStyle(.secondary)
                    }
                    .environment(\.locale, Locale(identifier: context.state.language))
                }
            } compactLeading: {
                Image(systemName: "arrow.down.circle.fill")
            } compactTrailing: {
                Text(context.state.fraction, format: .percent.precision(.fractionLength(0))).monospacedDigit()
            } minimal: {
                Gauge(value: context.state.fraction) { Image(systemName: "arrow.down") }.gaugeStyle(.accessoryCircularCapacity)
            }
        }
    }

    private func subtitle(_ state: DownloadActivityAttributes.ContentState) -> LocalizedStringKey {
        if state.waiting { return "En pausa" }
        return state.remaining > 1 ? "Orbital · faltan \(state.remaining)" : "Orbital · descargando"
    }
}
