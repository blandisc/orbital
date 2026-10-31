import SwiftUI
import Charts
import OrbitalCore

// Piezas de «Lo que ves» (docs/producto/muvy-busqueda-premios/prototipo-wrapped.html): la tarjeta de Para ti, un dato
// grande, las barras del periodo, el mapa día por día y los géneros. Los colores de película, serie y las dos son los del
// mapa de «Tu año» (`DS.YearMap`).

/// La puerta de «Lo que ves» arriba de Para ti (Fernando, 30 oct 2026, opción E2): el mismo renglón de «Tuyo» (`ListRow`):
/// lo que más viste esta semana en pila, «Lo que ves» y «4 h esta semana · sobre todo drama».
struct WatchingCard: View {
    /// nil: aún cargando.
    let stats: WatchingStats?
    /// «Lo que ves» en el idioma de la app (lo pone quien la usa: el del sistema no siempre es el de la app).
    let name: String
    /// Los géneros de la semana ya en el idioma de la app (los pone quien la usa).
    var genres: [String] = []
    /// nil: solo el renglón (dentro de un `NavigationLink`, que recibe el toque; ver `CollectionsCard`).
    var action: (() -> Void)?

    var body: some View {
        if let action { Button(action: action) { row }.buttonStyle(.plain).accessibilityIdentifier("watching-card") }
        else { row.accessibilityIdentifier("watching-card") }
    }

    private var row: some View {
        ListRow(name: name, detail: detail, posters: (stats?.top ?? []).prefix(DS.ParaTiB.matchFan).map(\.poster))
            .contentShape(Rectangle())
    }

    /// «4 h esta semana · sobre todo drama» (o «Aún nada esta semana»; mientras carga, «Esta semana»).
    private var detail: Text {
        guard let s = stats else { return Text("Esta semana") }
        if s.isEmpty { return Text("Aún nada esta semana") }
        let h = s.minutes / 60, m = s.minutes % 60
        let time = h == 0 ? Text("\(m) min esta semana") : Text("\(h) h esta semana")
        guard let genre = genres.first else { return time }
        return Text("\(time) · sobre todo \(genre.lowercased())")
    }
}

/// Las barras del periodo (días, semanas, meses o años), la más alta resaltada.
struct WatchingBars: View {
    let values: [Int]
    let labels: [String]

    var body: some View {
        let top = max(values.max() ?? 0, 1)
        HStack(alignment: .bottom, spacing: DS.Space.s1) {
            ForEach(values.indices, id: \.self) { i in
                VStack(spacing: DS.Space.s1) {
                    GeometryReader { geo in
                        VStack { Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: DS.Radius.xs).fill(values[i] == top && values[i] > 0 ? DS.brandMoon : DS.fillStrong)
                                .frame(height: max(DS.Watching.barMin, geo.size.height * CGFloat(values[i]) / CGFloat(top)))
                        }
                    }
                    Text(verbatim: labels.indices.contains(i) ? labels[i] : "").font(DS.TextRecipe.caption.font).foregroundStyle(DS.textMuted).lineLimit(1)
                        .minimumScaleFactor(DS.Size.statScale)
                }
            }
        }
        .frame(height: DS.Watching.barsHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Minutos por periodo"))
    }
}

/// «Día por día»: en una semana o un mes, un calendario de verdad (L M X J V S D arriba, el número de cada día) con un solo
/// color, azul (Fernando, 31 oct 2026), más intenso según cuánto viste ese día; en un año o siempre, el mapa de cuadritos
/// con el mismo azul.
struct WatchingDayGrid: View {
    let start: Date
    let end: Date
    let minutes: [Date: Int]
    /// Tocar un día (en el mapa de «Día por día» abre lo que viste ese día); nil: solo se ve.
    var onDay: ((Date) -> Void)?
    var calendar: Calendar = {
        var c = Calendar.current
        c.firstWeekday = 2   // la semana empieza en lunes, como en los calendarios en español
        return c
    }()

