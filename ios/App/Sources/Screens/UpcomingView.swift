import SwiftUI
import OrbitalCore
import OrbitalModels

/// «Próximos estrenos» (Para ti › Listas › Trakt): los episodios que salen de las series que sigues, con la hora de aquí.
///   · Por día: «Hoy · jueves 9», «Mañana · viernes 10»… y debajo sus estrenos.
///   · Semana: una tira con los siete días (como la guía de la TV); al tocar uno, lo que sale ese día.
/// Varios episodios el mismo día van juntos («T2 E4–E6»); lo de madrugada dice «Desde la madrugada». Pulsar abre la serie.
struct UpcomingView: View {
    @ObservedObject var observer: ModelObserver<ParaTiModel>
    @State private var picked: Date?
    private var model: ParaTiModel { observer.model }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            DSSegmented<ParaTiModel.CalendarLayout>(options: [(.byDay, "Por día"), (.week, "Semana")],
                                                   selection: Binding(get: { model.calendarLayout }, set: { model.calendarLayout = $0 }))
                .padding(.horizontal, DS.Space.gutter)
            if model.airings.isEmpty {
                DSNotice(text: "No sale nada en los próximos 14 días de las series que sigues.").padding(.horizontal, DS.Space.gutter)
            } else if model.calendarLayout == .byDay {
                ForEach(AiringDay.byDay(model.airings)) { day in
                    VStack(alignment: .leading, spacing: DS.Space.s2) {
                        DayHeading(day: day.day)
                        ForEach(day.airings) { AiringRow(airing: $0) }
                    }
                    .padding(.horizontal, DS.Space.gutter)
                }
            } else {
                week
            }
        }
    }

    @ViewBuilder private var week: some View {
        let days = AiringDay.week(model.airings, from: Date())
        let selected = days.first { $0.day == picked } ?? days.first { !$0.airings.isEmpty } ?? days[0]
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Space.s2) {
                ForEach(days) { d in DayPill(day: d, selected: d.day == selected.day) { picked = d.day } }
            }
            .padding(.horizontal, DS.Space.gutter)
        }
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            DayHeading(day: selected.day)
            if selected.airings.isEmpty { Text("Nada este día").font(DS.font(.sm)).foregroundStyle(DS.textMuted) }
            ForEach(selected.airings) { AiringRow(airing: $0) }
        }
        .padding(.horizontal, DS.Space.gutter)
    }
}

/// «Hoy», «Mañana» o el nombre del día, y la fecha al lado en gris («jueves 9»).
struct DayHeading: View {
    let day: Date
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
            dayName(day, locale: locale).font(DS.font(.lg, weight: .bold)).foregroundStyle(DS.text)
            Text(verbatim: day.formatted(.dateTime.weekday(.wide).day().locale(locale))).font(DS.font(.sm)).foregroundStyle(DS.textMuted)
        }
        .accessibilityElement(children: .combine).accessibilityAddTraits(.isHeader)
    }
}

func dayName(_ day: Date, locale: Locale, calendar: Calendar = .current) -> Text {
    if calendar.isDateInToday(day) { return Text("Hoy") }
    if calendar.isDateInTomorrow(day) { return Text("Mañana") }
    return Text(verbatim: day.formatted(.dateTime.weekday(.wide).locale(locale)).capitalized(with: locale))
}

/// La hora de aquí («20:00»), o «Desde la madrugada» (lo de streaming sale de noche).
func airingTime(_ a: Airing, locale: Locale) -> Text {
    a.atDawn ? Text("Desde la madrugada") : Text(verbatim: a.aired.formatted(.dateTime.hour().minute().locale(locale)))
}

/// Un día de la tira de la semana: su nombre corto, el número y un punto si sale algo.
struct DayPill: View {
    let day: AiringDay
    let selected: Bool
    let action: () -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        Button(action: action) {
            VStack(spacing: DS.Space.s1) {
                Group {
                    if Calendar.current.isDateInToday(day.day) { Text("Hoy") }
                    else { Text(verbatim: day.day.formatted(.dateTime.weekday(.abbreviated).locale(locale))) }
                }
                .font(DS.font(.xs, weight: .semibold))
                Text(verbatim: day.day.formatted(.dateTime.day().locale(locale))).font(DS.font(.lg, weight: .bold))
                Circle().fill(day.airings.isEmpty ? Color.clear : (selected ? DS.onPrimary : DS.text)).frame(width: DS.Space.s1, height: DS.Space.s1)
            }
            .frame(minWidth: DS.Size.touchTarget).padding(.vertical, DS.Space.s2).padding(.horizontal, DS.Space.s1)
            .foregroundStyle(selected ? DS.onPrimary : (day.airings.isEmpty ? DS.textMuted : DS.text))
            .background(selected ? DS.primary : DS.fill, in: RoundedRectangle(cornerRadius: DS.Radius.md))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: day.day.formatted(.dateTime.weekday(.wide).day().month().locale(locale))))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Un estreno en renglón: la imagen ancha de la serie y, al lado, el nombre, cuándo y dónde, y el episodio.
struct AiringRow: View {
    let airing: Airing
    @Environment(\.locale) private var locale

    var body: some View {
        NavigationLink(value: airing.series.route) {
            HStack(alignment: .center, spacing: DS.Space.s3) {
                ZStack(alignment: .topLeading) {
                    PosterView(url: airing.series.wide, title: airing.series.title, aspect: DS.Poster.stillAspect)
                    if Calendar.current.isDateInToday(airing.day) { DSBadge(text: "Sale hoy").padding(DS.Space.s1) }
                }
                .frame(width: DS.Poster.episodeThumbWidth)
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    Text(verbatim: airing.series.title).font(DS.font(.md, weight: .semibold)).foregroundStyle(DS.text).lineLimit(2)
                    when.font(DS.font(.sm)).foregroundStyle(DS.text).lineLimit(1)
                    Text(verbatim: [airing.episodeLabel, airing.count > 1 ? nil : airing.episodeTitle].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(DS.font(.xs)).foregroundStyle(DS.textMuted).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    private var when: Text {
        airing.network.isEmpty ? airingTime(airing, locale: locale) : airingTime(airing, locale: locale) + Text(verbatim: " · \(airing.network)")
    }
}

/// Un estreno en el estante «Próximos estrenos»: la imagen ancha, el nombre y cuándo («Hoy · T3 E4»; la hora, en el calendario completo).
struct AiringCard: View {
    let airing: Airing
    @Environment(\.locale) private var locale

    var body: some View {
        NavigationLink(value: airing.series.route) {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                PosterView(url: airing.series.wide, title: airing.series.title, aspect: DS.Poster.stillAspect)
                Text(verbatim: airing.series.title).font(DS.font(.xs, weight: .semibold)).foregroundStyle(DS.text).lineLimit(1)
                (dayName(airing.day, locale: locale) + Text(verbatim: " · \(airing.episodeLabel)"))
                    .font(DS.font(.xs)).foregroundStyle(DS.textMuted).lineLimit(1)
            }
            .frame(width: DS.Poster.episodeThumbWidth * 1.4)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}
