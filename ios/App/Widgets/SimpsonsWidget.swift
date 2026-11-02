import SwiftUI
import UIKit
import WidgetKit
import OrbitalCore

// «Un Simpson del día»: la tele morada de la sala sobre el amarillo de Los Simpson, con la imagen del episodio en la pantalla.
// Un episodio distinto cada día (el mismo todo el día); tocarlo lo reproduce. El mediano trae «Ver» y «Otro al azar» (la ruleta).
// Lo arma la app (`SimpsonsWidgetPublisher`); el widget solo lee la semana del App Group.

struct SimpsonsEntry: TimelineEntry {
    var date: Date
    var day: SimpsonsOfTheDay.Day?
    var language: String
}

/// Una entrada por día a medianoche, de lo que la app dejó armado.
struct SimpsonsProvider: TimelineProvider {
    func placeholder(in context: Context) -> SimpsonsEntry { SimpsonsEntry(date: Date(), day: Self.sample, language: "es") }

    func getSnapshot(in context: Context, completion: @escaping (SimpsonsEntry) -> Void) {
        let day = WidgetStore.loadSimpsons()?.day(for: Date())
        completion(SimpsonsEntry(date: Date(), day: day ?? (context.isPreview ? Self.sample : nil), language: Self.language))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpsonsEntry>) -> Void) {
        let now = Date(), calendar = Calendar.current
        let week = WidgetStore.loadSimpsons()
        var entries = [SimpsonsEntry(date: now, day: week?.day(for: now), language: Self.language)]
        for day in week?.days ?? [] where day.day > now { entries.append(SimpsonsEntry(date: day.day, day: day, language: Self.language)) }
        let last = entries.last?.date ?? now
        let refresh = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: last)) ?? last
        completion(Timeline(entries: entries, policy: .after(refresh)))
    }

    /// El idioma de la app (el que dejó en el snapshot de «Lo siguiente para ti»).
    private static var language: String { WidgetStore.load()?.language ?? "es" }

}

