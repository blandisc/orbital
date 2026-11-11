import SwiftUI
import UIKit
import WidgetKit
import OrbitalCore

// «Lo nuevo de lo tuyo» (como la línea de Inicio, `ReleaseTimeline`): lo que ya salió de tus series en los últimos días, la
// marca HOY y lo que viene, más apagado. Lee el mismo snapshot que «Lo siguiente para ti» (`WidgetSnapshot.upcoming`).

// MARK: Datos

struct ReleasesEntry: TimelineEntry {
    var date: Date
    var line: [WidgetSnapshot.UpcomingEpisode]
    var language: String
}

/// Una entrada ahora, otra en cuanto sale cada estreno de hoy en adelante (pasa a «Nuevo») y otra a medianoche (Hoy → Ayer).
struct ReleasesProvider: TimelineProvider {
    func placeholder(in context: Context) -> ReleasesEntry { ReleasesEntry(date: Date(), line: WidgetSnapshot.sampleReleases(), language: "es") }

    func getSnapshot(in context: Context, completion: @escaping (ReleasesEntry) -> Void) {
        let stored = WidgetStore.load()
        let line = stored?.upcoming ?? []
        completion(ReleasesEntry(date: Date(), line: context.isPreview && line.isEmpty ? WidgetSnapshot.sampleReleases() : line, language: stored?.language ?? "es"))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ReleasesEntry>) -> Void) {
        let now = Date(), stored = WidgetStore.load()
        let line = stored?.upcoming ?? []
        let calendar = Calendar.current
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let moments = Set([now, midnight] + line.map(\.airs).filter { $0 > now && $0 < midnight.addingTimeInterval(DS.Widget.fallbackRefresh) })
        let entries = moments.sorted().map { ReleasesEntry(date: $0, line: line, language: stored?.language ?? "es") }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(DS.Widget.fallbackRefresh))))
    }
}

// MARK: Widget

struct ReleasesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetStore.releasesKind, provider: ReleasesProvider()) { entry in
            ReleasesView(entry: entry).environment(\.locale, Locale(identifier: entry.language))
        }
        .configurationDisplayName("Lo nuevo de lo tuyo")
        .description("Lo que ya salió de tus series y lo que viene.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

struct ReleasesView: View {
    var entry: ReleasesEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemMedium: ReleasesLine(entry: entry)
        case .accessoryRectangular: ReleasesLockRow(entry: entry)
        case .accessoryCircular: ReleasesLockRound(entry: entry)
        case .accessoryInline: ReleasesInline(entry: entry)
        default: ReleasesSpotlight(entry: entry)
        }
    }
}

// MARK: Piezas

/// El póster reducido que dejó la app; sin él, el tono de Orbital.
private struct ReleasePoster: View {
    var airing: WidgetSnapshot.UpcomingEpisode
    var body: some View {
        // Recortado y reducido al tamaño exacto del póster (`WidgetImage.fill`).
        WidgetFillImage(url: airing.imageFile.flatMap { WidgetStore.imageURL($0) }) {
            ZStack {
                DS.surface
                Text(verbatim: airing.title).font(DS.font(.xs, weight: .semibold)).foregroundStyle(DS.textMuted)
                    .multilineTextAlignment(.center).padding(DS.Space.s1)
            }
        }
        .aspectRatio(DS.Poster.aspect, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
    }
}

/// Cómo va respecto a `now`, con las palabras de la línea de Inicio: «Ayer», «Hoy», «Mañana», el día; y la hora si es hoy.
private struct ReleaseWhen {
    var airing: WidgetSnapshot.UpcomingEpisode
    var now: Date
    var language: String
    private var calendar: Calendar { .current }
    private var locale: Locale { Locale(identifier: language) }

    var isOut: Bool { airing.isOut(at: now) }
    /// Salió hoy: ya se puede ver («Nuevo»).
    var isNew: Bool { isOut && calendar.isDate(airing.date, inSameDayAs: now) }

