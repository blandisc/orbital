import ActivityKit
import SwiftUI
import WidgetKit

@main
struct OrbitalWidgets: WidgetBundle {
    var body: some Widget {
        NextUpWidget()
        DownloadLiveActivity()
        RemoteControlButton()
    }
}

/// Las descargas en la pantalla bloqueada y en la Dynamic Island: qué baja, cuánto lleva y cuántas faltan.
struct DownloadLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DownloadActivityAttributes.self) { context in
            // Pantalla bloqueada: el póster de lo que baja, su nombre y episodio, el avance y cuánto falta.
            HStack(spacing: DS.Space.s3) {
                ActivityPoster(file: context.state.poster, width: DS.Widget.activityPoster)
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(verbatim: context.state.title).font(DS.font(.md, weight: .semibold)).foregroundStyle(DS.paper).lineLimit(1)
                        Spacer(minLength: DS.Space.s2)
                        percent(context.state).font(DS.font(.md, weight: .semibold)).foregroundStyle(DS.paper)
                    }
                    if !context.state.detail.isEmpty {
                        Text(verbatim: context.state.detail).font(DS.font(.sm)).foregroundStyle(DS.onArtSecondary).lineLimit(1)
                    }
                    ProgressView(value: context.state.fraction).tint(context.state.done ? DS.good : DS.paper)
                    Text(subtitle(context.state)).font(DS.font(.sm)).foregroundStyle(DS.onArtSecondary).lineLimit(1)
                }
            }
            .padding()
            .environment(\.locale, Locale(identifier: context.state.language))   // el idioma de la app, no el del sistema
            .environment(\.colorScheme, .dark)   // el fondo es el velo oscuro en los dos modos: letra clara siempre
            .activityBackgroundTint(DS.scrim)
            .activitySystemActionForegroundColor(DS.paper)
        } dynamicIsland: { context in
            DynamicIsland {
                // Abierta: el póster a la izquierda, el porcentaje a la derecha y, abajo, nombre, episodio y avance (con aire:
                // nada se corta contra la orilla de la isla).
                DynamicIslandExpandedRegion(.leading) {
                    ActivityPoster(file: context.state.poster, width: DS.Widget.islandPoster).padding(.leading, DS.Space.s1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    percent(context.state).font(DS.font(.lg, weight: .semibold)).padding(.trailing, DS.Space.s1)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: context.state.title).font(DS.font(.md, weight: .semibold)).lineLimit(1)
                        (context.state.detail.isEmpty ? Text(subtitle(context.state)) : Text(verbatim: context.state.detail))
                            .font(DS.font(.sm)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .environment(\.locale, Locale(identifier: context.state.language))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: DS.Space.s1) {
                        ProgressView(value: context.state.fraction).tint(context.state.done ? DS.good : nil)
                        Text(subtitle(context.state)).font(DS.font(.sm)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .padding(.horizontal, DS.Space.s1)
                    .environment(\.locale, Locale(identifier: context.state.language))
                }
            } compactLeading: {
                ActivityPoster(file: context.state.poster, width: DS.Space.s5)
            } compactTrailing: {
                Gauge(value: context.state.fraction) { EmptyView() }.gaugeStyle(.accessoryCircularCapacity).tint(context.state.done ? DS.good : DS.paper)
            } minimal: {
                Gauge(value: context.state.fraction) { Image(systemName: context.state.done ? "checkmark" : "arrow.down") }.gaugeStyle(.accessoryCircularCapacity)
            }
        }
    }

    private func percent(_ state: DownloadActivityAttributes.ContentState) -> some View {
        Group {
            if state.done { Image(systemName: "checkmark.circle.fill").foregroundStyle(DS.good) }
            else { Text(state.fraction, format: .percent.precision(.fractionLength(0))).monospacedDigit() }
        }
    }

    private func subtitle(_ state: DownloadActivityAttributes.ContentState) -> LocalizedStringKey {
        if state.done { return "Descargado · listo para ver sin conexión" }
        if state.waiting { return "En espera" }   // en pausa o esperando red
        return state.remaining > 1 ? "Orbital · faltan \(state.remaining)" : "Orbital · descargando"
    }
}

/// El póster de lo que baja (lo dejó la app en el App Group); sin él, la flecha de descarga.
struct ActivityPoster: View {
    let file: String?
    let width: CGFloat

    var body: some View {
        if let file, let url = WidgetStore.imageURL(file), let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image).resizable().scaledToFill()
                .frame(width: width, height: width / DS.Poster.aspect)
                .clipShape(RoundedRectangle(cornerRadius: DS.Widget.posterRadius, style: .continuous))
        } else {
            Image(systemName: "arrow.down.circle.fill").font(DS.font(.lg)).foregroundStyle(DS.paper).frame(width: width)
        }
    }
}
