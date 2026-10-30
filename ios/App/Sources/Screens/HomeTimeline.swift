import SwiftUI
import OrbitalCore

/// «Lo nuevo de lo tuyo» (Inicio, docs/producto/inicio-benchmark/): lo que ya salió de tus series en los últimos días y lo
/// que viene, en una sola línea de tiempo con la marca HOY entre los dos. Lo que ya salió va con su punto verde (ya se puede
/// ver); lo que viene, más apagado y con cuánto falta. Abre en HOY (lo de antes a la izquierda). El calendario del mes
/// completo, en el botón del encabezado.
struct ReleaseTimeline: View {
    let airings: [Airing]
    let onOpen: (TitleRoute) -> Void
    let onCalendar: () -> Void
    @Environment(AppEnvironment.self) private var env

    private enum Moment { case out, today, soon }

    var body: some View {
        let start = Calendar.current.startOfDay(for: Date())
        let firstSoon = airings.firstIndex { $0.day > start }
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            HStack(alignment: .sectionTitle) {
                DSSectionHead(title: Text("Lo nuevo de lo tuyo"), source: .trakt, eyebrow: Text("Ya salió y lo que viene"))
                Spacer(minLength: DS.Space.s2)
                Button(action: onCalendar) {
                    DSCapsuleLabel(title: Text(verbatim: Date().formatted(Date.FormatStyle(locale: env.uiLocale).month(.wide)).capitalized(with: env.uiLocale)), symbol: "calendar")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Calendario del mes"))
                .accessibilityIdentifier("release-calendar")
            }
            .padding(.horizontal, DS.Space.gutter)
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: DS.Space.s3) {
                        ForEach(Array(airings.enumerated()), id: \.element.id) { i, a in
                            if i == firstSoon { todayMark.id(Self.today) }
                            card(a, moment: a.day < start ? .out : a.day == start ? .today : .soon, start: start)
                        }
                        if firstSoon == nil { todayMark.id(Self.today) }
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.horizontal, DS.Space.gutter, for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
                .onAppear { proxy.scrollTo(Self.today, anchor: UnitPoint(x: DS.HomeTimeline.todayAnchor, y: 0.5)) }
            }
        }
    }

    private static let today = "hoy"

    /// La marca de hoy: una línea delgada con «HOY» arriba.
    private var todayMark: some View {
        VStack(spacing: DS.Space.s1) {
            Text("HOY").recipe(.caption, color: DS.onPrimary).fontWeight(.heavy)
                .padding(.horizontal, DS.Space.s2).padding(.vertical, DS.HomeTimeline.markPad)
                .background(DS.success, in: Capsule())
            Capsule().fill(DS.success).frame(width: DS.HomeTimeline.markLine)
                .frame(maxHeight: .infinity)
        }
        .frame(height: DS.HomeTimeline.width / DS.Poster.aspect + DS.HomeTimeline.labelRow)
        .accessibilityHidden(true)
    }

    private func card(_ a: Airing, moment: Moment, start: Date) -> some View {
        let days = Calendar.current.dateComponents([.day], from: start, to: a.day).day ?? 0
        let episode = a.episodeLabel(env.services.episodeLabel)
        return Button { onOpen(a.series.route) } label: {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                HStack(spacing: DS.Space.s1) {
                    Circle().fill(moment == .soon ? DS.ink500 : DS.success).frame(width: DS.HomeTimeline.dot, height: DS.HomeTimeline.dot)
                    when(a.day, moment: moment).recipe(.caption, color: moment == .soon ? DS.textMuted : DS.text).fontWeight(.bold).lineLimit(1)
                }
                .frame(height: DS.HomeTimeline.labelRow, alignment: .leading)
                PosterView(url: a.series.poster, title: a.series.title)
                    .overlay(alignment: .topLeading) {
                        if moment == .today {
                            Text("Nuevo").recipe(.caption, color: DS.onPrimary).fontWeight(.heavy)
                                .padding(.horizontal, DS.Space.s2).padding(.vertical, DS.HomeTimeline.markPad)
                                .background(DS.success, in: Capsule()).padding(DS.Space.s2)
                        }
                    }
                    .overlay(alignment: .bottomLeading) {
                        if moment == .soon, days >= 2 {
                            Text("en \(days) días").recipe(.caption, color: DS.onArtSecondary).fontWeight(.semibold)
                                .padding(DS.Space.s2).onArt()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(LinearGradient(colors: [.clear, DS.scrimStrong], startPoint: .top, endPoint: .bottom))
                        }
                    }
                    .opacity(moment == .soon ? DS.HomeTimeline.soonOpacity : 1)
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: a.series.title).recipe(.footnote).fontWeight(.semibold).lineLimit(1)
                    Text(verbatim: episode).recipe(.caption, color: DS.textMuted).lineLimit(1)
                }
            }
            .frame(width: DS.HomeTimeline.width)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    /// «Ayer», «Hoy», «Mañana» o el día de la semana.
    private func when(_ day: Date, moment: Moment) -> Text {
        Calendar.current.isDateInYesterday(day) ? Text("Ayer") : dayName(day, locale: env.uiLocale)
    }
}
