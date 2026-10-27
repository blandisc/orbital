import ActivityKit
import SwiftUI
import ImageIO
import WidgetKit
import OrbitalCore

@main
struct OrbitalWidgets: WidgetBundle {
    var body: some Widget {
        NextUpWidget()
        DownloadLiveActivity()
        RemoteControlButton()   // el control de tu Orbital en el Centro de control (mismo kind de antes: el que ya estaba puesto revive)
        SimpsonsControlButton()   // «Un Simpson al azar» en el Centro de control
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
                    bar(context.state).tint(context.state.done ? DS.good : DS.paper)
                    subtitleText(context.state).font(DS.font(.sm)).foregroundStyle(DS.onArtSecondary).lineLimit(1)
                }
            }
            .padding()
            .environment(\.locale, Locale(identifier: context.state.language))   // el idioma de la app, no el del sistema
            .environment(\.colorScheme, .dark)   // el fondo es el velo oscuro en los dos modos: letra clara siempre
            .activityBackgroundTint(DS.scrim)
            .activitySystemActionForegroundColor(DS.paper)
            .widgetURL(WidgetLink.downloadsURL)   // tocarla abre Descargas
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
                        bar(context.state).tint(context.state.done ? DS.good : nil)
                        subtitleText(context.state).font(DS.font(.sm)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .padding(.horizontal, DS.Space.s1)
                    .environment(\.locale, Locale(identifier: context.state.language))
                }
            } compactLeading: {
                ActivityPoster(file: context.state.poster, width: DS.Space.s5)
            } compactTrailing: {
                // Un anillo chico y blanco que se llena (con la app en segundo plano, solo hasta la hora estimada); al terminar,
                // la palomita. Antes: el porcentaje, que en segundo plano se volvía una cuenta regresiva que estiraba la isla.
                compactProgress(context.state)
            } minimal: {
                Image(systemName: context.state.done ? "checkmark" : "arrow.down").font(DS.font(.sm, weight: .bold))
                    .foregroundStyle(context.state.done ? DS.good : DS.paper)
            }
            .widgetURL(WidgetLink.downloadsURL)
        }
    }

    /// La barra: con la app en segundo plano avanza sola hasta la hora estimada; si no, la fracción que mandó la app.
    @ViewBuilder private func bar(_ state: DownloadActivityAttributes.ContentState) -> some View {
        if !state.done, let start = state.estimateStart, let end = state.estimateEnd, end > start {
            ProgressView(timerInterval: start...end, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
        } else {
            ProgressView(value: state.fraction)
        }
    }

    /// «Termina como a las 10:42» mientras avanza sola; si no, lo de siempre.
    private func subtitleText(_ state: DownloadActivityAttributes.ContentState) -> Text {
        if !state.done, let end = state.estimateEnd {
            return Text("Termina como a las \(end.formatted(Date.FormatStyle(locale: Locale(identifier: state.language)).hour().minute()))")
        }
        return Text(subtitle(state))
    }

    private func percent(_ state: DownloadActivityAttributes.ContentState) -> some View {
        Group {
            if state.done { Image(systemName: "checkmark.circle.fill").foregroundStyle(DS.good) }
            // En segundo plano, lo que falta en cuenta regresiva (el porcentaje se quedaría congelado), con ancho fijo.
            else if let end = state.estimateEnd, end > .now {
                Text(timerInterval: Date.now...end, countsDown: true).monospacedDigit().multilineTextAlignment(.trailing)
                    .frame(width: DS.Widget.timerWidth, alignment: .trailing)
            }
            else { Text(state.fraction, format: .percent.precision(.fractionLength(0))).monospacedDigit() }
        }
    }

    @ViewBuilder private func compactProgress(_ state: DownloadActivityAttributes.ContentState) -> some View {
        if state.done {
            Image(systemName: "checkmark.circle.fill").font(DS.font(.sm, weight: .bold)).foregroundStyle(DS.good)
        } else {
            Group {
                if let start = state.estimateStart, let end = state.estimateEnd, end > start {
                    ProgressView(timerInterval: start...end, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                } else {
                    ProgressView(value: state.fraction)
                }
            }
            .progressViewStyle(.circular)
            .tint(DS.paper)
            .frame(width: DS.Widget.compactRing, height: DS.Widget.compactRing)
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

    @Environment(\.displayScale) private var scale

    var body: some View {
        // Reducida al tamaño exacto de donde va: una imagen más grande que su lugar (la de 240 px en la isla compacta, de
        // 20 pt) hace que iOS no dibuje la actividad y enseñe solo bloques grises.
        if let file, let url = WidgetStore.imageURL(file), let image = Self.thumbnail(url, maxPixel: width / DS.Poster.aspect * scale) {
            Image(uiImage: image).resizable().scaledToFill()
                .frame(width: width, height: width / DS.Poster.aspect)
                .clipShape(RoundedRectangle(cornerRadius: DS.Widget.posterRadius, style: .continuous))
        } else {
            Image(systemName: "arrow.down.circle.fill").font(DS.font(.lg)).foregroundStyle(DS.paper).frame(width: width)
        }
    }

    static func thumbnail(_ url: URL, maxPixel: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: max(1, Int(maxPixel.rounded(.up)))]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map { UIImage(cgImage: $0) }
    }
}
