import SwiftUI
import UIKit
import WidgetKit
import OrbitalCore

// MARK: Datos

struct NextUpEntry: TimelineEntry {
    var date: Date
    var snapshot: WidgetSnapshot
}

/// Una sola entrada: el widget no calcula nada con el tiempo. La app avisa (`WidgetCenter.reloadTimelines`) al actualizar Inicio o
/// al cerrar el reproductor; si no avisa, se pide recarga a las 6 horas.
struct NextUpProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextUpEntry { NextUpEntry(date: Date(), snapshot: .sample) }

    func getSnapshot(in context: Context, completion: @escaping (NextUpEntry) -> Void) {
        let stored = WidgetStore.load()
        completion(NextUpEntry(date: Date(), snapshot: context.isPreview && stored?.items.isEmpty != false ? .sample : stored ?? .empty))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextUpEntry>) -> Void) {
        let now = Date()
        completion(Timeline(entries: [NextUpEntry(date: now, snapshot: WidgetStore.load() ?? .empty)], policy: .after(now.addingTimeInterval(DS.Widget.fallbackRefresh))))
    }
}

// MARK: Widget

struct NextUpWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetStore.kind, provider: NextUpProvider()) { entry in
            NextUpView(entry: entry)
                .environment(\.locale, Locale(identifier: entry.snapshot.language))
        }
        .configurationDisplayName("Lo siguiente para ti")
        .description("Sigue viendo donde ibas.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

struct NextUpView: View {
    var entry: NextUpEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemMedium: MediumView(snapshot: entry.snapshot)
        case .accessoryRectangular: LockView(snapshot: entry.snapshot)
        default: SmallView(snapshot: entry.snapshot)
        }
    }
}

// MARK: Piezas

/// La imagen reducida que dejó la app (nada de red aquí).
private func poster(_ item: WidgetSnapshot.Item) -> UIImage? {
    item.imageFile.flatMap { WidgetStore.imageURL($0) }.flatMap { UIImage(contentsOfFile: $0.path) }
}

private func artTone(_ item: WidgetSnapshot.Item) -> Color { DS.Palette.color(hex: item.tint) ?? DS.surface }

/// El fondo con el tinte del arte (el mismo recurso que el fondo de las pantallas).
private func tintedBackground(_ color: Color) -> some View {
    LinearGradient(colors: [color, color.mix(with: DS.bg, by: DS.Backdrop.tintFloor)], startPoint: .top, endPoint: .bottom)
}

/// La barra de avance fina.
private struct ProgressLine: View {
    var fraction: Double
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(DS.track)
                Capsule().fill(DS.primary).frame(width: proxy.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: DS.Widget.progressHeight)
        .accessibilityHidden(true)
    }
}

/// El póster a sangre (o el tono del arte si no hay imagen), alineado arriba para que no se corte la cara.
private struct Art: View {
    var item: WidgetSnapshot.Item
    var body: some View {
        ZStack {
            tintedBackground(artTone(item))
            if let image = poster(item) {
                // La imagen solo rellena el espacio que le toca (no lo agranda): si no, empuja el texto fuera del widget.
                Color.clear.overlay(alignment: .top) { Image(uiImage: image).resizable().scaledToFill() }.clipped()
            }
        }
    }
}

/// El velo inferior: del arte limpio a casi opaco, para que el título se lea.
private var bottomScrim: some View {
    LinearGradient(stops: [.init(color: .clear, location: DS.Widget.scrimStart), .init(color: DS.scrimStrong, location: 1)], startPoint: .top, endPoint: .bottom)
}

/// Título en una línea, «T2 · E6 · quedan 20 min» y la barra de avance.
private struct Caption: View {
    var item: WidgetSnapshot.Item
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            Text(item.title).font(DS.font(.md, weight: .semibold)).foregroundStyle(DS.text).lineLimit(1)
            if !item.detail.isEmpty { Text(item.detail).font(DS.font(.xs)).foregroundStyle(DS.textMuted).lineLimit(1) }
            if let progress = item.progress { ProgressLine(fraction: progress) }
        }
    }
}