struct SimpsonsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetStore.simpsonsKind, provider: SimpsonsProvider()) { entry in
            SimpsonsDayView(entry: entry).environment(\.locale, Locale(identifier: entry.language))
        }
        .configurationDisplayName("Un Simpson del día")
        .description("Un episodio distinto cada día. Tócalo y lo pone.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct SimpsonsDayView: View {
    var entry: SimpsonsEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if family == .systemMedium { medium } else { small }
        }
        .foregroundStyle(DS.backdropDeep)
        .environment(\.colorScheme, .light)   // sobre el amarillo, letra oscura en los dos modos
        .widgetURL(entry.day?.link)
        .containerBackground(for: .widget) { DS.Simpsons.amarillo }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            SimpsonsTV(day: entry.day).frame(maxWidth: .infinity)
            Spacer(minLength: 0)
            Text("Episodio del día").font(DS.font(.xs, weight: .bold)).foregroundStyle(DS.backdropDeep.opacity(DS.Opacity.dimmed))
            caption(lines: 1)
        }
    }

    private var medium: some View {
        HStack(spacing: DS.Space.s4) {
            SimpsonsTV(day: entry.day).frame(width: DS.Widget.simpsonsTV)
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text("Un Simpson del día").font(DS.font(.xs, weight: .bold)).foregroundStyle(DS.backdropDeep.opacity(DS.Opacity.dimmed))
                caption(lines: 2)
                Spacer(minLength: 0)
                HStack(spacing: DS.Space.s2) {
                    if let link = entry.day?.link {
                        Button(intent: OpenWidgetLinkIntent(link: link)) { pill(Text("Ver"), symbol: Image(systemName: "play.fill"), solid: true) }
                    }
                    Button(intent: OpenSimpsonsIntent()) { pill(Text("Otro"), symbol: Image("simpsons.donut"), solid: false) }
                        .accessibilityLabel(Text("Un Simpson al azar"))
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// El nombre del episodio (o «Los Simpson» si Cinemeta no lo trae) y «T6 · E12».
    @ViewBuilder private func caption(lines: Int) -> some View {
        let day = entry.day
        Text(verbatim: (day?.title).flatMap { $0.isEmpty ? nil : $0 } ?? "Los Simpson")
            .font(DS.font(.md, weight: .heavy)).lineLimit(lines).minimumScaleFactor(DS.Widget.labelShrink)
        if let day {
            Text(verbatim: episodeLabel(day))
                .font(DS.font(.xs, weight: .semibold)).monospacedDigit()
        }
    }

    /// «T6 · E12» (en inglés, «S6 · E12»).
    private func episodeLabel(_ day: SimpsonsOfTheDay.Day) -> String {
        (entry.language == "en" ? "S" : "T") + "\(day.season) · E\(day.episode)"
    }

    private func pill(_ title: Text, symbol: Image, solid: Bool) -> some View {
        HStack(spacing: DS.Space.s1) {
            symbol.font(DS.font(.xs, weight: .bold))
            title.font(DS.font(.xs, weight: .semibold))
        }
        .foregroundStyle(solid ? DS.Simpsons.amarillo : DS.backdropDeep)
        .padding(.horizontal, DS.Space.s3)
        .frame(minHeight: DS.Widget.button)
        .background(Capsule().fill(solid ? DS.backdropDeep : DS.Simpsons.tvBody.opacity(DS.Opacity.faint)))
    }
}

/// La tele de la sala de Los Simpson: el mueble morado con su perilla, la antena y, en la pantalla, la imagen del episodio.
private struct SimpsonsTV: View {
    var day: SimpsonsOfTheDay.Day?

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let screenWidth = width * DS.Widget.simpsonsScreenShare
            VStack(spacing: 0) {
                antenna(width: width)
                HStack(spacing: width * DS.Widget.simpsonsGap) {
                    screen.frame(width: screenWidth, height: screenWidth / DS.Simpsons.screenAspect)
                    VStack(spacing: width * DS.Widget.simpsonsGap) {
                        Circle().fill(DS.Simpsons.knob)
                        Circle().fill(DS.Simpsons.knob)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(width * DS.Widget.simpsonsGap)
                .background(RoundedRectangle(cornerRadius: width * DS.Widget.simpsonsBodyRadius, style: .continuous).fill(DS.Simpsons.tvBody))
                .overlay(RoundedRectangle(cornerRadius: width * DS.Widget.simpsonsBodyRadius, style: .continuous)
                    .strokeBorder(DS.Simpsons.tvShade, lineWidth: DS.Simpsons.screenFrame))
            }
        }
        .aspectRatio(DS.Widget.simpsonsTVAspect, contentMode: .fit)
        .accessibilityHidden(true)
    }

    /// La pantalla con la imagen del episodio (o la estática verde de la tele vieja si aún no la hay).
    private var screen: some View {
        ZStack {
            DS.Simpsons.knob
            if let file = day?.imageFile, let url = WidgetStore.simpsonsImageURL(file), let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image).resizable().widgetAccentedRenderingMode(.fullColor).scaledToFill()
            } else {
                Image("simpsons.donut").font(DS.font(.lg)).foregroundStyle(DS.Simpsons.amarillo)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
    }

    /// Las dos varillas de la antena, abiertas en V.
    private func antenna(width: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            Capsule().fill(DS.Simpsons.antenna).frame(width: DS.Simpsons.antennaLine, height: width * DS.Widget.simpsonsAntenna)
                .rotationEffect(.degrees(-DS.Widget.simpsonsAntennaAngle), anchor: .bottom)
            Capsule().fill(DS.Simpsons.antenna).frame(width: DS.Simpsons.antennaLine, height: width * DS.Widget.simpsonsAntenna)
                .rotationEffect(.degrees(DS.Widget.simpsonsAntennaAngle), anchor: .bottom)
        }
        .frame(height: width * DS.Widget.simpsonsAntenna)
    }
}