    var body: some View {
        let first = calendar.dateInterval(of: .weekOfYear, for: start)?.start ?? start
        let count = max(1, (calendar.dateComponents([.day], from: first, to: end).day ?? 0) + 1)
        let weeks = Int((Double(count) / 7).rounded(.up))
        let most = max(minutes.values.max() ?? 0, 1)
        if weeks <= 6 {
            VStack(spacing: DS.YearMap.gap) {
                HStack(spacing: DS.YearMap.gap) {
                    ForEach(0..<7, id: \.self) { d in
                        Text(verbatim: Self.letter(calendar.date(byAdding: .day, value: d, to: first) ?? first, calendar: calendar))
                            .recipe(.caption, color: DS.textMuted).frame(maxWidth: .infinity)
                    }
                }
                ForEach(0..<weeks, id: \.self) { w in
                    HStack(spacing: DS.YearMap.gap) {
                        ForEach(0..<7, id: \.self) { d in
                            let day = calendar.date(byAdding: .day, value: w * 7 + d, to: first) ?? first
                            let inside = !(day > end || day < calendar.startOfDay(for: start))
                            let watched = minutes[calendar.startOfDay(for: day)] ?? 0
                            ZStack {
                                RoundedRectangle(cornerRadius: DS.Radius.xs).fill(inside ? fill(watched, most) : .clear)
                                if inside {
                                    Text(verbatim: "\(calendar.component(.day, from: day))")
                                        .recipe(.caption, color: watched > 0 ? DS.paper : DS.textMuted).monospacedDigit()
                                }
                            }
                            .aspectRatio(1, contentMode: .fit)   // ds-exception: cuadros cuadrados (un día)
                            .contentShape(Rectangle())
                            .onTapGesture { if inside, let onDay { onDay(calendar.startOfDay(for: day)) } }
                            .accessibilityHidden(!inside || onDay == nil)
                            .accessibilityLabel(Text(day, format: .dateTime.day().month(.wide)))
                            .accessibilityAddTraits(.isButton)
                        }
                    }
                }
            }
            .accessibilityElement(children: onDay == nil ? .ignore : .contain)
            .accessibilityHidden(onDay == nil)
        } else {
            longGrid(first: first, weeks: weeks, most: most)
        }
    }

    private func longGrid(first: Date, weeks: Int, most: Int) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: DS.YearMap.gap) {
                ForEach(0..<weeks, id: \.self) { w in
                    VStack(spacing: DS.YearMap.gap) {
                        ForEach(0..<7, id: \.self) { d in
                            let day = calendar.date(byAdding: .day, value: w * 7 + d, to: first) ?? first
                            RoundedRectangle(cornerRadius: DS.YearMap.radius)
                                .fill(day > end || day < calendar.startOfDay(for: start) ? .clear : fill(minutes[calendar.startOfDay(for: day)] ?? 0, most))
                                .frame(width: DS.Watching.cell, height: DS.Watching.cell)
                        }
                    }
                }
            }
        }
        .defaultScrollAnchor(.trailing)
        .accessibilityHidden(true)
    }

    /// L M X J V S D (miércoles es X, como en los calendarios en español).
    static func letter(_ day: Date, calendar: Calendar) -> String {
        ["D", "L", "M", "X", "J", "V", "S"][calendar.component(.weekday, from: day) - 1]
    }

    /// Azul más intenso según los minutos de ese día; sin nada, el relleno de siempre.
    private func fill(_ watched: Int, _ most: Int) -> Color {
        guard watched > 0 else { return DS.fill }
        return DS.orbitalBlue.opacity(DS.Watching.dayFloor + (1 - DS.Watching.dayFloor) * Double(watched) / Double(most))
    }
}

/// «Día por día» con zoom (Fernando, 31 oct 2026, opción Z1): un solo mapa que va del año al mes y al día. Arriba, las
/// migas («2026 › Octubre › 15») para subir; en el año, los doce meses (más intensos según cuánto viste); en el mes, el
/// calendario; en el día, lo que viste ese día. «Tu año» vive aquí adentro.
struct WatchingZoomMap: View {
    enum Level: Equatable { case year, month, day }
    let plays: [TraktPlay]
    /// Dónde abre: el mes de hoy (semana, mes) o el año (año, siempre).
    let startLevel: Level
    let locale: Locale
    @State private var level: Level = .month
    @State private var focus = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let calendar: Calendar = {
        var c = Calendar.current
        c.firstWeekday = 2
        return c
    }()

