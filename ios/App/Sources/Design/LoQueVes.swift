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
    /// nil: solo el renglón (dentro de un `NavigationLink`, que recibe el toque; ver `CollectionsShowcase`).
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
    /// La barra elegida (en «Cómo calificas»): resaltada; nil, la más alta.
    var highlighted: Int? = nil
    /// Tocar una barra (en «Cómo calificas»: abre lo que calificaste con ese número); nil: solo se ve.
    var onTap: ((Int) -> Void)?

    var body: some View {
        let top = max(values.max() ?? 0, 1)
        HStack(alignment: .bottom, spacing: DS.Space.s1) {
            ForEach(values.indices, id: \.self) { i in
                VStack(spacing: DS.Space.s1) {
                    GeometryReader { geo in
                        VStack { Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: DS.Radius.xs).fill((highlighted.map { $0 == i } ?? (values[i] == top)) && values[i] > 0 ? DS.brandMoon : DS.fillStrong)
                                .frame(height: max(DS.Watching.barMin, geo.size.height * CGFloat(values[i]) / CGFloat(top)))
                        }
                    }
                    Text(verbatim: labels.indices.contains(i) ? labels[i] : "").font(DS.TextRecipe.caption.font).foregroundStyle(DS.textMuted).lineLimit(1)
                        .minimumScaleFactor(DS.Size.statScale)
                }
                .contentShape(Rectangle())
                .onTapGesture { if values[i] > 0 { onTap?(i) } }
            }
        }
        .frame(height: DS.Watching.barsHeight)
        .accessibilityElement(children: onTap == nil ? .ignore : .contain)
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

/// «Día por día» (Fernando, 31 oct 2026, decisión 3A): arriba siempre el año como en GitHub (una columna por semana, del
/// azul del logo según cuánto viste); tocarlo acerca ese mes, que se abre debajo como calendario; tocar un día abre debajo lo
/// que viste, sin esconder lo de arriba. Las flechas cambian de año. «Tu año» vive aquí adentro.
struct WatchingZoomMap: View {
    let plays: [TraktPlay]
    /// Al abrir: el mes de hoy abierto (semana, mes) o solo el año (año, siempre).
    let opensMonth: Bool
    let locale: Locale
    @State private var year = Calendar.current.component(.year, from: Date())
    @State private var month: Date?
    @State private var day: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let calendar: Calendar = {
        var c = Calendar.current
        c.firstWeekday = 2
        return c
    }()