    /// «Ayer», «Hoy», «Mañana» o «Viernes».
    var day: Text {
        if calendar.isDate(airing.date, inSameDayAs: now) { return Text("Hoy") }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(airing.date, inSameDayAs: yesterday) { return Text("Ayer") }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(airing.date, inSameDayAs: tomorrow) { return Text("Mañana") }
        return Text(verbatim: airing.date.formatted(.dateTime.weekday(.wide).locale(locale)).capitalized(with: locale))
    }

    /// Lo que va en el renglón de arriba de cada póster, corto para que todos midan igual: la hora de hoy («21:00»), «Hoy»,
    /// «Ayer», «Mañana» o el día abreviado («Vie»). «Nuevo» no va aquí: es el puntito del póster, como en Inicio.
    var label: Text {
        if !isOut, calendar.isDate(airing.date, inSameDayAs: now) { return hour }
        if calendar.isDate(airing.date, inSameDayAs: now) { return Text("Hoy") }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(airing.date, inSameDayAs: yesterday) { return Text("Ayer") }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(airing.date, inSameDayAs: tomorrow) { return Text("Mañana") }
        return Text(verbatim: airing.date.formatted(.dateTime.weekday(.abbreviated).locale(locale)).capitalized(with: locale).replacingOccurrences(of: ".", with: ""))
    }

