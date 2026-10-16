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
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.circle.fill").font(.title2).foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(context.state.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Spacer()
                        Text(context.state.fraction, format: .percent.precision(.fractionLength(0))).font(.subheadline).monospacedDigit()
                    }
                    ProgressView(value: context.state.fraction).tint(.white)
                    Text(subtitle(context.state)).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding()
            .activityBackgroundTint(DS.scrim)
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Image(systemName: "arrow.down.circle.fill").font(.title2) }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.fraction, format: .percent.precision(.fractionLength(0))).font(.title3).monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(context.state.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                        ProgressView(value: context.state.fraction)
                        Text(subtitle(context.state)).font(.caption).foregroundStyle(.secondary)
                    }
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