    var body: some View {
        let byDay = Dictionary(grouping: plays) { calendar.startOfDay(for: $0.at) }
        let minutes = byDay.mapValues { $0.reduce(0) { $0 + $1.minutes } }
        VStack(alignment: .leading, spacing: DS.Layout.titleToContent) {
            header(byDay)
            yearMap(minutes)
            if let month {
                monthCalendar(month, minutes)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if let day {
                dayDetail(day, byDay)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(DS.Motion.base(reduceMotion), value: month)
        .animation(DS.Motion.base(reduceMotion), value: day)
        .sensoryFeedback(.selection, trigger: month)
        .sensoryFeedback(.selection, trigger: day)
        .onAppear {
            year = calendar.component(.year, from: Date())
            month = opensMonth ? calendar.dateInterval(of: .month, for: Date())?.start : nil
            day = nil
            #if DEBUG
            if Demo.isOn, Demo.zoom == "year" { month = nil }
            if Demo.isOn, Demo.zoom == "day", let last = plays.map(\.at).max() {
                day = calendar.startOfDay(for: last); month = calendar.dateInterval(of: .month, for: last)?.start
            }
            #endif
        }
        .onChange(of: opensMonth) { _, opens in month = opens ? calendar.dateInterval(of: .month, for: Date())?.start : nil; day = nil }
    }

    /// El año con sus flechas y, si hay un mes abierto, su nombre con una ✕ para cerrarlo.
    private func header(_ byDay: [Date: [TraktPlay]]) -> some View {
        let now = calendar.component(.year, from: Date())
        let first = byDay.keys.map { calendar.component(.year, from: $0) }.min() ?? now
        return HStack(spacing: DS.Space.s2) {
            Text(verbatim: "\(year)").font(DS.TextRecipe.cardTitle.font).foregroundStyle(DS.text).monospacedDigit()
            if let month {
                Button { self.month = nil; day = nil } label: {
                    HStack(spacing: DS.Space.s1) {
                        Text(verbatim: monthName(month))
                        Image(systemName: "xmark").font(DS.TextRecipe.caption.font.weight(.bold))
                    }
                    .font(DS.TextRecipe.footnote.font.weight(.semibold)).foregroundStyle(DS.backdropDeep)
                    .padding(.horizontal, DS.Space.s3).frame(minHeight: DS.Size.touchTarget * DS.Watching.chipHeight)
                    .background(DS.orbitalBlue, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Cerrar \(monthName(month))"))
            }
            Spacer(minLength: DS.Space.s2)
            Button { year -= 1; month = nil; day = nil } label: { Image(systemName: "chevron.left") }
                .accessibilityLabel(Text("Año anterior")).disabled(year <= first)
            Button { year += 1; month = nil; day = nil } label: { Image(systemName: "chevron.right") }
                .accessibilityLabel(Text("Año siguiente")).disabled(year >= now)
        }
        .buttonStyle(.glass).buttonBorderShape(.circle)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("watching-crumbs")
    }

    /// El año como GitHub: 53 columnas (semanas) de lunes a domingo, las letras de los meses arriba; tocar acerca ese mes.
    private func yearMap(_ minutes: [Date: Int]) -> some View {
        let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? Date()
        let firstMonday = calendar.dateInterval(of: .weekOfYear, for: start)?.start ?? start
        let weeks = DS.Watching.yearWeeks
        let inYear = minutes.filter { calendar.component(.year, from: $0.key) == year }
        let most = max(inYear.values.max() ?? 0, 1)
        let today = calendar.startOfDay(for: Date())
        return GeometryReader { geo in
            let pitch = geo.size.width / CGFloat(weeks)
            let cell = max(1, pitch - DS.Watching.yearGap)
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                // Las letras de los meses, sobre la semana en que empiezan.
                ZStack(alignment: .topLeading) {
                    ForEach(1...12, id: \.self) { m in
                        if let first = calendar.date(from: DateComponents(year: year, month: m, day: 1)) {
                            let w = (calendar.dateComponents([.day], from: firstMonday, to: first).day ?? 0) / 7
                            Text(verbatim: String(first.formatted(.dateTime.month(.narrow).locale(locale))))
                                .font(DS.TextRecipe.caption.font)
                                .foregroundStyle(month.map { calendar.isDate($0, equalTo: first, toGranularity: .month) } == true ? DS.text : DS.textMuted)
                                .offset(x: CGFloat(w) * pitch)
                        }
                    }
                }
                .frame(height: DS.Watching.yearLabel, alignment: .topLeading)
                HStack(alignment: .top, spacing: pitch - cell) {
                    ForEach(0..<weeks, id: \.self) { w in
                        VStack(spacing: pitch - cell) {
                            ForEach(0..<7, id: \.self) { d in
                                let date = calendar.date(byAdding: .day, value: w * 7 + d, to: firstMonday) ?? firstMonday
                                let inside = calendar.component(.year, from: date) == year && date <= today
                                let chosen = month.map { calendar.isDate($0, equalTo: date, toGranularity: .month) } ?? false
                                RoundedRectangle(cornerRadius: DS.YearMap.radius)
                                    .fill(inside ? fill(minutes[date] ?? 0, most) : .clear)
                                    .opacity(month == nil || chosen ? 1 : DS.Watching.otherMonths)
                                    .frame(width: cell, height: cell)
                            }
                        }
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { point in
                    let w = min(weeks - 1, max(0, Int(point.x / pitch))), d = min(6, max(0, Int(point.y / pitch)))
                    guard let date = calendar.date(byAdding: .day, value: w * 7 + d, to: firstMonday),
                          calendar.component(.year, from: date) == year, date <= today else { return }
                    month = calendar.dateInterval(of: .month, for: date)?.start
                    day = nil
                }
            }
        }
        .frame(height: DS.Watching.yearLabel + DS.Space.s1 + 7 * (DS.Watching.yearCell + DS.Watching.yearGap))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(inYear.count) días con algo visto en \(String(year))"))
        .accessibilityHint(Text("Toca para abrir un mes"))
        .accessibilityAddTraits(.isButton)
    }

    /// El mes abierto: su calendario; tocar un día abre lo que viste debajo.
    private func monthCalendar(_ month: Date, _ minutes: [Date: Int]) -> some View {
        let interval = calendar.dateInterval(of: .month, for: month) ?? DateInterval(start: month, duration: 0)
        let end = min(calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end, Date())
        return WatchingDayGrid(start: interval.start, end: end, minutes: minutes, onDay: { d in day = day == d ? nil : d }, calendar: calendar)
    }

    /// El día: cada título una vez, con sus episodios.
    @ViewBuilder private func dayDetail(_ day: Date, _ byDay: [Date: [TraktPlay]]) -> some View {
        let plays = byDay[calendar.startOfDay(for: day)] ?? []
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            HStack {
                Text(verbatim: YearView.dayTitle(day, locale)).recipe(.cardTitle)
                Spacer()
                Button { self.day = nil } label: { Image(systemName: "xmark") }
                    .buttonStyle(.glass).buttonBorderShape(.circle)
                    .accessibilityLabel(Text("Cerrar el día"))
            }
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
        .padding(DS.Space.s3)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("watching-day")
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

/// Los géneros como una dona (Fernando, 31 oct 2026): cada uno de su color (los de las listas, `DS.Watching.genreColors`) y
/// al lado su nombre y su parte del total. En el centro, el que tocas (en la dona o en la lista); sin tocar, el principal.
/// Lo que no cabe en cinco va junto en «Otros».
struct WatchingGenres: View {
    let genres: [(name: String, count: Int)]
    let name: (String) -> String
    @State private var picked: String?
    @State private var angle: Int?

    private struct Slice: Identifiable { let id: String; let label: Text; let count: Int; let color: Color }

    var body: some View {
        let total = max(1, genres.reduce(0) { $0 + $1.count })
        let shown = genres.prefix(DS.Watching.genreColors.count)
        let rest = genres.dropFirst(shown.count).reduce(0) { $0 + $1.count }
        let slices = shown.enumerated().map { i, g in Slice(id: g.name, label: Text(verbatim: name(g.name)), count: g.count, color: DS.Watching.genreColors[i]) }
            + (rest > 0 ? [Slice(id: "_rest", label: Text("Otros"), count: rest, color: DS.fillStrong)] : [])
        let current = slices.first { $0.id == picked } ?? slices.first
        HStack(spacing: DS.Space.s5) {
            Chart(slices) { s in
                SectorMark(angle: .value("count", s.count), innerRadius: .ratio(DS.Watching.donutHole), angularInset: DS.Watching.donutGap)
                    .foregroundStyle(s.color).cornerRadius(DS.Radius.xs)
                    .opacity(current == nil || current?.id == s.id ? 1 : DS.Watching.genreDim)
            }
            .chartLegend(.hidden)
            .chartAngleSelection(value: $angle)
            .onChange(of: angle) { _, value in
                // El ángulo tocado → la rebanada (se suman las cuentas hasta pasarlo).
                guard let value else { return }
                var sum = 0
                picked = slices.first { sum += $0.count; return value < sum }?.id ?? picked
            }
            .chartBackground { proxy in
                GeometryReader { geo in
                    if let current, let plot = proxy.plotFrame {
                        let frame = geo[plot]
                        // Al centro exacto de la dona: el porcentaje pegado a su número y el nombre debajo.
                        VStack(spacing: 0) {
                            Text(verbatim: "\(current.count * 100 / total)%").font(DS.TextRecipe.title.font.weight(.heavy)).foregroundStyle(current.color)
                                .monospacedDigit().contentTransition(.numericText())
                            current.label.recipe(.caption, color: DS.textMuted).lineLimit(1).minimumScaleFactor(DS.Size.statScale)
                        }
                        .frame(width: frame.width * DS.Watching.donutHole * DS.Watching.donutLabel)
                        .position(x: frame.midX, y: frame.midY)
                    }
                }
            }
            .frame(width: DS.Watching.donut, height: DS.Watching.donut)
            .sensoryFeedback(.selection, trigger: picked)
            .animation(DS.Motion.tint(false), value: picked)
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                ForEach(slices) { s in
                    Button { picked = s.id } label: {
                        HStack(spacing: DS.Space.s2) {
                            Circle().fill(s.color).frame(width: DS.Watching.genreDot, height: DS.Watching.genreDot)
                            s.label.recipe(.footnote, color: current?.id == s.id ? DS.text : DS.textMuted).lineLimit(1)
                            Spacer(minLength: DS.Space.s1)
                            Text(verbatim: "\(s.count * 100 / total)%").recipe(.caption, color: DS.textMuted).monospacedDigit()
                        }
                        .frame(minHeight: DS.Watching.genreRow)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(current?.id == s.id ? .isSelected : [])
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// El carrusel de «Cómo calificas»: los pósters de lo que calificaste con el número elegido, de lo más reciente a lo más
/// viejo; tocar uno abre su ficha.
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
