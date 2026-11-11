import SwiftUI
import OrbitalCore
import OrbitalModels

/// «Lo nuevo de lo tuyo» (Inicio, docs/producto/inicio-benchmark/): lo que ya salió de tus series en los últimos días y lo
/// que viene, en una sola línea de tiempo con la marca HOY entre los dos (por hora: lo de hoy más tarde va después). Lo que ya
/// salió va con su punto turquesa (`DS.fresh`) (ya se puede ver; lo de hoy, «Nuevo»); lo que viene, más apagado y con cuánto falta. Abre en HOY (lo de antes a la izquierda). El calendario del mes
/// completo, en el botón del encabezado.
struct ReleaseTimeline: View {
    let airings: [Airing]
    let onOpen: (TitleRoute) -> Void
    let onCalendar: () -> Void
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // Cada minuto: lo que sale hoy a las 21:00 pasa a «Nuevo» a esa hora, y a medianoche «Hoy» se vuelve «Ayer».
        TimelineView(.everyMinute) { context in line(now: context.date) }
    }

    private func line(now: Date) -> some View {
        let nowIndex = HomeModel.nowIndex(in: airings, now: now)
        return VStack(alignment: .leading, spacing: DS.Space.s3) {
            // Con letra de accesibilidad el mes baja bajo el título (al lado no cabía y se salía de la pantalla).
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: DS.Space.s2))
                                                      : AnyLayout(HStackLayout(alignment: .sectionTitle))
            layout {
                DSSectionHead(title: Text("Lo nuevo de lo tuyo"), eyebrow: Text("Ya salió y lo que viene"))
                if !typeSize.isAccessibilitySize { Spacer(minLength: DS.Space.s2) }
                // El calendario es un ícono redondo, como el «+» de Canales (Fernando, 2 nov 2026, B3: sin la cápsula «Noviembre»;
                // el mes ya se ve al abrirlo).
                DSIconButton(symbol: "calendar", label: "Calendario del mes", size: .regular, action: onCalendar)
                    .alignmentGuide(.sectionTitle) { $0[VerticalAlignment.center] }
                    .accessibilityIdentifier("release-calendar")
            }
            .padding(.horizontal, DS.Space.gutter)
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: DS.Space.s3) {
                        ForEach(Array(airings.enumerated()), id: \.element.id) { i, a in
                            if i == nowIndex { todayMark.id(Self.today) }
                            card(a, moment: a.moment(now: now))
                        }
                        if nowIndex == airings.count { todayMark.id(Self.today) }
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.horizontal, DS.Space.gutter, for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
                .onAppear {
                    let anchor = UnitPoint(x: DS.HomeTimeline.todayAnchor, y: UnitPoint.center.y)
                    // La primera vez que se ve en esta sesión, la línea se desliza sola hasta HOY y la marca late una vez (te
                    // ubica: lo de antes a la izquierda); las siguientes ya abre ahí, sin repetir el paseo.
                    guard !Self.settled, !reduceMotion else { proxy.scrollTo(Self.today, anchor: anchor); return }
                    Self.settled = true
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(DS.HomeTimeline.settleDelay))
                        withAnimation(DS.Motion.smooth(reduceMotion)) { proxy.scrollTo(Self.today, anchor: anchor) }
                        try? await Task.sleep(for: .seconds(DesignTokens.Motion.slow))
                        pulse += 1
                    }
                }
            }
        }
    }

    private static let today = "hoy"
    /// Ya se deslizó hasta HOY en esta sesión.
    @MainActor private static var settled = false
    @State private var pulse = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// La marca de hoy: una línea delgada con «Hoy» arriba.
    private var todayMark: some View {
        VStack(spacing: DS.Space.s1) {
            DSBadge(text: "Hoy", tone: .fresh)
                .keyframeAnimator(initialValue: CGFloat(1), trigger: pulse) { badge, scale in badge.scaleEffect(scale) } keyframes: { _ in
                    SpringKeyframe(DS.HomeTimeline.pulseScale, duration: DesignTokens.Motion.base)
                    SpringKeyframe(1, duration: DesignTokens.Motion.slow)
                }
            Capsule().fill(LinearGradient(colors: [DS.fresh, .clear], startPoint: .top, endPoint: .bottom))
                .frame(width: DS.HomeTimeline.markLine)
                .frame(maxHeight: .infinity)
        }
        .frame(height: DS.HomeTimeline.width / DS.Poster.aspect + DS.HomeTimeline.labelRow)
        .accessibilityHidden(true)
    }

    private func card(_ a: Airing, moment: ReleaseMoment) -> some View {
        let soon = moment.isSoon
        let episode = a.episodeLabel(env.services.episodeLabel)
        return Button { onOpen(a.series.route) } label: {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                HStack(spacing: DS.Space.s1) {
                    Circle().fill(soon ? DS.ink500 : DS.fresh).frame(width: DS.HomeTimeline.dot, height: DS.HomeTimeline.dot)
                    when(a).recipe(.badge, color: soon ? DS.textMuted : DS.text).lineLimit(1)
                }
                .frame(height: DS.HomeTimeline.labelRow, alignment: .leading)
                PosterView(url: a.series.poster, title: a.series.title)
                    .overlay(alignment: .topLeading) {
                        if moment == .new { DSCornerRibbon(text: "Nuevo") }
                    }
                    .overlay(alignment: .bottomLeading) {
                        if case .soon(let days) = moment, days >= 2 {
                            Text("en \(days) días").recipe(.badge, color: DS.onArtSecondary)
                                .padding(DS.Space.s2).onArt()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(ArtVeil(at: 0))
                        }
                    }
                    .opacity(soon ? DS.Opacity.dimmed : 1)
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: a.series.title).recipe(.label).lineLimit(1)
                    Text(verbatim: episode).recipe(.caption, color: DS.textMuted).lineLimit(1)
                }
            }
            .frame(width: DS.HomeTimeline.width)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    /// «Ayer», «Mañana» o el día de la semana. Lo de hoy dice su hora («21:00»): «Hoy» ya lo dice la marca de la línea, y
    /// repetido en cada tarjeta sobraba (I13, revisión del 10 nov). Sin hora conocida (medianoche o de madrugada), nada.
    private func when(_ a: Airing) -> Text {
        let calendar = Calendar.current
        if calendar.isDateInToday(a.day) {
            let parts = calendar.dateComponents([.hour, .minute], from: a.aired)
            guard !a.atDawn, calendar.isDateInToday(a.aired), parts.hour != 0 || parts.minute != 0 else { return Text(verbatim: " ") }
            return Text(verbatim: Strings.date(a.aired, .time, language: env.services.appSettings.uiLanguage))
        }
        return calendar.isDateInYesterday(a.day) ? Text("Ayer") : dayName(a.day, locale: env.uiLocale)
    }
}

/// «Hoy», «Mañana» o el día de la semana («Jueves»).
func dayName(_ day: Date, locale: Locale, calendar: Calendar = .current) -> Text {
    if calendar.isDateInToday(day) { return Text("Hoy") }
    if calendar.isDateInTomorrow(day) { return Text("Mañana") }
    return Text(verbatim: day.formatted(.dateTime.weekday(.wide).locale(locale)).capitalized(with: locale))
}