    /// «21:00»; sin hora conocida, «Madrugada» (lo de streaming).
    var hour: Text {
        guard airing.aired != nil else { return Text("Madrugada") }
        return Text(verbatim: airing.airs.formatted(Date.FormatStyle(locale: locale).hour().minute()))
    }
}

/// El punto del rótulo, como en la línea de Inicio: turquesa (`DS.fresh`, el punto del logo) lo que ya salió (se puede ver), gris lo
/// que viene.
private struct ReleaseDot: View {
    var out: Bool
    /// Sobre el arte (el chico): lo que viene en papel, que el gris no se ve.
    var onArt = false
    var body: some View {
        Circle().fill(out ? DS.fresh : onArt ? DS.onArtSecondary : DS.ink500).frame(width: DS.HomeTimeline.dot, height: DS.HomeTimeline.dot)
    }
}

private func noReleases() -> some View {
    VStack(alignment: .leading, spacing: DS.Space.s1) {
        Text("Lo nuevo de lo tuyo").font(DS.font(.sm, weight: .semibold)).foregroundStyle(DS.text)
        Text("Cuando salga algo de tus series, aparece aquí.").font(DS.font(.xs)).foregroundStyle(DS.textMuted)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
}

// MARK: Tamaños

/// Mediano: la línea de Inicio. Hasta dos de lo que ya salió, la marca HOY y lo que viene (cuantos quepan, hasta tres).
private struct ReleasesLine: View {
    var entry: ReleasesEntry

    var body: some View {
        let out = entry.line.filter { $0.isOut(at: entry.date) }.suffix(DS.Widget.releasesOut)
        let next = entry.line.filter { !$0.isOut(at: entry.date) }.prefix(DS.Widget.releasesShown - out.count)
        Group {
            if out.isEmpty && next.isEmpty {
                noReleases()
            } else {
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Lo nuevo de lo tuyo").font(DS.font(.sm, weight: .semibold)).foregroundStyle(DS.text)
                        Spacer(minLength: DS.Space.s2)
                        Text("Ya salió y lo que viene").font(DS.font(.xs)).foregroundStyle(DS.textMuted).lineLimit(1)
                    }
                    HStack(alignment: .top, spacing: DS.Space.s2) {
                        ForEach(Array(out), id: \.id) { card($0) }
                        todayMark
                        ForEach(Array(next), id: \.id) { card($0) }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .environment(\.colorScheme, .dark)
        .containerBackground(for: .widget) { DS.bg.environment(\.colorScheme, .dark) }
        .widgetURL(URL(string: "\(WidgetLink.scheme)://"))
    }

    /// La marca HOY: una línea turquesa delgada que se desvanece hacia abajo, con «Hoy» arriba (la de Inicio, `HomeTimeline`).
    private var todayMark: some View {
        VStack(spacing: DS.Space.s1) {
            Text("Hoy").font(DS.font(.xs, weight: .bold)).foregroundStyle(DS.fresh)
            Capsule().fill(LinearGradient(colors: [DS.fresh, .clear], startPoint: .top, endPoint: .bottom))
                .frame(width: DS.HomeTimeline.markLine).frame(maxHeight: .infinity)
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityHidden(true)
    }

    private func card(_ airing: WidgetSnapshot.UpcomingEpisode) -> some View {
        let when = ReleaseWhen(airing: airing, now: entry.date, language: entry.language)
        return Link(destination: airing.link ?? URL(fileURLWithPath: "/")) {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                // El rótulo nunca pasa del ancho del póster: antes podía usar el aire entre pósters y «Mañana» se encimaba con el
                // punto del siguiente (Fernando, 3 nov 2026). Si con el punto no cabe, va sin él y un poco más chico (el color
                // del texto sigue diciendo si ya salió).
                let label = when.label.font(DS.font(.xs, weight: .semibold)).foregroundStyle(when.isOut ? DS.text : DS.textMuted).lineLimit(1)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: DS.Space.s1) { ReleaseDot(out: when.isOut); label }.fixedSize()
                    label.minimumScaleFactor(DS.Widget.labelShrink)
                }
                .frame(width: DS.Widget.releasePoster, alignment: .leading)
                ReleasePoster(airing: airing).opacity(when.isOut ? 1 : DS.Opacity.dimmed)
                    .overlay(alignment: .topLeading) { if when.isNew { DSNewDot(text: "Nuevo", compact: true) } }
                Text(verbatim: airing.episodeLabel).font(DS.font(.xs)).foregroundStyle(DS.textMuted).lineLimit(1)
                    .minimumScaleFactor(DS.Widget.labelShrink)
            }
            .frame(width: DS.Widget.releasePoster)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Chico: lo de hoy que ya se puede ver o, si no, lo siguiente que sale, a sangre, con cuánto falta.
private struct ReleasesSpotlight: View {
    var entry: ReleasesEntry

    /// Lo nuevo de hoy primero; luego lo que viene.
    private var pick: WidgetSnapshot.UpcomingEpisode? {
        let calendar = Calendar.current
        return entry.line.last { $0.isOut(at: entry.date) && calendar.isDate($0.date, inSameDayAs: entry.date) }
            ?? entry.line.first { !$0.isOut(at: entry.date) }
    }

    var body: some View {
        if let airing = pick {
            let when = ReleaseWhen(airing: airing, now: entry.date, language: entry.language)
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                // Lo nuevo lleva el puntito en la esquina (el de Inicio); lo que viene, su punto y cuándo.
                if !when.isNew {
                    HStack(spacing: DS.Space.s1) {
                        ReleaseDot(out: when.isOut, onArt: true)
                        Text("\(when.day) · \(when.hour)").font(DS.font(.xs, weight: .semibold)).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Text(verbatim: airing.title).font(DS.font(.md, weight: .bold)).lineLimit(2)
                Text(verbatim: airing.episodeLabel).font(DS.font(.xs, weight: .medium)).foregroundStyle(DS.onArtSecondary).lineLimit(1)
                (when.isOut ? Text("Ya salió") : countdown(airing, when)).font(DS.font(.lg, weight: .bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(DS.Widget.labelShrink)
            }
            .foregroundStyle(DS.text)
            .shadow(color: DS.scrimStrong, radius: DS.Widget.textShadowRadius)
            .frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.colorScheme, .dark)
            .widgetURL(airing.link)
            .widgetArtBackground {   // también en la pantalla tintada
                ZStack {
                    DS.bg
                    WidgetFillImage(url: airing.imageFile.flatMap { WidgetStore.imageURL($0) }, anchor: .top)
                        .opacity(when.isOut ? 1 : DS.Opacity.dimmed)
                    LinearGradient(stops: [.init(color: .clear, location: DS.Widget.scrimStart), .init(color: DS.scrimStrong, location: 1)],   // ds-exception: el widget es otro programa y no trae ArtVeil
                                   startPoint: .top, endPoint: .bottom)
                }
                .overlay(alignment: .topLeading) {
                    // El fondo no hereda el idioma del widget (salía «NEW»): se le pasa aquí.
                    if when.isNew { DSNewDot(text: "Nuevo").environment(\.locale, Locale(identifier: entry.language)) }
                }
            }
        } else {
            noReleases().containerBackground(for: .widget) { DS.bg }
        }
    }

    /// Hoy: cuánto falta, en vivo («2:41:09»); otro día: en cuántos días («en 3 días»).
    private func countdown(_ airing: WidgetSnapshot.UpcomingEpisode, _ when: ReleaseWhen) -> Text {
        let calendar = Calendar.current
        if calendar.isDate(airing.date, inSameDayAs: entry.date) { return Text(timerInterval: entry.date...airing.airs, countsDown: true) }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: entry.date), to: airing.date).day ?? 0
        return days <= 1 ? Text("Mañana") : Text("en \(days) días")
    }
}

/// Pantalla bloqueada, rectangular: «● Hoy 21:00», la serie y el episodio.
private struct ReleasesLockRow: View {
    var entry: ReleasesEntry
    var body: some View {
        let airing = entry.line.first { !$0.isOut(at: entry.date) } ?? entry.line.last
        VStack(alignment: .leading, spacing: 0) {
            if let airing {
                let when = ReleaseWhen(airing: airing, now: entry.date, language: entry.language)
                HStack(spacing: DS.Space.s1) {
                    Image(systemName: when.isOut ? "sparkles" : "calendar")
                    (when.isOut ? Text("Ya salió") : Text("\(when.day) \(when.hour)")).font(DS.font(.sm, weight: .semibold)).lineLimit(1)
                }
                Text(verbatim: airing.title).font(DS.font(.lg, weight: .semibold)).lineLimit(1)
                Text(verbatim: airing.episodeLabel).font(DS.font(.sm)).lineLimit(1)
            } else {
                Text("Lo nuevo de lo tuyo").font(DS.font(.sm, weight: .semibold))
                Text("Nada esta semana").font(DS.font(.sm))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(airing?.link)
        .containerBackground(for: .widget) { AccessoryWidgetBackground() }
    }
}

/// Pantalla bloqueada, redondo: la hora si sale hoy; si no, en cuántos días.
private struct ReleasesLockRound: View {
    var entry: ReleasesEntry
    var body: some View {
        let airing = entry.line.first { !$0.isOut(at: entry.date) }
        ZStack {
            AccessoryWidgetBackground()
            if let airing {
                let calendar = Calendar.current
                let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: entry.date), to: airing.date).day ?? 0
                VStack(spacing: 0) {
                    if days == 0 {
                        ReleaseWhen(airing: airing, now: entry.date, language: entry.language).hour.font(DS.font(.sm, weight: .bold)).minimumScaleFactor(DS.Widget.labelShrink)
                        Text("hoy").font(DS.font(.xs))
                    } else {
                        Text(verbatim: "\(days)").font(DS.font(.lg, weight: .bold))
                        Text(days == 1 ? "día" : "días").font(DS.font(.xs))
                    }
                }
            } else {
                Image(systemName: "calendar").font(DS.font(.lg))
            }
        }
        .widgetURL(airing?.link)
        .containerBackground(for: .widget) { Color.clear }
    }
}

/// Sobre la hora de la pantalla bloqueada: «Hoy 21:00 · The Bear T4 E3».
private struct ReleasesInline: View {
    var entry: ReleasesEntry
    var body: some View {
        if let airing = entry.line.first(where: { !$0.isOut(at: entry.date) }) {
            let when = ReleaseWhen(airing: airing, now: entry.date, language: entry.language)
            Text("\(when.day) \(when.hour) · \(airing.title) \(airing.episodeLabel)")
                .widgetURL(airing.link)
        } else {
            Text("Nada nuevo esta semana")
        }
    }
}