/// Nada pendiente: el ícono de Orbital y un enlace a la app.
private struct EmptyState: View {
    var body: some View {
        VStack(spacing: DS.Space.s2) {
            Image("Logo").resizable().frame(width: DS.Size.touchTarget, height: DS.Size.touchTarget).clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
            Text("Nada pendiente").font(DS.font(.md, weight: .semibold)).foregroundStyle(DS.text)
            Text("Abrir Orbital").font(DS.font(.xs)).foregroundStyle(DS.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(URL(string: "\(WidgetLink.scheme)://"))
        .containerBackground(for: .widget) { DS.bg }
    }
}

// MARK: Tamaños

private struct SmallView: View {
    var snapshot: WidgetSnapshot
    var body: some View {
        if let item = snapshot.items.first {
            VStack(alignment: .leading) {
                Spacer(minLength: 0)
                Caption(item: item)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetURL(item.link)
            .containerBackground(for: .widget) { ZStack { Art(item: item); bottomScrim } }
        } else {
            EmptyState()
        }
    }
}

private struct MediumView: View {
    var snapshot: WidgetSnapshot

    var body: some View {
        if let first = snapshot.items.first {
            HStack(spacing: DS.Space.s3) {
                Link(destination: first.link ?? URL(fileURLWithPath: "/")) {
                    ZStack(alignment: .bottomLeading) {
                        Art(item: first)
                        bottomScrim
                        Caption(item: first).padding(DS.Space.s2)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
                }
                VStack(spacing: DS.Space.s2) {
                    rows(Array(snapshot.items.dropFirst()))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .containerBackground(for: .widget) { tintedBackground(artTone(first)) }
        } else {
            EmptyState()
        }
    }

    /// Dos renglones: los siguientes de «Seguir viendo»; con calendario, el segundo es el «Próximo estreno».
    @ViewBuilder private func rows(_ rest: [WidgetSnapshot.Item]) -> some View {
        if let next = snapshot.upcoming?.first {
            if let one = rest.first { Row(item: one) }
            UpcomingRow(episode: next, language: snapshot.language)
        } else {
            ForEach(rest.prefix(2)) { Row(item: $0) }
        }
    }
}

/// Miniatura, título y dato; tocarlo reproduce ese título.
private struct Row: View {
    var item: WidgetSnapshot.Item
    var body: some View {
        Link(destination: item.link ?? URL(fileURLWithPath: "/")) {
            HStack(spacing: DS.Space.s2) {
                ZStack {
                    if let image = poster(item) { Image(uiImage: image).resizable().scaledToFill() } else { artTone(item) }
                }
                .frame(width: DS.Widget.thumbWidth).aspectRatio(DS.Poster.aspect, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    Text(item.title).font(DS.font(.sm, weight: .semibold)).foregroundStyle(DS.text).lineLimit(1)
                    Text(item.detail).font(DS.font(.xs)).foregroundStyle(DS.textMuted).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// «Próximo estreno» (cuando exista el calendario, CEN-22): título, «T3 E4» y el día.
private struct UpcomingRow: View {
    var episode: WidgetSnapshot.UpcomingEpisode
    var language: String

    /// «Hoy», «Mañana» o «Viernes 17» (en el idioma del snapshot).
    private var dayText: Text {
        let calendar = Calendar.current
        if calendar.isDateInToday(episode.date) { return Text("Hoy") }
        if calendar.isDateInTomorrow(episode.date) { return Text("Mañana") }
        return Text(episode.date.formatted(.dateTime.weekday(.wide).day().locale(Locale(identifier: language))).localizedCapitalized)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            Text("Próximo estreno").font(DS.font(.xs)).foregroundStyle(DS.textMuted)
            Text(episode.title).font(DS.font(.sm, weight: .semibold)).foregroundStyle(DS.text).lineLimit(1)
            Text("\(episode.episodeLabel) · \(dayText)").font(DS.font(.xs)).foregroundStyle(DS.textMuted).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Pantalla de bloqueo: título y «T2 · E6 · quedan 20 min».
private struct LockView: View {
    var snapshot: WidgetSnapshot
    var body: some View {
        if let item = snapshot.items.first {
            VStack(alignment: .leading) {
                Text(item.title).font(.headline).lineLimit(1)
                if !item.detail.isEmpty { Text(item.detail).font(.caption).lineLimit(1) }
                if let progress = item.progress { ProgressView(value: progress) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetURL(item.link)
            .containerBackground(for: .widget) { AccessoryWidgetBackground() }
        } else {
            VStack(alignment: .leading) {
                Text("Nada pendiente").font(.headline).lineLimit(1)
                Text("Abrir Orbital").font(.caption).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetURL(URL(string: "\(WidgetLink.scheme)://"))
            .containerBackground(for: .widget) { AccessoryWidgetBackground() }
        }
    }
}
