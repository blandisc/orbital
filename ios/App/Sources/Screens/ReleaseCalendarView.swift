import SwiftUI
import OrbitalCore
import OrbitalModels

/// Sale hoy › el mes: cada día con el color de lo que sale de las series que sigues (dos el mismo día: la casilla partida).
/// Tocar un día enseña abajo qué sale; tocar una serie abre su ficha.
struct ReleaseCalendarView: View {
    @State private var observer = ModelObserver(ReleaseCalendarModel(AppEnvironment.shared.services))
    @Environment(AppEnvironment.self) private var env
    let open: (TitleRoute) -> Void

    var body: some View {
        let model = observer.model
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                header(model)
                weekdays
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.s1), count: 7), spacing: DS.Space.s1) {
                    ForEach(Array(model.grid.enumerated()), id: \.offset) { _, day in
                        if let day { cell(day, model) } else { Color.clear.frame(height: DS.ReleaseDays.cell) }
                    }
                }
                .overlay { if model.loading && model.days.isEmpty { ProgressView() } }
                dayList(model)
            }
            .dsSheetContent()
        }
        .scrollContentBackground(.hidden).background(Backdrop())
        .task { await model.load() }
        .sensoryFeedback(.selection, trigger: model.selected)
    }

    private func header(_ model: ReleaseCalendarModel) -> some View {
        HStack(alignment: .sectionTitle) {
            DSSectionHead(title: Text(verbatim: sentence(model.month.formatted(Date.FormatStyle(locale: env.uiLocale).month(.wide).year()))),
                          eyebrow: Text("De las series que sigues"))
            Spacer(minLength: DS.Space.s2)
            HStack(spacing: DS.Space.s2) {
                DSIconButton(symbol: "chevron.backward", label: "Mes anterior") { Task { await model.move(-1) } }
                DSIconButton(symbol: "chevron.forward", label: "Mes siguiente") { Task { await model.move(1) } }
            }
            .alignmentGuide(.sectionTitle) { $0[VerticalAlignment.center] }
        }
    }

    /// L M M J V S D (o como empiece la semana en tu región).
    private var weekdays: some View {
        var cal = Calendar.current
        cal.locale = env.uiLocale
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        let first = cal.firstWeekday - 1
        let ordered = Array(symbols[first...] + symbols[..<first])
        return HStack(spacing: DS.Space.s1) {
            ForEach(Array(ordered.enumerated()), id: \.offset) { _, s in
                Text(verbatim: s).recipe(.caption, color: DS.textFaint).fontWeight(.bold).frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    private func cell(_ day: Date, _ model: ReleaseCalendarModel) -> some View {
        let airings = model.airings(on: day)
        let number = Calendar.current.component(.day, from: day)
        return Button { model.selected = day } label: {
            CalendarDayCell(number: number, art: airings.map(\.series.poster), isToday: day == model.today,
                            isSelected: day == model.selected, isPast: day < model.today)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: day.formatted(Date.FormatStyle(locale: env.uiLocale).day().month(.wide))))
        .accessibilityValue(airings.isEmpty ? Text("Nada sale") : Text(verbatim: airings.map(\.series.title).joined(separator: ", ")))
        .accessibilityAddTraits(day == model.selected ? .isSelected : [])
    }

    /// Solo la primera letra en mayúscula («Octubre de 2026», no «Octubre De 2026»).
    private func sentence(_ text: String) -> String { text.prefix(1).uppercased(with: env.uiLocale) + text.dropFirst() }

    /// Lo que sale el día elegido.
    @ViewBuilder private func dayList(_ model: ReleaseCalendarModel) -> some View {
        let airings = model.airings(on: model.selected)
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            Text(verbatim: sentence(model.selected.formatted(Date.FormatStyle(locale: env.uiLocale).weekday(.wide).day().month(.wide))))
                .recipe(.cardTitle)
            if airings.isEmpty && !model.loading { Text("Ese día no sale nada de lo que sigues.").recipe(.footnote) }
            ForEach(airings) { a in
                Button { open(a.series.route) } label: {
                    HStack(spacing: DS.Space.s3) {
                        PosterView(url: a.series.poster, title: a.series.title).frame(width: DS.Size.thumbSmall)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(verbatim: a.series.title).recipe(.cardTitle).lineLimit(1)
                            Text(verbatim: a.episodeLabel(env.services.episodeLabel)).recipe(.footnote).lineLimit(1)
                        }
                        Spacer(minLength: DS.Space.s2)
                        Text(verbatim: a.aired.formatted(Date.FormatStyle(locale: env.uiLocale).hour().minute())).recipe(.data, color: DS.textMuted)
                    }
                    .padding(DS.Space.s2)
                    .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .animation(DS.Motion.base(false), value: model.selected)
    }
}
