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
        let now = Date(), stored = WidgetStore.load() ?? .empty
        // Una entrada ahora y otra a medianoche: «Hoy» y «Mañana» cambian de día, y un estreno que ya pasó deja de verse.
        let today = Calendar.current.startOfDay(for: now)
        let midnight = Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today
        let entries = [now, midnight].map { NextUpEntry(date: $0, snapshot: Self.fromDay($0, stored)) }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(DS.Widget.fallbackRefresh))))
    }

    /// El snapshot sin los estrenos de días anteriores a `date`.
    private static func fromDay(_ date: Date, _ snapshot: WidgetSnapshot) -> WidgetSnapshot {
        var copy = snapshot
        let start = Calendar.current.startOfDay(for: date)
        copy.upcoming = snapshot.upcoming?.filter { $0.date >= start }
        return copy
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
        .description("Sigue viendo donde ibas, aquí o en la TV.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
    }
}

struct NextUpView: View {
    var entry: NextUpEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemMedium: MediumView(snapshot: entry.snapshot, date: entry.date)
        case .systemLarge: LargeView(snapshot: entry.snapshot, date: entry.date)
        case .accessoryRectangular: LockView(snapshot: entry.snapshot)
        default: SmallView(snapshot: entry.snapshot)
        }
    }
}

// MARK: Piezas

/// Un archivo de imagen del App Group que sí está.
private func existing(_ file: String?) -> URL? {
    file.flatMap { WidgetStore.imageURL($0) }.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
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

/// El arte a sangre (o el tono si no hay imagen), alineado arriba para que no se corten las cabezas. `wide`: la imagen ancha (con el póster
/// de respaldo); si no, el póster vertical.
private struct Art: View {
    var item: WidgetSnapshot.Item
    var wide = false
    var body: some View {
        ZStack {
            tintedBackground(artTone(item))
            // Recortada y reducida al tamaño exacto del hueco (`WidgetImage.fill`): nítida y sin pasar del límite de WidgetKit.
            if let url = (wide ? existing(item.wideFile) : nil) ?? existing(item.imageFile) { WidgetFillImage(url: url, anchor: .top) }
        }
    }
}

/// El logo del título a su tamaño exacto (cabe en `box`), o nil si no hay.
private struct LogoImage: View {
    var url: URL
    @Environment(\.displayScale) private var scale
    var body: some View {
        if let image = WidgetImage.fit(url, box: CGSize(width: DS.Widget.logoWidth, height: DS.Widget.logoHeight), scale: scale) {
            Image(uiImage: image).resizable().widgetAccentedRenderingMode(.fullColor).scaledToFit()
        }
    }
}

/// El velo inferior: del arte limpio a casi opaco, para que el título y el dato se lean (en el ancho empieza más arriba).
private func bottomScrim(wide: Bool = false) -> some View {
    LinearGradient(stops: [.init(color: .clear, location: wide ? DS.Widget.scrimStartWide : DS.Widget.scrimStart), .init(color: DS.scrimStrong, location: 1)],   // ds-exception: el widget es otro programa y no trae ArtVeil
                   startPoint: .top, endPoint: .bottom)
}

/// El logo del título si lo hay (y entonces no se pinta el título en texto), o el título en una línea; debajo «T2 · E6 · quedan 20 min» y la
/// barra de avance. Letra clara con sombra sobre el velo, como el destacado de Inicio.
private struct Caption: View {
    var item: WidgetSnapshot.Item
    /// Los botones «Aquí» y «En la TV» debajo: con nombre (`.labeled`) o solo el ícono (`.icons`, el chico).
    var actions: WatchActions.Style? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            if let logo = existing(item.logoFile) {
                LogoImage(url: logo).frame(maxWidth: DS.Widget.logoWidth, maxHeight: DS.Widget.logoHeight, alignment: .leading)
                    .accessibilityLabel(item.title)
            } else {
                Text(item.title).font(DS.font(.md, weight: .semibold)).foregroundStyle(DS.text).lineLimit(1)
            }
            if !item.detail.isEmpty { Text(item.detail).font(DS.font(.xs, weight: .medium)).foregroundStyle(DS.text).lineLimit(2) }
            if let progress = item.progress { ProgressLine(fraction: progress) }
            if let actions { WatchActions(item: item, style: actions).padding(.top, DS.Space.s1) }
        }
        .shadow(color: DS.scrimStrong, radius: DS.Widget.textShadowRadius)
        .environment(\.colorScheme, .dark)   // va sobre el velo del arte: letra clara también con la pantalla de inicio en claro
    }
}