    var body: some View {
        let byDay = Dictionary(grouping: plays) { calendar.startOfDay(for: $0.at) }
        let minutes = byDay.mapValues { $0.reduce(0) { $0 + $1.minutes } }
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            crumbs(byDay)
            Group {
                switch level {
                case .year: year(minutes)
                case .month: month(minutes)
                case .day: day(byDay)
                }
            }
            .id(level)
            .transition(.scale(scale: DS.Watching.zoomScale).combined(with: .opacity))
        }
        .animation(DS.Motion.base(reduceMotion), value: level)
        .animation(DS.Motion.base(reduceMotion), value: focus)
        .sensoryFeedback(.selection, trigger: level)
        .onAppear {
            level = startLevel; focus = Date()
            #if DEBUG
            if Demo.isOn, Demo.zoom == "year" { level = .year }
            if Demo.isOn, Demo.zoom == "day", let last = plays.map(\.at).max() { focus = calendar.startOfDay(for: last); level = .day }
            #endif
        }
        .onChange(of: startLevel) { _, new in level = new; focus = Date() }
    }

    /// «2026 › Octubre › 15»: lo de arriba se toca para subir; a la derecha, flechas para ir al año, mes o día de al lado.
    private func crumbs(_ byDay: [Date: [TraktPlay]]) -> some View {
        HStack(spacing: DS.Space.s1) {
            crumb(Text(verbatim: "\(calendar.component(.year, from: focus))"), current: level == .year) { level = .year }
            if level != .year {
                Image(systemName: "chevron.forward").font(DS.TextRecipe.caption.font).foregroundStyle(DS.textMuted).accessibilityHidden(true)
                crumb(Text(verbatim: monthName(focus)), current: level == .month) { level = .month }
            }
            if level == .day {
                Image(systemName: "chevron.forward").font(DS.TextRecipe.caption.font).foregroundStyle(DS.textMuted).accessibilityHidden(true)
                crumb(Text(verbatim: "\(calendar.component(.day, from: focus))"), current: true) {}
            }
            Spacer(minLength: DS.Space.s2)
            Button { step(-1, byDay) } label: { Image(systemName: "chevron.left") }
                .accessibilityLabel(Text("Anterior")).disabled(!canStep(-1, byDay))
            Button { step(1, byDay) } label: { Image(systemName: "chevron.right") }
                .accessibilityLabel(Text("Siguiente")).disabled(!canStep(1, byDay))
        }
        .buttonStyle(.glass).buttonBorderShape(.circle)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("watching-crumbs")
    }

    private func crumb(_ title: Text, current: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            title.font(DS.TextRecipe.cardTitle.font).foregroundStyle(current ? DS.text : DS.textMuted).lineLimit(1)
                .frame(minHeight: DS.Size.touchTarget)
        }
        .buttonStyle(.plain)
        .allowsHitTesting(!current)
        .accessibilityAddTraits(current ? .isSelected : [])
    }

    /// El año: los doce meses en cuadros, con sus horas.
    private func year(_ minutes: [Date: Int]) -> some View {
        let y = calendar.component(.year, from: focus)
        let months: [(Date, Int)] = (1...12).compactMap { m in
            guard let start = calendar.date(from: DateComponents(year: y, month: m, day: 1)),
                  let interval = calendar.dateInterval(of: .month, for: start) else { return nil }
            return (start, minutes.filter { interval.contains($0.key) }.values.reduce(0, +))
        }
        let most = max(months.map(\.1).max() ?? 0, 1)
        let now = Date()
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.YearMap.gap), count: DS.Watching.monthColumns), spacing: DS.YearMap.gap) {
            ForEach(months, id: \.0) { start, watched in
                let future = start > now
                Button { focus = start; level = .month } label: {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: start.formatted(.dateTime.month(.abbreviated).locale(locale)).capitalized(with: locale))
                            .recipe(.footnote, color: watched > 0 ? DS.paper : DS.textMuted).fontWeight(.semibold)
                        Spacer(minLength: 0)
                        if watched > 0 {
                            Text(verbatim: watched >= 60 ? "\(watched / 60) h" : "\(watched) min").recipe(.caption, color: DS.paper).monospacedDigit()
                        }
                    }
                    .padding(DS.Space.s2)
                    .frame(maxWidth: .infinity, minHeight: DS.Watching.monthTile, alignment: .leading)
                    .background(fill(watched, most), in: RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(future)
                .opacity(future ? DS.Watching.futureMonth : 1)
            }
        }
    }

    /// El mes: el calendario; tocar un día abre lo que viste.
    private func month(_ minutes: [Date: Int]) -> some View {
        let interval = calendar.dateInterval(of: .month, for: focus) ?? DateInterval(start: focus, duration: 0)
        let end = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
        return WatchingDayGrid(start: interval.start, end: end, minutes: minutes, onDay: { d in focus = d; level = .day }, calendar: calendar)
    }

    /// El día: cada título una vez, con sus episodios.
    @ViewBuilder private func day(_ byDay: [Date: [TraktPlay]]) -> some View {
        let plays = byDay[calendar.startOfDay(for: focus)] ?? []
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            Text(verbatim: YearView.dayTitle(focus, locale)).recipe(.footnote, color: DS.textMuted)
            if plays.isEmpty {
                Text("Ese día no viste nada.").recipe(.footnote)
            } else {
                ForEach(WatchingDay.groups(plays), id: \.imdb) { g in
                    TitleNavigationLink(route: TitleRoute(kind: g.kind, metaID: g.imdb, title: g.title, poster: String(format: ForYou.metahubPoster, g.imdb))) {
                        HStack(spacing: DS.Space.s3) {
                            PosterView(url: String(format: ForYou.metahubPoster, g.imdb), title: g.title).frame(width: DS.YearMap.dayPoster)
                            VStack(alignment: .leading, spacing: DS.Space.s1) {
                                Text(verbatim: g.title).recipe(.cardTitle).lineLimit(1)
                                Text(verbatim: g.detail).recipe(.footnote).lineLimit(2)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").foregroundStyle(DS.textMuted)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Las flechas: el año o el mes de al lado; en el día, el día anterior o siguiente con algo visto.
    private func step(_ by: Int, _ byDay: [Date: [TraktPlay]]) {
        switch level {
        case .year: focus = calendar.date(byAdding: .year, value: by, to: focus) ?? focus
        case .month: focus = calendar.date(byAdding: .month, value: by, to: focus) ?? focus
        case .day: if let next = nextDay(by, byDay) { focus = next }
        }
    }

    private func canStep(_ by: Int, _ byDay: [Date: [TraktPlay]]) -> Bool {
        let now = Date()
        switch level {
        case .year:
            let y = calendar.component(.year, from: focus) + by
            return y <= calendar.component(.year, from: now) && (by > 0 || byDay.keys.contains { calendar.component(.year, from: $0) <= y })
        case .month:
            guard let d = calendar.date(byAdding: .month, value: by, to: focus), let i = calendar.dateInterval(of: .month, for: d) else { return false }
            return i.start <= now && (by > 0 || byDay.keys.contains { $0 < i.end })
        case .day: return nextDay(by, byDay) != nil
        }
    }

    private func nextDay(_ by: Int, _ byDay: [Date: [TraktPlay]]) -> Date? {
        let today = calendar.startOfDay(for: focus)
        let days = byDay.keys.sorted()
        return by > 0 ? days.first { $0 > today } : days.last { $0 < today }
    }

    private func monthName(_ d: Date) -> String {
        let text = d.formatted(.dateTime.month(.wide).locale(locale))
        return text.prefix(1).uppercased(with: locale) + text.dropFirst()
    }

    private func fill(_ watched: Int, _ most: Int) -> Color {
        guard watched > 0 else { return DS.fill }
        return DS.orbitalBlue.opacity(DS.Watching.dayFloor + (1 - DS.Watching.dayFloor) * Double(watched) / Double(most))
    }
}

/// Lo que viste en un día, cada título una vez: «2 h 20 min» o «T1 E3 «Nombre», T1 E4» (lo usan «Tu año» y el mapa).
enum WatchingDay {
    static func groups(_ plays: [TraktPlay]) -> [(imdb: String, kind: String, title: String, detail: String)] {
        var order: [String] = [], byTitle: [String: [TraktPlay]] = [:]
        for p in plays { if byTitle[p.imdb] == nil { order.append(p.imdb) }; byTitle[p.imdb, default: []].append(p) }
        return order.compactMap { id in
            guard let list = byTitle[id], let first = list.first else { return nil }
            let detail: String
            if first.kind == "movie" {
                let m = first.minutes
                detail = m > 0 ? (m >= 60 ? "\(m / 60) h \(m % 60) min" : "\(m) min") : ""
            } else {
                detail = list.map { p in
                    guard let s = p.season, let e = p.episode else { return p.episodeTitle ?? "" }
                    return "T\(s) E\(e)" + (p.episodeTitle.map { " «\($0)»" } ?? "")
                }.joined(separator: ", ")
            }
            return (id, first.kind, first.title, detail)
        }
    }
}

/// Los géneros como una dona (Fernando, 31 oct 2026): cada uno de su color (los de las listas, `DS.Watching.genreColors`),
/// el principal en el centro y al lado su nombre y su parte del total. Lo que no cabe en cinco va junto en «Otros».
struct WatchingGenres: View {
    let genres: [(name: String, count: Int)]
    let name: (String) -> String

    private struct Slice: Identifiable { let id: String; let label: Text; let count: Int; let color: Color }

    var body: some View {
        let total = max(1, genres.reduce(0) { $0 + $1.count })
        let shown = genres.prefix(DS.Watching.genreColors.count)
        let rest = genres.dropFirst(shown.count).reduce(0) { $0 + $1.count }
        let slices = shown.enumerated().map { i, g in Slice(id: g.name, label: Text(verbatim: name(g.name)), count: g.count, color: DS.Watching.genreColors[i]) }
            + (rest > 0 ? [Slice(id: "_rest", label: Text("Otros"), count: rest, color: DS.fillStrong)] : [])
        HStack(spacing: DS.Space.s5) {
            Chart(slices) { s in
                SectorMark(angle: .value("count", s.count), innerRadius: .ratio(DS.Watching.donutHole), angularInset: DS.Watching.donutGap)
                    .foregroundStyle(s.color).cornerRadius(DS.Radius.xs)
            }
            .chartLegend(.hidden)
            .frame(width: DS.Watching.donut, height: DS.Watching.donut)
            .overlay {
                if let first = slices.first {
                    VStack(spacing: 0) {
                        Text(verbatim: "\(first.count * 100 / total) %").font(DS.TextRecipe.title.font.weight(.heavy)).foregroundStyle(first.color)
                            .monospacedDigit()
                        first.label.recipe(.caption, color: DS.textMuted).lineLimit(1).minimumScaleFactor(DS.Size.statScale)
                    }
                    .frame(width: DS.Watching.donut * DS.Watching.donutHole * DS.Watching.donutLabel)
                }
            }
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                ForEach(slices) { s in
                    HStack(spacing: DS.Space.s2) {
                        Circle().fill(s.color).frame(width: DS.Watching.genreDot, height: DS.Watching.genreDot)
                        s.label.recipe(.footnote).lineLimit(1)
                        Spacer(minLength: DS.Space.s1)
                        Text(verbatim: "\(s.count * 100 / total) %").recipe(.caption, color: DS.textMuted).monospacedDigit()
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// «Tus 5 estrellas» (Fernando, 31 oct 2026, opción R1): los pósters de lo que calificaste con 5, de lo más reciente a lo
/// más viejo; tocar uno abre su ficha.
struct WatchingFiveStars: View {
    struct Item: Identifiable { let id: String; let title: String; let kind: String; let poster: String }
    let items: [Item]
    let open: (Item) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Space.s2) {
                ForEach(items) { item in
                    Button { open(item) } label: {
                        PosterView(url: item.poster, title: item.title)
                            .frame(width: DS.Watching.starPoster)
                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(verbatim: item.title))
                }
            }
            .padding(.horizontal, DS.Space.gutter)
        }
        .padding(.horizontal, -DS.Space.gutter)
        .scrollClipDisabled()
    }
}
