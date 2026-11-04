import SwiftUI
import UIKit
import WidgetKit
import OrbitalCore

// «Los Simpson en la tele»: la tele morada de la sala sobre el amarillo de Los Simpson, con la imagen del episodio en la
// pantalla. Cambia de episodio cada media hora, a la hora y a la media (Fernando, 4 nov 2026: «que el episodio que se muestra
// en los widgets de los Simpson cambie cada X tiempo»); tocarlo lo reproduce. El mediano trae «Ver» y «Otro» (la ruleta).
// Lo arma la app (`SimpsonsWidgetPublisher`); el widget solo lee la tanda del App Group.

struct SimpsonsEntry: TimelineEntry {
    var date: Date
    var day: SimpsonsOfTheDay.Episode?
    var language: String
}

/// Un cuadro por turno (cada `simpsonsTurnMinutes`), ya con su imagen en el disco: iOS los pasa solo, sin despertar a la app
/// ni gastar internet. Al acabarse los cuadros pide los siguientes.
struct SimpsonsProvider: TimelineProvider {
    func placeholder(in context: Context) -> SimpsonsEntry { SimpsonsEntry(date: Date(), day: Self.sample, language: "es") }

    func getSnapshot(in context: Context, completion: @escaping (SimpsonsEntry) -> Void) {
        let day = Self.ready()?.episode(at: Date(), minutes: DS.Widget.simpsonsTurnMinutes)
        completion(SimpsonsEntry(date: Date(), day: day ?? (context.isPreview ? Self.sample : nil), language: Self.language))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpsonsEntry>) -> Void) {
        let now = Date(), minutes = DS.Widget.simpsonsTurnMinutes
        let week = Self.ready(), first = SimpsonsOfTheDay.turn(for: now, minutes: minutes)
        let entries = (0..<DS.Widget.simpsonsTurns).map { offset -> SimpsonsEntry in
            let date = offset == 0 ? now : SimpsonsOfTheDay.start(ofTurn: first + offset, minutes: minutes)
            return SimpsonsEntry(date: date, day: week?.episode(at: date, minutes: minutes), language: Self.language)
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    /// La tanda que dejó la app, solo con los episodios cuya imagen ya está en el disco (si a alguno no le llegó, la tele no
    /// enseña la dona en su turno; si no llegó ninguna, la tanda entera).
    private static func ready() -> SimpsonsOfTheDay? {
        guard var week = WidgetStore.loadSimpsons() else { return nil }
        let withImage = week.episodes.filter { episode in
            episode.imageFile.flatMap { WidgetStore.simpsonsImageURL($0) }.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        }
        if !withImage.isEmpty { week.episodes = withImage }
        return week
    }

    /// El idioma de la app (el que dejó en el snapshot de «Lo siguiente para ti»).
    private static var language: String { WidgetStore.load()?.language ?? "es" }

}

struct SimpsonsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetStore.simpsonsKind, provider: SimpsonsProvider()) { entry in
            SimpsonsDayView(entry: entry).environment(\.locale, Locale(identifier: entry.language))
        }
        .configurationDisplayName("Los Simpson en la tele")
        .description("Un episodio distinto cada media hora. Tócalo y lo pone.")
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
            // En el chico, sin la etiqueta «Episodio del día»: el nombre cabe completo (antes «Treehouse of Horr…»).
            caption(lines: 2)
        }
    }

    private var medium: some View {
        HStack(spacing: DS.Space.s4) {
            SimpsonsTV(day: entry.day).frame(width: DS.Widget.simpsonsTV)
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text("Los Simpson en la tele").font(DS.font(.xs, weight: .bold)).foregroundStyle(DS.backdropDeep.opacity(DS.Opacity.dimmed))
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
    private func episodeLabel(_ day: SimpsonsOfTheDay.Episode) -> String {
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
    var day: SimpsonsOfTheDay.Episode?

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
        // Completa, con franjas negras arriba y abajo como en una tele vieja (Fernando, 2 nov 2026): las imágenes son
        // panorámicas y la pantalla es casi cuadrada; recortada se perdía una cuarta parte (Bart a la mitad en «Cape Feare»).
        WidgetFitImage(url: day?.imageFile.flatMap { WidgetStore.simpsonsImageURL($0) }, bars: DS.Simpsons.screenBars) {
            ZStack {
                DS.Simpsons.knob
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