/// Nada pendiente: la marca de Orbital y un enlace a la app.
private struct EmptyState: View {
    var body: some View {
        VStack(spacing: DS.Space.s2) {
            OrbitalMark(size: DS.Size.touchTarget).foregroundStyle(DS.text)   // la marca de la TV
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
                Caption(item: item, actions: .icons)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetURL(item.link)
            .widgetArtBackground { ZStack { Art(item: item); bottomScrim() } }   // también en la pantalla tintada
        } else {
            EmptyState()
        }
    }
}

private struct MediumView: View {
    var snapshot: WidgetSnapshot
    /// El momento de la entrada (no el de pintarla): la de medianoche dice «Hoy» del día nuevo.
    var date: Date

    var body: some View {
        if let first = snapshot.items.first {
            HStack(spacing: DS.Space.s3) {
                Link(destination: first.link ?? URL(fileURLWithPath: "/")) {
                    ZStack(alignment: .bottomLeading) {
                        Art(item: first, wide: true)
                        bottomScrim(wide: true)
                        Caption(item: first, actions: .icons).padding(DS.Space.s2)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
                }
                VStack(spacing: DS.Space.s2) {
                    rows(Array(snapshot.items.dropFirst()))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .environment(\.colorScheme, .dark)   // el fondo es el tono oscuro del arte: letra clara en los dos modos
            .containerBackground(for: .widget) { tintedBackground(artTone(first)).environment(\.colorScheme, .dark) }   // el fondo también: sala oscura
        } else {
            EmptyState()
        }
    }

    /// Dos renglones: los siguientes de «Seguir viendo»; con calendario, el segundo es el «Próximo estreno».
    @ViewBuilder private func rows(_ rest: [WidgetSnapshot.Item]) -> some View {
        if let next = snapshot.upcoming?.first(where: { !$0.isOut(at: date) }) {
            if let one = rest.first { Row(item: one) }
            UpcomingRow(episode: next, language: snapshot.language, date: date)
        } else {
            ForEach(rest.prefix(2)) { Row(item: $0) }
        }
    }
}

/// «Aquí» (abre el reproductor donde ibas) y «En la TV» (lo manda a tu Orbital sin abrir la app). Tras tocar «En la TV», el botón
/// dice lo que pasó unos minutos: «Mandando…», «En tu Orbital» o «La TV no contesta».
struct WatchActions: View {
    enum Style { case labeled, icons }
    var item: WidgetSnapshot.Item
    var style: Style

    var body: some View {
        HStack(spacing: DS.Space.s2) {
            if let link = item.link {
                Button(intent: OpenWidgetLinkIntent(link: link)) {
                    pill(Text("Aquí"), symbol: "play.fill", solid: true)
                }
                .accessibilityLabel(Text("Ver aquí"))
            }
            Button(intent: PlayOnTVIntent(kind: item.kind, metaID: item.metaID, videoID: item.videoID, name: item.title)) {
                tvPill
            }
            .accessibilityLabel(Text("Ver en la TV"))
        }
        .buttonStyle(.plain)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder private var tvPill: some View {
        switch WidgetTVStatus.current(for: item.metaID) {
        case .sending: pill(Text("Mandando…"), symbol: "tv", solid: false, wide: true)
        case .sent: pill(Text("En tu Orbital"), symbol: "checkmark", solid: false, wide: true)
        case .failed: pill(Text("La TV no contesta"), symbol: "exclamationmark.triangle.fill", solid: false, wide: true)
        case nil: pill(Text("En la TV"), symbol: "tv", solid: false)
        }
    }

    /// Una cápsula: papel con letra oscura («Aquí») o vidrio claro («En la TV»). Con íconos solo, el círculo; el estado de la TV
    /// (`wide`) siempre lleva su texto para que se entienda qué pasó.
    private func pill(_ title: Text, symbol: String, solid: Bool, wide: Bool = false) -> some View {
        let showsTitle = style == .labeled || wide
        return HStack(spacing: DS.Space.s1) {
            Image(systemName: symbol).font(DS.font(.xs, weight: .bold))
            if showsTitle { title.font(DS.font(.xs, weight: .semibold)).lineLimit(1).minimumScaleFactor(DS.Widget.labelShrink) }
        }
        .foregroundStyle(solid ? DS.backdropDeep : DS.paper)
        .padding(.horizontal, showsTitle ? DS.Space.s3 : 0)
        .frame(minWidth: DS.Widget.button, minHeight: DS.Widget.button)
        .background(Capsule().fill(solid ? DS.paper : DS.fillStrong))
    }
}

/// Grande: el de ahora a lo ancho con «Aquí» y «En la TV» con nombre; abajo los otros dos de «Seguir viendo» o el próximo
/// estreno.
private struct LargeView: View {
    var snapshot: WidgetSnapshot
    var date: Date

    var body: some View {
        if let first = snapshot.items.first {
            VStack(spacing: DS.Space.s3) {
                ZStack(alignment: .bottomLeading) {
                    Art(item: first, wide: true)
                    bottomScrim(wide: true)
                    Caption(item: first, actions: .labeled).padding(DS.Space.s3)
                }
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
                .frame(maxHeight: .infinity)
                .widgetURL(first.link)
                VStack(spacing: DS.Space.s2) {
                    ForEach(snapshot.items.dropFirst().prefix(2)) { Row(item: $0) }
                    if let next = snapshot.upcoming?.first(where: { !$0.isOut(at: date) }), snapshot.items.count < 3 {
                        UpcomingRow(episode: next, language: snapshot.language, date: date)
                    }
                }
            }
            .environment(\.colorScheme, .dark)
            .containerBackground(for: .widget) { tintedBackground(artTone(first)).environment(\.colorScheme, .dark) }
        } else {
            EmptyState()
        }
    }
}

/// Miniatura, título y dato; tocarlo reproduce ese título.
private struct Row: View {
    var item: WidgetSnapshot.Item
    var body: some View {
        Link(destination: item.link ?? URL(fileURLWithPath: "/")) {
            HStack(spacing: DS.Space.s2) {
                WidgetFillImage(url: existing(item.imageFile)) { artTone(item) }
                .frame(width: DS.Widget.thumbWidth, height: DS.Widget.thumbWidth / DS.Poster.aspect)
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
    var date: Date

    /// «Hoy», «Mañana» o «Viernes 17» (en el idioma del snapshot).
    private var dayText: Text {
        let calendar = Calendar.current
        if calendar.isDate(episode.date, inSameDayAs: date) { return Text("Hoy") }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: date), calendar.isDate(episode.date, inSameDayAs: tomorrow) { return Text("Mañana") }
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
                Text(item.title).font(DS.font(.lg)).lineLimit(1)
                if !item.detail.isEmpty { Text(item.detail).font(DS.font(.sm)).lineLimit(1) }
                if let progress = item.progress { ProgressView(value: progress) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetURL(item.link)
            .containerBackground(for: .widget) { AccessoryWidgetBackground() }
        } else {
            VStack(alignment: .leading) {
                Text("Nada pendiente").font(DS.font(.lg)).lineLimit(1)
                Text("Abrir Orbital").font(DS.font(.sm)).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetURL(URL(string: "\(WidgetLink.scheme)://"))
            .containerBackground(for: .widget) { AccessoryWidgetBackground() }
        }
    }
}
