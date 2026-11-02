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
    /// Los géneros del periodo ya en el idioma de la app (los pone quien la usa).
    var genres: [String] = []
    /// El periodo que cuenta: el primero con algo (si la semana va vacía, el mes; si no, el año…).
    var period: WatchingStats.Period = .week
    /// Lo último que viste, para cuando no hay nada en ningún periodo cargado.
    var lastTitle: String?
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

    /// «12 h este mes · sobre todo drama»: del primer periodo con algo (nunca vacía: el domingo la semana empieza en cero).
    /// Sin nada contado, lo último que viste; mientras carga, «Lo que viste».
    private var detail: Text {
        guard let s = stats else { return Text("Lo que viste") }
        if s.isEmpty { return lastTitle.map { Text("Lo último: \($0)") } ?? Text("Aún no hay nada") }
        let h = s.minutes / 60, m = s.minutes % 60
        let amount = h == 0 ? Text("\(m) min") : Text("\(h) h")
        let time = Text("\(amount) \(WatchingCard.phrase(period))")
        guard let genre = genres.first else { return time }
        return Text("\(time) · sobre todo \(genre.lowercased())")
    }

    static func phrase(_ p: WatchingStats.Period) -> Text {
        switch p { case .week: Text("esta semana"); case .month: Text("este mes"); case .year: Text("este año"); case .all: Text("desde siempre") }
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
    /// Las barras crecen desde abajo, una tras otra, cuando llegan sus números (al abrir o al cambiar de periodo).
    @State private var grown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let top = max(values.max() ?? 0, 1)
        HStack(alignment: .bottom, spacing: DS.Space.s1) {
            ForEach(values.indices, id: \.self) { i in
                VStack(spacing: DS.Space.s1) {
                    GeometryReader { geo in
                        VStack { Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: DS.Radius.xs, style: .continuous).fill((highlighted.map { $0 == i } ?? (values[i] == top)) && values[i] > 0 ? DS.brandMoon : DS.fillStrong)
                                .frame(height: max(DS.Watching.barMin, geo.size.height * CGFloat(values[i]) / CGFloat(top) * (grown ? 1 : 0)))
                                .animation(DS.Motion.enter(reduceMotion)?.delay(Double(i) * DS.Watching.barStagger), value: grown)
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
        .onChange(of: values, initial: true) { _, _ in
            grown = false
            Task { @MainActor in grown = true }   // en el siguiente cuadro: así crecen desde abajo y no aparecen ya hechas
        }
        .accessibilityElement(children: onTap == nil ? .ignore : .contain)
        .accessibilityLabel(Text("Minutos por periodo"))
    }
}

/// «Día por día» (Fernando, 31 oct 2026, opción B): solo el mapa de calor como GitHub, en grande (una columna por semana,
/// de lunes a domingo, del azul del logo según cuánto viste). Se desliza de lado hacia atrás en el tiempo y abre en lo de
/// hoy; arriba, la letra de cada mes (y el año en enero). Tocar un día abre debajo lo que viste; tocarlo otra vez lo cierra.
struct WatchingZoomMap: View {
    let plays: [TraktPlay]
    let locale: Locale
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
            map(minutes)
            if let day {
                // Se asoma desde debajo del mapa (apenas baja y crece un poco, fundiéndose), sin brincar desde arriba; otro
                // día se funde sobre el anterior (Fernando, 31 oct 2026).
                dayDetail(day, byDay)
                    .id(day)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: DS.Watching.dayFrom, anchor: .top))
                                                .combined(with: .offset(y: -DS.Space.s2)),
                                            removal: .opacity))
            }
        }
        .animation(DS.Motion.smooth(reduceMotion), value: day)
        .sensoryFeedback(.selection, trigger: day)
        .onAppear {
            #if DEBUG
            if Demo.isOn, Demo.zoom == "day", let last = plays.map(\.at).max() { day = calendar.startOfDay(for: last) }
            #endif
        }
    }

    /// Desde el lunes de la semana de lo primero que viste (al menos un año) hasta esta semana.
    private func map(_ minutes: [Date: Int]) -> some View {
        let today = calendar.startOfDay(for: Date())
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let earliest = min(minutes.keys.min() ?? today, calendar.date(byAdding: .weekOfYear, value: -(DS.Watching.yearWeeks - 1), to: thisWeek) ?? today)
        let firstWeek = calendar.dateInterval(of: .weekOfYear, for: earliest)?.start ?? earliest
        let weeks = (calendar.dateComponents([.weekOfYear], from: firstWeek, to: thisWeek).weekOfYear ?? 0) + 1
        let most = max(minutes.values.max() ?? 0, 1)
        let pitch = DS.Watching.heatCell + DS.Watching.heatGap
        return ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: DS.Watching.heatGap) {
                ForEach(0..<weeks, id: \.self) { w in
                    let monday = calendar.date(byAdding: .weekOfYear, value: w, to: firstWeek) ?? firstWeek
                    VStack(spacing: DS.Watching.heatGap) {
                        // La letra del mes en la semana en que empieza (y el año en enero).
                        Text(verbatim: label(monday)).font(DS.TextRecipe.caption.font).foregroundStyle(DS.textMuted)
                            .lineLimit(1).fixedSize().frame(width: DS.Watching.heatCell, height: DS.Watching.yearLabel, alignment: .leading)
                        ForEach(0..<7, id: \.self) { d in
                            let date = calendar.date(byAdding: .day, value: d, to: monday) ?? monday
                            let inside = date <= today
                            let chosen = day.map { calendar.isDate($0, inSameDayAs: date) } ?? false
                            RoundedRectangle(cornerRadius: DS.Radius.xs, style: .continuous)
                                .fill(inside ? fill(minutes[date] ?? 0, most) : .clear)
                                .dsSelectionRing(chosen, radius: DS.Radius.xs)
                                .frame(width: DS.Watching.heatCell, height: DS.Watching.heatCell)
                                .contentShape(Rectangle())
                                .onTapGesture { if inside { day = chosen ? nil : date } }
                                .accessibilityHidden(!inside || (minutes[date] ?? 0) == 0)
                                .accessibilityLabel(Text(date, format: .dateTime.weekday(.wide).day().month(.wide)))
                                .accessibilityValue(Text("\((minutes[date] ?? 0) / 60) h"))
                                .accessibilityAddTraits(.isButton)
                        }
                    }
                    .frame(width: DS.Watching.heatCell)
                }
            }
        }
        .defaultScrollAnchor(.trailing)   // abre en lo de hoy
        .frame(height: DS.Watching.yearLabel + 8 * pitch)
        .accessibilityIdentifier("watching-heatmap")
    }

    /// «O» al empezar octubre; «2026» en la semana de enero.
    private func label(_ monday: Date) -> String {
        guard let sunday = calendar.date(byAdding: .day, value: 6, to: monday),
              let first = calendar.dateInterval(of: .month, for: sunday)?.start, first >= monday else { return "" }
        if calendar.component(.month, from: first) == 1 { return String(calendar.component(.year, from: first)) }
        return String(first.formatted(.dateTime.month(.narrow).locale(locale)))
    }

    /// El día: cada título una vez, con sus episodios.
    @ViewBuilder private func dayDetail(_ day: Date, _ byDay: [Date: [TraktPlay]]) -> some View {
        let plays = byDay[calendar.startOfDay(for: day)] ?? []
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            HStack {
                Text(verbatim: YearView.dayTitle(day, locale)).recipe(.cardTitle)
                Spacer()
                DSIconButton(symbol: "xmark", label: "Cerrar el día", size: .regular) { self.day = nil }
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
        .dsCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("watching-day")
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
    /// La dona se arma al llegar (gira y crece desde el centro), al abrir y al cambiar de periodo.
    @State private var built = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                    .opacity(current == nil || current?.id == s.id ? 1 : DS.Opacity.faint)
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
                            // En un renglón: el % más chico, pegado a la cifra, y si no cabe se encoge (con «38%» el % caía abajo).
                            Text("\(Text(verbatim: "\(current.count * 100 / total)"))\(Text(verbatim: "%").font(DS.TextRecipe.cardTitle.font))")
                                .font(DS.TextRecipe.stat.font).foregroundStyle(current.color)
                                .monospacedDigit().lineLimit(1).minimumScaleFactor(DS.Size.statScale).contentTransition(.numericText())
                            current.label.recipe(.caption, color: DS.textMuted).lineLimit(1).minimumScaleFactor(DS.Size.statScale)
                        }
                        .frame(width: frame.width * DS.Watching.donutHole * DS.Watching.donutLabel)
                        .position(x: frame.midX, y: frame.midY)
                    }
                }
            }
            .frame(width: DS.Watching.donut, height: DS.Watching.donut)
            .rotationEffect(.degrees(built || reduceMotion ? 0 : DS.Watching.donutTurn))
            .scaleEffect(built || reduceMotion ? 1 : DS.Watching.donutStart)
            .opacity(built ? 1 : 0)
            .onChange(of: genres.map(\.name), initial: true) { _, _ in
                built = false
                Task { @MainActor in withAnimation(DS.Motion.enter(reduceMotion) ?? DS.Motion.fade) { built = true } }
            }
            .sensoryFeedback(.selection, trigger: picked)
            .animation(DS.Motion.fade, value: picked)
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
